# Traffic During Rounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every player's game runs a few AI traffic cars around itself during a round. The server lets those cars through, keeps them out of every player check, and counts them in the crash fault rule. The leaderboard can filter by traffic, and traffic crashes are labelled.

**Architecture:**
- **Server, pure modules:**
  - The new `cnr/traffic.lua` owns the per-player amount (capped by `MaxCars`, 0 on BeamNG.Earth) and the panel note.
  - `cnr/crash.lua` and `cnr/round.lua` take traffic cars into the fault check and label the cause.
  - `cnr/leaderboard.lua` filters by traffic.
- **Server, `main.lua`:**
  - Tells each game when and how much traffic to spawn, after its round car is placed and the extra cars are cleaned up.
  - Lets traffic through the vehicle rule, takes the game's traffic report, reads traffic positions for the round tick, and shares every player's round car with all games.
- **Client:**
  - The new `copsAndRobbers/traffic.lua` drives the game's `gameplay_traffic`: spawn, hold still, release, delete, report, name tags.
  - The main client file wires it to the round events.

**Tech Stack:** Lua 5.3 (server), LuaJIT / Lua 5.1 (client), Vue 3 apps, `make test`, `make vuecheck`.

**Spec:** `docs/superpowers/specs/2026-11-16-traffic-rounds-design.md`

## Global Constraints
- **The setting:** `trafficPerPlayer`, default 5, a whole number ≥ 0, 0 = off. It is locked during a round like every setting.
- **The cap:** at most `MaxCars − 1` per player in a real round and `MaxCars − 3` for the practice issuer, never below 0. If `MaxCars` can't be read (not a number), there is no cap.
- **BeamNG.Earth:** in geo mode the effective traffic is 0 whatever the setting says. No traffic positions travel as latitude/longitude.
- **Fault rule:** the nearest car within 15 m decides (`CONTACT_RADIUS`, unchanged). Traffic only enters the fault check, never catching, resets, sight, the teleport check or the crash detector.
- **Events:**
  - Server → one game: `cnr_trafficStart {count}`.
  - Game → server: `cnr_trafficCars {vids = [..]}`.
  - Server → games: `cnr_roundCars {keys = ["1-0", "2-3"]}`. Sent to the issuer only in practice.
- **Exact copy:**
  - Notices: "Bob: crash penalty 10s (traffic)", "Traffic could not spawn", "Only 2 of 3 traffic cars spawned".
  - Panel notes: "5 each · 30 cars with 6 players", "5 each · 5 cars with 1 player", "MaxCars is 4 on this server: 3 per player", "MaxCars is 1 on this server: no room for traffic", "Traffic isn't available on BeamNG.Earth yet".
  - Leaderboard filter: "All traffic" / "With traffic" / "No traffic".
  - Round detail: "Traffic: 5 per player".
  - Timeline: "Bob: crash penalty 10 s (traffic)".
- **Traffic vehicles:** official vehicles only. No police, no emergency vehicles, no taxis or other special vehicles, no random traffic events. All spawned cars are active.
- **Project rules:**
  - No chat messages and no pop-ups: everything goes through the apps.
  - No code comments.
  - Client code stays LuaJIT-compatible.
  - The `cnr/*.lua` modules stay pure (no `MP` API).
- **Version:** 2.2.0.
- **Hands off:** do not deploy without asking. Do not touch branch `night-weather-rounds` or the main checkout.

## Review Focus
1. **Lobby traffic still running when a round is set up:** its spawns and edits are refused, and its cars are removed exactly as today, until the server's go-ahead. Tested in Task 3 ("a traffic spawn before the go-ahead is refused").
2. **The round ends while the game's traffic is still spawning:** cars that finish spawning after the round must be deleted, not left in the lobby. Tested in Task 6 ("traffic that finishes spawning after the round is deleted too").
3. **A colour repaint or Apply rebuild right after traffic spawned, before the game has reported it:** no traffic car is removed by the clean-up. Tested in Task 3 ("a repaint after the go-ahead removes no traffic").
4. **`MaxCars` unreadable, or lower than the cars a player needs:** an unreadable value means no cap. Too low means 0 traffic and no go-ahead, never a negative count. Tested in Task 1 (`perPlayer`) and Task 3 ("no go-ahead without room").
5. **A player who joins or reconnects mid-round:** they get the round cars list on join, and their go-ahead after their own car is placed. Tested in Task 3 ("a mid-round joiner gets the round cars and its own go-ahead").

---

### Task 1: Setting, cap and rules payload

**Files:**
- Modify: `server/CopsAndRobbers/cnr/config.lua` (`DEFAULTS`, number validation)
- Create: `server/CopsAndRobbers/cnr/traffic.lua`
- Modify: `server/CopsAndRobbers/cnr/rules.lua`
- Modify: `tests/test_config.lua`
- Create: `tests/test_traffic.lua`

**Interfaces:**
- Produces:
  - `config.DEFAULTS.trafficPerPlayer = 5`. Validated as a whole number ≥ 0: add an `integers = { trafficPerPlayer = true }` set checked in `validNumber` with `v == math.floor(v)`.
  - `traffic.perPlayer(setting, maxCars, geo, practice) -> integer`.
    - 0 when `geo`.
    - Otherwise `floor(setting)` (at least 0), capped at `floor(maxCars) − (practice and 3 or 1)` (at least 0) when `tonumber(maxCars)` is a number.
  - `traffic.note(setting, maxCars, geo, players) -> string|nil`, in this order:
    - nil when the setting is ≤ 0.
    - The BeamNG.Earth line when `geo`.
    - When capped below the setting: the MaxCars line, or "no room for traffic" at 0.
    - Otherwise "N each · N×players cars with P player(s)".
  - `rules.payload(cfg, trafficPerPlayer) -> table`. `KEYS` gains `"trafficPerPlayer"`. The second argument, when given, replaces `cfg.trafficPerPlayer`.

- [ ] **Step 1: Write the failing tests**

`tests/test_config.lua`:
```lua
test("traffic per player defaults to 5 and must be a whole number of at least 0", function()
  assertEq(config.merge(nil).trafficPerPlayer, 5)
  assertEq(config.merge({ trafficPerPlayer = 0 }).trafficPerPlayer, 0)
  local cfg, warnings = config.merge({ trafficPerPlayer = 2.5 })
  assertEq(cfg.trafficPerPlayer, 5); assertEq(#warnings, 1)
  assertEq(config.merge({ trafficPerPlayer = -1 }).trafficPerPlayer, 5)
end)
```
`tests/test_traffic.lua`:
```lua
local traffic = require("cnr.traffic")
local rules = require("cnr.rules")
local config = require("cnr.config")

test("per player traffic is capped by MaxCars, practice leaves room for the AI", function()
  assertEq(traffic.perPlayer(5, 6, false, false), 5)
  assertEq(traffic.perPlayer(5, 4, false, false), 3)
  assertEq(traffic.perPlayer(5, 4, false, true), 1)
  assertEq(traffic.perPlayer(5, 2, false, true), 0)
  assertEq(traffic.perPlayer(5, 1, false, false), 0)
  assertEq(traffic.perPlayer(0, 6, false, false), 0)
end)

test("unreadable MaxCars means no cap, BeamNG.Earth means none", function()
  assertEq(traffic.perPlayer(5, nil, false, false), 5)
  assertEq(traffic.perPlayer(5, "lots", false, false), 5)
  assertEq(traffic.perPlayer(5, 6, true, false), 0)
end)

test("the panel note names the cost, the cap or BeamNG.Earth", function()
  assertEq(traffic.note(5, 32, false, 6), "5 each · 30 cars with 6 players")
  assertEq(traffic.note(5, 32, false, 1), "5 each · 5 cars with 1 player")
  assertEq(traffic.note(5, 4, false, 6), "MaxCars is 4 on this server: 3 per player")
  assertEq(traffic.note(5, 1, false, 2), "MaxCars is 1 on this server: no room for traffic")
  assertEq(traffic.note(5, 32, true, 6), "Traffic isn't available on BeamNG.Earth yet")
  assertEq(traffic.note(0, 32, false, 6), nil)
end)

test("the rules payload carries the effective traffic", function()
  local cfg = config.merge(nil)
  assertEq(rules.payload(cfg).trafficPerPlayer, 5)
  assertEq(rules.payload(cfg, 3).trafficPerPlayer, 3)
end)
```

- [ ] **Step 2: Run `make test`.** Expected: FAIL in `test_traffic.lua` (module `cnr.traffic` not found) and in the new config test.
- [ ] **Step 3: Implement** `config.lua`, `traffic.lua` and `rules.lua` as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: trafficPerPlayer setting, capped by MaxCars`

### Task 2: Traffic in the fault rule, and the crash cause

**Files:**
- Modify: `server/CopsAndRobbers/cnr/crash.lua` (`atFault`)
- Modify: `server/CopsAndRobbers/cnr/round.lua` (`tick`, `otherCars`, `note`, `clear`)
- Modify: `tests/test_crash.lua`
- Modify: `tests/test_round.lua`

**Interfaces:**
- Produces:
  - `crash.atFault(selfCar, others) -> boolean, nearest|nil`. The second value is the nearest car within 15 m (nil when none, or when the car has no position or velocity).
  - A traffic car is `{ pos = {x,y,z}, vel = {x,y,z}, traffic = true }`.
  - `Round:tick(now, cars, stations, traffic)`:
    - `traffic` is a list of traffic cars, possibly nil.
    - The round keeps it as `self.prevTraffic` (set next to `self.prevCars` at the end of the tick, cleared in `clear`).
    - `otherCars(pid)` appends `self.prevTraffic`.
  - The penalty effect becomes `{ kind = "penalty", pid, seconds, name, cause = "traffic" | nil }`. `cause` is `"traffic"` when the nearest car returned by `atFault` has `traffic == true`.
  - `Round:note(now, kind, name, seconds, cause)`: the timeline entry gets `cause` when it is given.

- [ ] **Step 1: Write the failing tests**

`tests/test_crash.lua`:
```lua
test("driving into a traffic car is your fault, being hit by one is not", function()
  local cop = { pos = { x = 100, y = 0, z = 0 }, vel = { x = 120 / 3.6, y = 0, z = 0 } }
  local parked = { pos = { x = 108, y = 0, z = 0 }, vel = { x = 0, y = 0, z = 0 }, traffic = true }
  local fault, nearest = crash.atFault(cop, { parked })
  assertEq(fault, true); assertEq(nearest.traffic, true)
  local slow = { pos = { x = 100, y = 0, z = 0 }, vel = { x = 60 / 3.6, y = 0, z = 0 } }
  local oncoming = { pos = { x = 108, y = 0, z = 0 }, vel = { x = -100 / 3.6, y = 0, z = 0 }, traffic = true }
  assertEq((crash.atFault(slow, { oncoming })), false)
end)
```
`tests/test_round.lua` (uses the existing `running()` and `kmh()` helpers):
```lua
local function parkedAt(x) return { { pos = { x = x, y = 0, z = 0 }, vel = { x = 0, y = 0, z = 0 }, traffic = true } } end

test("a cop driving into traffic gets a penalty labelled traffic", function()
  local r = running()
  r:tick(11.25, { [1] = kmh(-500, 0), [2] = kmh(100, 120), [3] = kmh(500, 0) }, {}, parkedAt(108))
  local fx = r:tick(11.5, { [1] = kmh(-500, 0), [2] = kmh(104, 0), [3] = kmh(500, 0) }, {}, parkedAt(108))
  assertEq(find(fx, "penalty", 2).cause, "traffic")
  assertEq(r.timeline[#r.timeline].cause, "traffic")
end)

test("a cop hit by traffic gets no penalty", function()
  local r = running()
  local oncoming = { { pos = { x = 108, y = 0, z = 0 }, vel = { x = -100 / 3.6, y = 0, z = 0 }, traffic = true } }
  r:tick(11.25, { [1] = kmh(-500, 0), [2] = kmh(100, 60), [3] = kmh(500, 0) }, {}, oncoming)
  local fx = r:tick(11.5, { [1] = kmh(-500, 0), [2] = kmh(101, 0), [3] = kmh(500, 0) }, {}, oncoming)
  assertEq(find(fx, "penalty"), nil)
end)

test("a crash with a player or with nothing carries no cause", function()
  local r = running()
  r:tick(11.25, { [1] = kmh(-500, 0), [2] = kmh(100, 120), [3] = kmh(108, 0) }, {})
  local fx = r:tick(11.5, { [1] = kmh(-500, 0), [2] = kmh(104, 0), [3] = kmh(108, 0) }, {})
  assertEq(find(fx, "penalty", 2).cause, nil)
end)

test("traffic never holds the runner and never teleports", function()
  local r = running()
  local fx
  for i = 1, 40 do
    fx = r:tick(11 + i * 0.25, { [1] = kmh(0, 0), [2] = kmh(900, 0), [3] = kmh(-900, 0) }, {}, parkedAt(i % 2 == 0 and 5 or 600))
    assertEq(find(fx, "roundEnd"), nil)
    assertEq(find(fx, "broadcast"), nil)
  end
end)
```

- [ ] **Step 2: Run `make test`.** Expected: the four new round tests and the crash test FAIL (`cause` is nil, or the fourth `tick` argument is ignored).
- [ ] **Step 3: Implement** `atFault`'s second return value, `tick`'s fourth parameter, `prevTraffic`, `otherCars`, `cause` on the effect and on `note`.
- [ ] **Step 4: Run `make test`.** Expected: all pass, including the existing crash and round tests.
- [ ] **Step 5: Commit** `feat: traffic counts in the crash fault rule, traffic crashes are labelled`

### Task 3: Traffic cars through the vehicle rule

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`
- Modify: `tests/test_main.lua`

**Interfaces:**
- Consumes: `traffic.perPlayer` (Task 1).
- Produces, in `main.lua`:
  - **State:**
    - `trafficOpen = {}` maps pid → count. It is set when the go-ahead goes out.
    - `trafficVids = {}` maps pid → `{[vid] = true}`.
    - Both are reset wherever `activeVid = {}` is reset today (`handlers.start`, `handlers.test`, the `roundEnd` effect) and cleared for a pid in `cnrOnPlayerDisconnect`.
  - **Helpers:**
    - `local function maxCars()` returns `MP.Settings.MaxCars and tonumber(MP.Get(MP.Settings.MaxCars))`, guarded with `pcall`.
    - `local function trafficFor(pid)` returns `traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, current.test and pid == current.issuerId)`.
  - **`openTraffic(pid)`:** when `trafficFor(pid) > 0` and `trafficOpen[pid] == nil`, it sets `trafficOpen[pid]` and sends `cnr_trafficStart {count}` to that pid.
  - **`cnrOnMyVehicle`:**
    - The clean-up (`MP.RemoveVehicle` of the other cars) still runs, but only when `not current.test and not trafficOpen[pid]`.
    - Then `openTraffic(pid)` runs. This also happens in practice, which returns early today: move that `return` below.
    - Then `pushRoundCars()`.
  - **`vehicleAllowed(pid, vid, data, isSpawn)`:** gains `vid`. After the "not in a round" check:
    - The practice issuer with `trafficOpen[pid]` → allowed. BeamMP's own `MaxCars` still limits it.
    - With `trafficOpen[pid]` and `vid ~= activeVid[pid]`: an edit → allowed. A spawn → allowed while the number of the player's cars other than `activeVid[pid]` is below `trafficOpen[pid]`.
    - Otherwise the rule is unchanged.
  - **`cnrOnVehicleSpawn` / `cnrOnVehicleEdited`:**
    - They only set `activeVid[pid] = vid` when `not trafficOpen[pid]`.
    - `checkParts` is skipped when `vid ~= activeVid[pid] and (current.test or trafficOpen[pid])`.
  - **`cnrOnTrafficCars(pid, data)`, registered for `"cnr_trafficCars"`:**
    - Ignored unless `trafficOpen[pid]`.
    - It stores up to `trafficOpen[pid]` numeric vids, never `activeVid[pid]` and never an `aiVid` value.
  - **`pushRoundCars(pid)`:**
    - The keys are `"pid-vid"` from `activeVid` for every non-AI pid in `current.players`, sorted.
    - With a `pid` argument it sends to that pid. Without one, it sends to `current.test and current.issuerId or -1`, and only when the list changed since the last send.
    - The last-sent list resets with the round.
    - `cnrOnPlayerJoin` calls `pushRoundCars(pid)` during an active round. `cnrOnPlayerDisconnect` calls `pushRoundCars()`.
- **Test harness** (`boot` in `tests/test_main.lua`):
  - `MP.Settings = { Map = 4, MaxCars = 2 }`.
  - `MP.Get = function(key) if key == 2 then return opts.maxCars or 1 end return <map as today> end`. A default of 1 keeps every existing test at zero traffic.
  - `GetPositionRaw` first looks up `env.vidPositions[pid .. "-" .. vid]` (a `{pos=..., vel=...}` table), then falls back to today's stub.

- [ ] **Step 1: Write the failing tests** (`boot({ maxCars = 6 })` unless noted; `placed(env, pid)` sends `cnr_myVehicle {vid=0}`):
  - `"after the round car is placed, the game is told how much traffic to spawn"`:
    - After `env.startRound()` and `cnr_myVehicle` from pid 2: `env.lastSent("cnr_trafficStart")` has pid 2 and `"count":5`.
    - With `maxCars = 4` the count is 3.
  - `"no go-ahead without room"`, three cases with no `cnr_trafficStart` at all:
    - `maxCars = 1`.
    - `config` with `"trafficPerPlayer":0`.
    - `map = "/levels/beamng_earth/info.json"`.
  - `"the go-ahead comes after the clean-up"`:
    - Pid 1 starts with cars `{[0]="x",[1]="y",[2]="z"}`.
    - After `cnr_myVehicle {vid=0}`: `#env.removed == 2`, and `cnr_trafficStart` goes to pid 1.
  - `"a traffic spawn before the go-ahead is refused"`:
    - After `startRound()`, before `cnr_myVehicle`, `onVehicleSpawn(2, 4, 'USER:Bob:2-4:{"jbm":"etk800","vcf":{}}')` returns 1.
  - `"traffic spawns pass up to the count, the next is refused"`:
    - After the go-ahead for pid 2 (`count = 5`), five spawns of `etk800` with vids 1 to 5 return 0. Add each to `env.vehicles[2]` before the next.
    - The sixth returns 1.
  - `"a traffic edit is never deleted, never a parts change, and never becomes the player's car"`:
    - After the go-ahead for pid 2, edits of vid 3 with two different `etk800` part lists both return 0, and `partsLines(env) == 0`.
    - In the chase, `onVehicleReset(2, 3, "")` gives no notice, and `onVehicleReset(2, 0, "")` gives "Bob reset illegally".
  - `"a repaint after the go-ahead removes no traffic"`:
    - After the go-ahead for pid 2, set `env.vehicles[2] = {[0]="x",[3]="t",[4]="t"}`.
    - Then `cnr_color` from pid 2 in prep, followed by `cnr_myVehicle {vid=0}` from pid 2, leaves `#env.removed == 0`.
  - `"in practice the issuer may spawn traffic of any model"`:
    - After `test runner`, the pick and `cnr_myVehicle {vid=0}`: `cnr_trafficStart` has `"count":3` (6 − 3).
    - A spawn of `etk800` with vid 5 returns 0.
  - `"everyone learns the round cars"`:
    - After `cnr_myVehicle {vid=0}` from pid 1 and `{vid=3}` from pid 2, the last `cnr_roundCars` has pid −1 and its data contains `"1-0"` and `"2-3"`.
  - `"a mid-round joiner gets the round cars and its own go-ahead"`:
    - Set `env.names = {"Reinder","Bob","Kim"}` and extend `GetPlayers` for pid 3.
    - In the chase, `onPlayerJoin(3)` sends `cnr_roundCars` to pid 3.
    - After `cnr_myVehicle` from pid 3, `cnr_trafficStart` goes to pid 3.
- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL (no `cnr_trafficStart`, spawns refused, `cnr_roundCars` missing).
- [ ] **Step 3: Implement** the Interfaces in `main.lua`, and register `cnr_trafficCars` (storing the report; its positions are read in Task 4).
- [ ] **Step 4: Run `make test`.** Expected: all pass, and every existing `test_main.lua` test still passes.
- [ ] **Step 5: Commit** `feat: traffic cars pass the vehicle rule and never count as the player's car`

### Task 4: Traffic positions, the "(traffic)" notice, rules, panel note, recorded traffic

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`
- Modify: `server/CopsAndRobbers/cnr/panel.lua` (`snapshot`)
- Modify: `tests/test_main.lua`
- Modify: `tests/test_panel.lua`

**Interfaces:**
- Consumes: `traffic.perPlayer` and `traffic.note` (Task 1), `Round:tick(now, cars, stations, traffic)` and the penalty `cause` (Task 2), `trafficVids` (Task 3).
- Produces:
  - **`cnrTick`:** builds `trafficCars` from `trafficVids` with `MP.GetPositionRaw(pid, vid)`, each `{pos, vel, traffic = true}` through `vec.toVec`. It skips errors and passes the list as `current:tick`'s fourth argument. Not in geo mode.
  - **Penalty notice:** `string.format("%s: crash penalty %gs%s", name, seconds, e.cause == "traffic" and " (traffic)" or "")`.
  - **`pushRules`:** sends `rules.payload(cfg, traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, false))`.
  - **`roundTraffic`:**
    - Set in `handlers.start` to `traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, false)`.
    - The `record` effect sets `run.traffic = roundTraffic` when it is > 0. Otherwise the field is left out.
  - **`panelState`:** passes `trafficNote = traffic.note(cfg.trafficPerPlayer, maxCars(), geoMode, <online count>)`, and `panel.snapshot` copies `info.trafficNote` to `trafficNote`.

- [ ] **Step 1: Write the failing tests:**
  - `"a cop who drives into reported traffic gets (traffic) in the notice"` (`boot({ maxCars = 6 })`):
    - Both players placed, the runner reports `cnr_trafficCars {vids={5}}`, and `env.vidPositions["1-5"] = {pos={208,0,0}, vel={0,0,0}}`.
    - Run to the chase, then crash pid 2 the way the existing `"penalty is shown on everyone's screen"` test does (200 m at 120 km/h, then 201 m at 0).
    - The last `cnr_notice` data contains `"msg":"Bob: crash penalty 10s (traffic)"`.
  - `"How to play gets the effective traffic"`:
    - With `maxCars = 4`, the boot-time `cnr_rules` data contains `"trafficPerPlayer":3`.
    - With the BeamNG.Earth map, `"trafficPerPlayer":0`.
  - `"the panel shows the traffic note"`:
    - With `maxCars = 4`, opening the panel gives `cnr_panelState` data containing `"trafficNote":"MaxCars is 4 on this server: 3 per player"`.
  - `"a recorded run keeps its traffic, and a traffic crash's cause survives the save"`:
    - With `maxCars = 6`: the full round from the notice test, ended with `env.panel(2, "end")`.
    - The saved `data/leaderboard.json` contains `"traffic":5` and `"cause":"traffic"`.
    - With `maxCars = 1`, a saved run has no `"traffic"`.
  - `"reported traffic keeps out the player's own car and stops at the count"` (`boot({ maxCars = 6 })`):
    - `cnr_trafficCars` from pid 2 with vids `{0,1,2,3,4,5,6,7}`.
    - Wrap `MP.GetPositionRaw` to record the vids asked for pid 2 during one `cnr_tick` in the chase: exactly 5 distinct traffic vids, plus vid 0 for the player itself.
  - `tests/test_panel.lua`, `"snapshot passes the traffic note"`: `panel.snapshot({ trafficNote = "x" }).trafficNote == "x"`.
- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: traffic positions in the crash check, traffic in rules, panel and runs`

### Task 5: Leaderboard traffic filter

**Files:**
- Modify: `server/CopsAndRobbers/cnr/leaderboard.lua` (`matches`, `rounds`)
- Modify: `server/CopsAndRobbers/main.lua` (`boardState`, `cnrOnBoard`)
- Modify: `tests/test_leaderboard.lua`
- Modify: `tests/test_main.lua`

**Interfaces:**
- Produces:
  - **`matches(r, filter)`:** reads `filter.traffic`.
    - `"with"` keeps runs with `(tonumber(r.traffic) or 0) > 0`.
    - `"without"` keeps runs with `(tonumber(r.traffic) or 0) == 0`.
    - Anything else keeps all runs.
    - Every list (`best`/`runners`, `cops`, `players`, `rounds`, `rankOf`) already goes through `matches`. Check each one does.
  - **`rounds()` entries:** gain `traffic = r.traffic`.
  - **`boardState`:**
    - `f.traffic` is `sub.traffic` when it is `"with"` or `"without"`.
    - It returns `traffic = f.traffic or "all"`.
  - **`cnrOnBoard` filter message:** keeps `traffic = type(msg.traffic) == "string" and msg.traffic or nil`, the same way `mode` is handled.

- [ ] **Step 1: Write the failing tests:**
  - `tests/test_leaderboard.lua`, `"the traffic filter splits runs with and without traffic"`:
    - Runs `a` (`traffic = 5`, 300 s), `b` (no field, 200 s) and `c` (`traffic = 0`, 100 s).
    - `leaderboard.runners(board, {traffic = "with"}, 10)` has only a.
    - `{traffic = "without"}` gives b and c.
    - `{}` gives all three.
    - `#leaderboard.rounds(board, {traffic = "without"})` is 2, and `leaderboard.rounds(board, {traffic = "with"})[1].traffic` is 5.
  - `tests/test_leaderboard.lua`, `"a timeline cause reaches the rounds list"`:
    - A run with timeline `{{t=3, kind="penalty", name="Bob", seconds=10, cause="traffic"}}` gives `rounds(board)[1].timeline[1].cause == "traffic"`.
  - `tests/test_main.lua`, `"the board app can filter by traffic"`:
    - A filter message with `"traffic":"with"` gives `cnr_boardState` data containing `"traffic":"with"`.
    - A later filter message without `traffic` gives `"traffic":"all"`.
- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: leaderboard filter by traffic`

### Task 6: Client traffic

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/traffic.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`
- Modify: `tests/client_stubs.lua`
- Modify: `tests/test_client.lua`

**Interfaces:**
- Consumes: `cnr_trafficStart {count}` and `cnr_roundCars {keys}` from the server (Tasks 3 and 4).
- Produces, `copsAndRobbers/traffic.lua`:
  - **`M.setNotify(fn)`:** like `ai.setNotify`.
  - **`M.civilian(info) -> boolean`.** `info` is an entry of `core_vehicles.getConfigList(true).configs`. Returns false when:
    - `info` is nil.
    - `info.Source ~= "BeamNG - Official"`.
    - The lowercased `info["Config Type"]` is `"police"`.
    - The lowercased `key` or `Name` contains any of `police`, `sheriff`, `interceptor`, `ambulance`, `fire`, `rescue`, `emergency`, `taxi`.
  - **`M.start(count, held, clock)`:**
    1. `gameplay_traffic.deleteVehicles()`, to clear the player's lobby traffic.
    2. `gameplay_traffic.setTrafficVars({ activeAmount = count, enableRandomEvents = false })`.
    3. Build the group: `gameplay_traffic_trafficUtils.createTrafficGroup(count * 2)`, keep the entries whose config passes `civilian` (look the config up by `model_key` and `key` in the config list), and trim to `count`.
    4. `gameplay_traffic.spawnTraffic(#group, group)`. This skips the special-vehicle providers: no police, no reserved taxi.
    - Remembers `count`, `held`, `startedAt = clock`, and `running = true`.
    - With no `gameplay_traffic`, or an empty group, it notifies "Traffic could not spawn" at once and stays stopped.
  - **Holding by freezing** (`controller.setFreeze`) keeps the game's traffic AI ticking, so its own headlight rule still runs for held cars (the spec's night-prep requirement). Task 9 checks this in game. If it turns out not to hold, the fallback is to set `electrics.setLightsState(1)` on held cars at night, using the same night window: `core_environment.getTimeOfDay()` and `core_solarTimeOfDay.getSolarNightWindow`.
  - **`M.release()`:** sets `held = false` and sends `controller.setFreeze(0)` once to each traffic car.
  - **`M.stop(clock)`:**
    - Only acts if `running`: calls `deleteVehicles()`, sets `running = false` and `cleanupUntil = clock + 15`.
    - Clears the `hideNametag` it set, and the round cars list.
  - **`M.tick(clock, active) -> vids|nil`. Traffic cars** are the `getTrafficData()` entries with `isAi == true` whose object exists and `MPVehicleGE.isOwn(id)`.
    - While running and held: send `controller.setFreeze(1)` to each traffic car every 0.5 s.
    - While running, every 1 s: the sorted server vids (`game.serverVid`) of the traffic cars. Return them only when they differ from the last returned list.
    - At `startedAt + 15`, once: notify "Traffic could not spawn" (0 cars) or `string.format("Only %d of %d traffic cars spawned", n, count)` (fewer than `count`), with tone `"warn"`.
    - Not running and `clock < cleanupUntil`: if any traffic cars exist, `deleteVehicles()`.
    - While `active`: hide BeamMP name tags. For every key in `MPVehicleGE.getVehicles()` whose owner pid (`^(%d+)%-`) has a round car and which is not a round car, set `v.hideNametag = true` and remember it.
  - **Round cars:**
    - `M.setRoundCars(keys)` stores the set, and each owner's round car.
    - `M.roundCar(pid) -> key|nil`.
    - `M.isTraffic(key) -> boolean`: the owner has a round car and the key isn't it.
- Produces, `copsAndRobbers.lua`:
  - A local `runnerOut`: true from `onRunnerGo`, or from a setup whose phase is `"headstart"` or `"running"`. Reset in `endRound`.
  - `cnr_trafficStart` → `traffic.start(d.count, not runnerOut, clock)`.
  - `cnr_roundCars` → `traffic.setRoundCars(d.keys)`.
  - `onRunnerGo` → `traffic.release()`.
  - `endRound` → `traffic.stop(clock)`.
  - `onUpdate`: `local vids = traffic.tick(clock, active)`. If any, `sendServer("cnr_trafficCars", { vids = vids })`.
  - `onExtensionLoaded`: `traffic.setNotify` to a warn HUD event.
  - **`runnerObject()`:**
    1. The AI runner.
    2. `traffic.roundCar(runnerId)` when known.
    3. The runner's `activeVehicleID`, unless `traffic.isTraffic(key)`.
    4. Otherwise nil. The "any car of the runner" loop goes.
- **Stubs** (`tests/client_stubs.lua`):
  - **`gameplay_traffic`:**
    - `spawnTraffic(amount, group)` records `{amount, group}` in `env.trafficSpawns`. Unless `env.deferTraffic`, it adds `amount` fake vehicles (`env.addObject`, ids from `env.nextId`) to `env.gameTraffic[id] = {isAi = true}`.
    - `env.finishTraffic()` adds them later.
    - `deleteVehicles()` deletes every `env.gameTraffic` object, empties it, and counts calls in `env.trafficDeletes`.
    - `getTrafficData()` returns `env.gameTraffic`.
    - `setTrafficVars(v)` stores `env.trafficVars = v`.
  - **`gameplay_traffic_trafficUtils.createTrafficGroup(n)`:** alternates `{model="pickup", config="d15_4wd_A"}` and `{model="fullsize", config="police"}`.
  - **`opts.configs`** default:
    - `{model_key="pickup", key="d15_4wd_A", Source="BeamNG - Official", ["Config Type"]="Factory", Name="D15 4WD"}`
    - `{model_key="fullsize", key="police", Source="BeamNG - Official", ["Config Type"]="Police", Name="Police"}`
  - **`MPVehicleGE.isOwn`:** also true for ids in `env.gameTraffic`.
  - **The existing `copInChase` helper** also fires `cnr_roundCars {keys={"2-0"}}`.

- [ ] **Step 1: Write the failing tests:**
  - `"traffic spawns only on the server's go-ahead, without police"`:
    - After `startCop`, `#env.trafficSpawns == 0`.
    - `cnr_trafficStart {count=3}` gives `env.trafficSpawns[1].amount == 3`, every group entry has `model == "pickup"`, and `env.trafficVars.enableRandomEvents == false`.
  - `"traffic stands still until the runner's GO"`:
    - After the go-ahead and `env.tick(1)`, each traffic object's commands contain `"controller.setFreeze(1)"`.
    - After `cnr_runnerGo {headStartSeconds=7}`, they contain `"controller.setFreeze(0)"`, and `env.tick(2)` adds no further `setFreeze(1)`.
  - `"traffic for a player who joins during the chase drives at once"`:
    - Setup with `phase = "running"`, then the go-ahead: no `"controller.setFreeze(1)"` on any traffic object.
  - `"traffic is deleted at round end and on leaving, never when none was started"`:
    - `cnr_roundEnd` after a go-ahead: `env.trafficDeletes` goes up and no traffic object remains.
    - A round without a go-ahead ending leaves `env.trafficDeletes` unchanged.
    - `onBeamMPServerLeave` after a go-ahead deletes too.
  - `"traffic that finishes spawning after the round is deleted too"`:
    - With `env.deferTraffic = true`: go-ahead, `cnr_roundEnd`, `env.finishTraffic()`, `env.tick(1)`.
    - No traffic object remains.
  - `"the game reports its traffic cars once per change"`:
    - After the go-ahead, `env.tick(1.2)`: `env.lastSent("cnr_trafficCars").vids` lists the 3 traffic ids, sorted.
    - `env.tick(2)` sends no new report.
    - Deleting one traffic object, then `env.tick(1.2)`, sends a report with 2.
  - `"traffic cars have no name tags, players keep theirs"`:
    - `env.mpVehicles` has `"1-100"`, `"2-0"` and `"2-5"`, and `cnr_roundCars {keys={"1-100","2-0"}}` arrives.
    - After `env.tick(0.2)`: `env.mpVehicles["2-5"].hideNametag == true`, and `"2-0"`'s is nil.
    - After `cnr_roundEnd`, `"2-5"`'s is nil again.
  - **Replace** `"sight follows the car the runner is driving, not a parked one"` with `"sight follows the runner's round car, never one of his traffic cars"`:
    - With round cars `{"2-0"}`, the runner's `activeVehicleID = "2-1"` (a far traffic object 301 at y=900) still gives `seen == true`.
    - Then, with `traffic.setRoundCars({})` via `cnr_roundCars {keys={}}` and `activeVehicleID = "2-1"`, `seen == false`.
  - `"a failed traffic spawn tells the player once"`:
    - With `env.deferTraffic = true` and never finished, `env.tick(16)` gives a HUD event "Traffic could not spawn" exactly once.
    - Spawning 2 of 3 (a stub override) gives "Only 2 of 3 traffic cars spawned".
- [ ] **Step 2: Run `make test`.** Expected: the new tests FAIL (no handler for `cnr_trafficStart`, module missing).
- [ ] **Step 3: Implement** `traffic.lua` and the main file wiring, as in Interfaces.
- [ ] **Step 4: Run `make test` and `luajit -bl client/lua/ge/extensions/copsAndRobbers/traffic.lua >/dev/null`.** Expected: all tests pass and it compiles.
- [ ] **Step 5: Commit** `feat: each game runs its own traffic during a round`

### Task 7: Panel, How to play and leaderboard UI

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/settings.js` (`GROUPS`, Round group)
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/PanelSettings.vue`
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`helpBlock`)
- Modify: `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
- Modify: `client/ui/modules/apps/CopsAndRobbersLeaderboard/app.vue`
- Modify: `client/ui/modules/apps/CopsAndRobbersLeaderboard/board.js` (`eventText`)
- Modify: `client/ui/modules/apps/CopsAndRobbersLeaderboard/BoardRounds.vue` (`detailSub`)
- Modify: `tests/test_hud.lua`

**Interfaces:**
- Consumes: `trafficNote` in the panel state (Task 4), `trafficPerPlayer` in the rules (Task 4), `traffic` on the board state and on each round, `cause` on timeline entries (Tasks 4 and 5).
- Produces:
  - **The settings item**, in the Round group after Time limit:
    ```js
    { key: "trafficPerPlayer", label: "Traffic", unit: "per player", step: 1, min: 0, common: true, offAtZero: true,
      help: "AI traffic cars around each player during a round" }
    ```
  - **`PanelSettings.vue`:** under that item's `set-help`, a second `set-help` line with `state.trafficNote` when `item.key === 'trafficPerPlayer'` and the note is set.
  - **`hud.lua` `helpBlock`:** `r.trafficOn = (tonumber(rules.trafficPerPlayer) or 0) > 0`.
  - **`HowToPlay.vue`:**
    - Basics, after the first paragraph: `<p v-if="trafficOn">There's traffic: <span class="v">{{ value("trafficPerPlayer") }}</span> cars around each player.</p>`.
    - The Crash penalty line ends, when `trafficOn`, with " Driving into traffic counts too; being hit by it doesn't."
    - `trafficOn` is `computed(() => r.value.trafficOn === true)`.
  - **Leaderboard `app.vue`:**
    - `TRAFFIC = [{value:"all",label:"All traffic"},{value:"with",label:"With traffic"},{value:"without",label:"No traffic"}]`.
    - A third `BngDropdown v-model="trafficFilter"`.
    - `filter(map, mode, traffic)` sends `{action:"filter", map, mode, traffic}`. The map and mode setters pass `state.value.traffic` along.
  - **`board.js` penalty text:** appends `" (traffic)"` when `e.cause === "traffic"`.
  - **`BoardRounds.vue` `detailSub`:** adds `Traffic: ${n} per player` when `Number(r.traffic) > 0`.

- [ ] **Step 1: Write the failing test** (`tests/test_hud.lua`, using its `rules()` helper), `"How to play knows whether traffic is on"`:
  - `hud.payload(hud.new(), 0, { helpOpen = true, rules = rules({ trafficPerPlayer = 5 }) }).help.rules.trafficOn == true`.
  - With `trafficPerPlayer = 0`: `false`.
- [ ] **Step 2: Run `make test`.** Expected: the new test FAILS.
- [ ] **Step 3: Implement** the Interfaces.
- [ ] **Step 4: Run `make test` and `make vuecheck`.** Expected: all tests pass; vuecheck reports no compile, SCSS, syntax or icon errors.
- [ ] **Step 5: Commit** `feat: traffic in the panel, How to play and the leaderboard`

### Task 8: Docs, version, verification

**Files:**
- Modify: `README.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/DEPENDENCIES.md`
- Modify: `server/CopsAndRobbers/main.lua` (`VERSION`)
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`CLIENT_VERSION`)
- Modify: `client/mod_info/CopsAndRobbers/info.json`
- Modify: the `"2.1.0"` strings in `tests/test_client.lua`

- [ ] **Step 1: Version 2.2.0** in the three code places and the tests.
- [ ] **Step 2: README:**
  - The settings row: `trafficPerPlayer` | 5 | "AI traffic cars around each player (0 = off; normal maps only, not on BeamNG.Earth yet)".
  - The install line: `MaxCars` must be at least 1 + traffic per player (3 + traffic for practice).
  - A tip that BeamMP's "Simplify remote vehicles" option lightens other players' traffic.
- [ ] **Step 3: FEATURES:**
  - Round flow (traffic spawns in prep, stands still until GO).
  - Vehicle rules (traffic cars allowed up to the cap).
  - The crash penalty fault rule with traffic, and "(traffic)".
  - The leaderboard traffic filter and the traffic on each round.
  - How to play, the settings table, and the BeamNG.Earth section (traffic off there for now).
  - "AI traffic" stays in the locked list.
  - Update the test count.
- [ ] **Step 4: DEPENDENCIES:**
  - A `gameplay_traffic` subsection under the GE section: `deleteVehicles`, `setTrafficVars({activeAmount, enableRandomEvents})`, `trafficUtils.createTrafficGroup`, `spawnTraffic(amount, group)` (it skips the police and taxi providers that `setupTraffic` would add), `getTrafficData()[id].isAi`, and the game's own headlight rule.
  - Config list fields `Source`, `Config Type`, `key`, `Name` for the civilian filter.
  - The BeamMP server: `MP.Get(MP.Settings.MaxCars)`, and BeamMP syncing traffic as normal cars.
  - The BeamMP client: `MPVehicleGE.getVehicles()[key].hideNametag`.
  - The quick check gains a practice round with traffic, checking that:
    - cars spawn and stand still until GO, with headlights on when it's night;
    - they have no name tags and no police or emergency vehicles;
    - a cop driving into one gets "(traffic)";
    - all are gone after the round.
  - Note under BeamNG.Earth why traffic is off there.
- [ ] **Step 5: Verify:**
  - `make test`: all pass, with the count noted.
  - `make vuecheck`: clean.
  - `for f in client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/*.lua; do luajit -bl "$f" >/dev/null || echo "$f"; done`: no output.
- [ ] **Step 6: Commit** `feat: 2.2.0 - traffic during rounds`

### Task 9: Final review and in-game check
- [ ] A fresh reviewer reads the whole branch against the spec. Fix what it finds and re-run Task 8's verification.
- [ ] In game, after asking the user (`make install-local`; `.testserver` has `MaxCars = 4`, so ask before raising it): a practice round as cop with traffic, going through Task 8's DEPENDENCIES check.
- [ ] Ask the user before any deploy or merge.
