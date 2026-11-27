#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/scripts"
cp scripts/{board,board.conf} "$tmp/repo/scripts"
cd "$tmp/repo"
git init -qb develop
git add scripts
git -c commit.gpgsign=false -c user.name=Tester -c user.email=tester@users.noreply.github.com commit -qm fixture
git -c commit.gpgsign=false -c user.name=Tester -c user.email=tester@users.noreply.github.com commit --allow-empty -qm head
export LOG="$tmp/log" PATH="$tmp:$PATH" LANE=Next ASSIGNED=- BLOCKERS=0
cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LOG"
api_response() {
  if [[ ${1:-} == --jq ]]; then jq -r "$2"; else cat; fi
}
case "$*" in
  '--version') echo "gh version ${GH_VERSION:-2.106.0}" ;;
  'api users/'*) echo "${OWNER_TYPE:-Organization}" ;;
  'api graphql '*projectsV2*) printf '9\tSoftbody Arcade\n' ;;
  *'select(.name=="Effort")'*) printf 'SIZEFIELD\tSIZEOPTION\n' ;;
  'api graphql '*issueFields\(first*) printf 'FIELD\tOPTION\n' ;;
  'api graphql '*mutation*) echo '{}' ;;
  'api graphql '*latestRelease*)
    jq -n --arg tag "${RELEASE_TAG-v1.2.3}" --argjson draft "${DRAFT:-false}" --argjson pre "${PRERELEASE:-false}" '
      {data:{repository:{latestRelease:(if $tag == "" then null else {tagName:$tag,isDraft:$draft,isPrerelease:$pre} end)}}}' |
      jq -r "${!#}"
    ;;
  'api graphql '*releaseCards*)
    if [[ " $* " == *' --paginate '* ]]; then cat "$RELEASE_CARDS"; else head -n 1 "$RELEASE_CARDS"; fi
    ;;
  'api graphql '*openLinkedPrs*)
    [[ " $* " == *' --paginate '* && "$*" == *'nodes{url state}'* ]] || exit 9
    jq -n --arg prs "${PRS:-}" --arg merged "${MERGED_PRS:-}" '
      def links($urls; $state): [$urls | split(",")[] | select(. != "" and . != "-") | {url: ., state:$state}];
      {data:{repository:{issue:{closedByPullRequestsReferences:{
        nodes:(links($merged; "MERGED") + links($prs; "OPEN"))}}}}}' | jq -r "${!#}"
    ;;
  'api graphql '*includeClosedPrs:true*)
    case " $* " in
      *' issue=4 '*) nodes='[{"merged":false,"mergeCommit":null},{"merged":true,"mergeCommit":{"oid":"merged-sha"}}]' ;;
      *' issue=2 '*|*' issue=5 '*) nodes='[{"merged":true,"mergeCommit":{"oid":"unreleased-sha"}}]' ;;
      *' issue=6 '*) nodes='[{"merged":false,"mergeCommit":null}]' ;;
      *' issue=13 '*) nodes='[{"merged":true,"mergeCommit":{"oid":"merged-sha"}}]' ;;
      *' issue=15 '*) nodes='[{"merged":true,"mergeCommit":null}]' ;;
      *' issue=17 '*) nodes='[{"merged":true,"mergeCommit":{"oid":"missing-sha"}}]' ;;
      *' issue=18 '*) nodes='[{"merged":true,"mergeCommit":{"oid":"merged-sha"}},{"merged":true,"mergeCommit":{"oid":"unreleased-sha"}}]' ;;
      *) nodes='[]' ;;
    esac
    jq -nc --argjson nodes "$nodes" --arg args " $* " '
      ($nodes[:1], (select($args | contains(" --paginate ")) | $nodes[1:] | select(length > 0))) |
      {data:{repository:{issue:{closedByPullRequestsReferences:{nodes:.}}}}}' | jq -r "${!#}"
    ;;
  'api repos/'*'/compare/'*...missing-sha*) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  'api repos/'*'/compare/'*...merged-sha*) echo "${MERGED_COMPARISON:-identical}" ;;
  'api repos/'*'/compare/'*...unreleased-sha*)
    if [[ ${COMPARE_FAIL:-} ]]; then echo 'compare failed' >&2; exit 7; fi
    echo ahead
    ;;
  'api repos/'*'/compare/'*) echo "unexpected compare: $*" >&2; exit 9 ;;
  'api repos/'*'/releases/tags/v2.0.0'*)
    jq -n --argjson draft "${DRAFT:-false}" --argjson pre "${PRERELEASE:-false}" '{draft:$draft, prerelease:$pre}' |
      api_response "${@:3}"
    ;;
  'api repos/'*'/releases/tags/'*) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  'api graphql '*projectV2*)
    status=$LANE
    if grep -q 'issue create --title Deferred' "$LOG"; then status=Inbox; fi
    if [[ -n ${DELAY_INBOX:-} ]]; then
      status=-
      if [[ -f $LOG.slept ]]; then status=Inbox; fi
    fi
    jq -n --arg lane "$status" --arg priority "${FIELD-High}" --arg effort "${SIZE-Low}" \
      --arg type "${TYPE-Feature}" --arg state "${STATE:-OPEN}" --arg label "${TAGS:-}" \
      --arg assigned "$ASSIGNED" --arg prs "${PRS:-}" --arg merged "${MERGED_PRS:-}" --argjson blockers "$BLOCKERS" \
      --argjson count "${CARD_COUNT:-1}" --argjson others "${OTHER_COUNT:-0}" --arg owner "${OWNER_TYPE:-Organization}" '
      def nodes($values; key): {nodes: [$values | split(",")[] | select(. != "" and . != "-") | key]};
      {data: {($owner|ascii_downcase): {projectV2: {items: {nodes: [
        {content: null}, {content: {}},
        (range(1; $count+$others+1) as $n | {
          status: (if $lane == "-" then null else {name: $lane} end),
          content: {repository: {nameWithOwner: (if $n > $count then "softbody-arcade/other" else "softbody-arcade/cops-and-robbers" end)},
            number: $n, title: "Card", state: $state, milestone: {title: "v1"},
            issueType: (if $type == "-" then null else {name: $type} end),
            issueFieldValues: {nodes: [
              ({field: {name: "Priority"}, name: $priority}, {field: {name: "Effort"}, name: $effort})
              | select(.name != "-")]},
            labels: nodes($label; {name: .}), assignees: nodes($assigned; {login: .}),
            closedByPullRequestsReferences: {nodes: (nodes($merged; {url: .}).nodes + nodes($prs; {url: .}).nodes)[:20]},
            issueDependenciesSummary: {blockedBy: $blockers}}})]}}}}}' | jq -r "${!#}"
    ;;
  'issue view '*--json\ number*) echo '{"number":1,"title":"Card","issueType":{"name":"Feature"},"milestone":{"title":"v1"},"parent":{"number":3},"subIssues":{"nodes":[{"number":4}]},"blockedBy":{"nodes":[{"number":5}]},"closedByPullRequestsReferences":[{"url":"https://example.com/pr"}],"body":"First\nSecond"}' ;;
  'issue view '*--json\ id*) echo "NODE-${3}" ;;
  'issue view '*--json\ parent*) echo "${PARENT-PARENT}" ;;
  'pr view '*headRefOid*) echo "${HEAD_SHA:?}" ;;
  'api --paginate '*'/comments'*)
    jq -n --arg staged "${STAGED-}" --arg other "${OTHER_STAGED-}" \
      --arg comment "${EXISTING_COMMENT-}" --arg author "${COMMENT_AUTHOR:-me}" '
      [($staged | split(",")[] | select(length > 0) | {user:{login:"me"}, author_association:"OWNER", body:("Staged for playtest (#1): " + .)}),
       ($other | select(length > 0) | {user:{login:"peer"}, author_association:"MEMBER", body:("Staged for playtest (#1): " + .)}),
       ($comment | select(length > 0) | {user:{login:$author}, author_association:"COLLABORATOR", body:.})]' | api_response "${@:4}"
    ;;
  'pr comment '*) echo '{}' ;;
  'api user '*) echo me ;;
  'issue view '*--json\ body*) cat "$READY" ;;
  'api --paginate '*'/issues?state='*)
    jq -n --arg existing "${EXISTING:-}" --arg author "${CREATOR:-me}" --arg head "$HEAD_SHA" --arg prs "$PRS" '
      [select($existing != "") | {number: ($existing|tonumber), user:{login:$author}, author_association:"MEMBER"}
       + ({type:{name:"Bug"}, body:"Failed in-game check #1"},
          {type:{name:"In-game check"}, body:("Build: " + $head + " (" + $prs + "), work card #1")})]' | api_response "${@:4}"
    ;;
  'api repos/'*'/issues/'*)
    jq -n --arg id "${2##*/}" '{id:123} + (if $id == "33" then {pull_request:{url:"https://example.com/pr"}} else {} end)' | api_response "${@:3}"
    ;;
  'pr view '*--json\ body*) echo "${BODY:-}" ;;
  'issue edit '*--milestone\ 9.9.9*) echo 'milestone not found' >&2; exit 7 ;;
  'api repos/'*) echo 123 ;;
  'api -X '*|'issue edit '*|'label create '*|'issue close '*|'pr edit '*) echo '{}' ;;
  'issue create '*) echo https://github.com/softbody-arcade/cops-and-robbers/issues/1 ;;
  'project item-edit '*--value\ Done)
    if [[ ${MOVE_FAIL:-} ]]; then echo 'move failed' >&2; exit 7; fi
    echo '{}'
    ;;
  'project item-add '*/issues/22)
    if [[ ${ADD_FAIL:-} ]]; then echo 'add failed' >&2; exit 7; fi
    echo '{}'
    ;;
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
  ! grep -Eq '^(api -X|api graphql .*query=mutation|label create|project item-|issue (edit|create|close|reopen|comment)|pr (edit|comment))' "$LOG" || exit 1
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
LANE=Playtest guard 'Use board release to move Accepted cards to Done' move 1 done
LANE=Review expect 0 '' move 1 accepted
wrote '--field Status --value Accepted'
LANE=Accepted expect 0 '#1 Card' list accepted
grep -Fxq Accepted "$tmp/out"
STATE=CLOSED LANE=Done TYPE=- FIELD=- SIZE=- expect 0 '' check
[[ ! -s $tmp/out ]]
STATE=CLOSED LANE=Next CARD_COUNT=6 BLOCKERS=1 expect 0 '' check
[[ ! -s $tmp/out ]]
LANE=Accepted TYPE=- FIELD=- SIZE=- expect 0 '' check
[[ ! -s $tmp/out ]]
guard 'Result requires Playtest' result 1 pass
expect 2 'Unknown lane: elsewhere' move 1 elsewhere
expect 0 Card list next
expect 0 '' list backlog
[[ ! -s $tmp/out ]]
LANE=Paused expect 0 Other list
grep -Fxq Other "$tmp/out"
grep -Fq '#1 Card' "$tmp/out"
LANE=- expect 0 Other list
expect 0 Card list
wrote 'items(first:50,after:$endCursor)'
wrote 'pageInfo{hasNextPage endCursor}'
expect 0 'Usage:' --help
for route in 'Review or Playtest' 'reopen the issue' 're-stage' 'In-game check' 'Playtest to Backlog' 'move N done'; do
  grep -Fiq -- "$route" "$tmp/out"
done
expect 0 'Usage:' -h
GH_VERSION=2.105.9 expect 2 'requires gh' list
OWNER_TYPE=User expect 0 Card list --all
wrote 'user(login:$owner)'
LANE=Accepted STATE=CLOSED guard 'To rework merged work, reopen #1: the board returns it to Inbox, then triage it again' move 1 build
LANE=Accepted guard '#1 is already open: move it to Inbox with board move 1 inbox, then triage it again' move 1 build
LANE=Accepted expect 0 '' move 1 inbox
wrote '--field Status --value Inbox'
LANE=Inbox guard 'Use start from Next to enter Design or Build' move 1 build
LANE=Review expect 0 '' move 1 build
wrote '--field Status --value Build'
ASSIGNED=peer,me,another expect 0 '' start 1 build
wrote '--field Status --value Build'
ASSIGNED=peer,someone guard 'Already assigned to peer,someone' start 1 build
LANE=Next guard 'Use start to leave Next for active work' move 1 review
LANE=Backlog guard 'Move ready work to Next first' move 1 review
LANE=Inbox guard 'Use triage to leave Inbox' move 1 next
TAGS=needs-decision expect 0 '[needs-decision]' waiting --all
LANE=Playtest expect 0 '[awaiting playtest]' waiting
STATE=CLOSED LANE=Playtest TAGS=needs-decision expect 0 '' waiting
[[ ! -s $tmp/out ]]
CARD_COUNT=6 expect 1 'Next holds 6 cards' check
CARD_COUNT=5 OTHER_COUNT=1 expect 1 'Next holds 6 cards' check
CARD_COUNT=5 expect 0 '' check
[[ ! -s $tmp/out ]]
LANE=- guard 'Issue #1 has no board status' start 1 build
expect 2 'Unexpected --staged' move 1 review --staged bad
expect 1 'did not enter Inbox' new feature High Card
! wrote '--field Status' || exit 1
DELAY_INBOX=1 expect 0 '' new feature High Card
diff -u - "$tmp/out" <<'URL'
https://github.com/softbody-arcade/cops-and-robbers/issues/1
URL
[[ -f $LOG.slept ]]
order() { [[ $(sed -n 's/.*--field \([^ ]*\) --value .*/\1/p' "$LOG") == Status ]]; }
order
wrote 'issue create --title Card --type Feature'
LANE=Inbox expect 0 '' triage 1 bug Medium
[[ ! -s $tmp/out ]]
wrote 'issue edit 1 --type Bug'
wrote 'setIssueFieldValue'
order
LANE=Inbox TYPE=- FIELD=- expect 0 '' check
[[ ! -s $tmp/out ]]
TYPE=- FIELD=- BLOCKERS=1 expect 1 'missing type' check
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
for source in Backlog Next Design Build Review Playtest Accepted; do
  LANE=$source TYPE=- SIZE=- expect 0 '' triage 1 bug High
  wrote 'issue edit 1 --type Bug'
  wrote 'select(.name=="High")'
  wrote 'select(.name=="Medium")'
  ! wrote 'project item-edit' || exit 1
done
LANE=Done guard 'Cannot triage a Done card' triage 1 bug High
LANE=Inbox expect 0 '' new task High Medium 'Low'
wrote 'issue create --title Low --type Task'
wrote 'select(.name=="Effort")'
wrote 'select(.name=="Medium")'
wrote '-f field=SIZEFIELD -f option=SIZEOPTION'
expect 2 'Invalid type: Chore' new Chore Card
! wrote 'issue create' || exit 1
expect 0 '' new bug Card --body-file "$READY"
wrote "issue create --title Card --type Bug --body-file $READY"
expect 2 'Invalid effort: Urgent' new task High Urgent Card
! wrote 'issue create' || exit 1
LANE=Inbox expect 0 '' triage 1 task High Low
wrote '-f field=SIZEFIELD -f option=SIZEOPTION'
LANE=Inbox SIZE=- expect 0 '' triage 1 task Low
wrote 'select(.name=="Medium")'
LANE=Inbox expect 2 'Invalid effort: Urgent' triage 1 task High Urgent
! wrote 'issue edit' || exit 1
expect 0 '' priority 1 Urgent
[[ ! -s $tmp/out ]]
wrote 'select(.name=="Priority")'
wrote 'select(.name=="Urgent")'
wrote '-f issue=NODE-1 -f field=FIELD -f option=OPTION'
expect 2 'Invalid priority: Later' priority 1 Later
! wrote 'setIssueFieldValue' || exit 1
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
SIZE=- expect 1 '#1 missing effort' check
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
[[ $(grep -c '^label create ' "$LOG") == 5 ]]
wrote 'label create good first issue --repo softbody-arcade/cops-and-robbers --force --color 7057ff --description Good for newcomers'
wrote 'label create help wanted --repo softbody-arcade/cops-and-robbers --force --color 008672 --description Extra attention is needed'
wrote 'label create accessibility --repo softbody-arcade/cops-and-robbers --force --color f143ab --description Barrier affecting people with disabilities'
wrote 'label create needs-decision --repo softbody-arcade/cops-and-robbers --force --color D93F0B --description Waiting on a maintainer decision'
wrote 'label create needs-playtest --repo softbody-arcade/cops-and-robbers --force --color 5319E7 --description PR changes something a player sees, hears or feels'
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
merged_history=$(for id in {1..20}; do printf '%s/%s,' "${PRS%/*}" "$id"; done)
MERGED_PRS=$merged_history expect 0 '' move 1 playtest --staged "$HEAD_SHA"
wrote "pr comment 42 --body Staged for playtest (#1): $HEAD_SHA"
MERGED_PRS=$PRS PRS= guard 'Requires one linked open PR in this repository' move 1 playtest --staged "$HEAD_SHA"
recovery='Use board move 1 build for rework, or board move 1 playtest --staged <full sha> after staging the current linked PR head.'
STAGED="$HEAD_SHA,other" LANE=Playtest guard "PR head differs from staged SHA. $recovery" result 1 pass
STAGED="other,$HEAD_SHA" MERGED_PRS=${PRS%/*}/41 LANE=Playtest expect 0 '' result 1 defer --checks-file "$tmp/note"
wrote "Build: $HEAD_SHA ($PRS), work card #1"
STAGED=other LANE=Playtest guard "PR head differs from staged SHA. $recovery" result 1 pass
STAGED= LANE=Playtest guard "No staged comment from me. $recovery" result 1 pass
STAGED= OTHER_STAGED=$HEAD_SHA LANE=Playtest guard "No staged comment from me. $recovery" result 1 pass
OTHER_STAGED=other LANE=Playtest expect 0 '' result 1 pass
wrote "pr comment 42 --body Playtest pass"
for links in '' "$PRS,${PRS%/*}/43"; do
  PRS=$links LANE=Playtest guard "Requires one linked open PR in this repository. $recovery" result 1 pass
  PRS=$links LANE=Playtest expect 0 '' move 1 build
  wrote '--field Status --value Build'
done
LANE=Playtest expect 0 '' move 1 playtest --staged "$HEAD_SHA"
wrote "pr comment 42 --body Staged for playtest (#1): $HEAD_SHA"
LANE=Playtest TYPE='In-game check' expect 0 '' move 1 backlog
wrote '--field Status --value Backlog'
LANE=Playtest expect 1 'Playtest' move 1 backlog
for source in Inbox Backlog Next; do
  TYPE='In-game check' SIZE=- LANE=$source READY=/dev/null expect 0 '' move 1 playtest
  wrote '--field Status --value Playtest'
  wrote 'select(.name=="Medium")'
  ! wrote '--json body' || exit 1
  TYPE='In-game check' FIELD=- LANE=$source guard 'Set type and priority first' move 1 playtest
done
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
wrote '-f issue=NODE-22 -f field=SIZEFIELD -f option=SIZEOPTION'
wrote 'select(.name=="Medium")'
! wrote 'issue create' || exit 1
expect 0 '' result 1 defer --checks-file "$tmp/note"
wrote '--type In-game check'
wrote '-f issue=NODE-1 -f field=FIELD -f option=OPTION'
wrote '- [ ] High: Keep it.'
wrote 'select(.name=="High")'
EXISTING_COMMENT=$'Playtest fail\n' EXISTING=22 TYPE='In-game check' expect 0 '' result 1 fail
! wrote 'issue create' || exit 1
grep -Fxq -- 'project item-add 9 --owner softbody-arcade --url https://github.com/softbody-arcade/cops-and-robbers/issues/22' "$LOG" || exit 1
! wrote 'issue comment' || exit 1
ADD_FAIL=1 EXISTING_COMMENT=$'Playtest fail\n' EXISTING=22 TYPE='In-game check' expect 2 'add failed' result 1 fail
grep -Fxq -- 'project item-add 9 --owner softbody-arcade --url https://github.com/softbody-arcade/cops-and-robbers/issues/22' "$LOG" || exit 1
! wrote 'issue close' || exit 1
EXISTING_COMMENT="Playtest fail for #1 at $HEAD_SHA"$'\n' expect 0 '' result 1 fail
! wrote 'pr comment' || exit 1
! wrote 'issue comment' || exit 1
CREATOR=peer EXISTING=22 COMMENT_AUTHOR=peer EXISTING_COMMENT=$'Playtest fail\n' TYPE='In-game check' expect 0 '' result 1 fail
wrote 'issue create --title Failed check:'
wrote 'issue comment 1 --body Playtest fail'
for result in pass fail; do
  TYPE='In-game check' expect 0 '' result 1 "$result"
  wrote "issue close 1 --repo"
  wrote "issue comment 1 --body Playtest $result"
  if [[ $result == fail ]]; then wrote 'issue create --title Failed check:'; fi
done
TYPE='In-game check' guard 'Check already deferred' result 1 defer
guard '#33 is a pull request' show 33
guard '#33 is a pull request' decide 33 --file "$tmp/note"
guard '#33 is a pull request' effort 33 Low
guard '#33 is a pull request' priority 33 Low
guard '#33 is a pull request' milestone 33 none
guard '#33 is a pull request' triage 33 Bug High
guard '#33 is a pull request' start 33 build
guard '#33 is a pull request' move 33 review
guard '#33 is a pull request' result 33 pass
guard '#33 is a pull request' parent 33 1
guard '#33 is a pull request' unparent 33
guard '#33 is a pull request' block 33 --by 1
guard '#33 is a pull request' unblock 33 --by 1
guard '#33 is a pull request' parent 1 33
guard '#33 is a pull request' block 1 --by 33
guard '#33 is a pull request' unblock 1 --by 33
export RELEASE_CARDS="$tmp/release-cards"
jq -nc '
  def card($number; $lane; $reason; $type):
    {id: "ITEM-\($number)", updatedAt: "2000-01-01T00:00:00Z", isArchived: false, status: {name: $lane},
     content: {number: $number, state: "CLOSED", stateReason: $reason, issueType: {name: $type},
       updatedAt: "2000-01-01T00:00:00Z", repository: {nameWithOwner: "softbody-arcade/cops-and-robbers"}}};
  {data:{organization:{projectV2:{id:"PROJECT",items:{nodes:[
    card(1; "Accepted"; "NOT_PLANNED"; "Feature"),
    card(2; "Accepted"; "COMPLETED"; "In-game check"),
    card(3; "Accepted"; "COMPLETED"; "Task"),
    card(17; "Accepted"; "COMPLETED"; "Task"),
    card(4; "Accepted"; "COMPLETED"; "Bug"),
    card(5; "Accepted"; "COMPLETED"; "Bug"),
    card(6; "Accepted"; "COMPLETED"; "Task"),
    (card(7; "Done"; "COMPLETED"; "Task") | .updatedAt = (now - 14*86400 - 1 | todateiso8601) | .content.updatedAt = .updatedAt),
    (card(8; "Done"; "COMPLETED"; "Task") | .updatedAt = (now - 13*86400 | todateiso8601)),
    (card(9; "Done"; "COMPLETED"; "Task") | .content.updatedAt = (now - 13*86400 | todateiso8601)),
    (card(10; "Accepted"; "DUPLICATE"; "Task") | .content.repository.nameWithOwner = "softbody-arcade/other"),
    card(11; "Accepted"; "DUPLICATE"; "Task"),
    (card(12; "Done"; "COMPLETED"; "Task") | .isArchived = true),
    (card(13; "Accepted"; null; "Task") | .content.state = "OPEN"),
    (card(14; "Done"; null; "Task") | .content.state = "OPEN"),
    card(15; "Accepted"; "COMPLETED"; "Task"),
    card(16; "Accepted"; null; "Task"),
    card(18; "Accepted"; "COMPLETED"; "Task"),
    {id:"DRAFT", status:{name:"Accepted"}, content:{}},
    {id:"REDACTED", status:{name:"Accepted"}, content:null}
  ]}}}}} | (.data.organization.projectV2.items.nodes |= .[:4]), (.data.organization.projectV2.items.nodes |= .[4:])' > "$RELEASE_CARDS"
expect 0 '#1 moved to Done' release
diff -u - "$tmp/out" <<'RELEASE'
#1 moved to Done
#2 moved to Done
#3 moved to Done
#17 waiting for a release
#4 moved to Done
#5 waiting for a release
#6 has no merged PR
#7 archived
#11 moved to Done
#13 is still open
#15 waiting for a release
#16 has no completion reason or linked PR
#18 waiting for a release
RELEASE
cp "$tmp/out" "$tmp/release-output"
[[ $(grep -c 'project item-edit .* --field Status --value Done' "$LOG") == 5 ]]
wrote 'item=ITEM-7'
[[ $(grep -c 'archiveProjectV2Item' "$LOG") == 1 ]]
wrote '/compare/v1.2.3...merged-sha'
expect 0 '#1 would move to Done' release --dry-run
sed -e 's/ moved to Done$/ would move to Done/' -e 's/ archived$/ would archive/' "$tmp/release-output" > "$tmp/expected-dry-run"
diff -u "$tmp/expected-dry-run" "$tmp/out"
! wrote 'project item-edit' || exit 1
! wrote 'archiveProjectV2Item' || exit 1
MERGED_COMPARISON=behind expect 0 '#4 would move to Done' release v2.0.0 --dry-run
wrote '/compare/v2.0.0...merged-sha'
! wrote 'latestRelease' || exit 1
expect 2 'HTTP 404' release v9.9.9
! wrote 'project item-edit' || exit 1
for flag in DRAFT PRERELEASE; do
  export "$flag=true"
  expect 1 'draft or prerelease' release v2.0.0
  ! wrote 'project item-edit' || exit 1
  ! wrote 'archiveProjectV2Item' || exit 1
  expect 0 'No published release yet' release --dry-run
  grep -qx '#4 waiting for a release' "$tmp/out"
  ! wrote '/compare/' || exit 1
  unset "$flag"
done
RELEASE_TAG= expect 0 'No published release yet' release --dry-run
grep -qx '#1 would move to Done' "$tmp/out"
grep -qx '#4 waiting for a release' "$tmp/out"
! wrote '/compare/' || exit 1
COMPARE_FAIL=1 expect 2 'compare failed' release
! wrote 'project item-edit' || exit 1
! wrote 'archiveProjectV2Item' || exit 1
MOVE_FAIL=1 expect 2 'move failed' release
[[ $(grep -c '^project item-edit ' "$LOG") == 1 ]]
! wrote 'archiveProjectV2Item' || exit 1
other="$tmp/other"
git init -qb develop "$other"
if (cd "$other" && "$tmp/repo/scripts/board" labels) >"$tmp/out" 2>&1; then exit 1; else rc=$?; fi
[[ $rc == 1 && $(cat "$tmp/out") == 'Run the board script from its own checkout' ]]
git switch -qc feature/test
guard 'Board writes require the develop branch' labels
guard 'Board writes require the develop branch' release
expect 0 '#1 would move to Done' release --dry-run
guard 'Board writes require the develop branch' effort 1 High
guard 'Board writes require the develop branch' priority 1 Low
git switch -q develop
touch untracked
expect 0 '' labels
echo >> scripts/board
guard 'Board writes require a clean checkout' labels
guard 'Board writes require a clean checkout' release
