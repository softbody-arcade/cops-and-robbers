# Remove BeamNG.Earth support

Design proposal for review, based on main at `f2046e37ab8a2e38af9479de89f8640a37f91448`.

CnR currently shares game-world positions on ordinary BeamMP maps. BeamNG.Earth gives each player a different coordinate origin, so CnR maintains a second network protocol and uses Earth services for routes and stations. Retire that integration end to end. Acceptance means a packaged, upgraded ordinary BeamMP server can run a chase, including practice and rejoin, with its usual routes, stations, rules and history. Earlier Earth traffic and weather proposals become historical research. Any future support requires a separate complete design, implementation and multiplayer verification in game.

## Scope

A fresh build and install contains only the ordinary BeamMP integration. Remove Earth-specific references from maintained code, tests, configuration, deployment defaults and current documentation. A host selecting any third-party level gets the same ordinary map path. Use the ordinary path without checking the old map ID. Dated design records can still explain the change.

Remove the old live deployment assumptions from the repository. A future live rollout needs a confirmed destination, service and resource paths from the host. Packaging and local installation can be verified independently.

## Proposed order of removal

| Step | Change and behavior to verify |
| --- | --- |
| 1. Establish the ordinary wire contract | Exercise load and join through `cnr_mode` (version, HUD connection, first-use help and app-state reset), setup through `cnr_roundSetup` (`runnerPos`, `resumePos`), and live/lost sight through `cnr_lastSeen` (`pos`, `live`, per-cop `route`). Keep `cnr_nearestCop`, `cnr_requestStations`, `cnr_stations` and `cnr_stationList`. Drop `geo`, `runnerGeo` and `resumeGeo` on the shared messages and panel state. Retire both ends of `cnr_geo` and `cnr_relocated`. Preserve the join/version mismatch warning so a stale client can rejoin for the matching ZIP. |
| 2. Remove the alternate coordinate system | In server `main.lua`, remove automatic geo mode, report validation, staleness, origin, name-based geo resume cache, station conversion/merge, deferred reset verdicts and the three-second live rate limit. Remove `cnr/geo.lua` (WGS84 to local metres) and the geo member on live/last-seen effects in `cnr/round.lua`. Read humans, practice AI and traffic via `MP.GetPositionRaw` with existing owner/vehicle mapping and full 3D position and velocity. Keep sight cadence from settings, normal reset enforcement and placement grace. In particular, `Round:vehiclePlaced` calls `Round:relocated` to clear tracking after placement. |
| 3. Remove client Earth services | In `copsAndRobbers.lua` and client `geo.lua`, remove API discovery/version warnings, 4 Hz reports, Places queries, lat/lon conversions, Earth GPS polling, rebase hook and its practice-only `ai.relocate` caller and implementation. Move the eight-way compass and ordinary route clearing into a surviving client helper before deleting `geo.lua`. Keep vanilla `core_groundMarkers.setPath(target/nil)`, route preferences, distances and last-seen age, name tags/minimap hiding, legal reset and road recovery, and cleanup on round end/leave. Preserve `ai.objects()` for lights, spectators and hiding. |
| 4. Restore one settings and stations path | In server `cnr/sky.lua`, `cnr/traffic.lua`, `cnr/panel.lua` and their callers, drop the geo argument, gates and refusal text. Retain optional year in sky selection, MaxCars/practice limits and runner-only traffic. Keep the client's ordinary solar latitude/date handling. In `PanelSettings.vue`, `settings.js` and `PanelMap.vue`, remove `noEarth`, geo notes and selectors. Preserve the settings editor, station count, discovery via `freeroam_facilities` and `freeroam_gasStations`, per-map XYZ/radius storage, manual add/remove, 3D nearest list and station resets. Retire `nearby.nearest`'s flat-only option. The shipped `config.json` has no Earth switch to migrate. |
| 5. Align release material | Update README, `docs/FEATURES.md` and `docs/DEPENDENCIES.md` throughout, including support claims, feature exceptions, installation and upstream checks. Date-stamped completed specs and plans remain historical evidence. Once merged and checked, reconcile superseded Earth-only ledger items on main while keeping open ordinary-map work. Remove Earth-specific defaults and references from `scripts/deploy.sh`, `make deploy` and host documentation together. Any required deployment settings must come from the host. |

## Existing installations and records

The removal operates on the source tree and the artifacts built from it. Existing installations may retain stale files after an overlay. Remove all callers of the obsolete modules and leave files from previous installations alone. The installer and game must have no Earth-specific detection, deletion or migration logic. Hosts can upgrade without preparing or cleaning their data directories.

Keep normal leaderboard reads and writes, including the existing handling of arbitrary map IDs. Remove the special spelling in `game.mapTitle`. Leave stored runs, stations and shared player data to their ordinary storage paths. The feature requires no one-time maintenance tool, host command or rewrite of historical rows.

## Pending branch integration

| Inspected branch head | Integration consequence |
| --- | --- |
| `fixes-16` · `3c21153c369b9d69b32adbe9353c52ab0ba5e13f` | Coordinate before either branch lands. Preserve the negotiated canonical start grid (`cnr_startGridReady`, `cnr_planStart`, `cnr_startGrid`), ordinary `pos/dir` validation, per-slot failures, one-way headings, AI/human parity, timeouts and fallback for a missing planner. Its `startGrid.lua`, pending human/AI placement, server validation and tests also encode Earth `geo/toward` poses, rebase retries and a warning. Remove these Earth branches on the integrated head. Its watched-AI geo-report fix disappears with the sender. |
| `fixes-17` · `4d76504b482fac48a16e8bf5efb412401e5669a9` and `fixes-18` · `80859ac067c94668ef5a3131fc7cabe4ea501fd2` | Rotor sound and helicopter search/flight edits are independent. Keep their tests and exercise helicopter tracking during sight changes and round cleanup. |
| `thunder` · `aa6891f110933aefbda03ca1d99bad4376be5f65` | Shares client update/sky, host settings, server sky selection and tests. Carry forward storm selection, shared seed, scheduled strikes, the round/rejoin clock, spectator handling and the player's flash preference. Update pending Earth-only acceptance wording when integrating the approved work. |

Refresh these heads when preparing the implementation plan. Coordinate overlap on the removal or integration branch and repeat the checks after merging conflicting work.

## Verification before release

- Audit tracked runtime code, UI, active docs and deployment defaults for Earth API names, hooks, wire fields and map IDs. Inspect mixed tests in `test_client`, `test_main`, `test_round`, `test_sky`, `test_weather`, `test_traffic` and stubs. Remove dedicated geodesy tests and replace Earth-only expectations. Retain ordinary layout-switch, hemisphere/date, compass, route, immediate reset, 3D station and hiding coverage.
- Build from a clean checkout into empty output directories. Inspect the actual client ZIP and server payload, then install into an empty server directory and check the installed contents. All three must be free of the retired modules, identifiers and integration references. Perform this audit during review without adding Earth-specific checks or fixture data to the maintained test suite.
- Exercise the normal overlay install with a custom config, existing runs on ordinary maps and unrecognized map IDs, and an unrelated stale file. Installing should leave existing data and the stale file in place. Finish a round and restart to verify the new run is saved and earlier records are still available.
- Compile every changed game Lua file with `luajit -bl path/to/file.lua >/dev/null`. Run `make test`, `make vuecheck` and `make package`.
- Stage an archived, reviewed SHA on the local BeamMP test server with its installed config preserved. On West Coast USA, exercise a human chase, rejoin and spectate, plus normal and watched-AI practice. Check placement/heading, live and last-seen routes, name tags/minimap, nearest cop, catch/reset/penalty, station add/remove, weather/traffic controls and history after restart. On a second ordinary level such as Italy, check independent station discovery and level-specific leaderboard filtering. Record the tested SHA, observations and logs. The user playtests or explicitly defers outstanding in-game checks before merge. A live deployment is a separate request.
