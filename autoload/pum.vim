let g:pum#_namespace = has('nvim') ? nvim_create_namespace('pum') : 0
let g:pum#completed_item = {}
let s:pum_cursor_id = 50


function! pum#_get() abort
  if !('s:pum'->exists())
    call pum#_init()
  endif
  return s:pum
endfunction
function! pum#_init() abort
  if 's:pum'->exists()
    call pum#close()
  endif

  let s:pum = #{
        \   auto_confirm_timer: -1,
        \   buf: -1,
        \   items: [],
        \   cursor: -1,
        \   current_word: '',
        \   height: -1,
        \   horizontal_menu: v:false,
        \   id: -1,
        \   len: 0,
        \   orig_input: '',
        \   pos: [],
        \   reversed: v:false,
        \   scroll_buf: -1,
        \   scroll_id: -1,
        \   skip_complete: v:false,
        \   startcol: -1,
        \   startrow: -1,
        \   width: -1,
        \   border_width: 0,
        \   border_height: 0,
        \ }
endfunction
function! pum#_options() abort
  if !('s:options'->exists())
    let s:options = #{
          \   auto_confirm_time: 0,
          \   auto_select: &completeopt =~# 'noinsert',
          \   border: 'none',
          \   highlight_columns: {},
          \   highlight_horizontal_menu: '',
          \   highlight_matches: '',
          \   highlight_normal_menu: 'Pmenu',
          \   highlight_scroll_bar: 'PmenuSbar',
          \   highlight_selected: 'PmenuSel',
          \   horizontal_menu: v:false,
          \   item_orders: ['abbr', 'kind', 'menu'],
          \   max_horizontal_items: 3,
          \   max_height: &pumheight,
          \   max_width: 0,
          \   min_width: &pumwidth,
          \   offset_row: has('nvim') || v:version >= 900 ? 0 : 1,
          \   padding: v:false,
          \   reversed: v:false,
          \   scrollbar_char: '|',
          \   use_complete: v:false,
          \   use_setline: v:false,
          \   zindex: 1000,
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

  if a:items->empty()
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

  call pum#_reset_skip_complete()

  if pum.cursor >= 0 && pum.current_word !=# ''
        \ && pum.items->len() >= pum.cursor
    " Call the event later
    " NOTE: It may be failed when inside autocmd
    let completed_item = pum.items[pum.cursor - 1]
    call timer_start(1, { -> s:complete_done(completed_item) })
  endif

  if '#User#PumClose'->exists()
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
  return s:to_bool(info.pum_visible
        \ && (info.selected >= 0 || info.inserted != ''))
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
  for what in a:1->copy()->filter({ _, val -> info->has_key(val) })
    let ret[what] = info[what]
  endfor

  return ret
endfunction
function! pum#current_item() abort
  let info = pum#complete_info()
  return info.items->get(info.selected, {})
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
        \ mode() ==# 't' && !has('nvim') ? ''->term_getline('.') :
        \ '.'->getline()
endfunction
function! pum#_row() abort
  let row = mode() ==# 't' && !has('nvim') ?
        \ '%'->bufnr()->term_getcursor()[0] :
        \ '.'->line()
  return row
endfunction
function! pum#_col() abort
  let col = mode() ==# 't' && !has('nvim') ?
        \ bufnr('%')->term_getcursor()[1] :
        \ mode() ==# 'c' ? getcmdpos() :
        \ mode() ==# 't' ? '.'->col() : '.'->col()
  return col
endfunction

function! pum#_cursor_id() abort
  return s:pum_cursor_id
endfunction

function! pum#_format_item(item, options, mode, startcol, max_columns) abort
  let columns = a:item->get('columns', {})->copy()->extend(#{
        \   abbr: get(a:item, 'abbr', a:item.word),
        \   kind: get(a:item, 'kind', ''),
        \   menu: get(a:item, 'menu', ''),
        \ })

  let str = ''
  for order in a:options.item_orders
    if a:max_columns->get(order, 0) <= 0
      continue
    endif

    if str !=# ''
      let str .= ' '
    endif

    let column = columns->get(order, '')->substitute('[[:cntrl:]]', '?', 'g')
    if order ==# 'abbr' && column ==# ''
      " Fallback to "word"
      let column = a:item.word
    endif
    let column .= ' '->repeat(a:max_columns[order] - strdisplaywidth(column))

    let str .= column
  endfor

  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let str = ' ' .. str .. ' '
  endif

  return str
endfunction

function! s:complete_done(completed_item) abort
  let g:pum#completed_item = a:completed_item

  " NOTE: Old Vim/neovim does not support v:completed_item changes
  silent! let v:completed_item = g:pum#completed_item

  if mode() ==# 'i' && v:completed_item ==# g:pum#completed_item
    " NOTE: Call CompleteDone when insert mode only
    doautocmd <nomodeline> CompleteDone
  endif

  if exists('#User#PumCompleteDone')
    doautocmd <nomodeline> User PumCompleteDone
  endif
endfunction

function! pum#_reset_skip_complete() abort
  let pum = pum#_get()
  let pum.skip_complete = v:false
endfunction
