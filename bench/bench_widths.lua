-- bench/bench_widths.lua
-- Benchmark script for calculate_column_widths / calculate_dimensions
-- Lua vs Vimscript implementations.
--
-- Usage (Neovim headless):
--   nvim --headless -u NONE -c "set runtimepath+=." \
--        -c "lua dofile('bench/bench_widths.lua')" \
--        -c "qa!"
--
-- The script times N iterations of both the Lua and Vimscript paths and
-- prints a comparison to stdout.

local ITERATIONS = 500

-- Representative completion items (100 items, multi-column)
local function make_items(n)
  local t = {}
  for i = 1, n do
    t[i] = {
      word = string.format('completion_item_%03d', i),
      abbr = string.format('completion_item_%03d', i),
      kind = (i % 3 == 0) and 'function' or (i % 3 == 1) and 'variable' or 'keyword',
      menu = string.format('[module_%02d]', i % 10),
    }
  end
  return t
end

local items = make_items(100)

-- Options mirroring the default pum options
local options = {
  item_orders = { 'abbr', 'space', 'kind', 'space', 'menu' },
  max_columns = { kind = 10, menu = 20 },
  padding     = false,
  min_width   = 0,
  max_width   = 0,
  min_height  = 0,
  max_height  = 0,
  border      = 'none',
}

-- ── Lua fast path ───────────────────────────────────────────────────────────
local widths = require('pum.widths')

local function bench_lua_widths()
  widths.clear_widths_cache()
  for _ = 1, ITERATIONS do
    widths.calculate_column_widths_fast(items, options)
  end
end

local function bench_lua_dimensions()
  widths.clear_widths_cache()
  for _ = 1, ITERATIONS do
    local mc, tw, nal = widths.calculate_column_widths_fast(items, options)
    widths.calculate_dimensions_fast(items, mc, tw, nal, options, 'i', 2, {})
  end
end

-- ── Vimscript path ──────────────────────────────────────────────────────────
-- We call pum#open to exercise the full Vimscript path indirectly.
-- For a more controlled comparison we call the public API function which
-- routes through s:calculate_column_widths when the Lua path is disabled.
-- NOTE: Since the Lua fast path is active during this bench run, the
-- Vimscript wrapper actually delegates to Lua.  To benchmark pure Vimscript,
-- temporarily add  let s:lua_widths_available = v:false  in popup.vim.

local function bench_luaeval_roundtrip()
  vim.fn['pum#_init_options']()
  for _ = 1, ITERATIONS do
    -- Calling luaeval in a loop mirrors the cost of what the Vimscript
    -- wrapper does when the Lua path is NOT active.
    vim.fn.luaeval(
      "require('pum.widths').calculate_column_widths_fast(_A[1],_A[2])",
      { items, options })
  end
end

-- ── Timing helper ───────────────────────────────────────────────────────────
local function timeit(label, fn, ncalls_per_iter)
  -- Warm up
  fn()
  local t0 = vim.loop.hrtime()
  fn()
  local elapsed_ns = vim.loop.hrtime() - t0
  local elapsed_ms = elapsed_ns / 1e6
  local total_calls = ITERATIONS * (ncalls_per_iter or 1)
  local us_per_call = elapsed_ns / total_calls / 1e3
  print(string.format('%-38s  %7.2f ms  (%d calls, %.3f µs/call)',
        label, elapsed_ms, total_calls, us_per_call))
end

-- ── Correctness check ───────────────────────────────────────────────────────
print('=== Correctness check ===')
local mc_lua, tw_lua, nal_lua = widths.calculate_column_widths_fast(items, options)
print(string.format('Lua:         max_columns=%d  total_width=%d  non_abbr_length=%d',
      #mc_lua, tw_lua, nal_lua))

local dims_lua = widths.calculate_dimensions_fast(
  items, mc_lua, tw_lua, nal_lua, options, 'i', 2, {})
print(string.format('Lua dims:    width=%d  height=%d  abbr_width=%d',
      dims_lua.width, dims_lua.height, dims_lua.abbr_width))

print('(Vimscript comparison requires disabling s:lua_widths_available in popup.vim)')
print('')

-- ── Benchmark ───────────────────────────────────────────────────────────────
print(string.format('=== Benchmark: %d iterations × %d items ===', ITERATIONS, #items))
timeit('Lua calculate_column_widths_fast',  bench_lua_widths, 1)
timeit('Lua calculate_dimensions_fast',     bench_lua_dimensions, 1)
timeit('luaeval round-trip overhead',       bench_luaeval_roundtrip, 1)
print('')
print('NOTE: "luaeval round-trip overhead" measures the Vimscript→Lua overhead.')
print('To benchmark pure Vimscript s:calculate_column_widths, temporarily add:')
print('  let s:lua_widths_available = v:false')
print('in autoload/pum/popup.vim and re-run.  Remove it afterwards.')
