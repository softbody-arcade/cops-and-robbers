# Who can do what

This page covers the [Softbody Arcade](https://github.com/softbody-arcade) organization, the `cops-and-robbers` repo and the [Softbody Arcade board](https://github.com/orgs/softbody-arcade/projects/1). The repo and the board are public. GitHub enforces the access rules below; the working rules on top of them are in [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

## At a glance

| | Anyone on GitHub | Playtester | Contributor | Maintainer |
|---|---|---|---|---|
| See the code, issues and board | Yes | Yes | Yes | Yes |
| Open issues and comment | Yes | Yes | Yes | Yes |
| Fork and open a PR from the fork | Yes | Yes | Yes | Yes |
| Report a security problem privately | Yes | Yes | Yes | Yes |
| Set labels, type, Priority, Effort, milestone and assignee; close and reopen issues | No | Yes | Yes | Yes |
| Push branches to the repo itself | No | No | Yes, except `main` and `release/*` | Yes, except `main` |
| Approve a PR | No | No | Yes, as advice | Yes, as advice |
| Merge into `main` | No | No | No | Yes, through a PR with green CI |
| Push straight to `main` | No | No | No | No |
| Start a release (`release/*` branch) | No | No | No | Yes |
| Move or delete a `v*` tag | No | No | No | Yes |
| Move cards on the board | No | No | No | Yes |
| Change repo, board or org settings | No | No | No | Yes |

Teams give the extra rights: `playtesters` is Triage on the repo, `contributors` is Write and `maintainers` is Admin. On the board, `maintainers` is Admin and everyone else can read.

## Anyone on GitHub

Anyone with a GitHub account can:
- read the code, the issues, the pull requests and the board
- open an issue with one of the templates (Bug, Feature idea, In-game check, Ready ticket) and comment on any issue or PR
- fork the repo and open a PR from the fork. CI runs on a fork PR only after a maintainer approves the run, and the run gets a read-only token.
- report a security problem privately with **Report a vulnerability** on the Security tab (see [SECURITY.md](../SECURITY.md))

They can't change anything in the repo or on the board.

## Playtesters

Playtesters run in-game checks and report what they see.

On top of what anyone can do, they can:
- give an issue its type, Priority, Effort, labels and milestone, assign it, and close or reopen it
- mark duplicates, and hide or lock unhelpful comments

What they normally do:
1. Pick an issue of type **In-game check**.
2. Follow its setup and action, and post a comment: pass or fail, and what happened.
3. File a **Bug** for anything else they notice.

The maintainer records the result and moves the card.

## Contributors

Contributors write code and docs.

On top of what a playtester can do, they can:
- push branches to the repo itself (by convention `feature/<topic>` and `fixes/<topic>`) and open PRs from them, so CI runs without waiting for approval
- review and approve PRs. Nothing requires an approval to merge, so an approval is advice, not a gate.
- delete their own branches. Merged branches are deleted automatically.

They can't:
- merge into `main`, push to it, force-push it or delete it
- create, change or delete `release/*` branches
- move or delete a `v*` tag
- move cards on the board. They comment on the issue and the maintainer moves the card.

Known gap: a contributor can still create a new `v*` tag or publish a release by hand (#42). The server's updater only installs releases published by the release workflow (#25), so a hand-made release never deploys.

What they normally do:
1. Comment on an issue to claim it. The maintainer starts the card and assigns it to them.
2. Branch, push early, and open a draft PR with `Fixes #n`.
3. Follow [AGENTS.md](../AGENTS.md) for specs, plans, tests and reviews.
4. Say in the PR if players would see, hear or feel the change.

## Maintainers

The `maintainers` team has Admin on the repo and on the board. The organization owner can also change org settings, teams and billing.

Only maintainers:
- triage new issues, order the Next lane and move cards between lanes
- merge PRs into `main`. A merge needs a PR with the five CI checks green: `test`, `luajit`, `vuecheck`, `privacy` and `package`. Nobody can push to `main` directly, maintainers included.
- start a release with `make version V=x.y.z` and merge the `Release x.y.z` PR, which tags and publishes it
- stage builds on the local test server and deploy to the live server
- change repo settings, rulesets, teams, the board's fields, views and workflows, and org settings

## Coding agents

An agent (Claude, Codex or any other) acts with the GitHub login of the person running it, so it gets exactly that person's rights. [AGENTS.md](../AGENTS.md) narrows that further:
- An agent working for a contributor follows the contributor rules. It skips maintainer-only steps and lists them in its PR.
- An agent working for the maintainer merges, releases, deploys or writes to the board only for what the maintainer asked or decided in the current session.
- Agents never run a contributor's branch on the maintainer's machine. They review it as a diff, and CI runs it.
- Every decision an agent hears in chat goes on the ticket as a dated comment, written for a public repo.

## Automations

| Automation | What it does | Rights |
|---|---|---|
| Board workflows | Add new issues to the board in Inbox, move closed issues to Done and reopened ones back to Inbox, add sub-issues, archive Done cards after two weeks | Board only |
| CI (`ci.yml`) | Runs the five checks on every PR and on `main` | Read-only token |
| Release (`release.yml`) | When a `Release x.y.z` PR merges: tests and packages without write access, then tags `vx.y.z`, publishes the release with the ZIP, server archive and checksums, and closes milestone `x.y.z` | Writes only in the publish job |
| Dependabot | Opens a PR each week when a GitHub Action or a `tools/vuecheck` npm package has a new version, and raises security alerts | Opens PRs; a maintainer merges them |
| Secret scanning | Blocks a push that contains a known secret format | Push protection on |

## Enforced on GitHub

| Ruleset | Applies to | Effect |
|---|---|---|
| `main-checks` | `main` | PR required, the five CI checks must pass, merge commits only, no force-push or deletion. Nobody bypasses it. |
| `main-merge` | `main` | Only maintainers can update `main`, and only by merging a PR. |
| `release-branches` | `release/*` | Only maintainers can create, update or delete them. |
| `release-tags` | `v*` tags | Only maintainers can move or delete them. |

The organization also requires two-factor sign-in, and members can't create repositories.
