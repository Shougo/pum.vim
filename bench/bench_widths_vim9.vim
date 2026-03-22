" bench/bench_widths_vim9.vim
" Benchmark script for the Vim9 fast path in autoload/pum/widths.vim.
"
" Usage:
"   vim -Nu NONE -c "set runtimepath+=." \
"       -c "source bench/bench_widths_vim9.vim" \
"       -c "q"

if has('nvim')
  echomsg 'bench_widths_vim9.vim: Vim only – skipping on Neovim'
  finish
endif

const s:ITERATIONS = 500
const s:N_ITEMS = 100

" Build a representative completion list
function s:make_items(n) abort
  let items = []
  for i in range(1, a:n)
    call add(items, #{
          \   word: printf('completion_item_%03d', i),
          \   abbr: printf('completion_item_%03d', i),
          \   kind: (i % 3 == 0) ? 'function'
          \         : (i % 3 == 1) ? 'variable' : 'keyword',
          \   menu: printf('[module_%02d]', i % 10),
          \ })
  endfor
  return items
endfunction

let s:items = s:make_items(s:N_ITEMS)

" Options matching the default pum options
let s:options = #{
      \   item_orders: ['abbr', 'space', 'kind', 'space', 'menu'],
      \   max_columns: #{ kind: 10, menu: 20 },
      \   padding:     v:false,
      \   min_width:   0,
      \   max_width:   0,
      \   min_height:  0,
      \   max_height:  0,
      \   border:      'none',
      \ }

" ── helpers ─────────────────────────────────────────────────────────────────

function s:bench_vim9_widths() abort
  call pum#widths#clear_widths_cache_v9()
  for _ in range(s:ITERATIONS)
    call pum#widths#calculate_column_widths_v9(s:items, s:options)
  endfor
endfunction

function s:bench_vim9_dimensions() abort
  call pum#widths#clear_widths_cache_v9()
  let [mc, tw, nal] = pum#widths#calculate_column_widths_v9(s:items, s:options)
  for _ in range(s:ITERATIONS)
    call pum#widths#calculate_dimensions_v9(
          \ s:items, mc, tw, nal, s:options, 'i', 2, {})
  endfor
endfunction

function s:time_ms(F) abort
  let t0 = reltime()
  call call(a:F, [])
  return reltimefloat(reltime(t0)) * 1000.0
endfunction

" ── correctness check ────────────────────────────────────────────────────────

call pum#_init_options()
let s:opts = pum#_options()

call pum#widths#clear_widths_cache_v9()
let [s:mc, s:tw, s:nal] =
      \ pum#widths#calculate_column_widths_v9(s:items, s:opts)

echomsg printf('Correctness: max_columns entries=%d  total_width=%d  non_abbr=%d',
      \ len(s:mc), s:tw, s:nal)

if s:tw <= 0
  echoerr 'bench_widths_vim9: total_width should be positive'
  finish
endif

" ── benchmarks ───────────────────────────────────────────────────────────────

let s:t_widths = s:time_ms(function('s:bench_vim9_widths'))
echomsg printf('calculate_column_widths_v9  %d × %d items  %.1f ms  (%.3f ms/call)',
      \ s:ITERATIONS, s:N_ITEMS, s:t_widths, s:t_widths / s:ITERATIONS)

let s:t_dims = s:time_ms(function('s:bench_vim9_dimensions'))
echomsg printf('calculate_dimensions_v9     %d × %d items  %.1f ms  (%.3f ms/call)',
      \ s:ITERATIONS, s:N_ITEMS, s:t_dims, s:t_dims / s:ITERATIONS)

echomsg 'bench_widths_vim9.vim: done'
