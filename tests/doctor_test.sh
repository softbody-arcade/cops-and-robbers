#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
runner=$BASH
repo=$PWD
failures=0
valid_email="123+contributor@"
valid_email+="users.noreply.github.com"

cat > "$bin/tool" <<'STUB'
#!/bin/bash
noreply_domain=users.noreply.github.com
default_scopes="'repo', 'read:project'"
tool=${0##*/}
printf '%s %s\n' "$tool" "$*" >> "$CALL_LOG"
case "$*" in
    --version|-v)
        if [[ ${FAILED_VERSION_TOOL:-} == "$tool" ]]; then
            printf '%s\n' 'No version selected. Install 99.0.0 to continue.' >&2
            exit 1
        fi ;;
esac
case $tool in
    bash) echo "GNU bash, version ${BASH_REPORT:-4.4.23}(1)-release" ;;
    git)
        [[ $1 != config ]] || printf '%s\n' "$PWD" >> "$PWD_LOG"
        case "$*" in
            --version) echo "git version ${GIT_REPORT:-2.56.1}" ;;
            'config user.email') printf '%s\n' "${EMAIL_REPORT-123+contributor@$noreply_domain}" ;;
            'config core.hooksPath') printf '%s\n' "${HOOKS_REPORT-.githooks}" ;;
            *) exit 2 ;;
        esac ;;
    node) echo "v${NODE_REPORT:-22.1.0}" ;;
    gh)
        case "$*" in
            --version) echo "gh version ${GH_REPORT:-2.106.0} (2026-01-01)" ;;
            'auth status --active --hostname github.com --no-refresh')
                [[ ${GH_PROMPT_DISABLED:-} == 1 && ${NO_COLOR:-} == 1 ]] || exit 2
                case ${GH_LOGGED_IN:-yes} in
                    no) exit 1 ;;
                    network) printf '%s\n' 'github.com' '  X Failed to log in to github.com using token (GH_TOKEN)' '  - Active account: true' '  - The token in GH_TOKEN is invalid.' "  - Error: Post \"https://api.github.com/graphql\": proxyconnect tcp: $GH_ERROR" >&2; exit 1 ;;
                    deadline) printf '%s\n' 'github.com' '  X Failed to log in to github.com using token (GH_TOKEN)' '  - Active account: true' '  - The token in GH_TOKEN is invalid.' '  - Error: Post "https://api.github.com/graphql": context deadline exceeded' >&2; exit 1 ;;
                    timeout) printf '%s\n' '  X Timeout trying to log in to github.com account test (keyring)' >&2; exit 1 ;;
                    offline)
                        printf '%s\n' 'error connecting to api.github.com' 'Check your internet connection or https://githubstatus.com' >&2
                        exit 1 ;;
                esac
                printf '%s\n' 'github.com' \
                    '  ✓ Logged in to github.com account doctor-test-account (keyring)' \
                    '  - Active account: true' \
                    '  - Git operations protocol: https' \
                    '  - Token: gho_fixture_masked' >&2
                if [[ ${OMIT_SCOPES:-no} == yes ]]; then
                    :
                elif [[ ${CLICOLOR_FORCE:-0} == 1 ]]; then
                    printf '  - \033[1mToken scopes:\033[0m %s\n' "${GH_SCOPES-$default_scopes}" >&2
                else
                    printf '  - Token scopes: %s\n' "${GH_SCOPES-$default_scopes}" >&2
                fi ;;
            *) exit 2 ;;
        esac ;;
    lua5.3) echo "${LUA53_REPORT-Lua 5.3.6}" ;;
    luajit) echo 'LuaJIT 2.1.1736781742' ;;
    jq) echo 'jq-1.8.2' ;;
    unzip) echo 'UnZip 6.00 of 20 April 2009, by Debian. Original by Info-ZIP.' ;;
    zip) printf '%s\n' 'Copyright (c) 1990-2008 Info-ZIP.' 'This is Zip 3.0 (July 5th 2008), by Info-ZIP.' ;;
    tar) echo "${TAR_REPORT:-tar (GNU tar) 1.35}" ;;
    lua) echo "Lua ${LUA_REPORT:-5.4.8}" ;;
    ssh-keygen) exit 2 ;;
    *) echo "${0##*/} version 3.1.0" ;;
esac
STUB
chmod +x "$bin/tool"
for tool in bash git lua5.3 lua luajit python3 node npm zip unzip rsync tar jq gh ssh-keygen gzip sha256sum; do
    ln -s tool "$bin/$tool"
done

fail() {
    printf '%s\n%s\n' "$1" "$output" >&2
    failures=$((failures + 1))
}

run_doctor() {
    local expected=$1 status=0 lua=lua5.3
    shift
    : > "$bin/calls"
    : > "$bin/pwds"
    output=$(env PATH="$bin" CALL_LOG="$bin/calls" PWD_LOG="$bin/pwds" "$@" "$runner" "$repo/scripts/doctor" 2>&1) || status=$?
    if [[ $status != "$expected" ]]; then
        fail "Expected doctor exit $expected, got $status ($*)"
    fi

    [[ -e $bin/lua5.3 ]] || lua=lua
    {
        printf '%s\n' 'bash --version' 'git --version' "$lua -v" 'luajit -v' \
            'python3 --version' 'node --version' 'npm --version' 'zip -v'
        [[ ! -e $bin/gzip ]] || printf '%s\n' 'gzip --version'
        [[ ! -e $bin/sha256sum ]] || printf '%s\n' 'sha256sum --version'
        printf '%s\n' 'unzip -v' 'rsync --version' 'tar --version'
        if [[ -e $bin/jq ]]; then
            printf '%s\n' 'jq --version'
        fi
        printf '%s\n' 'gh --version'
        if [[ ${expect_auth:-yes} == yes ]]; then
            printf '%s\n' 'gh auth status --active --hostname github.com --no-refresh'
        fi
        printf '%s\n' 'git config user.email' 'git config core.hooksPath'
    } > "$bin/expected-calls"
    if ! diff -u "$bin/expected-calls" "$bin/calls"; then
        fail "Unexpected tool calls ($*)"
    fi
    assert_private 'doctor-test-account'
    assert_private 'gho_fixture_masked'
    assert_private "$valid_email"
}

expect_line() {
    if ! grep -Eq "^$1$" <<< "$output"; then
        fail "Missing expected line matching $1"
    fi
}

assert_private() {
    if [[ $output == *"$1"* ]]; then
        printf '%s\n' 'Doctor printed private fixture data' >&2
        failures=$((failures + 1))
    fi
}

mkdir "$bin/elsewhere"
cd "$bin/elsewhere"
run_doctor 0
if [[ $(cat "$bin/pwds") != "$(printf '%s\n%s' "$repo" "$repo")" ]]; then
    fail 'Git config did not run from the repository root'
fi
cd "$repo"
run_doctor 0
expect_line 'ok gzip.*'
expect_line 'ok sha256sum.*'
expect_line 'ok git 2\.56\.1'
expect_line 'ok node 22\.1\.0'
expect_line 'ok gh 2\.106\.0'
expect_line 'ok Lua 5\.3\.6'
expect_line 'ok luajit 2\.1\.1736781742'
expect_line 'ok jq 1\.8\.2'
expect_line 'ok zip 3\.0'
expect_line 'ok unzip 6\.00'
expect_line 'ok tar 1\.35'
for tool in bash python3 npm rsync ssh-keygen; do
    expect_line "ok $tool( .+)?"
done
expect_line 'ok gh project access'
expect_line 'ok git noreply email'
expect_line 'ok git hooks'

run_doctor 0 "GH_SCOPES='repo', 'project'" NODE_REPORT=24.1.0
expect_line 'ok gh project access'
expect_line 'ok node 24\.1\.0'

expect_auth=no run_doctor 1 GIT_REPORT=2.40.9 NODE_REPORT=21.7.3 BASH_REPORT=4.3.48 GH_REPORT=2.105.9 'LUA53_REPORT=Lua 5.2.4'
expect_line 'old git 2\.40\.9.*'
expect_line 'old node 21\.7\.3.*'
expect_line 'old bash 4\.3\.48.*'
expect_line 'old gh 2\.105\.9.*'
expect_line 'old Lua 5\.2\.4.*'
expect_line 'missing gh project access.*upgrade gh.*'

run_doctor 0 GIT_REPORT=2.41.0 NODE_REPORT=22.0.0
expect_line 'ok git 2\.41\.0'
expect_line 'ok node 22\.0\.0'

run_doctor 1 'LUA53_REPORT=Lua version unavailable'
expect_line 'missing Lua \(version unavailable, need 5\.3\+\).*'

run_doctor 1 'TAR_REPORT=bsdtar 3.7.7 - libarchive 3.7.7 zlib/1.2.12'
expect_line '(old|missing) tar.*brew install gnu-tar.*gnubin.*PATH.*'

run_doctor 1 FAILED_VERSION_TOOL=python3
expect_line 'missing python3.*brew install python.*'

run_doctor 1 FAILED_VERSION_TOOL=node
expect_line 'missing node.*brew install node.*'

run_doctor 0 CLICOLOR_FORCE=1
expect_line 'ok gh project access'

for error in 'dial tcp 127.0.0.1:9: connect: connection refused' 'dial tcp: lookup api.github.com: no such host' 'connection reset by peer' 'i/o timeout' 'network is unreachable'; do
    run_doctor 1 GH_LOGGED_IN=network GH_ERROR="$error"
    expect_line 'missing gh project access.*network.*'
done

run_doctor 1 GH_LOGGED_IN=deadline
expect_line 'missing gh project access.*network.*'

run_doctor 1 GH_LOGGED_IN=timeout
expect_line 'missing gh project access.*network.*'

run_doctor 1 GH_LOGGED_IN=offline
expect_line 'missing gh project access.*network.*'

run_doctor 1 GH_LOGGED_IN=no
expect_line 'missing gh project access.*gh auth login.*'

run_doctor 1 OMIT_SCOPES=yes
expect_line 'missing gh project access.*classic token.*'

run_doctor 1 GH_SCOPES=none
expect_line 'missing gh project access.*gh auth refresh.*'

run_doctor 1 "GH_SCOPES='repo', 'project:read'"
expect_line 'missing gh project access.*gh auth refresh.*'

email="private-contributor@"
email+="example.invalid"
run_doctor 1 EMAIL_REPORT="$email" HOOKS_REPORT=other-hooks
expect_line 'missing git noreply email.*'
expect_line 'missing git hooks.*make hooks.*'
assert_private "$email"

for email in '@users.noreply.github.com' "${valid_email}.example.invalid" "prefix${valid_email#*@}"; do
    run_doctor 1 EMAIL_REPORT="$email"
    expect_line 'missing git noreply email.*'
    assert_private "$email"
done

rm "$bin/gzip" "$bin/sha256sum"
run_doctor 1
expect_line 'missing gzip.*pacman -S gzip.*apt install gzip.*brew install gzip.*'
expect_line 'missing sha256sum.*pacman -S coreutils.*apt install coreutils.*brew install coreutils.*'

rm "$bin/lua5.3" "$bin/jq" "$bin/ssh-keygen"
run_doctor 1
expect_line 'ok Lua 5\.4\.8'
expect_line 'missing jq.*pacman.*apt.*brew.*'
expect_line 'missing ssh-keygen.*'
output=''
if grep -nE '\$\{[^}]*(,,|\^\^)' "$repo/scripts/doctor"; then
    fail 'scripts/doctor uses Bash 4 case conversion, which Bash 3.2 cannot parse'
fi

(( failures == 0 )) || exit 1
printf 'doctor: all checks passed\n'
