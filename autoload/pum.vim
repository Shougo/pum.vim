let g:pum#completed_item = {}
let g:pum#completed_event = ''


function pum#_get() abort
  if !'s:pum'->exists()
    call pum#_init()
  endif
  return s:pum
endfunction
function pum#_init() abort
  if 's:pum'->exists()
    call pum#close()
  endif

  let s:pum = #{
        \   auto_confirm_timer: -1,
        \   buf: -1,
        \   changedtick: b:changedtick,
        \   items: [],
        \   cursor: -1,
        \   current_word: '',
        \   height: -1,
        \   horizontal_menu: v:false,
        \   id: -1,
        \   inserted_buf: -1,
        \   inserted_id: -1,
        \   len: 0,
        \   matched_id: 70,
        \   namespace: has('nvim') ? nvim_create_namespace('pum') : 0,
        \   orig_input: '',
        \   pos: [],
        \   preview: v:false,
        \   preview_buf: -1,
        \   preview_id: -1,
        \   reversed: v:false,
        \   scroll_buf: -1,
        \   scroll_id: -1,
        \   selected_id: -1,
        \   skip_complete: v:false,
        \   skip_count: 0,
        \   startcol: -1,
        \   startrow: -1,
        \   width: -1,
        \   border_width: 0,
        \   border_height: 0,
        \ }
endfunction
function pum#_init_options() abort
  let s:options = #{
        \   auto_confirm_time: 0,
        \   auto_select: &completeopt =~# 'noinsert',
        \   blend: '+pumblend'->exists() ? &pumblend : 0,
        \   border: 'none',
        \   commit_characters: [],
        \   direction: 'auto',
        \   follow_cursor: v:false,
        \   highlight_columns: {},
        \   highlight_horizontal_menu: '',
        \   highlight_horizontal_separator: 'PmenuSbar',
        \   highlight_inserted: 'PmenuMatchIns',
        \   highlight_lead: 'PmenuMatchLead',
        \   highlight_matches: '',
        \   highlight_normal_menu: 'Pmenu',
        \   highlight_preview: '',
        \   highlight_scrollbar: 'PmenuSbar',
        \   highlight_selected: 'PmenuSel',
        \   horizontal_menu: v:false,
        \   insert_preview: v:false,
        \   item_orders: [
        \     'abbr', 'space', 'kind', 'space', 'menu',
        \   ],
        \   max_columns: #{
        \     kind: 10,
        \     menu: 20,
        \   },
        \   max_height: &pumheight,
        \   max_horizontal_items: 3,
        \   max_width: 0,
        \   min_height: 0,
        \   min_width: &pumwidth,
        \   offset_cmdcol: 0,
        \   offset_cmdrow: 0,
        \   offset_col: 0,
        \   offset_row: 0,
        \   padding: v:false,
        \   preview: v:false,
        \   preview_border: 'none',
        \   preview_delay: 500,
        \   preview_height: &previewheight,
        \   preview_width: &pumwidth / 2,
        \   reversed: v:false,
        \   scrollbar_char: '|',
        \   use_setline: v:false,
        \   zindex: 1000,
        \ }
  let s:local_options = {}
endfunction
function pum#_options() abort
  if !'s:options'->exists()
    call pum#_init_options()
  endif

  let options = s:options->copy()

  const mode = mode()

  let local_options = s:local_options->get(mode, {})
  if mode ==# 'c'
    " Use getcmdtype()
    call extend(local_options, s:local_options->get(getcmdtype(), {}))
  endif
  if 'b:buffer_options'->exists()
    call extend(local_options, b:buffer_options)
  endif

  call extend(options, local_options)

  return options
endfunction

function pum#set_option(key_or_dict, value = '') abort
  if !'s:options'->exists()
    call pum#_init_options()
  endif

  const dict = pum#util#_normalize_key_or_dict(a:key_or_dict, a:value)
  call s:check_options(dict)

  call extend(s:options, dict)

  call pum#popup#_close_preview()
endfunction
function pum#set_local_option(mode, key_or_dict, value = '') abort
  if !'s:options'->exists()
    call pum#_init_options()
  endif

  const dict = pum#util#_normalize_key_or_dict(a:key_or_dict, a:value)
  call s:check_options(dict)

  if !s:local_options->has_key(a:mode)
    let s:local_options[a:mode] = {}
  endif
  call extend(s:local_options[a:mode], dict)
endfunction
function pum#set_buffer_option(key_or_dict, value = '') abort
  if !'s:options'->exists()
    call pum#_init_options()
  endif
  if !'b:buffer_options'->exists()
    let b:buffer_options = {}
  endif

  const dict = pum#util#_normalize_key_or_dict(a:key_or_dict, a:value)
  call s:check_options(dict)

  call extend(b:buffer_options, dict)
endfunction
function s:check_options(options) abort
  const default_keys = s:options->keys()

  for key in a:options->keys()
    if default_keys->index(key) < 0
      call pum#util#_print_error('Invalid option: ' .. key)
    endif
  endfor
endfunction

function pum#open(startcol, items, mode = mode(), insert = v:false) abort
  if !has('patch-9.1.0448') && !has('nvim-0.10')
    call pum#util#_print_error(
          \ 'pum.vim requires Vim 9.1.0448+ or neovim 0.10.0+.')
    return -1
  endif

  if a:items->empty() || pumvisible() || wildmenumode()
    call pum#close()
    return
  endif

  try
    return pum#popup#_open(a:startcol, a:items, a:mode, a:insert)
  catch /E523:\|E565:\|E5555:/
    " Ignore "Not allowed here"
    return -1
  endtry
endfunction

function pum#close(event = 'complete_done', close_window = v:true) abort
  if !pum#visible()
    return
  endif

  let pum = pum#_get()
  if pum.id <= 0
    return
  endif

  call pum#_reset_skip_complete()

  call pum#_stop_debounce_timer('s:debounce_preview_timer')
  call pum#popup#_close_preview()

  call pum#popup#_close_inserted()

  if pum.cursor >= 0 && pum.current_word !=# ''
        \ && pum.items->len() >= pum.cursor
    " Call the event later
    " NOTE: It may be failed when inside autocmd
    let completed_item = pum.items[pum.cursor - 1]
    call timer_start(1, { -> s:complete_done(completed_item, a:event) })
  endif

  if '#User#PumClose'->exists()
    doautocmd <nomodeline> User PumClose
  endif

  if a:close_window
    " NOTE: pum.scroll_id is broken after pum#popup#_close()
    const id = pum.id
    const scroll_id = pum.scroll_id

    call pum#popup#_close(id)
    call pum#popup#_close(scroll_id)
  endif
endfunction

function s:to_bool(int_boolean_value) abort
  return a:int_boolean_value ==# 1 ? v:true : v:false
endfunction

function pum#visible() abort
  return (pum#_get().id > 0)->s:to_bool()
endfunction

function pum#preview_visible() abort
  return (pum#_get().preview_id > 0)->s:to_bool()
endfunction

function pum#open_preview() abort
  return pum#popup#_preview()
endfunction

function pum#entered() abort
  const info = pum#complete_info()
  const selected = (!pum#_options().auto_select && info.selected == 0)
        \ || info.selected > 0
  return (info.pum_visible && (selected || info.inserted != ''))->s:to_bool()
endfunction

function pum#complete_info(...) abort
  let pum = pum#_get()
  let info = #{
        \   mode: '',
        \   pum_visible: pum#visible(),
        \   items: pum.items,
        \   selected: pum.cursor > 0 ? pum.cursor - 1 : -1,
        \   inserted: pum.current_word,
        \ }

  if a:0 == 0 || type(a:1) != v:t_list
    return info
  endif

  let ret = {}
  for what in a:1->copy()->filter({ _, val -> info->has_key(val) })
    let ret[what] = info[what]
  endfor

  return ret
endfunction
function pum#current_item() abort
  let info = pum#complete_info()
  return info.items->get(info.selected, {})
endfunction

function pum#update_current_item(dict) abort
  call extend(pum#current_item(), a:dict)

  call pum#_complete_changed()
endfunction

function pum#get_pos() abort
  if !pum#visible()
    return {}
  endif

  let pum = pum#_get()
  return #{
        \   height: pum.height + pum.border_height,
        \   width: pum.width + pum.border_width,
        \   row: pum.pos[0],
        \   col: pum.pos[1],
        \   size: pum.len,
        \   scrollbar: pum.scroll_id > 0,
        \ }
endfunction

function pum#get_preview_buf() abort
  return pum#_get().preview_buf
endfunction

function pum#skip_complete() abort
  let pum = pum#_get()
  let skip = pum.skip_complete

  let pum.skip_count -= 1
  if pum.skip_count <= 0
    call pum#_reset_skip_complete()
  endif

  return skip
endfunction
function pum#_inc_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:true
  let pum.skip_count += 1
endfunction

function pum#_getline() abort
  return mode() ==# 'c' ? getcmdline() :
        \ mode() ==# 't' && !has('nvim') ? ''->term_getline('.') :
        \ '.'->getline()
endfunction
function pum#_row() abort
  const row = mode() ==# 't' && !has('nvim') ?
        \ '%'->bufnr()->term_getcursor()[0] :
        \ '.'->line()
  return row
endfunction
function pum#_col() abort
  const col = mode() ==# 't' && !has('nvim') ?
        \ bufnr('%')->term_getcursor()[1] :
        \ mode() ==# 'c' ? getcmdpos() :
        \ mode() ==# 't' ? '.'->col() : '.'->col()
  return col
endfunction

function pum#_format_item(
      \ item, options, mode, startcol, max_columns, abbr_width) abort
  const columns = a:item->get('columns', {})->copy()
        \ ->extend(#{
        \   abbr: a:item->get('abbr', a:item.word),
        \   kind: a:item->get('kind', ''),
        \   menu: a:item->get('menu', ''),
        \ })

  let str = ''
  for [name, max_column] in a:max_columns
    if name ==# 'space'
      let str ..= ' '
      continue
    endif

    if name ==# 'abbr'
      let max_column = a:abbr_width
    endif

    let column = columns->get(name, '')->substitute('[[:cntrl:]]', '?', 'g')
    if name ==# 'abbr' && column ==# ''
      " Fallback to "word"
      let column = a:item.word
    endif

    if column->strdisplaywidth() > max_column
      " Truncate
      let column = column->pum#util#_truncate(
            \ max_column, max_column / 3, '...')
    endif
    if column->strdisplaywidth() < max_column
      " Padding
      let column ..= ' '->repeat(max_column - column->strdisplaywidth())
    endif

    let str ..= column
  endfor

  if a:options.padding
    let str ..= ' '

    if a:mode ==# 'c' || a:startcol != 1
      let str = ' ' .. str
    endif
  endif

  return str
endfunction

function s:complete_done(completed_item, event) abort
  let g:pum#completed_item = a:completed_item
  let g:pum#completed_event = a:event

  if '#User#PumCompleteDonePre'->exists()
    doautocmd <nomodeline> User PumCompleteDonePre
  endif

  " Create new undo point
  let &l:undolevels = &l:undolevels

  let v:completed_item = g:pum#completed_item

  if mode() ==# 'i' && v:completed_item ==# g:pum#completed_item
    " NOTE: The events are available for insert mode only

    if '#CompleteDonePre'->exists()
      doautocmd <nomodeline> CompleteDonePre
    endif

    if '#CompleteDone'->exists()
      doautocmd <nomodeline> CompleteDone
    endif

    " NOTE: v:completed_item may be changed
    if v:completed_item !=# g:pum#completed_item
      let g:pum#completed_item = v:completed_item
    endif
  endif

  if '#User#PumCompleteDone'->exists()
    doautocmd <nomodeline> User PumCompleteDone
  endif
endfunction

function pum#_reset_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:false
  let pum.skip_count = 0
endfunction

function pum#_complete_changed() abort
  let pum = pum#_get()
  let options = pum#_options()

  if pum.preview
    call pum#_stop_debounce_timer('s:debounce_preview_timer')

    " NOTE: In terminal mode, the timer does not work well.
    if mode() ==# 't'
      call pum#popup#_preview()
    else
      let s:debounce_preview_timer = timer_start(
            \ options.preview_delay, { -> pum#popup#_preview() })
    endif
  endif

  if '#User#PumCompleteChanged'->exists()
    doautocmd <nomodeline> User PumCompleteChanged
  endif
endfunction

function pum#_stop_debounce_timer(timer_name) abort
  if a:timer_name->exists()
    silent! call timer_stop({a:timer_name})
    unlet {a:timer_name}
  endif
endfunction
