#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
runner=$BASH

cat > "$bin/tool" <<'STUB'
#!/bin/bash
noreply_domain=users.noreply.github.com
default_scopes="'repo', 'read:project'"
case ${0##*/} in
    bash) echo "GNU bash, version ${BASH_REPORT:-4.4.23}(1)-release" ;;
    git)
        case "$*" in
            --version) echo "git version ${GIT_REPORT:-2.41.0}.vendor" ;;
            'config user.email') printf '%s\n' "${EMAIL_REPORT-123+contributor@$noreply_domain}" ;;
            'config core.hooksPath') printf '%s\n' "${HOOKS_REPORT-.githooks}" ;;
            *) exit 2 ;;
        esac ;;
    node) echo "v${NODE_REPORT:-22.9.0}" ;;
    gh)
        case "$*" in
            --version) echo "gh version ${GH_REPORT:-2.106.0} (2026-01-01)" ;;
            'auth status --active --hostname github.com --no-refresh')
                [[ ${GH_LOGGED_IN:-yes} == yes ]] || exit 1
                printf '  - Token scopes: %s\n' "${GH_SCOPES-$default_scopes}" >&2 ;;
            *) exit 2 ;;
        esac ;;
    lua5.3) echo 'Lua 5.3.6' ;;
    lua) echo "Lua ${LUA_REPORT:-5.4.8}" ;;
    ssh-keygen) exit 2 ;;
    *) echo "${0##*/} version 3.1.0" ;;
esac
STUB
chmod +x "$bin/tool"
for tool in bash git lua5.3 lua luajit python3 node npm zip unzip rsync tar jq gh ssh-keygen; do
    ln -s tool "$bin/$tool"
done

run_doctor() {
    local expected=$1 status=0
    shift
    output=$(env PATH="$bin" "$@" "$runner" scripts/doctor 2>&1) || status=$?
    if [[ $status != "$expected" ]]; then
        printf 'Expected doctor exit %s, got %s\n%s\n' "$expected" "$status" "$output" >&2
        exit 1
    fi
}

expect_line() {
    if ! grep -Eq "^$1$" <<< "$output"; then
        printf 'Missing expected line matching %s\n%s\n' "$1" "$output" >&2
        exit 1
    fi
}

run_doctor 0
expect_line 'ok git 2\.41\.0'
expect_line 'ok node 22\.9\.0'
expect_line 'ok gh 2\.106\.0'
expect_line 'ok Lua 5\.3\.6'
for tool in bash luajit python3 npm zip unzip rsync tar jq ssh-keygen; do
    expect_line "ok $tool( .+)?"
done
expect_line 'ok gh project access'
expect_line 'ok git noreply email'
expect_line 'ok git hooks'
[[ $output != *123+contributor* ]]

run_doctor 0 "GH_SCOPES='repo', 'project'" NODE_REPORT=24.1.0
expect_line 'ok gh project access'
expect_line 'ok node 24\.1\.0'

run_doctor 1 GIT_REPORT=2.9.0 NODE_REPORT=20.19.0 BASH_REPORT=3.2.57 GH_REPORT=2.99.0
expect_line 'old git 2\.9\.0.*'
expect_line 'old node 20\.19\.0.*'
expect_line 'old bash 3\.2\.57.*'
expect_line 'old gh 2\.99\.0.*'

run_doctor 1 GH_LOGGED_IN=no
expect_line 'missing gh project access.*gh auth login.*'

run_doctor 1 "GH_SCOPES='repo', 'project:read'"
expect_line 'missing gh project access.*gh auth refresh.*'

email="private-contributor@"
email+="example.invalid"
run_doctor 1 EMAIL_REPORT="$email" HOOKS_REPORT=other-hooks
expect_line 'missing git noreply email.*'
expect_line 'missing git hooks.*make hooks.*'
[[ $output != *"$email"* ]]

rm "$bin/lua5.3" "$bin/jq" "$bin/ssh-keygen"
run_doctor 1
expect_line 'ok Lua 5\.4\.8'
expect_line 'missing jq.*pacman.*apt.*brew.*'
expect_line 'missing ssh-keygen.*'
printf 'doctor: all checks passed\n'
