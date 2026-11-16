# Night and Weather Rounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The host can give rounds a time of day, a running clock, weather (with rain/snow, temperature, wet grip and gusty wind) for everyone, with random picks by configurable chances and a New sky reroll in prep.

**Architecture:** The server picks the round's sky (pure `cnr/sky.lua`), keeps it on the round and sends it in `cnr_roundSetup` and a new `cnr_sky` message. Each client applies it through `core_environment` (save, set, lock), its own precipitation object, ground model swaps (`surfaces.lua`) and a deterministic gust model (`wind.lua`), and restores everything when the round ends.

**Tech Stack:** Lua (server: BeamMP, Lua 5.3; client: BeamNG GE Lua, LuaJIT), Vue 3 panel app, tests with `make test` (`tests/run.lua`), UI syntax check with `make vuecheck`.

**Spec:** `docs/superpowers/specs/2026-11-16-night-weather-design.md` (read it first; this plan does not repeat the game API facts in its Constraints section).

## Global Constraints

- No code comments, no emojis (AGENTS.md).
- Client code must run on LuaJIT (Lua 5.1 syntax: no `//`, no `goto` labels in new code, no integer/bit operators). Server code runs on Lua 5.3. Tests run with `lua5.3`.
- Defaults that keep existing setups unchanged: `timeOfDay = "map"`, `weather = "map"`, `clockSpeed = 0`, `nightChancePercent = 25`, `badWeatherChancePercent = 25`, `weatherDriving = true`.
- Time keys: `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night`. Weather keys: `clear`, `cloudy`, `rain`, `storm`, `fog`, `snow`. Labels are the capitalised key ("Night", "Rain"), joined with `" · "`.
- On `beamng_earth` the server sends no sky.
- A client only touches the sky when the round sets something (time or weather set, or `clockSpeed > 0`).
- Wind seed: whole number 1 to 2147483646; generator `seed = seed * 16807 % 2147483647` (exact in doubles); never `math.random` on the client for wind.
- Commit messages: `feat:` / `fix:` / `docs:` prefix, say why, end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Every task ends with `make test` passing (`N passed, 0 failed`); UI tasks also `make vuecheck`; tasks that add or change client Lua also `luajit -bl <file> >/dev/null` for each such file (the tests run on Lua 5.3, this checks LuaJIT syntax).
- The game's `getState().groundWind` and `getInitState().groundWind` are the live wind vector, not copies (`environment.lua:30`, `:878`, `:1375`, `:1785`): never keep them without copying x, y and z.

## Review Focus

1. **The player's sky must be saved once per round**: New car, a rejoin and `cnr_sky` re-apply mid-round; restore must still bring back the sky from before the round, not a round sky. Pinned in Task 6 (`saves the player's sky only once`).
2. **New sky from a wet weather to a dry one** must put surfaces back and remove the rain object, not stack changes. Pinned in Task 5 (`a new weather first puts the old surfaces back`) and Task 6 (`a calm sky removes our precipitation object`).
3. **After the round nothing keeps running**: no wind updates, no lock, no precipitation object, original surfaces. Pinned in Task 6 (`restore stops the wind updates`).
4. **A player whose sky was locked before the round** (another mod) gets it locked again after; a player whose sky was unlocked gets it unlocked. Pinned in Task 6 (`restore puts the earlier lock back`).
5. **The player's own ground wind comes back after the round** (the game's state holds the live wind vector, so a saved copy taken carelessly changes with the round's wind). Pinned in Task 6 (`restore gives the player's own wind back`).
6. **BeamNG.Earth never gets a sky or New sky**, also with a clock speed set. Pinned in Task 2 (`nothing is sent on BeamNG.Earth, also with a clock speed`) and Task 3 (`Earth rounds get no sky`).
7. **A rejoin mid-chase with a running clock or wind** lands on the same time and gust as everyone else. Pinned in Task 3 (`a mid-chase join gets clockSeconds`) and Task 7 (`a mid-chase setup starts the clock at clockSeconds`).

---

### Task 1: Sky settings on the server

**Files:**
- Modify: `server/CopsAndRobbers/cnr/config.lua` (`DEFAULTS`, `CHOICES`, `MAXIMA`, `validNumber`, `M.setValue`)
- Modify: `server/CopsAndRobbers/cnr/panel.lua` (`applyValues` warning match)
- Test: `tests/test_config.lua`

**Interfaces:**
- Produces: `cfg.timeOfDay`, `cfg.nightChancePercent`, `cfg.clockSpeed`, `cfg.weather`, `cfg.badWeatherChancePercent`, `cfg.weatherDriving` with the defaults from Global Constraints.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_config.lua`)

```lua
test("sky settings have defaults", function()
  local c = config.merge(nil)
  assertEq(c.timeOfDay, "map"); assertEq(c.nightChancePercent, 25); assertEq(c.clockSpeed, 0)
  assertEq(c.weather, "map"); assertEq(c.badWeatherChancePercent, 25); assertEq(c.weatherDriving, true)
end)

test("every time and weather choice is accepted", function()
  for _, t in ipairs({ "map", "sunrise", "morning", "noon", "afternoon", "sunset", "night", "random" }) do
    assertEq(config.merge({ timeOfDay = t }).timeOfDay, t)
  end
  for _, w in ipairs({ "map", "clear", "cloudy", "rain", "storm", "fog", "snow", "random" }) do
    assertEq(config.merge({ weather = w }).weather, w)
  end
end)

test("sky settings reject unknown choices and out-of-range numbers", function()
  local c, w = config.merge({ timeOfDay = "dusk", weather = "hail", nightChancePercent = 101, badWeatherChancePercent = -1, clockSpeed = 121 })
  assertEq(c.timeOfDay, "map"); assertEq(c.weather, "map")
  assertEq(c.nightChancePercent, 25); assertEq(c.badWeatherChancePercent, 25); assertEq(c.clockSpeed, 0)
  assertEq(#w, 5)
end)

test("clock speed must be a whole number", function()
  local c, w = config.merge({ clockSpeed = 2.5 })
  assertEq(c.clockSpeed, 0); assertEq(#w, 1)
  assertEq(config.merge({ clockSpeed = 120 }).clockSpeed, 120)
end)

test("a broken weatherDriving doesn't block saving weather", function()
  local updated = config.setValue({ weatherDriving = "yes" }, "weather", "rain")
  assertEq(updated ~= nil, true)
  assertEq(updated.weather, "rain")
end)
```

- [ ] **Step 2: Run** `make test` — expected: the new tests FAIL (`expected map, got nil`; the setValue test returns nil).

- [ ] **Step 3: Implement in `cnr/config.lua`**: add the six keys to `DEFAULTS`; add `timeOfDay` and `weather` sets to `CHOICES` (values as in the test); add `nightChancePercent = 100`, `badWeatherChancePercent = 100`, `clockSpeed = 120` to `MAXIMA`; add a `WHOLE = { clockSpeed = true }` set that `validNumber` checks (`v % 1 == 0`). `weather` is a prefix of `weatherDriving`, so the warning match in `config.setValue` (`config.lua:143`) and `panel.applyValues` (`panel.lua:162`) must match `key .. " "` at the start of the warning instead of `key`.

- [ ] **Step 4: Run** `make test` — expected: all pass. If another test counts every setting (for example a panel or chat listing), update its expected count, not the new keys.

- [ ] **Step 5: Commit** — `feat: sky settings for night and weather rounds`

---

### Task 2: Server sky picking (`cnr/sky.lua`)

**Files:**
- Create: `server/CopsAndRobbers/cnr/sky.lua`
- Test: `tests/test_sky.lua`

**Interfaces:**
- Consumes: the Task 1 settings.
- Produces:
  - `sky.pick(cfg, random, geo) -> table`: `{}` when `geo` is true; otherwise `{ time = key|nil, weather = key|nil, windDir = integer, windSeed = integer }`.
  - `sky.hasRandom(cfg) -> boolean`: time or weather is `"random"`.
  - `sky.payload(s, cfg, clockSeconds) -> table|nil`: `nil` when `s` is nil or empty (`next(s) == nil`, which is what Earth gets), or when `s.time`, `s.weather` are nil and `cfg.clockSpeed` is 0; otherwise `{ time, weather, clockSpeed (only > 0), driving (true only when s.weather and cfg.weatherDriving), windDir, windSeed, clockSeconds }`.
- `random` follows `math.random`: `random()` for chance rolls (night when `random() * 100 < nightChancePercent`, same for bad weather), `random(#list)` to pick from a list, `random(0, 359)` for `windDir`, `random(1, 2147483646)` for `windSeed`. Day list: sunrise, morning, noon, afternoon, sunset. Calm list: clear, cloudy. Bad list: rain, storm, fog, snow (in that order).

- [ ] **Step 1: Write the failing tests** (`tests/test_sky.lua`)

```lua
local sky = require("cnr.sky")
local config = require("cnr.config")

local function rng(roll, index)
  return function(m, n)
    if m == nil then return roll end
    if n == nil then return math.min(index, m) end
    return m
  end
end
local function cfg(o) return (config.merge(o)) end

test("map choices pick no time or weather but still pick wind", function()
  local s = sky.pick(cfg(nil), rng(0.5, 1))
  assertEq(s.time, nil); assertEq(s.weather, nil); assertEq(s.windDir, 0); assertEq(s.windSeed, 1)
end)

test("fixed choices are kept", function()
  local s = sky.pick(cfg({ timeOfDay = "sunset", weather = "fog" }), rng(0.5, 1))
  assertEq(s.time, "sunset"); assertEq(s.weather, "fog")
end)

test("random time follows the night chance", function()
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 100 }), rng(0.99, 1)).time, "night")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 0 }), rng(0, 3)).time, "noon")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 25 }), rng(0.2499, 1)).time, "night")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 25 }), rng(0.25, 1)).time, "sunrise")
end)

test("random weather follows the bad weather chance", function()
  assertEq(sky.pick(cfg({ weather = "random", badWeatherChancePercent = 100 }), rng(0.5, 4)).weather, "snow")
  assertEq(sky.pick(cfg({ weather = "random", badWeatherChancePercent = 0 }), rng(0.5, 2)).weather, "cloudy")
end)

test("nothing is picked on BeamNG.Earth", function()
  assertEq(next(sky.pick(cfg({ weather = "rain", timeOfDay = "night" }), rng(0, 1), true)), nil)
end)

test("hasRandom sees a random time or weather", function()
  assertEq(sky.hasRandom(cfg(nil)), false)
  assertEq(sky.hasRandom(cfg({ timeOfDay = "random" })), true)
  assertEq(sky.hasRandom(cfg({ weather = "random" })), true)
end)

test("payload is nil when the round sets nothing", function()
  assertEq(sky.payload({ windDir = 10, windSeed = 5 }, cfg(nil), nil), nil)
end)

test("payload carries a clock speed even with the map's own sky", function()
  local p = sky.payload({ windDir = 10, windSeed = 5 }, cfg({ clockSpeed = 30 }), nil)
  assertEq(p.clockSpeed, 30); assertEq(p.time, nil); assertEq(p.driving, nil); assertEq(p.windSeed, 5)
end)

test("payload sends driving only with a weather and the switch on", function()
  local s = { weather = "rain", windDir = 10, windSeed = 5 }
  assertEq(sky.payload(s, cfg({ weather = "rain" }), nil).driving, true)
  assertEq(sky.payload(s, cfg({ weather = "rain", weatherDriving = false }), nil).driving, nil)
  assertEq(sky.payload({ time = "night", windDir = 1, windSeed = 1 }, cfg(nil), nil).driving, nil)
  assertEq(sky.payload(s, cfg(nil), nil).clockSpeed, nil)
end)

test("nothing is sent on BeamNG.Earth, also with a clock speed", function()
  local c = cfg({ clockSpeed = 30, weather = "rain" })
  assertEq(sky.payload(sky.pick(c, rng(0, 1), true), c, nil), nil)
  assertEq(sky.payload(nil, c, nil), nil)
end)

test("payload passes clockSeconds", function()
  assertEq(sky.payload({ time = "noon", windDir = 1, windSeed = 1 }, cfg(nil), 12.5).clockSeconds, 12.5)
end)
```

- [ ] **Step 2: Run** `make test` — expected: `tests/test_sky.lua` fails to load (`module 'cnr.sky' not found`).
- [ ] **Step 3: Implement** `cnr/sky.lua` with the three functions above.
- [ ] **Step 4: Run** `make test` — expected: all pass.
- [ ] **Step 5: Commit** — `feat: server picks the round's sky by the configured chances`

---

### Task 3: The round carries the sky; setup, New sky and the panel

**Files:**
- Modify: `server/CopsAndRobbers/cnr/round.lua` (`Round:clear`, `Round:start`)
- Modify: `server/CopsAndRobbers/cnr/panel.lua` (`COMMANDS`, `M.can`, `M.snapshot`)
- Modify: `server/CopsAndRobbers/main.lua` (`require("cnr.sky")`, `handlers.start`, `handlers.test`, the `setup` branch of `applyEffects`, new `handlers.sky`, `panelState`)
- Test: `tests/test_round.lua`, `tests/test_panel.lua`, `tests/test_main.lua`

**Interfaces:**
- Consumes: `sky.pick`, `sky.hasRandom`, `sky.payload` (Task 2).
- Produces:
  - `round.sky` (table or nil): set from `opts.sky` in `Round:start`, cleared in `Round:clear`; New car (`reroll`) keeps it.
  - `cnr_roundSetup` payload gains `sky = sky.payload(current.sky, cfg, clockSeconds)` where `clockSeconds = current.countdownStartedAt and math.max(0, now() - current.countdownStartedAt) or nil` (so it is absent before GO).
  - New client event `cnr_sky`, data = the same payload table, sent to every non-AI pid in `current.players` on New sky.
  - Panel command `sky`; `panel.can(state, test, evolving, skyRandom)` gains `sky = (state == "prep" or state == "ready") and skyRandom == true`; `panel.snapshot(info)` passes `info.skyRandom`; `panelState()` sets `skyRandom = not geoMode and sky.hasRandom(cfg)`.
- `handlers.sky(pid)`: on Earth (`geoMode`) → reply `"Not available on BeamNG.Earth yet"`; state not `prep`/`ready` → reply `"You can only change the sky before GO"`; no random setting → reply `"Set time of day or weather to random first"`; else `current.sky = sky.pick(cfg, math.random, geoMode)` and send `cnr_sky`. The "New sky: Night · Rain" notice is shown by the client when `cnr_sky` arrives (Task 7), so the server sends no notice text.
- `handlers.start` passes `{ build = ..., sky = sky.pick(cfg, math.random, geoMode) }` to `current:start` (the pick must happen before `start`, because evolving mode emits setup effects from inside `start`); `handlers.test` adds `sky = ...` to its opts.

- [ ] **Step 1: Write the failing tests**

`tests/test_round.lua`:
```lua
test("start keeps the sky it is given, New car keeps it, clear drops it", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players, { sky = { weather = "rain" } })
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  r:reroll(2, 2)
  r:vehiclePicked(3, 2, "etk800", "cfg", players)
  assertEq(r.sky.weather, "rain")
  r:clear()
  assertEq(r.sky, nil)
end)
```

`tests/test_panel.lua`:
```lua
test("New sky is offered before GO with a random setting", function()
  assertEq(panel.allow("sky"), "sky")
  assertEq(panel.can("prep", false, false, true).sky, true)
  assertEq(panel.can("ready", false, true, true).sky, true)
  assertEq(panel.can("prep", false, false, false).sky, false)
  assertEq(panel.can("countdown", false, false, true).sky, false)
  assertEq(panel.snapshot({ phase = "prep", skyRandom = true }).can.sky, true)
end)
```

`tests/test_main.lua` (after the local `countSent` helper; `EARTH` is the Earth map path defined at `test_main.lua:501`; if a geo-mode round needs more setup before `cnr_roundSetup` is sent, follow the existing Earth tests there):
```lua
test("round setup has no sky by default", function()
  local env = boot()
  env.startRound()
  assertEq(env.lastSent("cnr_roundSetup").data:find('"sky"', 1, true), nil)
  env.cleanup()
end)

test("round setup carries a fixed sky", function()
  local env = boot({ config = '{"timeOfDay":"night","weather":"rain"}' })
  env.startRound()
  local s = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(s.time, "night"); assertEq(s.weather, "rain"); assertEq(s.driving, true); assertEq(s.clockSeconds, nil)
  env.cleanup()
end)

test("New car keeps the sky", function()
  local env = boot({ config = '{"weather":"random"}' })
  env.startRound()
  local seed = decodeJson(env.lastSent("cnr_roundSetup").data).sky.windSeed
  env.panel(2, "reroll")
  env.call("cnr_vehiclePicked", 2, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).sky.windSeed, seed)
  env.cleanup()
end)

test("New sky goes to the round's players before GO only", function()
  local env = boot({ config = '{"weather":"random"}' })
  env.startRound()
  env.sent = {}
  env.panel(1, "sky")
  assertEq(countSent(env, "cnr_sky", 1), 1); assertEq(countSent(env, "cnr_sky", 2), 1)
  env.go()
  env.panel(1, "sky")
  assertEq(env.replyHas("before GO"), true)
  env.cleanup()
end)

test("New sky needs a random setting", function()
  local env = boot()
  env.startRound()
  env.panel(1, "sky")
  assertEq(env.replyHas("to random first"), true)
  env.cleanup()
end)

test("Earth rounds get no sky", function()
  local env = boot({ map = EARTH, config = '{"clockSpeed":30,"weather":"rain"}' })
  env.startRound()
  local setup = env.lastSent("cnr_roundSetup")
  if setup then assertEq(setup.data:find('"sky"', 1, true), nil) end
  env.panel(1, "sky")
  assertEq(env.replyHas("BeamNG.Earth"), true)
  env.cleanup()
end)

test("a practice round gets a sky too", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } }, config = '{"weather":"snow"}' })
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).sky.weather, "snow")
  env.cleanup()
end)

test("a mid-chase join gets clockSeconds", function()
  local env = boot({ config = '{"clockSpeed":30}' })
  env.startRound(); env.go()
  env.positions[1], env.positions[2] = 0, 900
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.names = { "Reinder", "Bob", "Cid" }
  env.call("onPlayerJoin", 3)
  assertNear(decodeJson(env.lastSent("cnr_roundSetup").data).sky.clockSeconds, 15, 0.01)
  env.cleanup()
end)
```

- [ ] **Step 2: Run** `make test` — expected: the new tests FAIL (`sky` nil, no `cnr_sky` sent).
- [ ] **Step 3: Implement** the round, panel and main changes listed under Interfaces.
- [ ] **Step 4: Run** `make test` — expected: all pass.
- [ ] **Step 5: Commit** — `feat: rounds carry their sky to every player, with New sky before GO`

---

### Task 4: Gust model (`copsAndRobbers/wind.lua`)

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/wind.lua`
- Test: `tests/test_wind.lua`

**Interfaces:**
- Produces: `wind.at(weather, seed, dirDeg, t) -> x, y, z` (m/s, `z` always 0). `dirDeg` is where the wind pushes: `x = speed * sin(rad)`, `y = speed * cos(rad)`. Calm weathers (`clear`, `cloudy`, `fog`, `nil`, unknown) return `0, 0, 0`.
- Values (`wind.WEATHER`): rain `{ steady = 4, peak = 10, every = {10, 25}, length = {2, 5}, turn = 0 }`; storm `{ steady = 12, peak = 25, every = {5, 15}, length = {2, 6}, turn = 30 }`; snow `{ steady = 3, peak = 8, every = {10, 25}, length = {2, 5}, turn = 0 }`.
- Gust schedule from the seed only (Park–Miller, Global Constraints): starting at `t = 0`, repeatedly draw a gap in `every`, a length in `length`, a strength `steady + (peak - steady) * (0.5 + 0.5 * r)` and a turn in `[-turn, turn]` degrees. Inside a gust the speed is `steady + (strength - steady) * sin(pi * (t - start) / length)` and the direction turns by `turn * sin(...)`. An invalid seed (not 1 to 2147483646) is treated as 1. Caching the schedule per `(weather, seed)` is allowed.

- [ ] **Step 1: Write the failing tests** (`tests/test_wind.lua`)

```lua
local wind = require("copsAndRobbers/wind")

local function speed(x, y) return math.sqrt(x * x + y * y) end

test("calm weathers have no wind", function()
  for _, w in ipairs({ "clear", "cloudy", "fog" }) do
    local x, y, z = wind.at(w, 7, 0, 30)
    assertEq(x, 0); assertEq(y, 0); assertEq(z, 0)
  end
  assertEq((wind.at(nil, 7, 0, 30)), 0)
end)

test("at the start only the steady wind blows, towards dirDeg", function()
  local x, y = wind.at("rain", 7, 90, 0)
  assertNear(x, 4, 1e-6); assertNear(y, 0, 1e-6)
end)

test("the same seed and time give the same wind, another seed differs", function()
  local same, differs = true, false
  for t = 0, 120, 0.5 do
    local ax, ay = wind.at("storm", 12345, 40, t)
    local bx, by = wind.at("storm", 12345, 40, t)
    local cx, cy = wind.at("storm", 777, 40, t)
    if ax ~= bx or ay ~= by then same = false end
    if math.abs(ax - cx) > 0.01 or math.abs(ay - cy) > 0.01 then differs = true end
  end
  assertEq(same, true); assertEq(differs, true)
end)

test("storm gusts come within a minute", function()
  local strongest = 0
  for i = 0, 600 do
    local x, y = wind.at("storm", 4242, 0, i * 0.1)
    strongest = math.max(strongest, speed(x, y))
  end
  assertEq(strongest > 18, true)
end)

test("storm gusts never pass the peak or turn more than 30 degrees", function()
  for i = 0, 6000 do
    local t = i * 0.1
    local x, y = wind.at("storm", 4242, 0, t)
    assertEq(speed(x, y) <= 25 + 1e-6, true, "peak at " .. t)
    assertEq(math.abs(math.deg(math.atan(x, y))) <= 30 + 1e-6, true, "turn at " .. t)
  end
end)
```

(`math.atan(x, y)` is the Lua 5.3 two-argument form in the test only; in `wind.lua` use `math.sin`/`math.cos` and no `atan2`.)

- [ ] **Step 2: Run** `make test` — expected: `module 'copsAndRobbers/wind' not found`.
- [ ] **Step 3: Implement** `wind.lua` as specified under Interfaces.
- [ ] **Step 4: Run** `make test` — expected: all pass.
- [ ] **Step 5: Commit** — `feat: deterministic wind gusts every player's game computes the same`

---

### Task 5: Fake environment for tests, and wet/snow surfaces (`copsAndRobbers/surfaces.lua`)

**Files:**
- Create: `tests/env_stubs.lua` (test helper)
- Create: `client/lua/ge/extensions/copsAndRobbers/surfaces.lua`
- Test: `tests/test_surfaces.lua`

**Interfaces:**
- Produces (test helper) `fakeEnvironment(opts) -> fake` (`opts` may be nil), installing `_G.core_environment`, `_G.be`, `_G.createObject`, `_G.scenetree` and `_G.vec3` (if missing, a function returning `{ x = x, y = y, z = z }`). The fake behaves like the game where it matters: setters and `setState` are ignored while locked.
  - `fake.state` — current state: `time = 0.1, play = true, dayLength = 1800, cloudCover = 0.3, fogDensity = 1, windSpeed = 1, groundWind = vec3(0, 0, 0), temperatureCurveOverrideC = false`; `getState()` returns a shallow copy whose `groundWind` is the live `fake.state.groundWind` vector itself (as in the game); `setState(s)` (when unlocked) sets x, y and z of `fake.state.groundWind` in place from `s.groundWind`, merges the other fields of `s`, and appends a copy of `s` to `fake.setStates`.
  - `fake.init` — what `getInitState()` returns: a copy of the starting state whose `groundWind` is also the live `fake.state.groundWind` vector (as in the game).
  - `fake.locked`, `enableChanges(b)` sets `fake.locked = not b`, `canChange()` returns `not fake.locked`; `fake.locked` starts as `opts.locked or false`.
  - `getSolarTimeOfDayValue(key)` returns `timeOfDayKeyToTime[key]`; `timeOfDayKeyToTime = { sunrise = 0.775, morning = 0.825, noon = 0, afternoon = 0.175, sunset = 0.245, night = 0.5 }`.
  - `setTemperatureProfile(p)` appends to `fake.profiles` when unlocked.
  - `getLightState()` returns `{ isNight = fake.state.time > 0.25 and fake.state.time < 0.75 }`.
  - `fake.models` is the same table as `core_environment.groundModels`: ASPHALT (static 0.98, sliding 0.70, roughness 0) with alias CONCRETE (same `cdata` table, `isAlias = true, parent = "ASPHALT"`), ASPHALT_WET (0.92, 0.55, 0.2), RUMBLE_STRIP (0.98, 0.70, 0.5), GRAVEL (0.69, 0.74, 0.44), GRAVEL_WET (0.62, 0.60, 0.38), DIRT (0.70, 0.73, 0.42) with alias DIRT_GRASS, MUD (0.55, 0.55, 0.5, defaultDepth 0.15), GRASS (0.61, 0.65, 0.43), SNOW (0.65, 0.40, 0.3), SAND (0.6, 0.6, 0.5); every `cdata` also has `hydrodynamicFriction, stribeckVelocity, defaultDepth, strength, fluidDensity, flowConsistencyIndex, flowBehaviorIndex, dragAnisotropy, shearStrength`.
  - `be:setGroundModel(name, cdata)` appends `{ name = name, static = cdata.staticFrictionCoefficient, sliding = cdata.slidingFrictionCoefficient }` to `fake.modelSets`; `be:queueAllObjectLua(cmd)` appends to `fake.queued`; `be:setGroundWind(v)` appends to `fake.groundWinds`.
  - `createObject(class)` returns an object with `setField(name, _, value)`, `getField(name)`, `registerObject(name)` (stores it in `fake.objects[name]`), `delete()` (removes it, appends name to `fake.deleted`); `scenetree.findObject(name)` reads `fake.objects`; `scenetree.MissionGroup:addObject(obj)` is a no-op.
- Produces `surfaces.apply(weather)`, `surfaces.restore()`, `surfaces.drop()`:
  - `apply` first restores anything this module changed, then applies `surfaces.RULES[weather]` (the spec's Surfaces table). A rule is `{ targets = {...}, become = "ASPHALT_WET" }` (copy the spec's physics fields from the source `cdata`) or `{ targets = {...}, static = f, sliding = f }` (multiply the two friction values). Targets missing from `core_environment.groundModels` are skipped. Before changing a target the first time, save its physics fields. After changing it, call `be:setGroundModel` for the target and for every model whose `isAlias` and `parent == target`.
  - `restore` writes the saved fields back, calls `be:setGroundModel` for each target and its aliases, and forgets them. `drop` only forgets.
  - Weathers without rules (`clear`, `cloudy`, `fog`, nil) change nothing.

- [ ] **Step 1: Write the failing tests** (`tests/test_surfaces.lua`)

```lua
dofile("tests/env_stubs.lua")
local function load()
  package.loaded["copsAndRobbers/surfaces"] = nil
  return require("copsAndRobbers/surfaces")
end
local function cd(fake, name) return fake.models[name].cdata end

test("rain makes asphalt the game's wet asphalt, aliases included", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("rain")
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.92)
  assertEq(cd(fake, "ASPHALT").roughnessCoefficient, 0.2)
  local names = {}
  for _, m in ipairs(fake.modelSets) do names[m.name] = true end
  assertEq(names.ASPHALT, true); assertEq(names.CONCRETE, true)
end)

test("rain makes dirt wet gravel, a storm makes it mud", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("rain"); assertEq(cd(fake, "DIRT").staticFrictionCoefficient, 0.62)
  s.apply("storm"); assertEq(cd(fake, "DIRT").defaultDepth, 0.15)
  assertEq(cd(fake, "GRAVEL").staticFrictionCoefficient, 0.62)
end)

test("grass and rumble strips are scaled, not replaced", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("storm")
  assertNear(cd(fake, "GRASS").staticFrictionCoefficient, 0.61 * 0.75, 1e-9)
  assertNear(cd(fake, "GRASS").roughnessCoefficient, 0.43, 1e-9)
  assertNear(cd(fake, "RUMBLE_STRIP").slidingFrictionCoefficient, 0.70 * 0.79, 1e-9)
  assertNear(cd(fake, "RUMBLE_STRIP").roughnessCoefficient, 0.5, 1e-9)
end)

test("snow covers roads, dirt, grass and wet ground but not sand", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("snow")
  for _, n in ipairs({ "ASPHALT", "RUMBLE_STRIP", "GRAVEL", "DIRT", "GRASS", "GRAVEL_WET", "MUD" }) do
    assertEq(cd(fake, n).staticFrictionCoefficient, 0.65, n)
  end
  assertEq(cd(fake, "SAND").staticFrictionCoefficient, 0.6)
end)

test("a new weather first puts the old surfaces back", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("snow"); s.apply("rain")
  assertEq(cd(fake, "GRAVEL_WET").staticFrictionCoefficient, 0.62)
  assertEq(cd(fake, "DIRT").staticFrictionCoefficient, 0.62)
  s.apply("clear")
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.98)
end)

test("restore puts every surface back, drop leaves them", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("storm"); s.restore()
  assertEq(cd(fake, "ASPHALT").slidingFrictionCoefficient, 0.70)
  assertEq(cd(fake, "DIRT").defaultDepth, 0)
  s.apply("rain"); s.drop(); s.restore()
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.92)
end)
```

- [ ] **Step 2: Run** `make test` — expected: `module 'copsAndRobbers/surfaces' not found`.
- [ ] **Step 3: Implement** `tests/env_stubs.lua` and `surfaces.lua` as specified.
- [ ] **Step 4: Run** `make test` — expected: all pass.
- [ ] **Step 5: Commit** — `feat: rain, storm and snow swap in the game's own wet, mud and snow surfaces`

---

### Task 6: Client sky (`copsAndRobbers/sky.lua`)

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/sky.lua`
- Test: `tests/test_sky_client.lua`

**Interfaces:**
- Consumes: `wind.at` (Task 4), `surfaces.apply/restore/drop` (Task 5), the payload from Task 3 (`time, weather, clockSpeed, driving, windDir, windSeed, clockSeconds`).
- Produces:
  - `sky.label(p) -> string|nil` — e.g. `"Night · Rain"`, `"Snow"`, nil when neither is set.
  - `sky.apply(p)` — nothing when `p` is nil or sets nothing (no time, no weather, no `clockSpeed`). Otherwise: if nothing is saved this round, save `core_environment.getState()` with `groundWind` copied (`vec3(g.x, g.y, g.z)`, because the game hands out its live vector) and `wasLocked = not core_environment.canChange()`; `enableChanges(true)`; one `setState` with the whole round sky; temperature; precipitation; surfaces (when `p.driving`); `enableChanges(false)`.
    - Time fields: a set time gives `time = getSolarTimeOfDayValue(key) or timeOfDayKeyToTime[key]`, `play = false`; no time gives `time` and `dayLength` from `getInitState()` with `play = false` (the clock is stopped for the whole round unless a clock speed starts it at GO). Remember the applied `time` as the clock start.
    - Weather fields from `sky.WEATHER[key]` (`cloudCover`, `fogDensity`, `windSpeed`); no weather takes those from `getInitState()`.
    - `groundWind = vec3(wind.at(p.weather, p.windSeed, p.windDir, 0))` when `p.driving` and the weather is windy, else `vec3(0, 0, 0)`, so every player in the round has the same wind.
    - Temperature: the `setState` always has `temperatureCurveOverrideC = false` (back to the map's curve, dropping any curve the player made); weathers with `temperatureC` then call `setTemperatureProfile({ averageC = temperatureC })`.
    - Precipitation: always delete our object `cnr_precipitation` if it exists; weathers with `precipitation` create it again (`createObject("Precipitation")`, `setField` for `dataBlock, numDrops, dropSize, minSpeed, maxSpeed, boxWidth = 40, boxHeight = 20, useWind = 1`, `registerObject("cnr_precipitation")`, `scenetree.MissionGroup:addObject`). `numOfDrops` is never passed to `setState`.
    - Surfaces: `surfaces.apply(p.driving and p.weather or nil)`.
  - `sky.startClock(clockSeconds)` — sets the round time to `clockSeconds or 0`; with `clockSpeed > 0`: unlock, `setState({ time = (start + clockSeconds * speed / 86400) % 1, play = true, dayLength = 86400 / speed })`, lock.
  - `sky.update(dt)` — once started, the round time advances by `dt`; while the sky has wind (`p.driving` and a windy weather) it applies the wind every 0.25 s with `be:queueAllObjectLua(string.format("obj:setWind(%f,%f,%f)", x, y, z))` and `be:setGroundWind(vec3(x, y, z))` at the round time (0 before `startClock`). It never calls `enableChanges`.
  - `sky.restore()` — if something is saved: unlock, `setState(saved)`, `surfaces.restore()`, delete `cnr_precipitation`, `enableChanges(not wasLocked)`, forget everything (round time, wind, saved state).
  - `sky.drop()` — `surfaces.drop()`, `enableChanges(not wasLocked)` if something was saved, forget everything; no `setState`.
  - `sky.isNight() -> boolean` — `core_environment.getLightState()` and its `isNight`, false when missing.
  - Every function returns quietly when `core_environment` is nil. `sky.lua` and `surfaces.lua` read `core_environment`, `be`, `createObject` and `scenetree` as globals at call time (no locals cached at load), so tests can swap the fakes.
- Starting weather values (`sky.WEATHER`, tuned in Task 9): clear `{ cloudCover = 0.2, fogDensity = 1, windSpeed = 1 }`; cloudy `{ cloudCover = 0.9, fogDensity = 2, windSpeed = 2 }`; rain `{ cloudCover = 1.0, fogDensity = 4, windSpeed = 3, temperatureC = 8, precipitation = { dataBlock = "rain_medium", numDrops = 3000, dropSize = 1, minSpeed = 0.1, maxSpeed = 0.3 } }`; storm `{ cloudCover = 1.2, fogDensity = 8, windSpeed = 8, temperatureC = 8, precipitation = { dataBlock = "rain_medium", numDrops = 6000, dropSize = 1, minSpeed = 0.1, maxSpeed = 0.3 } }`; fog `{ cloudCover = 0.4, fogDensity = 25, windSpeed = 1, temperatureC = 5 }`; snow `{ cloudCover = 1.0, fogDensity = 5, windSpeed = 2, temperatureC = -5, precipitation = { dataBlock = "Snow_menu", numDrops = 5000, dropSize = 0.2, minSpeed = 0.1, maxSpeed = 0.3 } }`.

- [ ] **Step 1: Write the failing tests** (`tests/test_sky_client.lua`)

```lua
dofile("tests/env_stubs.lua")
local function load(opts)
  local fake = fakeEnvironment(opts)
  for _, n in ipairs({ "copsAndRobbers/sky", "copsAndRobbers/surfaces", "copsAndRobbers/wind" }) do package.loaded[n] = nil end
  return require("copsAndRobbers/sky"), fake
end
local RAIN_NIGHT = { time = "night", weather = "rain", driving = true, windDir = 90, windSeed = 7 }

test("labels join the time and the weather", function()
  local sky = load()
  assertEq(sky.label(RAIN_NIGHT), "Night · Rain")
  assertEq(sky.label({ weather = "snow" }), "Snow")
  assertEq(sky.label({ clockSpeed = 30 }), nil)
end)

test("a sky that sets nothing touches nothing", function()
  local sky, fake = load()
  sky.apply(nil); sky.apply({ windDir = 1, windSeed = 1 })
  assertEq(#fake.setStates, 0); assertEq(fake.locked, false)
end)

test("a round sky is applied and locked", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.time, 0.5); assertEq(s.play, false); assertEq(s.cloudCover, 1.0); assertEq(s.numOfDrops, nil)
  assertNear(s.groundWind.x, 4, 1e-6)
  assertEq(fake.profiles[1].averageC, 8)
  assertEq(fake.objects.cnr_precipitation:getField("dataBlock"), "rain_medium")
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.92)
  assertEq(fake.locked, true)
end)

test("a part on the map's own comes from the map's start values", function()
  local sky, fake = load()
  fake.state.time = 0.3
  sky.apply({ weather = "fog", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].time, 0.1); assertEq(fake.setStates[1].play, false)
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
  assertEq(fake.profiles[1].averageC, 5)
end)

test("restore gives the player's own wind back", function()
  local sky, fake = load()
  fake.state.groundWind.x = 1
  sky.apply({ weather = "storm", driving = true, windDir = 0, windSeed = 7 })
  assertEq(fake.state.groundWind.y > 1, true)
  sky.restore()
  assertEq(fake.state.groundWind.x, 1); assertEq(fake.state.groundWind.y, 0)
end)

test("a round without a windy weather has no ground wind", function()
  local sky, fake = load()
  fake.state.groundWind.x = 3
  sky.apply({ time = "night", windDir = 0, windSeed = 1 })
  assertEq(fake.state.groundWind.x, 0)
end)

test("weathers without a temperature hand the map's curve back", function()
  local sky, fake = load()
  sky.apply({ time = "noon", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
end)

test("saves the player's sky only once", function()
  local sky, fake = load()
  fake.state.cloudCover = 0.05
  sky.apply(RAIN_NIGHT); sky.apply(RAIN_NIGHT)
  sky.apply({ time = "noon", weather = "snow", driving = true, windDir = 0, windSeed = 3 })
  sky.restore()
  assertEq(fake.state.cloudCover, 0.05); assertEq(fake.state.time, 0.1)
end)

test("a calm sky removes our precipitation object", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  sky.apply({ time = "night", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(fake.objects.cnr_precipitation, nil)
end)

test("restore puts the earlier lock back", function()
  local sky, fake = load({ locked = true })
  sky.apply(RAIN_NIGHT); sky.restore()
  assertEq(fake.locked, true)
  local sky2, fake2 = load()
  sky2.apply(RAIN_NIGHT); sky2.restore()
  assertEq(fake2.locked, false)
end)

test("restore stops the wind updates and removes everything", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
  for _ = 1, 4 do sky.update(0.25) end
  local before = #fake.queued
  assertEq(before >= 3, true)
  sky.restore(); sky.update(1)
  assertEq(#fake.queued, before)
  assertEq(fake.objects.cnr_precipitation, nil)
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
end)

test("wind updates don't touch the lock", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
  local states = #fake.setStates
  sky.update(2)
  assertEq(#fake.setStates, states); assertEq(fake.locked, true)
  assertEq(fake.queued[1]:find("obj:setWind(", 1, true) ~= nil, true)
end)

test("driving off leaves surfaces and wind alone", function()
  local sky, fake = load()
  sky.apply({ weather = "storm", windDir = 0, windSeed = 1 }); sky.startClock(0); sky.update(1)
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
  assertEq(#fake.queued, 0)
end)

test("the clock starts at GO at the configured speed", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", clockSpeed = 60, windDir = 0, windSeed = 1 })
  sky.startClock(600)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
  assertNear(s.time, (0.245 + 600 * 60 / 86400) % 1, 1e-9)
end)

test("drop forgets without applying", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  local n = #fake.setStates
  sky.drop(); sky.restore()
  assertEq(#fake.setStates, n); assertEq(fake.locked, false)
end)

test("isNight follows the game's light state", function()
  local sky, fake = load()
  assertEq(sky.isNight(), false)
  sky.apply(RAIN_NIGHT)
  assertEq(sky.isNight(), true)
end)
```

- [ ] **Step 2: Run** `make test` — expected: `module 'copsAndRobbers/sky' not found`.
- [ ] **Step 3: Implement** `sky.lua` as specified.
- [ ] **Step 4: Run** `make test` — expected: all pass.
- [ ] **Step 5: Commit** — `feat: players' games apply the round's sky and give their own back afterwards`

---

### Task 7: Client wiring, prep card and AI headlights

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`onRoundSetup`, `onCountdown`, `endRound`, new `onSky`, `onUpdate`, `updateLightsAndPatch`, event registration, `M.onClientEndMission`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hudfeed.lua` (`M.prep`, new `M.prepSky`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`center` role card)
- Modify: `client/lua/ge/extensions/copsAndRobbers/ai.lua` (`M.lightsOn`)
- Modify: `tests/client_stubs.lua` (`bootClient` installs `fakeEnvironment()` as `env.sky`, before it loads `copsAndRobbers.lua`)
- Test: `tests/test_client.lua`, `tests/test_hud.lua`

**Interfaces:**
- Consumes: `sky.*` (Task 6), `fakeEnvironment` (Task 5).
- Produces:
  - `hudfeed.prep(role, car, waiting, runner, skyLabel)`, `hudfeed.prepSky(skyLabel)`; `hud.lua`'s role card sets `car` to the car and the sky label joined by `" · "` (either may be missing).
  - `ai.lightsOn(headlights)` — as today for cop lightbars; with `headlights` true every AI car also gets `"electrics.setLightsState(1)"`.
- Wiring:
  - `onRoundSetup`: `sky.apply(d.sky)`; `hudfeed.prep(..., sky.label(d.sky))`; for phases `countdown`, `headstart` and `running` call `sky.startClock(d.sky and d.sky.clockSeconds or 0)`.
  - `onSky(data)` registered for `cnr_sky`: `sky.apply(d)`, `hudfeed.prepSky(sky.label(d))`, and `hudfeed.event("New sky: " .. label, clock, "info")` when there is a label.
  - `onCountdown`: `sky.startClock(0)`.
  - `endRound`: `sky.restore()` (covers round end, cancel and leaving the server).
  - `M.onClientEndMission = function() sky.drop(); leaveServer() end`.
  - `onUpdate`: `sky.update(dtReal or 0)`.
  - `updateLightsAndPatch`: `ai.lightsOn(sky.isNight())`.

- [ ] **Step 1: Write the failing tests**

`tests/test_hud.lua`:
```lua
test("the role card adds the round's sky to the car line", function()
  local s = hud.new()
  local info = { active = true, role = "cop", prep = { role = "cop", car = "Gavril D-Series", sky = "Night · Rain", waiting = "go" } }
  assertEq(hud.payload(s, 0, info).center.car, "Gavril D-Series · Night · Rain")
end)
```

`tests/test_client.lua` (uses `SETUP`, `copy` and `startCop` already in the file):
```lua
test("a round sky is applied at setup and shown on the role card", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { time = "night", weather = "rain", driving = true, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  assertEq(env.sky.locked, true)
  assertEq(env.hud().center.car, "Gavril Pickup · Night · Rain")
end)

test("New sky updates the card and says so", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { weather = "rain", windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  env.fire("cnr_sky", { time = "noon", weather = "snow", windDir = 0, windSeed = 9 })
  env.tick(0.2)
  assertEq(env.hud().center.car, "Gavril Pickup · Noon · Snow")
  assertEq(env.sky.objects.cnr_precipitation:getField("dataBlock"), "Snow_menu")
end)

test("the countdown starts the round clock", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { time = "sunset", clockSpeed = 60, windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  env.fire("cnr_countdown", { seconds = 3 })
  local s = env.sky.setStates[#env.sky.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
end)

test("a mid-chase setup starts the clock at clockSeconds", function()
  local env = bootClient()
  local d = copy(SETUP); d.phase = "running"; d.chaseElapsed = 100
  d.sky = { time = "sunset", clockSpeed = 60, clockSeconds = 110, windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d); env.tick(0.1)
  assertNear(env.sky.state.time, (0.245 + 110 * 60 / 86400) % 1, 1e-6)
end)

test("the round end gives the player's sky back, a map change only forgets it", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { weather = "storm", driving = true, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  env.fire("cnr_roundEnd", { reason = "cancelled" })
  assertEq(env.sky.locked, false); assertEq(env.sky.state.cloudCover, 0.3)
  env.fire("cnr_roundSetup", d); env.tick(1)
  local n = #env.sky.setStates
  env.M.onClientEndMission()
  assertEq(#env.sky.setStates, n)
end)

test("practice AI cars turn their headlights on at night", function()
  local env = bootClient()
  local d = copy(SETUP); d.role = "runner"; d.runnerId = 1; d.inPlace = true
  d.sky = { time = "night", windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d)
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -1, role = "cop", index = 1, name = "AI cop 1" } } })
  env.tick(3)
  local cmds = table.concat(env.spawned[1].veh.commands, "\n")
  assertEq(cmds:find("electrics.setLightsState(1)", 1, true) ~= nil, true)
end)
```

If the AI setup event or fields differ from what `copsAndRobbers.lua` registers (check its `AddEventHandler` list and `ai.setup`), adjust the test's event data, not the assertion.

- [ ] **Step 2: Run** `make test` — expected: the new tests FAIL (`env.sky` nil, card without the sky).
- [ ] **Step 3: Implement** the wiring, the `hudfeed`/`hud`/`ai` changes, and `bootClient` setting `env.sky = fakeEnvironment()` before its `loadfile("client/lua/ge/extensions/copsAndRobbers.lua")` line (with `dofile("tests/env_stubs.lua")` at the top of `client_stubs.lua`).
- [ ] **Step 4: Run** `make test` — expected: all pass, including every existing client test.
- [ ] **Step 5: Commit** — `feat: round setup, New sky, GO and round end drive the sky in every game`

---

### Task 8: Panel: Sky settings and the New sky button

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/settings.js` (`GROUPS`, `shown`, `stepped`)
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/PanelSettings.vue` (item filter, Earth line)
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/PanelRound.vue` (New sky button)

**Interfaces:**
- Consumes: `state.settings` keys (Task 1), `state.can.sky` and `state.geo` (Task 3).
- A **Sky** group right after **Round** in `GROUPS`:
  - `timeOfDay` — label "Time of day", `kind: "choice"`, `common: true`, options `map` "Map default", `sunrise` "Sunrise", `morning` "Morning", `noon` "Noon", `afternoon` "Afternoon", `sunset` "Sunset", `night` "Night", `random` "Random"; help "The time the chase starts at; random follows the night chance".
  - `nightChancePercent` — "Night chance", unit "%", step 5, min 0, max 100, `when: v => v("timeOfDay") === "random"`; help "How often a random time of day is night".
  - `clockSpeed` — "Clock speed", step 1, min 0, max 120; shows "stopped" at 0 and "N×" otherwise; help "How fast time passes once the chase starts; 1 is real time".
  - `weather` — "Weather", `kind: "choice"`, `common: true`, options `map` "Map default", `clear` "Clear", `cloudy` "Cloudy", `rain` "Rain", `storm` "Storm", `fog` "Fog", `snow` "Snow", `random` "Random"; help "Random follows the bad weather chance".
  - `badWeatherChancePercent` — "Bad weather chance", unit "%", step 5, min 0, max 100, `when: v => v("weather") === "random"`; help "How often random weather is rain, storm, fog or snow".
  - `weatherDriving` — "Weather affects driving", `kind: "bool"`; help "Rain, storm and snow change grip and bring gusty wind".
- `shown(item, v)` returns the option label for `kind: "choice"`; `stepped` moves a choice to the previous/next option (wrapping), so the existing minus/plus buttons work for it.
- `PanelSettings.vue`: the `common` and `more` lists drop items whose `when(props.store.valueOf)` is false; when `state.geo`, the Sky group shows only a `p-why` line "Not available on BeamNG.Earth yet" under its title, without its settings (the design's choice).
- `PanelRound.vue`: a "New sky" button (`v-if="can.sky"`, secondary accent) next to New car that emits `command` `"sky"`.

- [ ] **Step 1: Implement** the changes above.
- [ ] **Step 2: Run** `make vuecheck` — expected: no errors. Run `make test` — expected: all pass.
- [ ] **Step 3: Commit** — `feat: the panel sets the sky and offers New sky in prep`

---

### Task 9: Docs, version, and the in-game check with the host

**Files:**
- Modify: `README.md` (Settings table rows for the six keys), `docs/FEATURES.md` (a "Night and weather" section: settings, random chances, New sky, clock, grip table summary, wind, temperature, restore after the round, not on BeamNG.Earth), version `2.2.0` in `server/CopsAndRobbers/main.lua` (`VERSION`), `client/lua/ge/extensions/copsAndRobbers.lua` (`CLIENT_VERSION`, line 16; the client warns "rejoin to update" when it differs from the server), `client/mod_info/CopsAndRobbers/info.json` (`version_string`), the `docs/FEATURES.md` title and `tools/previews/panel.svg` (cosmetic); tests expecting `2.1.0` (`tests/test_main.lua:758-759`, the `version = "2.1.0"` lines and the warning text in `tests/test_client.lua`) move to `2.2.0`.
- Modify: `TODO.md` (tick "Night and weather rounds").
- Modify: `docs/DEPENDENCIES.md` (what the sky, weather and grip code relies on in the game and the maps, and what to check when they update).
- Values tuned in game go into `client/lua/ge/extensions/copsAndRobbers/sky.lua` (`WEATHER`), `wind.lua` (`WEATHER`) and `surfaces.lua` (grass factors) with their tests updated.

- [ ] **Step 1: Write the docs and bump the version**; run `make test` and `make vuecheck` — expected: all pass.
- [ ] **Step 2: Add the sky, weather and grip dependencies to `docs/DEPENDENCIES.md`**, in its existing format (Used in / What we use / On update, check):
  - In "BeamNG.drive: game engine Lua (GE)", a **Sky, weather and grip** area (`copsAndRobbers/sky.lua`, `surfaces.lua`, `wind.lua`):
    - `core_environment`: `getState` / `setState` (fields `time`, `play`, `dayLength`, `cloudCover`, `fogDensity` in thousandths, `windSpeed`, `groundWind`, `temperatureCurveOverrideC`), `getInitState`, `enableChanges` / `canChange` (the lock: every setter, `setState` and its fade do nothing while locked), `getSolarTimeOfDayValue(key)` and `timeOfDayKeyToTime` (keys sunrise, morning, noon, afternoon, sunset, night), `setTemperatureProfile({ averageC })`, `getLightState().isNight`, `groundModels[name].{cdata, isAlias, parent}`.
    - `be:setGroundModel(name, cdata)`, `be:queueAllObjectLua(cmd)`, `be:setGroundWind(vec3)`.
    - `createObject("Precipitation")` with the fields `dataBlock`, `numDrops`, `dropSize`, `minSpeed`, `maxSpeed`, `boxWidth`, `boxHeight`, `useWind`; `registerObject`, `delete`, `scenetree.findObject`, `scenetree.MissionGroup:addObject`.
    - **Game data:** the precipitation datablocks `rain_medium` and `Snow_menu` (`art/datablocks/managedDatablocks.datablocks.json` in `gameengine.zip`); the ground models and their alias lists in `art/groundmodels.json` (targets ASPHALT, ASPHALT_OLD, ASPHALT_PREPPED, COBBLESTONE, RUMBLE_STRIP, GRAVEL, DIRT, DIRT_DUSTY, DIRT_DUSTY_LOOSE, GRASS, GRAVEL_WET, MUD; sources ASPHALT_WET, GRAVEL_WET, MUD, SNOW).
    - **Map materials:** maps say which surface a road or terrain layer is by naming one of those ground models or an alias (`groundmodelName` / `groundType` in their material files). Checked on 0.40.5 for west_coast_usa, Utah, italy, east_coast_usa, johnson_valley and jungle_rock_island. A surface name we don't list, or a map with its own `groundModels/` folder (a mod map), stays dry in rain and snow.
    - `getState().groundWind` and `getInitState().groundWind` are the game's live wind vector, not copies; we copy it when saving.
    - While the sky is locked the game skips its own `onVehicleSpawned = applyGroundWind` (the lock check in `applyGroundWind`), so cars spawned during a round get wind only from our 0.25 s updates.
    - On a map change the game's `onClientEndMission` reloads ground models, clears the temperature override and zeroes the wind, but never undoes `enableChanges(false)`; that's why our `drop()` puts the lock back. Check after an update: leave mid-round or change map, and on the next map the environment menu works and grip is normal.
    - On update, check: the functions above still exist (grep the game's `lua/ge/extensions/core/environment.lua`); `groundmodels.json` still has the listed names and aliases with similar values; the two datablocks still exist; the map scan below shows no new road, dirt or grass surface names (add any to `surfaces.lua` `RULES`); in game, a practice round with Night and Rain shows rain and night lights, wet roads slide, gusts push the car, the environment menu is greyed out, and after End chase the sky, grip, wind and menu are back.
    - The map scan (prints each map's surface names with counts):
      ```bash
      for z in ~/.local/share/Steam/steamapps/common/BeamNG.drive/content/levels/*.zip; do echo "== $(basename "$z" .zip): $(unzip -p "$z" '*.json' 2>/dev/null | grep -oi '"groundmodelName" *: *"[^"]*"\|"groundType" *: *"[^"]*"' | sed 's/.*: *"//;s/"//' | tr a-z A-Z | sort | uniq -c | sort -rn | awk '{printf "%s(%s) ", $2, $1}')"; done
      ```
  - In "BeamNG.drive: vehicle Lua and jbeam", the vehicle commands `obj:setWind(x, y, z)` (sent to every car through `be:queueAllObjectLua`) and `electrics.setLightsState(1)` (practice AI headlights at night).
  - In the quick check's practice-round list (step 4), a **Sky** line: with Time of day Night and Weather Rain, rain shows, the AI cars have headlights, and everything is back after End chase; set Time of day and Weather back to Map default afterwards (the panel writes the live server's `config.json`).
  - In the "BeamNG.Earth" section: we send no sky on `beamng_earth`, because a change through `core_environment` flips the player's Earth sky to Manual and saves it in their Earth settings.
  - If the New sky button got an icon, add its name to the UI section's icon list.
- [ ] **Step 3: Commit** — `docs: night and weather rounds in the README, features and dependencies, 2.2.0`
- [ ] **Step 4: Build** `make package` — expected: `dist/Client/CopsAndRobbers.zip` and `dist/Server/CopsAndRobbers/`. Install it on the host's test setup (`make install-local`, or deploy only when the host asks).
- [ ] **Step 5: Check in game with the host** (the spec's in-game list): rain and snow on west_coast_usa and Utah; night lights at night; weather values look right on two or three maps; drag tires against road tires on wet and snow; a road car on a storm's muddy Utah dirt road (stuck too easily → storm dirt becomes GRAVEL_WET); wind strengths and gusts feel right; two players see a storm gust at about the same moment; exhaust steam in snow; clock speed 60 runs dusk into night; a rejoin mid-chase lands on the same time; after the round sky, grip, temperature and wind are back and the environment menu works again.
- [ ] **Step 6: Tune** the values the check calls for, update the affected tests, `make test`, commit — `fix: tune weather values after playing them`.
- [ ] **Step 7: Clean up** — ask the host whether to delete the throwaway test extension `~/.local/share/BeamNG/BeamNG.drive/current/lua/ge/extensions/cnrSnowTest.lua` (outside the repo).
