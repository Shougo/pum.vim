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
          \ 'max_horizontal_items': 3,
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

  " Remove dup
  let items = s:uniq_by_word_or_dup(a:items)

  let max_abbr = max(map(copy(items), { _, val ->
        \ strwidth(get(val, 'abbr', val.word))
        \ }))
  let max_kind = max(map(copy(items), { _, val ->
        \ strwidth(get(val, 'kind', ''))
        \ }))
  let max_menu = max(map(copy(items), { _, val ->
        \ strwidth(get(val, 'menu', ''))
        \ }))
  let format = printf('%%s%s%%s%s%%s',
        \ (max_kind != 0 ? ' ' : ''),
        \ (max_menu != 0 ? ' ' : ''))
  let lines = map(copy(items), { _, val ->
        \ s:format_item(format, val, max_abbr, max_kind, max_menu)
        \ })

  let pum = pum#_get()
  let pum.items = copy(items)

  let options = pum#_options()

  let width = max_abbr + max_kind + max_menu
  " Padding
  if max_kind != 0
    let width += 1
  endif
  if max_menu != 0
    let width += 1
  endif

  if (!has('nvim') && a:mode ==# 't')
    let cursor = term_getcursor(bufnr('%'))
    let spos = { 'row': cursor[0], 'col': a:startcol }
  else
    let spos = screenpos(0, line('.'), a:startcol)
  endif

  let height = len(items)
  if &pumheight > 0
    let height = min([height, &pumheight])
  else
    let height = min([height, &lines - 1])
  endif
  if a:mode !=# 'c'
    " Adjust to screen row
    let padding = options.border !=# 'none' && has('nvim') ? 3 : 1
    let minheight_below = min([height, &lines - spos.row - padding])
    let minheight_above = min([height, spos.row - padding])
    if minheight_below >= minheight_above
      " Use below window
      let height = minheight_below
    else
      " Use above window
      let spos.row = spos.row - height - padding
      let height = minheight_above
    endif
  endif
  let height = max([height, 1])

  let pos = a:mode ==# 'c' ?
        \ [&lines - height - &cmdheight, a:startcol] :
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

      let pum.id = id
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

  let pum.cursor = 0
  let pum.height = height
  let pum.width = width
  let pum.len = len(items)
  let pum.startcol = a:startcol
  let pum.startrow = s:row()
  let pum.current_line = getline('.')
  let pum.col = pum#_col()
  let pum.orig_input = pum#_getline()[a:startcol - 1 : pum#_col() - 2]

  " Clear current highlight
  silent! call matchdelete(pum#_cursor_id(), pum.id)

  if !pum.horizontal_menu
    " Highlight
    call s:highlight_items(items, max_abbr, max_kind, max_menu)

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
  elseif a:mode ==# 'c' && has('nvim')
    " Note: :redraw is needed for command line completion in neovim
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

function! pum#_highlight(highlight, prop_type, priority, id, row, col, length) abort
  let pum = pum#_get()

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
          \ a:col - 1,
          \ a:col - 1 + a:length
          \ )
  else
    call prop_add(a:row, a:col, {
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

function! s:highlight_items(items, max_abbr, max_kind, max_menu) abort
  let pum = pum#_get()
  let options = pum#_options()

  let start_abbr = 1
  let end_abbr = a:max_abbr + 1
  let start_kind = start_abbr + end_abbr
  let end_kind = a:max_kind + 1
  let start_menu = (a:max_kind != 0) ?
        \ start_kind + end_kind : start_abbr + end_abbr
  let end_menu = a:max_menu + 1

  let highlight_abbr = options.highlight_abbr !=# '' && a:max_abbr != 0
  let highlight_kind = options.highlight_kind !=# '' && a:max_kind != 0
  let highlight_menu = options.highlight_menu !=# '' && a:max_menu != 0

  for row in range(1, len(a:items))
    " Default highlights
    if highlight_abbr
      call pum#_highlight(
            \ options.highlight_abbr, 'pum_abbr', 0,
            \ g:pum#_namespace, row, start_abbr, end_abbr)
    endif

    if highlight_kind
      call pum#_highlight(
            \ options.highlight_kind, 'pum_kind', 0,
            \ g:pum#_namespace, row, start_kind, end_kind)
    endif

    if highlight_menu
      call pum#_highlight(
            \ options.highlight_menu, 'pum_menu', 0,
            \ g:pum#_namespace, row, start_menu, end_menu)
    endif

    let item = a:items[row - 1]
    if !empty(get(item, 'highlights', []))
      " Use custom highlights
      for hl in item.highlights
        let start = hl.type ==# 'abbr' ? start_abbr :
              \ hl.type ==# 'kind' ? start_kind : start_menu
        call pum#_highlight(
              \ hl.hl_group, hl.name, 1,
              \ g:pum#_namespace, row, start + hl.col, hl.width)
      endfor
    endif
  endfor
endfunction

function! s:format_item(format, item, max_abbr, max_kind, max_menu) abort
  let abbr = substitute(get(a:item, 'abbr', a:item.word),
        \ '[[:cntrl:]]', '?', 'g')
  let abbr .= repeat(' ' , a:max_abbr - strwidth(abbr))
  let kind = get(a:item, 'kind', '')
  let kind .= repeat(' ' , a:max_kind - strwidth(kind))
  let menu = get(a:item, 'menu', '')
  let menu .= repeat(' ' , a:max_menu - strwidth(menu))
  return printf(a:format, abbr, kind, menu)
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
