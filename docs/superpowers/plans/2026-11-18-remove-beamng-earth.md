# Remove BeamNG.Earth support — implementation plan

> Use Superpowers subagent-driven development. Each task has a fresh implementer and independent reviewer. Track steps with the checkboxes below.

**Goal** — A fresh CnR install runs the ordinary BeamMP protocol on every level and ships no trace of the retired integration.

**Architecture** — Keep the existing XYZ position, road, station and settings paths. Remove the alternate protocol at both ends. An upgrade overlays the shipped files and leaves stale files and historical data in place.

**Tech stack** — BeamMP server Lua, BeamNG LuaJIT, Vue, Bash, GNU Make and rsync.

**Approved design** — [Removal design](../specs/2026-11-18-remove-beamng-earth-design.md), commit `cc1e77a`.

## Global constraints

- Work on `remove-beamng-earth`. Read the shared ledger from main. Before starting, compare the branch with current main, `fixes-16` (reviewed design baseline `3c21153`) and `thunder` (documentation head `6bd7132`). Carry merged work forward. Coordinate any still-unmerged overlap with its owner and repeat the package audit on the eventual integrated revision. The placement and thunder changes have their own review and playtest gates.
- No special map detection, unsupported-map screen, compatibility shim, data migration, purge, fixture naming the old level, or installer deletion list. Leave host files and existing leaderboard rows alone. Keep historical design records in the repository.
- For each code task, run its focused cases and `make test`. Compile each changed game Lua file with `luajit -bl path/to/file.lua >/dev/null`. Run `make vuecheck` for UI edits. Commit and review each task before advancing. Keep the version bump for merged main.

## Review focus

1. Rejoining with a missing vehicle sample must preserve placement grace and avoid a false reset penalty (task 2).
2. A lost runner, a cop with routing disabled and a spectator must each retain their existing route and visibility behavior (task 2).
3. Two vertically separated stations at the same XY must remain distinguishable (task 1).
4. A host setting a year for sky generation or running practice with few free car slots must keep the same sky and traffic behavior (task 1).
5. An upgrade with an unknown map in historical runs and a stray file must preserve both (task 4).

## Task 1 — Ordinary settings and stations

- [ ] Cover the ordinary cases in `tests/test_sky.lua`, `test_weather.lua`, `test_traffic.lua`, `test_nearby.lua`, `test_panel.lua` and the station cases in `tests/test_main.lua` and `test_client.lua`. In this task remove or update all retired settings, station and panel expectations, including the station-list, panel snapshot and map-specific traffic cases in `tests/test_main.lua`. Update calls to the following signatures first and run the focused Lua files with `lua tests/run.lua tests/test_sky.lua tests/test_traffic.lua tests/test_nearby.lua`. A supplied year must select the same date as before, practice must retain its existing vehicle cap, and nearest must return 10 m before 300 m for points at those vertical distances.
- [ ] In `server/CopsAndRobbers/cnr/{sky,traffic,panel}.lua` and all callers in `main.lua`, use `sky.pick(cfg, random, year)`, `traffic.perPlayer(setting, maxCars, practice)` and `traffic.note(setting, maxCars, players, runnerOnly)`. Preserve random weather, New sky, runner-only traffic, station count and setting availability. Remove the extra mode flag from panel snapshots.
- [ ] Collapse station load/save, discovery, add/remove and list messages to the existing XYZ path in server `main.lua` and client `lua/ge/extensions/copsAndRobbers.lua`. Keep radius storage and ordinary discovery from both facilities APIs. Send `cnr_stationList` with its stations array. In client `copsAndRobbers/nearby.lua` use `nearest(points, here, limit)` with 3D distance. Remove the old station lookup caller and source-specific station branches together.
- [ ] In `client/ui/modules/apps/CopsAndRobbersPanel/{PanelSettings.vue,PanelMap.vue,settings.js}`, remove obsolete setting gates, selectors and copy. Verify ordinary manual stations, station list and weather controls using the existing tests and Vue check. Commit and review.

## Task 2 — One position protocol from server to client

- [ ] Exercise the registered handlers in `tests/test_main.lua` and `tests/test_client.lua`. Assert the version at join, XYZ runner setup, XYZ resume after rejoin, the existing missing-vehicle fallback, and live/lost sight payloads. On the pre-grid branch, assert the join and broadcast mode payloads contain only `version = CNR_VERSION`. On the integrated `fixes-16` branch, both payloads must also advertise `startGrid = true`. Update both expectations together when integrating. Run the tests before editing.
- [ ] In server `main.lua` and `cnr/round.lua`, read vehicle position and velocity through the existing ordinary `MP.GetPositionRaw` path, including AI owners and traffic. Retain `cnr_mode`, `cnr_roundSetup`, `cnr_lastSeen` and `cnr_nearestCop`. Remove geo report and relocation event registrations, their callbacks, tracking/cache state, alternate sight throttle and deferred reset. Keep `Round:vehiclePlaced` and its internal tracking reset. Run `tests/test_round.lua` with the handler tests.
- [ ] In client `lua/ge/extensions/copsAndRobbers.lua`, keep version mismatch, first-use help and HUD reset in the mode handler. Use ordinary placement vectors and `core_groundMarkers.setPath(target)` or `setPath(nil)` for routes. Preserve all eight compass directions by moving the existing helper into `copsAndRobbers/game.lua`. Verify lost/live sight, route disabled, end/leave, minimap/name-tag hiding and spectator behavior. Remove the rebase hook, periodic reports and GPS polling. Remove only the corresponding `ai.relocate` helper from `copsAndRobbers/ai.lua`. Preserve `ai.objects()`.
- [ ] Remove server `cnr/geo.lua`, client `copsAndRobbers/geo.lua`, `tests/test_geo.lua` and remaining obsolete position-protocol cases/stubs in mixed tests. Preserve compass, normal route clearing, no-position and ordinary layout-switch coverage, using neutral layout names in `tests/test_placement.lua`. Simplify `game.mapTitle(id)` to use the engine title and existing generic fallback. Keep the returned table shape and USA/UK casing.
- [ ] If the canonical start grid from `fixes-16` is present, remove alternate poses, warning and rebase retries in `startGrid.lua`, client setup, server validation and tests. Retain the mode capability bit at join and broadcast, the ready/plan/grid handshake, XYZ and direction validation, per-slot failure, timeout fallback and one-way placement for human and AI rounds. If the grid lands later, record this same check on the integration and run it there before shipping the combination. Verify thunder's shared seed, spectator clock and flash setting on any integrated thunder head. Commit and review.

## Task 3 — Current documentation and deployment

- [ ] Edit `README.md`, `docs/FEATURES.md` and `docs/DEPENDENCIES.md`. Describe ordinary BeamMP installation, route/station APIs, weather and traffic. Remove retired support claims, exceptions, IDs and upstream checks. Scan player-facing help, shipped metadata and pending thunder documentation for equivalent copy.
- [ ] Replace the host-specific deploy script with a host-configured entry point. Keep `make deploy` as an explicit host-configured entry point. Proposed interface: the host supplies `CNR_DEPLOY_SCRIPT` pointing to an executable that accepts the absolute packaged client ZIP and server payload directory as its two arguments. Document the arguments, the host’s responsibility for preserving config/data and verifying the loaded version and logs. Do not invent a production destination.
- [ ] Exercise the deployment interface locally. With the variable unset the command must exit nonzero before any network operation. With a temporary executable that only records its arguments, assert both paths exist, are absolute, and point to the ZIP and server plugin directory. Verify failure status from the executable propagates. Keep `make package` and `make install-local` usable without deployment settings. Commit and review.

## Task 4 — Fresh package, overlay and local playtest

- [ ] From a disposable `git archive` of the reviewed SHA, run LuaJIT checks, `make test`, `make vuecheck` and `make package`. Run `unzip -t dist/Client/CopsAndRobbers.zip`, unpack it and inspect names and text in both the extracted client and `dist/Server`. Install into an empty temporary directory with `make install-local TESTSERVER=...` and repeat the inspection, including its client ZIP. Audit source, filenames, tests, UI, deploy scripts and current docs for the retired map ID, API names, wire events, pose fields and modules. Exclude dated planning history from the source audit. Run the audit during review without shipping a blacklist.
- [ ] Repeat the install over a disposable fixture with a custom config, existing leaderboard with ordinary and unknown map IDs, a per-map station file and a stray file. Follow the documented config-copy step before overlay. Compare those files before and immediately after install. Complete an ordinary round, restart and check history and rankings include earlier runs and the new result. No fixture or check needs to name the retired map.
- [ ] Get an independent whole-branch review, resolve findings and re-review changes. Stage the reviewed archive on the local server with its config preserved. Report the SHA and a short playtest list. On West Coast USA check a chase, normal and watched-AI practice, rejoin and spectating, spawn headings, last-seen routes, nearest cop, tags/minimap, reset/catch, stations and weather/traffic controls. On Italy check independent station discovery and map-filtered history. On a head including `fixes-17` and `fixes-18`, watch the helicopter track a visible runner, search after sight is lost, reacquire the runner and clean up its searchlight and rotor sound at round end. Repeat on the integrated head if those branches land later. Confirm round history survives restart.
- [ ] Record user results or explicitly deferred in-game checks on main. After merge, run the relevant checks on main and reconcile the shared ledger, including its retired research section, while preserving ordinary open issues. Follow the project's separate version-bump and deployment workflow.
