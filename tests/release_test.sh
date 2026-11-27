#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@users.noreply.github.com
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@users.noreply.github.com
failures=0
at=@

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
  'pr create') echo "$*" >> "${GH_LOG:-/dev/null}"; all=" $* "; [[ "${all,,}" == *" --repo test/repo "* ]] || exit 3; exit "${GH_PR_STATUS:-0}" ;;
esac
exit 1
STUB
cat > "$tmp/bin/fake-lua" <<'STUB'
#!/usr/bin/env bash
[[ -z ${EDIT_DURING_TEST:-} ]] || echo "unrelated edit" >> "$EDIT_DURING_TEST"
[[ -z ${RACE_ORIGIN:-} ]] || git -C "$RACE_ORIGIN" branch release/1.1.0 main
exit "${LUA_STATUS:-0}"
STUB
cat > "$tmp/bin/fake-ssh" <<'STUB'
#!/usr/bin/env bash
root="$1"
shift
cmd="${*: -1}"
cmd="${cmd/\'\//\'}"
cd "$root" && eval "git ${cmd#git-}"
STUB
chmod +x "$tmp/bin/gh" "$tmp/bin/fake-lua" "$tmp/bin/fake-ssh"
export PATH="$tmp/bin:$PATH" VERSION_LUA=fake-lua GH_LOG="$tmp/gh.log"

fixture() {
  local dir="$tmp/$1"
  git init -q --bare "$dir/origin.git"
  mkdir -p "$dir/root/test" "$dir/root/Test"
  ln -s "$dir/origin.git" "$dir/root/test/repo.git"
  ln -s "$dir/origin.git" "$dir/root/Test/Repo.git"
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
    git remote add origin "git${at}github.com:test/repo.git"
    git config core.sshCommand "$(printf '%q %q' "$tmp/bin/fake-ssh" "$dir/root")"
    git config ssh.variant ssh
    git push -q origin main main:develop
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
check "a failed PR prints a retry with repo, title and body" 'grep -Fq -- "--repo test/repo --base main --head release/1.1.0 --title \"Release 1.1.0\" --body \"Merging this PR publishes the release. Deployment is separate.\"" "$tmp/out"'
check "a failed PR fails the release" '[[ $(cat "$tmp/status") == 1 ]]'

work="$(fixture ok)"
git -C "$work" commit -q --allow-empty -m "local only"
run_version "$work"
check "a release start succeeds" '[[ $(cat "$tmp/status") == 0 ]]'
check "a release starts from origin/develop" '[[ $(git -C "$work/../origin.git" rev-parse release/1.1.0^) == $(git -C "$work/../origin.git" rev-parse develop) ]]'
check "a release start commits the new version" '[[ $(git -C "$work/../origin.git" show release/1.1.0:server/CopsAndRobbers/main.lua) == "local VERSION = \"1.1.0\"" && $(git -C "$work/../origin.git" show release/1.1.0:docs/FEATURES.md) == "# Cops and Robbers 1.1.0: features" ]]'
work="$(fixture race)"
racer="$(git -C "$work/../origin.git" rev-parse main)"
RACE_ORIGIN="$work/../origin.git" run_version "$work"
check "a release branch created during the run is not moved" '[[ $(cat "$tmp/status") != 0 && $(git -C "$work/../origin.git" rev-parse release/1.1.0) == "$racer" ]]'

work="$(fixture lookup)"
mkdir -p "$tmp/flaky"
printf '#!/usr/bin/env bash\n[[ $1 == ls-remote ]] && exit 128\nexec %q "$@"\n' "$(command -v git)" > "$tmp/flaky/git"
chmod +x "$tmp/flaky/git"
PATH="$tmp/flaky:$PATH" run_version "$work"
check "a failed branch lookup stops the release" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "could not check" "$tmp/out" && ! git -C "$work/../origin.git" show-ref --verify --quiet refs/heads/release/1.1.0'

work="$(fixture signed)"
ssh-keygen -q -t ed25519 -N "" -f "$tmp/signing-key"
git -C "$work" config gpg.format ssh
git -C "$work" config user.signingkey "$tmp/signing-key.pub"
git -C "$work" config commit.gpgsign true
run_version "$work"
check "a release commit is signed when signing is on" '[[ $(cat "$tmp/status") == 0 ]] && git -C "$work/../origin.git" cat-file commit release/1.1.0 | grep -q "^gpgsig "'

work="$(fixture shadow)"
git -C "$work" commit -q --allow-empty -m "local only"
git -C "$work" branch origin/develop
run_version "$work"
check "a local branch named origin/develop is not the release base" '[[ $(git -C "$work/../origin.git" rev-parse release/1.1.0^) == $(git -C "$work/../origin.git" rev-parse develop) ]]'

work="$(fixture not-github)"
git -C "$work" remote set-url origin "$work/../origin.git"
run_version "$work"
check "an origin outside GitHub is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "must fetch from and push to a GitHub repository" "$tmp/out"'

work="$(fixture ssh443)"
git -C "$work" remote set-url origin "ssh://git${at}ssh.github.com:443/test/repo.git"
run_version "$work"
check "GitHub SSH over port 443 is accepted" '[[ $(cat "$tmp/status") == 0 ]]'

work="$(fixture mirror)"
git -C "$work" remote set-url origin https://mirror.example.test/github.com/test/repo.git
run_version "$work"
check "a non-GitHub host is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "must fetch from and push to a GitHub repository" "$tmp/out"'

work="$(fixture secret)"
git -C "$work" remote set-url origin "https://user:hunter2${at}github.com/test/"
run_version "$work"
check "a refused origin never prints its credentials" '[[ $(cat "$tmp/status") == 1 ]] && ! grep -q hunter2 "$tmp/out"'

work="$(fixture split)"
git -C "$work" config remote.origin.pushurl https://github.com/other/repo.git
run_version "$work"
check "an origin that pushes to another repository is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "more than one repository" "$tmp/out" && ! git -C "$work/../origin.git" show-ref --verify --quiet refs/heads/release/1.1.0'

work="$(fixture rewrite)"
git init -q --bare "$work/../elsewhere.git"
git -C "$work" config url."$work/../elsewhere.git/".pushInsteadOf "git${at}github.com:"
run_version "$work"
check "a push URL rewritten away from GitHub is refused" '[[ $(cat "$tmp/status") == 1 ]] && ! git -C "$work/../elsewhere.git" show-ref --quiet'

work="$(fixture case)"
git -C "$work" config remote.origin.pushurl "git${at}github.com:Test/Repo.git"
run_version "$work"
check "repository names compare without case" '[[ $(cat "$tmp/status") == 0 ]]'

work="$(fixture ahead)"
git -C "$work" commit -q --allow-empty -m "ticket on develop"
git -C "$work" push -q origin HEAD:develop
git -C "$work" reset -q --hard HEAD^
run_version "$work"
check "a release branches from develop, not main" '[[ $(cat "$tmp/status") == 0 && $(git -C "$work/../origin.git" rev-parse release/1.1.0^) == $(git -C "$work/../origin.git" rev-parse develop) && $(git -C "$work/../origin.git" rev-parse develop) != $(git -C "$work/../origin.git" rev-parse main) ]]'

work="$(fixture hotfix)"
git -C "$work" commit -q --allow-empty -m "ticket on develop"
git -C "$work" push -q origin HEAD:develop
git -C "$work" reset -q --hard HEAD^
RELEASE_FROM=main run_version "$work"
check "a hotfix release with FROM=main branches from main" '[[ $(cat "$tmp/status") == 0 && $(git -C "$work/../origin.git" rev-parse release/1.1.0^) == $(git -C "$work/../origin.git" rev-parse main) ]]'
check "a release PR always targets main" 'grep -q "^pr create.*--base main" "$tmp/gh.log"'

work="$(fixture badfrom)"
RELEASE_FROM=feature run_version "$work"
check "an unknown FROM is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "FROM must be develop or main" "$tmp/out"'

work="$(fixture older)"
(cd "$work" && scripts/version.sh 0.9.0) > "$tmp/out" 2>&1 && echo 0 > "$tmp/status" || echo $? > "$tmp/status"
check "an older version is refused" '[[ $(cat "$tmp/status") == 1 ]] && grep -q "must be greater" "$tmp/out"'

pkg="$tmp/package"
mkdir -p "$pkg"
cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$pkg/"
make -s -C "$pkg" package >/dev/null
cp "$pkg/dist/release/SHA256SUMS" "$tmp/first"
find "$pkg/client" "$pkg/server" -exec touch -h -d '2001-02-03 04:05:06' {} +
TZ=Asia/Tokyo SOURCE_DATE_EPOCH=1 make -s -C "$pkg" package >/dev/null
check "repackaging the same source gives the same checksums" 'cmp -s "$tmp/first" "$pkg/dist/release/SHA256SUMS"'
check "packaging leaves file times in dist/Server alone" '[[ $(stat -c %Y "$pkg/dist/Server/CopsAndRobbers/main.lua") == $(stat -c %Y "$pkg/server/CopsAndRobbers/main.lua") ]]'
check "the client zip holds the mod folders" 'unzip -Z1 "$pkg/dist/release/CopsAndRobbers.zip" | grep -x "mod_info/CopsAndRobbers/info.json" >/dev/null'
for module in strikeSchedule groundingWeather; do
  check "the client zip holds the shared $module module" 'cmp -s <(unzip -p "$pkg/dist/release/CopsAndRobbers.zip" lua/ge/extensions/copsAndRobbers/$module.lua) "$pkg/server/CopsAndRobbers/cnr/$module.lua"'
done
umask_pkg="$tmp/package-umask"
mkdir -p "$umask_pkg"
(umask 077 && cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$umask_pkg/" && chmod -R go-rwx "$umask_pkg" && make -s -C "$umask_pkg" package >/dev/null)
check "a different umask gives the same checksums" 'cmp -s "$tmp/first" "$umask_pkg/dist/release/SHA256SUMS"'
setgid_pkg="$tmp/package-setgid"
mkdir -p "$setgid_pkg"
chmod g+s "$setgid_pkg"
cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$setgid_pkg/"
make -s -C "$setgid_pkg" package >/dev/null
check "a setgid build folder gives the same checksums" 'cmp -s "$tmp/first" "$setgid_pkg/dist/release/SHA256SUMS"'
broken="$tmp/package-broken"
mkdir -p "$broken/bin"
cp -r "$ROOT/Makefile" "$ROOT/client" "$ROOT/server" "$broken/"
printf '#!/bin/sh
exit 2
' > "$broken/bin/tar"
chmod +x "$broken/bin/tar"
check "a failing tar fails the package" '! PATH="$broken/bin:$PATH" make -s -C "$broken" package >/dev/null 2>&1'

pub="$tmp/publish"
mkdir -p "$pub/bin" "$pub/assets"
printf zip > "$pub/assets/CopsAndRobbers.zip"
printf tar > "$pub/assets/CopsAndRobbers-server.tar.gz"
printf sums > "$pub/assets/SHA256SUMS"
cat > "$pub/bin/gh" <<'STUB'
#!/usr/bin/env bash
state="$PUB_STATE"
echo "$*" >> "$state/log"
case "$*" in
  "api repos/test/repo/git/matching-refs/"*) [[ -z ${FAIL_LOOKUP:-}${FAIL_TAG_LOOKUP:-} ]] || exit 1; ref="refs/${2#repos/test/repo/git/matching-refs/}"; [[ ! -f $state/$ref ]] || echo "commit $(cat "$state/$ref")" ;;
  "api --paginate repos/test/repo/releases "*) [[ -z ${FAIL_LOOKUP:-} ]] || exit 1; [[ ! -d $state/release ]] || echo "$(cat "$state/draft") $(cat "$state/pre")" ;;
  "api --method POST repos/test/repo/git/refs"*)
    for a in "$@"; do case $a in ref=*) ref="${a#ref=}" ;; sha=*) sha="${a#sha=}" ;; esac; done
    [[ ! -f $state/$ref ]] || exit 1
    mkdir -p "$state/$(dirname "$ref")"; echo "$sha" > "$state/$ref" ;;
  "release view "*"assets"*) ls "$state/release" ;;
  "release download "*) cp "$state/release/$5" "$7/" ;;
  "release upload "*) cp "$4" "$state/release/" ;;
  "release edit "*) echo false > "$state/draft" ;;
  "release create "*) [[ " $* " == *" --verify-tag "* && -f $state/refs/tags/$3 ]] || exit 1; mkdir -p "$state/release"; echo false > "$state/draft"; echo false > "$state/pre"; for a in "$@"; do [[ -f $a ]] && cp "$a" "$state/release/"; done; true ;;
  "api --paginate repos/test/repo/milestones"*) echo 7 ;;
  "api --method PATCH repos/test/repo/milestones/7"*) touch "$state/milestone-closed" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$pub/bin/gh"
sha=0123456789abcdef0123456789abcdef01234567
other=fedcba9876543210fedcba9876543210fedcba98
publish() {
  set +e
  PUB_STATE="$1" GH_REPO=test/repo PATH="$pub/bin:$PATH" "$ROOT/scripts/publish-release" 1.1.0 "${2:-$sha}" "$pub/assets" > "$tmp/out" 2>&1
  echo $? > "$tmp/status"
  set -e
}
state="$pub/new"; mkdir -p "$state"
publish "$state"
check "publish tags the release commit" '[[ $(cat "$tmp/status") == 0 && $(cat "$state/refs/tags/v1.1.0") == "$sha" ]]'
check "publish uploads all three assets" '[[ $(ls "$state/release" | wc -l) == 3 ]]'
check "publish closes the milestone" '[[ -f $state/milestone-closed ]]'

state="$pub/moved"; mkdir -p "$state"; mkdir -p "$state/refs/tags"; echo "$other" > "$state/refs/tags/v1.1.0"
publish "$state"
check "publish refuses a tag at another commit" '[[ $(cat "$tmp/status") == 1 && ! -d $state/release ]] && grep -q "already points at" "$tmp/out"'

state="$pub/pre"; mkdir -p "$state/release"; mkdir -p "$state/refs/tags"; echo "$sha" > "$state/refs/tags/v1.1.0"; echo true > "$state/draft"; echo true > "$state/pre"
publish "$state"
check "publish refuses a prerelease draft" '[[ $(cat "$tmp/status") == 1 && $(cat "$state/draft") == true && ! -f $state/milestone-closed ]] && [[ -z $(ls "$state/release") ]]'

state="$pub/pre-untagged"; mkdir -p "$state/release"; echo true > "$state/draft"; echo true > "$state/pre"
publish "$state"
check "publish refuses a prerelease before creating its tag" '[[ $(cat "$tmp/status") == 1 && ! -e $state/refs/tags/v1.1.0 ]]'

state="$pub/outage"; mkdir -p "$state/release"; echo true > "$state/draft"; echo true > "$state/pre"
FAIL_LOOKUP=1 publish "$state"
check "publish creates no tag when the release lookup fails" '[[ $(cat "$tmp/status") == 1 && ! -e $state/refs/tags/v1.1.0 ]]'

state="$pub/tag-outage"; mkdir -p "$state"
FAIL_TAG_LOOKUP=1 publish "$state"
check "publish writes nothing when the tag lookup fails" '[[ $(cat "$tmp/status") == 1 && ! -e $state/refs/tags/v1.1.0 && ! -d $state/release ]] && ! grep -q -- "--method POST" "$state/log"'

state="$pub/differs"; mkdir -p "$state/release"; mkdir -p "$state/refs/tags"; echo "$sha" > "$state/refs/tags/v1.1.0"; echo true > "$state/draft"; echo false > "$state/pre"; printf other > "$state/release/CopsAndRobbers.zip"
publish "$state"
check "publish refuses a retained asset that differs" '[[ $(cat "$tmp/status") == 1 && ! -f $state/release/SHA256SUMS && $(cat "$state/draft") == true ]]'

state="$pub/partial"; mkdir -p "$state/release"; mkdir -p "$state/refs/tags"; echo "$sha" > "$state/refs/tags/v1.1.0"; echo true > "$state/draft"; echo false > "$state/pre"; printf zip > "$state/release/CopsAndRobbers.zip"
publish "$state"
check "publish completes a partial draft" '[[ $(cat "$tmp/status") == 0 && $(ls "$state/release" | wc -l) == 3 && $(cat "$state/draft") == false && -f $state/milestone-closed ]]'

if ((failures)); then
  echo "$failures release checks failed"
  exit 1
fi
echo "all release checks passed"
