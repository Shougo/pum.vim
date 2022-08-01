set verbose=1
let s:suite = themis#suite('pum')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  call pum#_init()
  normal! ggVGd
endfunction

function! s:suite.after_each() abort
endfunction

function! s:suite.open() abort
  call s:assert.equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}]), -1)
  call s:assert.not_equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'i'), -1)
  call s:assert.not_equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'c'), -1)
endfunction

function! s:suite.highlight() abort
  call pum#open(1, [
        \ {'word': 'foo bar', 'highlights': [
        \   {'type': 'abbr', 'name': 'abbr_foo', 'hl_group': 'Function', 'col': 0, 'width': 3},
        \   {'type': 'abbr', 'name': 'abbr_bar', 'hl_group': 'Underlined', 'col': 4, 'width': 3},
        \ ]},
        \ {'word': 'bar', 'kind': 'bar', 'highlights': [
        \   {'type': 'kind', 'name': 'kind_foo', 'hl_group': 'Error', 'col': 0, 'width': 3},
        \ ]},
        \ {'word': 'baz', 'menu': 'baz', 'highlights': [
        \   {'type': 'menu', 'name': 'menu_baz', 'hl_group': 'WarningMsg', 'col': 0, 'width': 3},
        \ ]},
        \ ], 'i')
endfunction

function! s:suite.select_relative() abort
  call pum#open(1, [{'word': 'foo'}, {'word': 'bar'}])

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call s:assert.equals(pum#_get().cursor, -1)

  call pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'i')

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call s:assert.equals(pum#_get().cursor, 2)

  call pum#map#select_relative(-1)
  call pum#map#select_relative(-1)

  call s:assert.equals(pum#_get().cursor, 0)
endfunction

function! s:suite.insert_relative() abort
  call pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'i')

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call s:assert.equals(pum#_get().cursor, 2)

  call pum#map#select_relative(-1)
  call pum#map#select_relative(-1)

  call s:assert.equals(pum#_get().cursor, 0)
endfunction

function! s:suite.format_item() abort
  let item = {'word': 'foo', 'kind': 'bar', 'menu': 'baz'}

  call s:assert.equals(
        \ pum#_format_item(item,
        \ {
        \   'item_orders': ['abbr', 'kind', 'menu'],
        \   'padding': v:true,
        \ }, 'i', 2, 3, 3, 3),
        \ ' foo bar baz ')

  call s:assert.equals(
        \ pum#_format_item(item,
        \ {
        \   'item_orders': ['menu', 'abbr', 'kind'],
        \   'padding': v:false,
        \ }, 'i', 1, 3, 3, 3),
        \ 'baz foo bar')
endfunction
