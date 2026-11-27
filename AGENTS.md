# Cops and Robbers: agent rules

This file is the single rule set for every contributor and every coding agent, whatever the provider. `CLAUDE.md` only includes it. The rules never require a harness-specific tool. "The maintainer" means the repo owner, ReinderN.

The repo is `softbody-arcade/cops-and-robbers`, in the `softbody-arcade` organization for BeamNG multiplayer minigames.

## Tickets are the ledger

GitHub Issues and the organization board **Softbody Arcade** (project 1) record all work: ideas, bugs, in-game checks, and what is in progress. An issue is the single place that says what happened to a piece of work and why. Use what GitHub provides natively; never mirror the same fact twice.

- **Type** (the org's issue types): `Feature` for ideas and new functionality, `Bug`, `Task` for maintenance and tooling, `In-game check` for something to verify in game. Every issue outside Inbox has a type, a priority and an effort.
- **Priority** (the org's issue field): `Urgent`, `High`, `Medium` or `Low`. Rank by player impact, then host or panel problems, then cosmetics, then maintainer-only work. Every issue outside Inbox has one.
- **Effort** (the org's issue field): `High`, `Medium` or `Low`, a rough size set at triage and refined in Design. Together with Priority it ranks the work: the board's **Quick wins** view lists open Urgent or High issues with Low effort, which are good picks for Next and for contributors.
- **Milestone**: the release version an issue is targeted at, named `x.y.z`. The maintainer assigns it when committing to a release. A release ships when its milestone's issues are closed or moved on, and `release.yml` closes the milestone.
- **Parent and sub-issues** give the structure: a large feature is a parent with its parts as sub-issues, and the issues folded into a fix batch become sub-issues of the batch's ticket. Progress rolls up on the parent.
- **Blocked by / blocking** (issue dependencies) records order: `scripts/board block <n> --by <m>`. Never use a label or prose for it.
- **Labels** remain only where nothing native exists: `needs-decision` while an issue waits on the maintainer, `needs-playtest` on a PR whose change a player would see, hear or feel, and `good first issue` / `help wanted` for contributors, and `accessibility` for barriers affecting players with disabilities. Close duplicates and dropped work with GitHub's "duplicate" and "not planned" close reasons.
- **Development.** Branches and PRs are linked through the issue's native Development section: create the branch with `gh issue develop <n> --name feature/<topic> --base main` (or `fixes/<topic>`), and the PR body says `Fixes #n`.
- **Links.** A `## Links` section in each ticket lists only what GitHub cannot link natively: its spec, plan and decision records in the repo, and outside references. Related issues use parent/sub-issues and blocked-by. Whoever writes a spec or plan links it the same day.
- **Decisions.** Every maintainer decision becomes a comment on the ticket: `**Decision (YYYY-MM-DD):**` followed by what was decided, the options and the reason (`scripts/board decide`). An agent posts decisions made in a chat before its turn ends. Nothing is decided only in chat.
- **Events.** Playtest results, deferred review findings (as links to new issues), deploys and scope changes also go on the ticket.
- **Findings.** A finding about a branch's own unmerged code goes in its PR and is fixed or filed before merge. Anything else found in passing becomes a new issue right away, including deferred review findings, with the affected file and the observable problem.
- **Claiming.** A PR lists every issue it handles as `Fixes #n`.

### Lanes

| Lane | Holds | Leaves when |
|---|---|---|
| Inbox | New, untriaged issues | `board triage <n> <type> <priority> [effort]` sets type, priority and effort, moving it to Backlog |
| Backlog | Triaged; a simple ticket is fine | The maintainer picks it for Next |
| Next | At most 5, top first, each meeting the definition of ready | `board start <n> design\|build` |
| Design | Brainstorm, spec and plan | The maintainer approves the plan, then `board move <n> build` |
| Build | Branch, worktree, draft PR; per-task implement and review | The PR is ready: `board move <n> review` |
| Review | Whole-branch review, fixes, CI | With `needs-playtest`: `board move <n> playtest --staged <sha>`. Without it, the PR merges |
| Playtest | Waiting on the maintainer's in-game result, plus `In-game check` issues | `board result <n> ...` (below) |
| Done | Closed issues, for any reason | Archived after 14 days without updates |

**Definition of ready for Next.** The ticket body has these sections: `## Goal`, `## Why`, `## Scope`, `## Done when`, `## Constraints and known facts`, `## Open questions`, `## Links`. The **Ready** issue template provides them, and `board move <n> next` refuses without them.

**Playtest results.**
- On a work card: `board result <n> pass`, `board result <n> fail`, or `board result <n> defer --checks-file F`, where F holds one check per line, each starting with its priority (`Urgent:`, `High:`, `Medium:` or `Low:`). `defer` files one `In-game check` issue with those checks as tasks; its Priority is the highest priority among the checks. Results are bound to the staged SHA.
- On an `In-game check` issue: `pass` or `fail` only. Both close it; `fail` also files a `Bug` that links the check.

**Who runs board commands.** Only the maintainer, or an agent acting for the maintainer, runs the board's write commands: `new`, `triage`, `start`, `move`, `result`, `block`, `unblock`, `parent`, `unparent`, `milestone`, `decide`, `labels` and `check`. Run `scripts/board`, for writes and authenticated reads alike, only from the maintainer's own checkout of `main`, never from a branch or snapshot under review, because a branch's `scripts/board` is untrusted code. Contributors file issues with the templates (`gh issue create` or the web), read the board on GitHub or with `list`, `waiting` and `show` from their own trusted checkout (scope `read:project`), and ask the maintainer on the ticket to move their card when their work changes lanes. `scripts/board --help` lists the commands.

**Agent rules the script cannot check:**
- Run `board start <n> build` or `board move <n> build` only after the maintainer approved that plan (for a fix batch without a spec: that batch) in the current session.
- Run `board result` only with a result the maintainer reported in the current session.
- Never move a card out of Playtest by hand.

## Roles

| Team | Repo | Board |
|---|---|---|
| `maintainers` | Admin | Admin |
| `contributors` | Write: `feature/*` and `fixes/*` branches and PRs | Read |
| `playtesters` | Triage: comment and file issues | Read |

- **Playtesters** take `In-game check` issues and post what they saw as a comment. The maintainer records the result.
- **Maintainer-only:** board writes, triage, ordering Next, milestones, merging, releases, staging on `.testserver`, the in-game probe extensions and deploys. A contributor's agent skips these and says in its PR what still needs doing.

## Design and implementation

- **Skills.** Use the repo-local [Superpowers v7.0.2 skills](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7/skills) for feature design, planning and implementation. Codex uses `.agents/skills/`, and Claude Code uses the same files through `.claude/skills/`. An agent without skill support reads each `SKILL.md` as instructions. See the [Codex tool mapping](.agents/skills/using-superpowers/references/codex-tools.md).
- **Specs and plans.**
  - For new features, agree on the design with the maintainer.
  - Write the spec in `docs/superpowers/specs/` and the task plan in `docs/superpowers/plans/`, and link both from the ticket.
  - Have the spec reviewed and fix the findings, then hand the spec to the maintainer before drafting the plan, unless the maintainer asks for a combined handoff. Then the same for the plan.
  - Implementation starts once the maintainer approves the plan and authorizes the build. Subagent-driven development is the default. An agent that cannot start subagents uses `executing-plans` inline, and gets each task reviewed in a separate, fresh session.
- **Writing a feature spec.**
  - Write it for the person deciding how the game should play.
  - Give a full gameplay spec explicit sections: Why, Goals, Non-goals (adjacent work outside the feature) and Anti-goals (outcomes that would spoil it even if the code worked).
  - Compare viable approaches, with concrete gameplay examples of success and failure.
  - Distinguish the maintainer's decisions, proposed tuning, choices left to the builder, automated acceptance and in-game checks.
  - Choose the other sections to answer real questions about the feature.
  - Identify engine assumptions that still need a check.
  - Examples:
    - The [player settings spec](docs/superpowers/specs/2026-11-16-player-settings-design.md) separates design decisions from choices left to the builder.
    - The [road placement spec](docs/superpowers/specs/2026-11-16-cop-spots-by-road-design.md) explains what the current code does.
    - The [Pigeon helicopter spec](docs/superpowers/specs/2026-11-17-pigeon-helicopter-design.md) records what was proven in game.
- **Writing a plan.** Another agent must be able to execute each task from its files, input fixtures, expected observations and verification commands. Break up steps that combine several decisions or checks. The [player settings plan](docs/superpowers/plans/2026-11-16-player-settings.md) shows the expected detail.
- **Running the work.**
  - The coordinator moves the ticket's card, tracks the plan (for longer jobs, a progress checklist the maintainer can see, such as the task list on the ticket), and dispatches a fresh implementer per task with the worktree, requirements and context. The implementer tests, commits and self-reviews.
  - A separate reviewer checks each task for requirements and code quality. Fixes go back to an implementer and are re-reviewed.
  - Before merge, a fresh reviewer examines the whole branch diff and posts the review on the PR.
- **Parallel fix batches.** While the main work is being implemented or reviewed, and no other fix batch is running, pick clear, independently testable bugs from the Backlog whose files do not overlap the main work, for a parallel fix batch on its own `fixes/<topic>` branch and PR. Issues needing a maintainer decision or an in-game check stay out of it and get `needs-decision` or a playtest.

Add source comments or emojis only when the maintainer asks for them.

## Branches, pull requests and merging

- **One branch per piece of work.**
  - Each feature or fix batch gets its own branch and worktree, named `feature/<topic>` or `fixes/<topic>`, created with `gh issue develop <n>` so the issue's Development section shows it.
  - Push at the first commit and open a draft PR with `Fixes #n`.
- **Merge gate:**
  - CI green on the PR's current head
  - the final review resolved
  - for `needs-playtest` PRs, a `board result` of pass or defer for exactly that head SHA. A later push voids the result.
- **Merging.** From the main checkout:
  1. Remove the worktree.
  2. `gh pr merge <pr> --merge --delete-branch --match-head-commit <sha>`.
  3. Pull `main`.
- **Direct commits on `main`.** While the repo is private, the maintainer (or an agent acting for the maintainer) may push docs-only changes such as specs, plans and this file straight to `main`. Contributors always use PRs. Everything that changes game or server behaviour goes through a PR. Once the repo is public, everything goes through a PR. Version bumps always do (see Releases).
- **Identity.** Everyone commits with their GitHub noreply address (`ID+login@users.noreply.github.com`), never a personal or work email; the privacy check rejects others. The maintainer commits as `ReinderN` and SSH-signs.

## Privacy

- Write commits, files and messages as if the repo were public.
- **Never include:** IP addresses, email addresses other than GitHub noreply ones, SSH login targets, URLs with credentials, absolute home paths, or anything about how or where the live server runs (type, hosting, containers, paths). Use `<repo>` for the checkout root and `~` for home. Keep machine-specific values in environment variables or git-ignored files.
- **`scripts/privacy-check`** enforces this:
  - The pre-push hook runs it on every outgoing commit. Enable it once per clone with `make hooks`, from a checkout of `main` you trust.
  - `make privacy` scans the tree.
  - CI checks every PR commit, and the full history on `main`.
  - Exact exceptions go in `.github/privacy-allow.txt` as `path:text`.
  - Private terms live only in the uncommitted `.git/info/privacy-deny`.
- **Never rewrite history** that has been pushed.

## Verification and release

- **Automated tests first.** If known inputs determine the expected result, verify it with an automated test. Use recorded round data for leaderboard ranking and assist thresholds, and sampled positions and speeds for catch timing. Add a missing regression test when needed. A passing test closes that part of the check.
- **Local checks.**
  - Keep game-side Lua compatible with BeamNG's LuaJIT. Check each changed game-side Lua file with `luajit -bl path/to/file.lua >/dev/null`.
  - Run `make test` for Lua changes and `make vuecheck` for UI changes.
  - `make package` builds the client ZIP, server payload, tarball and checksums.
  - The README lists the prerequisites. `docs/DEPENDENCIES.md` locates upstream APIs and compatibility checks.
- **CI** runs `test`, `luajit`, `vuecheck`, `privacy` and `package` on every PR and push to `main`.
- **Playtests.**
  - Ask the maintainer for a playtest (label the PR `needs-playtest`) only when an open question depends on what BeamNG or BeamMP actually does, or on what the player sees, hears or feels. Use an engine probe or logs first when they can answer it.
  - For each manual check, give the shortest setup and action, the observable pass condition, and the uncertainty it resolves.
  - Ask for a second player only when observing a second client is essential.
  - A deferred check becomes an `In-game check` issue in Playtest, filed by `board result <n> defer --checks-file F`.
- **Staging on the local test server (maintainer-only).**
  1. Extract `git archive <reviewed-sha>` into a disposable directory and work from that snapshot.
  2. Set `test_server=<repo>/.testserver`.
  3. If it has an installed config, first run `cp "$test_server/Resources/Server/CopsAndRobbers/config.json" server/CopsAndRobbers/config.json` in the snapshot.
  4. Run `make install-local TESTSERVER="$test_server"`.
  5. Restart the local BeamMP server. Then, from the maintainer's checkout of `main` (not the snapshot), record the SHA with `scripts/board move <n> playtest --staged <sha>`.
  The maintainer handles game and launcher restarts.
- **Engine probes (maintainer-only).**
  - Use a temporary GE extension in the game's user folder (`current/lua/ge/extensions/`), and read its tagged output in `current/beamng.log`.
  - Give the maintainer one comment-free GE console line, with statements separated by `;`.
  - Use freeroam for console experiments, and request screenshots for placement or visual tuning.
  - Ask before deleting a probe from the maintainer's game folder.
- **Releases.**
  - `make version V=x.y.z` builds the version commit on top of `origin/main` without touching the checkout, pushes `release/x.y.z` and opens the PR **Release x.y.z**.
  - Merging it is the approval to release: `release.yml` tags the merge commit and publishes the GitHub Release with the ZIP, tarball and checksums.
  - Agents merge a release PR only after the maintainer said, in the current session, to release that version.
  - Version numbers stay out of feature plans and branches. Tests use `CNR_VERSION`.
- **Deploy.**
  - The live server's setup is kept out of this repo.
  - Until the server-side updater exists (its own ticket), the maintainer deploys by hand, or with `make deploy` and a local `CNR_DEPLOY_SCRIPT`. An agent runs `make deploy` only when the maintainer explicitly asks for that deploy in the current session.
  - After a deploy, check that the server log shows the expected version loaded, and check for Lua errors.
  - A previous release's approval applies to that release alone.
