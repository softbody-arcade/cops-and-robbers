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

refuse() {
  echo "$*" >&2
  exit 1
}

release="release/$new"
title="Release $new"
body="Merging this PR publishes the release. Deployment is separate."
files=(server/CopsAndRobbers/main.lua client/lua/ge/extensions/copsAndRobbers.lua client/mod_info/CopsAndRobbers/info.json docs/FEATURES.md)

command -v gh >/dev/null || refuse "gh is required to open the release PR"
origin_url="$(git config --get remote.origin.url || true)"
[[ "$origin_url" =~ github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]] || refuse "origin must be a GitHub repository, got: $origin_url"
repo="${BASH_REMATCH[1]%.git}"
gh auth status >/dev/null 2>&1 || refuse "authenticate gh before starting a release"
git fetch origin '+refs/heads/main:refs/remotes/origin/main'
base="$(git rev-parse --verify --end-of-options refs/remotes/origin/main^{commit})"
set +e
git ls-remote --exit-code --heads origin "refs/heads/$release" >/dev/null
lookup=$?
set -e
((lookup != 0)) || refuse "$release already exists on origin"
((lookup == 2)) || refuse "could not check whether $release exists on origin"
old="$(git show "$base:server/CopsAndRobbers/main.lua" | sed -n 's/^local VERSION = "\(.*\)"/\1/p')"
[[ "$old" =~ $pattern ]] || refuse "invalid current version: $old"
printf '%s\n' "$old" "$new" | sort -VCu || refuse "version must be greater than $old"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/src"
git archive "$base" | tar -x -C "$tmp/src"
(
  cd "$tmp/src"
  sed -i -E "s/^(local VERSION = \")[^\"]+\"/\1$new\"/" server/CopsAndRobbers/main.lua
  sed -i -E "s/^(local CLIENT_VERSION = \")[^\"]+\"/\1$new\"/" client/lua/ge/extensions/copsAndRobbers.lua
  sed -i -E "s/(\"version_string\": *\")[^\"]+\"/\1$new\"/" client/mod_info/CopsAndRobbers/info.json
  sed -i -E "1s/^# Cops and Robbers [^ ]+: features/# Cops and Robbers $new: features/" docs/FEATURES.md
  "${VERSION_LUA:-lua}" tests/run.lua tests/test_version.lua
)
echo "$old -> $new"

export GIT_INDEX_FILE="$tmp/index"
git read-tree "$base"
for file in "${files[@]}"; do
  mode="$(git ls-tree "$base" -- "$file" | cut -d' ' -f1)"
  blob="$(git hash-object -w -- "$tmp/src/$file")"
  git update-index --cacheinfo "$mode,$blob,$file"
done
sign=()
[[ "$(git config --type=bool commit.gpgsign || true)" != true ]] || sign=(-S)
commit="$(git commit-tree "${sign[@]}" "$(git write-tree)" -p "$base" -m "chore: version $new")"
unset GIT_INDEX_FILE

git push --force-with-lease="refs/heads/$release:" origin "$commit:refs/heads/$release"
if ! gh pr create --repo "$repo" --base main --head "$release" --title "$title" --body "$body"; then
  echo "$release is pushed but its PR was not opened; run: gh pr create --repo $repo --base main --head $release --title \"$title\" --body \"$body\"" >&2
  exit 1
fi
