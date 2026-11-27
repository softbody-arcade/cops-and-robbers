# Who can do what

This page covers the [Softbody Arcade](https://github.com/softbody-arcade) organization, the `cops-and-robbers` repo and the [Softbody Arcade board](https://github.com/orgs/softbody-arcade/projects/1). The repo and the board are public. Tickets merge into `develop`, the default branch; `main` only receives releases. GitHub enforces the access rules below; the working rules on top of them are in [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

## At a glance

| | Anyone on GitHub | Playtester | Contributor | Maintainer |
|---|---|---|---|---|
| See the code, issues and board | Yes | Yes | Yes | Yes |
| Open issues and comment | Yes | Yes | Yes | Yes |
| Fork and open a PR from the fork | Yes | Yes | Yes | Yes |
| Report a security problem privately | Yes | Yes | Yes | Yes |
| Edit and close their own issues | Yes | Yes | Yes | Yes |
| Set labels, type, Priority, Effort, milestone and assignee on any issue; close and reopen it | No | Yes | Yes | Yes |
| Push branches to the repo itself | No | No | Yes, except `develop`, `main` and `release/*` | Yes, except `develop` and `main` |
| Review a PR, including an approving review | Yes, unless reviews are limited to people with access | Yes | Yes | Yes |
| Merge into `develop` or `main` | No | No | No | Yes, through a PR with green CI |
| Push straight to `develop` or `main` | No | No | No | No |
| Start a release (`release/*` branch) | No | No | No | Yes |
| Move or delete a `v*` tag | No | No | No | Yes |
| Move cards on the board | No | Merged work: Playtest → Accepted or Build | Own cards, Build ↔ Review | Anything |
| Add game idea drafts to the board | No | Yes | Yes | Yes |
| Change repo and board settings | No | No | No | Yes |
| Change org-wide settings and create teams | No | No | No | Org owner only |

Teams give the extra rights: `playtesters` is Triage on the repo, `contributors` is Write and `maintainers` is Admin. On the board, `playtesters` and `contributors` have Write and `maintainers` Admin. Board Write can't be limited per lane, so the allowed moves are a rule, not enforced; GitHub's history shows who moved what.

## Anyone on GitHub

Anyone with a GitHub account can:
- read the code, the issues, the pull requests and the board
- open an issue with one of the templates (Bug, Idea, In-game check, Ready ticket), comment on any issue or PR, and edit or close their own issues
- fork the repo and open a PR from the fork. CI on a PR from an external contributor (someone outside the organization) waits until someone with Write approves the run, and the run gets a read-only token.
- review PRs, unless reviews are limited to people with access. Reviews are advice: GitHub requires no approving review, and the merge gate in [AGENTS.md](../AGENTS.md) decides instead.
- report a security problem privately with **Report a vulnerability** on the Security tab (see [SECURITY.md](../SECURITY.md))

They can't change anything else in the repo or on the board.

## Playtesters

Playtesters run in-game checks and report what they see.

On top of what anyone can do, they can:
- give an issue its labels, Priority, Effort and milestone, assign it, and close or reopen it (and its type, in the web interface)
- mark duplicates

What they normally do:
1. Pick an issue of type **In-game check**.
2. Follow its setup and action, and post a comment: pass or fail, and what happened.
3. For merged work they tested on `develop`, move the card: **Playtest → Accepted** when it passed, **Playtest → Build** when it didn't. For `In-game check` issues and unmerged changes, the comment is enough; the maintainer records the result.
4. File a **Bug** for anything else they notice.

They can also add new minigame ideas to the board as draft items (the **Game ideas** view). Bugs and ideas for an existing game start as an issue in its repo, which lands in Inbox by itself. The green status badge on an issue page is GitHub's own issue status, not the board lane; the board lane is what counts.

## Contributors

Contributors write code and docs.

On top of what a playtester can do, they can:
- push branches to the repo itself (by convention `feature/<topic>` and `fixes/<topic>`) and open PRs from them, so CI runs without waiting for approval
- approve CI runs on PRs from external contributors
- delete their own branches. Merged branches are deleted automatically.

They can't:
- merge into `develop` or `main`, push to them, force-push them or delete them
- create, change or delete `release/*` branches
- move or delete a `v*` tag
- move cards other than their own between Build and Review. The maintainer moves the rest.

Known gap: a contributor can still create a new `v*` tag or publish a release by hand (#42). Today releases are deployed by hand, so the maintainer decides what goes live. The planned updater (#25) will only install releases published by the release workflow.

What they normally do:
1. Comment on an issue to claim it. The maintainer starts the card and assigns it to them.
2. Branch, push early, and open a draft PR with `Fixes #n`.
3. Follow [AGENTS.md](../AGENTS.md) for specs, plans, tests and reviews.
4. Say in the PR if players would see, hear or feel the change.

## Maintainers

The `maintainers` team has Admin on the repo and on the board. Org-wide settings, creating teams and billing belong to the organization owner, which is a separate role. A team maintainer can still manage, and delete, their own team.

Only maintainers:
- triage new issues, order the Next lane, and make every card move other than the playtester and contributor drags above
- merge PRs into `develop`, and release PRs into `main`, after the merge gate in [AGENTS.md](../AGENTS.md): the maintainer's go, a final review of the head being merged, and a playtest result where needed. GitHub itself requires a PR with the five CI checks green: `test`, `luajit`, `vuecheck`, `privacy` and `package`. Nobody can push to `develop` or `main` directly, maintainers included.
- start a release with `make version V=x.y.z` and merge the `Release x.y.z` PR, which tags and publishes it
- stage builds on the local test server and deploy to the live server
- change repo settings, rulesets, and the board's fields, views and workflows

## Coding agents

An agent (Claude, Codex or any other) acts with the GitHub login of the person running it, so it can do at most what that person can (its token may allow less). [AGENTS.md](../AGENTS.md) narrows that further:
- An agent working for a contributor follows the contributor rules. It skips maintainer-only steps and lists them in its PR.
- An agent working for the maintainer merges, releases, deploys or writes to the board only for what the maintainer asked or decided in the current session.
- Agents never run a contributor's branch on the maintainer's machine. They review it as a diff, and CI runs it.
- A decision the maintainer makes in a chat goes on the ticket as a dated comment, written for a public repo. When unsure whether something may be published, the agent asks first.

## Automations

| Automation | What it does | Rights |
|---|---|---|
| Board workflows | Add new issues to the board in Inbox, move closed issues to Accepted and reopened ones back to Inbox, add sub-issues. `scripts/board release` (run by the maintainer) moves released and finished work to Done and archives Done cards after 14 days without updates | Board only |
| CI (`ci.yml`) | Runs the five checks on every PR and on pushes to `develop` and `main` | Read-only token |
| Release (`release.yml`) | When a PR from this repo's `release/x.y.z` branch merges into `main` (or on a manual run for an already merged one): tests and packages without write access, then tags `vx.y.z`, publishes the release with the ZIP, server archive and checksums, and closes milestone `x.y.z`, then opens **Sync main into develop** | Writes in the publish job (tag, release, milestone) and the sync job (opens a PR) |
| Dependabot | Opens a PR each week when a GitHub Action or a `tools/vuecheck` npm package has a new version, and raises security alerts | Opens PRs; a maintainer merges them |
| Secret scanning | Blocks a push that contains a supported secret pattern, unless push protection is bypassed | Push protection on |

## Enforced on GitHub

| Ruleset | Applies to | Effect |
|---|---|---|
| `develop-checks`, `main-checks` | `develop`, `main` | PR required, the five CI checks must pass, merge commits only, no force-push or deletion. Nobody bypasses them. |
| `develop-merge`, `main-merge` | `develop`, `main` | Only maintainers can update them, and only by merging a PR. That merge counts as a bypass of this ruleset: `gh pr merge --admin`, or the "bypass rules" tick in the merge box. |
| `release-branches` | `release/*` | Only maintainers can create, update or delete them. |
| `release-tags` | `v*` tags | Only maintainers can move or delete them. |

The organization also requires two-factor sign-in, and members can't create repositories.
