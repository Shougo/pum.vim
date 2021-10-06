let s:suite = themis#suite('pum')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
endfunction

function! s:suite.after_each() abort
  call pum#_init()
endfunction

function! s:suite.open() abort
  call s:assert.equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}]), -1)
  call s:assert.not_equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'i'), -1)
  call s:assert.not_equals(pum#open(1, [{'word': 'foo'}, {'word': 'bar'}], 'c'), -1)
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
