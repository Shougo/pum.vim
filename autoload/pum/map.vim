let s:skip_count = -1

function! pum#map#select_relative(delta) abort
  let pum = pum#_get()
  if pum.id <= 0
    return ''
  endif

  " Clear current highlight
  if !pum.horizontal_menu
    silent! call matchdelete(pum#_cursor_id(), pum.id)
  endif

  let pum.cursor += a:delta

  if pum.cursor > pum.len || pum.cursor == 0
    " Reset
    let pum.cursor = 0

    " Move real cursor
    if pum.horizontal_menu
      call pum#_redraw_horizontal_menu()
    else
      call win_execute(pum.id, 'call cursor(1, 0) | redraw')
    endif

    return ''
  elseif pum.cursor < 0
    " Reset
    let pum.cursor = pum.len
  endif

  if exists('#User#PumCompleteChanged')
    doautocmd <nomodeline> User PumCompleteChanged
  endif

  if pum.horizontal_menu
    call pum#_redraw_horizontal_menu()
  else
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

  if pum.horizontal_menu
    call pum#_redraw_horizontal_menu()
  endif

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

  if mode() ==# 'c' || pum#_options().setline_insert
    call s:setline(prev_input . a:word . next_input)
    call s:cursor(pum.startcol + len(a:word))
  else
    call s:insertline(a:word)
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

  let pum = pum#_get()
  let pum.current_line = pum#_getline()[: pum.startcol]

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
          \ if s:check_text_changed() | call pum#close() | endif
  endif
endfunction
function! s:check_text_changed() abort
  return line('.') != pum#_get().startrow ||
        \ (strchars(pum#_get().current_line) >
        \  strchars(pum#_getline()[: pum#_get().startcol]))
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
  if exists('#User#PumCompleteDone')
    doautocmd <nomodeline> User PumCompleteDone
  endif
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

    if pum#_options().setline_insert
      call setline('.', split(a:text, '\n'))
    else
      call feedkeys(a:text, 'n')
    endif
  endif
endfunction
function! s:insertline(text) abort
  let current_word = pum#_getline()[pum#_get().startcol - 1 : pum#_col() - 2]
  if current_word ==# a:text
    return
  endif

  " Note: ":undojoin" is needed to prevent undo breakage
  let tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif

  let chars = ''
  " Note: Change backspace option to work <BS> correctly
  if mode() !=# 't'
    let chars .= "\<Cmd>set backspace=start\<CR>"
  endif
  let chars .= repeat("\<BS>", strchars(current_word)) . a:text
  if mode() !=# 't'
    let chars .= printf("\<Cmd>set backspace=%s\<CR>", &backspace)
  endif
  let s:skip_count = strchars(mode() ==# 't' ? chars : a:text) + 1

  call feedkeys(chars, 'n')
endfunction
