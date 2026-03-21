-- lua/pum/widths.lua
-- Neovim-only Lua fast path for column-width calculation and dimension
-- computation (mirrors s:calculate_column_widths and s:calculate_dimensions
-- from autoload/pum/popup.vim).
--
-- On Vim (non-Neovim) this module is never loaded; the Vimscript
-- implementation is used as-is.

local M = {}

-- Internal width cache: keyed by string value.
-- Cleared via M.clear_widths_cache() at the start of each pum#open call.
local _widths_cache = {}

--- Clear the internal width cache.
-- Called from Vimscript (autoload/pum.vim) when pum#open starts a new
-- candidate list, matching the behaviour of  let s:width_cache = {}  there.
function M.clear_widths_cache()
  _widths_cache = {}
end

-- Return the display width of a string, using the local cache.
local function display_width(str)
  local w = _widths_cache[str]
  if w then
    return w
  end
  w = vim.fn.strdisplaywidth(str)
  _widths_cache[str] = w
  return w
end

-- ---------------------------------------------------------------------------
-- Border helpers (mirror s:get_border_size)
-- ---------------------------------------------------------------------------

-- Returns the display width of a border character specification.
-- ch can be a string or a list {char, highlight}.
local function borderchar_width(ch)
  if type(ch) == 'string' then
    return vim.fn.strdisplaywidth(ch)
  elseif type(ch) == 'table' then
    local c = ch[1]
    if type(c) == 'string' then
      return vim.fn.strdisplaywidth(c)
    end
  end
  return 0
end

-- Returns the height (0 or 1) contributed by a border character.
local function borderchar_height(ch)
  if type(ch) == 'string' then
    return (ch ~= '') and 1 or 0
  elseif type(ch) == 'table' then
    local c = ch[1]
    if type(c) == 'string' then
      return (c ~= '') and 1 or 0
    end
  end
  return 0
end

-- Returns {border_left, border_top, border_right, border_bottom}
-- Mirrors s:get_border_size() in autoload/pum/popup.vim.
local function get_border_size(border)
  if type(border) == 'string' then
    if border == 'none' then
      return 0, 0, 0, 0
    else
      return 1, 1, 1, 1
    end
  elseif type(border) == 'table' and #border > 0 then
    local n = #border
    return
      borderchar_width(border[(3 % n) + 1]),
      borderchar_height(border[(1 % n) + 1]),
      borderchar_width(border[(7 % n) + 1]),
      borderchar_height(border[(5 % n) + 1])
  else
    return 0, 0, 0, 0
  end
end

-- ---------------------------------------------------------------------------
-- calculate_column_widths_fast
-- ---------------------------------------------------------------------------

--- Calculate maximum column widths for all items.
-- Mirrors s:calculate_column_widths(items, options) exactly.
--
-- @param items   list of completion item dicts
-- @param options pum options dict (item_orders, max_columns)
-- @return max_columns (list of {name, max_width} pairs),
--         total_width  (number),
--         non_abbr_length (number)
function M.calculate_column_widths_fast(items, options)
  local max_columns     = {}
  local width           = 0
  local non_abbr_length = 0
  local prev_column_length = 0

  local item_orders = options.item_orders or {}
  local opt_max_columns = options.max_columns or {}

  for _, column in ipairs(item_orders) do
    local max_column

    if column == 'space' then
      max_column = 1
    elseif column == 'abbr' then
      max_column = 0
      for _, val in ipairs(items) do
        local abbr = val.abbr
        if abbr == nil or abbr == vim.NIL then
          abbr = val.word or ''
        end
        local w = display_width(tostring(abbr))
        if w > max_column then
          max_column = w
        end
      end
    elseif column == 'kind' then
      max_column = 0
      for _, val in ipairs(items) do
        local kind = val.kind
        if kind == nil or kind == vim.NIL then kind = '' end
        local w = display_width(tostring(kind))
        if w > max_column then max_column = w end
      end
    elseif column == 'menu' then
      max_column = 0
      for _, val in ipairs(items) do
        local menu = val.menu
        if menu == nil or menu == vim.NIL then menu = '' end
        local w = display_width(tostring(menu))
        if w > max_column then max_column = w end
      end
    else
      -- Custom column: stored in item.columns[column]
      max_column = 0
      for _, val in ipairs(items) do
        local cols = val.columns
        local cell = ''
        if cols and type(cols) == 'table' then
          local v = cols[column]
          if v ~= nil and v ~= vim.NIL then
            cell = tostring(v)
          end
        end
        local w = display_width(cell)
        if w > max_column then max_column = w end
      end
    end

    -- Apply max_columns constraint from options
    local opt_limit = opt_max_columns[column]
    if opt_limit ~= nil and opt_limit ~= vim.NIL then
      if opt_limit < max_column then
        max_column = opt_limit
      end
    end

    -- Skip zero-width columns and 'space' after a zero-width column
    if max_column <= 0 or (column == 'space' and prev_column_length == 0) then
      prev_column_length = 0
      -- continue
    else
      width = width + max_column
      max_columns[#max_columns + 1] = { column, max_column }

      if column ~= 'abbr' then
        non_abbr_length = non_abbr_length + max_column
      end
      prev_column_length = max_column
    end
  end

  return max_columns, width, non_abbr_length
end

-- ---------------------------------------------------------------------------
-- calculate_dimensions_fast
-- ---------------------------------------------------------------------------

--- Calculate final popup dimensions and format display lines.
-- Mirrors s:calculate_dimensions(items, max_columns, total_width,
--   non_abbr_length, options, mode, startcol, pum) exactly.
--
-- @param items           list of completion items
-- @param max_columns     list of {name, max_width} pairs (from calculate_column_widths_fast)
-- @param total_width     number
-- @param non_abbr_length number
-- @param options         pum options dict
-- @param mode            mode character ('i', 'c', 't')
-- @param startcol        starting column (number)
-- @param pum             pum state object (unused here, kept for API symmetry)
-- @return dict with width, height, padding, padding_height, padding_width,
--         padding_left, border_left, border_top, border_right, border_bottom,
--         abbr_width, lines
function M.calculate_dimensions_fast(
    items, max_columns, total_width, non_abbr_length,
    options, mode, startcol, _pum)

  -- ── Padding & border dimensions ──────────────────────────────────────────
  -- Mirrors s:calculate_padding_dimensions
  local border = options.border or 'none'
  local border_left, border_top, border_right, border_bottom =
    get_border_size(border)

  local padding_height = 1 + border_top + border_bottom
  local padding_width  = 1 + border_left + border_right
  local padding_left   = border_left

  local padding
  if options.padding then
    if mode == 'c' or startcol ~= 1 then
      padding = 2
      padding_width = padding_width + 2
      padding_left  = padding_left + 1
    else
      padding = 1
    end
  else
    padding = 0
  end

  -- ── Width constraints ─────────────────────────────────────────────────────
  -- Mirrors s:apply_width_constraints
  local width = total_width + padding
  local min_width = options.min_width or 0
  local max_width = options.max_width or 0
  if min_width > 0 and width < min_width then
    width = min_width
  end
  if max_width > 0 and width > max_width then
    width = max_width
  end

  -- ── abbr_width ────────────────────────────────────────────────────────────
  local abbr_width = width - non_abbr_length - padding

  -- ── Format items into display lines ──────────────────────────────────────
  -- Delegate to pum#_format_item (which itself may use the Lua fast path)
  local lines = {}
  for _, val in ipairs(items) do
    lines[#lines + 1] = vim.fn['pum#_format_item'](
      val, options, mode, startcol, max_columns, abbr_width)
  end

  -- ── Height constraints ────────────────────────────────────────────────────
  -- Mirrors s:apply_height_constraints
  local height = #items
  local max_height = options.max_height or 0
  local min_height = options.min_height or 0
  if max_height > 0 and height > max_height then
    height = max_height
  end
  if min_height > 0 and height < min_height then
    height = min_height
  end

  return {
    width          = width,
    height         = height,
    padding        = padding,
    padding_height = padding_height,
    padding_width  = padding_width,
    padding_left   = padding_left,
    border_left    = border_left,
    border_top     = border_top,
    border_right   = border_right,
    border_bottom  = border_bottom,
    abbr_width     = abbr_width,
    lines          = lines,
  }
end

return M
