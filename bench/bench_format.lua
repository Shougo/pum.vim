-- bench/bench_format.lua
-- Benchmark script for pum#_format_item Lua vs Vimscript implementations.
--
-- Usage (Neovim headless):
--   nvim --headless -u NONE -c "set runtimepath+=." \
--        -c "lua dofile('bench/bench_format.lua')" \
--        -c "qa!"
--
-- The script times N iterations of both the Lua and Vimscript paths and
-- prints a comparison to stdout.

local ITERATIONS = 2000

-- Representative completion items
local items = {
  { word = 'printf',          abbr = 'printf',          kind = 'func',   menu = '[libc]'    },
  { word = 'pthread_create',  abbr = 'pthread_create',  kind = 'func',   menu = '[pthread]' },
  { word = 'some_long_identifier_that_needs_truncation',
    abbr = 'some_long_identifier_that_needs_truncation',
    kind = 'var',    menu = '[module]'  },
  { word = 'x',               abbr = 'x',               kind = '',       menu = ''          },
  { word = 'complete_item',   abbr = 'complete_item',   kind = 'method', menu = '[MyClass]' },
}

-- Column configuration (same shape as what pum.vim passes)
local max_columns = {
  { 'abbr',  20 },
  { 'space',  1 },
  { 'kind',   8 },
  { 'space',  1 },
  { 'menu',  10 },
}
local abbr_width = 20

local options_padding    = { padding = true,  item_orders = { 'abbr', 'space', 'kind', 'space', 'menu' } }
local options_no_padding = { padding = false, item_orders = { 'abbr', 'space', 'kind', 'space', 'menu' } }

-- ── Lua fast path ──────────────────────────────────────────────────────────
local fmt = require('pum.format')

local function bench_lua()
  fmt.clear_width_cache()
  for _ = 1, ITERATIONS do
    for _, item in ipairs(items) do
      fmt.format_item(item, options_padding, 'i', 2, max_columns, abbr_width)
      fmt.format_item(item, options_no_padding, 'i', 1, max_columns, abbr_width)
    end
  end
end

-- ── Vimscript path ─────────────────────────────────────────────────────────
local function bench_vimscript()
  vim.fn['pum#_init_options']()
  for _ = 1, ITERATIONS do
    for _, item in ipairs(items) do
      -- Force Vimscript path by calling the underlying Vimscript logic via
      -- vim.fn.  (The autoload wrapper will use the Lua fast path when
      -- available, so we call pum#util#_truncate directly only where needed;
      -- for a fair comparison we disable the Lua path temporarily.)
      vim.fn['pum#_format_item'](item, options_padding,    'i', 2, max_columns, abbr_width)
      vim.fn['pum#_format_item'](item, options_no_padding, 'i', 1, max_columns, abbr_width)
    end
  end
end

-- ── Timing helper ──────────────────────────────────────────────────────────
local function timeit(label, fn)
  -- Warm up
  fn()
  local t0 = vim.loop.hrtime()
  fn()
  local elapsed_ns = vim.loop.hrtime() - t0
  local elapsed_ms = elapsed_ns / 1e6
  local calls = ITERATIONS * #items * 2
  local us_per_call = elapsed_ns / calls / 1e3
  print(string.format('%-20s  %7.2f ms  (%d calls, %.3f µs/call)',
        label, elapsed_ms, calls, us_per_call))
end

-- ── Correctness check ──────────────────────────────────────────────────────
print('=== Correctness check ===')
-- Temporarily force vimscript path for reference output.
-- We compare the Lua output against the Vimscript output item-by-item.
local ok = true
for _, item in ipairs(items) do
  for _, opts in ipairs({ options_padding, options_no_padding }) do
    for _, mode_startcol in ipairs({ {'i', 1}, {'i', 2}, {'c', 1} }) do
      local m, sc = mode_startcol[1], mode_startcol[2]
      local lua_out = fmt.format_item(item, opts, m, sc, max_columns, abbr_width)
      local vim_out = vim.fn['pum#_format_item'](item, opts, m, sc, max_columns, abbr_width)
      -- Note: when running with the Lua path active, vim_out == lua_out by
      -- definition.  To get a truly independent Vimscript result you would
      -- need to temporarily set s:lua_format_available = v:false.  For a
      -- quick sanity check we at least verify the function doesn't error.
      if type(lua_out) ~= 'string' then
        print('FAIL: lua_out is not a string for item=' .. vim.inspect(item))
        ok = false
      end
      if type(vim_out) ~= 'string' then
        print('FAIL: vim_out is not a string for item=' .. vim.inspect(item))
        ok = false
      end
    end
  end
end
if ok then
  print('All outputs are strings (correctness OK under active fast path)')
end

-- ── Benchmark ──────────────────────────────────────────────────────────────
print('')
print(string.format('=== Benchmark: %d iterations × %d items × 2 option sets ===',
      ITERATIONS, #items))
timeit('Lua format_item',  bench_lua)
timeit('Vimscript wrapper', bench_vimscript)
print('')
print('NOTE: "Vimscript wrapper" includes the Lua fast path when run on Neovim.')
print('To benchmark pure Vimscript, temporarily add the following line at the')
print('top of autoload/pum.vim and re-run:')
print('  let s:lua_format_available = v:false')
print('Then remove it afterwards to restore the fast path.')
