#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/scripts"
cp scripts/{board,board.conf} "$tmp/repo/scripts"
cd "$tmp/repo"
git init -qb main
git add scripts
git -c commit.gpgsign=false -c user.name=Tester -c user.email=tester@users.noreply.github.com commit -qm fixture
git -c commit.gpgsign=false -c user.name=Tester -c user.email=tester@users.noreply.github.com commit --allow-empty -qm head
export LOG="$tmp/log" PATH="$tmp:$PATH" LANE=Next ASSIGNED=- BLOCKERS=0
cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$LOG"
case "$*" in
  '--version') echo "gh version ${GH_VERSION:-2.106.0}" ;;
  'api users/'*) echo "${OWNER_TYPE:-Organization}" ;;
  'api graphql '*projectsV2*) printf '9\tSoftbody Arcade\n' ;;
  *'select(.name=="Effort")'*) printf 'SIZEFIELD\tSIZEOPTION\n' ;;
  'api graphql '*issueFields\(first*) printf 'FIELD\tOPTION\n' ;;
  'api graphql '*mutation*) echo '{}' ;;
  'api graphql '*projectV2*)
    status=$LANE
    if grep -q 'issue create --title Deferred' "$LOG"; then status=Inbox; fi
    if [[ -n ${DELAY_INBOX:-} ]]; then
      status=-
      if [[ -f $LOG.slept ]]; then status=Inbox; fi
    fi
    printf '%s\n' "softbody-arcade/cops-and-robbers|1|$status|${FIELD-High}|${SIZE-Low}|${TYPE-Feature}|v1|${TAGS:-}|$ASSIGNED|${PRS:--}|$BLOCKERS|Card"
    ;;
  'issue view '*--json\ number*) echo '{"number":1,"title":"Card","issueType":{"name":"Feature"},"milestone":{"title":"v1"},"parent":{"number":3},"subIssues":{"nodes":[{"number":4}]},"blockedBy":{"nodes":[{"number":5}]},"closedByPullRequestsReferences":[{"url":"https://example.com/pr"}],"body":"First\nSecond"}' ;;
  'issue view '*--json\ id*) echo "NODE-${3}" ;;
  'issue view '*--json\ parent*) echo "${PARENT-PARENT}" ;;
  'pr view '*headRefOid*) echo "${HEAD_SHA:?}" ;;
  'api --paginate '*'/comments '*@base64*) echo "${EXISTING_COMMENT:-}" ;;
  'api --paginate '*'/comments '*) echo "Staged for playtest (#1): ${STAGED:?}" ;;
  'pr comment '*) echo '{}' ;;
  'api user '*) echo me ;;
  'issue view '*--json\ body*) cat "$READY" ;;
  'api --paginate '*'/issues?state='*) echo "${EXISTING:-}" ;;
  'pr view '*--json\ body*) echo "${BODY:-}" ;;
  'issue edit '*--milestone\ 9.9.9*) echo 'milestone not found' >&2; exit 7 ;;
  'api repos/'*) echo 123 ;;
  'api -X '*|'issue edit '*|'label create '*|'issue close '*|'pr edit '*) echo '{}' ;;
  'issue create '*) echo https://github.com/softbody-arcade/cops-and-robbers/issues/1 ;;
  'issue comment '*|'project item-add '*|'project item-edit '*) echo '{}' ;;
  *) echo "Unexpected gh $*" >&2; exit 9 ;;
esac
STUB
cat > "$tmp/sleep" <<'STUB'
#!/usr/bin/env bash
[[ -n ${DELAY_INBOX:-} ]] || exit 99
touch "$LOG.slept"
STUB
chmod +x "$tmp/gh" "$tmp/sleep"
expect() {
  local code=$1 pattern=$2 rc=0
  shift 2
  : > "$LOG"
  scripts/board "$@" >"$tmp/out" 2>&1 || rc=$?
  if [[ $rc != "$code" ]] || ( [[ -n $pattern ]] && ! grep -Fq -- "$pattern" "$tmp/out" ); then
    cat "$tmp/out" >&2
    echo "Unexpected result ($rc) for $*" >&2
    exit 1
  fi
}
wrote() { grep -Fq -- "$1" "$LOG"; }
guard() {
  expect 1 "$@"
  [[ $(cat "$tmp/out") == "$1" ]]
  ! grep -Eq '^(api -X|api graphql .*query=mutation|label create|project item-|issue (edit|create|close|comment)|pr (edit|comment))' "$LOG" || exit 1
}
export READY="$tmp/ready"
sections=(Goal Why Scope 'Done when' 'Constraints and known facts' 'Open questions' Links)
for missing in "${sections[@]}"; do
  for section in "${sections[@]}"; do
    [[ $section == "$missing" ]] || echo "## $section"
  done > "$READY"
  guard "Missing sections: ## $missing" move 1 next
done
printf '## %s  \n' "${sections[@]}" > "$READY"
expect 0 '' move 1 next
wrote '--field Status --value Next'
LANE=Review guard 'Requires --staged SHA' move 1 playtest
BLOCKERS=1 guard 'Issue is blocked' start 1 build
ASSIGNED=someone guard 'Already assigned to someone' start 1 design
LANE=Backlog guard 'Start requires Next' start 1 build
guard 'Use start from Next to enter Design or Build' move 1 build
TYPE=- guard 'Set type and priority first' move 1 review
LANE=Playtest guard 'Only result may move a Playtest card' move 1 done
guard 'Result requires Playtest' result 1 pass
expect 2 'Unknown lane: elsewhere' move 1 elsewhere
expect 0 Card list
wrote 'items(first:50,after:$endCursor)'
wrote 'pageInfo{hasNextPage endCursor}'
expect 0 'Usage:' --help
expect 0 'Usage:' -h
GH_VERSION=2.105.9 expect 2 'requires gh' list
OWNER_TYPE=User expect 0 Card list --all
wrote 'user(login:$owner)'
LANE=Next guard 'Use start to leave Next for active work' move 1 review
LANE=Backlog guard 'Move ready work to Next first' move 1 review
LANE=Inbox guard 'Use triage to leave Inbox' move 1 next
TAGS=needs-decision expect 0 '[needs-decision]' waiting --all
LANE=Playtest expect 0 '[awaiting playtest]' waiting
LANE=- guard 'Issue #1 has no board status' start 1 build
expect 2 'Unexpected --staged' move 1 review --staged bad
expect 1 'did not enter Inbox' new feature High Card
! wrote '--field Status' || exit 1
DELAY_INBOX=1 expect 0 '' new feature High Card
[[ -f $LOG.slept ]]
order() { [[ $(sed -n 's/.*--field \([^ ]*\) --value .*/\1/p' "$LOG") == Status ]]; }
order
wrote 'issue create --title Card --type Feature'
LANE=Inbox expect 0 '' triage 1 bug Medium
wrote 'issue edit 1 --type Bug'
wrote 'setIssueFieldValue'
order
LANE=Inbox TYPE=- FIELD=- expect 0 '' check
[[ ! -s $tmp/out ]]
TYPE=- FIELD=- BLOCKERS=1 expect 0 'missing type' check
grep -q 'missing priority' "$tmp/out"
grep -q 'blocked in Next' "$tmp/out"
expect 0 '' start 1 design
wrote '--add-assignee me'
wrote '--field Status --value Design'
LANE=Design expect 0 '' move 1 build
wrote '--field Status --value Build'
expect 0 '' new in-game-check Card
wrote '--type In-game check'
! wrote 'setIssueFieldValue' || exit 1
guard 'Triage requires Inbox' triage 1 bug High
LANE=Inbox expect 0 '' new task High Medium 'Low'
wrote 'issue create --title Low --type Task'
wrote 'select(.name=="Effort")'
wrote 'select(.name=="Medium")'
wrote '-f field=SIZEFIELD -f option=SIZEOPTION'
expect 2 'Invalid effort: Urgent' new task High Urgent Card
! wrote 'issue create' || exit 1
LANE=Inbox expect 0 '' triage 1 task High Low
wrote '-f field=SIZEFIELD -f option=SIZEOPTION'
LANE=Inbox SIZE=- expect 0 '' triage 1 task Low
wrote 'select(.name=="Medium")'
LANE=Inbox expect 2 'Invalid effort: Urgent' triage 1 task High Urgent
! wrote 'issue edit' || exit 1
expect 0 '' effort 1 High
wrote 'select(.name=="Effort")'
wrote 'select(.name=="High")'
wrote '-f issue=NODE-1 -f field=SIZEFIELD -f option=SIZEOPTION'
expect 2 'Invalid effort: Urgent' effort 1 Urgent
! wrote 'setIssueFieldValue' || exit 1
SIZE=- guard 'Set effort first' move 1 review
LANE=Inbox SIZE=High expect 0 '' triage 1 task Low
wrote 'select(.name=="High")'
expect 0 '' new task High
wrote 'issue create --title High --type Task'
! wrote 'setIssueFieldValue' || exit 1
SIZE=- expect 0 '#1 missing effort' check
LANE=Inbox SIZE=- expect 0 '' check
[[ ! -s $tmp/out ]]
expect 0 'Card | Feature | High | Low |' list
wrote 'select(.field.name=="Effort")'
expect 0 '#1 Card' show 1
diff -u - "$tmp/out" <<'SHOW'
#1 Card
Type: Feature
Priority: High
Effort: Low
Lane: Next
Milestone: v1
Parent: #3
Sub-issues: #4
Blocked by: #5
Linked PRs: https://example.com/pr

First
Second
SHOW
wrote 'subIssues,blockedBy,closedByPullRequestsReferences'
expect 0 '' parent 1 2
wrote 'addSubIssue'
wrote '-f child=NODE-1 -f par=NODE-2'
PARENT='' guard 'Issue has no parent' unparent 1
expect 0 '' unparent 1
wrote 'removeSubIssue'
expect 0 '' milestone 1 1.2.3
wrote '--milestone 1.2.3'
expect 2 'milestone not found' milestone 1 9.9.9
[[ $(cat "$tmp/out") == 'milestone not found' ]]
expect 0 '' milestone 1 none
wrote '--remove-milestone'
expect 0 '' block 1 --by 2
wrote 'POST repos/softbody-arcade/cops-and-robbers/issues/1/dependencies/blocked_by -F issue_id=123'
expect 0 '' unblock 1 --by 2
wrote 'DELETE repos/softbody-arcade/cops-and-robbers/issues/1/dependencies/blocked_by/123'
expect 0 '' labels
[[ $(grep -c '^label create ' "$LOG") == 2 ]]
wrote 'label create needs-decision --repo softbody-arcade/cops-and-robbers --force'
wrote 'label create needs-playtest --repo softbody-arcade/cops-and-robbers --force'
printf 'Low: Observe.\nHigh: Keep it.\n' > "$tmp/note"
expect 0 '' decide 1 --file "$tmp/note"
wrote "**Decision ($(date +%F)):**"
export LANE=Review
export PRS=https://github.com/softbody-arcade/cops-and-robbers/pull/42
HEAD_SHA=$(git rev-parse HEAD)
export HEAD_SHA STAGED=$HEAD_SHA
PRS=- guard 'Requires one linked open PR in this repository' move 1 playtest --staged "$HEAD_SHA"
expect 2 'Expected full local commit SHA' move 1 playtest --staged bad
expect 2 'Expected full local commit SHA' move 1 playtest --staged 0000000000000000000000000000000000000000
TYPE='In-game check' expect 2 'Unexpected --staged' move 1 playtest --staged "$HEAD_SHA"
guard 'Staged SHA differs from PR head' move 1 playtest --staged "$(git rev-parse HEAD^)"
expect 0 '' move 1 playtest --staged "$HEAD_SHA"
wrote "Staged for playtest (#1): $HEAD_SHA"
STAGED=other LANE=Playtest guard 'PR head differs from staged SHA' result 1 pass
TYPE='In-game check' expect 0 '' move 1 playtest
wrote '--field Status --value Playtest'
export LANE=Playtest
expect 0 '' result 1 pass
wrote "pr comment 42 --body Playtest pass for #1 at $HEAD_SHA"
expect 0 '' result 1 fail
wrote 'pr edit 42'
wrote '--field Status --value Build'
BODY="- [ ] Playtest fail for #1 at $HEAD_SHA" expect 0 '' result 1 fail
! wrote 'pr edit 42' || exit 1
printf 'High: proper line\nmissing priority\n' > "$tmp/invalid"
expect 2 'Expected priority-prefixed check' result 1 defer --checks-file "$tmp/invalid"
! wrote 'issue create' || exit 1
expect 2 'Defer requires --checks-file F' result 1 defer
EXISTING=22 expect 0 '' result 1 defer --checks-file "$tmp/note"
! wrote 'issue create' || exit 1
expect 0 '' result 1 defer --checks-file "$tmp/note"
wrote '--type In-game check'
wrote '-f issue=NODE-1 -f field=FIELD -f option=OPTION'
wrote '- [ ] High: Keep it.'
wrote 'select(.name=="High")'
EXISTING_COMMENT=$(printf 'Playtest fail\n' | base64 -w0) EXISTING=22 TYPE='In-game check' expect 0 '' result 1 fail
! wrote 'issue create' || exit 1
! wrote 'issue comment' || exit 1
EXISTING_COMMENT=$(printf 'Playtest fail for #1 at %s\n' "$HEAD_SHA" | base64 -w0) expect 0 '' result 1 fail
! wrote 'pr comment' || exit 1
! wrote 'issue comment' || exit 1
for result in pass fail; do
  TYPE='In-game check' expect 0 '' result 1 "$result"
  wrote "issue close 1 --repo"
  wrote "issue comment 1 --body Playtest $result"
  if [[ $result == fail ]]; then wrote 'issue create --title Failed check:'; fi
done
TYPE='In-game check' guard 'Check already deferred' result 1 defer
other="$tmp/other"
git init -qb main "$other"
if (cd "$other" && "$tmp/repo/scripts/board" labels) >"$tmp/out" 2>&1; then exit 1; else rc=$?; fi
[[ $rc == 1 && $(cat "$tmp/out") == 'Run the board script from its own checkout' ]]
git switch -qc feature/test
guard 'Board writes require the main branch' labels
guard 'Board writes require the main branch' effort 1 High
git switch -q main
touch untracked
guard 'Board writes require a clean checkout' labels
