LUA := $(shell command -v lua5.3 2>/dev/null || command -v lua)
TESTSERVER := .testserver

.PHONY: test vuecheck package install-local clean deploy version hooks privacy

test:
	$(LUA) tests/run.lua tests/test_*.lua
	python3 -I tests/privacy_check_test.py

privacy:
	scripts/privacy-check tree HEAD

hooks:
	git config core.hooksPath .githooks

vuecheck:
	cd tools/vuecheck && $(if $(CI),npm ci,npm install) --silent --no-audit --no-fund && node check.mjs ../../client/ui
	cd tools/vuecheck && node --experimental-vm-modules hud-settings.test.mjs
	cd tools/vuecheck && node --experimental-vm-modules panel-tabs.test.mjs

package: clean
	mkdir -p dist/Client dist/Server
	cd client && zip -qr ../dist/Client/CopsAndRobbers.zip scripts lua mod_info ui art
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
