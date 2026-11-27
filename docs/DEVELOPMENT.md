# Developing Cops and Robbers

Setting up a machine, testing, releasing and the code layout. How to contribute is in [CONTRIBUTING.md](../CONTRIBUTING.md); the full rules for people and coding agents are in [AGENTS.md](../AGENTS.md).

## Prerequisites

For contributors:

- `lua5.3`, `luajit` and `python3` for tests and Lua checks
- Node 22 with npm for UI checks
- `zip`, `unzip`, `rsync`, `gzip`, `sha256sum` (GNU coreutils) and GNU tar for packaging
- `git` 2.41 or newer (the privacy check uses `--attr-source`)
- `ssh-keygen` for SSH commit signing
- Bash 4.4+, `jq` and `gh` 2.106+ for `scripts/board` and its tests

Run `make doctor` to check these prerequisites and your contributor setup.

## The base submodule

`base/` is [arcade-base](https://github.com/softbody-arcade/arcade-base), the shared rules and tooling, pinned to one commit of a base release. `make doctor` reports when `base/` doesn't match the pin; fix it with the step for what it says:

- **Not initialised** (a clone made without `--recurse-submodules`): `git submodule update --init`.
- **`base/` is at another commit than the pin** (you checked out something inside `base/`): `git submodule update -- base` puts it back at the pin.
- **The index pins another commit than the last commit** (you staged a pin change you didn't mean): `git restore --staged -- base`, then `git submodule update -- base`.
- **The index has no base pin** (for example after `git rm --cached base`): `git restore --staged -- base`, then `git submodule update --init -- base`.
- **The base pin has a merge conflict:** keep this branch's pin with `git restore --source=HEAD --staged -- base` (or the other side's with `--source=MERGE_HEAD`), then `git submodule update --init -- base`.
- **Moving the pin on purpose** (to a new base release): check out the release commit inside `base/`, `git add base`, and move every arcade-base link to the same commit in the same PR; `make test` checks the links against the staged pin.

Never edit or commit inside `base/`; changes to the base go through a PR in arcade-base.

## Development

See the compatibility checks for BeamMP and BeamNG.drive updates. [Dependencies](DEPENDENCIES.md)

The `docs/` folder is also an [Obsidian](https://obsidian.md) vault for reading the specs, plans and other docs: open `docs/` with **Open folder as vault**. The shared `docs/.obsidian/app.json` keeps links in the plain Markdown format GitHub shows. Links to files outside `docs/`, such as the README or source files, work on GitHub but fall outside the Obsidian vault. Workspace layout, themes and plugins stay local.

Run `python3 tools/previews/generate.py` to rebuild the app picker thumbnails from the mod logo and the names in each app's `app.json`. The generator uses Pillow and the DejaVu Sans Bold font.

`make test` runs the rule, wiring and client tests with stock Lua (`tests/test_client.lua` loads the real GE
extension against stubbed game functions). `make install-local` installs to `.testserver/` by default. Set `TESTSERVER`
to choose a different local BeamMP server directory.

The version lives in four places (server `main.lua`, client `copsAndRobbers.lua`, `mod_info/.../info.json`, the
`docs/FEATURES.md` heading); `tests/test_version.lua` checks they agree and the other tests read it from the server.
Feature branches never change it, so branches built side by side don't conflict. To release, run
`make version V=x.y.z`: it builds the version commit on top of `origin/develop` (not your local branch), pushes it as
`release/x.y.z` and opens the **Release x.y.z** PR into `main`, without touching your checkout. Merging that PR publishes the
release, and the release workflow then opens a PR that merges `main` back into `develop`. For a hotfix, `make version
V=x.y.z FROM=main` starts the release branch from `main` instead.

Client layout (`client/lua/ge/extensions/`): `copsAndRobbers.lua` holds round state, the server event handlers and the
`onUpdate` steps; `copsAndRobbers/` has `game` (GE helpers), `inputs` (locks, reset hooks), `roads` (spawn spots),
`vehicles` (car pick, cop lights), `lightbar` (emergency light planner), `ai` (practice cars),
`hud` (HUD model), `hudfeed` (HUD state and push), `apps` (opening and closing the apps) and `placement` (layout handling).

## Host-configured deployment

Set `CNR_DEPLOY_SCRIPT` to the path of a host-provided executable when running `make deploy`.

```sh
CNR_DEPLOY_SCRIPT=/path/to/deploy-cnr make deploy
```

The target builds the package and passes two absolute paths to the executable, in order.

1. The packaged client ZIP, `dist/Client/CopsAndRobbers.zip`.
2. The packaged server plugin directory, `dist/Server/CopsAndRobbers/`.

The host's executable handles the destination, preserves installed `config.json` and `data/`, restarts the server
and checks the server log for the expected `Cops and Robbers <version> loaded` line and any Lua errors.
`make deploy` fails if the executable is missing or exits with an error. `make package` and `make install-local`
work independently of the deployment hook.
