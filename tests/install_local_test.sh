#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

package=dist/Server/CopsAndRobbers
plugins=testserver/Resources/Server
installed=$plugins/CopsAndRobbers
mkdir -p "$package" dist/Client "$plugins/OtherPlugin"
touch dist/Client/CopsAndRobbers.zip "$plugins/OtherPlugin/main.lua"
printf '%s\n' '{"port": 1}' > "$package/config.json"
printf '%s\n' 'return true' > "$package/main.lua"

install_local() {
    make -s -f "$repo/Makefile" -o package install-local TESTSERVER=testserver
}

install_local
cmp "$package/config.json" "$installed/config.json"
cmp "$package/main.lua" "$installed/main.lua"

mkdir -p "$installed/data" "$package/data"
touch "$installed/old.lua"
printf '%s\n' '{"port": 12345}' > "$installed/config.json"
printf '%s\n' 'player score' > "$installed/data/scores"
printf '%s\n' 'packaged score' > "$package/data/scores"
printf '%s\n' 'previous round' > "$installed/data/history"
install_local

failures=0
check() {
    if ! "${@:2}"; then
        printf 'FAIL: %s\n' "$1" >&2
        failures=$((failures + 1))
    fi
}
check 'stale old.lua survived install-local' test ! -e "$installed/old.lua"
check 'installed config.json changed' grep -Fxq '{"port": 12345}' "$installed/config.json"
check 'installed data was overwritten' grep -Fxq 'player score' "$installed/data/scores"
check 'installed data was deleted' grep -Fxq 'previous round' "$installed/data/history"
check 'another server plugin was removed' test -f "$plugins/OtherPlugin/main.lua"
(( failures == 0 )) || exit 1
printf 'install-local: all checks passed\n'
