"set verbose=1
let s:suite = themis#suite('pum')
let s:assert = themis#helper('assert')

function s:suite.before_each() abort
  call pum#_init()
  call pum#_init_options()
  normal! ggVGd
endfunction

function s:suite.after_each() abort
endfunction

function s:suite.open() abort
  call s:assert.equals(pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }]), -1)
  call s:assert.not_equals(pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i'), -1)
  call s:assert.not_equals(pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'c'), -1)
endfunction

function s:suite.highlight() abort
  call pum#open(1, [
        \ #{ word: 'foo bar', highlights: [
        \   #{ type: 'abbr', name: 'abbr_foo', hl_group: 'Function', col: 1, width: 3 },
        \   #{ type: 'abbr', name: 'abbr_bar', hl_group: 'Underlined', col: 5, width: 3 },
        \ ]},
        \ #{ word: 'bar', kind: 'bar', highlights: [
        \   #{ type: 'kind', name: 'kind_foo', hl_group: 'Error', col: 1, width: 3 },
        \ ]},
        \ #{ word: 'baz', menu: 'baz', highlights: [
        \   #{ type: 'menu', name: 'menu_baz', hl_group: 'WarningMsg', col: 1, width: 3 },
        \ ]},
        \ ], 'i')
endfunction

function s:suite.select_relative() abort
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }])

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call s:assert.equals(pum#_get().cursor, -1)

  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  call pum#map#select_relative(1)
  call pum#map#select_relative(1)

  call s:assert.equals(pum#_get().cursor, 2)

  call pum#map#select_relative(-1)

  call s:assert.equals(pum#_get().cursor, 1)
endfunction

function s:suite.insert_relative() abort
  call pum#open(1, [#{ word: 'foo' }, #{ word: 'bar' }], 'i')

  call pum#map#insert_relative(1)
  call pum#map#insert_relative(1)

  call s:assert.equals(pum#_get().cursor, 2)

  call pum#map#insert_relative(-1)
  call pum#map#insert_relative(-1)

  call s:assert.equals(pum#_get().cursor, 0)
endfunction

function s:suite.format_item() abort
  const item = #{ word: 'foo', kind: 'bar', menu: 'baz' }

  call s:assert.equals(
        \ pum#_format_item(item,
        \ #{
        \   item_orders: ['abbr', 'space', 'kind', 'space', 'menu'],
        \   padding: v:true,
        \ }, 'i', 2,
        \ [
        \   ['abbr', 3],
        \   ['space', 1],
        \   ['kind', 3],
        \   ['space', 1],
        \   ['menu', 3],
        \ ], 3),
        \ ' foo bar baz ')

  call s:assert.equals(
        \ pum#_format_item(item,
        \ #{
        \   item_orders: ['menu', 'space', 'abbr', 'space', 'kind'],
        \   padding: v:false,
        \ }, 'i', 1,
        \ [
        \   ['menu', 3],
        \   ['space', 1],
        \   ['abbr', 3],
        \   ['space', 1],
        \   ['kind', 3],
        \ ], 3),
        \ 'baz foo bar')

  " truncate check
  const item2 = #{ word: 'aaaaaaaaaaaaaaaaaa', kind: 'bbb', menu: 'ccc' }
  call s:assert.equals(
        \ pum#_format_item(item2,
        \ #{
        \   item_orders: ['menu', 'space', 'abbr', 'space', 'kind'],
        \   padding: v:false,
        \ }, 'i', 1,
        \ [
        \   ['menu', 3],
        \   ['space', 1],
        \   ['abbr', 10],
        \   ['space', 1],
        \   ['kind', 3],
        \ ], 10),
        \ 'ccc aaaa...aaa bbb')
endfunction
