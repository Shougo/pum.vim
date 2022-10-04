# pum.vim

Note: It is still experimental version.

[![Doc](https://img.shields.io/badge/doc-%3Ah%20pum-orange.svg)](doc/pum.txt)

Please read [help](doc/pum.txt) for details.

<!-- vim-markdown-toc GFM -->

- [Introduction](#introduction)
- [Install](#install)
- [Configuration](#configuration)
- [Screenshots](#screenshots)

<!-- vim-markdown-toc -->

## Introduction

pum.vim is the framework library to implement original popup menu completion.

It works both insert mode and command line mode.

## Install

**Note:** pum.vim requires Neovim (0.5.0+ and of course, **latest** is
recommended) or Vim 8.2.1978.

pum.vim detects if "noice.nvim" is installed.
https://github.com/folke/noice.nvim

For vim-plug

```viml
call plug#begin()

Plug 'Shougo/pum.vim'

call plug#end()
```

For dein.vim

```viml
call dein#begin()

call dein#add('Shougo/pum.vim')

call dein#end()
```

## Configuration

```vim
inoremap <C-n>   <Cmd>call pum#map#insert_relative(+1)<CR>
inoremap <C-p>   <Cmd>call pum#map#insert_relative(-1)<CR>
inoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
inoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
inoremap <PageDown> <Cmd>call pum#map#insert_relative_page(+1)<CR>
inoremap <PageUp>   <Cmd>call pum#map#insert_relative_page(-1)<CR>
```

## Screenshots

## Plans

- [x] PumCompleteDone autocmd
- [x] PumCompleteChanged autocmd
- [x] Highlight options
- [x] Scroll support
- [x] Highlight match the input
