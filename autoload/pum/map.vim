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
      call pum#popup#_redraw_horizontal_menu()
    else
      call win_execute(pum.id, 'call cursor(1, 0) | redraw')
    endif

    " Reset scroll bar
    if pum.scroll_id > 0 && has('nvim') && pum.scroll_id->winbufnr() > 0
      call nvim_win_set_config(pum.scroll_id, #{
            \   relative: 'editor',
            \   row: pum.scroll_row,
            \   col: pum.scroll_col,
            \ })
    endif

    return ''
  elseif pum.cursor < 0
    " Reset
    let pum.cursor = pum.len
  endif

  if '#User#PumCompleteChanged'->exists()
    silent! doautocmd <nomodeline> User PumCompleteChanged
  endif

  if pum.horizontal_menu
    call pum#popup#_redraw_horizontal_menu()
  else
    " Move real cursor
    " NOTE: If up scroll, cursor must adjust...
    " NOTE: Use matchaddpos() instead of nvim_buf_add_highlight() or prop_add()
    " Because the highlight conflicts with other highlights
    if delta < 0
      call win_execute(pum.id, '
            \ call cursor(pum#_get().cursor, 0)
            \ | call matchaddpos(pum#_options().highlight_selected,
            \                    [pum#_get().cursor], 0, pum#_cursor_id())
            \ | redraw')
    else
      call win_execute(pum.id, '
            \ call cursor(pum#_get().cursor + 1, 0)
            \ | call matchaddpos(pum#_options().highlight_selected,
            \                    [pum#_get().cursor], 0, pum#_cursor_id())
            \ | redraw')
    endif
  endif

  " Update scroll bar
  if pum.scroll_id > 0 && has('nvim') && pum.scroll_id->winbufnr() > 0
    const head = 'w0'->line(pum.id)
    const bottom = 'w$'->line(pum.id)
    const offset =
          \ head == 1 ? 0 :
          \ bottom == pum.len ? pum.height - pum.scroll_height :
          \ (pum.height * (head + 0.0) / pum.len + 0.5)->floor()->float2nr()

    call nvim_win_set_config(pum.scroll_id, #{
          \   relative: 'editor',
          \   row: pum.scroll_row + offset,
          \   col: pum.scroll_col,
          \ })
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

  call pum#popup#_reset_auto_confirm(mode())

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

  let g:inserted = v:false
  call s:insert_current_word(prev_word, v:null)

  if pum.horizontal_menu
    call pum#popup#_redraw_horizontal_menu()
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

  return ''
endfunction

function! pum#map#longest_relative(delta) abort
  let pum = pum#_get()
  if pum.items->empty()
    return ''
  endif

  const complete_str = pum.orig_input
  let common_str = pum.items[0].word
  for item in pum.items[1:]
    while item.word->tolower()->stridx(common_str->tolower()) != 0
      let common_str = common_str[: -2]
    endwhile
  endfor

  const prev_word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input

  if common_str ==# '' || complete_str ==? common_str
        \ || common_str ==# prev_word
    return pum#map#insert_relative(a:delta)
  endif

  " Insert the longest word.
  call s:insert(common_str, prev_word, v:null)

  let pum.orig_input = common_str
  let pum.skip_complete = v:false

  return ''
endfunction

function! pum#map#confirm() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word ==# ''
    call s:insert_current_word(pum.orig_input,
          \ { -> s:skip_next_complete() })
  else
    call s:skip_next_complete()
  endif

  " Reset v:completed_item to prevent CompleteDone is twice
  autocmd pum-temp TextChangedI,TextChangedP * ++once
        \ silent! let v:completed_item = {}

  return ''
endfunction

function! pum#map#cancel() abort
  let pum = pum#_get()

  const current_word = pum.current_word
  const current_cursor = pum.cursor

  " Disable current inserted text
  let pum.current_word = ''
  let pum.cursor = -1

  if current_cursor > 0 && current_word !=# ''
    call s:insert(pum.orig_input, current_word,
          \ { -> s:skip_next_complete() })
  else
    call s:skip_next_complete()
  endif

  return ''
endfunction

function! pum#map#select_relative_page(delta) abort
  call pum#map#select_relative((a:delta * pum#_get().height)->float2nr())
  return ''
endfunction
function! pum#map#insert_relative_page(delta) abort
  call pum#map#insert_relative((a:delta * pum#_get().height)->float2nr())
  return ''
endfunction

function! pum#map#_skip_count() abort
  return s:skip_count
endfunction

function! s:skip_next_complete() abort
  " Skip completion until next input

  call pum#close()

  let pum = pum#_get()
  let pum.skip_complete = v:true
  let s:skip_count = 1

  " Note: s:check_user_input() does not work well in terminal mode
  if mode() ==# 't'
    if '##TextChangedT'->exists()
      autocmd pum-temp TextChangedT * call pum#_reset_skip_complete()
    endif
  else
    call s:check_user_input({ -> pum#_reset_skip_complete() })
  endif
endfunction

function! s:insert(word, prev_word, after_func) abort
  augroup pum-temp
    autocmd!
  augroup END

  let pum = pum#_get()

  " Convert to 0 origin
  const startcol = pum.startcol - 1
  const prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
  const next_input = pum#_getline()[startcol :][len(a:prev_word):]

  " NOTE: current_word must be changed before call after_func
  let pum.current_word = a:word

  " NOTE: The text changes fires TextChanged events.  It must be ignored.
  let pum.skip_complete = v:true

  if mode() ==# 'c'
    call s:setcmdline(prev_input .. a:word .. next_input)
    call s:cursor(pum.startcol + len(a:word))
  elseif mode() ==# 't'
    call s:insert_line_jobsend(a:word)
  elseif pum#_options().use_setline
    call setline('.', prev_input .. a:word .. next_input)
    call s:cursor(pum.startcol + len(a:word))
  elseif a:word ==# '' || !pum#_options().use_complete
        \ || a:after_func != v:null
    " NOTE: complete() does not work for empty string
    call s:insert_line_feedkeys(a:word, a:after_func)
    return
  else
    call s:insert_line_complete(a:word)
    return
  endif

  if a:after_func != v:null
    call call(a:after_func, [])
  endif
endfunction
function! s:insert_current_word(prev_word, after_func) abort
  let pum = pum#_get()

  const word = pum.cursor > 0 ?
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
    if has('nvim')
      lua vim.on_key(function(key)
            \   if string.match(key, '^%C$') then
            \     vim.fn['pum#close']()
            \   end
            \ end)
    elseif '##TextChangedT'->exists()
      let s:prev_line = pum#_getline()
      autocmd pum-temp TextChangedT * call s:check_text_changed_terminal()
    endif
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
  const startcol_line = pum#_getline()[: pum.startcol]
  const check_startcol_line = startcol_line !=# pum.orig_line &&
        \ (strchars(pum.current_line) > strchars(startcol_line))

  " NOTE: Check "current_word" is one of the items.
  const current_word = pum#_getline()[pum.startcol-1 : pum#_col()-2]
  const check_item = pum.items->copy()->map(
        \ { _, val -> val.word })->index(current_word) < 0
  return check_item || check_startcol_line
endfunction
function! s:check_text_changed_terminal() abort
  " Check pum.items is inserted
  let pum = pum#_get()
  if pum#_row() != pum.startrow
    call pum#close()
    return
  endif

  const current_line = pum#_getline()
  if current_line !=# s:prev_line
    call pum#close()
  endif
  let s:prev_line = current_line
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
  if '*setcmdline'->exists()
    " NOTE: skip_count is needed
    " CmdlineChanged is triggered after setcmdline() call
    let s:skip_count = 2

    " NOTE: CmdlineChanged autocmd must be disabled
    call setcmdline(a:text)
  else
    " Clear cmdline
    let chars = "\<C-e>\<C-u>"

    " NOTE: for control chars
    let chars ..= a:text->split('\zs')
          \ ->map({ _, val -> val <# ' ' ? "\<C-q>" .. val : val })->join('')

    " NOTE: skip_count is needed to skip feedkeys()
    let s:skip_count = chars->strchars()

    call feedkeys(chars, 'n')
  endif
endfunction

function! s:insert_line_feedkeys(text, after_func) abort
  " feedkeys() implementation

  " NOTE: ":undojoin" is needed to prevent undo breakage
  const tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif

  let chars = ''
  " NOTE: Change backspace option to work <BS> correctly
  if mode() ==# 'i'
    let chars ..= "\<Cmd>set backspace=start\<CR>"
  endif
  const current_word = pum#_getline()[pum#_get().startcol - 1 : pum#_col() - 2]
  let chars ..= "\<BS>"->repeat(current_word->strchars()) .. a:text
  if mode() ==# 'i'
    let chars ..= printf("\<Cmd>set backspace=%s\<CR>", &backspace)
  endif
  if a:after_func != v:null
    let g:PumCallback = function(a:after_func)
    let chars ..= "\<Cmd>call call(g:PumCallback, [])\<CR>"
  endif
  let s:skip_count = (mode() ==# 't' ? chars : a:text)->strchars() + 1

  call feedkeys(chars, 'n')
endfunction

function! s:insert_line_complete(text) abort
  " complete() implementation

  " NOTE: Restore completeopt is needed after complete()
  autocmd pum TextChangedI,TextChangedP * ++once
        \ let &completeopt = s:save_completeopt

  let s:save_completeopt = &completeopt
  set completeopt=menu

  call complete(pum#_get().startcol, [a:text])

  " NOTE: Hide native popup menu.
  " Because native popup menu disables user insert mappings.
  call feedkeys("\<C-x>\<C-z>", 'in')
endfunction

function! s:insert_line_jobsend(text) abort
  const current_word = pum#_getline()[
        \ pum#_get().startcol - 1 : pum#_col() - 2]
  const chars = "\<C-h>"->repeat(current_word->strchars()) .. a:text

  if has('nvim')
    call chansend(b:terminal_job_id, chars)
  else
    call term_sendkeys(bufnr(), chars)
    call term_wait(bufnr())
  endif
endfunction
