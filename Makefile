LUA := $(shell command -v lua5.3 2>/dev/null || command -v lua)
TESTSERVER := .testserver

.PHONY: test package install-local clean

test:
	$(LUA) tests/run.lua tests/test_*.lua

package: clean
	mkdir -p dist/Client dist/Server
	cd client && zip -qr ../dist/Client/CopsAndRobbers.zip scripts lua mod_info
	rsync -a --exclude data server/CopsAndRobbers dist/Server/

install-local: package
	mkdir -p $(TESTSERVER)/Resources/Client $(TESTSERVER)/Resources/Server
	cp dist/Client/CopsAndRobbers.zip $(TESTSERVER)/Resources/Client/
	rsync -a dist/Server/CopsAndRobbers $(TESTSERVER)/Resources/Server/

clean:
	rm -rf dist
