VIM ?= vim

test:
	$(VIM) -u NONE -N -U NONE -S test/run_tests.vim

.PHONY: test
