LUA := $(shell command -v lua5.3 2>/dev/null || command -v lua)
TESTSERVER := .testserver

.PHONY: test vuecheck package install-local clean deploy version

test:
	$(LUA) tests/run.lua tests/test_*.lua

vuecheck:
	cd tools/vuecheck && npm install --silent --no-audit --no-fund && node check.mjs ../../client/ui

package: clean
	mkdir -p dist/Client dist/Server
	cd client && zip -qr ../dist/Client/CopsAndRobbers.zip scripts lua mod_info ui
	rsync -a --exclude data server/CopsAndRobbers dist/Server/

install-local: package
	mkdir -p $(TESTSERVER)/Resources/Client $(TESTSERVER)/Resources/Server
	cp dist/Client/CopsAndRobbers.zip $(TESTSERVER)/Resources/Client/
	rsync -a dist/Server/CopsAndRobbers $(TESTSERVER)/Resources/Server/

clean:
	rm -rf dist

deploy: package
	./scripts/deploy.sh

version:
	./scripts/version.sh $(V)
	$(LUA) tests/run.lua tests/test_version.lua
