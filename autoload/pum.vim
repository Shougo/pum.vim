let g:pum#_namespace = has('nvim') ? nvim_create_namespace('pum') : 0
let g:pum#completed_item = {}
let s:pum_cursor_id = 50


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

  let s:pum = #{
        \ auto_confirm_timer: -1,
        \ buf: -1,
        \ items: [],
        \ cursor: -1,
        \ current_word: '',
        \ height: -1,
        \ horizontal_menu: v:false,
        \ id: -1,
        \ len: 0,
        \ orig_input: '',
        \ pos: [],
        \ reversed: v:false,
        \ scroll_buf: -1,
        \ scroll_id: -1,
        \ skip_complete: v:false,
        \ startcol: -1,
        \ startrow: -1,
        \ width: -1,
        \ border_width: 0,
        \ border_height: 0,
        \}
endfunction
function! pum#_options() abort
  if !exists('s:options')
    let s:options = #{
          \ auto_confirm_time: 0,
          \ auto_select: &completeopt =~# 'noinsert',
          \ border: 'none',
          \ highlight_columns: {},
          \ highlight_horizontal_menu: '',
          \ highlight_matches: '',
          \ highlight_normal_menu: 'Pmenu',
          \ highlight_scroll_bar: 'PmenuSbar',
          \ highlight_selected: 'PmenuSel',
          \ horizontal_menu: v:false,
          \ item_orders: ['abbr', 'kind', 'menu'],
          \ max_horizontal_items: 3,
          \ max_height: &pumheight,
          \ max_width: 0,
          \ min_width: &pumwidth,
          \ offset_row: has('nvim') || v:version >= 900 ? 0 : 1,
          \ padding: v:false,
          \ reversed: v:false,
          \ scrollbar_char: '|',
          \ use_complete: v:false,
          \ zindex: 1000,
          \ }
  endif
  return s:options
endfunction

function! pum#set_option(key_or_dict, value = '') abort
  let dict = pum#util#_normalize_key_or_dict(a:key_or_dict, a:value)
  call extend(pum#_options(), dict)
endfunction

function! pum#open(startcol, items, mode = mode(), insert = v:false) abort
  if !has('patch-8.2.1978') && !has('nvim-0.8')
    call pum#util#_print_error(
          \ 'pum.vim requires Vim 8.2.1978+ or neovim 0.8.0+.')
    return -1
  endif

  if empty(a:items)
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

function! pum#close() abort
  if !pum#visible()
    return
  endif

  let pum = pum#_get()
  if pum.id <= 0
    return
  endif

  call s:complete_done()
  if exists('#User#PumClose')
    silent! doautocmd <nomodeline> User PumClose
  endif

  " NOTE: pum.scroll_id is broken after pum#popup#_close()
  let id = pum.id
  let scroll_id = pum.scroll_id

  call pum#popup#_close(id)
  call pum#popup#_close(scroll_id)
endfunction

function! s:to_bool(int_boolean_value) abort
  return a:int_boolean_value ==# 1 ? v:true : v:false
endfunction

function! pum#visible() abort
  return s:to_bool(pum#_get().id > 0)
endfunction

function! pum#entered() abort
  let info = pum#complete_info()
  return s:to_bool(info.pum_visible && (info.selected >= 0 || info.inserted != ''))
endfunction

function! pum#complete_info(...) abort
  let pum = pum#_get()
  let info = #{
        \ mode: '',
        \ pum_visible: pum#visible(),
        \ items: pum.items,
        \ selected: pum.cursor - 1,
        \ inserted: pum.current_word,
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
function! pum#current_item() abort
  let info = pum#complete_info()
  return get(info.items, info.selected, {})
endfunction

function! pum#get_pos() abort
  if !pum#visible()
    return {}
  endif

  let pum = pum#_get()
  return #{
        \ height: pum.height + pum.border_height,
        \ width: pum.width + pum.border_width,
        \ row: pum.pos[0],
        \ col: pum.pos[1],
        \ size: pum.len,
        \ scrollbar: v:false,
        \ }
endfunction

function! pum#skip_complete() abort
  return pum#_get().skip_complete
endfunction

function! pum#_getline() abort
  return mode() ==# 'c' ? getcmdline() :
        \ mode() ==# 't' && !has('nvim') ? term_getline('', '.') :
        \ getline('.')
endfunction
function! pum#_row() abort
  let row = mode() ==# 't' && !has('nvim') ?
        \ term_getcursor(bufnr('%'))[0] :
        \ line('.')
  return row
endfunction
function! pum#_col() abort
  let col = mode() ==# 't' && !has('nvim') ?
        \ term_getcursor(bufnr('%'))[1] :
        \ mode() ==# 'c' ? getcmdpos() :
        \ mode() ==# 't' ? col('.') : col('.')
  return col
endfunction

function! pum#_cursor_id() abort
  return s:pum_cursor_id
endfunction

function! pum#_redraw_horizontal_menu() abort
  let pum = pum#_get()

  if empty(pum.items)
    return
  endif

  if pum.cursor == 0
    let items = copy(pum.items)
  else
    let cursor = pum.cursor - 1
    let items = [pum.items[cursor]]
    let items += pum.items[cursor + 1:]
    if cursor > 0
      let items += pum.items[: cursor - 1]
    endif
  endif

  let max_items = pum#_options().max_horizontal_items

  if len(pum.items) > max_items
    let items = items[: max_items - 1]
  endif

  let word = printf('{ %s%s%s}',
        \ pum.cursor == 0 ? '' : '> ',
        \ join(map(items, { _, val -> get(val, 'abbr', val.word) })),
        \ len(pum.items) <= max_items ? '' : ' ... ',
        \ )

  let options = pum#_options()

  if has('nvim')
    call nvim_buf_clear_namespace(0, g:pum#_namespace, 0, -1)

    call nvim_buf_set_extmark(
          \ 0, g:pum#_namespace, line('.') - 1, 0,
          \ #{
          \   virt_text: [[word, options.highlight_horizontal_menu]],
          \   hl_mode: 'combine',
          \   priority: 0,
          \ })

    " Dummy
    let pum.id = 1000
  else
    let winopts = #{
          \ pos: 'topleft',
          \ line: line('.'),
          \ col: col('.') + 3,
          \ highlight: options.highlight_horizontal_menu,
          \ }
    let lines = [word]

    if pum.id > 0
      call popup_move(pum.id, winopts)
      call popup_settext(pum.id, lines)
    else
      let pum.id = popup_create(lines, winopts)
      let pum.buf = winbufnr(pum.id)
    endif
  endif
endfunction

function! pum#_format_item(item, options, mode, startcol, max_columns) abort
  let columns = extend(copy(get(a:item, 'columns', {})), #{
        \   abbr: get(a:item, 'abbr', a:item.word),
        \   kind: get(a:item, 'kind', ''),
        \   menu: get(a:item, 'menu', ''),
        \ })

  let str = ''
  for order in a:options.item_orders
    if get(a:max_columns, order, 0) <= 0
      continue
    endif

    if str !=# ''
      let str .= ' '
    endif

    let column = substitute(get(columns, order, ''), '[[:cntrl:]]', '?', 'g')
    if order ==# 'abbr' && column ==# ''
      " Fallback to "word"
      let column = a:item.word
    endif
    let column .= repeat(' ' , a:max_columns[order] - strdisplaywidth(column))

    let str .= column
  endfor

  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let str = ' ' . str . ' '
  endif

  return str
endfunction

function! s:complete_done() abort
  let pum = pum#_get()

  call pum#_reset_skip_complete()

  if pum.cursor <= 0 || pum.current_word ==# ''
        \ || len(pum.items) < pum.cursor
    return
  endif

  let g:pum#completed_item = pum.items[pum.cursor - 1]

  " NOTE: Old Vim/neovim does not support v:completed_item changes
  silent! let v:completed_item = g:pum#completed_item

  if mode() ==# 'i' && v:completed_item ==# g:pum#completed_item
    " NOTE: Call CompleteDone when insert mode only

    " NOTE: It may be failed when InsertCharPre
    silent! doautocmd <nomodeline> CompleteDone
  endif

  if exists('#User#PumCompleteDone')
    " NOTE: It may be failed when InsertCharPre
    silent! doautocmd <nomodeline> User PumCompleteDone
  endif
endfunction

function! pum#_reset_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:false
endfunction
