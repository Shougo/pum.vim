function pum#util#_print_error(string, name = 'pum') abort
  echohl Error
  for line in
        \ (a:string->type() ==# v:t_string ? a:string : a:string->string())
        \ ->split("\n")->filter({ _, val -> val != ''})
    echomsg printf('[%s] %s', a:name, line)
  endfor
  echohl None
endfunction

function pum#util#_normalize_key_or_dict(key_or_dict, value) abort
  if a:key_or_dict->type() == v:t_dict
    return a:key_or_dict
  elseif a:key_or_dict->type() == v:t_string
    let base = {}
    let base[a:key_or_dict] = a:value
    return base
  endif
  return {}
endfunction

function pum#util#_truncate(str, max, footer_width, separator) abort
  const width = a:str->strwidth()
  if width <= a:max
    const ret = a:str
  else
    const header_width = a:max - a:separator->strwidth() - a:footer_width
    const ret = s:strwidthpart(a:str, header_width) .. a:separator
         \ .. s:strwidthpart_reverse(a:str, a:footer_width)
  endif
  return s:truncate(ret, a:max)
endfunction
function s:truncate(str, width) abort
  " Original function is from mattn.
  " http://github.com/mattn/googlereader-vim/tree/master

  if a:str =~# '^[\x00-\x7f]*$'
    return a:str->len() < a:width
          \ ? printf('%-' .. a:width .. 's', a:str)
          \ : a:str->strpart(0, a:width)
  endif

  let ret = a:str
  let width = a:str->strwidth()
  if width > a:width
    let ret = s:strwidthpart(ret, a:width)
    let width = ret->strwidth()
  endif

  return ret
endfunction
function s:strwidthpart(str, width) abort
  const str = a:str->tr("\t", ' ')
  const vcol = a:width + 2
  return str->matchstr('.*\%<' .. (vcol < 0 ? 0 : vcol) .. 'v')
endfunction
function s:strwidthpart_reverse(str, width) abort
  const str = a:str->tr("\t", ' ')
  const vcol = str->strwidth() - a:width
  return str->matchstr('\%>' .. (vcol < 0 ? 0 : vcol) .. 'v.*')
endfunction

function pum#util#_luacheck(module) abort
  return has('nvim') &&
        \ 'type(select(2, pcall(require, _A.module))) == "table"'
        \ ->luaeval(#{ module: a:module })
endfunction
