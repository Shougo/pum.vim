const s:priority_highlight_item = 2
const s:priority_highlight_column = 1
const s:priority_highlight_selected = 0
const s:priority_highlight_lead = 1
const s:priority_highlight_horizontal_separator = 1

" Opens a popup menu for completion/suggestions
"
" This function creates a floating/popup window displaying completion items.
" It handles positioning, sizing, highlighting, and platform-specific rendering
" for both Neovim and Vim.
"
" Args:
"   startcol: Column where completion starts
"   items: List of completion items
"   mode: Mode character ('i' = insert, 'c' = command-line, 't' = terminal)
"   insert: If true, automatically insert first item
"
" Returns:
"   Window ID of created popup, or -1 on error
function pum#popup#_open(startcol, items, mode, insert) abort
  " Validate mode parameter
  if a:mode !~# '[ict]'
    return -1
  endif

  " Reset autocmd groups
  augroup pum
    autocmd!
  augroup END
  augroup pum-temp
    autocmd!
  augroup END

  let options = pum#_options()
  let items = s:uniq_by_word_or_dup(a:items)

  " Calculate column widths and dimensions
  let [max_columns, total_width, non_abbr_length] =
        \ s:calculate_column_widths(items, options)

  let pum = pum#_get()
  let dimensions = s:calculate_dimensions(
        \ items, max_columns, total_width, non_abbr_length,
        \ options, a:mode, a:startcol, pum)

  " Get cursor/screen position
  if !has('nvim') && a:mode ==# 't'
    const cursor = '%'->bufnr()->term_getcursor()
    let spos = #{
          \   row: cursor[0],
          \   col: options.follow_cursor ? cursor[1] : a:startcol,
          \ }
  else
    let spos = screenpos(
          \   0, '.'->line(),
          \   options.follow_cursor ? getcurpos()[2] : a:startcol,
          \ )
  endif

  " Calculate position and direction
  let [pos, direction, height, reversed, items, lines] =
        \ s:calculate_position(spos, dimensions, options, a:mode, items,
        \                      a:startcol)

  " Apply command-line specific adjustments
  if a:mode ==# 'c'
    let [pos, height, direction] =
          \ s:adjust_cmdline_position(pos, height, direction, options,
          \                           dimensions, dimensions.lines)
  endif

  " Adjust position for borders
  if direction ==# 'above'
    let pos[0] -= dimensions.border_top + dimensions.border_bottom
  endif
  let pos[1] += dimensions.border_left

  " Create popup window based on menu type and platform
  if options.horizontal_menu
    let pum.horizontal_menu = v:true
    let pum.cursor = 0
    let pum.items = items->copy()
    call pum#popup#_redraw_horizontal_menu()
  elseif has('nvim')
    let pum = s:create_nvim_window(pum, pos, dimensions, options, items,
          \                        lines, direction, height)
  else
    let pum = s:create_vim_popup(pum, pos, dimensions, options, lines, height)
  endif

  " Adjust scrollbar position for reversed menus
  if reversed && pum.scroll_id > 0
    call win_execute(pum.id, 'call cursor("$", 0)')
    call pum#popup#_redraw_scroll()

    if has('nvim')
      call nvim_win_set_config(pum.scroll_id, #{
            \   border: 'none',
            \   relative: 'editor',
            \   row: pum.scroll_row + height - 1,
            \   col: pum.scroll_col,
            \ })
    endif
  endif

  " Fire PumOpen event
  if '#User#PumOpen'->exists()
    doautocmd <nomodeline> User PumOpen
  endif

  " Setup autocmds and store state
  call s:setup_autocmds_and_state(pum, items, direction, reversed, a:startcol,
        \                         options, a:mode, a:insert, max_columns,
        \                         height, dimensions)

  return pum.id
endfunction

function pum#popup#_close(id) abort
  if a:id <= 0
    return
  endif

  " Reset
  augroup pum
    autocmd!
  augroup END
  augroup pum-temp
    autocmd!
  augroup END

  let pum = pum#_get()
  let pum.current_word = ''
  let pum.id = -1
  let pum.scroll_id = -1
  let pum.cursor = -1

  let g:pum#completed_item = {}

  call pum#popup#_close_id(a:id)
  call s:stop_auto_confirm()
endfunction
function pum#popup#_close_id(id) abort
  if a:id < 0
    return
  endif

  try
    " Move cursor
    call win_execute(a:id, 'call cursor(1, 0)')

    " NOTE: popup may be already closed
    " Close popup and clear highlights
    if has('nvim')
      call nvim_buf_clear_namespace(
            \ a:id->winbufnr(), pum#_get().namespace, 1, -1)
      call nvim_win_close(a:id, v:true)
    else
      " NOTE: prop_remove() is not needed.
      " popup_close() removes the buffer.
      call popup_close(a:id)
    endif
  catch /E523:\|E565:\|E5555:\|E994:/
    " Ignore "Not allowed here"

    " Close the popup window later
    call timer_start(100, { -> pum#popup#_close_id(a:id) })
  endtry

  call pum#popup#_redraw()
endfunction

function pum#popup#_redraw() abort
  redraw
endfunction

function pum#popup#_redraw_scroll() abort
  const pum = pum#_get()

  " NOTE: normal redraw does not work...
  " And incsearch hack does not work in neovim.
  call win_execute(pum.id,
        \ has('nvim') ? 'redraw' : 'call pum#popup#_redraw()')
  if has('nvim') && &laststatus ==# 3
    redrawstatus
  endif

  if getcmdwintype() !=# ''
    " NOTE: redraw! is required for cmdwin
    redraw!
  endif
endfunction
function pum#popup#_redraw_preview() abort
  const pum = pum#_get()

  " NOTE: normal redraw does not work...
  " And incsearch hack does not work in neovim.
  call win_execute(pum.preview_id,
        \ has('nvim') ? 'redraw' : 'call pum#popup#_redraw()')
  if has('nvim') && &laststatus ==# 3
    redrawstatus
  endif

  if getcmdwintype() !=# ''
    " NOTE: redraw! is required for cmdwin
    redraw!
  endif
endfunction

" returns [border_left, border_top, border_right, border_bottom]
function s:get_border_size(border) abort
  if a:border->type() == v:t_string
    return a:border ==# 'none' ? [0, 0, 0, 0] : [1, 1, 1, 1]
  elseif a:border->type() == v:t_list && !a:border->empty()
    return [
          \   s:get_borderchar_width(a:border[3 % len(a:border)]),
          \   s:get_borderchar_height(a:border[1 % len(a:border)]),
          \   s:get_borderchar_width(a:border[7 % len(a:border)]),
          \   s:get_borderchar_height(a:border[5 % len(a:border)]),
          \ ]
  else
    return [0, 0, 0, 0]
  endif
endfunction

function s:get_borderchar_height(ch) abort
  if a:ch->type() == v:t_string
    " character
    return a:ch->empty() ? 0 : 1
  elseif a:ch->type() == v:t_list
        \ && !a:ch->empty() && a:ch[0]->type() == v:t_string
    " character with highlight: [ch, highlight]
    return a:ch[0]->empty() ? 0 : 1
  else
    call pum#util#_print_error('invalid border character: %s', a:ch)
    return 0
  endif
endfunction

function s:get_borderchar_width(ch) abort
  if a:ch->type() == v:t_string
    " character
    return strdisplaywidth(a:ch)
  elseif a:ch->type() == v:t_list
        \ && !a:ch->empty() && a:ch[0]->type() == v:t_string
    " character with highlight: [ch, highlight]
    return strdisplaywidth(a:ch[0])
  else
    call pum#util#_print_error('invalid border character: %s', a:ch)
    return 0
  endif
endfunction

" Calculate border and padding dimensions for popup windows
"
" Computes padding and border sizes based on options and mode. This is used
" across different popup types (main menu, horizontal menu, preview).
"
" Args:
"   border: Border specification from options
"   options: PUM options dictionary
"   mode: Mode character ('i', 'c', 't')
"   startcol: Starting column (used to determine padding)
"
" Returns:
"   Dictionary with:
"     - border_left, border_top, border_right, border_bottom: Individual sizes
"     - padding_height: Total vertical padding (1 + borders)
"     - padding_width: Total horizontal padding (1 + borders + optional padding)
"     - padding_left: Left padding offset
function s:calculate_border_padding(border, options, mode, startcol) abort
  const [border_left, border_top, border_right, border_bottom]
        \ = s:get_border_size(a:border)
  let padding_height = 1 + border_top + border_bottom
  let padding_width = 1 + border_left + border_right
  let padding_left = border_left

  " Add extra horizontal padding for command-line or non-first-column
  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left += 1
  endif

  return #{
        \   border_left: border_left,
        \   border_top: border_top,
        \   border_right: border_right,
        \   border_bottom: border_bottom,
        \   padding_height: padding_height,
        \   padding_width: padding_width,
        \   padding_left: padding_left,
        \ }
endfunction

" Get current screen position based on mode
"
" Retrieves the screen position of the cursor, handling different modes
" and terminal mode quirks.
"
" Args:
"   mode: Mode character ('i', 'c', 't')
"
" Returns:
"   Dictionary with row and col representing screen position
function s:get_screen_position(mode) abort
  if !has('nvim') && a:mode ==# 't'
    const cursor = bufnr('%')->term_getcursor()
    return #{ row: cursor[0], col: '.'->col() }
  else
    return screenpos(0, '.'->line(), '.'->col())
  endif
endfunction

" Determine popup direction based on available screen space
"
" Chooses whether to display popup above or below cursor based on available
" space and user preferences.
"
" Args:
"   spos: Screen position (dictionary with row)
"   height: Desired popup height
"   padding_height: Total vertical padding
"   options: PUM options (direction, offset_row)
"   mode: Mode character
"
" Returns:
"   String: 'above' or 'below'
function s:determine_direction(spos, height, padding_height, options, mode) abort
  if a:mode ==# 'c'
    return 'above'
  endif

  let minheight_below = [
        \   a:height, &lines - a:spos.row -
        \   a:padding_height - a:options.offset_row
        \ ]->min()
  let minheight_above = [
        \   a:height, a:spos.row - a:padding_height - a:options.offset_row
        \ ]->min()

  if (minheight_below < minheight_above && a:options.direction ==# 'auto')
        \ || (minheight_above >= 1 && a:options.direction ==# 'above')
    return 'above'
  else
    return 'below'
  endif
endfunction

function s:highlight_items(items, max_columns) abort
  let pum = pum#_get()
  let options = pum#_options()

  for row in range(1, a:items->len())
    " Default highlights

    let item = a:items[row - 1]
    let item_highlights = item->get('highlights', [])

    let start = 1
    for [order, max_column] in a:max_columns
      for hl in item_highlights->copy()->filter(
            \ {_, val -> val.type ==# order})
        call s:highlight(
              \ hl.hl_group, hl.name,
              \ s:priority_highlight_item,
              \ pum.buf, row, start + hl.col - 1, hl.width)
      endfor

      " NOTE: The byte length of multibyte characters may be larger than
      " max_column calculated by strdisplaywidth().
      let elem = ['abbr', 'kind', 'menu']->index(order) >= 0
            \ ? item->get(order, '')
            \ : item->get('columns', {})->get(order, '')
      let width = max_column - elem->strdisplaywidth() + elem->strlen()

      let highlight_column = options.highlight_columns->get(order, '')
      if highlight_column !=# ''
        call s:highlight(
              \ highlight_column, 'pum_' .. order,
              \ s:priority_highlight_column,
              \ pum.buf, row, start, width)
      endif

      let start += width
    endfor
  endfor
endfunction

function s:highlight(highlight, prop_type, priority, buf, row, col, length) abort
  if a:highlight ==# ''
    return
  endif

  let pum = pum#_get()

  let col = a:col
  if pum#_options().padding && (mode() ==# 'c' || pum.startcol != 1)
    let col += 1
  endif

  if !a:highlight->hlexists()
    call pum#util#_print_error(
          \ printf('highlight "%s" does not exist', a:highlight))
    return
  endif

  if has('nvim')
    return nvim_buf_set_extmark(
          \ a:buf, pum.namespace, a:row - 1, col - 1, #{
          \   end_col: col - 1 + a:length,
          \   hl_group: a:highlight,
          \   priority: a:priority,
          \ })
  else
    " Add prop_type
    if a:prop_type->prop_type_get()->empty()
      call prop_type_add(a:prop_type, #{
            \   highlight: a:highlight,
            \   priority: a:priority,
            \ })
    endif
    call prop_add(a:row, col, #{
          \   length: a:length,
          \   type: a:prop_type,
          \   bufnr: a:buf,
          \ })
    return -1
  endif
endfunction

function pum#popup#_redraw_selected() abort
  let pum = pum#_get()
  let prop_type = 'pum_highlight_selected'

  " Clear current highlight
  if has('nvim')
    call nvim_buf_del_extmark(pum.buf, pum.namespace, pum.selected_id)
    let pum.selected_id = -1
  elseif !prop_type->prop_type_get()->empty()
    call prop_remove(#{
          \   type: prop_type,
          \   bufnr: pum.buf,
          \ })
  endif

  if pum.cursor <= 0
    return
  endif
  let length = pum.buf->getbufline(pum.cursor)[0]->strlen()
  let col = pum#_options().padding && (mode() ==# 'c' || pum.startcol != 1)
        \ ? 0 : 1
  let pum.selected_id = s:highlight(
        \   pum#_options().highlight_selected,
        \   prop_type,
        \   s:priority_highlight_selected,
        \   pum.buf, pum.cursor, col, length
        \ )
endfunction

function pum#popup#_redraw_horizontal_menu() abort
  let pum = pum#_get()

  if pum.items->empty()
    call pum#close()
    return
  endif

  " Reorder items to place cursor item first (for horizontal scrolling)
  if pum.cursor == 0
    let items = pum.items->copy()
  else
    const cursor = pum.cursor - 1
    let items = [pum.items[cursor]]
    let items += pum.items[cursor + 1:]
    if cursor > 0
      let items += pum.items[: cursor - 1]
    endif
  endif

  let options = pum#_options()

  " Build horizontal menu lines with items separated by ' | '
  let lines = []
  let height = 0
  let item_count = 0
  let word = ''
  let separator = v:false
  for index in items->len()->range()
    if item_count != 0
      let word ..= ' | '
      let separator = v:true
    endif
    let word ..= items[index]->get('abbr', items[index].word)

    let item_count += 1

    if item_count >= options.max_horizontal_items
      if height >= options.max_height
        break
      endif

      call add(lines, word)

      " Next line
      let height += 1
      let word = ''
      let item_count = 0
    endif
  endfor
  if word != ''
    if index < items->len() - 1
      let word ..= ' ...'
    endif

    call add(lines, word)
    let height += 1
  endif

  " Apply height constraints
  if options.min_height > 0
    let height = [height, options.min_height]->max()
  endif

  " Calculate border and padding using shared helper
  const current_mode = mode()
  const border_padding =
        \ s:calculate_border_padding(options.border, options,
        \                            current_mode, pum.startcol)

  " Get current screen position
  let spos = s:get_screen_position(current_mode)

  " Determine direction (above/below cursor)
  const direction = s:determine_direction(
        \ spos, height, border_padding.padding_height, options, current_mode)

  " Calculate width with constraints
  let width = lines->mapnew({ _, val -> val->strwidth() })->max()
  if options.min_width > 0
    let width = [width, options.min_width]->max()
  endif
  if options.max_width > 0
    let width = [width, options.max_width]->min()
  endif

  " Calculate popup position
  let pos = current_mode ==# 'c' ?
        \ [&lines - height - [1, &cmdheight]->max() - options.offset_cmdrow,
        \  options.follow_cursor ? getcmdpos() + options.offset_cmdcol :
        \  options.offset_cmdcol] :
        \ [spos.row + (direction ==# 'above' ?
        \              -options.offset_row - height - 1 : options.offset_row),
        \  options.follow_cursor ? spos.col - 1 + options.offset_col :
        \  options.offset_col]

  " Apply command-line specific position adjustments
  if current_mode ==# 'c'
    const cmdline_pos = s:get_cmdline_pos(options, direction, pos[0])
    if !cmdline_pos->empty()
      let pos[0] = cmdline_pos.row
      let pos[1] += cmdline_pos.col
    endif

    let pos[1] += [getcmdprompt()->len(), 1]->max()
  endif

  " Create or update popup window (Neovim)
  if has('nvim')
    if pum.buf < 0
      let pum.buf = nvim_create_buf(v:false, v:true)
    endif
    call nvim_buf_set_lines(pum.buf, 0, -1, v:true, lines)

    let winopts = #{
          \   border: options.border,
          \   relative: 'editor',
          \   width: width,
          \   height: height,
          \   row: pos[0],
          \   col: pos[1],
          \   anchor: 'NW',
          \   style: 'minimal',
          \   zindex: options.zindex,
          \ }

    if pum.id > 0
      " Reuse window
      call nvim_win_set_config(pum.id, winopts)
    else
      call pum#close()

      " NOTE: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      const id = nvim_open_win(pum.buf, v:false, winopts)

      call s:set_float_window_options(id, options, 'horizontal_menu')

      let pum.id = id
    endif
  else
    " Create or update popup window (Vim)
    let winopts = #{
          \   pos: 'topleft',
          \   line: pos[0] + 1,
          \   col: pos[1] + 1,
          \   maxheight: height,
          \   maxwidth: width,
          \   highlight: options.highlight_horizontal_menu,
          \ }

    if pum.id > 0
      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)
    else
      let pum.id = popup_create(lines, winopts)
      let pum.buf = pum.id->winbufnr()
    endif
  endif

  let pum.pos = pos
  let pum.width = width

  " Highlight selected item and separator
  if pum.cursor > 0
    " Highlight the first item
    call s:highlight(
          \ options.highlight_selected,
          \ 'pum_highlight_selected',
          \ s:priority_highlight_selected,
          \ pum.buf, 1, 1, items[0]->get('abbr', items[0].word)->strlen())
  endif
  if separator
    call s:highlight(
          \ options.highlight_horizontal_separator,
          \ 'pum_highlight_separator',
          \ s:priority_highlight_selected,
          \ pum.buf, 1, items[0]->get('abbr', items[0].word)->strlen() + 2, 1)
  endif

  call pum#popup#_redraw()
endfunction

function pum#popup#_redraw_inserted() abort
  let pum = pum#_get()

  if pum.cursor <= 0 || pum.current_word ==# ''
    call pum#popup#_close_inserted()
    return
  endif

  let options = pum#_options()

  if has('nvim')
    if pum.inserted_buf < 0
      let pum.inserted_buf = nvim_create_buf(v:false, v:true)
    endif
    call nvim_buf_set_lines(
          \ pum.inserted_buf, 0, -1, v:true, [pum.current_word])

    let winopts = #{
          \   border: 'none',
          \   relative: 'editor',
          \   width: pum.current_word->strlen(),
          \   height: 1,
          \   row: pum.pos[0] - 1,
          \   col: pum.pos[1],
          \   anchor: 'NW',
          \   style: 'minimal',
          \   zindex: options.zindex,
          \ }

    if pum.inserted_id > 0
      " Reuse window
      call nvim_win_set_config(pum.inserted_id, winopts)
    else
      " NOTE: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      const id = nvim_open_win(pum.inserted_buf, v:false, winopts)

      call s:set_float_window_options(id, options, 'inserted')

      let pum.inserted_id = id
    endif
  else
    let winopts = #{
          \   pos: 'topleft',
          \   line: pum.pos[0],
          \   col: pum.pos[1] + 1,
          \   maxwidth: pum.current_word->strlen(),
          \   maxheight: 1,
          \   highlight: options.highlight_inserted,
          \ }

    if pum.inserted_id > 0
      call popup_move(pum.inserted_id, winopts)
      call popup_settext(pum.inserted_id, [pum.current_word])
    else
      let pum.inserted_id = popup_create([pum.current_word], winopts)
      let pum.inserted_buf = pum.inserted_id->winbufnr()
    endif
  endif

  " Highlight the lead text
  if pum.orig_input !=# '' && pum.current_word->stridx(pum.orig_input) == 0
    call s:highlight(
          \ options.highlight_lead,
          \ 'pum_highlight_lead',
          \ s:priority_highlight_lead,
          \ pum.inserted_buf, 1, 1, pum.orig_input->strlen())
  endif

  call pum#popup#_redraw()
endfunction
function pum#popup#_close_inserted() abort
  let pum = pum#_get()

  if pum.inserted_id < 0
    return
  endif

  call pum#popup#_close_id(pum.inserted_id)

  let pum.inserted_id = -1
endfunction

function pum#popup#_preview() abort
  let save_id = win_getid()

  const pos = getpos('.')
  try
    call s:open_preview()
  finally
    call setpos('.', pos)
  endtry

  call win_gotoid(save_id)
endfunction

" Calculate dimensions for preview window
"
" Computes width and height for preview window based on content and
" available screen space.
"
" Args:
"   previewer: Previewer dictionary with optional 'contents' key
"   options: PUM options
"
" Returns:
"   Dictionary with width and height
function s:calculate_preview_dimensions(previewer, options) abort
  " Calculate initial dimensions from content or use defaults
  if a:previewer->has_key('contents')
    let width = a:previewer.contents
          \ ->mapnew({ _, val -> val->strwidth() })->max()
    let width = [width, a:options.preview_width]->min()

    " Calculate height with word wrapping algorithm
    " Algorithm derived from https://github.com/matsui54/denops-popup-preview.vim
    " (MIT Licence; Copyright (c) 2021 Haruki Matsui)
    let height = 0
    for line in a:previewer.contents
      let height += [
            \   1, (line->strdisplaywidth() / (width + 0.0))
            \      ->ceil()->float2nr()
            \ ]->max()
    endfor
    let height = [height, a:options.preview_height]->min()
  else
    let width = a:options.preview_width
    let height = a:options.preview_height
  endif

  " Constrain dimensions to reasonable bounds
  " NOTE: Must be positive and fit within available screen space
  let width  = [[20, width]->max(),
        \       (&columns - win_screenpos(0)[1]) / 3]->min()
  let height = [[1, height]->max(), &lines / 2]->min()

  return #{ width: width, height: height }
endfunction

" Create or update preview window for Neovim
"
" Handles Neovim-specific window creation and configuration for preview.
"
" Args:
"   pum: PUM state object
"   previewer: Previewer dictionary
"   options: PUM options
"   row: Window row position
"   col: Window column position
"   dimensions: Dimensions dictionary from s:calculate_preview_dimensions()
"
" Returns:
"   Updated pum object
function s:create_preview_window_nvim(
      \ pum, previewer, options, row, col, dimensions) abort
  " Create buffer if needed
  if a:pum.preview_buf < 0
    let a:pum.preview_buf = nvim_create_buf(v:false, v:true)
  endif

  " Set buffer contents if provided
  if a:previewer->has_key('contents')
    call setbufvar(a:pum.preview_buf, '&modifiable', v:true)
    call setbufvar(a:pum.preview_buf, '&readonly', v:false)
    call nvim_buf_set_lines(
          \ a:pum.preview_buf, 0, -1, v:true, a:previewer.contents)
    call setbufvar(a:pum.preview_buf, '&modified', v:false)
  endif

  " Configure window options
  let winopts = #{
        \   border: a:options.preview_border,
        \   relative: 'editor',
        \   row: a:row - 1,
        \   col: a:col - 1,
        \   width: a:dimensions.width,
        \   height: a:dimensions.height,
        \   anchor: 'NW',
        \   style: 'minimal',
        \   zindex: a:options.zindex + 1,
        \ }

  " Create or update window
  if a:pum.preview_id > 0
    " Reuse existing window
    call nvim_win_set_config(a:pum.preview_id, winopts)
  else
    call pum#popup#_close_preview()

    " NOTE: noautocmd cannot be set in nvim_win_set_config()
    let winopts.noautocmd = v:true

    " Create new window
    const id = nvim_open_win(a:pum.preview_buf, v:false, winopts)

    call s:set_float_window_options(id, a:options, 'preview')

    let a:pum.preview_id = id
  endif

  " Handle help previews (requires special buffer setup)
  if a:previewer.kind ==# 'help'
    if a:previewer.kind !=# a:pum.preview_kind
      " Create new buffer for help
      let a:pum.preview_buf = nvim_create_buf(v:false, v:true)
    endif

    try
      call win_execute(a:pum.preview_id,
            \ 'setlocal buftype=help | help ' .. a:previewer.tag)
    catch
      call pum#popup#_close_preview()
      return a:pum
    endtry
  endif

  return a:pum
endfunction

" Create or update preview window for Vim
"
" Handles Vim-specific popup window creation and configuration for preview.
"
" Args:
"   pum: PUM state object
"   previewer: Previewer dictionary
"   options: PUM options
"   row: Window row position
"   col: Window column position
"   dimensions: Dimensions dictionary from s:calculate_preview_dimensions()
"
" Returns:
"   Updated pum object
" Setup help preview buffer for Vim
" Returns [help_bufnr, firstline] or [v:null, v:null] on error
function s:setup_help_preview_buffer(tag) abort
  const save_window = win_getid()
  const help_save = range(1, winnr('$'))
        \ ->filter({ _, val -> val->getwinvar('&buftype') ==# 'help'})
        \ ->map({ _, val -> [val, val->winbufnr(), val->getcurpos()]})

  try
    " Create dummy help buffer
    " NOTE: ":help" does not work in popup window.
    execute 'help' a:tag
    const help_bufnr = bufnr()
    const firstline = '.'->line()
  catch
    return [v:null, v:null]
  endtry

  " Restore previous help windows
  if help_save->empty()
    helpclose
  else
    for save in help_save
      execute save[0] 'wincmd w'
      execute 'buffer' save[1][0]
      call setpos('.', save[2])
    endfor
    call win_gotoid(save_window)
  endif

  return [help_bufnr, firstline]
endfunction

" Create help preview window in Vim
function s:create_help_preview_vim(pum, previewer, winopts) abort
  call pum#popup#_close_preview()

  let [help_bufnr, firstline] = s:setup_help_preview_buffer(a:previewer.tag)
  if help_bufnr == v:null
    call pum#popup#_close_preview()
    return a:pum
  endif

  " Set firstline to display tag
  let winopts = deepcopy(a:winopts)
  let winopts.firstline = firstline

  let a:pum.preview_id = popup_create(help_bufnr, winopts)
  let a:pum.preview_buf = help_bufnr

  return a:pum
endfunction

" Create or update regular content preview window in Vim
function s:create_content_preview_vim(pum, previewer, winopts) abort
  if a:pum.preview_id > 0
    " Update existing popup window
    call popup_move(a:pum.preview_id, a:winopts)
    if a:previewer->has_key('contents')
      call popup_settext(a:pum.preview_id, a:previewer.contents)
    endif
  else
    " Create new popup window
    if a:previewer->has_key('contents')
      let a:pum.preview_id = popup_create(a:previewer.contents, a:winopts)
    else
      let a:pum.preview_id = popup_create([], a:winopts)
    endif
    let a:pum.preview_buf = a:pum.preview_id->winbufnr()
  endif

  return a:pum
endfunction

function s:create_preview_window_vim(
      \ pum, previewer, options, row, col, dimensions) abort
  " Configure window options
  let winopts = #{
        \   pos: 'topleft',
        \   line: a:row,
        \   col: a:col,
        \   maxwidth: a:dimensions.width,
        \   maxheight: a:dimensions.height,
        \   highlight: a:options.highlight_preview,
        \   scrollbarhighlight: a:options.highlight_scrollbar,
        \ }

  " Handle help previews (requires special buffer setup in Vim)
  if a:previewer.kind ==# 'help'
    return s:create_help_preview_vim(a:pum, a:previewer, winopts)
  else
    return s:create_content_preview_vim(a:pum, a:previewer, winopts)
  endif
endfunction

function s:open_preview() abort
  let pum = pum#_get()

  " Validate preview requirements
  if pum.cursor <= 0
    call pum#popup#_close_preview()
    return
  endif

  const item = pum#current_item()

  " Get preview contents and validate
  const previewer = s:get_previewer(item)
  if previewer->has_key('contents') && previewer.contents->empty()
    call pum#popup#_close_preview()
    return
  endif

  const options = pum#_options()

  " Calculate preview position (to the right of main popup)
  const pos = pum#get_pos()
  if pos->empty()
    return
  endif
  const row = pos.row + 1
  const col = pos.col + pos.width + 2

  " Calculate preview dimensions
  const dimensions = s:calculate_preview_dimensions(previewer, options)

  " Create or update preview window (platform-specific)
  if has('nvim')
    let pum = s:create_preview_window_nvim(
          \ pum, previewer, options, row, col, dimensions)
  else
    let pum = s:create_preview_window_vim(
          \ pum, previewer, options, row, col, dimensions)
  endif

  " Execute custom command if provided
  if previewer->has_key('command')
    try
      call win_execute(pum.preview_id, previewer.command)
    catch
      call pum#popup#_close_preview()
      return
    endtry
  endif

  " Configure window settings
  if previewer.kind ==# 'markdown'
    call setbufvar(pum.preview_buf, '&filetype', 'markdown')
  endif
  call setwinvar(pum.preview_id, '&wrap', v:true)
  call setwinvar(pum.preview_id, '&foldenable', v:false)

  " Navigate to specific line if requested
  if previewer->has_key('lineNr')
    try
      call win_execute(pum.preview_id, previewer.lineNr)
    catch
      call pum#popup#_close_preview()
      return
    endtry
  endif

  " Fire user autocommand event
  if '#User#PumPreview'->exists()
    doautocmd <nomodeline> User PumPreview
  endif

  " Setup autocmds to close preview when cursor moves
  augroup pum-preview
    autocmd!
  augroup END

  autocmd pum-preview ModeChanged *:n ++nested
          \ call pum#popup#_close_preview()
  if mode() ==# 'c'
    autocmd pum-preview CursorMovedC * ++nested
          \ call s:check_preview()
  else
    autocmd pum-preview CursorMovedI * ++nested
          \ call s:check_preview()
  endif

  " Store preview state
  let pum.preview_row = row
  let pum.preview_col = col
  let pum.preview_kind = previewer.kind

  call pum#popup#_redraw()
endfunction
function pum#popup#_close_preview() abort
  let pum = pum#_get()

  if pum.preview_id < 0
    return
  endif

  augroup pum-preview
    autocmd!
  augroup END

  call pum#popup#_close_id(pum.preview_id)

  let pum.preview_id = -1
  let pum.preview_row = 0
  let pum.preview_col = 0
endfunction
function s:get_previewer(item) abort
  " In terminal mode, it does not work well.
  if mode() !=# 't' && '*ddc#get_previewer'->exists()
    const previewer = ddc#get_previewer(a:item)
    if previewer.kind !=# 'empty'
      return previewer
    endif
  endif

  " Fallback to item info
  const info = a:item->get('info', '')

  return #{
        \   kind: 'text',
        \   contents: info->substitute('\r\n\?', '\n', 'g')->split('\n'),
        \ }
endfunction
function s:check_preview() abort
  let pum = pum#_get()

  if pum.preview_id < 0
    return
  endif

  if mode() ==# 'c' && pum#_col() >= pum.preview_col - 1
    call pum#popup#_close_preview()
  elseif pum#_row() >= pum.preview_row && pum#_col() >= pum.preview_col
    call pum#popup#_close_preview()
  endif
endfunction

function pum#popup#_reset_auto_confirm(mode) abort
  call s:stop_auto_confirm()

  let options = pum#_options()
  if options.auto_confirm_time <= 0
    return
  endif

  let pum = pum#_get()

  let pum.auto_confirm_timer = timer_start(
        \ options.auto_confirm_time, { -> s:auto_confirm() })

  " Reset the timer when user input texts
  if a:mode ==# 'i'
    autocmd pum TextChangedI,TextChangedP * ++once ++nested
          \ call pum#popup#_reset_auto_confirm(mode())
  elseif a:mode ==# 'c'
    autocmd pum CmdlineChanged * ++once ++nested
          \ call pum#popup#_reset_auto_confirm(mode())
  elseif a:mode ==# 't'
    autocmd pum TextChangedT * ++once ++nested
          \ call pum#popup#_reset_auto_confirm(mode())
  endif
endfunction
function s:stop_auto_confirm() abort
  let pum = pum#_get()
  if pum.auto_confirm_timer > 0
    call timer_stop(pum.auto_confirm_timer)

    let pum.auto_confirm_timer = -1
  endif
endfunction
function s:auto_confirm() abort
  let pum = pum#_get()
  if pum.current_word ==# '' || pum.cursor == 0
    return
  endif

  call pum#map#confirm()
  call pum#close()
endfunction

function pum#popup#_check_text_changed() abort
  const next_input = pum#_getline()[pum#_col():]

  if !'s:prev_next'->exists()
    let s:prev_next = next_input
  endif

  let pum = pum#_get()
  if pum.skip_complete
    let s:prev_next = next_input
    return
  endif

  if pum#_row() != pum.startrow || next_input !=# s:prev_next
    call pum#close()
  endif
  let s:prev_next = next_input
endfunction

function pum#popup#_check_cursor_moved() abort
  let pum = pum#_get()
  if pum#_col() != pum.col && pum#_getline() ==# pum.orig_line
    call pum#close()
  endif
endfunction

function s:set_float_window_options(id, options, highlight) abort
  let highlight = 'NormalFloat:' ..
        \ (   a:highlight ==# ''
        \   ? 'None'
        \   : a:options['highlight_' .. a:highlight]
        \ )
  let highlight ..= ',FloatBorder:FloatBorder,CursorLine:Visual'
  if &hlsearch
    " Disable 'hlsearch' highlight
    let highlight ..= ',Search:None,CurSearch:None'
  endif

  call setwinvar(a:id, '&winhighlight', highlight)
  call setwinvar(a:id, '&winblend', a:options.blend)
  call setwinvar(a:id, '&wrap', v:false)
  call setwinvar(a:id, '&scrolloff', 0)
endfunction

function s:uniq_by_word_or_dup(items) abort
  let ret = []
  let seen = {}
  for item in a:items
    let key = item.word
    if !seen->has_key(key) || item->get('dup', 0)
      let seen[key] = v:true
      call add(ret, item)
    endif
  endfor
  return ret
endfunction

function s:is_cmdline_vim_window() abort
  return '*cmdline#_get'->exists() && !cmdline#_get().pos->empty()
endfunction

function s:get_cmdline_pos(options, direction, cmdline_row) abort
  let pos = {}

  if s:is_cmdline_vim_window()
    const [cmdline_left, cmdline_top, cmdline_right, cmdline_bottom]
          \ = s:get_border_size(cmdline#_options().border)

    let cmdline_pos = cmdline#_get().pos->copy()
    let cmdline_pos[0] += cmdline_top + cmdline_bottom
    let cmdline_pos[1] += cmdline_left

    let pos.row = cmdline_pos[0]
    let pos.row += (a:direction ==# 'above' ?
          \        -a:options.offset_row : a:options.offset_row)

    let pos.col = cmdline_pos[1] + 1
  elseif has('nvim') && pum#util#_luacheck('noice')
    " Use noice cursor
    let noice_pos = 'require("noice").api.get_cmdline_position()'
          \ ->luaeval().screenpos
    let noice_view =
          \ 'require("noice.config").options.cmdline.view'->luaeval()
    if noice_view ==# 'cmdline'
      " NOTE: Use default command line row.
      let pos.row = a:cmdline_row
    else
      let pos.row = noice_pos.row
      let pos.row += (a:direction ==# 'above' ?
            \        -a:options.offset_row : a:options.offset_row)
    endif

    let pos.col = noice_pos.col - 1
  endif

  return pos
endfunction

" Calculate column widths for popup menu items
"
" Determines the maximum display width needed for each column type (abbr, kind,
" menu, custom columns) across all items, respecting configured constraints.
"
" Args:
"   items: List of completion items
"   options: PUM options containing item_orders and max_columns
"
" Returns:
"   [max_columns, width, non_abbr_length]
"   - max_columns: List of [column_name, max_width] pairs
"   - width: Total width of all columns combined
"   - non_abbr_length: Width of all non-abbr columns
function s:calculate_column_widths(items, options) abort
  let max_columns = []
  let width = 0
  let non_abbr_length = 0
  let prev_column_length = 0

  for column in a:options.item_orders
    " Calculate max width for each column type
    let max_column =
          \   column ==# 'space' ? 1 :
          \   column ==# 'abbr' ? a:items->mapnew({ _, val ->
          \     val->get('abbr', val.word)->strdisplaywidth()
          \   })->max() :
          \   column ==# 'kind' ? a:items->mapnew({ _, val ->
          \     val->get('kind', '')->strdisplaywidth()
          \   })->max() :
          \   column ==# 'menu' ? a:items->mapnew({ _, val ->
          \     val->get('menu', '')->strdisplaywidth()
          \   })->max() :
          \   a:items->mapnew({ _, val ->
          \     val->get('columns', {})->get(column, '')
          \     ->strdisplaywidth()
          \   })->max()

    " Apply max column constraints
    let max_column = [
          \  max_column,
          \  a:options.max_columns->get(column, max_column)
          \ ]->min()

    " Skip columns with zero width or space after zero-width column
    if max_column <= 0 || (column ==# 'space' && prev_column_length ==# 0)
      let prev_column_length = 0
      continue
    endif

    let width += max_column
    call add(max_columns, [column, max_column])

    if column !=# 'abbr'
      let non_abbr_length += max_column
    endif
    let prev_column_length = max_column
  endfor

  return [max_columns, width, non_abbr_length]
endfunction

" Calculate padding dimensions based on mode and options
" Returns [padding, padding_height, padding_width, padding_left]
function s:calculate_padding_dimensions(options, mode, startcol, border) abort
  const padding = a:options.padding ?
        \ (a:mode ==# 'c' || a:startcol != 1) ? 2 : 1 : 0

  const [border_left, border_top, border_right, border_bottom] =
        \ s:get_border_size(a:border)
  
  let padding_height = 1 + border_top + border_bottom
  let padding_width = 1 + border_left + border_right
  let padding_left = border_left
  
  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left += 1
  endif

  return [padding, padding_height, padding_width, padding_left,
        \ border_left, border_top, border_right, border_bottom]
endfunction

" Apply width constraints to calculated width
function s:apply_width_constraints(width, options) abort
  let result = a:width
  if a:options.min_width > 0
    let result = [result, a:options.min_width]->max()
  endif
  if a:options.max_width > 0
    let result = [result, a:options.max_width]->min()
  endif
  return result
endfunction

" Apply height constraints to calculated height
function s:apply_height_constraints(height, options) abort
  let result = a:height
  if a:options.max_height > 0
    let result = [result, a:options.max_height]->min()
  endif
  if a:options.min_height > 0
    let result = [result, a:options.min_height]->max()
  endif
  return result
endfunction

" Calculate final popup dimensions and format display lines
"
" Applies padding, width/height constraints, calculates border sizes, and
" formats all items into display lines ready for rendering.
"
" Args:
"   items: List of completion items
"   max_columns: Column width information from s:calculate_column_widths()
"   total_width: Total width of all columns combined (before padding)
"   non_abbr_length: Width of non-abbr columns
"   options: PUM options
"   mode: Mode character ('i', 'c', 't')
"   startcol: Starting column
"   pum: PUM state object
"
" Returns:
"   Dictionary with width, height, padding info, border sizes, and formatted
"   lines
function s:calculate_dimensions(
      \ items, max_columns, total_width, non_abbr_length,
      \ options, mode, startcol, pum) abort
  " Calculate padding dimensions
  let [padding, padding_height, padding_width, padding_left,
        \ border_left, border_top, border_right, border_bottom] =
        \ s:calculate_padding_dimensions(a:options, a:mode, a:startcol,
        \                                 a:options.border)

  " Apply width constraints
  let width = s:apply_width_constraints(a:total_width + padding, a:options)

  " Calculate abbr width (abbr takes remaining space)
  const abbr_width = width - a:non_abbr_length - padding

  " Format items into display lines
  let lines = a:items->copy()
        \ ->map({ _, val ->
        \   pum#_format_item(
        \     val, a:options, a:mode, a:startcol, a:max_columns, abbr_width
        \   )
        \ })

  " Apply height constraints
  let height = s:apply_height_constraints(a:items->len(), a:options)

  return #{
        \   width: width,
        \   height: height,
        \   padding: padding,
        \   padding_height: padding_height,
        \   padding_width: padding_width,
        \   padding_left: padding_left,
        \   border_left: border_left,
        \   border_top: border_top,
        \   border_right: border_right,
        \   border_bottom: border_bottom,
        \   abbr_width: abbr_width,
        \   lines: lines,
        \ }
endfunction

" Calculate popup position and determine display direction
"
" Determines where the popup should appear (above/below cursor), adjusts for
" screen boundaries, and handles item reversal for above-cursor display.
"
" Args:
"   spos: Screen position (row, col)
"   dimensions: Dimension info from s:calculate_dimensions()
"   options: PUM options
"   mode: Mode character ('i', 'c', 't')
"   items: List of completion items
"   startcol: Starting column for completion
"
" Returns:
"   [pos, direction, height, reversed, items, lines]
"   - pos: Final [row, col] position
"   - direction: 'above' or 'below'
"   - height: Final height after adjustments
"   - reversed: Whether items were reversed
"   - items: Possibly reversed items list
"   - lines: Possibly reversed display lines
" Determine menu direction based on available screen space
" Returns [direction, height, adjusted_row]
function s:determine_menu_direction(spos, dimensions, options, height, mode) abort
  if a:mode ==# 'c'
    " Command-line mode - always below
    const cmd_height = [a:height, &lines - [&cmdheight, 1]->max()]->min()
    return ['below', cmd_height, a:spos.row]
  endif

  let spos_row = a:spos.row
  const minheight_below = [
        \   a:height,
        \   &lines - spos_row - a:dimensions.padding_height - a:options.offset_row,
        \ ]->min()
  const minheight_above = [
        \   a:height,
        \   spos_row - a:dimensions.padding_height - a:options.offset_row,
        \ ]->min()

  " Choose direction based on available space
  if (minheight_below < minheight_above && a:options.direction ==# 'auto')
        \ || (minheight_above >= 1 && a:options.direction ==# 'above')
    " Use above window
    let spos_row -= a:height + a:dimensions.padding_height
    return ['above', minheight_above, spos_row]
  else
    " Use below window
    return ['below', minheight_below, spos_row]
  endif
endfunction

" Reverse items and lines if needed based on direction and options
" Returns [reversed_flag, items, lines]
function s:apply_item_reversal(direction, items, lines, options) abort
  const reversed = a:direction ==# 'above' && a:options.reversed
  const result_items = reversed ? a:items->copy()->reverse() : a:items
  const result_lines = reversed ? a:lines->copy()->reverse() : a:lines
  return [reversed, result_items, result_lines]
endfunction

" Adjust column position to fit within screen bounds
" Returns adjusted column value
function s:adjust_column_position(col, dimensions, padding_left) abort
  let adjusted_col = a:col

  " Adjust column position to fit within screen
  const rest_width = &columns - adjusted_col - a:dimensions.padding_width
  if rest_width < a:dimensions.width
    let adjusted_col -= a:dimensions.width - rest_width
  endif

  " Apply padding adjustment
  let adjusted_col -= a:padding_left

  " Ensure column is within bounds
  if adjusted_col <= 0
    let adjusted_col = 1
  endif

  return adjusted_col
endfunction

function s:calculate_position(
      \ spos, dimensions, options, mode, items, startcol) abort
  " Determine direction and calculate appropriate height
  let [direction, height, adjusted_row] = s:determine_menu_direction(
        \ a:spos, a:dimensions, a:options, a:dimensions.height, a:mode)
  let height = [height, 1]->max()

  " Apply item/line reversal if needed
  let [reversed, items, lines] = s:apply_item_reversal(
        \ direction, a:items, a:dimensions.lines, a:options)

  " Create local copy of spos with adjusted row
  let spos_copy = deepcopy(a:spos)
  let spos_copy.row = adjusted_row

  " Adjust column position
  let spos_copy.col = s:adjust_column_position(
        \ spos_copy.col, a:dimensions, a:dimensions.padding_left)

  " Calculate final position
  let pos =
        \   a:mode ==# 'c'
        \ ? [
        \  &lines - height - [1, &cmdheight]->max() - a:options.offset_cmdrow,
        \  a:options.follow_cursor ? getcmdpos() :
        \  (a:startcol > 2 ? getcmdline()[: a:startcol - 2]->strdisplaywidth()
        \                  : a:startcol - 1)
        \  - a:dimensions.padding_left + a:options.offset_cmdcol,
        \ ]
        \ : [
        \  spos_copy.row + (direction ==# 'above' ?
        \              -a:options.offset_row : a:options.offset_row),
        \  spos_copy.col - 1,
        \ ]

  return [pos, direction, height, reversed, items, lines]
endfunction

" Adjust position for command-line mode with special plugin support
"
" Handles position adjustments for command-line mode, including support for
" vim-cmdline and Noice.nvim plugins that provide custom command-line windows.
"
" Args:
"   pos: Initial position [row, col]
"   height: Initial height
"   direction: Initial direction ('above' or 'below')
"   options: PUM options
"   dimensions: Dimension info from s:calculate_dimensions()
"   lines: Formatted display lines
"
" Returns:
"   [pos, height, direction] - Adjusted values for command-line mode
function s:adjust_cmdline_position(
      \ pos, height, direction, options, dimensions, lines) abort
  const check_cmdline = s:is_cmdline_vim_window()
  const check_noice = has('nvim') && pum#util#_luacheck('noice')
        \ && 'require("noice").api.get_cmdline_position()'
        \    ->luaeval()->type() != v:null->type()

  const adjustment = [getcmdprompt()->len(), 1]->max()
  const cmdline_pos = s:get_cmdline_pos(a:options, a:direction, a:pos[0])

  let direction = a:direction
  let pos = a:pos
  let height = a:height

  if cmdline_pos->empty()
    let direction = 'above'
  else
    let pos[0] = cmdline_pos.row
    let pos[1] += cmdline_pos.col
    if !has('nvim') && adjustment ==# 0
      let pos[1] += 1
    endif
  endif

  let pos[1] += adjustment

  if check_cmdline || check_noice
    " Adjust height to fit available space
    let height = [
          \   height,
          \     direction ==# 'above'
          \   ? pos[0] - 1
          \   : &lines - &cmdheight - pos[0]
          \ ]->min()
    if direction ==# 'above'
      let pos[0] -= height + 1
    endif

    if len(a:lines) > height
      let height -= a:dimensions.border_top + a:dimensions.border_bottom
    else
      let pos[0] -= a:dimensions.border_top + a:dimensions.border_bottom
    endif
  endif

  return [pos, height, direction]
endfunction

" Calculate scrollbar configuration for Neovim
" Returns [scroll_height, scroll_row, scroll_col, scroll_winopts]
function s:calculate_nvim_scrollbar_config(
      \ pos, dimensions, options, height, lines_count) abort
  const scroll_height = [
        \ (a:height * ((a:height + 0.0) / a:lines_count) + 0.5)
        \ ->floor()->float2nr(), 1]->max()
  const scroll_row = a:pos[0] + a:dimensions.border_top
  const scroll_col = a:pos[1] + a:dimensions.width + a:dimensions.border_right
  const scroll_winopts = #{
        \   border: 'none',
        \   relative: 'editor',
        \   width: a:options.scrollbar_char->strwidth(),
        \   height: scroll_height,
        \   row: scroll_row,
        \   col: scroll_col,
        \   anchor: 'NW',
        \   style: 'minimal',
        \   zindex: a:options.zindex + 1,
        \ }
  return [scroll_height, scroll_row, scroll_col, scroll_winopts]
endfunction

" Setup or update Neovim scrollbar window
function s:setup_nvim_scrollbar(pum, options, scroll_winopts) abort
  if a:pum.scroll_id > 0
    " Reuse scrollbar window
    call nvim_win_set_config(a:pum.scroll_id, a:scroll_winopts)
  else
    " Create new scrollbar window
    let scroll_winopts = deepcopy(a:scroll_winopts)
    let scroll_winopts.noautocmd = v:true
    let scroll_id = nvim_open_win(
          \ a:pum.scroll_buf, v:false, scroll_winopts)
    call s:set_float_window_options(scroll_id, a:options, 'scrollbar')
    let a:pum.scroll_id = scroll_id
  endif
endfunction

" Create or update Neovim floating window for popup menu
"
" Manages Neovim floating windows including the main popup and optional
" scrollbar. Reuses existing windows when possible to minimize flickering.
"
" Args:
"   pum: PUM state object
"   pos: Position [row, col]
"   dimensions: Dimension info from s:calculate_dimensions()
"   options: PUM options
"   items: List of completion items
"   lines: Formatted display lines
"   direction: Display direction ('above' or 'below')
"   height: Window height
"
" Returns:
"   Updated pum object with window IDs and state
function s:create_nvim_window(
      \ pum, pos, dimensions, options, items, lines, direction, height) abort
  " Create buffers if needed
  if a:pum.buf < 0
    let a:pum.buf = nvim_create_buf(v:false, v:true)
  endif
  if a:pum.scroll_buf < 0
    let a:pum.scroll_buf = nvim_create_buf(v:false, v:true)
  endif

  " Set buffer content
  call nvim_buf_set_lines(a:pum.buf, 0, -1, v:true, a:lines)

  let scroll_lines = a:lines->mapnew({ _ -> a:options.scrollbar_char })
  call nvim_buf_set_lines(a:pum.scroll_buf, 0, -1, v:true, scroll_lines)

  " Configure main window options
  let winopts = #{
        \   border: a:options.border,
        \   relative: 'editor',
        \   width: a:dimensions.width,
        \   height: a:height,
        \   row: a:pos[0],
        \   col: a:pos[1],
        \   anchor: 'NW',
        \   style: 'minimal',
        \   zindex: a:options.zindex,
        \ }

  " Calculate scrollbar configuration
  let [scroll_height, scroll_row, scroll_col, scroll_winopts] =
        \ s:calculate_nvim_scrollbar_config(
        \   a:pos, a:dimensions, a:options, a:height, a:lines->len())

  let a:pum.scroll_row = scroll_row
  let a:pum.scroll_col = scroll_col
  let a:pum.scroll_height = scroll_height

  " Create or update main window
  if a:pum.id > 0
    call pum#close('complete_done', v:false)

    if a:pos == a:pum.pos
      " Resize existing window
      call nvim_win_set_width(a:pum.id, a:dimensions.width)
      call nvim_win_set_height(a:pum.id, a:height)
    else
      " Reuse window with new config
      call nvim_win_set_config(a:pum.id, winopts)
    endif
  else
    call pum#close()

    " Create new window
    let winopts.noautocmd = v:true
    const id = nvim_open_win(a:pum.buf, v:false, winopts)
    call s:set_float_window_options(id, a:options, 'normal_menu')
    let a:pum.id = id
  endif

  " Create or update scrollbar window
  if a:options.scrollbar_char !=# '' && len(a:lines) > a:height
    call s:setup_nvim_scrollbar(a:pum, a:options, scroll_winopts)
  elseif a:pum.scroll_id > 0
    call pum#popup#_close_id(a:pum.scroll_id)
    let a:pum.scroll_id = -1
  endif

  let a:pum.pos = a:pos
  let a:pum.horizontal_menu = v:false

  return a:pum
endfunction

" Create or update Vim popup window for popup menu
"
" Manages Vim popup windows with proper border styling and character sets.
" Reuses existing popups when possible.
"
" Args:
"   pum: PUM state object
"   pos: Position [row, col]
"   dimensions: Dimension info from s:calculate_dimensions()
"   options: PUM options
"   lines: Formatted display lines
"   height: Window height
"
" Returns:
"   Updated pum object with window IDs and state
function s:create_vim_popup(
      \ pum, pos, dimensions, options, lines, height) abort
  " Configure popup options
  let winopts = #{
        \   pos: 'topleft',
        \   line: a:pos[0] + 1,
        \   col: a:pos[1] + 1,
        \   highlight: a:options.highlight_normal_menu,
        \   maxwidth: a:dimensions.width,
        \   maxheight: a:height,
        \   scroll: a:options.scrollbar_char !=# '',
        \   wrap: 0,
        \   zindex: a:options.zindex,
        \ }

  " Handle border configuration
  if a:options.border->type() ==# v:t_string
    if a:options.border !=# 'none'
      let winopts.border = [1, 1, 1, 1]
    endif

    if &ambiwidth ==# 'single' && &encoding ==# 'utf-8'
      " Use Unicode border characters for better appearance
      if a:options.border ==# 'single'
        let winopts.borderchars = [
              \   '─', '│', '─', '│',
              \   '┌', '┐', '┘', '└',
              \ ]
      elseif a:options.border ==# 'double'
        let winopts.borderchars = [
              \   '═', '║', '═', '║',
              \   '╔', '╗', '╝', '╚',
              \ ]
      endif
    endif
  else
    let winopts.border = [1, 1, 1, 1]
    let winopts.borderchars = a:options.border
  endif

  " Create or update popup
  if a:pum.id > 0
    call pum#close('complete_done', v:false)
    call popup_move(a:pum.id, winopts)
    call popup_settext(a:pum.id, a:lines)
  else
    call pum#close()
    let a:pum.id = a:lines->popup_create(winopts)
    let a:pum.buf = a:pum.id->winbufnr()
  endif

  let a:pum.pos = a:pos
  let a:pum.horizontal_menu = v:false

  return a:pum
endfunction

" Setup autocmds for popup lifecycle and store popup state
"
" Configures mode-specific autocmds for automatic popup closing and text change
" tracking. Stores all popup state including items, position, and dimensions.
" Applies highlighting and handles initial item selection.
"
" Args:
"   pum: PUM state object
"   items: List of completion items
"   direction: Display direction ('above' or 'below')
"   reversed: Whether items are reversed
"   startcol: Starting column
"   options: PUM options
"   mode: Mode character ('i', 'c', 't')
"   insert: If true, automatically insert first item
"   max_columns: Column width information
"   height: Window height
"   dimensions: Dimension info from s:calculate_dimensions()
function s:setup_autocmds_and_state(
      \ pum, items, direction, reversed, startcol,
      \ options, mode, insert, max_columns, height, dimensions) abort
  " Store popup state
  let a:pum.items = a:items->copy()
  let a:pum.cursor = 0
  let a:pum.direction = a:direction
  let a:pum.height = a:height
  let a:pum.width = a:dimensions.width
  let a:pum.border_width =
        \ a:dimensions.border_left + a:dimensions.border_right
  let a:pum.border_height =
        \ a:dimensions.border_top + a:dimensions.border_bottom
  let a:pum.len = a:items->len()
  let a:pum.reversed = a:reversed
  let a:pum.startcol = a:startcol
  let a:pum.startrow = pum#_row()
  let a:pum.current_line = pum#_getline()
  let a:pum.col = pum#_col()
  let a:pum.orig_input = pum#_getline()[a:startcol - 1 : pum#_col() - 2]
  let a:pum.orig_line = pum#_getline()
  let a:pum.changedtick = b:changedtick
  let a:pum.preview = a:options.preview

  if !a:pum.horizontal_menu
    " Apply highlighting to items
    call s:highlight_items(a:items, a:max_columns)

    " Highlight matching text
    silent! call matchdelete(a:pum.matched_id, a:pum.id)
    if a:options.highlight_matches !=# ''
      let pattern = a:pum.orig_input
            \ ->escape('~"*\.^$[]')
            \ ->substitute('\w\ze.', '\0[^\0]\\{-}', 'g')
      call matchadd(
            \ a:options.highlight_matches, pattern, 0, a:pum.matched_id,
            \ #{ window: a:pum.id })
    endif
  endif

  " Handle initial selection
  if a:insert
    call pum#map#insert_relative(+1)
  elseif a:options.auto_select
    call pum#map#select_relative(+1)
  else
    call pum#popup#_redraw()
  endif

  " Setup mode-specific autocmds for automatic closing
  if a:mode ==# 'i'
    autocmd pum InsertLeave * ++once ++nested
          \ call pum#close()
    autocmd pum TextChangedI,CursorMovedI,CursorHoldI * ++nested
          \ call pum#popup#_check_text_changed()
  elseif a:mode ==# 'c'
    autocmd pum CmdlineChanged * ++nested
          \ call pum#popup#_check_text_changed()
    if '##CursorMovedC'->exists() && !s:is_cmdline_vim_window()
      autocmd pum CursorMovedC * ++once ++nested
            \ call pum#popup#_check_cursor_moved()
    endif
    autocmd pum CmdlineLeave * ++once ++nested
          \ call pum#close()
  elseif a:mode ==# 't'
    autocmd pum ModeChanged t:* ++once ++nested
          \ call pum#close()
  endif
  autocmd pum CmdWinEnter,CmdWinLeave,CursorHold * ++once ++nested
        \ call pum#close()

  call pum#popup#_reset_auto_confirm(a:mode)
endfunction
