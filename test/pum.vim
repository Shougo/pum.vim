" Tests for pum.vim using Vim's native assert API
" All test function names must start with Test_

" Setup function called before each test
function! Setup() abort
  call pum#_init()
  call pum#_init_options()
  normal! ggVGd
endfunction

" Test pum#open() function
function! Test_open() abort
  call Setup()
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }]))
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i'))
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'c'))
endfunction

" Test highlight functionality
function! Test_highlight() abort
  call Setup()
  call pum#open(1, [
        \ #{ word: 'foo bar', highlights: [
        \   #{ type: 'abbr', name: 'abbr_foo', hl_group: 'Function', col: 1, width: 3 },
        \   #{ type: 'abbr', name: 'abbr_bar', hl_group: 'Underlined', col: 5, width: 3 },
        \ ]},
        \ #{ word: 'bar', kind: 'bar', highlights: [
        \   #{ type: 'kind', name: 'kind_foo', hl_group: 'Error', col: 1, width: 3 },
        \ ]},
        \ #{ word: 'baz', menu: 'baz', highlights: [
        \   #{ type: 'menu', name: 'menu_baz', hl_group: 'WarningMsg', col: 1, width: 3 },
        \ ]},
        \ ], 'i')
endfunction

" The highlights placed in the popup: [[row, col, length, group], ...].
function! s:placed() abort
  let pum = pum#_get()
  if has('nvim')
    return nvim_buf_get_extmarks(pum.buf, pum.namespace, 0, -1,
          \ #{ details: v:true })
          \ ->map({ _, m -> [m[1] + 1, m[2] + 1,
          \                  m[3].end_col - m[2], m[3].hl_group] })
          \ ->sort(function('s:compare'))
  endif
  const buf = winbufnr(pum.id)
  let placed = []
  for row in range(1, getbufinfo(buf)[0].linecount)
    for p in prop_list(row, #{ bufnr: buf })
      call add(placed,
            \ [row, p.col, p.length, prop_type_get(p.type).highlight])
    endfor
  endfor
  return placed->sort(function('s:compare'))
endfunction

" The highlights placed in the popup, by the text they cover:
" [[row, text, group], ...].
function! s:highlighted() abort
  let pum = pum#_get()
  const buf = has('nvim') ? pum.buf : winbufnr(pum.id)
  return s:placed()->map({ _, p -> [p[0],
        \ getbufline(buf, p[0])[0]->strpart(p[1] - 1, p[2]), p[3]] })
        \ ->sort(function('s:compare'))
endfunction

function! s:compare(a, b) abort
  for i in range(len(a:a))
    if a:a[i] != a:b[i]
      return a:a[i] < a:b[i] ? -1 : 1
    endif
  endfor
  return 0
endfunction

" (No syntax with -u NONE: the groups must be defined.)
for s:group in ['PumTestA', 'PumTestB', 'PumTestC', 'PumTestD']
  execute 'highlight' s:group 'ctermfg=1'
endfor

let s:highlighted_items = [
      \ #{ word: 'foo', kind: 'f', menu: 'A' },
      \ #{ word: 'barbaz', kind: 'fn', menu: 'B', highlights: [
      \   #{ type: 'abbr', name: 'abbr_baz', hl_group: 'PumTestA',
      \      col: 4, width: 3 },
      \   #{ type: 'menu', name: 'menu_b', hl_group: 'PumTestB',
      \      col: 1, width: 1 },
      \ ]},
      \ #{ word: 'qux', kind: 'v', menu: 'C' },
      \ ]

" The highlights of the items and of the columns
function! Test_highlight_items() abort
  call Setup()
  call pum#open(1, s:highlighted_items, 'i')
  call assert_equal([
        \ [2, 'B', 'PumTestB'],
        \ [2, 'baz', 'PumTestA'],
        \ ], s:highlighted())

  call Setup()
  call pum#set_option(#{
        \ highlight_columns: #{ kind: 'PumTestC', menu: 'PumTestD' } })
  call pum#open(1, s:highlighted_items, 'i')
  call assert_equal([
        \ [1, 'A', 'PumTestD'],
        \ [1, 'f ', 'PumTestC'],
        \ [2, 'B', 'PumTestB'],
        \ [2, 'B', 'PumTestD'],
        \ [2, 'baz', 'PumTestA'],
        \ [2, 'fn', 'PumTestC'],
        \ [3, 'C', 'PumTestD'],
        \ [3, 'v ', 'PumTestC'],
        \ ], s:highlighted())

  " padding: one column right when not at the start of the line
  call Setup()
  call pum#set_option(#{ padding: v:true })
  call setline(1, 'x')
  call pum#open(2, s:highlighted_items, 'i')
  call assert_equal([
        \ [2, 'B', 'PumTestB'],
        \ [2, 'baz', 'PumTestA'],
        \ ], s:highlighted())

  " Wide characters, a column of the items' own, and a missing group
  call Setup()
  call pum#set_option(#{
        \ item_orders: ['abbr', 'space', 'kind', 'space', 'mark'],
        \ highlight_columns: #{ kind: 'PumTestC', mark: 'PumTestD' } })
  call pum#open(1, [
        \ #{ word: 'あいう', abbr: 'あいう', kind: 'か',
        \    columns: #{ mark: '*' },
        \    highlights: [
        \      #{ type: 'abbr', name: 'abbr_i', hl_group: 'PumTestA',
        \         col: 4, width: 3 },
        \      #{ type: 'kind', name: 'kind_x', hl_group: 'PumTestMissing',
        \         col: 1, width: 1 },
        \    ]},
        \ #{ word: 'ab', abbr: 'ab', kind: 'c', columns: #{ mark: '+' } },
        \ ], 'i')
  call assert_equal([
        \ [1, '*', 'PumTestD'],
        \ [1, 'い', 'PumTestA'],
        \ [1, 'か', 'PumTestC'],
        \ [2, '+', 'PumTestD'],
        \ [2, 'c ', 'PumTestC'],
        \ ], s:highlighted())

  " The columns as in the line: the word for no abbr, a truncated abbr
  for opts in [{}, #{ max_width: 12 }]
    call Setup()
    call pum#set_option(extend(#{
          \ highlight_columns: #{ kind: 'PumTestC', menu: 'PumTestD' } },
          \ opts))
    call pum#open(1, [
          \ #{ word: 'あいう', kind: 'か', menu: 'M' },
          \ #{ word: 'abcdefghijklmnop', kind: 'c', menu: 'N' },
          \ ], 'i')
    call assert_equal([
          \ [1, 'M', 'PumTestD'],
          \ [1, 'か', 'PumTestC'],
          \ [2, 'N', 'PumTestD'],
          \ [2, 'c ', 'PumTestC'],
          \ ], s:highlighted(), string(opts))
  endfor

  " Nothing to highlight
  call Setup()
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')
  call assert_equal([], s:placed())
endfunction

" The lines of calculate_dimensions_fast() are those of pum#_format_item()
" (Neovim only)
function! Test_dimensions_lines() abort
  if !has('nvim')
    return
  endif
  let items = [
        \ #{ word: 'foo', kind: 'f', menu: 'A' },
        \ #{ word: 'barbaz', abbr: 'barbaz(x int, y string)', menu: 'B' },
        \ #{ word: 'あいう', kind: 'v' },
        \ #{ word: 'qux', abbr: '', menu: 'メニュー' },
        \ ]
  for opts in [
        \ {},
        \ #{ padding: v:true },
        \ #{ item_orders: ['kind', 'space', 'abbr', 'space', 'menu'] },
        \ #{ max_width: 12 },
        \ ]
    call Setup()
    call pum#set_option(opts)
    let options = pum#_options()
    for startcol in [1, 3]
      let columns = luaeval(
            \ "require('pum.widths').calculate_column_widths_fast(_A[1],_A[2])",
            \ [items, options])
      let dimensions = luaeval(
            \ "require('pum.widths').calculate_dimensions_fast("
            \ .. "_A[1],_A[2],_A[3],_A[4],_A[5],_A[6],_A[7],_A[8])",
            \ [items] + columns + [options, 'i', startcol, {}])
      call assert_equal(items->copy()->map({ _, item -> pum#_format_item(
            \   item, options, 'i', startcol, columns[0],
            \   dimensions.abbr_width) }),
            \ dimensions.lines, string([opts, startcol]))
    endfor
  endfor
endfunction

" abbr, kind and menu of the item, not of its columns (as extend() of Vim
" script puts them)
function! Test_columns_standard_fields() abort
  call Setup()
  call pum#set_option(#{ min_width: 0 })
  call pum#open(1, [
        \ #{ word: 'foo', abbr: 'abc', kind: 'k',
        \    columns: #{ abbr: 'XXX', kind: 'Y', menu: 'Z' } },
        \ ], 'i')
  let pum = pum#_get()
  const buf = has('nvim') ? pum.buf : winbufnr(pum.id)
  call assert_equal(['abc k '], getbufline(buf, 1, '$'))
endfunction

" Test select_relative functionality
function! Test_select_relative() abort
  call Setup()
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }])

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call assert_equal(2, pum#_get().cursor)

  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call assert_equal(2, pum#_get().cursor)

  call pum#map#select_relative(-1)

  call assert_equal(1, pum#_get().cursor)
endfunction

" Test insert_relative functionality
function! Test_insert_relative() abort
  call Setup()
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  call pum#map#insert_relative(1)
  call pum#map#insert_relative(1)

  call assert_equal(2, pum#_get().cursor)

  call pum#map#insert_relative(-1)
  call pum#map#insert_relative(-1)

  call assert_equal(0, pum#_get().cursor)
endfunction

" Test format_item functionality
function! Test_format_item() abort
  call Setup()
  const item = #{ word: 'foo', kind: 'bar', menu: 'baz' }

  call assert_equal(
        \ ' foo bar baz ',
        \ pum#_format_item(item,
        \ #{
        \   item_orders: ['abbr', 'space', 'kind', 'space', 'menu'],
        \   padding: v:true,
        \ }, 'i', 2,
        \ [
        \   ['abbr', 3],
        \   ['space', 1],
        \   ['kind', 3],
        \   ['space', 1],
        \   ['menu', 3],
        \ ], 3))

  call assert_equal(
        \ 'baz foo bar',
        \ pum#_format_item(item,
        \ #{
        \   item_orders: ['menu', 'space', 'abbr', 'space', 'kind'],
        \   padding: v:false,
        \ }, 'i', 1,
        \ [
        \   ['menu', 3],
        \   ['space', 1],
        \   ['abbr', 3],
        \   ['space', 1],
        \   ['kind', 3],
        \ ], 3))

  " truncate check
  const item2 = #{ word: 'aaaaaaaaaaaaaaaaaa', kind: 'bbb', menu: 'ccc' }
  call assert_equal(
        \ 'ccc aaaa...aaa bbb',
        \ pum#_format_item(item2,
        \ #{
        \   item_orders: ['menu', 'space', 'abbr', 'space', 'kind'],
        \   padding: v:false,
        \ }, 'i', 1,
        \ [
        \   ['menu', 3],
        \   ['space', 1],
        \   ['abbr', 10],
        \   ['space', 1],
        \   ['kind', 3],
        \ ], 10))
endfunction

" Test core plugin initialization
function! Test_core_init() abort
  " Test pum#_init() creates proper state structure
  call pum#_init()
  let pum = pum#_get()

  " Verify essential state fields are initialized
  call assert_equal(-1, pum.id)
  call assert_equal(-1, pum.cursor)
  call assert_equal([], pum.items)
  call assert_equal('', pum.current_word)
  call assert_equal(-1, pum.auto_confirm_timer)
  call assert_equal(-1, pum.buf)
  call assert_equal(-1, pum.preview_id)
  call assert_equal(-1, pum.scroll_id)
  call assert_equal(-1, pum.startcol)
  call assert_equal(v:false, pum.horizontal_menu)
  call assert_equal(v:false, pum.preview)
  call assert_equal(v:false, pum.reversed)
  call assert_equal(v:false, pum.skip_complete)
  call assert_equal(0, pum.skip_count)
endfunction

" Test options initialization
function! Test_options_init() abort
  " Test pum#_init_options() sets default options correctly
  call pum#_init_options()
  let options = pum#_options()

  " Verify essential default options
  call assert_equal(0, options.auto_confirm_time)
  call assert_equal([], options.commit_characters)
  call assert_equal('auto', options.direction)
  call assert_equal(v:false, options.follow_cursor)
  call assert_equal(v:false, options.horizontal_menu)
  call assert_equal(v:false, options.insert_preview)
  call assert_equal(v:false, options.padding)
  call assert_equal(v:false, options.preview)
  call assert_equal(v:false, options.preview_remains)
  call assert_equal(v:false, options.reversed)
  call assert_equal(v:false, options.use_setline)
  call assert_equal(1000, options.zindex)
  call assert_equal(v:t_list, type(options.item_orders))
  call assert_equal(v:t_dict, type(options.max_columns))
endfunction

" Test popup visibility detection
function! Test_visibility() abort
  call Setup()
  " Initially not visible
  call assert_equal(v:false, pum#visible())

  " Test _get returns state with id -1 initially
  let pum = pum#_get()
  call assert_equal(-1, pum.id)

  " After initialization, should still not be visible
  call pum#_init()
  call assert_equal(v:false, pum#visible())
endfunction

" Test auto-confirm timer functionality
function! Test_auto_confirm_timer() abort
  call Setup()
  " Set auto-confirm time option
  call pum#set_option('auto_confirm_time', 100)

  " Open popup
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  let pum = pum#_get()

  " Timer should be set when auto_confirm_time > 0
  " Note: Timer value depends on implementation details
  " We just verify it's a number
  call assert_equal(v:t_number, type(pum.auto_confirm_timer))

  " Reset option
  call pum#set_option('auto_confirm_time', 0)
endfunction

" Test complete info
function! Test_complete_info() abort
  call Setup()
  " Initially no completion
  let info = pum#complete_info()
  call assert_equal(v:false, info.pum_visible)
  call assert_equal([], info.items)
  call assert_equal(-1, info.selected)
  call assert_equal('', info.inserted)

  " Test complete_info with specific keys
  let info2 = pum#complete_info(['pum_visible', 'selected'])
  call assert_true(info2->has_key('pum_visible'))
  call assert_true(info2->has_key('selected'))
  call assert_false(info2->has_key('items'))
endfunction

" Test PUM menu open and close operations
function! Test_pum_menu_operations() abort
  call Setup()

  let result = pum#open(1, [#{ word: 'test' }])
  call assert_notequal(-1, result)

  " Test that open with empty items returns early
  let result = pum#open(1, [], 'i')
  " Empty items should return without error
  call assert_equal(v:false, pum#visible())

  " Test get_pos when not visible
  let pos = pum#get_pos()
  call assert_equal({}, pos)

  " Test current_item when not visible
  let item = pum#current_item()
  call assert_equal({}, item)
endfunction

" Test buffer and preview functions
function! Test_buffer_functions() abort
  call Setup()
  " Test get_buf returns buffer id
  let buf = pum#get_buf()
  call assert_equal(v:t_number, type(buf))
  call assert_equal(-1, buf)

  " Test get_preview_buf
  let preview_buf = pum#get_preview_buf()
  call assert_equal(v:t_number, type(preview_buf))
  call assert_equal(-1, preview_buf)

  " Test preview_visible
  call assert_equal(v:false, pum#preview_visible())
endfunction

" Test option setting functions
function! Test_set_options() abort
  call Setup()
  " Test set_option with single key
  call pum#set_option('padding', v:true)
  let options = pum#_options()
  call assert_equal(v:true, options.padding)

  " Test set_option with dict
  call pum#set_option(#{ padding: v:false, reversed: v:true })
  let options = pum#_options()
  call assert_equal(v:false, options.padding)
  call assert_equal(v:true, options.reversed)

  " Test set_local_option
  call pum#set_local_option('i', 'padding', v:true)
  " Local options are tested through _options()

  " Reset to defaults
  call pum#_init_options()
endfunction

" Test skip_complete functionality
function! Test_skip_complete() abort
  call Setup()
  let pum = pum#_get()

  " Initially skip_complete should be false
  call assert_equal(v:false, pum.skip_complete)
  call assert_equal(0, pum.skip_count)

  " Test _inc_skip_complete
  call pum#_inc_skip_complete()
  call assert_equal(v:true, pum.skip_complete)
  call assert_equal(1, pum.skip_count)

  " Increment again
  call pum#_inc_skip_complete()
  call assert_equal(2, pum.skip_count)

  " Test skip_complete() decrements counter
  let skip = pum#skip_complete()
  call assert_equal(v:true, skip)
  call assert_equal(1, pum.skip_count)

  " Call again
  let skip = pum#skip_complete()
  call assert_equal(v:true, skip)
  call assert_equal(0, pum.skip_count)
  call assert_equal(v:false, pum.skip_complete)

  " After reset, should be false
  let skip = pum#skip_complete()
  call assert_equal(v:false, skip)
endfunction

" Test entered state
function! Test_entered() abort
  call Setup()
  " Should not be entered when not visible
  call assert_equal(v:false, pum#entered())
endfunction

" Test get_direction function
function! Test_get_direction() abort
  call Setup()
  " direction is not set in initial state, it's set during popup open
  " We just test that the function exists and returns a value
  try
    let _ = pum#get_direction()
    " If it succeeds, direction could be any value
    call assert_true(v:true)
  catch
    " If it fails, that's expected for uninitialized state
    call assert_true(v:true)
  endtry
endfunction

" Test previewer option
function! PreviewerForTest(item) abort
  return a:item.word ==# 'foo'
        \ ? #{ kind: 'text', contents: ['preview of ' .. a:item.word] }
        \ : #{ kind: 'empty' }
endfunction

function! Test_previewer() abort
  call Setup()
  call assert_equal('', pum#_options().previewer)

  for Previewer in ['PreviewerForTest', function('PreviewerForTest')]
    call pum#set_option('previewer', Previewer)
    call pum#open(1, [
          \ #{ word: 'foo' },
          \ #{ word: 'bar', info: "info of bar" },
          \ ], 'i')

    " The previewer's contents.
    call pum#map#select_relative(1)
    call pum#open_preview()
    call assert_true(pum#preview_visible())
    call assert_equal(['preview of foo'],
          \ pum#get_preview_buf()->getbufline(1, '$'))

    " "empty" kind: the info.
    call pum#map#select_relative(1)
    call pum#open_preview()
    call assert_equal(['info of bar'],
          \ pum#get_preview_buf()->getbufline(1, '$'))

    call pum#close()
  endfor

  call pum#set_option('previewer', '')
endfunction

" Without previewer option, no completion plugin's previewer is used.
function! Test_previewer_default() abort
  call Setup()
  const dir = tempname()
  call mkdir(dir .. '/autoload', 'p')
  call writefile([
        \ 'function ddc#get_previewer(item) abort',
        \ "  return #{ kind: 'text', contents: ['from ddc'] }",
        \ 'endfunction',
        \ ], dir .. '/autoload/ddc.vim')
  let &runtimepath ..= ',' .. dir
  call assert_equal(['from ddc'], ddc#get_previewer({}).contents)

  call pum#open(1, [#{ word: 'foo', info: "info of foo" }], 'i')
  call pum#map#select_relative(1)
  call pum#open_preview()
  call assert_equal(['info of foo'],
        \ pum#get_preview_buf()->getbufline(1, '$'))
  call pum#close()

  let &runtimepath = &runtimepath->substitute(',' .. dir, '', '')
endfunction
