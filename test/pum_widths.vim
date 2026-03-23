" test/pum_widths.vim
" Tests for the width/dimension fast paths in pum.vim.
"
" On Neovim: exercises the Lua fast path (lua/pum/widths.lua).
" On Vim:    exercises the Vim9 fast path (autoload/pum/widths.vim).
" Both sections verify that the respective implementations produce
" semantically correct output.
"
" Usage:
"   Neovim:
"     nvim --headless -u NONE -c "set runtimepath+=." \
"          -c "source test/pum_widths.vim" -c "qa!"
"   Vim:
"     vim -Nu NONE -c "set runtimepath+=." \
"         -c "source test/pum_widths.vim" -c "q"
"   Or via the test runner:
"     nvim --headless -u NONE -c "set runtimepath+=." \
"          -c "source test/run_tests.vim"

" ── helpers ────────────────────────────────────────────────────────────────

" Helper: empty pum state placeholder (the fast path does not use the pum
" state object; it is kept for API symmetry with s:calculate_dimensions)
let s:empty_pum = {}

" Dispatch helpers: call the appropriate fast-path implementation.

function s:call_widths(items, options) abort
  if has('nvim')
    return luaeval(
          \ "require('pum.widths').calculate_column_widths_fast(_A[1],_A[2])",
          \ [a:items, a:options])
  else
    return pum#widths#CalculateColumnWidthsV9(a:items, a:options)
  endif
endfunction

function s:call_dims(items, mc, tw, nal, options, mode, startcol, ...) abort
  let pum_state = a:0 > 0 ? a:1 : s:empty_pum
  if has('nvim')
    return luaeval(
          \ "require('pum.widths').calculate_dimensions_fast("
          \ .. "_A[1],_A[2],_A[3],_A[4],_A[5],_A[6],_A[7],_A[8])",
          \ [a:items, a:mc, a:tw, a:nal, a:options, a:mode, a:startcol,
          \  pum_state])
  else
    return pum#widths#CalculateDimensionsV9(
          \ a:items, a:mc, a:tw, a:nal, a:options, a:mode, a:startcol,
          \ pum_state)
  endif
endfunction

" Legacy helpers kept for backward compatibility with existing callers.
function s:call_lua_widths(items, options) abort
  return s:call_widths(a:items, a:options)
endfunction

function s:call_lua_dims(items, mc, tw, nal, options, mode, startcol, ...) abort
  let pum_state = a:0 > 0 ? a:1 : s:empty_pum
  return s:call_dims(a:items, a:mc, a:tw, a:nal, a:options, a:mode, a:startcol,
        \ pum_state)
endfunction

" ── guard: check that the active fast path is available ─────────────────────

if has('nvim')
  if !pum#util#_luacheck('pum.widths')
    echomsg 'test/pum_widths.vim: pum.widths Lua module not loadable – skipping'
    finish
  endif
else
  if !exists('*pum#widths#CalculateColumnWidthsV9')
    " Trigger autoload
    call pum#widths#ClearWidthsCacheV9()
  endif
  if !exists('*pum#widths#CalculateColumnWidthsV9')
    echomsg 'test/pum_widths.vim: Vim9 widths implementation not available – skipping'
    finish
  endif
endif

" ── test cases ─────────────────────────────────────────────────────────────

func Test_widths_basic()
  call pum#_init_options()
  let options = pum#_options()

  let items = [
        \ #{ word: 'foo', kind: 'func', menu: '[mod]' },
        \ #{ word: 'longword', kind: 'var',  menu: '[other]' },
        \ ]

  " We directly compare the fast-path output against hardcoded expected values
  " derived from the inputs.

  let [mc, tw, nal] = s:call_widths(items, options)

  " max_columns must be a list of [name, width] pairs
  call assert_equal(v:t_list, type(mc))
  call assert_true(len(mc) > 0)

  " total_width must be positive
  call assert_true(tw > 0)

  " non_abbr_length must be <= total_width
  call assert_true(nal <= tw)

  " 'abbr' column width should be max strdisplaywidth of abbr/word fields
  let abbr_entry = mc->filter({ _, v -> v[0] ==# 'abbr' })
  if !abbr_entry->empty()
    call assert_equal(8, abbr_entry[0][1])  " 'longword' = 8 chars
  endif
endfunc

func Test_widths_no_items()
  call pum#_init_options()
  let options = pum#_options()

  let [mc, tw, nal] = s:call_widths([], options)

  call assert_equal([], mc)
  call assert_equal(0, tw)
  call assert_equal(0, nal)
endfunc

func Test_widths_space_skipped_after_empty()
  " A 'space' column immediately after a zero-width column should be skipped.
  call pum#_init_options()
  let options = pum#_options()->copy()
  " Use only kind + space + menu; kind has no values → both dropped
  call extend(options, #{
        \ item_orders: ['kind', 'space', 'abbr'],
        \ max_columns: {},
        \ })

  let items = [
        \ #{ word: 'hello', kind: '', menu: '' },
        \ #{ word: 'world', kind: '', menu: '' },
        \ ]

  let [mc, tw, nal] = s:call_widths(items, options)

  " kind is empty → zero width → skipped; space after it should also be skipped
  " Only 'abbr' should remain
  let names = mc->mapnew({ _, v -> v[0] })
  call assert_equal(v:false, names->index('space') >= 0 && names->index('kind') < 0,
        \ 'space should be dropped when kind is absent')
  call assert_notequal([], mc->filter({ _, v -> v[0] ==# 'abbr' }))
endfunc

func Test_widths_max_columns_constraint()
  call pum#_init_options()
  let options = pum#_options()->copy()
  call extend(options, #{
        \ item_orders: ['abbr', 'space', 'kind', 'space', 'menu'],
        \ max_columns: #{ kind: 4, menu: 5 },
        \ })

  let items = [
        \ #{ word: 'alpha',      kind: 'function_type', menu: 'some_module' },
        \ #{ word: 'beta',       kind: 'method',        menu: 'another' },
        \ ]

  let [mc, tw, nal] = s:call_widths(items, options)

  for entry in mc
    if entry[0] ==# 'kind'
      call assert_equal(4, entry[1], 'kind width should be capped at 4')
    endif
    if entry[0] ==# 'menu'
      call assert_equal(5, entry[1], 'menu width should be capped at 5')
    endif
  endfor
endfunc

func Test_dimensions_basic()
  call pum#_init_options()
  let options = pum#_options()

  let items = [
        \ #{ word: 'apple',  kind: 'f', menu: '[a]' },
        \ #{ word: 'banana', kind: 'v', menu: '[b]' },
        \ #{ word: 'cherry', kind: 'k', menu: '[c]' },
        \ ]

  let [mc, tw, nal] = s:call_widths(items, options)
  let dims = s:call_dims(items, mc, tw, nal, options, 'i', 2, {})

  " Result must be a dict with expected keys
  call assert_equal(v:t_dict, type(dims))
  for key in ['width', 'height', 'padding', 'padding_height', 'padding_width',
        \     'padding_left', 'border_left', 'border_top', 'border_right',
        \     'border_bottom', 'abbr_width', 'lines']
    call assert_true(dims->has_key(key),
          \ printf('dims should have key "%s"', key))
  endfor

  " height must equal number of items (no max_height constraint)
  call assert_equal(3, dims.height)

  " lines must have one entry per item
  call assert_equal(3, len(dims.lines))

  " lines entries must be strings
  for l in dims.lines
    call assert_equal(v:t_string, type(l))
  endfor
endfunc

func Test_dimensions_matches_fastpath()
  " End-to-end: verify the active fast path (Lua on Neovim, Vim9 on Vim)
  " produces output that matches hardcoded expected values derived from the
  " same calculation logic.
  call pum#_init_options()
  call pum#_init()
  let options = pum#_options()

  let items = [
        \ #{ word: 'alpha', kind: 'function', menu: '[mymod]' },
        \ #{ word: 'beta',  kind: 'variable', menu: '[mymod]' },
        \ ]

  let [mc, tw, nal] = s:call_widths(items, options)

  " Hardcoded expected values based on options defaults + item data:
  "   abbr: max('alpha'=5, 'beta'=4) = 5
  "   space: 1
  "   kind: min(max('function'=8,'variable'=8), max_columns.kind=10) = 8
  "   space: 1
  "   menu: min(strdisplaywidth('[mymod]')=7, max_columns.menu=20) = 7
  "   total_width = 5 + 1 + 8 + 1 + 7 = 22
  "   non_abbr_length = 1 + 8 + 1 + 7 = 17
  call assert_equal(22, tw)
  call assert_equal(17, nal)

  let dims = s:call_dims(items, mc, tw, nal, options, 'i', 2, {})

  " With no min_width/max_width and no padding:
  "   width = total_width + padding = 22 + 0 = 22
  "   abbr_width = width - non_abbr_length - padding = 22 - 17 - 0 = 5
  call assert_equal(22, dims.width)
  call assert_equal(5, dims.abbr_width)
  call assert_equal(2, dims.height)
endfunc

func Test_dimensions_padding()
  call pum#_init_options()
  let options = pum#_options()->copy()
  call extend(options, #{ padding: v:true })

  let items = [#{ word: 'hi', kind: 'f', menu: '[m]' }]

  let [mc, tw, nal] = s:call_widths(items, options)
  " startcol=2 → padding=2 (left+right)
  let dims_col2 = s:call_dims(items, mc, tw, nal, options, 'i', 2, {})
  " startcol=1 → padding=1 (right only)
  let dims_col1 = s:call_dims(items, mc, tw, nal, options, 'i', 1, {})

  call assert_equal(2, dims_col2.padding)
  call assert_equal(1, dims_col1.padding)
endfunc
