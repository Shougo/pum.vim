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
  if w ~= nil then
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
  local str = table.concat(M.format_parts(item, max_columns, abbr_width))

  if options.padding then
    str = str .. ' '
    if mode == 'c' or startcol ~= 1 then
      str = ' ' .. str
    end
  end

  return str
end

--- The columns of the line of format_item(), one string for each entry of
-- max_columns ('space' is ' '), without the padding: the highlights of
-- the columns are placed by their byte lengths.
--
-- @param item        table   completion item dict
-- @param max_columns table   list of {name, max_width} pairs (1-indexed)
-- @param abbr_width  number  max width for the 'abbr' column
-- @return table  list of strings
function M.format_parts(item, max_columns, abbr_width)
  -- Build the columns table.
  -- Vimscript: item.get('columns',{})->copy()->extend({abbr:..., kind:..., menu:...})
  -- extend() overwrites the keys there (its default is "force"): abbr, kind
  -- and menu are those of the item, never those of item.columns.
  local columns = {}
  local item_columns = item.columns
  if type(item_columns) == 'table' then
    for k, v in pairs(item_columns) do
      columns[k] = v
    end
  end
  local word = item.word or ''
  local a = item.abbr
  columns.abbr = (a ~= nil and a ~= vim.NIL) and a or word
  local k = item.kind
  columns.kind = (k ~= nil and k ~= vim.NIL) and k or ''
  local m = item.menu
  columns.menu = (m ~= nil and m ~= vim.NIL) and m or ''

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
        local padding = math.max(0, math.floor(max_col - col_width))
        col = col .. string.rep(' ', padding)
      end

      parts[#parts + 1] = col
    end
  end

  return parts
end

return M
