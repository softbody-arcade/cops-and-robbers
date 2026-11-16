# Day Length and Date Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Clock speed multiplier with the game's day-length list, always set the round's sky (no "Map default", Random by default), and give every round a date picked from its weather.

**Architecture:** The server picks the date in `cnr/sky.lua` together with time and weather, and sends it, plus the day length in seconds, in the sky info every player already gets (`cnr_roundSetup`, `cnr_sky`). The client sets the date in the same `core_environment.setState` call as the time, and works out named times ("sunrise") against that date. Runs record the day-length name and the date.

**Tech Stack:** Lua 5.3 (BeamMP server, `cnr/*`), LuaJIT game extension (client), Vue panel (`settings.js`), tests in `tests/` run by `make test`.

**Spec:** `docs/superpowers/specs/2026-11-16-day-length-and-date-design.md`

## Global Constraints
- Config key `dayLength`: choices `off`, `fast`, `moderate`, `slow`, `realtime`; default `moderate`.
- Seconds per full day: `fast` 900, `moderate` 1800, `slow` 7200, `realtime` 86400; `off` is a stopped clock (no seconds sent).
- `clockSpeed` is removed from the config; an old value gets "unknown setting clockSpeed ignored".
- `timeOfDay` and `weather` lose `map`; both default to `random`.
- Date windows: snow 1 Dec – 31 Jan; fog 1 Oct – 30 Nov; rain and storm 1 Mar – 30 Apr or 1 Oct – 30 Nov; clear and cloudy any day of the year. Never 29 Feb.
- Year: the server's current year.
- Label format: "Sunset · Snow · 14 Dec" (short English month names).
- Panel labels: "Day length"; options "Off", "Fast (15 min)", "Moderate (30 min)", "Slow (2 h)", "Realtime (24 h)"; help "How long a full day lasts once the chase starts".
- No code comments (project rule in AGENTS.md).

## Review Focus
1. A server whose saved config still has `clockSpeed` or `"map"` for time or weather: it starts, warns, and uses Moderate and Random. Test in Task 1.
2. A player who rejoins mid-chase gets the same date as everyone else, and New car keeps the date. Tests in Task 1.
3. Every date the server can pick exists (no 31 Nov, no 29 Feb, January days in a snow window are real days). Test in Task 1.
4. After the round, the player's own date comes back. Test in Task 2.
5. Old leaderboard runs without a date (and with `clockSpeed`) still get a label. Test in Task 2.

---

### Task 1: Server settings, date pick, payload and record

**Files:**
- Modify: `server/CopsAndRobbers/cnr/config.lua:31-34` (DEFAULTS), `:40-44` (CHOICES), `:68-69` (MAXIMA, WHOLE)
- Modify: `server/CopsAndRobbers/cnr/sky.lua` (whole file is 58 lines)
- Test: `tests/test_config.lua:102-129`, `tests/test_sky.lua`, `tests/test_main.lua:832-919`

**Interfaces:**
- Produces (`cnr/sky.lua`):
  - `M.DAY_SECONDS = { fast = 900, moderate = 1800, slow = 7200, realtime = 86400 }`
  - `M.date(weather: string, random: function) -> month: integer, day: integer`. Draws exactly one `random(1, total)` where `total` is the number of days in the weather's window, and counts through the window's months in this order: snow `{12, 1}`, fog `{10, 11}`, rain and storm `{3, 4, 10, 11}`, clear and cloudy `{1..12}`. Days per month `{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}`.
  - `M.pick(cfg, random, geo, year?) -> table`: `{}` when `geo`. Otherwise `{ time, weather, year, month, day, windDir, windSeed }`; `year` defaults to `tonumber(os.date("%Y"))`. Draw order: time, weather, date, windDir, windSeed. `main.lua` call sites stay as they are.
  - `M.payload(s, cfg, clockSeconds) -> table|nil`: nil when `s` is nil or empty. Otherwise `{ time, weather, year, month, day, windDir, windSeed, clockSeconds, daySeconds = M.DAY_SECONDS[cfg.dayLength], driving = true only with s.weather and cfg.weatherDriving }`.
  - `M.record(s, cfg) -> table|nil`: nil when `payload` is nil; otherwise `{ time, weather, year, month, day, dayLength = cfg.dayLength, driving }`.
  - `M.hasRandom(cfg)` unchanged.
- Payload fields the client reads (Task 2): `time`, `weather`, `year`, `month`, `day`, `daySeconds`, `driving`, `windDir`, `windSeed`, `clockSeconds`.

- [ ] **Step 1: Update the config tests in `tests/test_config.lua`**

Replace the four sky tests at `:102-129` (keep "a broken weatherDriving doesn't block saving weather"):

```lua
test("sky settings have defaults", function()
  local c = config.merge(nil)
  assertEq(c.timeOfDay, "random"); assertEq(c.nightChancePercent, 25); assertEq(c.dayLength, "moderate")
  assertEq(c.weather, "random"); assertEq(c.badWeatherChancePercent, 25); assertEq(c.weatherDriving, true)
  assertEq(c.clockSpeed, nil)
end)

test("every time, weather and day length choice is accepted", function()
  for _, t in ipairs({ "sunrise", "morning", "noon", "afternoon", "sunset", "night", "random" }) do
    assertEq(config.merge({ timeOfDay = t }).timeOfDay, t)
  end
  for _, w in ipairs({ "clear", "cloudy", "rain", "storm", "fog", "snow", "random" }) do
    assertEq(config.merge({ weather = w }).weather, w)
  end
  for _, d in ipairs({ "off", "fast", "moderate", "slow", "realtime" }) do
    assertEq(config.merge({ dayLength = d }).dayLength, d)
  end
end)

test("sky settings reject unknown choices and out-of-range numbers", function()
  local c, w = config.merge({ timeOfDay = "dusk", weather = "hail", dayLength = "1800", nightChancePercent = 101, badWeatherChancePercent = -1 })
  assertEq(c.timeOfDay, "random"); assertEq(c.weather, "random"); assertEq(c.dayLength, "moderate")
  assertEq(c.nightChancePercent, 25); assertEq(c.badWeatherChancePercent, 25)
  assertEq(#w, 5)
end)

test("an old config with map and clockSpeed falls back with warnings", function()
  local c, w = config.merge({ timeOfDay = "map", weather = "map", clockSpeed = 30 })
  assertEq(c.timeOfDay, "random"); assertEq(c.weather, "random"); assertEq(c.dayLength, "moderate")
  assertEq(#w, 3)
  assertEq(w[3], "unknown setting clockSpeed ignored")
end)
```

- [ ] **Step 2: Update the sky tests in `tests/test_sky.lua`**

Remove "map choices pick no time or weather but still pick wind", "payload is nil when the round sets nothing", "payload carries a clock speed even with the map's own sky". Change the rest and add the date tests:

```lua
test("random choices are the default and still pick wind", function()
  local s = sky.pick(cfg(nil), rng(0.5, 1), false, 2026)
  assertEq(s.time, "sunrise"); assertEq(s.weather, "clear"); assertEq(s.windDir, 0); assertEq(s.windSeed, 1)
  assertEq(s.year, 2026); assertEq(s.month, 1); assertEq(s.day, 1)
end)

test("the date follows the weather", function()
  local s = sky.pick(cfg({ weather = "snow" }), rng(0.5, 1), false, 2026)
  assertEq(s.month, 12); assertEq(s.day, 1)
  assertEq(sky.pick(cfg({ weather = "fog" }), rng(0.5, 1), false, 2026).month, 10)
  assertEq(sky.pick(cfg({ weather = "rain" }), rng(0.5, 1), false, 2026).month, 3)
end)

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local WINDOWS = {
  snow = { 62, { [12] = true, [1] = true }, { 12, 1 }, { 1, 31 } },
  fog = { 61, { [10] = true, [11] = true }, { 10, 1 }, { 11, 30 } },
  rain = { 122, { [3] = true, [4] = true, [10] = true, [11] = true }, { 3, 1 }, { 11, 30 } },
  storm = { 122, { [3] = true, [4] = true, [10] = true, [11] = true }, { 3, 1 }, { 11, 30 } },
  clear = { 365, nil, { 1, 1 }, { 12, 31 } },
  cloudy = { 365, nil, { 1, 1 }, { 12, 31 } },
}

test("every date in a window exists and each day comes up once", function()
  for weather, w in pairs(WINDOWS) do
    local total, months, first, last = w[1], w[2], w[3], w[4]
    local seen, count = {}, 0
    for n = 1, total do
      local month, day = sky.date(weather, function() return n end)
      assertEq(months == nil or months[month] == true, true)
      assertEq(day >= 1 and day <= DAYS[month], true)
      local key = month * 100 + day
      if not seen[key] then seen[key], count = true, count + 1 end
    end
    assertEq(count, total)
    local m1, d1 = sky.date(weather, function() return 1 end)
    assertEq(m1, first[1]); assertEq(d1, first[2])
    local m2, d2 = sky.date(weather, function() return total end)
    assertEq(m2, last[1]); assertEq(d2, last[2])
  end
  local m, d = sky.date("clear", function() return 60 end)
  assertEq(m, 3); assertEq(d, 1)
end)

test("the year defaults to the server's current year", function()
  assertEq(sky.pick(cfg(nil), rng(0.5, 1), false).year, tonumber(os.date("%Y")))
end)

test("hasRandom sees a random time or weather", function()
  assertEq(sky.hasRandom(cfg({ timeOfDay = "noon", weather = "clear" })), false)
  assertEq(sky.hasRandom(cfg(nil)), true)
  assertEq(sky.hasRandom(cfg({ timeOfDay = "noon" })), true)
  assertEq(sky.hasRandom(cfg({ weather = "clear" })), true)
end)

test("payload carries the date and the day length in seconds", function()
  local s = { time = "noon", weather = "snow", year = 2026, month = 12, day = 14, windDir = 1, windSeed = 2 }
  local p = sky.payload(s, cfg(nil), nil)
  assertEq(p.year, 2026); assertEq(p.month, 12); assertEq(p.day, 14); assertEq(p.daySeconds, 1800)
  assertEq(sky.payload(s, cfg({ dayLength = "fast" }), nil).daySeconds, 900)
  assertEq(sky.payload(s, cfg({ dayLength = "slow" }), nil).daySeconds, 7200)
  assertEq(sky.payload(s, cfg({ dayLength = "realtime" }), nil).daySeconds, 86400)
  assertEq(sky.payload(s, cfg({ dayLength = "off" }), nil).daySeconds, nil)
end)
```

In "payload sends driving only with a weather and the switch on", replace the last line with `assertEq(sky.payload(s, cfg({ dayLength = "off" }), nil).daySeconds, nil)`. In "nothing is sent on BeamNG.Earth, also with a clock speed", rename to "nothing is sent on BeamNG.Earth" and use `cfg({ dayLength = "fast", weather = "rain" })`. Replace "record keeps the conditions without the wind":

```lua
test("record keeps the conditions without the wind", function()
  local s = { time = "night", weather = "rain", year = 2026, month = 3, day = 9, windDir = 3, windSeed = 9 }
  local r = sky.record(s, cfg({ weather = "rain", dayLength = "fast" }))
  assertEq(r.time, "night"); assertEq(r.weather, "rain"); assertEq(r.dayLength, "fast"); assertEq(r.driving, true)
  assertEq(r.year, 2026); assertEq(r.month, 3); assertEq(r.day, 9)
  assertEq(r.windSeed, nil); assertEq(r.windDir, nil); assertEq(r.daySeconds, nil)
  assertEq(sky.record({}, cfg(nil)), nil)
end)
```

- [ ] **Step 3: Update the sky tests in `tests/test_main.lua:832-919`**

- "round setup has no sky by default" becomes:

```lua
test("round setup has a random sky with a date by default", function()
  local env = boot()
  env.startRound()
  local s = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(type(s.time), "string"); assertEq(type(s.weather), "string")
  assertEq(type(s.month), "number"); assertEq(type(s.day), "number"); assertEq(s.daySeconds, 1800)
  env.cleanup()
end)
```

- "New car keeps the sky": also capture `month` and `day` from the first setup and assert both are equal after New car.
- "New sky gives different conditions when it can": config `'{"weather":"random","timeOfDay":"noon"}'`.
- "New sky needs a random setting": `boot({ config = '{"timeOfDay":"noon","weather":"clear"}' })`.
- "Earth rounds get no sky": config `'{"dayLength":"fast","weather":"rain"}'`.
- "a mid-chase join gets clockSeconds": `boot()` instead of the `clockSpeed` config; before the join, store `month` and `day` from `env.lastSent("cnr_roundSetup")`; after the join, assert the joiner's setup has the same `month` and `day` and `daySeconds == 1800`, next to the existing `clockSeconds` check.

- [ ] **Step 4: Run the tests to see them fail**

Run: `make test 2>&1 | grep -E "FAIL|passed"`
Expected: FAIL lines in `test_config.lua`, `test_sky.lua` and `test_main.lua` (for example "expected random, got map", "attempt to call a nil value (field 'date')").

- [ ] **Step 5: Implement in `cnr/config.lua`**

DEFAULTS: `timeOfDay = "random"`, `weather = "random"`, replace `clockSpeed = 0` with `dayLength = "moderate"`. CHOICES: drop `map` from `timeOfDay` and `weather`; add `dayLength = { off = true, fast = true, moderate = true, slow = true, realtime = true }`. Remove `clockSpeed` from `MAXIMA` and `WHOLE` (`WHOLE = { trafficPerPlayer = true }`).

- [ ] **Step 6: Implement in `cnr/sky.lua`**

`DAY_SECONDS`, `date`, `pick`, `payload`, `record` as in Interfaces. Remove the `"map"` branches from `pickTime` and `pickWeather`. Don't change the `main.lua` call sites: `pick`'s default year covers them.

- [ ] **Step 7: Run the tests to see them pass**

Run: `make test 2>&1 | tail -1`
Expected: `N passed, 0 failed`

- [ ] **Step 8: Commit**

```bash
git add server/CopsAndRobbers/cnr/config.lua server/CopsAndRobbers/cnr/sky.lua tests/test_config.lua tests/test_sky.lua tests/test_main.lua
git commit -m "feat: day length choice, a date picked by the weather, random sky by default"
```

---

### Task 2: Client applies the date and the day length

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua:45-47` (setsSomething), `:101-117` (roundState), `:119-126` (label), `:155-168` (startClock)
- Modify: `tests/env_stubs.lua:29-31` (fake state), `:67` (getSolarTimeOfDayValue)
- Test: `tests/test_sky_client.lua`

**Interfaces:**
- Consumes: the payload fields from Task 1 (`year`, `month`, `day`, `daySeconds`, `time`, `weather`, ...).
- Produces: `sky.label(p) -> string|nil`, which the prep card and the leaderboard's Rounds tab already call (`copsAndRobbers.lua:182, 215, 502`). No signature changes.

- [ ] **Step 1: Update the stubs in `tests/env_stubs.lua`**

Add `latitude = 37.77, year = 2026, month = 6, day = 20` to `fake.state`. Change the solar stub to record the state it is given:

```lua
function env.getSolarTimeOfDayValue(key, state)
  fake.solarState = state
  return TIMES[key]
end
```

- [ ] **Step 2: Write the failing tests in `tests/test_sky_client.lua`**

In "labels join the time and the weather", replace `sky.label({ clockSpeed = 30 })` with `sky.label({ daySeconds = 1800 })` (still nil). Replace "the clock starts at GO at the configured speed":

```lua
test("the clock starts at GO with the round's day length", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", daySeconds = 1440, windDir = 0, windSeed = 1 })
  sky.startClock(600)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
  assertNear(s.time, (0.245 + 600 / 1440) % 1, 1e-9)
end)
```

Add:

```lua
local WINTER = { time = "sunrise", weather = "snow", year = 2026, month = 12, day = 14, windDir = 0, windSeed = 1 }

test("labels end with the date", function()
  local sky = load()
  assertEq(sky.label(WINTER), "Sunrise · Snow · 14 Dec")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 3 }), "Noon · Clear · 3 Jan")
end)

test("old runs without a date still get a label", function()
  local sky = load()
  assertEq(sky.label({ time = "night", weather = "rain", clockSpeed = 60 }), "Night · Rain")
end)

test("the round's date is set with the time", function()
  local sky, fake = load()
  sky.apply(WINTER)
  local s = fake.setStates[1]
  assertEq(s.year, 2026); assertEq(s.month, 12); assertEq(s.day, 14); assertEq(s.time, 0.775)
end)

test("the named time is worked out against the round's date", function()
  local sky, fake = load()
  sky.apply(WINTER)
  assertEq(fake.solarState.month, 12); assertEq(fake.solarState.day, 14); assertEq(fake.solarState.year, 2026)
  assertEq(fake.solarState.latitude, 37.77)
end)

test("restore gives the player's own date back", function()
  local sky, fake = load()
  sky.apply(WINTER)
  assertEq(fake.state.month, 12)
  sky.restore()
  assertEq(fake.state.year, 2026); assertEq(fake.state.month, 6); assertEq(fake.state.day, 20)
end)
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `make test 2>&1 | grep -E "FAIL|passed"`
Expected: FAIL in `test_sky_client.lua` (date label missing, `setStates[1].month` nil, clock time mismatch).

- [ ] **Step 4: Implement in `copsAndRobbers/sky.lua`**

- `setsSomething(p)`: `(p.daySeconds or 0) > 0` replaces the `clockSpeed` check.
- `roundState(env, p)`: when `p.month` and `p.day` are set, put `year`, `month`, `day` from `p` into `state`. For a named time, pass a copy of `env.getState()` with the round's date put in as the second argument of `env.getSolarTimeOfDayValue(p.time, solar)` (fall back to `env.timeOfDayKeyToTime[p.time]` as today). Don't modify the table `getTimeOfDay` returns; the game reuses it.
- `M.startClock`: read `round.daySeconds`; when it is above 0, `setState({ time = (clockStart + roundTime / daySeconds) % 1, play = true, dayLength = daySeconds })`. Remove `SECONDS_PER_DAY`.
- `M.label(p)`: after time and weather, add `string.format("%d %s", p.day, MONTHS[p.month])` when both are set; `MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `make test 2>&1 | tail -1`
Expected: `N passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/sky.lua tests/env_stubs.lua tests/test_sky_client.lua
git commit -m "feat: rounds set the date and run the clock by day length"
```

---

### Task 3: Panel, docs and version 2.4.0

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/settings.js:16-25` (Sky group), `:38` (the `item.speed` branch in the value formatter)
- Modify: `README.md:106-109`, `docs/FEATURES.md:1, 115, 145-151, 257-260`
- Modify: version `2.3.0` → `2.4.0` in `client/lua/ge/extensions/copsAndRobbers.lua:18`, `client/mod_info/CopsAndRobbers/info.json:5`, `server/CopsAndRobbers/main.lua:18`, `docs/FEATURES.md:1`, and the fixtures in `tests/test_client.lua:521, 569, 586, 587, 591, 1019`

**Interfaces:**
- Consumes: config key `dayLength` and its five choices (Task 1).

- [ ] **Step 1: Panel Sky group in `settings.js`**

Drop `["map", "Map default"]` from the Time of day and Weather options. Replace the `clockSpeed` item, in the same place, with:

```js
    { key: "dayLength", label: "Day length", kind: "choice",
      options: [["off", "Off"], ["fast", "Fast (15 min)"], ["moderate", "Moderate (30 min)"], ["slow", "Slow (2 h)"], ["realtime", "Realtime (24 h)"]],
      help: "How long a full day lasts once the chase starts" },
```

Remove the `if (item.speed) ...` line from the formatter; nothing else uses it.

- [ ] **Step 2: Check the panel builds**

Run: `make vuecheck`
Expected: exits 0 with no errors for `CopsAndRobbersPanel`.

- [ ] **Step 3: Docs**

- README and FEATURES settings tables: `timeOfDay` default `random`, choices without `map`; the `clockSpeed` row becomes `| \`dayLength\` | moderate | How long a full day lasts during the chase: \`off\` (stopped), \`fast\` (15 min), \`moderate\` (30 min), \`slow\` (2 h) or \`realtime\` (24 h) |`; `weather` default `random`, choices without `map`.
- FEATURES "Night and weather" (`:145-151`): Settings bullet lists Day length instead of Clock speed and says Time of day and Weather are a fixed choice or random (random by default; the sky is always set off Earth). Clock bullet: stopped with Off, otherwise stopped in prep and running from GO at the chosen day length. New bullet **Date:** "Each round gets a date that fits its weather: snow in December or January, fog in October or November, rain and storms in March, April, October or November, clear and cloudy any day. It sets sunrise, sunset and how long the night lasts, it is the same for everyone, and it shows on the prep card and in the Rounds tab ("Sunset · Snow · 14 Dec")."
- FEATURES `:115` "Saved per run": "clock speed" becomes "day length, date".

- [ ] **Step 4: Version 2.4.0**

Change the four version strings and the six `tests/test_client.lua` fixtures listed under Files (the "Your copy is 2.3.0" message becomes "Your copy is 2.4.0").

- [ ] **Step 5: Run everything**

Run: `make test 2>&1 | tail -1 && grep -rn "clockSpeed\|Map default\|2\.3\.0" client server README.md docs/FEATURES.md tests`
Expected: `N passed, 0 failed`. The grep shows only the old-record label test in `tests/test_sky_client.lua` and the old-config test in `tests/test_config.lua`.

- [ ] **Step 6: Commit**

```bash
git add client/ui/modules/apps/CopsAndRobbersPanel/settings.js README.md docs/FEATURES.md client/lua/ge/extensions/copsAndRobbers.lua client/mod_info/CopsAndRobbers/info.json server/CopsAndRobbers/main.lua tests/test_client.lua
git commit -m "feat: 2.4.0 - day length list and a date that follows the weather"
```

---

### Task 4: Check in game on the local server

Manual, with the host. See the in-game testing notes in memory: console commands one per line; the console is locked during a round.

- [ ] **Step 1: Install on the local server**

Run: `make install-local`
Expected: `.testserver/Resources/Client/CopsAndRobbers.zip` and `.testserver/Resources/Server/CopsAndRobbers` updated; the server log shows 2.4.0 loading with no Lua errors.

- [ ] **Step 2: The host checks, on west_coast_usa**
- The panel shows Day length with the five options, Moderate selected; Time of day and Weather show Random and have no "Map default".
- A practice round with Weather Snow and Time of day Sunrise: the prep card reads "Sunrise · Snow · <day> Dec" or "Jan", and the sun is at the horizon when the round starts.
- With Day length Fast, the sky visibly moves within a minute after GO.
- After the round, the environment menu shows the date the player had before.
