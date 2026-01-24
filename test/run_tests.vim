#!/usr/bin/env vim
" Test runner script for pum.vim
" This script runs all Test_* functions and reports results

" Load the plugin
set runtimepath+=.

" Source the test file
source test/pum.vim

" Get list of all test functions
let s:test_functions = []
redir => s:functions_output
silent! function
redir END

for line in split(s:functions_output, "\n")
  let match = matchstr(line, '^function Test_\zs\w\+')
  if match != ''
    call add(s:test_functions, 'Test_' . match)
  endif
endfor

" Run all tests
let s:total_tests = len(s:test_functions)
let s:passed = 0
let s:failed = 0

echo 'Running ' . s:total_tests . ' tests...'
echo ''

for test_func in s:test_functions
  " Clear any previous errors
  let v:errors = []
  
  try
    " Run the test
    execute 'call ' . test_func . '()'
    
    if len(v:errors) == 0
      let s:passed += 1
      echo 'ok ' . (s:passed + s:failed) . ' - ' . test_func
    else
      let s:failed += 1
      echo 'not ok ' . (s:passed + s:failed) . ' - ' . test_func
      for err in v:errors
        echo '  # ' . err
      endfor
    endif
  catch
    let s:failed += 1
    echo 'not ok ' . (s:passed + s:failed) . ' - ' . test_func
    echo '  # Exception: ' . v:exception
  endtry
endfor

echo ''
echo '# ' . repeat('=', 58)
echo '# Tests: ' . s:total_tests . ' | Passed: ' . s:passed . ' | Failed: ' . s:failed
echo '# ' . repeat('=', 58)

if s:failed > 0
  echo ''
  echo 'FAILED - ' . s:failed . ' test(s) failed'
  cquit
else
  echo ''
  echo 'SUCCESS - All tests passed!'
  qall!
endif
