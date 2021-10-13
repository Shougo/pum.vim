let s:skip_count = -1

function! pum#map#select_relative(delta) abort
  let pum = pum#_get()
  if pum.buf <= 0 || pum.id <= 0
    return ''
  endif

  " Clear current highlight
  silent! call matchdelete(pum#_cursor_id(), pum.id)

  let pum.cursor += a:delta
  if pum.cursor > pum.len || pum.cursor == 0
    " Reset
    let pum.cursor = 0

    " Move real cursor
    call win_execute(pum.id, 'call cursor(1, 0) | redraw')

    return ''
  elseif pum.cursor < 0
    " Reset
    let pum.cursor = pum.len
  endif

  silent doautocmd <nomodeline> User PumCompleteChanged

  " Move real cursor
  " Note: If up scroll, cursor must adjust...
  " Note: Use matchaddpos() instead of nvim_buf_add_highlight() or prop_add()
  " Because the highlight conflicts with other highlights
  if a:delta < 0
    call win_execute(pum.id, '
          \ call cursor(pum#_get().cursor, 0) |
          \ call matchaddpos(pum#_options().highlight_selected,
          \                   [pum#_get().cursor], 0, pum#_cursor_id()) |
          \ redraw')
  else
    call win_execute(pum.id, '
          \ call cursor(pum#_get().cursor + 1, 0) |
          \ call matchaddpos(pum#_options().highlight_selected,
          \                   [pum#_get().cursor], 0, pum#_cursor_id()) |
          \ redraw')
  endif

  return ''
endfunction

function! pum#map#insert_relative(delta) abort
  let pum = pum#_get()

  let prev_word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input

  call pum#map#select_relative(a:delta)
  if pum.cursor < 0 || pum.id <= 0
    let pum.current_word = ''
    return ''
  endif

  call s:insert_current_word(prev_word)

  " Call CompleteDone if user input
  call s:check_user_input({ -> s:complete_done() })

  return ''
endfunction

function! pum#map#confirm() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word ==# ''
    call s:insert_current_word(pum.orig_input)
  endif

  call pum#close()

  call s:complete_done()

  " Skip completion until next input
  let pum.skip_complete = v:true
  call s:check_user_input({ -> s:reset_skip_complete() })

  return ''
endfunction

function! pum#map#cancel() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word !=# ''
    call s:insert(pum.orig_input, pum.current_word)
  endif
  call pum#close()

  " Skip completion until next input
  let pum.skip_complete = v:true
  call s:check_user_input({ -> s:reset_skip_complete() })

  return ''
endfunction

function! pum#map#select_relative_page(delta) abort
  call pum#map#select_relative(float2nr(a:delta * pum#_get().height))
  return ''
endfunction
function! pum#map#insert_relative_page(delta) abort
  call pum#map#insert_relative(float2nr(a:delta * pum#_get().height))
  return ''
endfunction

function! pum#map#_skip_count() abort
  return s:skip_count
endfunction

function! s:insert(word, prev_word) abort
  let pum = pum#_get()

  " Convert to 0 origin
  let startcol = pum.startcol - 1
  let prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
  let next_input = pum#_getline()[startcol :][len(a:prev_word):]

  if mode() ==# 'c' || (pum#_options().setline_insert && mode() ==# 'i')
    call s:setline(prev_input . a:word . next_input)
    call s:cursor(pum.startcol + len(a:word))
  else
    let current_word = (pum.current_word ==# '') ?
          \ pum.orig_input : pum.current_word
    call s:insertline(current_word, a:word)
  endif

  let pum.current_word = a:word

  " Note: The text changes fires TextChanged events.  It must be ignored.
  let pum.skip_complete = v:true
endfunction
function! s:insert_current_word(prev_word) abort
  let pum = pum#_get()

  let word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input
  call s:insert(word, a:prev_word)
endfunction

function! s:check_user_input(callback) abort
  augroup pum-temp
    autocmd!
  augroup END

  let g:PumCallback = function(a:callback)

  if mode() ==# 'i' && pum#_options().setline_insert
    let s:skip_count = 1
  endif

  if mode() ==# 'c'
    autocmd pum-temp CmdlineChanged *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp CmdlineLeave *
          \ call s:reset_skip_complete()
  elseif mode() ==# 't'
    autocmd pum-temp User PumTextChanged
          \ call s:check_skip_count(g:PumCallback)
  else
    autocmd pum-temp InsertCharPre *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp InsertLeave *
          \ call s:reset_skip_complete()
    autocmd pum-temp TextChangedI *
          \ if line('.') != pum#_get().startrow | call pum#close() | endif
  endif
endfunction
function! s:check_skip_count(callback) abort
  let s:skip_count -= 1

  if s:skip_count > 0
    return
  endif

  " It should be user input

  augroup pum-temp
    autocmd!
  augroup END

  call call(a:callback, [])
endfunction
function! s:complete_done() abort
  let pum = pum#_get()

  if pum.cursor <= 0
    return
  endif

  call s:reset_skip_complete()

  let g:pum#completed_item = pum.items[pum.cursor - 1]
  silent doautocmd <nomodeline> User PumCompleteDone
endfunction
function! s:reset_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:false
  let pum.current_word = ''
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
    let tree = undotree()
    if tree.seq_cur == tree.seq_last
      undojoin
    endif

    if pum#_options().setline_insert && mode() ==# 'i'
      call setline('.', a:text)
    elseif mode() ==# 't' && &filetype ==# 'deol' && has('nvim')
      " Note: For Vim, jobsend() does not work well...
      call t:deol.jobsend(a:text)
    else
      call feedkeys(a:text, 'n')
    endif
  endif
endfunction
function! s:insertline(current_word, text) abort
  if a:current_word ==# a:text
    return
  endif

  " Note: ":undojoin" is needed to prevent undo breakage
  let tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif
  let chars = ''
  " Note: Change backspace option to work <BS> correctly
  let chars .= "\<Cmd>set backspace=\<CR>"
  let chars .= repeat("\<BS>", strchars(a:current_word)) . a:text
  let chars .= printf("\<Cmd>set backspace=%s\<CR>", &backspace)
  let s:skip_count = strchars(mode() ==# 't' ? chars : a:text) + 1

  if mode() ==# 't' && &filetype ==# 'deol' && has('nvim')
    " Note: For Vim, jobsend() does not work well...
    call t:deol.jobsend(chars)
  else
    call feedkeys(chars, 'n')
  endif
endfunction
