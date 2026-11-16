#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

new="${1:-}"
if [[ ! "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: make version V=x.y.z" >&2
  exit 1
fi
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != main ]]; then
  echo "the version is bumped on main after a merge, not on $branch" >&2
  exit 1
fi

old="$(sed -n 's/^local VERSION = "\(.*\)"/\1/p' server/CopsAndRobbers/main.lua)"
sed -i -E "s/^(local VERSION = \")[^\"]+\"/\1$new\"/" server/CopsAndRobbers/main.lua
sed -i -E "s/^(local CLIENT_VERSION = \")[^\"]+\"/\1$new\"/" client/lua/ge/extensions/copsAndRobbers.lua
sed -i -E "s/(\"version_string\": *\")[^\"]+\"/\1$new\"/" client/mod_info/CopsAndRobbers/info.json
sed -i -E "1s/^# Cops and Robbers [^ ]+: features/# Cops and Robbers $new: features/" docs/FEATURES.md
echo "$old -> $new"
