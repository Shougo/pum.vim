-- bench/bench_widths.lua
-- Benchmark script for the Lua fast path of the column widths and the
-- dimensions (lua/pum/widths.lua). Vim uses the Vim9 implementation instead:
-- see bench/bench_widths_vim9.vim.
--
-- Usage (Neovim headless):
--   nvim --headless -u NONE -c "set runtimepath+=." \
--        -c "lua dofile('bench/bench_widths.lua')" \
--        -c "qa!"
--
-- The script times N iterations of the Lua functions, and of a luaeval()
-- call from Vim script, and prints the results.

local ITERATIONS = 500

-- One line on stdout (say() of a headless Neovim may join the lines).
local function say(line)
  io.stdout:write(line, '\n')
end

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
    local mc, tw, nal = unpack(widths.calculate_column_widths_fast(items, options))
    widths.calculate_dimensions_fast(items, mc, tw, nal, options, 'i', 2, {})
  end
end

-- ── luaeval() from Vim script ───────────────────────────────────────────────
-- pum#popup#_open() calls the Lua functions with luaeval(): the items are
-- converted from Vim script each time.

local function bench_luaeval_roundtrip()
  vim.fn['pum#_init_options']()
  for _ = 1, ITERATIONS do
    -- As pum#popup#_open() does (the conversion of the items included).
    vim.fn.luaeval(
      "require('pum.widths').calculate_column_widths_fast(_A[1],_A[2])",
      { items, options })
  end
end

-- ── Timing helper ───────────────────────────────────────────────────────────
local function timeit(label, fn, ncalls_per_iter)
  -- Warm up
  fn()
  local t0 = vim.uv.hrtime()
  fn()
  local elapsed_ns = vim.uv.hrtime() - t0
  local elapsed_ms = elapsed_ns / 1e6
  local total_calls = ITERATIONS * (ncalls_per_iter or 1)
  local us_per_call = elapsed_ns / total_calls / 1e3
  say(string.format('%-38s  %7.2f ms  (%d calls, %.3f µs/call)',
        label, elapsed_ms, total_calls, us_per_call))
end

-- ── Correctness check ───────────────────────────────────────────────────────
say('=== Correctness check ===')
local mc_lua, tw_lua, nal_lua =
  unpack(widths.calculate_column_widths_fast(items, options))
say(string.format('Lua:         max_columns=%d  total_width=%d  non_abbr_length=%d',
      #mc_lua, tw_lua, nal_lua))

local dims_lua = widths.calculate_dimensions_fast(
  items, mc_lua, tw_lua, nal_lua, options, 'i', 2, {})
say(string.format('Lua dims:    width=%d  height=%d  abbr_width=%d',
      dims_lua.width, dims_lua.height, dims_lua.abbr_width))

say('')

-- ── Benchmark ───────────────────────────────────────────────────────────────
say(string.format('=== Benchmark: %d iterations × %d items ===', ITERATIONS, #items))
timeit('Lua calculate_column_widths_fast',  bench_lua_widths, 1)
timeit('Lua column widths + dimensions',    bench_lua_dimensions, 1)
timeit('luaeval() of column widths',        bench_luaeval_roundtrip, 1)
say('')
say('NOTE: "luaeval() of column widths" includes the conversion of the')
say('items from Vim script; compare it with "Lua calculate_column_widths_fast".')
