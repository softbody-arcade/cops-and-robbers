#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

new="${1:-}"
part="(0|[1-9][0-9]*)"
pattern="^$part[.]$part[.]$part$"
if [[ ! "$new" =~ $pattern ]]; then
  echo "usage: make version V=x.y.z" >&2
  exit 1
fi
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != main ]]; then
  echo "start a release on main (current branch: $branch)" >&2
  exit 1
fi

refuse() {
  echo "$*" >&2
  exit 1
}

[[ -z "$(git status --porcelain)" ]] || refuse "start a release with a clean working tree"
git fetch origin '+refs/heads/main:refs/remotes/origin/main'
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || refuse "main must match origin/main"

release="release/$new"
remote_branch="$(git ls-remote --heads origin "refs/heads/$release")"
[[ -z "$remote_branch" ]] || refuse "$release already exists on origin"
command -v gh >/dev/null || refuse "gh is required to open the release PR"
gh auth status >/dev/null 2>&1 || refuse "authenticate gh before starting a release"
old="$(sed -n 's/^local VERSION = "\(.*\)"/\1/p' server/CopsAndRobbers/main.lua)"
[[ "$old" =~ $pattern ]] || refuse "invalid current version: $old"
printf '%s\n' "$old" "$new" | sort -VCu || refuse "version must be greater than $old"
pushed=0
return_to_main() {
  status=$?
  if [[ $status -ne 0 && $pushed -eq 0 ]]; then
    git switch -f main >/dev/null 2>&1 || exit 1
    git branch -D "$release" >/dev/null 2>&1 || true
    echo "release $new aborted; nothing was pushed and main is unchanged" >&2
  else
    git switch main >/dev/null 2>&1 || exit 1
    if [[ $status -ne 0 ]]; then
      echo "$release is pushed but its PR was not opened; run: gh pr create --base main --head $release --title \"Release $new\"" >&2
    fi
  fi
  exit "$status"
}
git switch -c "$release"
trap return_to_main EXIT
sed -i -E "s/^(local VERSION = \")[^\"]+\"/\1$new\"/" server/CopsAndRobbers/main.lua
sed -i -E "s/^(local CLIENT_VERSION = \")[^\"]+\"/\1$new\"/" client/lua/ge/extensions/copsAndRobbers.lua
sed -i -E "s/(\"version_string\": *\")[^\"]+\"/\1$new\"/" client/mod_info/CopsAndRobbers/info.json
sed -i -E "1s/^# Cops and Robbers [^ ]+: features/# Cops and Robbers $new: features/" docs/FEATURES.md
echo "$old -> $new"
"${VERSION_LUA:-lua}" tests/run.lua tests/test_version.lua
git add -- server/CopsAndRobbers/main.lua client/lua/ge/extensions/copsAndRobbers.lua client/mod_info/CopsAndRobbers/info.json docs/FEATURES.md
git commit -m "chore: version $new"
git push -u origin "$release"
pushed=1
gh pr create --base main --head "$release" --title "Release $new" --body "Merging this PR publishes the release. Deployment is separate."
