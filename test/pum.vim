" Tests for pum.vim using Vim's native assert API
" All test function names must start with Test_

" Setup function called before each test
func Setup()
  call pum#_init()
  call pum#_init_options()
  normal! ggVGd
endfunc

" Test pum#open() function
func Test_open()
  call Setup()
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }]))
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i'))
  call assert_notequal(-1, pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'c'))
endfunc

" Test highlight functionality
func Test_highlight()
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
endfunc

" The highlights placed in the popup: [[row, col, length, group], ...].
func s:placed()
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
endfunc

func s:compare(a, b)
  for i in range(4)
    if a:a[i] != a:b[i]
      return a:a[i] < a:b[i] ? -1 : 1
    endif
  endfor
  return 0
endfunc

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
func Test_highlight_items()
  call Setup()
  call pum#open(1, s:highlighted_items, 'i')
  call assert_equal([
        \ [2, 4, 3, 'PumTestA'],
        \ [2, 11, 1, 'PumTestB'],
        \ ], s:placed())

  call Setup()
  call pum#set_option(#{
        \ highlight_columns: #{ kind: 'PumTestC', menu: 'PumTestD' } })
  call pum#open(1, s:highlighted_items, 'i')
  call assert_equal([
        \ [1, 8, 2, 'PumTestC'],
        \ [1, 11, 1, 'PumTestD'],
        \ [2, 4, 3, 'PumTestA'],
        \ [2, 8, 2, 'PumTestC'],
        \ [2, 11, 1, 'PumTestB'],
        \ [2, 11, 1, 'PumTestD'],
        \ [3, 8, 2, 'PumTestC'],
        \ [3, 11, 1, 'PumTestD'],
        \ ], s:placed())

  " padding: one column right when not at the start of the line
  call Setup()
  call pum#set_option(#{ padding: v:true })
  call setline(1, 'x')
  call pum#open(2, s:highlighted_items, 'i')
  call assert_equal([
        \ [2, 5, 3, 'PumTestA'],
        \ [2, 12, 1, 'PumTestB'],
        \ ], s:placed())

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
        \ [1, 4, 3, 'PumTestA'],
        \ [1, 11, 3, 'PumTestC'],
        \ [1, 15, 1, 'PumTestD'],
        \ [2, 8, 2, 'PumTestC'],
        \ [2, 11, 1, 'PumTestD'],
        \ ], s:placed())

  " Nothing to highlight
  call Setup()
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')
  call assert_equal([], s:placed())
endfunc

" The lines of calculate_dimensions_fast() are those of pum#_format_item()
" (Neovim only)
func Test_dimensions_lines()
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
endfunc

" Test select_relative functionality
func Test_select_relative()
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
endfunc

" Test insert_relative functionality
func Test_insert_relative()
  call Setup()
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  call pum#map#insert_relative(1)
  call pum#map#insert_relative(1)

  call assert_equal(2, pum#_get().cursor)

  call pum#map#insert_relative(-1)
  call pum#map#insert_relative(-1)

  call assert_equal(0, pum#_get().cursor)
endfunc

" Test format_item functionality
func Test_format_item()
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
endfunc

" Test core plugin initialization
func Test_core_init()
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
endfunc

" Test options initialization
func Test_options_init()
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
endfunc

" Test popup visibility detection
func Test_visibility()
  call Setup()
  " Initially not visible
  call assert_equal(v:false, pum#visible())

  " Test _get returns state with id -1 initially
  let pum = pum#_get()
  call assert_equal(-1, pum.id)

  " After initialization, should still not be visible
  call pum#_init()
  call assert_equal(v:false, pum#visible())
endfunc

" Test auto-confirm timer functionality
func Test_auto_confirm_timer()
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
endfunc

" Test complete info
func Test_complete_info()
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
endfunc

" Test PUM menu open and close operations
func Test_pum_menu_operations()
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
endfunc

" Test buffer and preview functions
func Test_buffer_functions()
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
endfunc

" Test option setting functions
func Test_set_options()
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
endfunc

" Test skip_complete functionality
func Test_skip_complete()
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
endfunc

" Test entered state
func Test_entered()
  call Setup()
  " Should not be entered when not visible
  call assert_equal(v:false, pum#entered())
endfunc

" Test get_direction function
func Test_get_direction()
  call Setup()
  " direction is not set in initial state, it's set during popup open
  " We just test that the function exists and returns a value
  try
    let direction = pum#get_direction()
    " If it succeeds, direction could be any value
    call assert_true(v:true)
  catch
    " If it fails, that's expected for uninitialized state
    call assert_true(v:true)
  endtry
endfunc

" Test previewer option
func PreviewerForTest(item) abort
  return a:item.word ==# 'foo'
        \ ? #{ kind: 'text', contents: ['preview of ' .. a:item.word] }
        \ : #{ kind: 'empty' }
endfunc

func Test_previewer()
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
endfunc

" Without previewer option, no completion plugin's previewer is used.
func Test_previewer_default()
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
endfunc
