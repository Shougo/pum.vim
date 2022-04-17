let g:pum#_namespace = has('nvim') ? nvim_create_namespace('pum') : 0
let g:pum#completed_item = {}
let s:pum_matched_id = 70
let s:pum_cursor_id = 50


function! pum#_get() abort
  if !exists('s:pum')
    call pum#_init()
  endif
  return s:pum
endfunction
function! pum#_init() abort
  if exists('s:pum')
    call pum#close()
  endif

  let s:pum = {
        \ 'buf': -1,
        \ 'items': [],
        \ 'cursor': -1,
        \ 'current_word': '',
        \ 'height': -1,
        \ 'horizontal_menu': v:false,
        \ 'id': -1,
        \ 'len': 0,
        \ 'orig_input': '',
        \ 'pos': [],
        \ 'skip_complete': v:false,
        \ 'startcol': -1,
        \ 'startrow': -1,
        \ 'width': -1,
        \}
endfunction
function! pum#_options() abort
  if !exists('s:options')
    let s:options = {
          \ 'border': 'none',
          \ 'highlight_abbr': '',
          \ 'highlight_horizontal_menu': '',
          \ 'highlight_kind': '',
          \ 'highlight_matches': '',
          \ 'highlight_menu': '',
          \ 'highlight_normal_menu': 'Pmenu',
          \ 'highlight_selected': 'PmenuSel',
          \ 'horizontal_menu': v:false,
          \ 'item_orders': ['abbr', 'kind', 'menu'],
          \ 'max_horizontal_items': 3,
          \ 'offset': has('nvim') ? 0 : 1,
          \ 'padding': v:false,
          \ 'reversed': v:false,
          \ 'setline_insert': v:false,
          \ }
  endif
  return s:options
endfunction

function! pum#set_option(key_or_dict, ...) abort
  let dict = s:normalize_key_or_dict(a:key_or_dict, get(a:000, 0, ''))
  call extend(pum#_options(), dict)
endfunction

function! pum#open(startcol, items, ...) abort
  if !has('patch-8.2.1978') && !has('nvim-0.5')
    call s:print_error(
          \ 'pum.vim requires Vim 8.2.1978+ or neovim 0.5.0+.')
    return -1
  endif

  if empty(a:items)
    call pum#close()
    return
  endif

  try
    return s:open(a:startcol, a:items, get(a:000, 0, mode()))
  catch /E523:/
    " Ignore "Not allowed here"
    return -1
  endtry
endfunction
function! s:open(startcol, items, mode) abort
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
  if &pumwidth > 0
    let width = max([width, &pumwidth])
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

  " Note: In Vim8, floating window must above of status line
  let pos = a:mode ==# 'c' ?
        \ [&lines - height - max([1, &cmdheight]) - options.offset,
        \  a:startcol - padding_left] :
        \ [spos.row, spos.col - 1]

  if options.horizontal_menu && a:mode ==# 'i'
    let pum.horizontal_menu = v:true
    let pum.cursor = 0

    call pum#_redraw_horizontal_menu()
  elseif has('nvim')
    if pum.buf < 0
      let pum.buf = nvim_create_buf(v:false, v:true)
    endif
    call nvim_buf_set_lines(pum.buf, 0, -1, v:true, lines)

    let winopts = {
          \ 'border': options.border,
          \ 'relative': 'editor',
          \ 'width': width,
          \ 'height': height,
          \ 'col': pos[1],
          \ 'row': pos[0],
          \ 'anchor': 'NW',
          \ 'style': 'minimal',
          \ 'zindex': 100,
          \ }

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

      " Note: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      let id = nvim_open_win(pum.buf, v:false, winopts)

      " Note: nvim_win_set_option() causes title flicker...
      " Disable 'hlsearch' highlight
      call nvim_win_set_option(id, 'winhighlight',
            \ printf('Normal:%s,Search:None', options.highlight_normal_menu))
      call nvim_win_set_option(id, 'winblend', &l:winblend)
      call nvim_win_set_option(id, 'wrap', v:false)
      call nvim_win_set_option(id, 'scrolloff', 0)
      call nvim_win_set_option(id, 'statusline', &l:statusline)

      let pum.id = id
    endif

    let pum.pos = pos
    let pum.horizontal_menu = v:false
  else
    let winopts = {
          \ 'pos': 'topleft',
          \ 'line': reversed ? len(items) : pos[0] + 1,
          \ 'col': pos[1] + 1,
          \ 'highlight': options.highlight_normal_menu,
          \ 'maxwidth': width,
          \ 'maxheight': height,
          \ 'wrap': 0,
          \ }

    if pum.id > 0
      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)
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
  let pum.len = len(items)
  let pum.reversed = reversed
  let pum.startcol = a:startcol
  let pum.startrow = s:row()
  let pum.current_line = getline('.')
  let pum.col = pum#_col()
  let pum.orig_input = pum#_getline()[a:startcol - 1 : pum#_col() - 2]

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
    " Note: :redraw is needed for command line completion
    if &incsearch && (getcmdtype() ==# '/' || getcmdtype() ==# '?')
      " Redraw without breaking 'incsearch' in search commands
      call feedkeys("\<C-r>\<BS>", 'n')
    endif
  endif

  " Note: redraw is needed for Vim8 or command line mode
  if !has('nvim') || a:mode ==# 'c'
    redraw
  endif

  augroup pum
    autocmd!
  augroup END

  " Close popup automatically
  if exists('##ModeChanged')
    autocmd pum ModeChanged * ++once call pum#close()
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

function! pum#close() abort
  call s:complete_done()

  try
    return s:close()
  catch /E523:\|E5555:/
    " Ignore "Not allowed here"
    return -1
  endtry
endfunction
function! s:close() abort
  let pum = pum#_get()

  if pum.id <= 0
    return
  endif

  " Note: popup may be already closed
  " Close popup and clear highlights
  if has('nvim')
    if pum.horizontal_menu
      call nvim_buf_clear_namespace(0, g:pum#_namespace, 0, -1)
    else
      call nvim_win_close(pum.id, v:true)
      call nvim_buf_clear_namespace(pum.buf, g:pum#_namespace, 1, -1)
    endif
  else
    " Note: prop_remove() is not needed.
    " popup_close() removes the buffer.
    call popup_close(pum.id)
  endif

  " Note: redraw is needed for Vim8 or command line mode
  if !has('nvim') || mode() ==# 'c'
    redraw
  endif

  augroup pum
    autocmd!
  augroup END

  let pum.current_word = ''
  let pum.id = -1

  let g:pum#completed_item = {}
endfunction

function! pum#visible() abort
  return pum#_get().id > 0
endfunction

function! pum#complete_info(...) abort
  let pum = pum#_get()
  let info =  {
        \ 'mode': '',
        \ 'pum_visible': pum#visible(),
        \ 'items': pum.items,
        \ 'selected': pum.cursor - 1,
        \ 'inserted': pum.current_word,
        \ }

  if a:0 == 0 || type(a:1) != v:t_list
    return info
  endif

  let ret = {}
  for what in filter(copy(a:1), { _, val -> has_key(info, val) })
    let ret[what] = info[what]
  endfor

  return ret
endfunction

function! pum#get_pos() abort
  if !pum#visible()
    return {}
  endif

  let pum = pum#_get()
  return {
        \ 'height': pum.height,
        \ 'width': pum.width,
        \ 'row': pum.pos[0],
        \ 'col': pum.pos[1],
        \ 'size': pum.len,
        \ 'scrollbar': v:false,
        \ }
endfunction

function! pum#skip_complete() abort
  return pum#_get().skip_complete
endfunction

function! pum#_getline() abort
  return mode() ==# 'c' ? getcmdline() :
        \ mode() ==# 't' && !has('nvim') ? term_getline('', '.') :
        \ getline('.')
endfunction
function! s:row() abort
  let row = mode() ==# 't' && !has('nvim') ?
        \ term_getcursor(bufnr('%'))[0] :
        \ line('.')
  return row
endfunction
function! pum#_col() abort
  let col = mode() ==# 't' && !has('nvim') ?
        \ term_getcursor(bufnr('%'))[1] :
        \ mode() ==# 'c' ? getcmdpos() :
        \ mode() ==# 't' ? col('.') : col('.')
  return col
endfunction

function! pum#_highlight(
      \ highlight, prop_type, priority, id, row, col, length) abort
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

function! pum#_cursor_id() abort
  return s:pum_cursor_id
endfunction

function! pum#_redraw_horizontal_menu() abort
  let pum = pum#_get()

  if empty(pum.items)
    return
  endif

  if pum.cursor == 0
    let items = copy(pum.items)
  else
    let cursor = pum.cursor - 1
    let items = [pum.items[cursor]]
    let items += pum.items[cursor + 1:]
    if cursor > 0
      let items += pum.items[: cursor - 1]
    endif
  endif

  let max_items = pum#_options().max_horizontal_items

  if len(pum.items) > max_items
    let items = items[: max_items - 1]
  endif

  let word = printf('{ %s%s%s}',
        \ pum.cursor == 0 ? '' : '> ',
        \ join(map(items, { _, val -> get(val, 'abbr', val.word) })),
        \ len(pum.items) <= max_items ? '' : ' ... ',
        \ )

  let options = pum#_options()

  if has('nvim')
    call nvim_buf_clear_namespace(0, g:pum#_namespace, 0, -1)

    call nvim_buf_set_extmark(
          \ 0, g:pum#_namespace, line('.') - 1, 0, {
          \ 'virt_text': [[word, options.highlight_horizontal_menu]],
          \ 'hl_mode': 'combine',
          \ 'priority': 0,
          \ })

    " Dummy
    let pum.id = 1000
  else
    let winopts = {
          \ 'pos': 'topleft',
          \ 'line': line('.'),
          \ 'col': col('.') + 3,
          \ 'highlight': options.highlight_horizontal_menu,
          \ }
    let lines = [word]

    if pum.id > 0
      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)
    else
      let pum.id = popup_create(lines, winopts)
      let pum.buf = winbufnr(pum.id)
    endif
  endif
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
          call pum#_highlight(
                \ options.highlight_abbr, 'pum_abbr', 0,
                \ g:pum#_namespace, row, start, a:max_abbr + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'abbr'})
          call pum#_highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_abbr + 1
      elseif order ==# 'kind' && a:max_kind != 0
        if options.highlight_kind !=# ''
          call pum#_highlight(
                \ options.highlight_kind, 'pum_kind', 0,
                \ g:pum#_namespace, row, start, a:max_kind + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'kind'})
          call pum#_highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_kind + 1
      elseif order ==# 'menu' && a:max_menu != 0
        if options.highlight_menu !=# ''
          call pum#_highlight(
                \ options.highlight_menu, 'pum_menu', 0,
                \ g:pum#_namespace, row, start, a:max_menu + 1)
        endif

        for hl in filter(copy(item_highlights),
              \ {_, val -> val.type ==# 'menu'})
          call pum#_highlight(
                \ hl.hl_group, hl.name, 1,
                \ g:pum#_namespace, row, start + hl.col, hl.width)
        endfor

        let start += a:max_menu + 1
      endif
    endfor
  endfor
endfunction

function! pum#_format_item(
      \ item, options, mode, startcol, max_abbr, max_kind, max_menu) abort
  let abbr = substitute(get(a:item, 'abbr', a:item.word),
        \ '[[:cntrl:]]', '?', 'g')
  let abbr .= repeat(' ' , a:max_abbr - strdisplaywidth(abbr))

  let kind = get(a:item, 'kind', '')
  let kind .= repeat(' ' , a:max_kind - strdisplaywidth(kind))

  let menu = get(a:item, 'menu', '')
  let menu .= repeat(' ' , a:max_menu - strdisplaywidth(menu))

  let str = ''
  for order in a:options.item_orders
    if order ==# 'abbr' && a:max_abbr != 0
      if str !=# ''
        let str .= ' '
      endif
      let str .= abbr
    elseif order ==# 'kind' && a:max_kind != 0
      if str !=# ''
        let str .= ' '
      endif
      let str .= kind
    elseif order ==# 'menu' && a:max_menu != 0
      if str !=# ''
        let str .= ' '
      endif
      let str .= menu
    endif
  endfor

  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let str = ' ' . str . ' '
  endif

  return str
endfunction

function! s:print_error(string) abort
  echohl Error
  echomsg printf('[pum] %s', type(a:string) ==# v:t_string ?
        \ a:string : string(a:string))
  echohl None
endfunction

function! s:normalize_key_or_dict(key_or_dict, value) abort
  if type(a:key_or_dict) == v:t_dict
    return a:key_or_dict
  elseif type(a:key_or_dict) == v:t_string
    let base = {}
    let base[a:key_or_dict] = a:value
    return base
  endif
  return {}
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
    " Note: Vim is not supported
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
    call s:print_error('invalid border character: %s', a:ch)
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
    call s:print_error('invalid border character: %s', a:ch)
    return 0
  endif
endfunction

function! s:complete_done() abort
  let pum = pum#_get()

  call pum#_reset_skip_complete()

  if pum.cursor <= 0 || pum.current_word ==# ''
        \ || len(pum.items) < pum.cursor
    return
  endif

  let g:pum#completed_item = pum.items[pum.cursor - 1]
  if exists('#User#PumCompleteDone')
    doautocmd <nomodeline> User PumCompleteDone
  endif
endfunction

function! pum#_reset_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:false
endfunction
