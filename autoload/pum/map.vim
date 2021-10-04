if has('nvim')
  let s:namespace = nvim_create_namespace('pum')
endif

function! pum#map#select_relative(delta) abort
  let pum = pum#_get()
  if pum.buf <= 0
    return ''
  endif

  " Clear current highlight
  if has('nvim')
    call nvim_buf_clear_namespace(pum.buf, s:namespace, 0, -1)
  else
    call prop_remove({
        \ 'type': 'pum_cursor',
        \ 'bufnr': pum.buf,
        \ })
  endif

  let pum.cursor += a:delta
  if pum.cursor > pum.len || pum.cursor == 0
    " Reset
    let pum.cursor = 0

    call s:redraw()

    return ''
  elseif pum.cursor < 0
    " Reset
    let pum.cursor = pum.len
  endif

  if has('nvim')
    call nvim_buf_add_highlight(
          \ pum.buf,
          \ s:namespace,
          \ pum#_options().highlight_selected,
          \ pum.cursor - 1,
          \ 0, -1
          \ )
  else
    call prop_add(pum.cursor, 1, {
          \ 'length': pum.width,
          \ 'type': 'pum_cursor',
          \ 'bufnr': pum.buf,
          \ })
  endif

  call s:redraw()

  return ''
endfunction

function! pum#map#insert_relative(delta) abort
  let pum = pum#_get()

  let prev_word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input

  call pum#map#select_relative(a:delta)
  if pum.cursor < 0 || pum.id <= 0
    return ''
  endif

  call s:insert_current_word(prev_word)

  " Call CompleteDone if user input
  augroup pum-temp
    autocmd!
  augroup END

  if mode() ==# 'c'
    autocmd pum-temp CmdlineChanged *
          \ call s:check_skip_count()
  else
    autocmd pum-temp InsertCharPre * ++once
          \ call s:complete_done()
  endif

  return ''
endfunction
function! s:check_skip_count() abort
  let s:skip_count -= 1

  if s:skip_count > 0
    return
  endif

  " It should be user input

  augroup pum-temp
    autocmd!
  augroup END

  call s:complete_done()
endfunction
function! s:complete_done() abort
  let pum = pum#_get()

  if pum.cursor <= 0
    return
  endif

  let g:pum#completed_item = pum.items[pum.cursor - 1]
  silent doautocmd <nomodeline> User PumCompleteDone
endfunction

function! pum#map#confirm() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word ==# ''
    call s:insert_current_word(pum.orig_input)
  endif

  call pum#close()

  call s:complete_done()

  return ''
endfunction

function! pum#map#cancel() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word !=# ''
    call s:insert(pum.orig_input, pum.current_word)
  endif
  call pum#close()
  return ''
endfunction

function! s:insert(word, prev_word) abort
  let pum = pum#_get()

  " Convert to 0 origin
  let startcol = pum.startcol - 1
  let prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
  let next_input = pum#_getline()[startcol :][len(a:prev_word):]

  call s:setline(prev_input . a:word . next_input)
  call s:cursor(pum.startcol + len(a:word))

  let pum.current_word = a:word

  " Note: The text changes fires TextChanged events.  It must be ignored.
  let g:pum#skip_next_complete = v:true
endfunction
function! s:insert_current_word(prev_word) abort
  let pum = pum#_get()

  let word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input
  call s:insert(word, a:prev_word)
endfunction

function! s:redraw() abort
  " Note: :redraw is needed for command line completion in neovim or Vim
  if mode() ==# 'c' || !has('nvim')
    redraw
  endif
endfunction

function! s:cursor(col) abort
  return mode() ==# 'c' ? setcmdpos(a:col) : cursor(0, a:col)
endfunction
function! s:setline(text) abort
  if mode() ==# 'c'
    " setcmdline() is not exists...

    " Clear cmdline
    let chars = "\<C-e>\<C-u>"

    " Note: for control chars
    let chars .= join(map(split(a:text, '\zs'),
          \ { _, val -> val <# ' ' ? "\<C-q>" . val : val }), '')

    " Note: skip_count is needed to skip feedkeys() in s:setline()
    let s:skip_count = strchars(chars)

    call feedkeys(chars, 'n')
  else
    " Note: ":undojoin" is needed to prevent undo breakage
    undojoin | call setline('.', a:text)
  endif
endfunction
