#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

package=dist/Server/CopsAndRobbers
plugins=testserver/Resources/Server
installed=$plugins/CopsAndRobbers
mkdir -p "$package/arcade" "$package/cnr" dist/Client "$plugins/OtherPlugin"
touch dist/Client/CopsAndRobbers.zip "$plugins/OtherPlugin/main.lua"
printf '%s\n' '{"port": 1}' > "$package/config.json"
printf '%s\n' 'return true' > "$package/main.lua"

install_local() {
    make -s -f "$repo/Makefile" -o package install-local TESTSERVER=testserver
}

install_local
cmp "$package/config.json" "$installed/config.json"
cmp "$package/main.lua" "$installed/main.lua"

mkdir -p "$installed/data" "$installed/cnr/data"
touch "$installed/old.lua" "$installed/arcade/config.json" "$installed/cnr/data/x"
printf '%s\n' '{"port": 12345}' > "$installed/config.json"
recovery_files=(config.json.corrupt-20261128-101500 config.json.tmp config.json.bak)
for file in "${recovery_files[@]}"; do
    printf '%s\n' "$file" > "$installed/$file"
done
printf '%s\n' 'player score' > "$installed/data/scores"
install_local

failures=0
check() {
    if ! "${@:2}"; then
        printf 'FAIL: %s\n' "$1" >&2
        failures=$((failures + 1))
    fi
}
check 'stale old.lua survived install-local' test ! -e "$installed/old.lua"
check 'packaged config.json was not installed' cmp -s "$package/config.json" "$installed/config.json"
for file in "${recovery_files[@]}"; do
    check "lost recovery file $file" grep -Fxq "$file" "$installed/$file"
done
check 'installed data was lost' grep -Fxq 'player score' "$installed/data/scores"
check 'stale nested config.json survived' test ! -e "$installed/arcade/config.json"
check 'stale nested data survived' test ! -e "$installed/cnr/data"
check 'another server plugin was removed' test -f "$plugins/OtherPlugin/main.lua"

rm -rf "$installed/data"
mkdir "$tmp/shared-data"
ln -s "$tmp/shared-data" "$installed/data"
install_local
check 'data symlink was removed' test -L "$installed/data"
(( failures == 0 )) || exit 1
printf 'install-local: all checks passed\n'
