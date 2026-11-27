#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
link='github\.com/softbody-arcade/arcade-base/(blob|tree)/[^/)[:space:]]+'

unpinned() {
    grep -oE "$link" | grep -vxE "github\.com/softbody-arcade/arcade-base/(blob|tree)/$1" || true
}

self=0123456789abcdef0123456789abcdef01234567
two="[a](https://github.com/softbody-arcade/arcade-base/blob/main/AGENTS.md) and [b](https://github.com/softbody-arcade/arcade-base/blob/$self/docs/ROLES.md)"
[[ $(unpinned "$self" <<< "$two") == github.com/softbody-arcade/arcade-base/blob/main ]] || { echo "base-pin: self-test missed an unpinned link next to a pinned one" >&2; exit 1; }
[[ -z $(unpinned "$self" <<< "[b](https://github.com/softbody-arcade/arcade-base/tree/$self/docs)") ]] || { echo "base-pin: self-test flagged a pinned link" >&2; exit 1; }

entries=$(git ls-files -s -- base)
[[ $(awk '$3 != 0' <<< "$entries") == "" ]] || { echo "base-pin: the base pin has a merge conflict" >&2; exit 1; }
pin=$(awk '$1 == "160000" && $3 == 0 {print $2}' <<< "$entries")
[[ $pin =~ ^[0-9a-f]{40}$ ]] || { echo "base-pin: no base gitlink in the index" >&2; exit 1; }
url=$(git config -f .gitmodules submodule.base.url)
[[ $url == https://github.com/softbody-arcade/arcade-base ]] || { echo "base-pin: unexpected base URL $url" >&2; exit 1; }
[[ $(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}') == base ]] || { echo "base-pin: base must be the only submodule" >&2; exit 1; }
bad=
while IFS= read -r file; do
    found=$(unpinned "$pin" < "$file")
    [[ -z $found ]] || bad+="$file: $found"$'\n'
done < <(git grep -lIE "$link" -- ':!base' ':!tests/base_pin_test.sh')
if [[ -n $bad ]]; then
    printf 'base-pin: links to arcade-base must use the pinned commit %s:\n%s' "$pin" "$bad" >&2
    exit 1
fi
echo "base-pin: links match $pin"
