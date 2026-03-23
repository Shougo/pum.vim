vim9script

# autoload/pum/widths.vim
# Vim9 fast path for pum column-width and dimension calculation.
#
# Used on Vim (9.1+).  Neovim uses lua/pum/widths.lua instead.
# Public API (accessible via autoload, Vim9 export def requires capitals):
#   pum#widths#ClearWidthsCacheV9()
#   pum#widths#CalculateColumnWidthsV9(items, options)
#   pum#widths#CalculateDimensionsV9(items, max_columns, total_width,
#                                     non_abbr_length, options, mode,
#                                     startcol, pum_state)

# Script-level display-width cache (string -> cell-width).
# Cleared by ClearWidthsCacheV9() on each pum#open().
var widths_cache: dict<number> = {}

# ── string helpers (ported from autoload/pum/util.vim) ──────────────────────

# Returns the leading part of str that fits within `width` display cells.
def StrwidthPart(str: string, width: number): string
  var s: string = tr(str, "\t", ' ')
  var vcol: number = width + 2
  return matchstr(s, '.*\%<' .. (vcol < 0 ? 0 : vcol) .. 'v')
enddef

# Returns the trailing part of str that occupies exactly `width` display cells.
def StrwidthPartReverse(str: string, width: number): string
  var s: string = tr(str, "\t", ' ')
  var vcol: number = strwidth(s) - width
  return matchstr(s, '\%>' .. (vcol < 0 ? 0 : vcol) .. 'v.*')
enddef

# Pads or clips str to exactly `width` display cells.
# For ASCII-only strings a fast byte-level path is used.
def TruncateStr(str: string, width: number): string
  if str =~# '^[\x00-\x7f]*$'
    return len(str) < width
        ? printf('%-' .. width .. 's', str)
        : strpart(str, 0, width)
  endif
  var ret: string = str
  if strwidth(ret) > width
    ret = StrwidthPart(ret, width)
  endif
  return ret
enddef

# Port of pum#util#_truncate(str, max, footer_width, separator)
def Truncate(str: string, max: number, footer_width: number, separator: string): string
  var w: number = strwidth(str)
  var ret: string
  if w <= max
    ret = str
  else
    var header_width: number = max - strwidth(separator) - footer_width
    ret = StrwidthPart(str, header_width) .. separator
        .. StrwidthPartReverse(str, footer_width)
  endif
  return TruncateStr(ret, max)
enddef

# ── border/padding helpers ───────────────────────────────────────────────────

def GetBordercharHeight(ch: any): number
  if type(ch) == v:t_string
    return empty(ch) ? 0 : 1
  elseif type(ch) == v:t_list && !empty(ch) && type(ch[0]) == v:t_string
    return empty(ch[0]) ? 0 : 1
  endif
  return 0
enddef

def GetBordercharWidth(ch: any): number
  if type(ch) == v:t_string
    return strdisplaywidth(ch)
  elseif type(ch) == v:t_list && !empty(ch) && type(ch[0]) == v:t_string
    return strdisplaywidth(ch[0])
  endif
  return 0
enddef

def GetBorderSize(border: any): list<number>
  if type(border) == v:t_string
    return border ==# 'none' ? [0, 0, 0, 0] : [1, 1, 1, 1]
  elseif type(border) == v:t_list && !empty(border)
    var n: number = len(border)
    return [
      GetBordercharWidth(border[3 % n]),
      GetBordercharHeight(border[1 % n]),
      GetBordercharWidth(border[7 % n]),
      GetBordercharHeight(border[5 % n]),
    ]
  endif
  return [0, 0, 0, 0]
enddef

# Returns [padding, padding_height, padding_width, padding_left,
#          border_left, border_top, border_right, border_bottom]
def CalcPaddingDimensions(
    options: dict<any>, mode: string, startcol: number, border: any
): list<number>
  var padding: number = !options.padding ? 0
      : (mode ==# 'c' || startcol != 1) ? 2 : 1

  var border_size: list<number> = GetBorderSize(border)
  var border_left: number   = border_size[0]
  var border_top: number    = border_size[1]
  var border_right: number  = border_size[2]
  var border_bottom: number = border_size[3]

  var padding_height: number = 1 + border_top + border_bottom
  var padding_width: number  = 1 + border_left + border_right
  var padding_left: number   = border_left

  if options.padding && (mode ==# 'c' || startcol != 1)
    padding_width += 2
    padding_left  += 1
  endif

  return [padding, padding_height, padding_width, padding_left,
          border_left, border_top, border_right, border_bottom]
enddef

# ── width cache ──────────────────────────────────────────────────────────────

# Cached display-width lookup for a single string.
def CachedWidth(text: string): number
  if has_key(widths_cache, text)
    return widths_cache[text]
  endif
  var w: number = strdisplaywidth(text)
  widths_cache[text] = w
  return w
enddef

# ── item formatter (inlined Vim9 port of pum#_format_item) ──────────────────
#
# FormatItem builds the display string for a single completion item.
# It is a Vim9 def port of pum#_format_item() (autoload/pum.vim), inlined here
# to avoid the per-item legacy function-call boundary, the
# s:lua_format_available check, and the pum#util#_truncate() call chain.
# All helpers above are also def so the entire hot path is bytecode-compiled.
#
# Parameters match those of pum#_format_item():
#   item        – completion-item dict (word/abbr/kind/menu/columns)
#   options     – pum options dict (padding, …)
#   mode        – current mode string ('i', 'c', …)
#   startcol    – popup start column
#   max_columns – list of [col_name, max_width] pairs from CalculateColumnWidthsV9
#   abbr_width  – allocated display width for the 'abbr' column
def FormatItem(
    item: dict<any>,
    options: dict<any>,
    mode: string,
    startcol: number,
    max_columns: list<any>,
    abbr_width: number
): string
  # Build a flat column dict from item fields
  var columns: dict<string> = extend(
      copy(get(item, 'columns', {})),
      {
        abbr: get(item, 'abbr', item.word),
        kind: get(item, 'kind', ''),
        menu: get(item, 'menu', ''),
      })

  var str: string = ''
  for col_entry in max_columns
    var name: string       = col_entry[0]
    var max_column: number = col_entry[1]

    if name ==# 'space'
      str ..= ' '
      continue
    endif

    if name ==# 'abbr'
      max_column = abbr_width
    endif

    var column: string = substitute(get(columns, name, ''), '[[:cntrl:]]', '?', 'g')
    if name ==# 'abbr' && column ==# ''
      column = item.word
    endif

    var col_width: number = CachedWidth(column)

    if col_width > max_column
      column = Truncate(column, max_column, max_column / 3, '...')
      col_width = CachedWidth(column)
    endif
    if col_width < max_column
      column ..= repeat(' ', max_column - col_width)
    endif

    str ..= column
  endfor

  if options.padding
    str ..= ' '
    if mode ==# 'c' || startcol != 1
      str = ' ' .. str
    endif
  endif

  return str
enddef

# ── public API ───────────────────────────────────────────────────────────────

# Clear the script-level width cache.  Called from pum#open() via pum.vim.
export def ClearWidthsCacheV9()
  widths_cache = {}
enddef

# Calculate the maximum column widths for a list of completion items.
#
# Mirrors s:calculate_column_widths() in autoload/pum/popup.vim.
#
# Returns [max_columns, total_width, non_abbr_length]
#   max_columns:     list of [column_name, max_width] pairs (non-zero columns)
#   total_width:     sum of all included column widths
#   non_abbr_length: sum of widths of non-'abbr' columns
export def CalculateColumnWidthsV9(
    items: list<dict<any>>, options: dict<any>
): list<any>
  var max_columns: list<any> = []
  var width: number = 0
  var non_abbr_length: number = 0
  var prev_column_length: number = 0

  for column in options.item_orders
    var max_column: number = 0

    if column ==# 'space'
      max_column = 1
    elseif column ==# 'abbr'
      for item in items
        var w: number = CachedWidth(get(item, 'abbr', item.word))
        if w > max_column
          max_column = w
        endif
      endfor
    elseif column ==# 'kind'
      for item in items
        var w: number = CachedWidth(get(item, 'kind', ''))
        if w > max_column
          max_column = w
        endif
      endfor
    elseif column ==# 'menu'
      for item in items
        var w: number = CachedWidth(get(item, 'menu', ''))
        if w > max_column
          max_column = w
        endif
      endfor
    else
      for item in items
        var w: number = CachedWidth(get(get(item, 'columns', {}), column, ''))
        if w > max_column
          max_column = w
        endif
      endfor
    endif

    # Apply per-column max constraint from options.max_columns
    var constraint: number = get(options.max_columns, column, max_column)
    if max_column > constraint
      max_column = constraint
    endif

    # Skip zero-width columns; also skip a 'space' after a skipped column
    if max_column <= 0 || (column ==# 'space' && prev_column_length == 0)
      prev_column_length = 0
      continue
    endif

    width += max_column
    add(max_columns, [column, max_column])
    if column !=# 'abbr'
      non_abbr_length += max_column
    endif
    prev_column_length = max_column
  endfor

  return [max_columns, width, non_abbr_length]
enddef

# Calculate final popup dimensions and format display lines.
#
# Mirrors s:calculate_dimensions() in autoload/pum/popup.vim.
# Uses the inlined Vim9 FormatItem() def instead of calling pum#_format_item()
# to avoid the per-item legacy function-call boundary.
#
# Returns a dict with keys:
#   width, height, padding, padding_height, padding_width, padding_left,
#   border_left, border_top, border_right, border_bottom, abbr_width, lines
export def CalculateDimensionsV9(
    items: list<dict<any>>,
    max_columns: list<any>,
    total_width: number,
    non_abbr_length: number,
    options: dict<any>,
    mode: string,
    startcol: number,
    pum_state: dict<any>
): dict<any>
  var pad_dims: list<number> = CalcPaddingDimensions(
      options, mode, startcol, options.border)

  var padding: number        = pad_dims[0]
  var padding_height: number = pad_dims[1]
  var padding_width: number  = pad_dims[2]
  var padding_left: number   = pad_dims[3]
  var border_left: number    = pad_dims[4]
  var border_top: number     = pad_dims[5]
  var border_right: number   = pad_dims[6]
  var border_bottom: number  = pad_dims[7]

  # Apply global width constraints
  var width: number = total_width + padding
  if options.min_width > 0 && width < options.min_width
    width = options.min_width
  endif
  if options.max_width > 0 && width > options.max_width
    width = options.max_width
  endif

  # 'abbr' column takes the remaining space
  var abbr_width: number = width - non_abbr_length - padding

  # Format each item using the inlined Vim9 def (avoids legacy call per item)
  var lines: list<string> = mapnew(items,
      (_, val) => FormatItem(val, options, mode, startcol, max_columns, abbr_width))

  # Apply height constraints
  var height: number = len(items)
  if options.max_height > 0 && height > options.max_height
    height = options.max_height
  endif
  if options.min_height > 0 && height < options.min_height
    height = options.min_height
  endif

  return {
    width: width,
    height: height,
    padding: padding,
    padding_height: padding_height,
    padding_width: padding_width,
    padding_left: padding_left,
    border_left: border_left,
    border_top: border_top,
    border_right: border_right,
    border_bottom: border_bottom,
    abbr_width: abbr_width,
    lines: lines,
  }
enddef
