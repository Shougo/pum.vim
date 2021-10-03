if has('nvim')
  let s:namespace = nvim_create_namespace('pum')
endif
let g:pum#skip_next_complete = v:false

if !exists('g:pum#highlight_select')
  let g:pum#highlight_select = 'PmenuSel'
endif

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
        \ 'id': -1,
        \ 'len': 0,
        \ 'orig_input': '',
        \ 'pos': [],
        \ 'startcol': -1,
        \ 'width': -1,
        \}
endfunction

function! pum#open(startcol, items) abort
  if !has('patch-8.2.1978') && !has('nvim-0.6')
    call s:print_error(
          \ 'pum.vim requires Vim 8.2.1978+ or neovim 0.6.0+.')
    return -1
  endif

  let max_abbr = max(map(copy(a:items), { _, val ->
        \ strwidth(get(val, 'abbr', val.word))
        \ }))
  let max_kind = max(map(copy(a:items), { _, val ->
        \ strwidth(get(val, 'kind', ''))
        \ }))
  let max_menu = max(map(copy(a:items), { _, val ->
        \ strwidth(get(val, 'menu', ''))
        \ }))
  let format = printf('%%-%ds%%-%ds%%-%ds',
        \ max_abbr + (max_kind != 0 ? 1: 0),
        \ max_kind + (max_menu != 0 ? 1: 0),
        \ max_menu)
  let lines = map(copy(a:items), { _, val -> printf(format,
        \ get(val, 'abbr', val.word),
        \ get(val, 'kind', ''),
        \ get(val, 'menu', ''))
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

  let height = len(a:items)
  if &pumheight > 0
    let height = min([height, &pumheight])
  endif
  let height = max([height, 1])

  let spos = screenpos('.', line('.'), a:startcol)
  let pos = mode() ==# 'c' ?
        \ [&lines - height - 1, a:startcol] : [spos.row, spos.col - 1]

  if has('nvim')
    if pum.buf < 0
      let pum.buf = nvim_create_buf(v:false, v:true)
    endif
    call nvim_buf_set_lines(pum.buf, 0, -1, v:true, lines)
    if pos == pum.pos && pum.id > 0
      " Resize window
      call nvim_win_set_width(pum.id, width)
      call nvim_win_set_height(pum.id, height)
    else
      call pum#close()

      " Create new window
      let opts = {
            \ 'relative': 'editor',
            \ 'width': width,
            \ 'height': height,
            \ 'col': pos[1],
            \ 'row': pos[0],
            \ 'anchor': 'NW',
            \ 'style': 'minimal',
            \ 'noautocmd': v:true,
            \ }
      let id = nvim_open_win(pum.buf, v:false, opts)

      let pum.id = id
      let pum.pos = pos
    endif
  else
    let options = {
          \ 'pos': 'topleft',
          \ 'line': pos[0] + 1,
          \ 'col': pos[1] + 1,
          \ 'maxwidth': width,
          \ 'maxheight': height,
          \ }

    if pum.id > 0
      call popup_move(pum.id, options)
      call popup_settext(pum.id, lines)
    else
      let pum.id = popup_create(lines, options)
      let pum.buf = winbufnr(pum.id)

      " Add prop types
      call prop_type_delete('pum_cursor')
      call prop_type_add('pum_cursor', {
            \ 'highlight': g:pum#highlight_select,
            \ })
    endif
  endif

  " Note: :redraw is needed for command line completion in neovim
  if mode() ==# 'c' && has('nvim')
    redraw
  endif

  let pum.cursor = 0
  let pum.height = height
  let pum.width = width
  let pum.len = len(a:items)
  let pum.items = copy(a:items)
  let pum.startcol = a:startcol
  let pum.orig_input = pum#_getline()[a:startcol - 1 : s:col()]

  return pum.id
endfunction

function! pum#close() abort
  let pum = pum#_get()

  if pum.id <= 0
    return
  endif

  if has('nvim')
    call nvim_win_close(pum.id, v:true)
  else
    call popup_close(pum.id)
  endif

  let pum.current_word = ''
  let pum.id = -1
endfunction

function! pum#visible() abort
  return pum#_get().id > 0
endfunction
function! pum#complete_info() abort
  let pum = pum#_get()
  return {
        \ 'mode': '',
        \ 'pumvisible': pum#visible(),
        \ 'items': pum.items,
        \ 'selected': pum.cursor - 1,
        \ 'inserted': pum.current_word,
        \ }
endfunction

function! pum#_getline() abort
  return mode() ==# 'c' ? getcmdline() : getline('.')
endfunction
function! s:col() abort
  return mode() ==# 'c' ? getcmdpos() : col('.')
endfunction

function! s:print_error(string) abort
  echohl Error
  echomsg printf('[pum] %s', type(a:string) ==# v:t_string ?
        \ a:string : string(a:string))
  echohl None
endfunction
