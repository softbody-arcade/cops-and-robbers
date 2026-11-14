# BeamMP Cops and Robbers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A BeamMP server plugin plus auto-distributed client mod that enforces the group's cops-and-robbers rules with configurable values.

**Architecture:** Server plugin (Lua 5.3, BeamMP server 3.9) owns round state, catch detection, reset eligibility and the leaderboard; all rule logic lives in pure modules under `server/CopsAndRobbers/cnr/` that take plain tables and a clock so they are unit-tested with stock Lua. `main.lua` is thin wiring to `MP.*`. The client mod (BeamNG GE Lua, game 0.40) picks the random vehicle, swaps/places/freezes vehicles, locks reset inputs except when the server says a reset is allowed, detects gas stations and shows toasts.

**Tech Stack:** Lua 5.3 (server, tests), LuaJIT/Lua 5.1 subset (client), BeamMP server 3.9.3 (AUR `beammp-server`), BeamNG.drive 0.40.5, `zip`, `make`.

**Spec:** `docs/superpowers/specs/2026-11-14-cops-and-robbers-design.md`

## Global Constraints

- Config defaults exactly: headStartSeconds 7, resetWaitSeconds 7, catchHoldSeconds 7, catchRadiusMeters 10, catchMaxSpeedKmh 3, stillMaxSpeedKmh 1, copResetMinDistanceMeters 1000, gasStationRadiusMeters 25, copSpawnMinMeters 50, copSpawnMaxMeters 150, explodeOnCatch false, includeModVehicles false.
- Survival clock starts at cop release (end of head start); no catch possible during head start. `survivedSeconds = endedAt - releasedAt`.
- Runner reset = repair in place only. Cop reset = repair + move to nearest road. Rewind/recover never available during a round.
- Exactly one runner; everyone else is a cop. Any player can run any command.
- Cancelled rounds (`/cnr stop`) are not recorded. Disconnect ends the round and is recorded with `endReason = "disconnect"`.
- Pure modules (`cnr/*.lua`) must not reference `MP`, `Util`, `FS` or `io`; they must run under plain `lua5.3`. Avoid `//`, `goto`, integer-only APIs in client code (LuaJIT).
- No code comments unless needed to explain a non-obvious engine quirk (repo owner preference).
- Chat command prefix `/cnr`; all chat replies prefixed `[CnR] `.

## Verified Engine/API facts (from source, 2026-11-14)

Server (BeamMP-Server `src/TLuaEngine.cpp`, `src/TServer.cpp`):
- Events: `onInit`, `onPlayerJoin(pid)`, `onPlayerDisconnect(pid)`, `onChatMessage(pid, name, msg)` (return 1 to hide), `onVehicleSpawn(pid, vid, data)` / `onVehicleEdited(pid, vid, data)` (return non-zero to cancel; `data` is `"roles:name:pid-vid:{json}"`, json has `jbm` = model and `vcf` = config table), `onVehicleReset(pid, vid, data)` (not cancellable), `onVehicleDeleted(pid, vid)`.
- Custom client→server events: `MP.RegisterEvent(name, fnName)`; handler gets `(pid, dataString)`.
- `MP.GetPositionRaw(pid, vid)` → `table, err`; table has `pos`, `vel`, `rot`, `tim`, `ping` (decoded from client position packet).
- `MP.TriggerClientEvent(pid|-1, name, string)`, `MP.SendChatMessage(pid|-1, msg)`, `MP.GetPlayers()` → `{[pid]=name}`, `MP.GetPlayerName`, `MP.GetPlayerVehicles(pid)` → `{[vid]=dataString}`, `MP.RemoveVehicle(pid, vid)`, `MP.CreateEventTimer(event, ms)`, `MP.GetServerTimeMS()`, `MP.Get(MP.Settings.Map)`, `Util.JsonEncode/JsonDecode`.

Client (BeamNG 0.40.5 + BeamMP mod):
- `AddEventHandler(name, fn(dataString))`, `TriggerServerEvent(name, dataString)` (globals from BeamMP).
- `MPVehicleGE.isOwn(gameVid)`, `MPVehicleGE.getGameVehicleID()` / `getServerVehicleID()`, `MPConfig.getPlayerServerID()`.
- Vehicles: `core_vehicles.getConfigList()` (configs carry `Source`: `"BeamNG - Official"` vs mod name), `core_vehicles.replaceVehicle(model, {config=path})`, `core_vehicles.spawnNewVehicle(model, {config=path, pos=vec3, rot=quat})`.
- Freeze: `veh:queueLuaCommand("controller.setFreeze(1)")` / `(0)`. Explode: `veh:queueLuaCommand("fire.explodeVehicle()")`.
- Input lock: `core_input_actionFilter.setGroup(name, {actions...})` + `core_input_actionFilter.addAction(0, name, true|false)`. Action names: `reset_physics` (R, in-place reset), `recover_vehicle`, `recover_vehicle_alt`, `recover_to_last_road`, `loadHome`, `saveHome`, `reload_vehicle`, `reload_all_vehicles`, `reset_all_physics`, `vehicle_selector`, `parts_selector`, `dropPlayerAtCamera`, `dropPlayerAtCameraNoReset`, `nodegrabberGrab`, `switch_next_vehicle`, `switch_previous_vehicle`, `toggleWalkingMode`.
- Road teleport: `spawn.teleportToLastRoad(veh)` (BeamMP-aware). Roads: `map.getMap().nodes[id] = {pos, radius, links}`, `map.findClosestRoad(pos)` → `n1, n2, dist`.
- Gas stations: `freeroam_facilities.getFacilitiesByType("gasStation")` + `freeroam_gasStations.gasStationCenterRadius(f)` → `center (vec3), radius`. West Coast USA has 10, Italy 12. Guard stations whose pumps aren't found (center becomes NaN).
- Toasts: `guihooks.trigger('Message', {ttl=s, msg=text, category='cnr', icon='directions_car'})`.

## Review Focus

1. Latency between server eligibility and the player's reset: a reset arriving up to 1.5 s after eligibility ended must not be flagged illegal (test in Task 3).
2. Runner chosen by partial/odd name: `/cnr start rei` must match "Reinder" case-insensitively, ambiguous or unknown names must reply with an error and not start (test in Task 6).
3. Position data missing (vehicle just spawned, no packet yet, `GetPositionRaw` error): tick must skip that vehicle, never crash or count it as stopped/caught (test in Task 5).
4. Command issued while a round is running (`/cnr start` again) or `/cnr stop` while idle: must reply with a clear error, state unchanged (test in Task 6).
5. Corrupt or partial `config.json` / `leaderboard.json`: unknown keys ignored, invalid values fall back to defaults with a warning, corrupt leaderboard is moved aside rather than overwritten (tests in Tasks 1 and 4).

---

## File Structure

```
Makefile                                    test / package / install targets
.gitignore                                  dist/, .testserver/
server/CopsAndRobbers/main.lua              MP wiring only
server/CopsAndRobbers/config.json           defaults (Global Constraints)
server/CopsAndRobbers/cnr/vec.lua           dist, speedKmh, normalize position tables
server/CopsAndRobbers/cnr/config.lua        merge + validate config
server/CopsAndRobbers/cnr/catch.lua         catch hold tracker
server/CopsAndRobbers/cnr/resets.lua        per-player reset eligibility
server/CopsAndRobbers/cnr/leaderboard.lua   records, best-per-player, formatting
server/CopsAndRobbers/cnr/round.lua         round state machine (pure, emits effects)
server/CopsAndRobbers/cnr/commands.lua      /cnr parsing + name matching
client/scripts/copsAndRobbers/modScript.lua loads the extension
client/lua/ge/extensions/copsAndRobbers.lua client logic
tests/run.lua                               tiny test runner (assertEq, assertNear)
tests/test_*.lua                            one per cnr module
```

## Event Protocol (all payloads JSON strings)

| Direction | Event | Payload |
|---|---|---|
| S→C (issuer) | `cnr_pickVehicle` | `{includeMods}` |
| C→S | `cnr_vehiclePicked` | `{model, config}` |
| S→C (all) | `cnr_roundSetup` | `{runnerId, role:"runner"\|"cop", model, config, headStartRemaining, runnerPos:{x,y,z}, copSpawnMin, copSpawnMax, copIndex}` (sent per player) |
| S→C (all) | `cnr_release` | `{}` |
| S→C (per player, on change) | `cnr_state` | `{resetAllowed, resetHint, catchProgress}` (catchProgress 0..1, rounded to 0.05) |
| S→C (all) | `cnr_roundEnd` | `{runnerId, runnerName, survivedSeconds, reason:"caught"\|"disconnect"\|"cancelled", explode}` |
| S→C (pid) | `cnr_requestStations` | `{map}` |
| C→S | `cnr_stations` | `{map, stations:[{x,y,z,r}]}` |

---

### Task 1: Scaffold, test runner, vec and config

**Files:**
- Create: `Makefile`, `.gitignore`, `tests/run.lua`, `server/CopsAndRobbers/config.json`, `server/CopsAndRobbers/cnr/vec.lua`, `server/CopsAndRobbers/cnr/config.lua`
- Test: `tests/test_vec.lua`, `tests/test_config.lua`

**Interfaces:**
- Produces:
  - `vec.toVec(t) -> {x,y,z}|nil` (accepts `{x=,y=,z=}` or `{1,2,3}`; nil on garbage)
  - `vec.dist(a, b) -> number`
  - `vec.speedKmh(vel) -> number` (vel in m/s)
  - `config.DEFAULTS` (table, values from Global Constraints)
  - `config.merge(raw: table|nil) -> cfg: table, warnings: {string}`
  - `tests/run.lua`: globals `test(name, fn)`, `assertEq(a, b, msg)`, `assertNear(a, b, eps, msg)`; runs every `tests/test_*.lua` passed as args, exits non-zero on failure. Sets `package.path` to include `server/CopsAndRobbers/?.lua`.
  - `make test` → `lua5.3 tests/run.lua tests/test_*.lua` (fallback `lua` if `lua5.3` missing).

- [ ] **Step 1: Write failing tests**

```lua
test("toVec accepts keyed and array", function()
  assertEq(vec.toVec({x=1,y=2,z=3}).z, 3)
  assertEq(vec.toVec({4,5,6}).x, 4)
  assertEq(vec.toVec("nope"), nil)
  assertEq(vec.toVec({1,2}), nil)
end)
test("dist and speed", function()
  assertNear(vec.dist({x=0,y=0,z=0},{x=3,y=4,z=0}), 5, 1e-9)
  assertNear(vec.speedKmh({x=10,y=0,z=0}), 36, 1e-9)
end)
test("merge fills defaults", function()
  local c, w = config.merge(nil)
  assertEq(c.headStartSeconds, 7); assertEq(c.copResetMinDistanceMeters, 1000)
  assertEq(c.explodeOnCatch, false); assertEq(#w, 0)
end)
test("merge keeps valid, rejects invalid, ignores unknown", function()
  local c, w = config.merge({headStartSeconds=10, catchRadiusMeters=-5, explodeOnCatch="yes", bogus=1})
  assertEq(c.headStartSeconds, 10)
  assertEq(c.catchRadiusMeters, 10)
  assertEq(c.explodeOnCatch, false)
  assertEq(c.bogus, nil)
  assertEq(#w, 3)
end)
test("copSpawnMax below min is corrected", function()
  local c, w = config.merge({copSpawnMinMeters=200, copSpawnMaxMeters=100})
  assertEq(c.copSpawnMaxMeters, 200); assertEq(#w, 1)
end)
```

Validation rule: numbers must be finite and `>= 0` (`> 0` for `catchHoldSeconds`, `catchRadiusMeters`); booleans must be booleans; wrong type/value → default + warning string naming the key.

- [ ] **Step 2:** `make test` → FAIL (modules missing).
- [ ] **Step 3:** Implement `vec.lua`, `config.lua`, `config.json` (exact defaults), `tests/run.lua`, `Makefile`, `.gitignore`.
- [ ] **Step 4:** `make test` → all PASS.
- [ ] **Step 5:** Commit `feat: scaffold, test runner, vec and config validation`.

---

### Task 2: Catch tracker

**Files:** Create `server/CopsAndRobbers/cnr/catch.lua`; Test `tests/test_catch.lua`

**Interfaces:**
- Consumes: `vec.dist`, `vec.speedKmh`, cfg fields `catchHoldSeconds`, `catchRadiusMeters`, `catchMaxSpeedKmh`.
- Produces:
  - `catch.new(cfg) -> tracker`
  - `tracker:update(now: seconds, runner: {pos, vel}|nil, cops: {{pos}...}) -> progress: number (0..1), caught: boolean`
  - `tracker:reset()`

Rule: held = runner present AND `speedKmh(runner.vel) < catchMaxSpeedKmh` AND some cop with `dist <= catchRadiusMeters`. Hold accumulates `now - lastNow` while held; any non-held update sets it to 0. `caught` when hold `>= catchHoldSeconds`. Missing runner data → not held, hold reset to 0.

- [ ] **Step 1: Failing tests**

```lua
local cfg = config.merge(nil)
local function car(x, vx) return {pos={x=x,y=0,z=0}, vel={x=vx or 0,y=0,z=0}} end
test("caught after 7s held", function()
  local t = catch.new(cfg); local p, c
  for i = 0, 28 do p, c = t:update(i*0.25, car(0), {car(5)}) end
  assertEq(c, true); assertNear(p, 1, 1e-9)
end)
test("not caught at 6.75s", function()
  local t = catch.new(cfg); local c
  for i = 0, 27 do _, c = t:update(i*0.25, car(0), {car(5)}) end
  assertEq(c, false)
end)
test("moving faster than 3 km/h breaks hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  local p = t:update(5.5, car(0, 1), {car(5)})
  assertEq(p, 0)
end)
test("cop beyond 10 m breaks hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  assertEq((t:update(5.5, car(0), {car(10.5)})), 0)
end)
test("missing runner data resets", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  assertEq((t:update(5.5, nil, {car(5)})), 0)
end)
```

- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test` → PASS.
- [ ] **Step 5:** Commit `feat: catch hold tracker`.

---

### Task 3: Reset eligibility

**Files:** Create `server/CopsAndRobbers/cnr/resets.lua`; Test `tests/test_resets.lua`

**Interfaces:**
- Consumes: `vec`, cfg `resetWaitSeconds`, `stillMaxSpeedKmh`, `copResetMinDistanceMeters`, `gasStationRadiusMeters`.
- Produces:
  - `resets.new(cfg) -> tracker` (one per player per round)
  - `tracker:update(now, car: {pos, vel}|nil, ctx: {role: "runner"|"cop", runnerPos: vec|nil, stations: {{x,y,z,r}}}) -> allowed: boolean, hint: string`
  - `tracker:consume(now) -> wasLegal: boolean` (call on `onVehicleReset`; legal if allowed now or allowed at any point in the last 1.5 s; resets the still timer either way)
  - `resets.atStation(pos, stations, cfg) -> boolean` (inside if `dist <= math.max(cfg.gasStationRadiusMeters, s.r + 10)`)

Rules (first match wins, hint strings exact):
1. cop and `runnerPos` and `dist >= copResetMinDistanceMeters` → `true, "Reset available (far from runner)"`.
2. not still (`speedKmh >= stillMaxSpeedKmh`) → still timer cleared; `false, "Stop to reset"`.
3. still and `atStation` → `true, "Reset available (gas station)"`.
4. still for `>= resetWaitSeconds` → `true, "Reset available"`.
5. else `false, string.format("Stay still %ds to reset", math.ceil(remaining))`.
Missing car data → `false, "Stop to reset"`, still timer cleared.

- [ ] **Step 1: Failing tests**

```lua
local cfg = config.merge(nil)
local function car(x, vx) return {pos={x=x,y=0,z=0}, vel={x=vx or 0,y=0,z=0}} end
local runnerCtx = {role="runner", stations={}}
test("wait rule needs 7s still", function()
  local t = resets.new(cfg)
  local a, h = t:update(0, car(0), runnerCtx); assertEq(a, false); assertEq(h, "Stay still 7s to reset")
  a = t:update(6.9, car(0), runnerCtx); assertEq(a, false)
  a, h = t:update(7.0, car(0), runnerCtx); assertEq(a, true); assertEq(h, "Reset available")
end)
test("moving restarts the wait", function()
  local t = resets.new(cfg)
  t:update(0, car(0), runnerCtx); t:update(5, car(0, 2), runnerCtx)
  assertEq((t:update(11, car(0), runnerCtx)), false)
end)
test("gas station allows immediately when still", function()
  local t = resets.new(cfg)
  local ctx = {role="runner", stations={{x=20,y=0,z=0,r=8}}}
  local a, h = t:update(0, car(0), ctx); assertEq(a, true); assertEq(h, "Reset available (gas station)")
  assertEq((t:update(1, car(0, 2), ctx)), false)
end)
test("station radius uses max(25, r+10)", function()
  assertEq(resets.atStation({x=30,y=0,z=0}, {{x=0,y=0,z=0,r=22}}, cfg), true)
  assertEq(resets.atStation({x=30,y=0,z=0}, {{x=0,y=0,z=0,r=5}}, cfg), false)
end)
test("far cop resets while moving, runner cannot", function()
  local t = resets.new(cfg)
  assertEq((t:update(0, car(0, 20), {role="cop", runnerPos={x=1000,y=0,z=0}, stations={}})), true)
  assertEq((t:update(1, car(0, 20), {role="cop", runnerPos={x=999,y=0,z=0}, stations={}})), false)
  assertEq((resets.new(cfg):update(0, car(0, 20), {role="runner", runnerPos={x=5000,y=0,z=0}, stations={}})), false)
end)
test("consume honours 1.5s grace and resets timer", function()
  local t = resets.new(cfg)
  t:update(0, car(0), runnerCtx); t:update(7, car(0), runnerCtx); t:update(7.5, car(0, 2), runnerCtx)
  assertEq(t:consume(8.4), true)
  assertEq(t:consume(10.1), false)
  assertEq((t:update(10.2, car(0), runnerCtx)), false)
end)
```

- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: reset eligibility rules`.

---

### Task 4: Leaderboard

**Files:** Create `server/CopsAndRobbers/cnr/leaderboard.lua`; Test `tests/test_leaderboard.lua`

**Interfaces:**
- Produces:
  - `leaderboard.load(decoded: table|nil) -> board` (`{runs = {...}}`; nil or missing `runs` → empty)
  - `leaderboard.add(board, run)` where `run = {player, survivedSeconds, map, model, config, releasedAt, endedAt, endReason}`
  - `leaderboard.best(board, limit) -> {{player, survivedSeconds, map, model}}` (best per player, descending, default limit 10)
  - `leaderboard.formatTime(seconds) -> "m:ss"` (e.g. 272.4 → `"4:32"`, 3725 → `"62:05"`)
  - `leaderboard.formatTop(board, limit) -> {string}` chat lines: `"1. Reinder 4:32 (pickup, west_coast_usa)"`; empty board → `{"No runs yet"}`

Main (Task 6) owns file IO: if decoding `leaderboard.json` fails, rename it to `leaderboard.json.corrupt-<unix>` and start empty.

- [ ] **Step 1: Failing tests** for: empty load; best keeps max per player and sorts; limit; `formatTime(272.4) == "4:32"`, `formatTime(59.99) == "0:59"`, `formatTime(3725) == "62:05"`; `formatTop` on empty board.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: leaderboard records and formatting`.

---

### Task 5: Round state machine

**Files:** Create `server/CopsAndRobbers/cnr/round.lua`; Test `tests/test_round.lua`

**Interfaces:**
- Consumes: `catch`, `resets`, `vec`, cfg.
- Produces: `round.new(cfg) -> r` with fields `r.state` (`"idle"|"picking"|"headstart"|"running"`), `r.runnerId`, `r.vehicle = {model, config}`, `r.startedAt`, `r.releasedAt`, and methods that return a list of **effects** (tables `{kind=..., ...}`) instead of doing IO:
  - `r:start(now, runnerId, issuerId, players: {[pid]=name}) -> effects` → state `picking`; effects `{kind="pickVehicle", pid=issuerId}`. Error if not idle: `{kind="reply", pid=issuerId, msg="A round is already running"}`.
  - `r:vehiclePicked(now, pid, model, config, players) -> effects` → only from `picking` and only from the issuer; state `headstart`, `startedAt=now`; effects one `{kind="setup", pid, role, copIndex, headStartRemaining=cfg.headStartSeconds}` per player, `{kind="broadcast", msg="<runner> is the runner! Car: <model>. Cops released in 7s"}`.
  - `r:tick(now, cars: {[pid]={pos,vel}|nil}, stations) -> effects`
    - `headstart`: when `now - startedAt >= headStartSeconds` → state `running`, `releasedAt=now`, effects `{kind="release"}`, `{kind="broadcast", msg="Cops released!"}`. No catch evaluation.
    - `running`: catch tracker on runner vs cops (only pids with data), reset trackers per player; effect `{kind="state", pid, resetAllowed, resetHint, catchProgress}` only when that player's tuple changed (catchProgress rounded to 0.05). On catch → `endRound("caught")`.
    - Both: reset trackers updated so resets work during head start for the runner.
  - `r:playerJoined(now, pid) -> effects` → if headstart/running, a `setup` effect with role cop, `headStartRemaining = max(0, startedAt + headStartSeconds - now)`.
  - `r:playerLeft(now, pid) -> effects` → runner leaving while `running` → `endRound("disconnect")`; while `picking`/`headstart` → cancel (not recorded). Issuer leaving during `picking` → cancel.
  - `r:vehicleReset(now, pid) -> effects` → `resets:consume`; illegal → `{kind="broadcast", msg="<name> reset illegally"}`.
  - `r:stop(now) -> effects` → cancel; error reply if idle: `"No round running"`.
  - `endRound(reason)` effects: `{kind="roundEnd", reason, survivedSeconds, explode = cfg.explodeOnCatch and reason=="caught"}`, `{kind="record", run}` (not for cancel), state `idle`, trackers cleared.
  - Picking times out after 10 s with no `vehiclePicked` → cancel with broadcast `"Vehicle pick timed out"`.

- [ ] **Step 1: Failing tests** covering: start→picking→headstart→running transition times (release at exactly 7 s); no catch during headstart even with runner stopped next to cop; catch after release + 7 s produces `roundEnd` with `survivedSeconds == 7` (±0.25) and a `record`; `explode` true only when cfg set and reason caught; runner disconnect in running records `disconnect`; runner disconnect in headstart cancels with no record; `start` while running returns the error reply and keeps state; `stop` while idle returns error; a pid whose car is `nil` in `tick` is skipped (no crash, cop list excludes it, runner nil → no catch progress); `state` effects only emitted on change; mid-round join yields cop setup with `headStartRemaining == 0` when running; pick timeout cancels.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: round state machine`.

---

### Task 6: Commands and server wiring

**Files:** Create `server/CopsAndRobbers/cnr/commands.lua`, `server/CopsAndRobbers/main.lua`; Test `tests/test_commands.lua`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `commands.parse(msg) -> cmd|nil` → `nil` if not starting with `/cnr`; else `{name, args={...}}`; bare `/cnr` → `{name="help"}`.
  - `commands.matchPlayer(query, players: {[pid]=name}) -> pid|nil, err|nil`: exact case-insensitive match wins; else unique case-insensitive prefix; `"random"` → random pid (inject `math.random`); errors exactly `"No player matching '<q>'"`, `"'<q>' matches several players: A, B"`.

`main.lua` responsibilities (not unit-tested; verified in Task 8):
- Prepend own directory to `package.path` (`debug.getinfo(1,"S").source`), require `cnr.*`.
- Load `config.json` via `Util.JsonDecode`, print warnings to server console. `/cnr reload` re-merges.
- Map name: from `MP.Get(MP.Settings.Map)` (`/levels/<name>/info.json`).
- Stations: load `data/stations/<map>.json`; if missing/empty, send `cnr_requestStations` to the first joining player; on `cnr_stations` save if still empty. `/cnr addstation` appends `{x,y,z,r=0}` at the issuer's current vehicle position; `/cnr removestation` removes nearest within 50 m. Create `data/` dirs with `FS.CreateDirectory`.
- Timer `MP.CreateEventTimer("cnr_tick", 250)`; tick builds `cars` from `MP.GetPositionRaw` for each player's active vehicle (skip on error) and applies effects.
- Active vehicle per player = last vid seen in spawn/edit during the round; extra vehicles removed with `MP.RemoveVehicle`.
- `onVehicleSpawn`/`onVehicleEdited` during headstart/running: decode json after the 3rd `:`; cancel (return 1) when `jbm ~= round.vehicle.model`, or when `vcf.partConfigFilename` exists and differs from `round.vehicle.config`, or (spawn only) when the player already has a vehicle. Reply `"Only the round car is allowed"`.
- `onChatMessage`: if `commands.parse` matches, dispatch and `return 1`.
- Effect application: `reply` → `SendChatMessage(pid, "[CnR] "..msg)`; `broadcast` → pid -1; `pickVehicle`/`setup`/`release`/`state`/`roundEnd` → `TriggerClientEvent` with protocol payloads (setup adds `runnerPos` from `GetPositionRaw` of the runner, `copSpawnMin/Max` from cfg); `record` → `leaderboard.add`, write file, then broadcast `"Runner caught! <name> survived m:ss"` (or `"<name> disconnected after m:ss"`) followed by `formatTop(board, 5)`.
- `/cnr config` lists `key = value` lines sorted; `/cnr help` lists commands from the spec table.

- [ ] **Step 1: Failing tests** for `parse` (`"/cnr start rei"`, `"/CNR top"` case-insensitive name, `"hello"` → nil, `"/cnr"` → help) and `matchPlayer` (`"rei"`→Reinder; `"REINDER"` exact beats prefix when `{Reinder, ReinderAlt}`; ambiguous error text; unknown error text; `"random"` returns a member pid).
- [ ] **Step 2:** FAIL. **Step 3:** Implement `commands.lua` then `main.lua`. **Step 4:** `make test` PASS; `luac5.3 -p server/CopsAndRobbers/main.lua` (or `lua5.3 -e 'loadfile(...)'`) syntax-clean.
- [ ] **Step 5:** Commit `feat: chat commands and server wiring`.

---

### Task 7: Client mod

**Files:** Create `client/scripts/copsAndRobbers/modScript.lua`, `client/lua/ge/extensions/copsAndRobbers.lua`; Modify `Makefile` (target `package` → `dist/Client/CopsAndRobbers.zip` with `scripts/` and `lua/` at zip root, `dist/Server/CopsAndRobbers/` copied without `data/`).

**Interfaces:**
- Consumes: Event Protocol table; verified client APIs above.
- Produces: extension `copsAndRobbers` registering handlers on load via `AddEventHandler` (guard `if AddEventHandler then`).

Behaviour:
- `modScript.lua`: `setExtensionUnloadMode("copsAndRobbers", "manual")` and `extensions.load("copsAndRobbers")`.
- `cnr_pickVehicle`: from `core_vehicles.getConfigList().configs`, keep entries whose `aggregates.Source` / `Source` is official unless `includeMods`; exclude `Type` values `Trailer`, `Prop`, `Utility` and model `unicycle`; pick random; send `cnr_vehiclePicked {model, config = <config key path used by replaceVehicle>}`.
- `cnr_roundSetup`: remember role. Lock inputs: group `cnr_locked` = all action names in the Verified list; `addAction(0, "cnr_locked", true)`. Runner: `replaceVehicle(model, {config})` in place. Cop: pick a road node with `copSpawnMin <= dist(runnerPos) <= copSpawnMax`, offset by `copIndex` so cops don't overlap (step through candidates sorted by distance, minimum 8 m between chosen spots), face along a link; `replaceVehicle` (or `spawnNewVehicle` if no own vehicle) then set position/rotation; if `headStartRemaining > 0` freeze and show a countdown toast each second; runner gets `"GO!"`.
- Binding check on `cnr_roundSetup`: inspect the active input bindings of every connected device (`core_input_bindings` — verify the exact accessor in `lua/ge/extensions/core/input/bindings.lua`); if no device binds `reset_physics`, toast for 10 s: `"Bind 'Reset vehicle' to a wheel button to reset during rounds"`. Players reset by action, not by key, so wheel buttons work once bound.
- `cnr_release`: unfreeze own vehicle; toast `"GO!"` for cops.
- `cnr_state`: when `resetAllowed` changes to true, unblock `reset_physics` only (separate group `cnr_resetKey`); toast hint on change; `catchProgress > 0` toast `"CAUGHT IN x.xs"` style (runner) / `"HOLDING x%"` (cops) at most every 0.5 s.
- Cop reset → road: in `onVehicleResetted(gameVid)` for own vehicle, role cop, round active, and not already teleporting → `spawn.teleportToLastRoad(veh)` once (flag cleared after 2 s).
- `cnr_roundEnd`: unlock everything, unfreeze, toast result; if `explode` and own vehicle is the runner's → `fire.explodeVehicle()`.
- `cnr_requestStations`: collect stations (skip NaN centers), send `cnr_stations`.
- On extension unload / disconnect: clear filters so a player is never left locked.

- [ ] **Step 1:** Implement both files; `luajit -bl client/lua/ge/extensions/copsAndRobbers.lua > /dev/null` and same for modScript → no syntax errors.
- [ ] **Step 2:** `make package` → `unzip -l dist/Client/CopsAndRobbers.zip` lists `scripts/copsAndRobbers/modScript.lua` and `lua/ge/extensions/copsAndRobbers.lua`.
- [ ] **Step 3:** Commit `feat: client mod`.

---

### Task 8: Local test server and playtest

**Files:** Modify `Makefile` (target `install-local` → copies `dist/` into `.testserver/Resources/`), Create `README.md` (install on the real server: copy `dist/Server/CopsAndRobbers` to `Resources/Server/`, `dist/Client/CopsAndRobbers.zip` to `Resources/Client/`; config reference; commands).

- [ ] **Step 1:** Ask the user to run `! yay -S beammp-server` (needs sudo). Create `.testserver/ServerConfig.toml` with `Private = true`, `Map = "/levels/west_coast_usa/info.json"`, `Port = 30814`, `MaxPlayers = 8`; AuthKey: try empty first, if the server or launcher refuses connections ask the user for a key from keymaster.
- [ ] **Step 2:** `make package install-local`, run `beammp-server` in `.testserver` (background), confirm console prints the plugin load and no Lua errors; `/cnr help` via chat after connecting.
- [ ] **Step 3:** Solo playtest with the user (direct connect `127.0.0.1:30814`), checklist:
  - `/cnr start <self>` swaps to a random official car, toasts show.
  - R does nothing while moving; stop 7 s → "Reset available" → R repairs in place; Insert/home/vehicle selector stay blocked.
  - Drive to a West Coast USA gas station, stop → immediate reset allowed. Server console shows stations loaded (10).
  - `/cnr stop` unlocks everything; `/cnr top` shows "No runs yet".
  - Second player (ask the user to have a friend join or run a second client) for catch, head-start freeze, cop placement, cop reset-to-road, disconnect, leaderboard record.
- [ ] **Step 4:** Fix anything found (each fix: failing test first if it touches `cnr/`), commit, then commit `docs: README with install and config`.
