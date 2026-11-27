#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pin=$(git ls-tree HEAD base | awk '$2 == "commit" {print $3}')
[[ $pin =~ ^[0-9a-f]{40}$ ]] || { echo "base-pin: no base gitlink in HEAD" >&2; exit 1; }
url=$(git config -f .gitmodules submodule.base.url)
[[ $url == https://github.com/softbody-arcade/arcade-base ]] || { echo "base-pin: unexpected base URL $url" >&2; exit 1; }
[[ $(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}') == base ]] || { echo "base-pin: base must be the only submodule" >&2; exit 1; }
bad=$(git grep -nIE 'github\.com/softbody-arcade/arcade-base/(blob|tree)/[^/)[:space:]]+' -- ':!base' |
    grep -vE "github\.com/softbody-arcade/arcade-base/(blob|tree)/$pin/" || true)
if [[ -n $bad ]]; then
    printf 'base-pin: links to arcade-base must use the pinned commit %s:\n%s\n' "$pin" "$bad" >&2
    exit 1
fi
echo "base-pin: links match $pin"
