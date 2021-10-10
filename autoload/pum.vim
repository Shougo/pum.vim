let s:namespace = has('nvim') ? nvim_create_namespace('pum') : 0
let g:pum#completed_item = {}
let s:pum_matched_id = 70


function! pum#_get() abort
  if !exists('s:pum')
    call pum#_init()

    augroup pum
      autocmd!
    augroup END
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
          \ 'highlight_kind': '',
          \ 'highlight_matches': '',
          \ 'highlight_menu': '',
          \ 'highlight_selected': 'PmenuSel',
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
  let options = pum#_options()

  let width = max_abbr + max_kind + max_menu
  " Padding
  if max_kind != 0
    let width += 1
  endif
  if max_menu != 0
    let width += 1
  endif

  let spos = screenpos(0, line('.'), a:startcol)

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
        \ [&lines - height - 1, a:startcol] : [spos.row, spos.col - 1]

  if has('nvim')
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

      " Disable 'hlsearch' highlight
      call nvim_win_set_option(id, 'winhighlight', 'Search:None')
      call nvim_win_set_option(id, 'winblend', &l:winblend)
      let pum.id = id
    endif

    let pum.pos = pos
  else
    let winopts = {
          \ 'pos': 'topleft',
          \ 'line': pos[0] + 1,
          \ 'col': pos[1] + 1,
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
  endif

  let pum.cursor = 0
  let pum.height = height
  let pum.width = width
  let pum.len = len(items)
  let pum.items = copy(items)
  let pum.startcol = a:startcol
  let pum.startrow = line('.')
  let pum.orig_input = pum#_getline()[a:startcol - 1 : s:col() - 2]

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

  if &completeopt =~# 'noinsert'
    call pum#map#select_relative(+1)
  elseif a:mode ==# 'c' && has('nvim')
    " Note: :redraw is needed for command line completion in neovim
    redraw
  endif

  " Close popup automatically
  if exists('##ModeChanged')
    autocmd pum ModeChanged * ++once call pum#close()
  elseif a:mode ==# 'i'
    autocmd pum InsertLeave * ++once call pum#close()
  elseif a:mode ==# 'c'
    autocmd pum WinEnter,CmdlineLeave * ++once call pum#close()
  elseif a:mode ==# 't' && exists('##TermEnter')
    autocmd pum TermEnter,TermLeave * ++once call pum#close()
  endif

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
    call nvim_win_close(pum.id, v:true)
    call nvim_buf_clear_namespace(pum.buf, s:namespace, 1, -1)
  else
    " Note: prop_remove() is not needed.
    " popup_close() removes the buffer.
    call popup_close(pum.id)
  endif

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
        \ 'pumvisible': pum#visible(),
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
  return mode() ==# 'c' ? getcmdline() : getline('.')
endfunction
function! s:col() abort
  return mode() ==# 'c' ? getcmdpos() : col('.')
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
            \ s:namespace, row, start_abbr, end_abbr)
    endif

    if highlight_kind
      call pum#_highlight(
            \ options.highlight_kind, 'pum_kind', 0,
            \ s:namespace, row, start_kind, end_kind)
    endif

    if highlight_menu
      call pum#_highlight(
            \ options.highlight_menu, 'pum_menu', 0,
            \ s:namespace, row, start_menu, end_menu)
    endif

    let item = a:items[row - 1]
    if !empty(get(item, 'highlights', []))
      " Use custom highlights
      for hl in item.highlights
        let start = hl.type ==# 'abbr' ? start_abbr :
              \ hl.type ==# 'kind' ? start_kind : start_menu
        call pum#_highlight(
              \ hl.hl_group, hl.name, 1,
              \ s:namespace, row, start + hl.col, hl.width)
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
