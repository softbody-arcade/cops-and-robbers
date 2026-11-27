# Manager/game split, step 1: server services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record event traces of scripted rounds, then move the manager's server services out of `server/CopsAndRobbers/main.lua` into `server/CopsAndRobbers/arcade/`, so the first 2.x step ships with nothing different for players and identical traces.

**Architecture:** Cops and Robbers splits along the seam in five 2.x steps (the roadmap below), each its own plan, release and playtest. This plan is step 1. It is a server-only refactor. Golden event traces, recorded from today's code before anything moves, gate every task: a task is done only when every trace still matches byte for byte. Manager services become modules under `arcade/`, required as `arcade.<name>`, with no module-level state: each stateful service is a `new()` factory that `main.lua` calls, so a hot reload of `main.lua` resets them exactly as it resets today's locals (probe 2: nested modules aren't rerun).

**Tech Stack:** Lua 5.3 (BeamMP Server 3.9.3), the existing `tests/run.lua` runner and the `test_main.lua` server boot.

**Spec:** [arcade manager design](https://github.com/softbody-arcade/arcade-base/blob/df1f2f3/docs/superpowers/specs/2026-11-27-arcade-manager-design.md) (arcade-base#1, approved 2026-11-27), with the probe results on [arcade-base#1](https://github.com/softbody-arcade/arcade-base/issues/1). Ticket: #69.

## Global Constraints

- Events keep their `cnr_` names and payloads through 2.x; no client file changes in this plan.
- Every golden trace from Task 1 matches after every task. A trace may only be re-recorded in Task 1; a mismatch later is a bug in the task, never a reason to update the golden.
- Players see, hear and feel nothing different; `config.json`, `data/leaderboard.json`, `data/build.json`, `data/colors.json` and `data/stations/<map>.json` keep their paths and formats.
- New server modules live in `server/CopsAndRobbers/arcade/` and are required as `arcade.<name>`. A module keeps no state at module level; services with state are created with `new(...)`.
- Server Lua stays within Lua 5.3. The game half stays in `cnr.*`.
- No source comments. Version numbers stay out of this plan's commits.
- Local checks before each commit: `make test`. The packaged server copies `server/CopsAndRobbers` whole, so `arcade/` ships without Makefile changes; `make package` must still succeed at the end.

## The seam (binding for every 2.x step)

Concerns follow the spec's "Who owns what" table. During 2.x the manager half lives in `arcade.*` (server) and, from step 3, in the client's manager extension; the game half in `cnr.*` and the game extension. At 3.0.0 the `arcade.*` code moves to arcade-base mostly as files.

**Server**

| Manager (`arcade.*`) | Game (`cnr.*`) |
|---|---|
| JSON file store (`readFile`, `writeFile`, `decodeFile`, move-aside) | Evolving build store `build.json` and its rules (`cnr.build`, `cnr_setup`, `cnr_change`, `cnr_missing`) |
| Messages (`send`, `notify`, `broadcast`, `reply` with the panel mirror) | Round state machine `cnr.round` and every effect kind it emits |
| Roster: player keys, sit out, per-player state cleared on leave | Roles, runner choice (`cnr.commands.eligibleNext`, `matchPlayer`), run counts |
| Player colours (`colors.json`, `cnr_color`, `cnr_myColor`) | Catch, crash, resets, sight, helicopter (`cnr.catch`, `cnr.crash`, `cnr.resets`, `cnr.sight`, `cnr.helicopter`) |
| Settings: global declaration, the generic validator, `config.json` load and save, `setValue`, `applyValues` | Its settings declaration (`cnr.config`) and the panel's game helpers (`cnr.panel`) |
| Round conditions: `sky`, `weather`, `climate`, `strikeSchedule`, lightning announcements and the strike clock | Which weather grounds the helicopter (`cnr.groundingWeather`, and `groundedAt` moved to `cnr.grounding`) |
| Traffic: `perPlayer`, open, reported cars, extra-car counts | The traffic note text and "runner only" (`cnr.traffic.note`, `trafficRunnerOnly`) |
| Leaderboard store: load, format check, move-aside, save, add; board subscriptions (`cnr_board`, `cnr_boardState`) | Leaderboard views (`cnr.leaderboard` views, `boardState`), `cnr_top` |
| Panel plumbing: subscribers, push on change, lobby push, command registry; automatic rounds (`auto`, `next`) and `reload` | Round commands: `start`, `test`, `go`, `stop`, `end`, `reroll`, `sky`, `addstation`, `removestation`; the panel's build and apply actions |
| Step 2: the cycle (lobby, round, results), spectating and parked bystanders, car tools and the round-vehicle list, vehicle callbacks asking the game | Step 2: answers to vehicle checks, minimum players, the game manifest |
| Step 5: session and sequence numbers, `pcall` around game calls, cleanup without the game | Step 5: lost-participant rules (lost cop leaves, lost runner ends the chase) |

Global settings: `timeOfDay`, `nightChancePercent`, `dayLength`, `weather`, `badWeatherChancePercent`, `weatherDriving`, `weatherChanges`, `weatherChangeMinMinutes`, `weatherChangeMaxMinutes`, `lightningMinSeconds`, `lightningMaxSeconds`, `trafficPerPlayer`, `autoNextRound`, `autoNextDelaySeconds`, `includeModVehicles`, `excludedModels`. Every other key in `cnr/config.lua` is the game's.

**Client (step 3; listed now as the spec asks)**

| Side effect today | Goes to |
|---|---|
| Environment state, time, date (`sky.lua`), rain and its sound (`rain.lua`), ground grip (`surfaces.lua`), wind and `setGroundWind` (`wind.lua`, `sky.lua`), lightning objects, bolts, flash and sounds (`lightning.lua`, `lightningScene.lua`, `strikes.lua`, `strikeClock.lua`), street-light index (`streetLights.lua`, read-only) | Manager round-condition services |
| Civilian traffic, its nametags and lights (`traffic.lua`) | Manager traffic service |
| Parked own cars and hitches while spectating (`spectator.lua`), camera cycling and seat (`be:enterVehicle`) | Manager spectating |
| Action-filter groups, reset hooks (`resetGameplay`, `spawn.teleportToLastRoad`), big-map teleport guard, recovery patch, spawn and edit locks (`inputs.lua`) | Manager input and spawn locks |
| Name-tag hiding and the minimap wrapper (`hiding.lua`) | Manager name tags; the game says whom to hide |
| App placement and layouts (`apps.lua`, `placement.lua`), `CnRHud`, `CnRPanel`, `CnRBoard` hooks, the route marker (`core_groundMarkers`) | Manager apps and HUD; the route is game content drawn through the manager |
| Round car spawn, replace, placement, freeze, paint and vehicle modes (`placeVehicle`, `modes.lua`) | Manager car tools |
| Own headlights at night (`ownLights.lua` headlight step) | Manager (global player setting) |
| AI practice cars (`ai.lua`) | Game, spawned and removed through the car tools |
| Helicopter light, van model and its `/temp/cnr` copies, rotor sound (`heli*.lua`, `beam.lua`) | Game objects created through the world-change registry |
| Light bar and siren signal (`lightbar.lua`, `ownLights.lightbarSignal`), explosion on catch | Game decorations and actions through the registry and car tools |
| Sight, ground sight, shelter, tunnels, visibility | Game |

Cleanup gaps the client step verifies first (from the inventory, not yet confirmed): a runner's light-bar signal isn't cleared at round end; the seat isn't returned after camera cycling; `isTraffic` is written on the own car; the recovery patch isn't removed from other cars; `surfaces.restore` doesn't call `be:setGroundModel` again.

**Player settings:** global: colour, auto headlights, hiding the HUD, lightning flashes. Cops and Robbers: siren, searchlight beam, helicopter sound, helicopter model, route to the runner.

**Reset scoring (step 5):** a reset scores only from the player's own report tagged with the round's session and sequence; the native callback confirms it. The server keeps counting native callbacks as a cross-check: a callback with no matching report is logged and added to the round timeline as an unreported reset, never scored.

## The 2.x steps

1. **Server services** (this plan): traces, then the manager's server services move to `arcade/`.
2. **Server contract**: `cnr.game` behind a game interface (manifest, settings declaration, round start, tick, player join and leave, vehicle checks, leaderboard views, panel actions); the cycle, spectating, car tools and vehicle callbacks move to `arcade/`; `main.lua` becomes wiring.
3. **Client split**: client traces first; a manager extension that loads the game extension; the world-change registry; the side-effect table above.
4. **Data-driven apps**: settings, HUD parts, announcements, How to play and leaderboard views as game data, apps keeping their ids.
5. **Sessions and failures**: session and sequence numbers, `pcall` around game calls, cleanup without the game, client-side errors as lost participants, tagged resets.

Each later step gets its own plan after the step before it is released, and its own sub-issue under #69.

## Review Focus

- A path the traces don't cover changes events or recipients: disconnect during picking, the AI-setup deadline cancel, a locked leaderboard, a corrupt `config.json`. Expected: identical messages and logs to before.
- `config.json` round trip: saving from the panel or `/cnr auto` keeps unknown, retired and game keys exactly as before, now that two declarations validate it.
- Hot reload: touching `main.lua` resets every service, as today; no `arcade.*` module keeps state at module level.
- Disconnect: every per-player table is still cleared, in the same order relative to the round's `playerLeft`.
- Validation warnings keep their text and order for any mix of global and game keys.

---

### Task 1: Golden event traces

**Files:**
- Create: `tests/server_boot.lua` (moved from `tests/test_main.lua`: `encode`, `decodeJson`, `boot` and the `env` helpers it defines)
- Modify: `tests/test_main.lua` (top: `dofile("tests/server_boot.lua")`; the moved code removed)
- Create: `tests/trace.lua`, `tests/test_traces.lua`, `tests/traces/<scenario>.txt`

**Interfaces:**
- Produces: `traceRun(scenario) -> string` in `tests/trace.lua`; the golden files; `UPDATE_TRACES=1` re-records them.

- [ ] **Step 1:** Move `encode`, `decodeJson` and `boot` with its `env` helpers into `tests/server_boot.lua` unchanged, `dofile` it from `test_main.lua`. Run `lua tests/run.lua tests/test_main.lua`. Expected: `238 passed, 0 failed`.
- [ ] **Step 2: Write the trace format test** in `tests/test_traces.lua`: `traceLine({ t = 1.25, to = 2, ev = "cnr_notice", data = '{"tone":"info","msg":"x"}' })` returns `1.250 2 cnr_notice {"msg":"x","tone":"info"}`: clock with three decimals, recipient, event, payload re-encoded with keys sorted at every depth.
- [ ] **Step 3: Run it.** Expected: FAIL, `traceLine` is nil.
- [ ] **Step 4: Implement `tests/trace.lua`:** `traceLine(entry)`; `traceRun(scenario)` boots with `boot(scenario.boot)`, sets `os.time` to return `1795000000` and `math.randomseed(1)` before the scenario's steps, runs `scenario.steps(env)`, restores `os.time`, returns every `env.sent` entry as a line plus every `env.logs` line prefixed `log `, joined by `\n`, with `env.dir` replaced by `<dir>` and `CNR_VERSION` by `<version>` everywhere, so a release's version bump or a new temp folder never changes a trace. `traceCheck(name, scenario)` compares with `tests/traces/<name>.txt` and fails naming the first differing line; with `UPDATE_TRACES=1` it writes the file.
- [ ] **Step 5: Write the scenarios** in `tests/test_traces.lua`, each built from the event sequences the existing `test_main.lua` tests already use:
  - `lobby`: two players join; one opens the panel, saves `headStartSeconds = 9`, opens the board and filters to `all`.
  - `round_caught`: a full round from `start` to a catch, with sight reports and the result pushed to the board.
  - `round_escaped`: `roundTimeLimitSeconds = 30`, the runner survives.
  - `late_joiner`: a third player joins during the chase and spectates; then the runner disconnects.
  - `practice_runner` and `practice_watch_ai`: `test runner` and `test cop` while sitting out, with AI registration.
  - `evolving`: `carMode = evolving`, a queued change, apply, rebuild and a missing-parts report.
  - `auto_next`: `auto on`, a round ends, the next one starts by itself; then `auto off`.
  - `prep_actions`: `reroll`, `sky` and `stop` in preparation.
  - `vehicle_rules`: a spectator's spawn refused, a wrong model refused, traffic spawns within the allowance.
- [ ] **Step 6:** Run `UPDATE_TRACES=1 lua tests/run.lua tests/test_traces.lua`, then `lua tests/run.lua tests/test_traces.lua` twice. Expected: all pass, and the second run finds no difference (the traces are deterministic).
- [ ] **Step 7:** Run `make test`. Expected: all pass.
- [ ] **Step 8: Commit** `Traces: golden event traces of scripted rounds`.

### Task 2: File store

**Files:**
- Create: `server/CopsAndRobbers/arcade/store.lua`, `tests/test_arcade_store.lua`
- Modify: `server/CopsAndRobbers/main.lua` (`readFile`, `writeFile`, `decodeFile` at 73-96 removed; callers use the store)

**Interfaces:**
- Produces: `store.read(path) -> string|nil`; `store.write(path, content)` (writes `path .. ".tmp"`, `FS.Remove(path)`, `FS.Rename(tmp, path)`); `store.decode(path) -> table|nil, corrupt: boolean` (empty or missing: `nil, false`; not JSON or not a table: `nil, true`).

- [ ] **Step 1: Write the failing tests:** in a temp directory with `Util` and `FS` fakes from `server_boot.lua`: `store.decode` of a missing file is `nil, false`; of `"[1"` is `nil, true`; of `'{"a":1}'` is `{ a = 1 }, false`; `store.write` then `store.read` returns the content and leaves no `.tmp` file.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_store.lua`. Expected: FAIL, module `arcade.store` not found.
- [ ] **Step 3: Implement** by moving the three functions from `main.lua`; `main.lua` requires `arcade.store` and calls it.
- [ ] **Step 4: Run** the store test, then `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.store: the JSON file store`.

### Task 3: Messages

**Files:**
- Create: `server/CopsAndRobbers/arcade/messages.lua`, `tests/test_arcade_messages.lua`
- Modify: `main.lua` (`log`, `send`, `notify`, `reply`, `refuse`, `broadcast`, `panelMirror` and the three `panelMirror = pid … pcall … panelMirror = nil` blocks in `cnrOnPanel`)

**Interfaces:**
- Produces: `messages.new({ prefix = "[CnR] " }) -> m` with `m.log(text)`, `m.send(pid, event, payload) -> engine result` (ignores a pid that isn't a number, or is below 0 and not -1), `m.notify(pid, text, tone)` (`cnr_notice`, tone defaults to `"info"`), `m.broadcast(text, tone)`, `m.reply(pid, text, tone)` (`cnr_panelReply { text, tone }` while `pid` is the mirror, else `notify`), `m.refuse(pid, text)` (`reply` with `"warn"`), `m.mirrored(pid, fn, ...) -> ok, err` (sets the mirror, `pcall`s `fn`, clears the mirror).

- [ ] **Step 1: Write the failing tests** with a recording `MP.TriggerClientEvent`: `send(-2, …)` and `send("1", …)` send nothing; `notify(3, "hi")` sends `cnr_notice` with `tone = "info"`; inside `mirrored(3, fn)` a `reply(3, "x")` sends `cnr_panelReply`, and after it the same call sends `cnr_notice`; an error in `fn` is returned and the mirror is cleared.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_messages.lua`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua` to `m.*`; `cnrOnPanel` keeps rethrowing with `error(err, 0)` after `pushPanel()`, as now.
- [ ] **Step 4: Run** the test and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.messages: sending, notices and panel replies`.

### Task 4: Roster

**Files:**
- Create: `server/CopsAndRobbers/arcade/roster.lua`, `tests/test_arcade_roster.lua`
- Modify: `main.lua` (`playerKey` 226, `pidForKey` 234, `playing` 250, `sitOut`, `cnrOnSitOut` body, `cnrOnPlayerDisconnect`, and every per-player table that disconnect clears)

**Interfaces:**
- Produces: `roster.new() -> r` with `r:key(pid) -> string` (`"beammp:<id>"` from `MP.GetPlayerIdentifiers`, else `"name:<name>"`), `r:pidForKey(key) -> pid|nil`, `r:setSitOut(pid, on)`, `r:sittingOut(pid) -> boolean`, `r:playing(players) -> list, count`, `r:perPlayer(name, group) -> table` (`group` is `"early"` or `"late"`; the same table is returned for a name every time), `r:clear(name)` (empties that table in place), `r:leaveEarly(pid)`, `r:leaveLate(pid)`.
- `cnrOnPlayerDisconnect` becomes: `r:leaveEarly(pid)`, the round's `playerLeft`, `r:leaveLate(pid)`, `pushRoundCars()`. Early: `connectionSerial`, `gridClients`, `stationsRequested`, `refusalLoggedAt`, `sitOut`, `parkedBystanders`, `panelSubs`, `boardSubs`. Late: `activeVid`, `registeredRoundCar`, `allowRoundSpawn`, `preRoundVehicles`, `trafficOpen`, `trafficVids`.
- Every `x = {}` reset of these tables in `main.lua` (round end at 653-660, `handlers.start` 804-808, `handlers.test` 817-821) becomes `r:clear("x")`.

- [ ] **Step 1: Write the failing tests:** keys for a player with and without a BeamMP id; `pidForKey` finds the current pid; `playing` leaves out sitting-out players and counts the rest; `leaveEarly` clears only early tables and `leaveLate` only late ones; `clear` keeps the table's identity; two rosters share no state.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_roster.lua`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua`.
- [ ] **Step 4: Run** the test and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.roster: player keys, sit out and per-player state`.

### Task 5: Player colours

**Files:**
- Move: `server/CopsAndRobbers/cnr/colors.lua` to `server/CopsAndRobbers/arcade/colors.lua` (`git mv`; `tests/test_colors.lua` requires `arcade.colors`)
- Create: `server/CopsAndRobbers/arcade/playerColors.lua`, `tests/test_arcade_player_colors.lua`
- Modify: `main.lua` (`loadColors`, `saveColors`, `colorTable`, `colorFor`, `sendMyColor`, `cnrOnColor` body)

**Interfaces:**
- Consumes: `arcade.store`, `arcade.roster`, `arcade.messages`.
- Produces: `playerColors.new(path, r, m) -> c` with `c:load()`, `c:get(pid) -> { hex, r, g, b }|nil` (by key, then by name, as `colorFor`), `c:set(pid, hex) -> ok, error`, `c:clear(pid)`, `c:sendMine(pid)` (`cnr_myColor { hex, error }`).

- [ ] **Step 1: Write the failing tests:** set then get by key; a name-keyed legacy entry is found; clearing removes the key and saves; an invalid hex returns the same error text `cnrOnColor` sends today.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement**, move `colors.lua`, switch `main.lua`; `cnrOnColor` keeps sending `cnr_paint` during preparation.
- [ ] **Step 4: Run** the test and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.playerColors: player colours`.

### Task 6: Settings declarations

**Files:**
- Create: `server/CopsAndRobbers/arcade/settings.lua`, `tests/test_arcade_settings.lua`
- Modify: `server/CopsAndRobbers/cnr/config.lua` (keeps only the game's keys and their rules), `server/CopsAndRobbers/cnr/panel.lua` (`applyValues` moves out), `main.lua` (`loadConfig`, `handlers.auto`, `panelSettings`), `tests/test_config.lua`, `tests/test_panel.lua`

**Interfaces:**
- A declaration is `{ DEFAULTS, CHOICES, POSITIVE, MAXIMA, WHOLE, RANGES, RETIRED_KEYS, RETIRED_VALUES, fix }`, the same rules `cnr/config.lua` applies today (`RANGES` is today's `TIMING_RANGES`; `fix(cfg, warnings)` is today's `copSpawnMaxMeters` correction and stays in `cnr/config.lua`).
- Produces: `settings.GLOBAL` (the declaration for the global keys listed in the seam, with their current defaults, choices and rules), `settings.combine(global, game) -> decl` (keys must not overlap: an overlap is an `error`), `settings.merge(raw, decl) -> cfg, warnings`, `settings.setValue(raw, key, text, decl) -> raw`, `settings.applyValues(raw, values, decl) -> raw|nil, keys|error`, `settings.defaults(decl) -> table`.
- `cnr.config` keeps `DEFAULTS`, `CHOICES`, `TIMING_RANGES` names for the game keys only; `main.lua` builds `decl = settings.combine(settings.GLOBAL, config)` once and uses it everywhere `config.merge`, `config.setValue`, `config.DEFAULTS` and `panel.applyValues` are used now.

- [ ] **Step 1: Write the failing tests:** `settings.combine(settings.GLOBAL, config)` holds exactly today's keys with today's defaults (compare with a literal copy of today's `config.DEFAULTS` in the test); combining two declarations that share a key errors; `merge` of `{ lightningMinSeconds = 30, lightningMaxSeconds = 20, copSpawnMinMeters = 200, copSpawnMaxMeters = 100, clockSpeed = 2, weather = "map" }` gives the same `cfg` and the same warnings, in the same order, as today's `config.merge` (record today's result in the test first, before changing `config.lua`).
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_settings.lua`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement:** the validator moves from `cnr/config.lua` to `arcade/settings.lua`; global keys and their rules move into `settings.GLOBAL`; `applyValues` moves from `cnr/panel.lua`.
- [ ] **Step 4: Run** the settings test, `tests/test_config.lua`, `tests/test_panel.lua`, then `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.settings: global and game declarations`.

### Task 7: Round conditions

**Files:**
- Move (`git mv`): `cnr/sky.lua`, `cnr/weather.lua`, `cnr/climate.lua`, `cnr/strikeSchedule.lua` to `arcade/`; their tests (`test_sky.lua`, `test_weather.lua`, `test_climate.lua`) require `arcade.*`
- Create: `server/CopsAndRobbers/cnr/grounding.lua`, `server/CopsAndRobbers/arcade/lightning.lua`, `tests/test_grounding.lua`, `tests/test_arcade_lightning.lua`
- Modify: `cnr/round.lua` (430, 466), `main.lua` (`announceLightning` 407, `cnrOnLightningClock` 1379, the timer at 618)

**Interfaces:**
- `weather.groundedAt` leaves `arcade.weather`; `grounding.at(s, t) -> boolean` in `cnr/grounding.lua` returns `require("cnr.groundingWeather")[weather.at(s, t)] == true`. `arcade.weather` no longer requires `cnr.groundingWeather`.
- `arcade.sky` reads choices from `settings.GLOBAL` instead of `cnr.config`.
- Produces: `lightning.new(m) -> l` with `l:announce(sky, focusCar, to)` (today's `announceLightning`, sending `cnr_lightningPositions`), `l:clock(pid, sky, data)` (today's `cnrOnLightningClock` reply), `l:startTimer(sky)` (today's `MP.CreateTimer` at 618).

- [ ] **Step 1: Write the failing tests:** `grounding.at` is true for `storm`, `fog`, `snow`, `thunderstorm` and false for `clear` at a time inside each weather's window; `arcade.weather` loads without `cnr.groundingWeather` on `package.path`; `lightning:clock` answers `{ seed, id, elapsed }` only for the current seed.
- [ ] **Step 2: Run** both tests. Expected: FAIL, modules not found.
- [ ] **Step 3: Implement** the moves and the two modules; switch `round.lua` and `main.lua`.
- [ ] **Step 4: Run** the new tests, `test_sky.lua`, `test_weather.lua`, `test_climate.lua`, `test_round.lua`, then `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade conditions: sky, weather, climate and lightning`.

### Task 8: Traffic

**Files:**
- Create: `server/CopsAndRobbers/arcade/traffic.lua`, `tests/test_arcade_traffic.lua`
- Modify: `cnr/traffic.lua` (keeps `note`; `perPlayer` moves), `tests/test_traffic.lua`, `main.lua` (`maxCars` 315, `trafficFor` 321, `openTraffic` 326, `extraCars` 334, `trafficCars` 431, `cnrOnTrafficCars` 1472)

**Interfaces:**
- Consumes: `arcade.roster` (`trafficOpen`, `trafficVids` stay roster tables, late group), `arcade.messages`.
- Produces: `traffic.perPlayer(setting, maxCars, practice) -> number` (moved unchanged), `traffic.maxCars() -> number|nil`, `traffic.new(r, m) -> t` with `t:allowance(pid, cfg, practice, eligible) -> number` (0 when `eligible` is false; the game passes `not runnerOnly or pid == runner`), `t:open(pid, count)` (`cnr_trafficStart { count }`), `t:isOpen(pid)`, `t:report(pid, vids, ownVid, isAI) -> nil` (today's `cnrOnTrafficCars` cap and exclusions), `t:extraCars(pid, ownVid) -> number`, `t:cars() -> list` (today's `trafficCars`).

- [ ] **Step 1: Write the failing tests:** `allowance` is 0 when not eligible and `perPlayer(...)` otherwise; `report` keeps at most the open count and skips the own and AI vids; `extraCars` counts the player's vehicles other than the own one.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua`; the runner-only rule stays in `main.lua` as the `eligible` argument.
- [ ] **Step 4: Run** the test, `test_traffic.lua` and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.traffic: traffic allowance and reported cars`.

### Task 9: Leaderboard store and board subscriptions

**Files:**
- Create: `server/CopsAndRobbers/arcade/records.lua`, `tests/test_arcade_records.lua`
- Modify: `main.lua` (`loadLeaderboard` 148, `saveLeaderboard` 209, `sendBoard` 502, `pushBoard` 507, `cnrOnBoard` 1534, `leaderboardLocked`, `boardSubs`)

**Interfaces:**
- Consumes: `arcade.store`, `arcade.messages`, `arcade.roster` (`boardSubs`, early group).
- Produces: `records.new({ dir, file = "leaderboard.json", isCurrent, empty, legacyName = "leaderboard-1.6" }, m) -> s` with `s:load() -> board` (today's move-aside rules for a corrupt or old-format file and the locked flag), `s:save(board)` (no write while locked), `s:open(pid, sub)`, `s:close(pid)`, `s:filter(pid, sub)`, `s:more(pid)`, `s:push(view)` and `s:sendTo(pid, view)`, where `view(sub) -> payload` is the game's `boardState` and the event stays `cnr_boardState`. The `cnr_board` action parsing (`open`, `filter`, `more`, `close`) moves into `s:handle(pid, msg, view)`.

- [ ] **Step 1: Write the failing tests:** a corrupt file is moved to `leaderboard.json.corrupt-<time>` and an empty board returned; an old-format file goes to `leaderboard-1.6.json`, or `leaderboard-1.6-<time>.json` when that exists; a failed move locks saving; `handle` with `open` then `more` sends two `cnr_boardState` with the subscription's `rounds` grown by 30, capped at 300.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua`; `boardState` stays in `main.lua` as the view.
- [ ] **Step 4: Run** the test, `test_leaderboard.lua` and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.records: the leaderboard store and board subscriptions`.

### Task 10: Panel plumbing, lobby and automatic rounds

**Files:**
- Create: `server/CopsAndRobbers/arcade/panel.lua`, `server/CopsAndRobbers/arcade/autoRounds.lua`, `tests/test_arcade_panel.lua`, `tests/test_arcade_auto_rounds.lua`
- Modify: `main.lua` (`pushPanel` 1009, `pushLobby` 842, `runCommand` 939, `handlers.auto` 852, `handlers.next` 871, `handlers.reload` 930, `startAutoRound` 1593, `autoNextAt`, the panel and lobby part of `cnrTick` 1606-1613)

**Interfaces:**
- Consumes: `arcade.messages`, `arcade.roster` (`panelSubs`, early group), `arcade.settings`.
- Produces: `panel.new(m, r) -> p` with `p:open(pid, state)`, `p:close(pid)`, `p:push(stateFn)` (sends `cnr_panelState` to subscribers only when `cnr.panel.signature` changes), `p:pushLobby(stateFn, pid)` (`cnr_lobby`, same signature rule), `p:command(name, handler)`, `p:run(pid, text)` (today's `runCommand`), `p:tick(panelStateFn, lobbyStateFn)` (today's two `pcall`s and their once-per-change error logs).
- Produces: `autoRounds.new() -> a` with `a:schedule(at)`, `a:cancel()`, `a:pending() -> at|nil`, `a:due(now) -> boolean`. The `auto`, `next` and `reload` commands register from `main.lua` through `p:command`, keeping today's replies; the game's commands register the same way.

- [ ] **Step 1: Write the failing tests:** `push` sends nothing when the state's signature is unchanged and sends to every subscriber when it changes; `open` always sends to the opener; a failing state function logs once until its error changes; `run` dispatches `start next` to the `start` handler with `args = { "next" }`; `due` is true only at or after the scheduled time and `cancel` clears it.
- [ ] **Step 2: Run** both tests. Expected: FAIL, modules not found.
- [ ] **Step 3: Implement** and switch `main.lua`.
- [ ] **Step 4: Run** the tests and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.panel and arcade.autoRounds: panel plumbing and automatic rounds`.

### Task 11: Step 1 wrap-up

**Files:**
- Modify: `docs/DEPENDENCIES.md` (the `arcade/` folder and what moved, one short section), `tests/test_traces.lua` (no change expected)

- [ ] **Step 1:** Check that `main.lua` no longer defines any function listed as manager in the seam's step 1 rows: `grep -n 'local function \(readFile\|writeFile\|decodeFile\|send\|notify\|playerKey\|pidForKey\|playing\|loadColors\|saveColors\|maxCars\|openTraffic\|extraCars\|trafficCars\|loadLeaderboard\|saveLeaderboard\|sendBoard\|pushBoard\|pushPanel\|pushLobby\|runCommand\|announceLightning\)' server/CopsAndRobbers/main.lua`. Expected: no output.
- [ ] **Step 2:** Check no `arcade.*` module requires `cnr.*`: `grep -rn 'require("cnr\.' server/CopsAndRobbers/arcade/`. Expected: no output.
- [ ] **Step 3:** Run `make test` and `make package`. Expected: all pass; `dist/Server/CopsAndRobbers/arcade/` exists.
- [ ] **Step 4:** Update `docs/DEPENDENCIES.md` and commit `Docs: the arcade folder`.
- [ ] **Step 5:** Playtest request on the PR (label `needs-playtest`), for the maintainer on the local test server: a full round with a catch; a practice round as runner; a late joiner spectating; saving a setting in the panel; the leaderboard's Rounds tab; automatic rounds on, one round, off. Pass: nothing differs from the release before. Uncertainty resolved: the extraction changes nothing BeamMP or the client observes beyond what the traces record.
