-- lua/pum/format.lua
-- Neovim-only Lua fast path for pum#_format_item.
-- On Vim (non-Neovim) this module is never loaded; the Vimscript
-- implementation in autoload/pum.vim is used as-is.

local M = {}

-- Width cache: keyed by string value, mirrors s:width_cache in autoload/pum.vim.
-- Cleared via M.clear_width_cache() when pum#open starts a new candidate list.
local _width_cache = {}

--- Clear the width cache.
-- Called from Vimscript (autoload/pum.vim) when pum#open resets s:width_cache.
function M.clear_width_cache()
  _width_cache = {}
end

-- Return the display width of a string, using the local cache.
local function display_width(str)
  local w = _width_cache[str]
  if w then
    return w
  end
  w = vim.fn.strdisplaywidth(str)
  _width_cache[str] = w
  return w
end

--- Format a single completion item for display.
-- Mirrors pum#_format_item in autoload/pum.vim exactly:
--   * iterates max_columns in order
--   * handles 'space' pseudo-column
--   * overrides max_column for 'abbr' with abbr_width
--   * substitutes control characters with '?'
--   * falls back to item.word for empty abbr
--   * truncates via pum#util#_truncate when over-width
--   * right-pads short columns with spaces
--   * adds leading/trailing padding spaces when options.padding is set
--
-- @param item        table   completion item dict
-- @param options     table   pum options (.padding bool)
-- @param mode        string  current mode ('i', 'c', 't', ...)
-- @param startcol    number  start column
-- @param max_columns table   list of {name, max_width} pairs (1-indexed)
-- @param abbr_width  number  max width for the 'abbr' column
-- @return string  formatted display string
function M.format_item(item, options, mode, startcol, max_columns, abbr_width)
  -- Build the columns table.
  -- Vimscript: item.get('columns',{})->copy()->extend({abbr:..., kind:..., menu:...})
  -- extend() does NOT overwrite existing keys when called on the copy, but
  -- pum.vim passes the standard fields with get() fallbacks, so the extend
  -- puts abbr/kind/menu in only if they are not already in columns.
  -- Here we replicate the same by building columns first from item.columns
  -- and then filling standard fields that are absent.
  local columns = {}
  local item_columns = item.columns
  if item_columns then
    for k, v in pairs(item_columns) do
      columns[k] = v
    end
  end
  local word = item.word or ''
  -- extend() in Vimscript by default does NOT overwrite existing keys:
  -- abbr/kind/menu are set only if not already present in columns.
  if columns.abbr == nil then
    local a = item.abbr
    columns.abbr = (a ~= nil and a ~= vim.NIL) and a or word
  end
  if columns.kind == nil then
    local k = item.kind
    columns.kind = (k ~= nil and k ~= vim.NIL) and k or ''
  end
  if columns.menu == nil then
    local m = item.menu
    columns.menu = (m ~= nil and m ~= vim.NIL) and m or ''
  end

  local parts = {}
  for _, entry in ipairs(max_columns) do
    local name      = entry[1]
    local max_col   = entry[2]

    if name == 'space' then
      parts[#parts + 1] = ' '
    else
      if name == 'abbr' then
        max_col = abbr_width
      end

      -- Get column string and replace control chars with '?'
      local col = columns[name]
      if col == nil or col == vim.NIL then
        col = ''
      else
        col = tostring(col)
      end
      col = col:gsub('%c', '?')

      -- Fallback: empty abbr → use item.word
      if name == 'abbr' and col == '' then
        col = word
      end

      -- Display width (cached)
      local col_width = display_width(col)

      if col_width > max_col then
        -- Truncate: delegate to Vimscript for byte-exact multibyte handling
        col = vim.fn['pum#util#_truncate'](col, max_col, math.floor(max_col / 3), '...')
        col_width = display_width(col)
      end

      if col_width < max_col then
        -- Right-pad with spaces
        col = col .. string.rep(' ', max_col - col_width)
      end

      parts[#parts + 1] = col
    end
  end

  local str = table.concat(parts)

  if options.padding then
    str = str .. ' '
    if mode == 'c' or startcol ~= 1 then
      str = ' ' .. str
    end
  end

  return str
end

return M
