# Evolving Car Mode and UI-only Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Release 1.8.0:
- Only the apps control the mod (five chat commands remain, no key bindings).
- Paint goes only through `/cnr color`.
- A new evolving car mode: a shared build that the runner changes once per round, with everyone seeing the change queued in the HUD. Apply rebuilds every car, then GO.

**Architecture:**
- **Server:** a pure `cnr/build.lua` holds the build and applies changes.
- **Round:** `round.lua` gains an evolving path (no picking, prep → applying → ready → countdown).
- **Wiring:** `main.lua` connects it to the panel, persistence (`data/build.json`) and new client events.
- **Client:** the runner's game is the source of truth. It snapshots what the build resolves to on its own game, diffs the live car against that every second, and on Apply sends its exact setup. Everyone's car is rebuilt from the config table, the same path cop lights already use.

**Tech Stack:** Lua 5.3 server, LuaJIT client, Vue 3 apps, `make test` (stock lua; `tests/test_client.lua` runs the real client on stubs).

**Spec:** `docs/superpowers/specs/2026-11-15-evolving-car-design.md`

## Global Constraints
- **Chat commands kept:** `color`, `addstation`, `removestation`, `help` and `version`. Any other `/cnr …` command replies "Use the Cops and Robbers Panel (Esc > UI Apps)". Key bindings are removed.
- **Settings:** `carMode` is `"random"` (default) or `"evolving"`. The apply ready timeout is **20 s**. Apply with no change keeps the step the same.
- **The build:** saved as `data/build.json` = `{model, name, parts, vars, step, startedFrom, startedAt, history = [{step, by, at, changes}]}`. It is written atomically. Reset and New build first move the old one to `data/build-<time>.json`.
- **New builds:** only from server-provided `.pc` configs (official ones, or ones from mods under `mods/multiplayer`), filtered like the random pick. Format-2 `.pc` files only.
- **Paint:** only through `/cnr color`, in both modes. Prep closes the parts menu for everyone, except the runner in evolving mode until Apply. Paint and livery (`paint_design` slots) are never part of the build.
- **Copy:**
  - HUD title "BOB'S CHANGE (2)", "BOB'S CHANGE: none yet", "+N more", "⚠ missing: <id>"
  - banner "APPLYING CHANGES" with "N/M ready"
  - panel "Start a new build first", "Apply the change first", "Apply change", "Reload config.json"
  - prep line "set your color with /cnr color"
  - chat "Change 7 by Bob: Engine 4.5L V8 → 6.0L V8 (+1 more)"
- **Reading the runner's setup:** `core_vehicle_manager.getPlayerVehicleData().config` holds `partsTree` and `vars`. Parts come from `core_vehicle_partmgmt.partsTreeToPartsMap(config.partsTree)`, or `config.parts` when present. This is the same conversion the game's own config save uses.
- **Don't deploy** until the user says the server is empty. Version **1.8.0**.

## Review Focus
1. **The build file is broken or missing at startup:** the server logs "no build" and keeps running. Evolving mode asks for a new build, and the bad file is moved aside. Test in Task 3.
2. **The runner leaves during prep or while applying:** the round cancels or ends as today, and the build is unchanged. Test in Task 4.
3. **A player never reports ready while applying:** after 20 s the round moves to ready anyway. Test in Task 4.
4. **The runner's snapshot equals his live car:** "none yet" is shown, and Apply keeps the step. Defaults resolved by the game must not show up as changes. Test in Task 6.
5. **The leaderboard mode filter:** older runs with no `mode` count as random. Test in Task 8.

---

### Task 1: UI-only controls
**Files:**
- `server/CopsAndRobbers/main.lua`: the chat handler, `HELP`, `cnrOnCommand` plus its RegisterEvent, the `reload` text, and texts containing `"/cnr`.
- `cnr/panel.lua`: `BINDABLE` becomes the panel's allowed list, plus `reload`.
- `cnr/round.lua`: texts.
- The client: delete `client/lua/ge/extensions/core/input/actions/copsAndRobbers.json`. In `copsAndRobbers.lua` remove `M.command`, `refreshActions` and `ACTIONS_FILE`, and change the prep toast text.
- Panel `app.vue`: add a "Reload config.json" button to the Settings tab that sends the command `reload`.
- `tests/test_main.lua`, `tests/test_round.lua` and `tests/test_client.lua`: update the tests that used chat commands or `cnr_command` so they use `env.call("cnr_panel", pid, '{"action":"command","text":...}')`. Add a helper `env.panel(pid, text)`.

**Tests (new):**
- `/cnr go` in chat → the reply contains "Use the Cops and Robbers Panel", and nothing starts.
- `/cnr color #ff0000` and `/cnr help` still work. The help text lists only the five commands.
- `cnr_command` is no longer registered.
- The panel command `reload` reloads, and is refused during a round.
- No server or client text sent to players contains `"/cnr go"`, `"/cnr start"` or `"/cnr auto"`. The test greps the source files for those literals.

### Task 2: paint lock and parts menu policy (client)
**Files:** `copsAndRobbers.lua` (`onRoundSetup`, `onCountdown`) and `copsAndRobbers/inputs.lua`. `tests/client_stubs.lua` records `core_input_actionFilter.addAction(…, "cnr_parts", blocked)` into `env.partsBlocked`.

**Produces:** `onRoundSetup` sets the parts menu to `allowed = (d.phase == "prep" and d.evolving == true and role == "runner")`. The prep text becomes "You are the runner/cop, set your color with /cnr color, waiting for GO".

**Tests:**
- Random-mode prep: the parts menu is blocked for both runner and cop.
- Evolving prep: open for the runner, blocked for a cop.
- Countdown: blocked.

### Task 3: build model and persistence (server)
**Files:** create `server/CopsAndRobbers/cnr/build.lua` and `tests/test_build.lua`. In `main.lua`: `loadBuild`/`saveBuild`/`backupBuild`, plus `carMode` in `config.lua` DEFAULTS (string; `merge` accepts only `"random"`/`"evolving"`).

**Produces:**
- `build.new(model, name, parts, vars, startedFrom, now) -> build` (step 0)
- `build.valid(t) -> bool`: model is a string, `parts` is a table of string→string, `vars` is a table.
- `build.apply(b, setup, changes, by, now) -> newBuild, changed`: if `setup` parts and vars equal `b`'s, return `b, false`. Otherwise step + 1, parts and vars come from the setup, and a history entry `{step, by, at, changes}` is added.
- `build.label(b) -> "Gavril D-Series · change 7"`: the name comes from `b.name`.
- `build.changeLine(step, by, changes) -> "Change 7 by Bob: Engine 4.5L V8 → 6.0L V8 (+1 more)"`: each change is `{label, from, to}`.

**Tests:**
- `new`, `valid` (rejects missing model, parts with non-string values)
- `apply` changed and unchanged
- the `label` format
- `changeLine` with 1 and 3 changes
- `config.merge({carMode = "x"})` warns and falls back to `"random"`
- **main:**
  - a corrupt `build.json` is moved aside and there's no build (Review Focus 1)
  - a saved build survives a reboot (`boot` reads it)

### Task 4: round evolving flow (server, pure)
**Files:** `cnr/round.lua` and `tests/test_round.lua`.

**Produces:**
- `Round:start(now, runnerId, issuerId, players, opts)`, where `opts.build = {model, config = <table>, step, name}`. It skips picking and goes straight to `prep`, with `self.evolving = true`. The setup effects carry `config` as the table and `evolving = true`.
- `Round:apply(now, pid)`:
  - only in `prep` when evolving, otherwise it replies "Not in evolving prep"
  - sets `state = "applying"`
  - emits `{kind="requestSetup", pid=runnerId}`
- `Round:setupReceived(now, pid, newConfig)`:
  - only from the runner while applying
  - sets `self.vehicle.config = newConfig`
  - emits `{kind="rebuild", config=newConfig}`
  - `self.readyPids = {}`, `self.applyStartedAt = now`
- `Round:vehicleReady(now, pid)`: marks a pid ready. Once all non-AI players are ready, `state = "ready"` and it emits `{kind="applied"}`.
- `Round:tick`:
  - in `applying`, after 20 s from `applyStartedAt`, goes to `ready` and emits `applied` with `timedOut = true`
  - in `applying` without a `setupReceived` within 20 s, also goes to `ready`, and the build stays as it was
- `Round:go`: in evolving mode it's allowed only from `ready`. From `prep` it replies "Apply the change first".
- `Round:reroll`: refused in evolving mode ("New car isn't available in evolving mode").
- The record gets `mode = self.evolving and "evolving" or "random"`, plus `buildStep`/`buildName` from `opts.build`.

**Tests:**
- the evolving start skips picking
- apply → requestSetup → setupReceived → rebuild
- all ready → applied
- the timeout at 20 s
- go refused from prep and allowed from ready
- reroll refused
- the runner leaving while applying finishes or cancels as today (Review Focus 2)
- the record has its mode and step

### Task 5: server wiring
**Files:** `main.lua` and `tests/test_main.lua`.

**Panel actions:**
- `{action="build", op="new", model, name, parts, vars}`: refused during a round. It backs up the current build, then saves `build.new`, replies "New build: <label>" and pushes the panel.
- `{action="build", op="reset"}`: refused during a round. It backs up the build, clears it and replies "Build reset".
- `{action="apply"}` → `current:apply(now(), pid)`.

**Starting rounds:** `handlers.start`/`handlers.test` with `cfg.carMode == "evolving"`. With no build they reply "Start a new build first". Otherwise they pass `opts.build = {model, config = {format=2, model, parts, vars}, step, name}`.

**Practice rounds** (`current.test`) use the build like normal rounds, but `build.apply`/`saveBuild` is skipped for them. Test: a practice Apply rebuilds the cars and leaves `build.json` unchanged.

**Events:**
- `cnr_setup` (the runner's reply: `{model, parts, vars, changes}`):
  - `current:setupReceived(...)`
  - in the `rebuild` effect: `build.apply` → `saveBuild`
  - if it changed, broadcast `build.changeLine`
  - send `cnr_rebuild {model, config}` to every human player
- `cnr_myVehicle` also calls `current:vehicleReady`.
- `cnr_change` (from the runner during prep: `{changes}`) → forwarded to every human round player as `cnr_queued {runner, changes}`.
- `cnr_missing` (`{parts}`) → `cnr_notice` "⚠ <name> is missing: a, b" to everyone.

**Effects:** `requestSetup` → `send(runner, "cnr_requestSetup")`. `applied` → `cnr_notice` "Cars ready, press GO" (and "(timed out)" when it timed out).

**Other changes:**
- `vehicleAllowed`: in evolving mode it compares only `jbm == model` and skips the `.pc` filename check.
- Panel state adds:
  - `build = {label, step} | nil`
  - `carMode`
  - `can.apply = state == "prep" and evolving`
  - `can.go = (state == "prep" and not evolving) or state == "ready"`
  - `can.build = not active`
  - The phase labels gain `applying` and `ready`.
- The `record` effect keeps the run's `mode`, `buildStep` and `buildName`.

**Tests:**
- new build → saved and in the panel state
- reset backs up
- start without a build is refused
- the full evolving round over the wiring (prep → apply → `cnr_requestSetup` to the runner → `cnr_setup` → `cnr_rebuild` to all → ready via `cnr_myVehicle` → go)
- `cnr_change` is forwarded
- `cnr_missing` notice
- an evolving vehicle edit with a different `.pc` name is not refused

### Task 6: client build logic
**Files:**
- create `client/lua/ge/extensions/copsAndRobbers/build.lua` (pure)
- modify `vehicles.lua`: `copConfig` accepts a table, `M.currentSetup()`, `M.partName(model, id)`, `M.hasPart(model, id)`, `M.configList(opts)`
- `copsAndRobbers.lua`, `hudfeed.lua`, `hud.lua` and the HUD `app.vue`
- tests: `tests/test_client.lua` and `tests/test_build_client.lua`

**`copsAndRobbers/build.lua`:**
- `diff(baseline, current) -> {{slot, from, to}...}` and `varsDiff(baselineVars, currentVars) -> {{name, from, to}...}`.
  - Sorted by slot.
  - Slots containing `paint_design` are ignored.
  - `""`/nil means "(none)".
  - Equal maps give `{}`.
- `label(slot) -> "Engine"`: strip the model prefix up to the first `_` when it matches the model, turn `_` into spaces, capitalize the first letter.

**`vehicles.lua`:**
- `currentSetup() -> {model, parts, vars}` | nil, read from `core_vehicle_manager.getPlayerVehicleData()` (see Global Constraints). It drops every slot whose name contains `paint_design` (liveries are paint, never part of the build). On rebuild, those slots keep the build's own values.
- `partName(model, id)` → the jbeam `information.name`, or the id.
- `configList({includeMods, excludedModels})` → `{{model, name, config}}` from `core_vehicles.getConfigList(true).configs`:
  - `Source == "BeamNG - Official"`, or the pc's origin under `/mods/multiplayer/` (`FS:getFileOriginInfo(pc).archivePath`)
  - Car/Truck, not excluded, mods only with `includeMods`
  - format-2 `.pc` files only

**Client flow:**
- **Runner, evolving prep:** after the car is placed (`pendingPlacement` cleared + 1 s), snapshot `baseline = currentSetup()`.
- **Every 1 s:** diff the current car against `baseline`. When the list changed, `sendServer("cnr_change", {changes = list with labels and display names})`.
- **`cnr_requestSetup`:** reply `cnr_setup {model, parts, vars, changes}`.
- **`cnr_rebuild {model, config}`:** `roundConfig = copConfig(model, config)` for cops, otherwise the config itself. `placeVehicle` in place (current position, upright). Then check every part with `hasPart` and send `cnr_missing` with any that are missing. The parts menu closes.
- **`cnr_queued {runner, changes}`:** `hudfeed.queued(runner, changes)` → the HUD shows the change list in place of the prep line.
- **The `applying` phase** shows the banner "APPLYING CHANGES"; ready counts come via `cnr_notice`.
- **Repaint in evolving prep** (`cnr_paint`): the runner's repaint uses `currentSetup()` instead of `roundConfig`, so his queued change survives.

**HUD:** the payload gets `change = {title, lines = {{label, from, to}}, more}`. `app.vue` renders it in place of the prep row (at most 4 lines, then "+N more").

**Tests:**
- `diff`/`varsDiff`/`label` cases, including Review Focus 4 (equal → empty)
- the runner sends `cnr_change` only when it changes
- `cnr_requestSetup` → `cnr_setup` from a stubbed `getPlayerVehicleData` and `partsTreeToPartsMap`
- `cnr_rebuild` places the car and reports missing parts
- `cnr_queued` → the HUD change title "BOB'S CHANGE (2)"
- a repaint in evolving prep keeps the current setup

### Task 7: panel
**Files:**
- Panel `app.vue`.
- `copsAndRobbers.lua`: `M.configs(opts)` → `guihooks.trigger("CnRConfigs", vehicles.configList(opts))`, and `M.newBuildFrom(config)`, which reads the `.pc` with `jsonReadFile` and sends the panel action `build/new` with its parts and vars.

**Round tab:**
- An "Evolving car" switch, which saves `carMode` like the other settings and is disabled during a round.
- When evolving:
  - the build label, or "No build yet"
  - **New build: random** (picks a random entry from `configList`)
  - **Choose car ▾** (`BngDropdown` with `showSearch`, items `{value=config, label="Brand Model – Config"}`) with a **Start build** button
  - **Reset build**, which needs two clicks within 3 s
  - **Apply change** (`can.apply`)
- GO is disabled while `!can.go`. When evolving and in prep, its reason reads "Apply the change first".

**Settings tab:** add the **Reload config.json** button.

**Verify:** `node --check`, plus a client test that `M.configs` filters to official and multiplayer-mod configs.

### Task 8: leaderboard mode filter
**Files:** `cnr/leaderboard.lua`, `main.lua` (board filter `{map, mode}`), the leaderboard `app.vue`, and tests.

**Produces:**
- `runners`/`cops`/`players` take `filter = {map, mode}`, where `mode` is nil, `"random"` or `"evolving"`. A run with no `mode` counts as `"random"` (Review Focus 5).
- `cnr_board {action="filter", map, mode}`, with `boardState.mode` in the state.
- The app gets a second dropdown: All modes / Random / Evolving.

**Tests:** the mode filter; old runs count as random.

### Task 9: docs and version
- README and FEATURES:
  - add a Controls section: the panel, the leaderboard app and the five chat commands
  - remove the command table and the key-binding sections
  - document the evolving car mode and the paint rule
- `DEPENDENCIES.md`: add `core_vehicle_manager.getPlayerVehicleData`, `core_vehicle_partmgmt.partsTreeToPartsMap`, `FS:getFileOriginInfo`, and the parts menu as the only paint path.
- `TODO.md`: remove the evolving car item.
- Version 1.8.0 everywhere, and the test counts.

### Task 10: final review (opus), fix pass, then ask for deploy (server empty) and merge.
