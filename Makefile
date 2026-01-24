VIM ?= vim

test:
	@echo "Running tests with Vim's native assert API..."
	@$(VIM) -u NONE -N -U NONE \
		--cmd 'set runtimepath+=.' \
		-S test/pum.vim \
		-c 'if len(v:errors) == 0 | echo "All tests passed!" | qall! | else | echo "Tests failed:" | for err in v:errors | echo err | endfor | cquit | endif'

.PHONY: test
