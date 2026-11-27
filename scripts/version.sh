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
if git show-ref --verify --quiet "refs/heads/$release"; then
  refuse "$release already exists locally"
fi
remote_branch="$(git ls-remote --heads origin "refs/heads/$release")"
[[ -z "$remote_branch" ]] || refuse "$release already exists on origin"
command -v gh >/dev/null || refuse "gh is required to open the release PR"
gh auth status >/dev/null 2>&1 || refuse "authenticate gh before starting a release"
old="$(sed -n 's/^local VERSION = "\(.*\)"/\1/p' server/CopsAndRobbers/main.lua)"
[[ "$old" =~ $pattern ]] || refuse "invalid current version: $old"
printf '%s\n' "$old" "$new" | sort -VCu || refuse "version must be greater than $old"

files=(server/CopsAndRobbers/main.lua client/lua/ge/extensions/copsAndRobbers.lua client/mod_info/CopsAndRobbers/info.json docs/FEATURES.md)
title="Release $new"
body="Merging this PR publishes the release. Deployment is separate."
pushed=0

back_on_main() {
  git switch main >/dev/null 2>&1 || true
  [[ "$(git branch --show-current)" == main ]]
}

finish() {
  local status=$?
  trap - EXIT
  if ((status != 0 && pushed == 0)); then
    git restore --source=HEAD --staged --worktree -- "${files[@]}" >/dev/null 2>&1 || true
    if back_on_main; then
      git branch -D "$release" >/dev/null 2>&1 || true
      echo "release $new aborted; nothing was pushed and main is unchanged" >&2
    else
      echo "release $new aborted and nothing was pushed, but switching back to main failed; switch to main and delete $release" >&2
    fi
  else
    back_on_main || echo "switching back to main failed; switch to main yourself" >&2
    if ((status != 0)); then
      echo "$release is pushed but its PR was not opened; run: gh pr create --base main --head $release --title \"$title\" --body \"$body\"" >&2
    fi
  fi
  exit "$status"
}

trap finish EXIT
git switch -c "$release"
sed -i -E "s/^(local VERSION = \")[^\"]+\"/\1$new\"/" server/CopsAndRobbers/main.lua
sed -i -E "s/^(local CLIENT_VERSION = \")[^\"]+\"/\1$new\"/" client/lua/ge/extensions/copsAndRobbers.lua
sed -i -E "s/(\"version_string\": *\")[^\"]+\"/\1$new\"/" client/mod_info/CopsAndRobbers/info.json
sed -i -E "1s/^# Cops and Robbers [^ ]+: features/# Cops and Robbers $new: features/" docs/FEATURES.md
echo "$old -> $new"
"${VERSION_LUA:-lua}" tests/run.lua tests/test_version.lua
git add -- "${files[@]}"
git commit -m "chore: version $new"
git push -u origin "$release"
pushed=1
gh pr create --base main --head "$release" --title "$title" --body "$body"
