const s:priority_highlight_item = 2
const s:priority_highlight_column = 1
const s:priority_highlight_selected = 0
const s:priority_highlight_horizontal_separator = 1

function pum#popup#_open(startcol, items, mode, insert) abort
  " NOTE: In neovim 0.10+, floating window works in command line window
  if a:mode !~# '[ict]' || (getcmdwintype() !=# '' && !has('nvim-0.10'))
    " Invalid mode
    return -1
  endif

  " Reset
  augroup pum
    autocmd!
  augroup END
  augroup pum-temp
    autocmd!
  augroup END

  let options = pum#_options()

  " Remove dup
  let items = s:uniq_by_word_or_dup(a:items)

  " Calc max columns
  let max_columns = []
  let width = 0
  let non_abbr_length = 0
  let prev_column_length = 0
  for column in options.item_orders
    let max_column =
          \   column ==# 'space' ? 1 :
          \   column ==# 'abbr' ? items->copy()->map({ _, val ->
          \     val->get('abbr', val.word)->strdisplaywidth()
          \   })->max() :
          \   column ==# 'kind' ? items->copy()->map({ _, val ->
          \     val->get('kind', '')->strdisplaywidth()
          \   })->max() :
          \   column ==# 'menu' ? items->copy()->map({ _, val ->
          \     val->get('menu', '')->strdisplaywidth()
          \   })->max() :
          \   items->copy()->map({ _, val ->
          \     val->get('columns', {})->get(column, '')
          \     ->strdisplaywidth()
          \   })->max()

    let max_column =
          \ [max_column, options.max_columns->get(column, max_column)]->min()

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

  " Padding
  const padding = options.padding ?
        \ (a:mode ==# 'c' || a:startcol != 1) ? 2 : 1 : 0
  let width += padding
  if options.min_width > 0
    let width = [width, options.min_width]->max()
  endif
  if options.max_width > 0
    let width = [width, options.max_width]->min()
  endif

  " NOTE: abbr is the rest column
  const abbr_width = width - non_abbr_length - padding

  let lines = items->copy()
        \ ->map({ _, val ->
        \   pum#_format_item(
        \     val, options, a:mode, a:startcol, max_columns, abbr_width
        \   )
        \ })

  let pum = pum#_get()

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

  const [border_left, border_top, border_right, border_bottom]
        \ = s:get_border_size(options.border)
  let padding_height = 1 + border_top + border_bottom
  let padding_width = 1 + border_left + border_right
  let padding_left = border_left
  if options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left += 1
  endif

  let height = items->len()
  if options.max_height > 0
    let height = [height, options.max_height]->min()
  endif
  if options.min_height > 0
    let height = [height, options.min_height]->max()
  endif

  if a:mode !=# 'c'
    " Adjust to screen row
    let minheight_below = [
          \ height, &lines - spos.row - padding_height - options.offset_row
          \ ]->min()
    let minheight_above = [
          \ height, spos.row - padding_height - options.offset_row
          \ ]->min()
    if (minheight_below < minheight_above && options.direction ==# 'auto')
          \ || (minheight_above >= 1 && options.direction ==# 'above')
      " Use above window
      let spos.row -= height + padding_height
      let height = minheight_above
      const direction = 'above'
    else
      " Use below window
      let height = minheight_below
      const direction = 'below'
    endif
  else
    const direction = 'above'
    let height = [height, &lines - [&cmdheight, 1]->max()]->min()
  endif
  let height = [height, 1]->max()

  " Reversed
  const reversed = direction ==# 'above' && options.reversed
  if reversed
    let lines = lines->reverse()
    let items = items->reverse()
  endif

  " Adjust to screen col
  const rest_width = &columns - spos.col - padding_width
  if rest_width < width
    let spos.col -= width - rest_width
  endif

  " Adjust to padding
  let spos.col -= padding_left

  if spos.col <= 0
    let spos.col = 1
  endif

  let pos = a:mode ==# 'c' ?
        \ [&lines - height - [1, &cmdheight]->max() - options.offset_cmdrow,
        \  options.follow_cursor ? getcmdpos() :
        \  a:startcol - padding_left + options.offset_cmdcol] :
        \ [spos.row + (direction ==# 'above' ?
        \              -options.offset_row : options.offset_row),
        \  spos.col - 1]

  if a:mode ==# 'c'
    if '*cmdline#_get'->exists() && !cmdline#_get().pos->empty()
      const [cmdline_left, cmdline_top, cmdline_right, cmdline_bottom]
            \ = s:get_border_size(cmdline#_options().border)

      let cmdline_pos = cmdline#_get().pos->copy()
      let cmdline_pos[0] += cmdline_top + cmdline_bottom
      let cmdline_pos[1] += cmdline_left

      let pos[0] = cmdline_pos[0]
      let pos[0] += (direction ==# 'above' ?
            \        -options.offset_row : options.offset_row)

      let pos[1] += cmdline#_get().prompt->strlen() + cmdline_pos[1]
    elseif has('nvim') && pum#util#_luacheck('noice')
      " Use noice cursor
      let noice_pos = luaeval(
            \ 'require("noice").api.get_cmdline_position()').screenpos

      let noice_view = luaeval('require("noice.config").options.cmdline.view')
      if noice_view !=# 'cmdline'
        let pos[0] = noice_pos.row
        let pos[0] += (direction ==# 'above' ?
              \        -options.offset_row : options.offset_row)
      endif

      let pos[1] += noice_pos.col - 1
    else
      " Use getcmdscreenpos() for adjustment
      let pos[1] += (getcmdscreenpos() - 1) - getcmdpos()
    endif
  endif

  if options.horizontal_menu
    let pum.horizontal_menu = v:true
    let pum.cursor = 0
    let pum.items = items->copy()

    call pum#popup#_redraw_horizontal_menu()
  elseif has('nvim')
    if pum.buf < 0
      let pum.buf = nvim_create_buf(v:false, v:true)
    endif
    if pum.scroll_buf < 0
      let pum.scroll_buf = nvim_create_buf(v:false, v:true)
    endif

    call nvim_buf_set_lines(pum.buf, 0, -1, v:true, lines)

    let scroll_lines = lines->copy()->map({ _ -> options.scrollbar_char })
    call nvim_buf_set_lines(pum.scroll_buf, 0, -1, v:true, scroll_lines)

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

    " NOTE: scroll_height must be positive
    const scroll_height = [
          \ (height * ((height + 0.0) / lines->len()) + 0.5
          \ )->floor()->float2nr(), 1]->max()
    const scroll_row = pos[0] + border_top
    const scroll_col = pos[1] + width + border_right
    let scroll_winopts = #{
          \   relative: 'editor',
          \   width: options.scrollbar_char->strwidth(),
          \   height: scroll_height,
          \   row: scroll_row,
          \   col: scroll_col,
          \   anchor: 'NW',
          \   style: 'minimal',
          \   zindex: options.zindex + 1,
          \ }

    let pum.scroll_row = scroll_winopts.row
    let pum.scroll_col = scroll_winopts.col
    let pum.scroll_height = scroll_winopts.height

    if pum.id > 0
      call pum#close('complete_done', v:false)

      if pos == pum.pos
        " Resize window
        call nvim_win_set_width(pum.id, width)
        call nvim_win_set_height(pum.id, height)
      else
        " Reuse window
        call nvim_win_set_config(pum.id, winopts)
      endif
    else
      call pum#close()

      " NOTE: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      const id = nvim_open_win(pum.buf, v:false, winopts)

      call s:set_float_window_options(id, options, 'normal_menu')

      let pum.id = id
    endif

    if options.scrollbar_char !=# '' && len(lines) > height
      if pum.scroll_id > 0
        " Reuse window
        call nvim_win_set_config(pum.scroll_id, scroll_winopts)
      else
        " NOTE: It cannot set in nvim_win_set_config()
        let scroll_winopts.noautocmd = v:true

        let scroll_id = nvim_open_win(
              \ pum.scroll_buf, v:false, scroll_winopts)
        call s:set_float_window_options(scroll_id, options, 'scrollbar')

        let pum.scroll_id = scroll_id
      endif
    elseif pum.scroll_id > 0
      call pum#popup#_close_id(pum.scroll_id)
      let pum.scroll_id = -1
    endif

    let pum.pos = pos
    let pum.horizontal_menu = v:false
  else
    let winopts = #{
          \   pos: 'topleft',
          \   line: pos[0] + 1,
          \   col: pos[1] + 1,
          \   highlight: options.highlight_normal_menu,
          \   maxwidth: width,
          \   maxheight: height,
          \   scroll: options.scrollbar_char !=# '',
          \   wrap: 0,
          \   zindex: options.zindex,
          \ }

    if options.border->type() ==# v:t_string
      if options.border ==# 'double'
        let winopts.border = [2, 2, 2, 2]
      elseif options.border !=# 'none'
        let winopts.border = [1, 1, 1, 1]
      endif
    else
      let winopts.borderchars = options.border
    endif

    if pum.id > 0
      call pum#close('complete_done', v:false)

      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)
    else
      call pum#close()

      let pum.id = lines->popup_create(winopts)
      let pum.buf = pum.id->winbufnr()
    endif

    let pum.pos = pos
    let pum.horizontal_menu = v:false
  endif

  if reversed && pum.scroll_id > 0
    " The cursor must be end
    call win_execute(pum.id, 'call cursor("$", 0)')
    call pum#popup#_redraw_scroll()

    if has('nvim')
      call nvim_win_set_config(pum.scroll_id, #{
            \   relative: 'editor',
            \   row: pum.scroll_row + height - 1,
            \   col: pum.scroll_col,
            \ })
    endif
  endif

  let pum.items = items->copy()
  let pum.cursor = 0
  let pum.direction = direction
  let pum.height = height
  let pum.width = width
  let pum.border_width = border_left + border_right
  let pum.border_height = border_top + border_bottom
  let pum.len = items->len()
  let pum.reversed = reversed
  let pum.startcol = a:startcol
  let pum.startrow = pum#_row()
  let pum.current_line = '.'->getline()
  let pum.col = pum#_col()
  let pum.orig_input = pum#_getline()[a:startcol - 1 : pum#_col() - 2]
  let pum.orig_line = '.'->getline()

  if !pum.horizontal_menu
    " Highlight
    call s:highlight_items(items, max_columns)

    " Simple highlight matches
    silent! call matchdelete(pum.matched_id, pum.id)
    if options.highlight_matches !=# ''
      let pattern = pum.orig_input->escape('~"*\.^$[]')
            \ ->substitute('\w\ze.', '\0[^\0]\\{-}', 'g')
      call matchadd(
            \ options.highlight_matches, pattern, 0, pum.matched_id,
            \ #{ window: pum.id })
    endif
  endif

  if a:insert
    call pum#map#insert_relative(+1)
  elseif options.auto_select
    call pum#map#select_relative(+1)
  else
    call pum#popup#_redraw()
  endif

  " Close popup automatically
  " NOTE: ModeChanged i:[^i]* does not work well when html lsp
  autocmd pum InsertLeave * ++once ++nested
        \ call pum#close()
  autocmd pum ModeChanged [ct]:* ++once ++nested
        \ call pum#close()
  autocmd pum CmdWinEnter,CmdWinLeave * ++once ++nested
        \ call pum#close()
  autocmd pum CursorHold * ++once ++nested
        \ call pum#close()
  autocmd pum TextChangedI * ++once ++nested
        \ call pum#popup#_check_text_changed()

  call pum#popup#_reset_auto_confirm(a:mode)

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
  let pum.preview_id = -1
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
  catch /E523:\|E565:\|E5555:/
    " Ignore "Not allowed here"

    " Close the popup window later
    call timer_start(100, { -> pum#popup#_close_id(a:id) })
  endtry

  call pum#popup#_redraw()
endfunction

function pum#popup#_redraw() abort
  if mode() ==# 'c' && &incsearch
        \ && (getcmdtype() ==# '/' || getcmdtype() ==# '?')
    " Redraw without breaking 'incsearch' in search commands
    call feedkeys("\<C-r>\<BS>", 'n')
  else
    redraw
  endif
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
              \ row, start + hl.col - 1, hl.width)
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
              \ row, start, width)
      endif

      let start += width
    endfor
  endfor
endfunction

function s:highlight(highlight, prop_type, priority, row, col, length) abort
  let pum = pum#_get()

  let col = a:col
  if pum#_options().padding && (mode() ==# 'c' || pum.startcol != 1)
    let col += 1
  endif

  if has('nvim')
    return nvim_buf_set_extmark(
          \ pum.buf, pum.namespace, a:row - 1, col - 1, #{
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
          \   bufnr: pum.buf,
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
        \ pum#_options().highlight_selected,
        \ prop_type,
        \ s:priority_highlight_selected,
        \ pum.cursor, col, length)
endfunction

function pum#popup#_redraw_horizontal_menu() abort
  let pum = pum#_get()

  if pum.items->empty()
    call pum#close()
    return
  endif

  " Adjust cursor
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

  " Adjust height
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

  if options.min_height > 0
    let height = [height, options.min_height]->max()
  endif

  const [border_left, border_top, border_right, border_bottom]
        \ = s:get_border_size(options.border)
  let padding_height = 1 + border_top + border_bottom
  let padding_width = 1 + border_left + border_right
  let padding_left = border_left
  if options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left += 1
  endif

  if !has('nvim') && mode() ==# 't'
    const cursor = bufnr('%')->term_getcursor()
    let spos = #{ row: cursor[0], col: '.'->col() }
  else
    let spos = screenpos(0, '.'->line(), '.'->col())
  endif

  if mode() !=# 'c'
    " Adjust to screen row
    let minheight_below = [
          \ height, &lines - spos.row - padding_height - options.offset_row
          \ ]->min()
    let minheight_above = [
          \ height, spos.row - padding_height - options.offset_row
          \ ]->min()
    if (minheight_below < minheight_above && options.direction ==# 'auto')
          \ || (minheight_above >= 1 && options.direction ==# 'above')
      " Use above window
      const direction = 'above'
    else
      " Use below window
      const direction = 'below'
    endif
  else
    const direction = 'above'
  endif

  let width = lines->copy()->map({ _, val -> val->strwidth() })->max()
  if options.min_width > 0
    let width = [width, options.min_width]->max()
  endif
  if options.max_width > 0
    let width = [width, options.max_width]->min()
  endif

  let pos = mode() ==# 'c' ?
        \ [&lines - height - [1, &cmdheight]->max() - options.offset_cmdrow,
        \  options.follow_cursor ? getcmdpos() + options.offset_cmdcol :
        \  options.offset_cmdcol] :
        \ [spos.row + (direction ==# 'above' ?
        \              -options.offset_row - height - 1 : options.offset_row),
        \  options.follow_cursor ? spos.col - 1 + options.offset_col :
        \  options.offset_col]

  if mode() ==# 'c'
    if '*cmdline#_get'->exists() && !cmdline#_get().pos->empty()
      const [cmdline_left, cmdline_top, cmdline_right, cmdline_bottom]
            \ = s:get_border_size(cmdline#_options().border)

      let cmdline_pos = cmdline#_get().pos->copy()
      let cmdline_pos[0] += cmdline_top + cmdline_bottom
      let cmdline_pos[1] += cmdline_left

      let pos[0] = cmdline_pos[0]
      let pos[0] += (direction ==# 'above' ?
            \        -options.offset_row : options.offset_row)

      let pos[1] += cmdline#_get().prompt->strlen() + cmdline_pos[1]
    elseif has('nvim') && pum#util#_luacheck('noice')
      " Use noice cursor
      let noice_pos = luaeval(
            \ 'require("noice").api.get_cmdline_position()').screenpos

      let noice_view = luaeval('require("noice.config").options.cmdline.view')
      if noice_view !=# 'cmdline'
        let pos[0] = noice_pos.row
        let pos[0] += (direction ==# 'above' ?
              \        -options.offset_row : options.offset_row)
      endif

      let pos[1] += noice_pos.col - 1
    else
      " Use getcmdscreenpos() for adjustment
      let pos[1] += (getcmdscreenpos() - 1) - getcmdpos()
    endif
  endif

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

  if pum.cursor > 0
    " Highlight the first item
    call s:highlight(
          \ options.highlight_selected,
          \ 'pum_highlight_selected',
          \ s:priority_highlight_selected,
          \ 1, 1, items[0]->get('abbr', items[0].word)->strlen())
  endif
  if separator
    call s:highlight(
          \ options.highlight_horizontal_separator,
          \ 'pum_highlight_separator',
          \ s:priority_highlight_selected,
          \ 1, items[0]->get('abbr', items[0].word)->strlen() + 2, 1)
  endif

  call pum#popup#_redraw()
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
function s:open_preview() abort
  let pum = pum#_get()

  if pum.cursor <= 0
    call pum#popup#_close_preview()
    return
  endif

  const item = pum#current_item()

  " Get preview contents
  const previewer = s:get_previewer(item)
  if previewer->has_key('contents') && previewer.contents->empty()
    call pum#popup#_close_preview()
    return
  endif

  const options = pum#_options()

  const pos = pum#get_pos()
  if pos->empty()
    return
  endif
  const row = pos.row + 1
  const col = pos.col + pos.width + 2

  if previewer->has_key('contents')
    let width = previewer.contents
          \ ->copy()->map({ _, val -> val->strwidth() })->max()
    let height = previewer.contents->len()
    let width = [width, options.preview_width]->min()
    let height = [height, options.preview_height]->min()
  else
    let width = options.preview_width
    let height = options.preview_height
  endif
  " NOTE: Must be positive
  let width = [20, width]->max()
  let height = [1, height]->max()

  if has('nvim')
    if pum.preview_buf < 0
      let pum.preview_buf = nvim_create_buf(v:false, v:true)
    endif

    if previewer->has_key('contents')
      call setbufvar(pum.preview_buf, '&modifiable', v:true)
      call setbufvar(pum.preview_buf, '&readonly', v:false)
      call nvim_buf_set_lines(
            \ pum.preview_buf, 0, -1, v:true, previewer.contents)
      call setbufvar(pum.preview_buf, '&modified', v:false)
    endif

    let winopts = #{
          \   border: options.preview_border,
          \   relative: 'editor',
          \   row: row - 1,
          \   col: col - 1,
          \   width: width,
          \   height: height,
          \   anchor: 'NW',
          \   style: 'minimal',
          \   zindex: options.zindex + 1,
          \ }

    if pum.preview_id > 0
      " Reuse window
      call nvim_win_set_config(pum.preview_id, winopts)
    else
      call pum#popup#_close_preview()

      " NOTE: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      const id = nvim_open_win(
            \ pum.preview_buf, v:false, winopts)

      call s:set_float_window_options(id, options, 'preview')

      let pum.preview_id = id
    endif

    if previewer.kind ==# 'help'
      try
        call win_execute(pum.preview_id,
              \ 'setlocal buftype=help | help ' .. previewer.tag)
      catch
        call pum#popup#_close_preview()
        return
      endtry
    endif
  else
    let winopts = #{
          \   pos: 'topleft',
          \   line: row,
          \   col: col,
          \   maxwidth: width,
          \   maxheight: height,
          \   highlight: options.highlight_preview,
          \ }

    if previewer.kind ==# 'help'
      call pum#popup#_close_preview()

      try
        " Create dummy help buffer
        " NOTE: ":help" does not work in popup window.
        execute 'help' previewer.tag
        const help_bufnr = bufnr()
        const firstline = '.'->line()
        helpclose
      catch
        call pum#popup#_close_preview()
        return
      endtry

      " Set firstline to display tag
      let winopts.firstline = firstline

      let pum.preview_id = popup_create(help_bufnr, winopts)
      let pum.preview_buf = help_bufnr
    elseif pum.preview_id > 0
      call popup_move(pum.preview_id, winopts)
      if previewer->has_key('contents')
        call popup_settext(pum.preview_id, previewer.contents)
      endif
    else
      if previewer->has_key('contents')
        let pum.preview_id = popup_create(previewer.contents, winopts)
      else
        let pum.preview_id = popup_create([], winopts)
      endif
      let pum.preview_buf = pum.preview_id->winbufnr()
    endif
  endif

  if previewer->has_key('command')
    try
      call win_execute(pum.preview_id, previewer.command)
    catch
      call pum#popup#_close_preview()
      return
    endtry
  endif

  if previewer.kind ==# 'markdown'
    call setbufvar(pum.preview_buf, '&filetype', 'markdown')
  endif
  call setbufvar(pum.preview_buf, '&wrap', v:true)

  call pum#popup#_redraw()
endfunction
function pum#popup#_close_preview() abort
  let pum = pum#_get()

  if pum.preview_id < 0
    return
  endif

  call pum#popup#_close_id(pum.preview_id)

  let pum.preview_id = -1
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
  if !'s:prev_line'->exists()
    let s:prev_line = pum#_getline()
  endif

  let pum = pum#_get()
  const current_line = pum#_getline()
  if pum.skip_complete
    let s:prev_line = current_line
    return
  endif

  if pum#_row() != pum.startrow || current_line !=# s:prev_line
        \ || ('g:skkeleton#mode'->exists() && g:skkeleton#mode !=# '')
    call pum#close()
  endif
  let s:prev_line = current_line
endfunction

function s:set_float_window_options(id, options, highlight) abort
  let highlight = 'NormalFloat:' .. a:options['highlight_' .. a:highlight]
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
