function pum#map#select_relative(delta, overflow='empty') abort
  let pum = pum#_get()
  if pum.id <= 0
    return ''
  endif

  let delta = a:delta
  if pum.reversed
    let delta *= -1
  endif

  let pum.cursor += delta

  if pum.cursor > pum.len || pum.cursor <= 0
    " Overflow

    if a:overflow ==# 'empty' && (pum.cursor > pum.len || pum.cursor ==# 0)
      " Select empty text

      " Reset
      let pum.cursor = 0

      call pum#popup#_close_preview()

      " Move real cursor
      if pum.horizontal_menu
        call pum#popup#_redraw_horizontal_menu()
      else
        call win_execute(pum.id, 'call cursor(1, 0)')
        call pum#popup#_redraw_selected()
      endif

      " Reset scroll bar
      if pum.scroll_id > 0 && has('nvim') && pum.scroll_id->winbufnr() > 0
        call nvim_win_set_config(pum.scroll_id, #{
              \   relative: 'editor',
              \   row: pum.scroll_row,
              \   col: pum.scroll_col,
              \ })
        call win_execute(pum.scroll_id, 'call cursor(1, 0)')
      endif

      call pum#popup#_redraw_scroll()

      call pum#popup#_reset_auto_confirm(mode())

      return ''
    endif

    if a:overflow ==# 'ignore'
      let pum.cursor = pum.cursor > pum.len ? pum.len : 1
    else
      " Loop
      let pum.cursor = pum.cursor > pum.len ? 1 : pum.len
    endif
  endif

  call pum#_complete_changed()

  if pum.horizontal_menu
    call pum#popup#_redraw_horizontal_menu()
  else
    " Move real cursor
    " NOTE: If up scroll, cursor must adjust...
    if delta < 0
      call win_execute(pum.id, 'call cursor(pum#_get().cursor, 0)')
    else
      call win_execute(pum.id, 'call cursor(pum#_get().cursor + 1, 0)')
    endif
    call pum#popup#_redraw_selected()

    call pum#popup#_redraw_scroll()
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
          \   row: pum.scroll_row + [offset, pum.scroll_height - 1]->min(),
          \   col: pum.scroll_col,
          \ })
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

  if mode() ==# 'i' && !pum#_options().commit_characters->empty()
    " TODO: vim.on_key support
    "if has('nvim')
    "  if !'s:check_commit_characters_handler'->exists()
    "    lua vim.on_key(function(key)
    "          \   local options = vim.fn['pum#_options']()
    "          \   local commit_characters = vim.fn.get(
    "          \     options, 'commit_characters', {})
    "          \   for _, v in ipairs(commit_characters) do
    "          \     if v == key then
    "          \       vim.fn['pum#map#confirm']()
    "          \       break
    "          \     end
    "          \   end
    "          \ end)
    "    const s:check_commit_characters_handler = v:true
    "  endif
    "endif

    autocmd InsertCharPre * ++once call s:check_commit_characters()
  endif

  call pum#popup#_reset_auto_confirm(mode())

  return ''
endfunction

function pum#map#insert_relative(delta, overflow='empty') abort
  if mode() ==# 't'
    " It does not work well in terminal mode.
    return ''
  endif

  if s:check_textwidth()
    " NOTE: If the input text is longer than 'textwidth', the completed text
    " will be the next line.  It breaks insert behavior.
    call pum#map#select_relative(a:delta, a:overflow)
    return
  endif

  let pum = pum#_get()

  let prev_word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input

  call pum#map#select_relative(a:delta, a:overflow)

  if pum.cursor < 0 || pum.id <= 0
    let pum.current_word = ''
    return ''
  endif

  call s:insert_current_word(prev_word, v:null)

  if pum.horizontal_menu
    call pum#popup#_redraw_horizontal_menu()
  endif

  " Close popup menu and CompleteDone if user input
  call s:check_user_input({ -> pum#close() })

  return ''
endfunction

function pum#map#longest_relative(delta, overflow='empty') abort
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
    return pum#map#insert_relative(a:delta, a:overflow)
  endif

  " Insert the longest word.
  call s:insert(common_str, prev_word, v:null)

  let pum.orig_input = common_str
  let pum.skip_complete = v:false

  return ''
endfunction

function pum#map#confirm() abort
  let pum = pum#_get()

  if pum.cursor > 0 && pum.current_word ==# ''
    call s:insert_current_word(pum.orig_input,
          \ { -> s:skip_next_complete('confirm') })
  else
    call s:skip_next_complete('confirm')
  endif

  " Reset v:completed_item to prevent CompleteDone is twice
  autocmd TextChangedI,TextChangedP * ++once
        \ let v:completed_item = {}

  return ''
endfunction
function pum#map#confirm_word() abort
  let pum = pum#_get()

  if pum.cursor > 0
    " Get non space characters
    const word = pum.items[pum.cursor - 1].word->matchstr('^\S\+')
    call s:insert(word, pum.orig_input,
          \ { -> s:skip_next_complete('confirm_word') })
  else
    call s:skip_next_complete('confirm_word')
  endif

  " Reset v:completed_item to prevent CompleteDone is twice
  autocmd TextChangedI,TextChangedP * ++once
        \ let v:completed_item = {}

  return ''
endfunction

function pum#map#cancel() abort
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

function pum#map#select_relative_page(delta, overflow='empty') abort
  call pum#map#select_relative(
        \ (a:delta * pum#_get().height)->float2nr(), a:overflow)
  return ''
endfunction
function pum#map#insert_relative_page(delta, overflow='empty') abort
  call pum#map#insert_relative(
        \ (a:delta * pum#_get().height)->float2nr(), a:overflow)
  return ''
endfunction

function pum#map#scroll_preview(delta) abort
  let pum = pum#_get()
  if pum.preview_id < 0 || a:delta ==# 0
    return ''
  endif

  const command = printf('noautocmd silent execute "normal! %s"',
        \                repeat(a:delta > 0 ? "\<C-e>": "\<C-y>",
        \                       a:delta > 0 ? a:delta : -a:delta))
  call win_execute(pum.preview_id, command)
  call pum#popup#_redraw_preview()
  return ''
endfunction

function s:skip_next_complete(event = 'complete_done') abort
  " Skip completion until next input

  call pum#close(a:event)

  let pum = pum#_get()
  let pum.skip_complete = v:true

  " Note: s:check_user_input() does not work well in terminal mode
  if mode() ==# 't' && !has('nvim')
    autocmd TextChangedT * ++once call pum#_reset_skip_complete()
  else
    call s:check_user_input({ -> pum#_reset_skip_complete() })
  endif
endfunction

function s:insert(word, prev_word, after_func) abort
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
  call pum#_inc_skip_complete()

  if mode() ==# 'c'
    " NOTE: setcmdpos() does not work in command line mode!
    call setcmdline(prev_input .. a:word .. next_input,
          \ pum.startcol + len(a:word))
  elseif mode() ==# 't'
    call s:insert_line_jobsend(a:word)
  elseif pum#_options().use_setline
    call setline('.', prev_input .. a:word .. next_input)
    call cursor(0, pum.startcol + len(a:word))
  elseif a:word ==# '' || a:after_func != v:null
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
function s:insert_current_word(prev_word, after_func) abort
  let pum = pum#_get()

  const word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input
  call s:insert(word, a:prev_word, a:after_func)
endfunction

function s:check_user_input(callback) abort
  augroup pum-temp
    autocmd!
  augroup END

  let g:PumCallback = function(a:callback)

  let pum = pum#_get()
  let pum.current_line = pum#_getline()[: pum.startcol]

  let s:prev_line = pum#_getline()

  if mode() ==# 'c'
    autocmd CmdlineLeave * ++once
          \ call pum#_reset_skip_complete()
  elseif mode() ==# 't'
    if has('nvim')
      if !'s:check_user_input_handler'->exists()
        lua vim.on_key(function(key)
              \   if string.match(key, '^%C$') then
              \     vim.fn['pum#close']()
              \   end
              \ end)
        const s:check_user_input_handler = v:true
      endif
    else
      autocmd pum-temp TextChangedT * call s:check_text_changed()
    endif
  else
    autocmd pum-temp InsertLeave * ++once
          \ call pum#_reset_skip_complete()
    autocmd pum-temp TextChangedI * call s:check_text_changed()
  endif
endfunction
function s:check_text_changed() abort
  let pum = pum#_get()
  const current_line = pum#_getline()
  if pum.skip_complete
    let s:prev_line = current_line
    return
  endif

  if pum#_row() != pum.startrow || current_line !=# s:prev_line
    call pum#close()
  endif
  let s:prev_line = current_line
endfunction
function s:check_commit_characters() abort
  if pum#_options().commit_characters->index(v:char) < 0 || !pum#visible()
    return
  endif

  let pum = pum#_get()
  const word = pum.cursor > 0 ?
        \ pum.items[pum.cursor - 1].word :
        \ pum.orig_input
  if word ==# pum.current_word || word->stridx(pum.orig_input) < 0
    " It must be head match
    return
  endif

  let v:char = word[pum.orig_input->len() :] .. v:char
endfunction

function s:insert_line_feedkeys(text, after_func) abort
  " feedkeys() implementation

  " NOTE: ":undojoin" is needed to prevent undo breakage
  const tree = undotree()
  if tree.seq_cur == tree.seq_last
    undojoin
  endif

  const current_word = pum#_getline()[pum#_get().startcol - 1 : pum#_col() - 2]
  let chars = "\<BS>"->repeat(current_word->strchars()) .. a:text
  if mode() ==# 'i' && !'s:save_backspace'->exists()
    " NOTE: Change backspace option to work <BS> correctly
    let s:save_backspace = &backspace
    " NOTE: Disable indentkeys
    let s:save_indentkeys = &l:indentkeys

    set backspace=start
    set indentkeys=

    " NOTE: Restore options
    autocmd TextChangedI,TextChangedP * ++once
          \ : if 's:save_backspace'->exists()
          \ |   let &backspace = s:save_backspace
          \ |   unlet! s:save_backspace
          \ |   let &l:indentkeys = s:save_indentkeys
          \ |   unlet! s:save_save_indentkeys
          \ | endif
  endif
  if a:after_func != v:null
    let g:PumCallback = function(a:after_func)
    let chars ..= "\<Cmd>call call(g:PumCallback, [])\<CR>"
  endif

  call feedkeys(chars, 'in')
endfunction

function s:insert_line_complete(text) abort
  " complete() implementation

  " NOTE: Restore completeopt is needed after complete()
  autocmd TextChangedI,TextChangedP * ++once
        \ : if 's:save_completeopt'->exists()
        \ |   let &completeopt = s:save_completeopt
        \ |   unlet! s:save_completeopt
        \ |   let &eventignore = s:save_eventignore
        \ |   unlet! s:save_eventignore
        \ | endif

  let s:save_completeopt = &completeopt
  let s:save_eventignore = &eventignore
  set completeopt=menu
  set eventignore=CompleteDone,ModeChanged

  call complete(pum#_get().startcol, [a:text])

  " NOTE: Hide native popup menu.
  " Because native popup menu disables user insert mappings.
  call feedkeys("\<C-x>\<C-z>", 'in')
endfunction

function s:insert_line_jobsend(text) abort
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

function s:check_textwidth() abort
  if mode() ==# 'i' && &l:formatoptions =~# '[tca]' && &l:textwidth > 0
    const pum = pum#_get()
    const startcol = pum.startcol - 1
    const prev_input = startcol == 0 ? '' : pum#_getline()[: startcol - 1]
    const word = pum.cursor > 0 ?
          \ pum.items[pum.cursor - 1].word :
          \ pum.orig_input
    if (prev_input .. word)->strdisplaywidth() >= &l:textwidth
      return v:true
    endif
  endif

  return v:false
endfunction
