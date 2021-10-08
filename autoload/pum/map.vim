let s:pum_cursor_id = 50

function! pum#map#select_relative(delta) abort
  let pum = pum#_get()
  if pum.buf <= 0 || pum.id <= 0
    return ''
  endif

  " Clear current highlight
  silent! call matchdelete(s:pum_cursor_id, pum.id)

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
          \                   [pum#_get().cursor], 0, s:pum_cursor_id) |
          \ redraw')
  else
    call win_execute(pum.id, '
          \ call cursor(pum#_get().cursor + 1, 0) |
          \ call matchaddpos(pum#_options().highlight_selected,
          \                   [pum#_get().cursor], 0, s:pum_cursor_id) |
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
    return ''
  endif

  call s:insert_current_word(prev_word)

  " Call CompleteDone if user input
  call s:check_user_input({ -> s:complete_done() })

  return ''
endfunction
function! s:check_user_input(callback) abort
  augroup pum-temp
    autocmd!
  augroup END

  let g:PumCallback = function(a:callback)

  if mode() ==# 'c'
    autocmd pum-temp CmdlineChanged *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp CmdlineLeave *
          \ call s:reset_skip_complete()
  else
    autocmd pum-temp InsertCharPre *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp TextChangedI *
          \ if line('.') != pum#_get().startrow | call pum#close() | endif
    autocmd pum-temp InsertLeave *
          \ call s:reset_skip_complete()
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
  let s:skip_count = 1
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
  let s:skip_count = 1
  call s:check_user_input({ -> s:reset_skip_complete() })

  return ''
endfunction

function! s:insert(word, prev_word) abort
  let pum = pum#_get()

  " Convert to 0 origin
  let startcol = pum.startcol - 1
  let prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
  let next_input = pum#_getline()[startcol :][len(a:prev_word):]

  if mode() ==# 'c'
    call s:setline(prev_input . a:word . next_input)
    call s:cursor(pum.startcol + len(a:word))
  else
    call s:insertline(pum.orig_input, a:word)
  endif

  let pum.current_word = a:word
  let pum.orig_input = a:word

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
    call feedkeys(a:text, 'n')
  endif
endfunction
function! s:insertline(orig_input, text) abort
  " Note: ":undojoin" is needed to prevent undo breakage
  let tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif
  let chars = repeat("\<C-h>", strchars(a:orig_input)) . a:text
  let s:skip_count = strchars(a:text) + 1
  call feedkeys(chars, 'n')
endfunction
