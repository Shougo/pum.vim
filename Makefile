PATH := ./vim-themis/bin:$(PATH)
export THEMIS_VIM  := nvim
export THEMIS_ARGS := -e -s --headless
export THEMIS_HOME := ./vim-themis

lint: lint/vim

lint/vim:
	vint --version
	vint autoload

test: vim-themis
	themis --version
	themis test/

vim-themis:
	git clone https://github.com/thinca/vim-themis vim-themis

.PHONY: lint lint/vim test
