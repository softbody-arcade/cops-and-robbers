# Cops and Robbers: agent rules

**Read `base/AGENTS.md` first** ([on GitHub](https://github.com/softbody-arcade/arcade-base/blob/main/AGENTS.md)). It holds the rules every Softbody Arcade repo shares: the ticket ledger and board lanes, roles, design and implementation, branches and merging, trusted code, privacy, and the general verification and release rules. This file only adds what is specific to Cops and Robbers; it never contradicts the shared rules. If `base/` is empty, run `git submodule update --init` (or clone with `--recurse-submodules`); `make doctor` checks it.

## This repo

- `softbody-arcade/cops-and-robbers` is a chase minigame for BeamNG.drive multiplayer (BeamMP).
- **Board.** The board's one auto-add workflow covers this repo: issues filed here land in Inbox by themselves.
- **The base.** `base/` is arcade-base as a submodule, pinned to a release; its `.gitmodules` entry and pin follow the shared **Trusted code** rule. This repo doesn't run on the base's library yet ([#56](https://github.com/softbody-arcade/cops-and-robbers/issues/56)).
- **Own copies of the shared tooling.** Until this repo moves onto the base's scripts and Actions, it keeps its own `scripts/board`, `scripts/privacy-check`, `scripts/doctor`, release scripts and workflows, issue templates and Superpowers skills (`.agents/skills/`, read by Claude Code through `.claude/skills/`). Run them from this repo, not from `base/`: `base/scripts/board` reads arcade-base's config ([arcade-base#8](https://github.com/softbody-arcade/arcade-base/issues/8)).
- **Roles.** [docs/ROLES.md](docs/ROLES.md) covers what is specific to this repo; the shared roles are in arcade-base's [roles page](https://github.com/softbody-arcade/arcade-base/blob/main/docs/ROLES.md).

## Verification

- **Automated tests.** Use recorded round data for leaderboard ranking and assist thresholds, and sampled positions and speeds for catch timing.
- **Local checks.**
  - Check each changed game-side Lua file with `luajit -bl path/to/file.lua >/dev/null`.
  - Run `make test` for Lua changes and `make vuecheck` for UI changes.
  - `make package` builds the client ZIP, server payload, tarball and checksums.
  - `docs/DEVELOPMENT.md` lists the prerequisites (`make doctor` checks them). `docs/DEPENDENCIES.md` locates upstream APIs and compatibility checks.
- **CI** runs `test`, `luajit`, `vuecheck`, `privacy` and `package`; these are the required checks.
- **Staging on the local test server (maintainer-only).**
  - **The maintainer's own branches:**
    1. Extract `git archive <reviewed-sha>` into a disposable directory and work from that snapshot.
    2. Set `test_server=<repo>/.testserver`.
    3. If it has an installed config, first run `cp "$test_server/Resources/Server/CopsAndRobbers/config.json" server/CopsAndRobbers/config.json` in the snapshot.
    4. Run `make install-local TESTSERVER="$test_server"`.
  - **A contributor's PR:** staging it runs its Makefile, packaging and server Lua under the maintainer's account, and no recipe on that account makes this safe. Agents never stage a contributor's PR. Until an isolated test server exists (#40), the maintainer decides per PR, after reviewing the whole diff, whether to playtest it and how.
  - **`develop` itself:** to test several merged tickets together, follow the same steps with `git archive origin/develop` (after `git fetch`). Their PRs are merged, so record the session as an `In-game check` issue that lists the tickets and checks (`board new in-game-check <priority> "<title>" --body-file F`, then `board move <n> playtest`), and report it with `board result <n> pass|fail`; skip `--staged`.
  - After installing, restart the local BeamMP server. When staging a single PR, record its head SHA from the maintainer's checkout of `develop` (not the snapshot) with `scripts/board move <n> playtest --staged <sha>`. The maintainer handles game and launcher restarts.
- **Engine probes (maintainer-only).**
  - Use a temporary GE extension in the game's user folder (`current/lua/ge/extensions/`), and read its tagged output in `current/beamng.log`.
  - Give the maintainer one comment-free GE console line, with statements separated by `;`.
  - Use freeroam for console experiments, and request screenshots for placement or visual tuning.
  - Ask before deleting a probe from the maintainer's game folder.

## Releases

- `make version V=x.y.z` builds the version commit on top of `origin/develop` without touching the checkout, pushes `release/x.y.z` and opens the PR **Release x.y.z** into `main`.
- **Hotfix:** `make version V=x.y.z FROM=main` starts the release branch from `main` instead, so unreleased work on `develop` stays out. Put the fix on `release/x.y.z` through a PR into that branch, then merge the release PR.
- Merging the release PR (with `--delete-branch`) is the approval to release: `release.yml` tags the merge commit and publishes the GitHub Release with the ZIP, tarball and checksums. It then opens **Sync main into develop**, which merges without `--delete-branch` because its head is `main`.
- After publishing, run `scripts/board release` (from the maintainer's checkout of `develop`) to move the released work from Accepted to Done.
- Tests use `CNR_VERSION`, never a literal version.

## Deploy

- The live server's setup is kept out of this repo.
- Until the server-side updater exists (its own ticket), the maintainer deploys by hand, or with `make deploy` and a local `CNR_DEPLOY_SCRIPT`. An agent runs `make deploy` only when the maintainer explicitly asks for that deploy in the current session.
- After a deploy, check that the server log shows the expected version loaded, and check for Lua errors.
- A previous release's approval applies to that release alone.
