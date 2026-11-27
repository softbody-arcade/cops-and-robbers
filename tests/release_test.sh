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

same_checkout() {
  [[ $(git -C "$1" branch --show-current) == main && $(git -C "$1" rev-parse HEAD) == "$2" ]] &&
    ! git -C "$1" show-ref --verify --quiet refs/heads/release/1.1.0
}

work="$(fixture edit)"
head="$(git -C "$work" rev-parse HEAD)"
echo "my note" >> "$work/docs/FEATURES.md"
echo "staged note" >> "$work/README.md"
git -C "$work" add README.md
EDIT_DURING_TEST="$work/server/CopsAndRobbers/main.lua" LUA_STATUS=23 run_version "$work"
check "a failing version test keeps its exit status" '[[ $(cat "$tmp/status") == 23 ]]'
check "a failing version test leaves the checkout on main" 'same_checkout "$work" "$head"'
check "a failing version test pushes nothing" '! git -C "$work/../origin.git" show-ref --verify --quiet refs/heads/release/1.1.0'
check "a failing version test keeps edits in version files" 'grep -q "my note" "$work/docs/FEATURES.md" && grep -q "unrelated edit" "$work/server/CopsAndRobbers/main.lua"'
check "a failing version test keeps staged edits" '[[ $(git -C "$work" diff --cached --name-only) == README.md ]]'

work="$(fixture hooks)"
head="$(git -C "$work" rev-parse HEAD)"
mkdir -p "$work/../hooks"
printf '#!/bin/sh\necho hooked >> README.md\nexit 1\n' > "$work/../hooks/post-checkout"
printf '#!/bin/sh\nexit 1\n' > "$work/../hooks/pre-commit"
chmod +x "$work/../hooks/post-checkout" "$work/../hooks/pre-commit"
git -C "$work" config core.hooksPath "$work/../hooks"
echo "staged note" >> "$work/README.md"
git -C "$work" add README.md
run_version "$work"
check "a release start runs no checkout or commit hooks" '[[ $(cat "$tmp/status") == 0 ]] && ! grep -q hooked "$work/README.md"'
check "a release start leaves the checkout on main" 'same_checkout "$work" "$head"'
check "a release start leaves staged work out of the release" '[[ $(git -C "$work" diff --name-only main origin/release/1.1.0 2>/dev/null || git -C "$work/../origin.git" diff --name-only main release/1.1.0) == $'"'"'client/lua/ge/extensions/copsAndRobbers.lua\nclient/mod_info/CopsAndRobbers/info.json\ndocs/FEATURES.md\nserver/CopsAndRobbers/main.lua'"'"' ]]'
check "a release start keeps staged work staged" '[[ $(git -C "$work" diff --cached --name-only) == README.md ]]'

work="$(fixture rejected)"
head="$(git -C "$work" rev-parse HEAD)"
printf '#!/bin/sh\nexit 1\n' > "$work/../origin.git/hooks/pre-receive"
chmod +x "$work/../origin.git/hooks/pre-receive"
run_version "$work"
check "a rejected push fails the release" '[[ $(cat "$tmp/status") != 0 ]]'
check "a rejected push leaves the checkout on main" 'same_checkout "$work" "$head"'

work="$(fixture exists)"
git -C "$work" push -q origin main:refs/heads/release/1.1.0
run_version "$work"
check "an existing release branch on origin is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "already exists on origin" "$tmp/out"'

work="$(fixture pr)"
GH_PR_STATUS=1 run_version "$work"
check "a failed PR keeps the pushed branch" 'git -C "$work/../origin.git" show-ref --verify --quiet refs/heads/release/1.1.0'
check "a failed PR prints a retry with title and body" 'grep -Fq -- "--title \"Release 1.1.0\" --body \"Merging this PR publishes the release. Deployment is separate.\"" "$tmp/out"'
check "a failed PR fails the release" '[[ $(cat "$tmp/status") == 1 ]]'

work="$(fixture ok)"
git -C "$work" commit -q --allow-empty -m "local only"
run_version "$work"
check "a release start succeeds" '[[ $(cat "$tmp/status") == 0 ]]'
check "a release starts from origin/main" '[[ $(git -C "$work/../origin.git" rev-parse release/1.1.0^) == $(git -C "$work/../origin.git" rev-parse main) ]]'
check "a release start commits the new version" '[[ $(git -C "$work/../origin.git" show release/1.1.0:server/CopsAndRobbers/main.lua) == "local VERSION = \"1.1.0\"" && $(git -C "$work/../origin.git" show release/1.1.0:docs/FEATURES.md) == "# Cops and Robbers 1.1.0: features" ]]'
work="$(fixture older)"
(cd "$work" && scripts/version.sh 0.9.0) > "$tmp/out" 2>&1 && echo 0 > "$tmp/status" || echo $? > "$tmp/status"
check "an older version is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "must be greater" "$tmp/out"'

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
for module in strikeSchedule groundingWeather; do
  check "the client zip holds the shared $module module" 'cmp -s <(unzip -p "$pkg/dist/release/CopsAndRobbers.zip" lua/ge/extensions/copsAndRobbers/$module.lua) "$pkg/server/CopsAndRobbers/cnr/$module.lua"'
done
umask_pkg="$tmp/package-umask"
mkdir -p "$umask_pkg"
(umask 077 && cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$umask_pkg/" && chmod -R go-rwx "$umask_pkg" && make -s -C "$umask_pkg" package SOURCE_DATE_EPOCH=1700000000 >/dev/null)
check "a different umask gives the same checksums" 'cmp -s "$tmp/first" "$umask_pkg/dist/release/SHA256SUMS"'
broken="$tmp/package-broken"
mkdir -p "$broken/bin"
cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$broken/"
printf '#!/bin/sh
exit 2
' > "$broken/bin/tar"
chmod +x "$broken/bin/tar"
check "a failing tar fails the package" '! PATH="$broken/bin:$PATH" make -s -C "$broken" package SOURCE_DATE_EPOCH=1700000000 >/dev/null 2>&1'

if ((failures)); then
  echo "$failures release checks failed"
  exit 1
fi
echo "all release checks passed"
