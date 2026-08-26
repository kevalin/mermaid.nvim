.PHONY: test lint clean

test:
	node --test tests/preview_export.test.mjs
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

lint:
	luacheck lua tests

clean:
	rm -rf /tmp/plenary.nvim
