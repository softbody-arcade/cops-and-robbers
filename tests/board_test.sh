#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LOG="$tmp/log" PATH="$tmp:$PATH" LANE=Next ASSIGNED=- BLOCKERS=0
cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$LOG"
case "$*" in
  'api graphql '*projectsV2*) printf '9\tSoftbody Arcade\n' ;;
  'api graphql '*projectV2*) printf '%s\n' "softbody-arcade/cops-and-robbers|1|$LANE|p1|idea,p1|$ASSIGNED|${PRS:--}|$BLOCKERS|Card" ;;
  'pr view '*headRefOid*) echo "${HEAD_SHA:?}" ;;
  'api --paginate '*'/comments '*) echo "Staged for playtest (#1): ${STAGED:?}" ;;
  'pr comment '*) echo '{}' ;;
  'api user '*) echo me ;;
  'issue view '*--json\ body*) echo '## Goal' ;;
  'issue create '*) echo https://github.com/softbody-arcade/cops-and-robbers/issues/1 ;;
  'issue comment '*|'project item-add '*|'project item-edit '*) echo '{}' ;;
  *) echo "Unexpected gh $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$tmp/gh"
expect() {
  local code=$1 pattern=$2 rc=0
  shift 2
  scripts/board "$@" >"$tmp/out" 2>&1 || rc=$?
  if [[ $rc != "$code" ]] || ! grep -Fqi "$pattern" "$tmp/out"; then
    cat "$tmp/out" >&2
    echo "Unexpected result ($rc) for $*" >&2
    exit 1
  fi
}
expect 1 '## Why' move 1 next
expect 1 'staged' move 1 playtest
BLOCKERS=1 expect 1 blocked start 1 build
ASSIGNED=someone expect 1 assigned start 1 design
LANE=Playtest expect 1 result move 1 'done'
expect 2 lane move 1 elsewhere
expect 0 Card list
grep -E 'api graphql .*--paginate' "$LOG" >/dev/null
# shellcheck disable=SC2016
grep -F 'items(first:50,after:$endCursor)' "$LOG" >/dev/null
grep -F 'pageInfo{hasNextPage endCursor}' "$LOG" >/dev/null
LANE=Inbox scripts/board new idea p1 Card
grep -F -- '--field Status --value Backlog' "$LOG" >/dev/null
grep -F -- '--field Priority --value p1' "$LOG" >/dev/null
echo 'Keep it.' > "$tmp/note"
scripts/board decide 1 --file "$tmp/note"
grep -F "**Decision ($(date +%F)):**" "$LOG" >/dev/null
grep -F 'Keep it.' "$LOG" >/dev/null
export PRS=https://github.com/softbody-arcade/cops-and-robbers/pull/42
export HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export STAGED=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
LANE=Playtest expect 1 'head differs' result 1 pass
if grep -q '^pr comment ' "$LOG"; then exit 1; fi
STAGED=$HEAD_SHA LANE=Playtest scripts/board result 1 pass
grep -F "pr comment 42 --body Playtest pass for #1 at $HEAD_SHA" "$LOG" >/dev/null
echo 'Board tests passed'
