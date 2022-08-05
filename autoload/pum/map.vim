let s:skip_count = -1

function! pum#map#select_relative(delta) abort
  let pum = pum#_get()
  if pum.id <= 0
    return ''
  endif

  let delta = a:delta
  if pum.reversed
    let delta *= -1
  endif

  " Clear current highlight
  if !pum.horizontal_menu
    silent! call matchdelete(pum#_cursor_id(), pum.id)
  endif

  let pum.cursor += delta

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
    silent! doautocmd <nomodeline> User PumCompleteChanged
  endif

  if pum.horizontal_menu
    call pum#_redraw_horizontal_menu()
  else
    " Move real cursor
    " NOTE: If up scroll, cursor must adjust...
    " NOTE: Use matchaddpos() instead of nvim_buf_add_highlight() or prop_add()
    " Because the highlight conflicts with other highlights
    if delta < 0
      call win_execute(pum.id, '
            \ call cursor(pum#_get().cursor, 0) |
            \ call matchaddpos(pum#_options().highlight_selected,
            \                  [pum#_get().cursor], 0, pum#_cursor_id()) |
            \ redraw')
    else
      call win_execute(pum.id, '
            \ call cursor(pum#_get().cursor + 1, 0) |
            \ call matchaddpos(pum#_options().highlight_selected,
            \                  [pum#_get().cursor], 0, pum#_cursor_id()) |
            \ redraw')
    endif
  endif

  " Update scroll bar
  if pum.scroll_id > 0 && has('nvim') && winbufnr(pum.scroll_id) > 0
    let offset = min([
          \ float2nr(pum.height * (pum.cursor + 0.0) / pum.len),
          \ pum.height - 1
          \ ])

    call nvim_win_set_config(pum.scroll_id, {
          \ 'relative': 'editor',
          \ 'row': pum.scroll_row + offset,
          \ 'col': pum.scroll_col,
          \ })
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

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

  call s:insert_current_word(prev_word, v:null)

  if pum.horizontal_menu
    call pum#_redraw_horizontal_menu()
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

  return ''
endfunction

function! pum#map#confirm() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word ==# ''
    call s:insert_current_word(pum.orig_input, { -> s:confirm_after() })
  else
    call s:confirm_after()
  endif

  return ''
endfunction

function! s:confirm_after() abort
  call pum#close()

  " Skip completion until next input
  let pum = pum#_get()
  let pum.skip_complete = v:true
  let pum.cursor = 0
  let s:skip_count = 1
  call s:check_user_input({ -> pum#_reset_skip_complete() })
endfunction

function! pum#map#cancel() abort
  let pum = pum#_get()

  let current_word = pum.current_word
  let pum.current_word = ''

  if pum.cursor > 0 && current_word !=# ''
    call s:insert(pum.orig_input, current_word, { -> s:confirm_after() })
  else
    call s:confirm_after()
  endif

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

function! s:insert(word, prev_word, after_func) abort
  let pum = pum#_get()

  " Convert to 0 origin
  let startcol = pum.startcol - 1
  let prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
  let next_input = pum#_getline()[startcol :][len(a:prev_word):]

  if mode() ==# 'c'
    call s:setcmdline(prev_input . a:word . next_input)
    call s:cursor(pum.startcol + len(a:word))
    if a:after_func != v:null
      call call(a:after_func, [])
    endif
  elseif a:word ==# '' || !pum#_options().use_complete
    " NOTE: complete() does not work for empty string
    call s:insert_line_feedkeys(a:word, a:after_func)
  else
    call s:insert_line_complete(a:word, a:after_func)
  endif

  let pum.current_word = a:word

  " NOTE: The text changes fires TextChanged events.  It must be ignored.
  let pum.skip_complete = v:true
endfunction
function! s:insert_current_word(prev_word, after_func) abort
  let pum = pum#_get()

  let word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input
  call s:insert(word, a:prev_word, a:after_func)
endfunction

function! s:check_user_input(callback) abort
  augroup pum-temp
    autocmd!
  augroup END

  let g:PumCallback = function(a:callback)

  let pum = pum#_get()
  let pum.current_line = pum#_getline()[: pum.startcol]

  if mode() ==# 'c'
    autocmd pum-temp CmdlineChanged *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp CmdlineLeave *
          \ call pum#_reset_skip_complete()
  elseif mode() ==# 't'
    autocmd pum-temp User PumTextChanged
          \ call s:check_skip_count(g:PumCallback)
  else
    autocmd pum-temp InsertCharPre *
          \ call s:check_skip_count(g:PumCallback)
    autocmd pum-temp InsertLeave *
          \ call pum#_reset_skip_complete()
    autocmd pum-temp TextChangedI *
          \ if s:check_text_changed() | call pum#close() | endif
  endif
endfunction
function! s:check_text_changed() abort
  let pum = pum#_get()
  let startcol_line = pum#_getline()[: pum.startcol]
  return line('.') != pum.startrow ||
        \ (startcol_line !=# pum.orig_line &&
        \  (strchars(pum.current_line) > strchars(startcol_line)))
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

function! s:cursor(col) abort
  return mode() ==# 'c' ? setcmdpos(a:col) : cursor(0, a:col)
endfunction

function! s:setcmdline(text) abort
  if exists('*setcmdline')
    " NOTE: CmdlineChanged autocmd must be disabled
    noautocmd call setcmdline(a:text)
  else
    " Clear cmdline
    let chars = "\<C-e>\<C-u>"

    " NOTE: for control chars
    let chars .= join(map(split(a:text, '\zs'),
          \ { _, val -> val <# ' ' ? "\<C-q>" . val : val }), '')

    " NOTE: skip_count is needed to skip feedkeys()
    let s:skip_count = strchars(chars)

    call feedkeys(chars, 'n')
  endif
endfunction

function! s:insert_line_feedkeys(text, after_func) abort
  " feedkeys() implementation

  " NOTE: ":undojoin" is needed to prevent undo breakage
  let tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif

  let chars = ''
  " NOTE: Change backspace option to work <BS> correctly
  if mode() ==# 'i'
    let chars .= "\<Cmd>set backspace=start\<CR>"
  endif
  let current_word = pum#_getline()[pum#_get().startcol - 1 : pum#_col() - 2]
  let chars .= repeat("\<BS>", strchars(current_word)) . a:text
  if mode() ==# 'i'
    let chars .= printf("\<Cmd>set backspace=%s\<CR>", &backspace)
  endif
  if a:after_func != v:null
    let g:PumCallback = function(a:after_func)
    let chars .= "\<Cmd>call call(g:PumCallback, [])\<CR>"
  endif
  let s:skip_count = strchars(mode() ==# 't' ? chars : a:text) + 1

  call feedkeys(chars, 'n')
endfunction

function! s:insert_line_complete(text, after_func) abort
  " NOTE: complete() implementation

  " NOTE: CompleteDone may does not work for complete() insertion
  if a:after_func != v:null
    let g:PumCallback = function(a:after_func)
    autocmd pum TextChangedI,TextChangedP * ++once
          \ let &completeopt = s:save_completeopt |
          \ call call(g:PumCallback, [])
  else
    autocmd pum TextChangedI,TextChangedP * ++once
          \ let &completeopt = s:save_completeopt
  endif

  let s:save_completeopt = &completeopt
  set completeopt=menu

  call complete(pum#_get().startcol, [a:text])
endfunction
