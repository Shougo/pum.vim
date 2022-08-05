let s:pum_matched_id = 70

function! pum#popup#_open(startcol, items, mode) abort
  if a:mode !~# '[ict]' || bufname('%') ==# '[Command Line]'
    " Invalid mode
    return -1
  endif

  let options = pum#_options()

  " Remove dup
  let items = s:uniq_by_word_or_dup(a:items)

  let max_abbr = max(map(copy(items), { _, val ->
        \ strdisplaywidth(get(val, 'abbr', val.word))
        \ }))
  let max_kind = max(map(copy(items), { _, val ->
        \ strdisplaywidth(get(val, 'kind', ''))
        \ }))
  let max_menu = max(map(copy(items), { _, val ->
        \ strdisplaywidth(get(val, 'menu', ''))
        \ }))
  let lines = map(copy(items), { _, val ->
        \   pum#_format_item(val, options, a:mode, a:startcol,
        \                    max_abbr, max_kind, max_menu)
        \ })

  let pum = pum#_get()

  " Calc width
  let width = max_abbr + max_kind + max_menu
  " Padding
  if max_kind != 0
    let width += 1
  endif
  if max_menu != 0
    let width += 1
  endif
  if options.padding && a:startcol != 1
    let width += 2
  endif
  if options.min_width > 0
    let width = max([width, options.min_width])
  endif
  if options.max_width > 0
    let width = min([width, options.max_width])
  endif

  if !has('nvim') && a:mode ==# 't'
    let cursor = term_getcursor(bufnr('%'))
    let spos = { 'row': cursor[0], 'col': a:startcol }
  else
    let spos = screenpos(0, line('.'), a:startcol)
  endif

  let [border_left, border_top, border_right, border_bottom] =
        \ s:get_border_size(options.border)
  let padding_height = 1 + border_top + border_bottom
  let padding_width = 1 + border_left + border_right
  let padding_left = border_left
  if options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left += 1
  endif

  let height = len(items)
  if &pumheight > 0
    let height = min([height, &pumheight])
  else
    let height = min([height, &lines - 1])
  endif

  if a:mode !=# 'c'
    " Adjust to screen row
    let minheight_below = min([height, &lines - spos.row - padding_height])
    let minheight_above = min([height, spos.row - padding_height])
    if minheight_below < minheight_above ||
          \ (minheight_above >= 1 && options.reversed)
      " Use above window
      let spos.row -= height + padding_height
      let height = minheight_above
      let direction = 'above'
    else
      " Use below window
      let height = minheight_below
      let direction = 'below'
    endif
  else
    let direction = 'above'
  endif
  let height = max([height, 1])

  " Reversed
  let reversed = direction ==# 'above' && options.reversed
  if reversed
    let lines = reverse(lines)
    let items = reverse(items)
  endif

  " Adjust to screen col
  let rest_width = &columns - spos.col - padding_width
  if rest_width < width
    let spos.col -= width - rest_width
  endif

  " Adjust to padding
  let spos.col -= padding_left

  if spos.col <= 0
    let spos.col = 1
  endif

  " NOTE: In Vim8, floating window must above of status line
  let pos = a:mode ==# 'c' ?
        \ [&lines - height - max([1, &cmdheight]) - options.offset,
        \  a:startcol - padding_left] :
        \ [spos.row, spos.col - 1]

  if a:mode ==# 'c' && exists('*getcmdscreenpos')
    " Use getcmdscreenpos() for adjustment
    let pos[1] += (getcmdscreenpos() - 1) - getcmdpos()
  endif

  if options.horizontal_menu && a:mode ==# 'i'
    let pum.horizontal_menu = v:true
    let pum.cursor = 0

    call pum#_redraw_horizontal_menu()
  elseif has('nvim')
    if pum.buf < 0
      let pum.buf = nvim_create_buf(v:false, v:true)
    endif
    if pum.scroll_buf < 0
      let pum.scroll_buf = nvim_create_buf(v:false, v:true)
    endif

    call nvim_buf_set_lines(pum.buf, 0, -1, v:true, lines)

    let scroll_lines = map(copy(lines), { _ -> options.scrollbar_char })
    call nvim_buf_set_lines(pum.scroll_buf, 0, -1, v:true, scroll_lines)

    let winopts = {
          \ 'border': options.border,
          \ 'relative': 'editor',
          \ 'width': width,
          \ 'height': height,
          \ 'row': pos[0],
          \ 'col': pos[1],
          \ 'anchor': 'NW',
          \ 'style': 'minimal',
          \ 'zindex': options.zindex,
          \ }

    let scroll_height = float2nr(
          \ height * ((height + 0.0) / len(lines)) + 0.5)
    " NOTE: scroll_height must be positive
    let scroll_height = max([scroll_height, 1])

    let scroll_row = pos[0]
    let scroll_col = pos[1] + width
    let scroll_winopts = {
          \ 'relative': 'editor',
          \ 'width': strwidth(options.scrollbar_char),
          \ 'height': scroll_height,
          \ 'row': scroll_row,
          \ 'col': scroll_col,
          \ 'anchor': 'NW',
          \ 'style': 'minimal',
          \ 'zindex': options.zindex + 1,
          \ }
    let pum.scroll_row = scroll_row
    let pum.scroll_col = scroll_col

    if pum.id > 0
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
      let id = nvim_open_win(pum.buf, v:false, winopts)

      " NOTE: nvim_win_set_option() causes title flicker...
      " Disable 'hlsearch' highlight
      call nvim_win_set_option(id, 'winhighlight',
            \ printf('Normal:%s,Search:None', options.highlight_normal_menu))
      call nvim_win_set_option(id, 'winblend', &l:pumblend)
      call nvim_win_set_option(id, 'wrap', v:false)
      call nvim_win_set_option(id, 'scrolloff', 0)
      call nvim_win_set_option(id, 'statusline', &l:statusline)

      let pum.id = id
    endif

    if options.scrollbar_char !=# '' && len(lines) > height
      if pum.scroll_id > 0
        " Reuse window
        call nvim_win_set_config(pum.scroll_id, scroll_winopts)
      else
        let scroll_id = nvim_open_win(
              \ pum.scroll_buf, v:false, scroll_winopts)
        call nvim_win_set_option(scroll_id, 'winhighlight',
              \ printf('Normal:%s,NormalFloat:None',
              \        options.highlight_scroll_bar))
        call nvim_win_set_option(scroll_id, 'winblend', &l:pumblend)
        call nvim_win_set_option(scroll_id, 'statusline', &l:statusline)

        let pum.scroll_id = scroll_id
      endif
    elseif pum.scroll_id > 0
      call pum#popup#_close_id(pum.scroll_id)
      let pum.scroll_id = -1
    endif

    let pum.pos = pos
    let pum.horizontal_menu = v:false
  else
    let winopts = {
          \ 'pos': 'topleft',
          \ 'line': pos[0] + 1,
          \ 'col': pos[1] + 1,
          \ 'highlight': options.highlight_normal_menu,
          \ 'maxwidth': width,
          \ 'maxheight': height,
          \ 'scroll': options.scrollbar_char !=# '',
          \ 'wrap': 0,
          \ 'zindex': options.zindex,
          \ }

    if pum.id > 0
      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)

      if pum.scroll_id > 0
        call popup_move(pum.scroll_id, scroll_winopts)
        call popup_settext(pum.scroll_id, scroll_lines)
      endif
    else
      let pum.id = popup_create(lines, winopts)
      let pum.buf = winbufnr(pum.id)
    endif

    let pum.pos = pos
    let pum.horizontal_menu = v:false
  endif

  if reversed
    " The cursor must be end
    call win_execute(pum.id, 'call cursor("$", 0) | redraw')
  endif

  let pum.items = copy(items)
  let pum.cursor = 0
  let pum.direction = direction
  let pum.height = height
  let pum.width = width
  let pum.border_width = border_left + border_right
  let pum.border_height = border_top + border_bottom
  let pum.len = len(items)
  let pum.reversed = reversed
  let pum.startcol = a:startcol
  let pum.startrow = s:row()
  let pum.current_line = getline('.')
  let pum.col = pum#_col()
  let pum.orig_input = pum#_getline()[a:startcol - 1 : pum#_col() - 2]
  let pum.orig_line = getline('.')

  " Clear current highlight
  silent! call matchdelete(pum#_cursor_id(), pum.id)

  if !pum.horizontal_menu
    " Highlight
    call s:highlight_items(
          \ items, options.item_orders, max_abbr, max_kind, max_menu)

    " Simple highlight matches
    silent! call matchdelete(s:pum_matched_id, pum.id)
    if options.highlight_matches !=# ''
      let pattern = substitute(escape(pum.orig_input, '~"*\.^$[]'),
            \ '\w\ze.', '\0[^\0]\\{-}', 'g')
      call matchadd(
            \ options.highlight_matches, pattern, 0, s:pum_matched_id,
            \ { 'window': pum.id })
    endif
  endif

  if &completeopt =~# 'noinsert'
    call pum#map#select_relative(+1)
  elseif a:mode ==# 'c'
    " NOTE: :redraw is needed for command line completion
    if &incsearch && (getcmdtype() ==# '/' || getcmdtype() ==# '?')
      " Redraw without breaking 'incsearch' in search commands
      call feedkeys("\<C-r>\<BS>", 'n')
    endif
  endif

  " NOTE: redraw is needed for Vim8 or command line mode
  if !has('nvim') || a:mode ==# 'c'
    redraw
  endif

  augroup pum
    autocmd!
  augroup END

  " Close popup automatically
  if exists('##ModeChanged')
    autocmd pum ModeChanged i:[^i]* ++once call pum#close()
    autocmd pum ModeChanged [ct]:* ++once call pum#close()
  elseif a:mode ==# 'i'
    autocmd pum InsertLeave * ++once call pum#close()
    autocmd pum CursorMovedI *
          \ if pum#_get().current_line ==# getline('.')
          \    && pum#_get().col !=# pum#_col() | call pum#close() | endif
  elseif a:mode ==# 'c'
    autocmd pum WinEnter,CmdlineLeave * ++once call pum#close()
  elseif a:mode ==# 't' && exists('##TermEnter')
    autocmd pum TermEnter,TermLeave * ++once call pum#close()
  endif
  autocmd pum CursorHold * ++once call pum#close()

  return pum.id
endfunction

function! pum#popup#_close(id) abort
  if a:id <= 0
    return
  endif

  " Reset
  augroup pum
    autocmd!
  augroup END

  let pum = pum#_get()
  let pum.current_word = ''
  let pum.id = -1
  let pum.scroll_id = -1

  let g:pum#completed_item = {}

  call pum#popup#_close_id(a:id)
endfunction
function! pum#popup#_close_id(id) abort
  try
    " Move cursor
    call win_execute(a:id, 'call cursor(1, 0)')

    " NOTE: popup may be already closed
    " Close popup and clear highlights
    if has('nvim')
      let pum = pum#_get()

      if pum.horizontal_menu
        call nvim_buf_clear_namespace(0, g:pum#_namespace, 0, -1)
      else
        call nvim_buf_clear_namespace(pum.buf, g:pum#_namespace, 1, -1)

        call nvim_win_close(a:id, v:true)
      endif
    else
      " NOTE: prop_remove() is not needed.
      " popup_close() removes the buffer.
      call popup_close(a:id)
    endif
  catch /E523:\|E565:\|E5555:/
    " Ignore "Not allowed here"

    " Close the popup window later
    call timer_start(10, { -> pum#popup#_close_id(a:id) })
  endtry

  " NOTE: redraw is needed for Vim8 or command line mode
  if !has('nvim') || mode() ==# 'c'
    redraw
  endif
endfunction

function! s:uniq_by_word_or_dup(items) abort
  let ret = []
  let seen = {}
  for item in a:items
    let key = item.word
    if !has_key(seen, key) || get(item, 'dup', 0)
      let seen[key] = v:true
      call add(ret, item)
    endif
  endfor
  return ret
endfunction

" returns [border_left, border_top, border_right, border_bottom]
function! s:get_border_size(border) abort
  if !has('nvim')
    " NOTE: Vim is not supported
    return [0, 0, 0, 0]
  elseif type(a:border) == v:t_string
    return a:border ==# 'none' ? [0, 0, 0, 0] : [1, 1, 1, 1]
  elseif type(a:border) == v:t_list && !empty(a:border)
    return [s:get_borderchar_width(a:border[3 % len(a:border)]),
          \ s:get_borderchar_height(a:border[1 % len(a:border)]),
          \ s:get_borderchar_width(a:border[7 % len(a:border)]),
          \ s:get_borderchar_height(a:border[5 % len(a:border)])]
  else
    return [0, 0, 0, 0]
  endif
endfunction

function! s:get_borderchar_height(ch) abort
  if type(a:ch) == v:t_string
    " character
    return empty(a:ch) ? 0 : 1
  elseif type(a:ch) == v:t_list && !empty(a:ch) && type(a:ch[0]) == v:t_string
    " character with highlight: [ch, highlight]
    return empty(a:ch[0]) ? 0 : 1
  else
    call pum#util#_print_error('invalid border character: %s', a:ch)
    return 0
  endif
endfunction

function! s:get_borderchar_width(ch) abort
  if type(a:ch) == v:t_string
    " character
    return strdisplaywidth(a:ch)
  elseif type(a:ch) == v:t_list && !empty(a:ch) && type(a:ch[0]) == v:t_string
    " character with highlight: [ch, highlight]
    return strdisplaywidth(a:ch[0])
  else
    call pum#util#_print_error('invalid border character: %s', a:ch)
    return 0
  endif
endfunction

function! s:row() abort
  let row = mode() ==# 't' && !has('nvim') ?
        \ term_getcursor(bufnr('%'))[0] :
        \ line('.')
  return row
endfunction

function! s:highlight_items(items, orders, max_abbr, max_kind, max_menu) abort
  let pum = pum#_get()
  let options = pum#_options()

  for row in range(1, len(a:items))
    " Default highlights

    let item = a:items[row - 1]
    let item_highlights = get(item, 'highlights', [])

    let start = 1
    for order in a:orders
      if order ==# 'abbr' && a:max_abbr != 0
        if options.highlight_abbr !=# ''
          call s:highlight(
                \ options.highlight_abbr, 'pum_abbr', 0,
                \ g:pum#_namespace, row, start, a:max_abbr + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'abbr'})
          call s:highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_abbr + 1
      elseif order ==# 'kind' && a:max_kind != 0
        if options.highlight_kind !=# ''
          call s:highlight(
                \ options.highlight_kind, 'pum_kind', 0,
                \ g:pum#_namespace, row, start, a:max_kind + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'kind'})
          call s:highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_kind + 1
      elseif order ==# 'menu' && a:max_menu != 0
        if options.highlight_menu !=# ''
          call s:highlight(
                \ options.highlight_menu, 'pum_menu', 0,
                \ g:pum#_namespace, row, start, a:max_menu + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'menu'})
          call s:highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_menu + 1
      endif
    endfor
  endfor
endfunction

function! s:highlight(highlight, prop_type, priority, id, row, col, length) abort
  let pum = pum#_get()

  let col = a:col
  if pum#_options().padding && pum.startcol != 1
    let col += 1
  endif

  if !has('nvim')
    " Add prop_type
    if empty(prop_type_get(a:prop_type))
      call prop_type_add(a:prop_type, {
            \ 'highlight': a:highlight,
            \ 'priority': a:priority,
            \ })
    endif
  endif

  if has('nvim')
    call nvim_buf_add_highlight(
          \ pum.buf,
          \ a:id,
          \ a:highlight,
          \ a:row - 1,
          \ col - 1,
          \ col - 1 + a:length
          \ )
  else
    call prop_add(a:row, col, {
          \ 'length': a:length,
          \ 'type': a:prop_type,
          \ 'bufnr': pum.buf,
          \ 'id': a:id,
          \ })
  endif
endfunction
