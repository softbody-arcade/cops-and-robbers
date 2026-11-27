# Who can do what in Cops and Robbers

The teams, what each one can do, how coding agents act, and the rulesets are the same in every Softbody Arcade repo. They are on arcade-base's [roles page](https://github.com/softbody-arcade/arcade-base/blob/6198cea32b7b8469a390bf2d12e012cafe35d8de/docs/ROLES.md), at the version this repo pins in `base/`. The working rules on top of them are in the shared [agent rules](https://github.com/softbody-arcade/arcade-base/blob/6198cea32b7b8469a390bf2d12e012cafe35d8de/AGENTS.md), this repo's [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

This page lists only what differs for `softbody-arcade/cops-and-robbers`.

## Board

The board's one auto-add workflow covers this repo: an issue filed here lands in Inbox by itself. Issues in other repos, such as arcade-base, are added to the board by a maintainer.

## Required checks

`develop-checks` and `main-checks` require the five CI checks: `test`, `luajit`, `vuecheck`, `privacy` and `package`. A maintainer merges a PR only when all five are green. arcade-base currently requires only `test` and `privacy`.

## Automations

| Automation | What it does | Rights |
|---|---|---|
| CI (`ci.yml`) | Runs the five checks on every PR and on pushes to `develop` and `main` | Read-only token |
| Release (`release.yml`) | When a PR from this repo's `release/x.y.z` branch merges into `main` (or on a manual run for an already merged one): tests and packages without write access, then tags `vx.y.z`, publishes the release with the ZIP, server archive and checksums, and closes milestone `x.y.z`, then opens **Sync main into develop** | Writes in the publish job (tag, release, milestone) and the sync job (opens a PR) |
| Dependabot | Opens a PR each week when a GitHub Action, a `tools/vuecheck` npm package or the `base/` submodule has a new version, and raises security alerts | Opens PRs; a maintainer merges them |

The board workflows and secret scanning work as on the shared page.

## Known gaps

- A contributor can still create a new `v*` tag or publish a release by hand (#42). Today releases are deployed by hand, so the maintainer decides what goes live. The planned updater (#25) will only install releases published by the release workflow.
