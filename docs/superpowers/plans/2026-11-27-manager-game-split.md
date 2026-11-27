# Manager/game split, step 1: server services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record event traces of scripted rounds, then move the manager's first server services out of `server/CopsAndRobbers/main.lua` into `server/CopsAndRobbers/arcade/`, so the first 2.x step ships with nothing different for players and identical traces.

**Architecture:** Cops and Robbers splits along the seam in five 2.x steps (the roadmap below), each its own plan, release and playtest. This plan is step 1, a server-only refactor. Golden event traces, recorded from today's code before anything moves, gate every task: a task is done only when every trace still matches. Manager services become modules under `arcade/`, required as `arcade.<name>`, with no module-level state: each stateful service is a `new()` factory that `main.lua` calls, so a hot reload of `main.lua` resets them exactly as it resets today's locals (probe 2: only top-level files rerun; nested modules stay cached).

**Tech Stack:** Lua 5.3 (BeamMP Server 3.9.3; CI runs `lua5.3`), the existing `tests/run.lua` runner and the `test_main.lua` server boot.

**Spec:** arcade manager design, `docs/superpowers/specs/2026-11-27-arcade-manager-design.md` on arcade-base's `develop` (arcade-base#1, approved 2026-11-27), with the probe results on [arcade-base#1](https://github.com/softbody-arcade/arcade-base/issues/1). Ticket: #69.

## Global Constraints

- Events keep their `cnr_` names and payloads through 2.x; no client file changes in this plan.
- Every golden trace from Task 1 matches after every task. A golden may only be recorded in Task 1; a mismatch later is a bug in the task, never a reason to re-record.
- Players see, hear and feel nothing different; `config.json`, `data/leaderboard.json`, `data/build.json`, `data/colors.json` and `data/stations/<map>.json` keep their paths and formats.
- New server modules live in `server/CopsAndRobbers/arcade/` and are required as `arcade.<name>`. A module keeps no state at module level; services with state are created with `new(...)`. An `arcade.*` module never requires a `cnr.*` module; `cnr.*` may require `arcade.*`.
- Server Lua stays within Lua 5.3. No source comments. Version numbers stay out of this plan's commits.
- Local checks before each commit: `make test`. `make package` copies `server/CopsAndRobbers` excluding `data`, so `arcade/` ships without Makefile changes.

## The seam (binding for every 2.x step)

Concerns follow the spec's "Who owns what" table. During 2.x the manager half lives in `arcade.*` (server) and, from step 3, in the client's manager extension; the game half in `cnr.*` and the game extension. At 3.0.0 the manager code moves to arcade-base mostly as files.

**Server**

| Manager (`arcade.*`) | Game (`cnr.*`) | Step |
|---|---|---|
| JSON file store | Evolving build store `build.json` and its rules (`cnr.build`, `cnr_setup`, `cnr_change`, `cnr_missing`) | 1 |
| Messages (`send`, `notify`, `broadcast`, `reply` with the panel mirror) | Round state machine `cnr.round` and every effect kind it emits | 1 |
| Roster: player keys, sit out, per-player state cleared on leave | Roles, runner choice (`eligibleNext`, `matchPlayer`), run counts | 1 |
| Player colours (`colors.json`, `cnr_color`, `cnr_myColor`) | Catch, crash, resets, sight, helicopter | 1 |
| Settings: global declaration, validator, `config.json` load and save | Its declaration and overrides (`cnr.config`), the panel's game helpers (`cnr.panel`) | 1 |
| Traffic: `perPlayer`, open, reported cars, extra-car counts | The traffic note text and "runner only" | 1 |
| Panel plumbing, lobby push, command registry and parsing; automatic rounds (`auto`, `next`) and `reload` | Round commands: `start`, `test`, `go`, `stop`, `end`, `reroll`, `sky`, `addstation`, `removestation`; the panel's build and apply actions | 1 |
| The cycle (lobby, round, results), spectating and parked bystanders, car tools, the round-vehicle list, vehicle callbacks asking the game | Answers to vehicle checks, minimum players, the game manifest | 2 |
| Round conditions: `sky`, `weather`, `climate`, `strikeSchedule` (shared with the client through a symlink), lightning announcements and the strike clock; weather takes the round's release and end times as inputs instead of reading the game's countdown, head start and time limit | Which weather grounds the helicopter: `groundedAt` moves to the game unchanged, still returning a weather name or `nil`; a newly grounding weather takes effect at once, and a grounding weather persists for its 60-second transition only while clearing into a non-grounding one (`test_weather.lua`: fog to snow shows the new weather taking effect at once, storm to rain the previous one persisting for 60 seconds) | 3 |
| Leaderboard store (load with its shape and legacy checks, move-aside, lock, save, add) and per-viewer board subscriptions | Leaderboard views, computed per viewer | 4 |
| Session and sequence numbers, `pcall` around game calls, cleanup without the game | Lost-participant rules (a lost cop leaves, a lost runner ends the chase) | 5 |

Global settings: `timeOfDay`, `nightChancePercent`, `dayLength`, `weather`, `badWeatherChancePercent`, `weatherDriving`, `weatherChanges`, `weatherChangeMinMinutes`, `weatherChangeMaxMinutes`, `lightningMinSeconds`, `lightningMaxSeconds`, `trafficPerPlayer`, `autoNextRound`, `autoNextDelaySeconds`, `includeModVehicles`, `excludedModels`. Every other key in `cnr/config.lua` is the game's. A game may override a global setting's default through an explicit `OVERRIDES` table; declaring the same key twice is an error.

**Client (step 3; listed now as the spec asks)**

| Side effect today | Goes to |
|---|---|
| Environment state, time, date (`sky.lua`), rain and its sound (`rain.lua`), ground grip (`surfaces.lua`), wind and `setGroundWind`, lightning objects, bolts, flash and sounds (`lightning.lua`, `lightningScene.lua`, `strikes.lua`, `strikeClock.lua`), street-light index (`streetLights.lua`, read-only) | Manager round-condition services |
| Civilian traffic, its name tags, lights and freeze (`traffic.lua`) | Manager traffic service |
| Parked own cars and hitches while spectating (`spectator.lua`), camera cycling and the seat (`be:enterVehicle`) | Manager spectating |
| Action-filter groups, reset hooks (`resetGameplay`, `spawn.teleportToLastRoad`), big-map teleport guard, recovery patch, spawn and edit locks (`inputs.lua`) | Manager input and spawn locks |
| Name-tag hiding and the minimap wrapper (`hiding.lua`) | Manager name tags; the game says whom to hide |
| App placement and layouts (`apps.lua`, `placement.lua`), `CnRHud`, `CnRPanel`, `CnRBoard`, the route marker (`core_groundMarkers`) | Manager apps and HUD; the route is game content drawn through the manager |
| Round car spawn, replace, placement, freeze, paint, vehicle modes (`placeVehicle`, `modes.lua`, `settings/cnr_vehicle_modes.json`) | Manager car tools |
| Own headlights at night, and the periodic light-state sync to own and traffic cars | Manager (headlights are a global player setting) |
| AI practice cars (`ai.lua`) and the light sync to them | Game, spawned and removed through the car tools |
| Helicopter light, van model and its `/temp/cnr` copies, rotor sound (`heli*.lua`, `beam.lua`) | Game objects created through the world-change registry |
| Light bar and siren signal, explosion on catch | Game decorations and actions through the registry and car tools |
| Gas-station lookup (`freeroam_facilities`, `cnr_stations`) | Game map content |
| How to play seen flag (`settings/cnr_help_seen.json`) | Manager, per game |
| Event-handler registration and `package.loaded` cleanup on unload | Each extension its own; the manager's state (player preferences, help seen, app placements, vehicle modes) outlives unloading the game extension |
| Sight, ground sight, shelter, tunnels, visibility | Game |

Cleanup gaps step 3 verifies first (from a read-only inventory, not yet confirmed in game): a runner's light-bar signal isn't cleared at round end; the seat isn't returned after camera cycling; `isTraffic` is written on the own car; the recovery patch isn't removed from other cars.

**Player settings:** global: colour, auto headlights, hiding the HUD, lightning flashes. Cops and Robbers: siren, searchlight beam, helicopter sound, helicopter model, route to the runner.

**Reset scoring (step 5):** a reset scores only from the player's own report tagged with the round's session and sequence; the native callback confirms it. The server keeps counting native callbacks as a cross-check in its diagnostics only: a callback with no matching report is logged with a per-session counter, never added to a round's timeline or leaderboard record, so a late callback from one round can't appear in the next.

## The 2.x steps

1. **Server services** (this plan): traces, then store, messages, roster, colours, settings, traffic, panel plumbing and automatic rounds move to `arcade/`.
2. **Server contract**: `cnr.game` behind a game interface (manifest, settings declaration, round start, tick, join and leave, vehicle checks, panel actions); the cycle, spectating, car tools and vehicle callbacks move to `arcade/`; `main.lua` becomes wiring.
3. **Client split and round conditions**: client traces first; a manager extension that loads the game extension; the world-change registry; the client side-effect table; the round-condition modules move to the manager on both sides, the shared `strikeSchedule` symlink with them.
4. **Data-driven apps and the leaderboard store**: settings, HUD parts, announcements, How to play and per-viewer leaderboard views as game data; the leaderboard store moves to the manager.
5. **Sessions and failures**: session and sequence numbers, `pcall` around game calls, cleanup without the game, client errors as lost participants, tagged resets.

Each later step gets its own plan after the step before it is released, and its own sub-issue under #69. The traces from Task 1 stay the parity baseline through every step: steps 1 to 4 keep them unchanged; step 5 adds session and sequence fields and the reset report. Its plan replays the same scenarios through an adapter that tags each legitimate client input with the current session and sequence, compares the output with those new fields removed, and tests stale inputs and the new fields on their own.

## Review Focus

- A path the traces don't cover changes events or recipients: disconnect during picking, the AI-setup deadline cancel, a corrupt `config.json`. Expected: identical messages and logs to before.
- `config.json` round trip: a save drops retired keys and retired values, keeps unknown keys, and otherwise writes what it wrote before.
- Hot reload: loading `main.lua` a second time in the same process gives fresh services, the start-up messages again and one tick timer, with nothing kept from the first load.
- Disconnect: every per-player table is still cleared, in the same order relative to the round's `playerLeft`.
- Panel pushes: an opener gets exactly one copy, last; nothing is computed when nobody has the panel open (computing it can pick a random next runner).

---

### Task 1: Golden event traces

**Files:**
- Create: `tests/server_boot.lua`: `encode`, `decodeJson` and `boot` with its `env` helpers, moved from `tests/test_main.lua`
- Modify: `tests/test_main.lua` (starts with `dofile("tests/server_boot.lua")`; the moved code removed)
- Create: `tests/trace.lua`, `tests/test_traces.lua`, `tests/traces/<scenario>.txt`

**Interfaces:**
- `server_boot.lua` ends with `serverBoot = { boot = boot, encode = encode }` (a global; `decodeJson` is already global). `test_main.lua` and `test_traces.lua` each start with `dofile("tests/server_boot.lua")` and `local boot, encode = serverBoot.boot, serverBoot.encode`.
- `boot` also gets `env.reload()` (runs the same `main.lua` chunk again in the same `env`, as a hot reload does) and `env.timerOps`, a list of every `MP.CancelEventTimer` and `MP.CreateEventTimer` call as `{ op, name, ms }`, kept across reloads.
- `boot` also keeps `env.stream`, one list in call order: the fake `MP.TriggerClientEvent` appends `{ kind = "send", t = env.clock, to = pid, ev = ev, data = data }` and the captured `print` appends `{ kind = "log", t = env.clock, text = text }`, next to today's `env.sent` and `env.logs`, which stay as they are.
- Produces: `traceLine(entry) -> string`, `traceRun(scenario) -> string`, `traceCheck(name, scenario)`; `UPDATE_TRACES=1` records.

- [ ] **Step 1:** Move the code and add the two exports. Run `lua tests/run.lua tests/test_main.lua`. Expected: `238 passed, 0 failed`.
- [ ] **Step 2: Write the failing format tests** in `tests/test_traces.lua`:
  - `traceLine({ kind = "send", t = 1.25, to = 2, ev = "cnr_notice", data = '{"tone":"info","msg":"x"}' })` is `1.250 2 cnr_notice {"msg":"x","tone":"info"}` (clock with three decimals, recipient, event, payload re-encoded with keys sorted at every depth).
  - `traceLine({ kind = "log", t = 0, text = "[CnR] hi" })` is `0.000 log [CnR] hi`.
  - Within one call group, consecutive sends of the same event with the same payload to different recipients (a fan-out over `pairs`) come out sorted by recipient; other lines keep their order.
  - Numbers in payloads are re-encoded with `string.format("%.10g", n)`, so `16.653397805827` and `16.653397805827389` give the same line.
- [ ] **Step 3: Run** `lua tests/run.lua tests/test_traces.lua`. Expected: FAIL, `traceLine` is nil.
- [ ] **Step 4: Implement `tests/trace.lua`.** `traceRun(scenario)` does the following, and restores every override and calls `env.cleanup()` in all cases, also when the scenario errors:
  1. Before `boot`: replace `os.time` (returns `1795000000` without an argument, else the real one) and `os.date` (formats `1795000000` when no time is given).
  2. Replace `math.random` and `math.randomseed` with a Lua-side generator so Lua 5.3 and newer give the same numbers: a 31-bit LCG (`state = (state * 1103515245 + 12345) % 2^31`, seeded with 1, `randomseed` ignored) with the standard `random()`, `random(m)` and `random(m, n)` semantics.
  3. Clear every `package.loaded` entry whose name starts with `cnr.` or `arcade.` (module-level counters such as `cnr.round`'s `lastRebuildId` would otherwise depend on which tests ran first in the same process), then boot with `scenario.boot`. Clear them again afterwards.
  4. Wrap `env.call` so each call starts a group line `call <event>` and ends with `ret <values>` (its return values, `tostring`-ed).
  5. Run `scenario.steps(env)` and return `env.stream` as lines grouped by call, with `env.dir` replaced by `<dir>` and `CNR_VERSION` by `<version>` everywhere.

  `traceCheck` compares with `tests/traces/<name>.txt`, failing with the first differing line number and both lines; with `UPDATE_TRACES=1` it writes the file.
- [ ] **Step 5: Write the scenarios**, each copying the inputs of the named existing `test_main.lua` test. Each scenario asserts its required observations in the test, so a wrong golden can't be recorded. "After GO" means after the start index of `env.go()`; boot's own cancelled `cnr_roundEnd` never counts. Tick loops advance 0.25 seconds per `cnr_tick` and stop at 2000 ticks with a failure.
  - `lobby` (the settings save from the test at 1118, the board from "the board app gets state on open, after a run and on a filter change", 1408): players 1 and 2 join; 1 opens the panel and saves `headStartSeconds = 9`; 1 opens the board and filters `map = "all"`. Required: a `cnr_panelReply` with `ok = true`; a `cnr_boardState` with `filter = "all"`.
  - `round_caught` (from "full round over main wiring", 280): player 1 has the board open; `env.startRound()`; both cars confirmed with `cnr_myVehicle`; `env.go()`; ticks through `cnr_release`; cop 2 sends `cnr_sight` with `{"seen":true}` (inputs as in the sight test at 1336); ticks until a `cnr_roundEnd` after GO. Required: a live `cnr_lastSeen` to cop 2 before the catch, `reason = "caught"`, and a `cnr_boardState` to player 1 after it.
  - `round_escaped` (same fixture): config `roundTimeLimitSeconds = 30`; `env.startRound()`, then `env.positions` set 2000 m apart, `env.go()`, ticks until a `cnr_roundEnd` after GO. Required: `reason = "escaped"`.
  - `late_joiner` (the fresh join from the test at 1347, the spectator payload from "a mid-chase rejoin gets chaseElapsed in the spectator event", 843): in the chase, player 3 joins. Required: `cnr_spectate` to 3 with `chaseElapsed`. Then the runner disconnects. Required: a new `cnr_roundEnd` with `reason = "disconnect"`.
  - `practice_runner` (from "/cnr test runner: AI vehicles are tracked as cops", 412) and `practice_watch_ai` (from "practice while sitting out runs the AI alone, the issuer spectates and nothing is recorded", 3363): Required before registration: `cnr_setupAI` sent to the issuer. Then the issuer's AI vehicles registered with `cnr_aiVehicles` and given known positions as in those tests. Required after: the round outcome those tests observe (an AI cop's catch), which proves the registration.
  - `evolving` (apply and rebuild from "a full evolving round: prep, apply, rebuild, ready, GO", 1607; the queued change from 1694; the missing-parts report from 1707): the saved build, change, apply, the `cnr_setup` reply and the vehicle acknowledgements with the rebuild id, then GO, all with the clock advanced less than 5 seconds between request and reply. Required: `cnr_queued`, `cnr_rebuild`, then `cnr_applied` before any timeout path, and the chase starting after GO. A separate player's `cnr_missing` gives the missing-parts notice.
  - `auto_next` (from "auto next round prepares a new round but waits for go", 709): `auto on`, a round ends, ticks past `autoNextDelaySeconds`, the `cnr_pickVehicle` answered with `cnr_vehiclePicked`. Required: a `cnr_roundSetup` after the first round's end naming the new runner. That fixture leaves the new round in preparation, so then `env.go()` and ticks through `cnr_release`; (from "auto off tells clients to drop the next round countdown", 1316) `auto off` during that chase, ticks until it ends. Required: `cnr_autoNext`, and that round's `cnr_roundEnd` without `autoNextSeconds`.
  - `prep_actions` (from "New car keeps the sky", 880, and "New sky goes to the round's players before GO only", 892): in preparation, `reroll`, the runner's `cnr_vehiclePicked`, `sky`, then `stop`. Required: `cnr_sky` after the pick, and a `cnr_roundEnd` with `reason = "cancelled"` after the stop.
  - `vehicle_rules` (from `trafficBoot` and "a traffic spawn before the go-ahead is refused", 2437 and 2512): `trafficBoot({ config = '{"trafficPerPlayer":1}', maxCars = 6 })` (`maxCars` is the existing option). In the chase: a spectator's `onVehicleSpawn` (required: returns `1`); a round player's spawn of another model before their traffic opens (required: `1`); the runner's own car confirmed with `cnr_myVehicle`, traffic opened, `cnr_trafficCars` reported, then a spawn within the allowance (required: `0`).
- [ ] **Step 6:** Run `UPDATE_TRACES=1 lua tests/run.lua tests/test_traces.lua`, then `lua tests/run.lua tests/test_traces.lua` three times. Expected: all pass every time.
- [ ] **Step 7:** Run `make test`. Expected: all pass.
- [ ] **Step 8: Commit** `Traces: golden event traces of scripted rounds`, push, and check that the PR's CI `test` job (Lua 5.3) passes before Task 2. If CI's traces differ from the local ones, fix the source of the difference in `tests/trace.lua` and record again; Task 2 starts only from traces that match on both.

### Task 2: File store

**Files:**
- Create: `server/CopsAndRobbers/arcade/store.lua`, `tests/test_arcade_store.lua`
- Modify: `server/CopsAndRobbers/main.lua` (`readFile`, `writeFile`, `decodeFile` at 73-96 removed; callers use the store)

**Interfaces:**
- Produces: `store.read(path) -> string|nil`; `store.write(path, content)` (writes `path .. ".tmp"`, `FS.Remove(path)`, `FS.Rename(tmp, path)`); `store.decode(path) -> table|nil, corrupt: boolean` (empty or missing: `nil, false`; not JSON or not a table: `nil, true`). It uses the `Util` and `FS` globals at call time.

- [ ] **Step 1: Write the failing tests** in a temp directory, with the `Util` and `FS` fakes from `server_boot.lua`: `decode` of a missing file is `nil, false`; of `"[1"` is `nil, true`; of `'{"a":1}'` is `{ a = 1 }, false`; `write` then `read` returns the content and leaves no `.tmp` file.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_store.lua`. Expected: FAIL, module `arcade.store` not found.
- [ ] **Step 3: Implement** by moving the three functions; `main.lua` requires `arcade.store`.
- [ ] **Step 4: Run** the test, then `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.store: the JSON file store`.

### Task 3: Messages

**Files:**
- Create: `server/CopsAndRobbers/arcade/messages.lua`, `tests/test_arcade_messages.lua`
- Modify: `main.lua` (`log`, `send`, `notify`, `reply`, `refuse`, `broadcast`, `panelMirror` and the three mirror blocks in `cnrOnPanel`)

**Interfaces:**
- Produces: `messages.new({ prefix = "[CnR] " }) -> m` with `m.log(text)`, `m.send(pid, event, payload) -> engine result` (ignores a pid that isn't a number, or is below 0 and not -1), `m.notify(pid, text, tone)` (`cnr_notice`, tone defaults to `"info"`), `m.broadcast(text, tone)`, `m.reply(pid, text, tone)` (`cnr_panelReply { text, tone }` while `pid` is the mirror, else `notify`), `m.refuse(pid, text)` (`reply` with `"warn"`), `m.mirrored(pid, fn, ...) -> ok, err` (sets the mirror, `pcall`s `fn`, clears the mirror).

- [ ] **Step 1: Write the failing tests** with a recording `MP.TriggerClientEvent`: `send(-2, …)` and `send("1", …)` send nothing; `notify(3, "hi")` sends `cnr_notice` with `tone = "info"`; inside `mirrored(3, fn)` a `reply(3, "x")` sends `cnr_panelReply`, and after it the same call sends `cnr_notice`; an error in `fn` is returned and the mirror is cleared.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua`; `cnrOnPanel` keeps calling `pushPanel()` and then rethrowing with `error(err, 0)`, as now.
- [ ] **Step 4: Run** the test and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.messages: sending, notices and panel replies`.

### Task 4: Roster

**Files:**
- Create: `server/CopsAndRobbers/arcade/roster.lua`, `tests/test_arcade_roster.lua`
- Modify: `main.lua` (`playerKey` 226, `pidForKey` 234, `playing` 250, `sitOut`, `cnrOnSitOut`, `cnrOnPlayerDisconnect` 1352, the per-player tables below)

**Interfaces:**
- Produces: `roster.new() -> r` with `r:key(pid) -> string` (`"beammp:<id>"` from `MP.GetPlayerIdentifiers`, else `"name:<name>"`), `r:pidForKey(key) -> pid|nil`, `r:setSitOut(pid, on)`, `r:sittingOut(pid) -> boolean`, `r:playing(players) -> map, count` (a pid-keyed map without sitting-out players, so sparse pids survive), `r:perPlayer(name, group) -> table` (`group` is `"early"` or `"late"`; the same table for a name every time), `r:clear(name)` (empties in place), `r:leaveEarly(pid)`, `r:leaveLate(pid)`.
- `cnrOnPlayerDisconnect` becomes exactly: `r:leaveEarly(pid)`, `applyEffects(current:playerLeft(now(), pid))`, `r:leaveLate(pid)`, `pushRoundCars()`. Early: `connectionSerial`, `gridClients`, `stationsRequested`, `refusalLoggedAt`, `sitOut`, `parkedBystanders`, `panelSubs`, `boardSubs`. Late: `activeVid`, `registeredRoundCar`, `allowRoundSpawn`, `preRoundVehicles`, `trafficOpen`, `trafficVids`.
- Every `x = {}` reset of these tables in `main.lua` becomes `r:clear("x")`: `parkedBystanders` at 646, the round-end resets at 653-658, `handlers.start` 804-806, `handlers.test` 817-819.

- [ ] **Step 1: Write the failing tests:** keys with and without a BeamMP id; `pidForKey` finds the current pid; `playing` keeps pids 2 and 7 when 5 sits out and counts 2; `leaveEarly` clears only early tables and `leaveLate` only late ones; `clear` keeps the table's identity; two rosters share no state.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua`.
- [ ] **Step 4: Run** the test and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.roster: player keys, sit out and per-player state`.

### Task 5: Player colours

**Files:**
- Move: `server/CopsAndRobbers/cnr/colors.lua` to `server/CopsAndRobbers/arcade/colors.lua` (`git mv`; `tests/test_colors.lua` requires `arcade.colors`)
- Create: `server/CopsAndRobbers/arcade/playerColors.lua`, `tests/test_arcade_player_colors.lua`
- Modify: `main.lua` (`loadColors`, `saveColors`, `colorTable`, `colorFor`, `sendMyColor`, `cnrOnColor` 1307)

**Interfaces:**
- Consumes: `arcade.store`, `arcade.roster`, `arcade.messages`.
- Produces: `playerColors.new(path, r, m) -> c` with `c:load()`, `c:get(pid) -> { hex, r, g, b }|nil` (by key, then by the bare name, as `colorFor`), `c:set(pid, hex) -> ok, error` (the parse error text from `arcade.colors.parseHex`), `c:clear(pid)` (removes the key and the bare-name entry, then saves), `c:sendMine(pid, err)` (`cnr_myColor { hex, error }`, as `sendMyColor(pid, err)` does).

- [ ] **Step 1: Write the failing tests:** set then get by key; a bare-name legacy entry is found; `clear` removes both the key and the bare-name entry so the colour doesn't come back after a reload; an invalid hex returns the error and `sendMine(pid, err)` sends it with the current colour.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement**, move `colors.lua`, switch `main.lua`; `cnrOnColor` keeps sending `cnr_paint` during preparation.
- [ ] **Step 4: Run** the test, `test_colors.lua` and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.playerColors: player colours`.

### Task 6: Settings

**Files:**
- Create: `server/CopsAndRobbers/arcade/settings.lua`, `tests/test_arcade_settings.lua`
- Modify: `server/CopsAndRobbers/cnr/config.lua`, `server/CopsAndRobbers/cnr/panel.lua` (`applyValues` delegates), `main.lua` (`loadConfig` 139, the `config.json` writes in `handlers.auto` 852 and `panelSettings` 1043)

**Interfaces:**
- A declaration is `{ DEFAULTS, CHOICES, POSITIVE, MAXIMA, WHOLE, TIMING_RANGES, RETIRED_KEYS, RETIRED_VALUES, OVERRIDES, fix }`: today's rules from `cnr/config.lua`, with `fix(cfg, warnings)` for the `copSpawnMaxMeters` correction (it stays the game's).
- Produces in `arcade.settings`: `GLOBAL` (the declaration for the global keys listed in the seam, with their current defaults, choices and rules); `combine(global, game) -> decl` (errors on a key declared in both; applies `game.OVERRIDES` to global defaults); `merge(raw, decl) -> cfg, warnings`; `setValue(raw, key, text, decl) -> raw | nil, error`; `applyValues(raw, values, decl) -> raw | nil, error` and its key list as today; `new(path, decl) -> s` with `s:load() -> cfg, warnings, raw` (today's `loadConfig`, including its corrupt-file handling and logs) and `s:save(raw)` (`Util.JsonPrettify(Util.JsonEncode(raw))` through `arcade.store`).
- `cnr/config.lua` holds the game declaration as `GAME` and keeps its public API for every current caller (`sky`, `round`, `panel` and the tests): `DEFAULTS`, `CHOICES` and `TIMING_RANGES` are the combined tables, and `merge(raw)`, `setValue(raw, key, text)` delegate to `arcade.settings` with `combine(GLOBAL, GAME)`. Callers move off this façade in later steps.

- [ ] **Step 1: Write the failing tests**, recording today's results before changing `config.lua`:
  - `combine(GLOBAL, GAME).DEFAULTS` equals a literal copy of today's `config.DEFAULTS`.
  - Combining two declarations that share a key errors; an `OVERRIDES` entry changes only that default.
  - `merge` of `{ lightningMinSeconds = 30, lightningMaxSeconds = 20, copSpawnMinMeters = 200, copSpawnMaxMeters = 100, clockSpeed = 2, weather = "map", zzz = 1, aaa = 1 }` gives today's `cfg`. Warnings compared as a set, except two orderings that exist today: unknown-key warnings sorted by key, and the cop-spawn correction before the timing-range corrections.
  - `setValue` with an invalid value returns `nil` and today's error text.
  - `s:save(settings.setValue(raw, "headStartSeconds", "9", decl))` on that raw table writes a file without `clockSpeed` and `weather`, with `zzz`, `aaa` and `headStartSeconds = 9`. `s:save` always receives the raw table returned by `setValue` or `applyValues`, never `cfg`.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_arcade_settings.lua`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** the validator, `GLOBAL`, `combine`, load and save in `arcade/settings.lua`; reduce `cnr/config.lua` to `GAME` plus the façade; `cnr/panel.lua`'s `applyValues` delegates; `main.lua` uses `s:load()` and `s:save(raw)`.
- [ ] **Step 4: Run** the settings test, `test_config.lua`, `test_panel.lua`, then `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.settings: global and game declarations, load and save`.

### Task 7: Traffic

**Files:**
- Create: `server/CopsAndRobbers/arcade/traffic.lua`, `tests/test_arcade_traffic.lua`
- Modify: `cnr/traffic.lua` (`perPlayer` moves; `note` stays and calls `arcade.traffic.perPlayer`), `tests/test_traffic.lua`, `main.lua` (`maxCars` 315, `trafficFor` 321, `openTraffic` 326, `extraCars` 334, `trafficCars` 431, `cnrOnTrafficCars` 1472, the traffic part of `vehicleAllowed` 1203-1207)

**Interfaces:**
- Consumes: `arcade.roster` (`trafficOpen`, `trafficVids`), `arcade.messages`.
- Produces: `traffic.perPlayer(setting, maxCars, practice) -> number` (moved unchanged), `traffic.maxCars() -> number|nil`, `traffic.new(r, m) -> t` with `t:allowance(pid, cfg, practice, eligible) -> number` (0 when `eligible` is false), `t:open(pid, count)` (guards a positive count and not already open; sends `cnr_trafficStart { count }`). The participant guard stays in `main.lua`, which calls `t:open` only when `current:isActive()` and `current.players[pid] ~= nil`, as today, `t:openCount(pid) -> number|nil`, `t:report(pid, vids, ownVid, isAI)` (today's cap and exclusions), `t:extraCars(pid, ownVid) -> number`, `t:cars() -> list`.
- The game passes `eligible = current.test or not cfg.trafficRunnerOnly or pid == current.runnerId`, so the runner-only rule applies to real rounds only, as now. The practice issuer's capacity stays computed where it is today.

- [ ] **Step 1: Write the failing tests:** `allowance` is 0 when not eligible and `perPlayer(...)` otherwise; `open` sends nothing for a count of 0 or a second time; `report` keeps at most the open count and skips the own and AI vids; `extraCars` counts the player's vehicles other than the own one.
- [ ] **Step 2: Run** the test. Expected: FAIL, module not found.
- [ ] **Step 3: Implement** and switch `main.lua` and `cnr/traffic.lua`.
- [ ] **Step 4: Run** the test, `test_traffic.lua` and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.traffic: traffic allowance and reported cars`.

### Task 8: Panel plumbing, lobby and automatic rounds

**Files:**
- Create: `server/CopsAndRobbers/arcade/panel.lua`, `server/CopsAndRobbers/arcade/commands.lua`, `server/CopsAndRobbers/arcade/autoRounds.lua`, `tests/test_arcade_panel.lua`, `tests/test_arcade_auto_rounds.lua`
- Modify: `cnr/panel.lua` (`signature` delegates to `arcade.panel.signature`), `cnr/commands.lua` (`parse` moves to `arcade.commands`; `cnr.commands.parse` delegates), `main.lua` (`pushPanel` 1009, `pushLobby` 842, `runCommand` 939, `handlers.auto` 852, `handlers.next` 871, `handlers.reload` 930, `startAutoRound` 1593, `autoNextAt`, the panel and lobby part of `cnrTick` 1607-1613)

**Interfaces:**
- Consumes: `arcade.messages`, `arcade.roster` (`panelSubs`), `arcade.settings`.
- Produces: `arcade.commands.parse(text) -> cmd|nil` (moved unchanged). `panel.signature(state) -> string` (moved unchanged). `panel.new(m, r) -> p` with:
  - `p:push(stateFn, opener)`: today's `pushPanel`. With no subscribers and no opener it returns without calling `stateFn`. An opener is first removed from the subscribers. Existing subscribers get the state only when its signature changed. The opener is then added and gets exactly one copy, last.
  - `p:pushLobby(stateFn, pid)`: with a `pid`, always sends `cnr_lobby` to that pid and leaves the broadcast signature alone; without one, broadcasts only on a changed signature.
  - `p:close(pid)`, `p:command(name, handler)`, `p:run(pid, text)` (today's `runCommand`).
  - `p:tick(panelStateFn, lobbyStateFn)`: today's two `pcall`s and their once-per-change error logs.
- Produces: `autoRounds.new() -> a` with `a:schedule(at)`, `a:cancel()`, `a:pending() -> at|nil`, `a:due(now) -> boolean`, and `autoRounds.register(p, ctx)`, which registers the `auto`, `next` and `reload` commands with today's replies. `ctx = { settings, a, pushRules, startNext, refreshConfig, reloadRound, isActive, send }`. `refreshConfig()` reloads the effective config and sets the running round's `cfg` in place, as `handlers.auto` does today; `reloadRound()` creates a new round, as `handlers.reload` does. `auto` uses only `refreshConfig`.

- [ ] **Step 1: Write the failing tests:**
  - `push` with no subscribers doesn't call `stateFn`.
  - With subscribers 4 and 5 and opener 2 on a changed state: 4 and 5 get exactly one copy each (in any order), and 2 gets exactly one, after both, on the recorded send order. On an unchanged state, only 2 gets a copy.
  - `pushLobby(fn, 4)` sends to 4 every time without changing what the next broadcast compares against.
  - A failing state function logs once until its error text changes.
  - `run` dispatches `start next` to the `start` handler with `args = { "next" }`.
  - `due` is true only at or after the scheduled time, and `cancel` clears it.
  - `auto off` cancels the schedule and sends `cnr_autoNext`; `auto off` during a chase calls `refreshConfig` and not `reloadRound`.
- [ ] **Step 2: Run** both tests. Expected: FAIL, modules not found.
- [ ] **Step 3: Implement** and switch `main.lua`; the game's commands register through `p:command`.
- [ ] **Step 4: Run** the tests, `test_panel.lua`, `test_commands.lua` and `make test`. Expected: all pass, traces identical.
- [ ] **Step 5: Commit** `arcade.panel, commands and autoRounds: panel plumbing and automatic rounds`.

### Task 9: Step 1 wrap-up

**Files:**
- Create: `tests/test_reload.lua`
- Modify: `docs/DEPENDENCIES.md` (one short section on the `arcade/` folder and what moved)

- [ ] **Step 1: Write the reload test:**
  1. Boot with `serverBoot.boot`; open the panel for player 1; turn automatic rounds on; run a round to its end so one is scheduled; note the scheduled time.
  2. `env.reload()`.
  3. Required: the reload sends `cnr_roundEnd { reason = "cancelled" }` and `cnr_mode` again; `env.timerOps` is `cancel cnr_tick`, `create cnr_tick 250`, twice in that order.
  4. Note the clock at the reload; the reloaded server's timer starts at zero there. Advance from the reload time by the old deadline's full delay plus 0.25 seconds, then tick. Required: no `cnr_panelState` (no subscriber survived) and no `cnr_pickVehicle` (no schedule survived).
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_reload.lua`. Expected: PASS (the services keep no module-level state). If it fails, find the state a module keeps and move it into its `new()`.
- [ ] **Step 3:** Check that `main.lua` no longer defines the moved functions: `grep -n 'local function \(readFile\|writeFile\|decodeFile\|send\|notify\|playerKey\|pidForKey\|playing\|loadColors\|saveColors\|maxCars\|openTraffic\|extraCars\|trafficCars\|pushPanel\|pushLobby\|runCommand\|loadConfig\)\b' server/CopsAndRobbers/main.lua`. Expected: no output.
- [ ] **Step 4:** Check that no `arcade.*` module requires `cnr.*`: `grep -rn 'require("cnr\.' server/CopsAndRobbers/arcade/`. Expected: no output.
- [ ] **Step 5:** Run `make test` and `make package`. Expected: all pass; `dist/Server/CopsAndRobbers/arcade/` exists and `dist/Server/CopsAndRobbers/data/` doesn't. No client Lua changed in this plan; if any did, `luajit -bl <file> >/dev/null` for each.
- [ ] **Step 6:** Update `docs/DEPENDENCIES.md`, commit `Docs: the arcade folder`.
- [ ] **Step 7:** Label the PR `needs-playtest` with the checks for the maintainer on the local test server. Pass: nothing differs from the release before. Uncertainty resolved: the extraction changes nothing BeamMP or the client sees beyond what the traces record.
  - a full round with a catch
  - a practice round as runner
  - a late joiner spectating
  - saving a setting in the panel
  - the leaderboard's Rounds tab
  - automatic rounds on, one round, then off
