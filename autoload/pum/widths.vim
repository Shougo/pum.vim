" autoload/pum/widths.vim
" Vim fast path for pum column-width and dimension calculation.
"
" Used on Vim (9.1+).  Neovim uses lua/pum/widths.lua instead.
" The public functions mirror the API of the Lua counterparts:
"   pum#widths#clear_widths_cache_v9()
"   pum#widths#calculate_column_widths_v9(items, options)
"   pum#widths#calculate_dimensions_v9(items, max_columns, total_width,
"                                       non_abbr_length, options, mode,
"                                       startcol, pum_state)

" Script-level display-width cache (string -> cell-width).
" Cleared by pum#widths#clear_widths_cache_v9() on each pum#open().
let s:widths_cache = {}

" ── helpers ─────────────────────────────────────────────────────────────────

function s:get_borderchar_height(ch) abort
  if a:ch->type() == v:t_string
    return a:ch->empty() ? 0 : 1
  elseif a:ch->type() == v:t_list && !a:ch->empty()
        \ && a:ch[0]->type() == v:t_string
    return a:ch[0]->empty() ? 0 : 1
  endif
  return 0
endfunction

function s:get_borderchar_width(ch) abort
  if a:ch->type() == v:t_string
    return a:ch->strdisplaywidth()
  elseif a:ch->type() == v:t_list && !a:ch->empty()
        \ && a:ch[0]->type() == v:t_string
    return a:ch[0]->strdisplaywidth()
  endif
  return 0
endfunction

function s:get_border_size(border) abort
  if a:border->type() == v:t_string
    return a:border ==# 'none' ? [0, 0, 0, 0] : [1, 1, 1, 1]
  elseif a:border->type() == v:t_list && !a:border->empty()
    const n = a:border->len()
    return [
          \   s:get_borderchar_width(a:border[3 % n]),
          \   s:get_borderchar_height(a:border[1 % n]),
          \   s:get_borderchar_width(a:border[7 % n]),
          \   s:get_borderchar_height(a:border[5 % n]),
          \ ]
  endif
  return [0, 0, 0, 0]
endfunction

" Returns [padding, padding_height, padding_width, padding_left,
"          border_left, border_top, border_right, border_bottom]
function s:calculate_padding_dimensions(options, mode, startcol, border) abort
  const padding = a:options.padding ?
        \ (a:mode ==# 'c' || a:startcol != 1) ? 2 : 1 : 0

  const [border_left, border_top, border_right, border_bottom] =
        \ s:get_border_size(a:border)

  let padding_height = 1 + border_top + border_bottom
  let padding_width  = 1 + border_left + border_right
  let padding_left   = border_left

  if a:options.padding && (a:mode ==# 'c' || a:startcol != 1)
    let padding_width += 2
    let padding_left  += 1
  endif

  return [padding, padding_height, padding_width, padding_left,
        \ border_left, border_top, border_right, border_bottom]
endfunction

" Cached display-width lookup for a single string.
function s:cached_width(text) abort
  if !s:widths_cache->has_key(a:text)
    let s:widths_cache[a:text] = strdisplaywidth(a:text)
  endif
  return s:widths_cache[a:text]
endfunction

" ── public API ───────────────────────────────────────────────────────────────

" Clear the script-level width cache.  Called from pum#open() via pum.vim.
function pum#widths#clear_widths_cache_v9() abort
  let s:widths_cache = {}
endfunction

" Calculate the maximum column widths for a list of completion items.
"
" Mirrors s:calculate_column_widths() in autoload/pum/popup.vim.
"
" Returns [max_columns, total_width, non_abbr_length]
"   max_columns:     list of [column_name, max_width] pairs (non-zero columns)
"   total_width:     sum of all included column widths
"   non_abbr_length: sum of widths of non-'abbr' columns
function pum#widths#calculate_column_widths_v9(items, options) abort
  let max_columns = []
  let width = 0
  let non_abbr_length = 0
  let prev_column_length = 0

  for column in a:options.item_orders
    " Calculate max width for each column type
    if column ==# 'space'
      let max_column = 1
    elseif column ==# 'abbr'
      let max_column = 0
      for item in a:items
        let w = s:cached_width(item->get('abbr', item.word))
        if w > max_column
          let max_column = w
        endif
      endfor
    elseif column ==# 'kind'
      let max_column = 0
      for item in a:items
        let w = s:cached_width(item->get('kind', ''))
        if w > max_column
          let max_column = w
        endif
      endfor
    elseif column ==# 'menu'
      let max_column = 0
      for item in a:items
        let w = s:cached_width(item->get('menu', ''))
        if w > max_column
          let max_column = w
        endif
      endfor
    else
      let max_column = 0
      for item in a:items
        let w = s:cached_width(item->get('columns', {})->get(column, ''))
        if w > max_column
          let max_column = w
        endif
      endfor
    endif

    " Apply per-column max constraint from options.max_columns
    let max_column = [
          \   max_column,
          \   a:options.max_columns->get(column, max_column),
          \ ]->min()

    " Skip zero-width columns; also skip a 'space' after a skipped column
    if max_column <= 0 || (column ==# 'space' && prev_column_length == 0)
      let prev_column_length = 0
      continue
    endif

    let width += max_column
    call add(max_columns, [column, max_column])
    if column !=# 'abbr'
      let non_abbr_length += max_column
    endif
    let prev_column_length = max_column
  endfor

  return [max_columns, width, non_abbr_length]
endfunction

" Calculate final popup dimensions and format display lines.
"
" Mirrors s:calculate_dimensions() in autoload/pum/popup.vim.
" Calls pum#_format_item() for each item (which itself branches between the
" Lua fast path on Neovim and the Vimscript path on Vim).
"
" Returns a dict with keys:
"   width, height, padding, padding_height, padding_width, padding_left,
"   border_left, border_top, border_right, border_bottom, abbr_width, lines
function pum#widths#calculate_dimensions_v9(
      \ items, max_columns, total_width, non_abbr_length,
      \ options, mode, startcol, pum_state) abort
  " Calculate padding dimensions
  let [padding, padding_height, padding_width, padding_left,
        \ border_left, border_top, border_right, border_bottom] =
        \ s:calculate_padding_dimensions(
        \   a:options, a:mode, a:startcol, a:options.border)

  " Apply global width constraints
  let width = a:total_width + padding
  if a:options.min_width > 0
    let width = [width, a:options.min_width]->max()
  endif
  if a:options.max_width > 0
    let width = [width, a:options.max_width]->min()
  endif

  " 'abbr' column takes the remaining space
  const abbr_width = width - a:non_abbr_length - padding

  " Format items into display lines
  let lines = a:items->copy()
        \ ->map({ _, val ->
        \   pum#_format_item(
        \     val, a:options, a:mode, a:startcol, a:max_columns, abbr_width
        \   )
        \ })

  " Apply height constraints
  let height = a:items->len()
  if a:options.max_height > 0
    let height = [height, a:options.max_height]->min()
  endif
  if a:options.min_height > 0
    let height = [height, a:options.min_height]->max()
  endif

  return #{
        \   width: width,
        \   height: height,
        \   padding: padding,
        \   padding_height: padding_height,
        \   padding_width: padding_width,
        \   padding_left: padding_left,
        \   border_left: border_left,
        \   border_top: border_top,
        \   border_right: border_right,
        \   border_bottom: border_bottom,
        \   abbr_width: abbr_width,
        \   lines: lines,
        \ }
endfunction
