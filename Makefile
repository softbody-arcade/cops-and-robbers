LUA := $(shell command -v lua5.3 2>/dev/null || command -v lua)
TESTSERVER := .testserver
ARCHIVE_EPOCH := 315532800

.PHONY: test vuecheck package install-local clean deploy version hooks privacy

test:
	$(LUA) tests/run.lua tests/test_*.lua
	python3 -I tests/privacy_check_test.py
	bash tests/release_test.sh

privacy:
	scripts/privacy-check tree HEAD

hooks:
	git config core.hooksPath .githooks

vuecheck:
	cd tools/vuecheck && $(if $(CI),npm ci,npm install) --silent --no-audit --no-fund && node check.mjs ../../client/ui
	cd tools/vuecheck && node --experimental-vm-modules hud-settings.test.mjs
	cd tools/vuecheck && node --experimental-vm-modules panel-tabs.test.mjs

package: clean
	mkdir -p dist/Client dist/Server dist/release dist/stage
	rsync -rpL --chmod=D755,F644 client/scripts client/lua client/mod_info client/ui client/art dist/stage/
	find dist/stage -exec touch -h -d @$(ARCHIVE_EPOCH) {} +
	cd dist/stage && find scripts lua mod_info ui art -print > ../client-files
	LC_ALL=C sort -o dist/client-files dist/client-files
	cd dist/stage && TZ=UTC zip -qX ../Client/CopsAndRobbers.zip -@ < ../client-files
	rm -rf dist/stage dist/client-files
	rsync -a --exclude data server/CopsAndRobbers dist/Server/
	cp dist/Client/CopsAndRobbers.zip dist/release/
	tar --sort=name --mtime=@$(ARCHIVE_EPOCH) --owner=0 --group=0 --numeric-owner --mode=a-st,u+rw,go-w,a+rX -cf dist/server.tar -C dist/Server CopsAndRobbers
	gzip -n -c dist/server.tar > dist/release/CopsAndRobbers-server.tar.gz
	rm dist/server.tar
	cd dist/release && sha256sum CopsAndRobbers.zip CopsAndRobbers-server.tar.gz > SHA256SUMS

install-local: package
	mkdir -p $(TESTSERVER)/Resources/Client $(TESTSERVER)/Resources/Server
	cp dist/Client/CopsAndRobbers.zip $(TESTSERVER)/Resources/Client/
	rsync -a dist/Server/CopsAndRobbers $(TESTSERVER)/Resources/Server/

clean:
	rm -rf dist

deploy: package
	./scripts/deploy.sh

version: export RELEASE_VERSION := $(value V)
version: export VERSION_LUA := $(LUA)
version:
	./scripts/version.sh "$$RELEASE_VERSION"
