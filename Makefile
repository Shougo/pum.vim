VIM ?= vim

test:
	$(VIM) -i NONE -u NONE -N -U NONE -V1 -e -s -S test/run_tests.vim

.PHONY: test
