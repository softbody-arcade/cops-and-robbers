# Cleanup, TODO fixes and client split (1.6.0)

User request (2026-11-15): "Check in game done, do all fixes now possible, update docs. ... if [a refactor] is needed to have cleaner split of all logic do that". Execution: native, final opus review, deploy, ask before merge.

## Findings that decide the fixes
- **AI crash twice:** the server sends a `cnr_notice` ("AI red: crash penalty 10s") and the client `onPenalty` (aiId) adds its own event. Fix: the client adds no event for AI penalties.
- **UI scale:** BeamNG sets the root font-size to 16px × UI scale, so `rem` fonts follow it.
- **Placement format:** `placementResolve.js` says `margin:auto` is read-only and deprecated. Centred axes use `"50%"` and sizes use `em`.
  - HUD: `{left="50%", right="", bottom="4.375em", width="32.5em", height="14.375em"}`.
- **Layout copy:** a stock layout without a user file (`userFileExists == false`) gets a user copy written by `addApp`. On leave, after removing the HUD, call `api.resetLayout(filename)` if we created the copy and its apps match the original (`/settings/ui_apps/originalLayouts/`).
- **Polling:** `placementTick` reads the layout file every 2 s. Once placed, check every 10 s.
- **`refreshUiApps`:** the panel was confirmed to appear in UI Apps in game, so no change.
- **Parts enforcement:** still blocked on the two BeamMP config shapes. For now, log which slots differ (up to 5) so the next session has data.

## Tasks
1. **Server fixes (TDD):**
   - `applyValues` rejects list entries that aren't strings or numbers, and rejects non-list values for list keys.
   - Settings replies echo the request `id`.
   - `pushPanel` in the tick is wrapped in `pcall`.
   - The panel keeps the case of the `start <name>` argument, and replies "Not available from the panel" when a command isn't allowed.
   - `matchPlayer` treats `=name` as an exact player name (so players named next, again or random can be picked).
   - `/cnr auto off` sends `cnr_autoNext {}` so clients drop "Next round in".
   - The parts-change log names the differing slots.
2. **Client characterisation test (`tests/test_client.lua` + `tests/client_stubs.lua`):** GE stubs. It loads the extension and drives:
   - join
   - prep (cop), countdown, runnerGo, release, state, an AI penalty, roundEnd, top, leave
   It asserts on HUD payloads and server sends. New failing cases: AI crash once, `hudResult` cleared on leave, `cnr_autoNext` cancels next, `onMode` resets the panel.
3. **Client fixes:** make those tests pass. One `leaveServer()` serves all three leave hooks.
4. **Client split:**
   - New modules under `copsAndRobbers/`:
     - `inputs` (locks, reset hooks, vehicle patch)
     - `roads` (spawn spots, nearest road)
     - `vehicles` (pick, options, lights config)
     - `ai`
     - `geo` (Earth API, gps, stations, geo send)
     - `hudfeed` (HUD state, push, placement wiring)
   - The main file keeps round state, event handlers, the `onUpdate` orchestration and the exports.
   - The characterisation test stays green and `luajit -bl` compiles each file.
5. **Placement:** new placement format, slower polling once placed, layout copy reset on leave (`test_placement`).
6. **Vue:**
   - Panel: request ids, flush on unmount, the stepper snaps to the grid, preset-name collisions are sent as `start =name`.
   - Both apps use `rem` fonts. `app.json` css is in `em`.
7. **Docs:** FEATURES (prep row, lights, panel), README and TODO. Version 1.6.0 (client, server, info.json, tests).
8. **Final review (opus), fix pass, `make deploy`, ask to merge.**
