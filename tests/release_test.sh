#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@users.noreply.github.com
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@users.noreply.github.com
failures=0

check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'pr create') exit "${GH_PR_STATUS:-0}" ;;
esac
exit 1
STUB
cat > "$tmp/bin/fake-lua" <<'STUB'
#!/usr/bin/env bash
[[ -z ${EDIT_DURING_TEST:-} ]] || echo "unrelated edit" >> "$EDIT_DURING_TEST"
exit "${LUA_STATUS:-0}"
STUB
chmod +x "$tmp/bin/gh" "$tmp/bin/fake-lua"
export PATH="$tmp/bin:$PATH" VERSION_LUA=fake-lua

fixture() {
  local dir="$tmp/$1"
  git init -q --bare "$dir/origin.git"
  git init -q -b main "$dir/work"
  (
    cd "$dir/work"
    mkdir -p scripts server/CopsAndRobbers client/lua/ge/extensions client/mod_info/CopsAndRobbers docs
    cp "$ROOT/scripts/version.sh" scripts/
    echo 'local VERSION = "1.0.0"' > server/CopsAndRobbers/main.lua
    echo 'local CLIENT_VERSION = "1.0.0"' > client/lua/ge/extensions/copsAndRobbers.lua
    echo '{ "version_string": "1.0.0" }' > client/mod_info/CopsAndRobbers/info.json
    echo '# Cops and Robbers 1.0.0: features' > docs/FEATURES.md
    echo readme > README.md
    git add -A
    git commit -qm fixture
    git remote add origin "$dir/origin.git"
    git push -q origin main
  )
  echo "$dir/work"
}

run_version() {
  set +e
  (cd "$1" && scripts/version.sh 1.1.0) > "$tmp/out" 2>&1
  echo $? > "$tmp/status"
  set -e
}

work="$(fixture edit)"
EDIT_DURING_TEST="$work/README.md" LUA_STATUS=23 run_version "$work"
check "a failing version test keeps its exit status" '[[ $(cat "$tmp/status") == 23 ]]'
check "a failing version test returns to main" '[[ $(git -C "$work" branch --show-current) == main ]]'
check "a failing version test deletes the release branch" '! git -C "$work" show-ref --verify --quiet refs/heads/release/1.1.0'
check "a failing version test keeps unrelated edits" 'grep -q "unrelated edit" "$work/README.md"'
check "a failing version test restores the version files" '[[ -z $(git -C "$work" status --porcelain -- server client docs) ]]'

work="$(fixture hook-start)"
mkdir -p "$work/../hooks"
printf '#!/bin/sh\n[ "$(git branch --show-current)" = main ] || exit 1\n' > "$work/../hooks/post-checkout"
chmod +x "$work/../hooks/post-checkout"
git -C "$work" config core.hooksPath "$work/../hooks"
run_version "$work"
check "a failing checkout hook still fails the release" '[[ $(cat "$tmp/status") != 0 ]]'
check "a failing checkout hook returns to main" '[[ $(git -C "$work" branch --show-current) == main ]]'
check "a failing checkout hook deletes the release branch" '! git -C "$work" show-ref --verify --quiet refs/heads/release/1.1.0'

work="$(fixture hook-cleanup)"
mkdir -p "$work/../hooks"
printf '#!/bin/sh\n[ "$(git branch --show-current)" != main ] || exit 1\n' > "$work/../hooks/post-checkout"
chmod +x "$work/../hooks/post-checkout"
git -C "$work" config core.hooksPath "$work/../hooks"
LUA_STATUS=23 run_version "$work"
check "a failing hook during cleanup keeps the original status" '[[ $(cat "$tmp/status") == 23 ]]'
check "a failing hook during cleanup still deletes the release branch" '! git -C "$work" show-ref --verify --quiet refs/heads/release/1.1.0'

work="$(fixture existing)"
git -C "$work" branch release/1.1.0
run_version "$work"
check "an existing local release branch is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "already exists locally" "$tmp/out"'
check "an existing local release branch is kept" 'git -C "$work" show-ref --verify --quiet refs/heads/release/1.1.0'

work="$(fixture pr)"
GH_PR_STATUS=1 run_version "$work"
check "a failed PR keeps the pushed branch" 'git -C "$work/../origin.git" show-ref --verify --quiet refs/heads/release/1.1.0'
check "a failed PR prints a retry with title and body" 'grep -Fq -- "--title \"Release 1.1.0\" --body \"Merging this PR publishes the release. Deployment is separate.\"" "$tmp/out"'
check "a failed PR returns to main" '[[ $(git -C "$work" branch --show-current) == main ]]'

work="$(fixture ok)"
run_version "$work"
check "a release start succeeds" '[[ $(cat "$tmp/status") == 0 ]]'
check "a release start commits the new version" '[[ $(git -C "$work" show release/1.1.0:server/CopsAndRobbers/main.lua) == "local VERSION = \"1.1.0\"" ]]'

pkg="$tmp/package"
mkdir -p "$pkg"
cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$pkg/"
make -s -C "$pkg" package SOURCE_DATE_EPOCH=1700000000 >/dev/null
cp "$pkg/dist/release/SHA256SUMS" "$tmp/first"
find "$pkg/client" "$pkg/server" -exec touch -h -d '2001-02-03 04:05:06' {} +
TZ=Asia/Tokyo make -s -C "$pkg" package SOURCE_DATE_EPOCH=1700000000 >/dev/null
check "repackaging the same source gives the same checksums" 'cmp -s "$tmp/first" "$pkg/dist/release/SHA256SUMS"'
check "packaging leaves file times in dist/Server alone" '[[ $(stat -c %Y "$pkg/dist/Server/CopsAndRobbers/main.lua") == $(stat -c %Y "$pkg/server/CopsAndRobbers/main.lua") ]]'
check "the client zip holds the mod folders" 'unzip -Z1 "$pkg/dist/release/CopsAndRobbers.zip" | grep -x "mod_info/CopsAndRobbers/info.json" >/dev/null'

if ((failures)); then
  echo "$failures release checks failed"
  exit 1
fi
echo "all release checks passed"
