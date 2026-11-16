# Player Settings Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One HUD card for a player's own options (car colour, auto headlights, cop siren), a host switch that forbids sirens, and distances and speeds that follow the game's metric or imperial setting.

**Architecture:**
- Three new pure client modules carry the logic, and `copsAndRobbers.lua` wires them in:
  - `units.lua`: formatting.
  - `playerSettings.lua`: the switches saved in the player's game.
  - `ownLights.lua`: when to send headlight and light-bar commands.
- The HUD payload gains a `settings` block, the chase line's distance as its own part, and the player's unit.
- The server only gains the `sirensAllowed` config key, which travels in `cnr_rules`.
- In the UI, one `HudSettings.vue` replaces `HudColor.vue`.

**Tech Stack:** Lua (BeamNG GE extension, BeamMP server plugin), Vue 3 apps on the game's UI kit (`@/common/components/base`). Tests: `make test` (plain Lua runner `tests/run.lua`). UI compile check: `make vuecheck`.

**Spec:** `docs/superpowers/specs/2026-11-16-player-settings-design.md`

## Global Constraints

- Work in a worktree branch (superpowers:using-git-worktrees).
- `TODO.md` is edited only on main. When execution starts, update the In progress entry on main with the branch name. At merge, on main:
  - Delete the entry and its four folded-in sub-items.
  - The Issues line "HUD styles repeated across components" stays as it is.
- No version bump in this branch (`make version` runs on main after the merge).
- Settings file: `settings/cnr_settings.json`, contents `{ headlights = <bool>, siren = <bool> }`. Both default to `false`.
- Host config key: `sirensAllowed`, boolean, default `true`.
- Vehicle commands, exactly:
  - `HEADLIGHTS_ON = "if (electrics.values.lights_state or 0) == 0 then electrics.setLightsState(1) end"`
  - `HEADLIGHTS_OFF = "electrics.setLightsState(0)"`
  - light bar: `"electrics.set_lightbar_signal(1)"` (lights only) / `"electrics.set_lightbar_signal(2)"` (siren) / `"electrics.set_lightbar_signal(0)"` (off)
- Bad weather is `rain`, `storm`, `fog` and `snow`.
- Game unit: `settings.getValue("uiUnitLength")`. Only `"imperial"` means imperial. Anything else, nil or an error means metric.
- Imperial chase distance:
  - feet rounded to 10: `math.floor(m * 3.28084 / 10 + 0.5) * 10`
  - from 1000 ft it shows miles instead: `string.format("%.1f mi", m / 1609.344)`
  - metric output is unchanged
- Imperial rule values (How to play):
  - whole feet below 1000 ft, otherwise miles to one decimal
  - speeds `round1(kmh * 0.621371) + " mph"`
- The Host panel stays metric everywhere.
- Copy (exact):
  - button **Settings**
  - card title **Your settings**
  - section label **Car colour**
  - rows **Auto headlights** / "On at night and in bad weather" and **Siren** / "As a cop, once cops are released"
  - disabled siren sub-text "Turned off by the host"
  - panel row label "Cop sirens", help "Cops may turn a siren on in their settings; off keeps every cop silent"
  - lock message "Parts and paint are locked during a round. Use Settings for your car colour"
- Project style: no code comments, no emojis.

## Review Focus

1. **A runner switches the lights off with the game's key at night to hide.** The mod must not switch them back on until the next change (sunset or sunrise, a weather change, or a new car). Test in Task 4: `own headlights are not re-sent while nothing changes`.
2. **A repaint in prep (`cnr_paint`) or an evolving rebuild at night** gives a fresh car with its lights off. The lights must come back on after the new placement. Test in Task 4: `a repaint at night lights the new car again`.
3. **A broken or foreign `cnr_settings.json`** (a string, numbers, `"yes"`) must load as both switches off, and must never throw while the extension loads. Test in Task 2: `a broken settings file means both switches off`.
4. **The host forbids sirens while a cop's switch is on, then allows them again.** The cop gets lights only, then the siren again. The player's file is never written by the host's switch. Test in Task 4: `the host's switch silences a cop and never touches the saved switch`.
5. **The game's unit setting is missing** (no `settings` global during early load) **or has an unexpected value.** Units must fall back to metric without an error. Test in Task 1: `an unknown or missing game unit means metric`.

---

### Task 1: Units and the chase line's distance on its own

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/units.lua`
- Create: `tests/test_units.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/geo.lua` (`formatDistance`, `gpsInfo`)
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`infoText` → `infoParts` in `onLastSeen`, `onNearestCop`, `runnerInfo`, `updateGpsInfo`, `onUpdate`, `endRound`, `startStatus`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hudfeed.lua` (`push`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`statusBlock`, `helpBlock`)
- Modify: `client/ui/modules/apps/CopsAndRobbersHud/HudChase.vue`
- Modify: `tests/client_stubs.lua` (a `settings` stub), `tests/test_hud.lua:58-60,214-215`, `tests/test_client.lua:380-416`

**Interfaces:**
- Produces:
  - `units.unit(value) -> "metric"|"imperial"`
  - `units.read() -> "metric"|"imperial"`
  - `units.distance(meters, unit) -> string`
  - `geo.formatDistance(m, unit) -> string` (unit optional, metric when nil)
  - info parts: `{ before = string, meters = number|nil, after = string|nil }`
  - hud info key `infoParts`
  - hud info key `units`
  - payload `status.info = { before, dist, after }`
  - payload `help.units`
  - stub `env.gameSettings` (table read by `settings.getValue`)

- [ ] **Step 1: Write the failing tests**

`tests/test_units.lua` (load the module with `package.path` as `tests/run.lua` sets it: `local units = require("copsAndRobbers/units")`):
```lua
test("metric distance is unchanged", function()
  assertEq(units.distance(640, "metric"), "640 m")
  assertEq(units.distance(999.4, "metric"), "999 m")
  assertEq(units.distance(999.5, "metric"), "1.0 km")
  assertEq(units.distance(1500, nil), "1.5 km")
end)
test("imperial distance in 10 ft steps, then miles", function()
  assertEq(units.distance(0, "imperial"), "0 ft")
  assertEq(units.distance(100, "imperial"), "330 ft")
  assertEq(units.distance(303, "imperial"), "990 ft")
  assertEq(units.distance(304, "imperial"), "0.2 mi")
  assertEq(units.distance(1609.344, "imperial"), "1.0 mi")
  assertEq(units.distance(2414, "imperial"), "1.5 mi")
end)
test("an unknown or missing game unit means metric", function()
  assertEq(units.unit("imperial"), "imperial")
  assertEq(units.unit("metric"), "metric")
  assertEq(units.unit("Imperial "), "metric")
  assertEq(units.unit(nil), "metric")
  _G.settings = nil
  assertEq(units.read(), "metric")
  _G.settings = { getValue = function() error("boom") end }
  assertEq(units.read(), "metric")
  _G.settings = { getValue = function(k) return k == "uiUnitLength" and "imperial" or nil end }
  assertEq(units.read(), "imperial")
  _G.settings = nil
end)
```
`tests/test_hud.lua:58-60` becomes:
```lua
local p = hud.payload(s, 200, { active = true, role = "cop", chaseStart = 7.3, resetAllowed = true, infoParts = { before = "Runner", meters = 640, after = "NE" } })
assertEq(p.status.info.before, "Runner"); assertEq(p.status.info.dist, "640 m"); assertEq(p.status.info.after, "NE")
local imp = hud.payload(s, 200, { active = true, role = "cop", chaseStart = 7.3, units = "imperial", infoParts = { before = "Runner", meters = 640, after = "NE" } })
assertEq(imp.status.info.dist, "0.4 mi")
```
Also in `tests/test_hud.lua`: the runner case at 214 asserts `.before == "Nearest cop"`, `.dist == "120 m"`, `.after == nil`. A new test asserts `hud.payload(hud.new(), 0, { helpOpen = true, units = "imperial", rules = {} }).help.units == "imperial"`, and that `help.units` is `"metric"` when `units` is nil.

`tests/client_stubs.lua`:
- add `env.gameSettings = opts.gameSettings or {}`
- add `_G.settings = { getValue = function(k) return env.gameSettings[k] end }`

`tests/test_client.lua:380-416`: replace the string asserts with part asserts:
- `info.before == "Runner"`, `info.dist == "640 m"`, `info.after == "N"`
- `"Runner seen"` / `"640 m"` / `"N"`
- `"Runner seen"` / `"1.5 km"`
- `"Nearest cop"` / `"1.2 km"`
- IN SIGHT keeps `status.info == nil`

Add `test("the chase distance follows the game's unit", ...)`:
- set `env.gameSettings.uiUnitLength = "imperial"`
- a `cnr_lastSeen` at 640 m
- assert `status.info.dist == "0.4 mi"`
- set the unit back to `"metric"`, `env.tick(0.2)`, and assert `"640 m"` (the unit is read at push time, so no new ping is needed)

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `make test`
Expected: FAIL in `tests/test_units.lua` (module not found), `test_hud.lua` and `test_client.lua` (info is a string).

- [ ] **Step 3: Implement**

- `units.lua`: the three functions above.
  - `read` wraps `settings.getValue("uiUnitLength")` in `pcall` and guards against a missing `settings` global.
  - `distance` holds today's metric code from `geo.formatDistance` plus the imperial branch from Global Constraints.
- `geo.formatDistance(m, unit)` returns `units.distance(m, unit)`.
- `geo.gpsInfo()` returns parts instead of a string:
  - by road: `{ before = "Runner", meters = g.remaining, after = "by road" .. dir }`
  - straight: `{ before = "Runner", meters = here:distance(target), after = dir ~= "" and dir:sub(2) or nil }`
  - `dir` keeps its leading space as today
- `copsAndRobbers.lua`: rename the local `infoText` to `infoParts`. Build parts:
  - `{ before = d.live and "Runner" or "Runner seen", meters = meters, after = geo.compass(here, target) }`
  - `nearestText` becomes `nearestParts = { before = "Nearest cop", meters = d.dist }`
  - pass `infoParts = infoParts` to `hudfeed.update`
- `hudfeed.push` passes `units = units.read()` and `infoParts = info.infoParts` into `hud.payload`.
- `hud.lua`:
  - `statusBlock` sets `status.info = { before = p.before, dist = p.meters and units.distance(p.meters, info.units) or nil, after = p.after }` when `info.infoParts` is a table, otherwise nil
  - `helpBlock(open, rules, unit)` sets `help.units = units.unit(unit)`
- `HudChase.vue`: replace `{{ status.info }}` with three spans in `.info-text`: `before` (display font), `dist` in `class="mono"` when present, and `after`, with a single space between parts that exist.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `N passed, 0 failed`.
Run: `make vuecheck`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/units.lua client/lua/ge/extensions/copsAndRobbers/geo.lua client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/hudfeed.lua client/lua/ge/extensions/copsAndRobbers/hud.lua client/ui/modules/apps/CopsAndRobbersHud/HudChase.vue tests/test_units.lua tests/client_stubs.lua tests/test_hud.lua tests/test_client.lua
git commit -m "feat: chase distances follow the game's unit and show in the mono font"
```

### Task 2: Player switches saved in the player's game

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/playerSettings.lua`
- Create: `tests/test_player_settings.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`onExtensionLoaded`, `M.ui`, `cnr_rules` handler)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hudfeed.lua` (`M.settings`, `leave`, `push`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`M.payload`)
- Test: `tests/test_client.lua`, `tests/test_hud.lua`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `playerSettings.FILE = "settings/cnr_settings.json"`
  - `playerSettings.load(decoded) -> { headlights = bool, siren = bool }`
  - `playerSettings.set(prefs, key, value) -> bool` (true when changed)
  - `hudfeed.settings(prefs)`
  - a module-level `prefs` table and a `sirensAllowed` boolean in `copsAndRobbers.lua`
  - `hud.payload(...).settings = { color = string|nil, headlights = bool, siren = bool, sirensAllowed = bool }` in lobby and round modes (absent in result mode)
  - the ui message `{ action = "setting", key = "headlights"|"siren", value = bool }`

- [ ] **Step 1: Write the failing tests**

`tests/test_player_settings.lua`:
```lua
local ps = require("copsAndRobbers/playerSettings")
test("a broken settings file means both switches off", function()
  for _, bad in ipairs({ nil, "x", 3, { headlights = "yes", siren = 1 }, { 1, 2 } }) do
    local p = ps.load(bad)
    assertEq(p.headlights, false); assertEq(p.siren, false)
  end
  local p = ps.load({ headlights = true, siren = false, extra = true })
  assertEq(p.headlights, true); assertEq(p.siren, false); assertEq(p.extra, nil)
end)
test("set takes only known keys and booleans", function()
  local p = ps.load(nil)
  assertEq(ps.set(p, "headlights", true), true); assertEq(p.headlights, true)
  assertEq(ps.set(p, "headlights", true), false)
  assertEq(ps.set(p, "siren", "on"), false); assertEq(p.siren, false)
  assertEq(ps.set(p, "color", true), false); assertEq(p.color, nil)
end)
```
In `tests/test_client.lua`:
- `test("a setting from the card is saved and shown")`:
  - `bootClient()`, `env.M.ui({ action = "setting", key = "siren", value = true })`, `env.tick(0.2)`
  - assert `env.written["settings/cnr_settings.json"].siren == true` and `.headlights == false`
  - assert `env.hud().settings.siren == true` and `env.hud().settings.sirensAllowed == true`
  - then `env.M.ui({ action = "setting", key = "nope", value = true })` writes nothing new: compare the count of `env.written` keys, or reset `env.written = {}` first
- `test("saved settings load on start")`:
  - `bootClient({ files = { ["settings/cnr_settings.json"] = { headlights = true } } })`, `env.tick(0.2)` after `env.fire("cnr_mode", {})`
  - assert `env.hud().settings.headlights == true`
- `test("the host's siren rule reaches the card")`: `env.fire("cnr_rules", { sirensAllowed = false })` → `env.hud().settings.sirensAllowed == false`.

In `tests/test_hud.lua`:
- lobby payload carries `settings.color` and the switch values
- a result payload has no `settings`
- `sirensAllowed` is true when `rules` is nil

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `make test`
Expected: FAIL (module `copsAndRobbers/playerSettings` not found, `settings` nil in the payload).

- [ ] **Step 3: Implement**

- `playerSettings.lua`: `load` copies only boolean `headlights` and `siren` from a table, false otherwise. `set` returns false for unknown keys and non-booleans.
- `copsAndRobbers.lua`:
  - load `prefs = playerSettings.load(<pcall jsonReadFile result>)` in `onExtensionLoaded` and call `hudfeed.settings(prefs)`.
  - `M.ui` action `"setting"`: if `playerSettings.set(prefs, msg.key, msg.value)` then `pcall(jsonWriteFile, playerSettings.FILE, prefs, true)` and `hudfeed.settings(prefs)`. Then `hudfeed.pushNow()` as the other actions do.
  - the `cnr_rules` handler also sets `sirensAllowed = not (type(r) == "table" and r.sirensAllowed == false)`.
- `hudfeed`:
  - stores `prefs`
  - `leave` keeps them (they belong to the player, not the server)
  - `push` passes `settings = prefs`
- `hud.payload` adds `payload.settings` in lobby and round modes, with `sirensAllowed = not (type(info.rules) == "table" and info.rules.sirensAllowed == false)`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/playerSettings.lua client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/hudfeed.lua client/lua/ge/extensions/copsAndRobbers/hud.lua tests/test_player_settings.lua tests/test_client.lua tests/test_hud.lua
git commit -m "feat: player switches for headlights and siren, saved in the player's game"
```

### Task 3: Host switch Cop sirens

**Files:**
- Modify: `server/CopsAndRobbers/cnr/config.lua` (`DEFAULTS`)
- Modify: `server/CopsAndRobbers/cnr/rules.lua` (`KEYS`)
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/settings.js` (Cops group)
- Modify: `README.md` (config table, after `explodeOnCatch`)
- Test: `tests/test_config.lua`, `tests/test_rules.lua:4-15`

**Interfaces:**
- Produces: `cfg.sirensAllowed` (boolean). `cnr_rules` payload key `sirensAllowed`, which Task 2's client handler reads.

- [ ] **Step 1: Write the failing tests**

`tests/test_rules.lua`: the payload test name and count become 15 keys, and it asserts `p.sirensAllowed == true` for the default config.

`tests/test_config.lua`:
- `test("sirensAllowed defaults to true and takes only booleans")`
  - `config.merge({}).sirensAllowed == true`
  - `config.merge({ sirensAllowed = false }).sirensAllowed == false`
  - `config.merge({ sirensAllowed = "no" })` gives `true` and a warning `"sirensAllowed must be true or false, using true"`

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `make test`
Expected: FAIL in `test_rules.lua` (14 keys) and `test_config.lua`.

- [ ] **Step 3: Implement**

- `DEFAULTS.sirensAllowed = true`. The boolean handling in `merge` and `parseValue` already covers it.
- Append `"sirensAllowed"` to `rules.KEYS`.
- `settings.js`, Cops group, after `assistMinSightPercent`: `{ key: "sirensAllowed", label: "Cop sirens", kind: "bool", help: "Cops may turn a siren on in their settings; off keeps every cop silent" }`.
- README config table row: `` | `sirensAllowed` | true | Cops may use a siren (each cop turns it on in their settings) | ``.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test && make vuecheck`
Expected: `0 failed`, vuecheck clean.

- [ ] **Step 5: Commit**

```bash
git add server/CopsAndRobbers/cnr/config.lua server/CopsAndRobbers/cnr/rules.lua client/ui/modules/apps/CopsAndRobbersPanel/settings.js README.md tests/test_config.lua tests/test_rules.lua
git commit -m "feat: host switch Cop sirens, sent to every player with the rules"
```

### Task 4: Own headlights and siren

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/ownLights.lua`
- Create: `tests/test_own_lights.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua` (add `M.BAD_WEATHER`, `M.isBadWeather(key)`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/traffic.lua:16,221` (use `sky.isBadWeather`)
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`:
  - `onRoundSetup`, `onSky`, `updatePendingPlacement`, `updateLightsAndPatch`, `endRound`
  - a new `updateOwnLights`, called from `onUpdate` right after `updateLightsAndPatch()` (so it runs after `updatePendingPlacement` in the same frame)
- Test: `tests/test_client.lua`

**Interfaces:**
- Consumes: `prefs.headlights`, `prefs.siren` and `sirensAllowed` from Task 2.
- Produces:
  - `ownLights.HEADLIGHTS_ON`, `ownLights.HEADLIGHTS_OFF` (Global Constraints)
  - `ownLights.new(enabled) -> state`
  - `ownLights.step(state, enabled, dark, placed) -> "on"|"off"|nil`
  - `ownLights.lightbarSignal(role, released, sirenOn, allowed) -> 1|2|nil`
  - `sky.isBadWeather(key) -> bool`

- [ ] **Step 1: Write the failing tests**

`tests/test_own_lights.lua`:
```lua
local L = require("copsAndRobbers/ownLights")
test("placing a car in the dark switches the lights on once", function()
  local s = L.new(true)
  assertEq(L.step(s, true, true, true), "on")
  assertEq(L.step(s, true, true, false), nil)
  assertEq(L.step(s, true, true, false), nil)
end)
test("sunset turns on, sunrise turns off, once each", function()
  local s = L.new(true)
  assertEq(L.step(s, true, false, true), nil)
  assertEq(L.step(s, true, true, false), "on")
  assertEq(L.step(s, true, false, false), "off")
  assertEq(L.step(s, true, false, false), nil)
end)
test("switching on in prep applies now, switching off leaves the lights", function()
  local s = L.new(false)
  assertEq(L.step(s, false, true, true), nil)
  assertEq(L.step(s, true, true, false), "on")
  assertEq(L.step(s, false, true, false), nil)
  assertEq(L.step(s, false, false, false), nil)
end)
test("the switch off never sends anything", function()
  local s = L.new(false)
  for _, dark in ipairs({ true, false, true }) do assertEq(L.step(s, false, dark, true), nil) end
end)
test("light bar signal by role, release, switch and host rule", function()
  assertEq(L.lightbarSignal("runner", true, true, true), nil)
  assertEq(L.lightbarSignal("cop", false, true, true), 1)
  assertEq(L.lightbarSignal("cop", true, true, true), 2)
  assertEq(L.lightbarSignal("cop", true, false, true), 1)
  assertEq(L.lightbarSignal("cop", true, true, false), 1)
end)
```
`tests/test_client.lua`. Use a helper `count(veh, cmd)` that counts exact command strings in `veh.commands`. For a night round, set `d.sky = { time = "night", windDir = 0, windSeed = 1 }`.
- `own headlights come on when the car is placed at night`:
  - files `{ headlights = true }`, a cop night round, `env.tick(1)`
  - `count(env.veh, L.HEADLIGHTS_ON) == 1`
- `own headlights are not re-sent while nothing changes`: as above, then `env.tick(10)` keeps the count at 1 and `count(env.veh, L.HEADLIGHTS_OFF) == 0`.
- `a day round in rain lights the car, a clear day does not`:
  - `d.sky = { time = "noon", weather = "rain", ... }` → 1
  - `{ time = "noon", weather = "clear" }` → 0
- `sunrise turns own headlights off once`: after placement at night, `env.sky.state.time = 0`, `env.tick(3)` → `count(env.veh, L.HEADLIGHTS_OFF) == 1`.
- `New sky to rain by day turns own headlights on`: day round placed, `env.fire("cnr_sky", { time = "noon", weather = "rain", windDir = 0, windSeed = 1 })`, `env.tick(2)` → on count 1.
- `a repaint at night lights the new car again`: night round placed (count 1), `env.fire("cnr_paint", { color = { r = 1, g = 0, b = 0 } })`, `env.tick(1)` → count 2.
- `the headlights switch off never touches the lights`: no settings file, night round, `env.tick(5)` → both counts 0.
- `switching headlights off in prep and round end send nothing`:
  - placed at night with the switch on (count 1)
  - `env.M.ui({ action = "setting", key = "headlights", value = false })`, `env.tick(2)`, then fire `cnr_roundEnd` and `env.tick(1)`
  - `HEADLIGHTS_OFF` count stays 0
- `a cop's siren runs only after release`:
  - files `{ siren = true }`, cop round, `env.tick(3)`
  - `count(env.veh, "electrics.set_lightbar_signal(2)") == 0`
  - `env.fire("cnr_release", {})`, `env.tick(3)` → `> 0`
  - `cnr_roundEnd` → the last lightbar command is `"electrics.set_lightbar_signal(0)"`
- `the host's switch silences a cop and never touches the saved switch`:
  - files `{ siren = true }`, `env.fire("cnr_rules", { sirensAllowed = false })`, cop round, release, `env.tick(3)`
  - signal 2 count 0, signal 1 count > 0
  - `env.written["settings/cnr_settings.json"] == nil`
  - then `env.fire("cnr_rules", { sirensAllowed = true })`, `env.tick(3)` → signal 2 count > 0
- `a runner never gets light bar commands`: runner round with `{ siren = true }`, release, `env.tick(3)` → no `set_lightbar_signal` on `env.veh`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `make test`
Expected: FAIL (module `copsAndRobbers/ownLights` not found, no headlight commands).

- [ ] **Step 3: Implement**

`ownLights.step` body (the order matters):
```lua
function M.step(state, enabled, dark, placed)
  local wasEnabled, wasDark = state.enabled, state.dark
  state.enabled, state.dark = enabled, dark
  if not enabled then return nil end
  if placed or not wasEnabled or wasDark == nil then return dark and "on" or nil end
  if wasDark == dark then return nil end
  return dark and "on" or "off"
end
```
- `ownLights.new(enabled)` returns `{ enabled = enabled == true, dark = nil }`.
- `lightbarSignal` returns nil unless `role == "cop"`. It returns 2 only when `released and sirenOn and allowed`, and 1 otherwise.
- `sky.lua`: `M.BAD_WEATHER = { rain = true, storm = true, fog = true, snow = true }` and `M.isBadWeather(key)`. In `traffic.lua`, drop the local table and call `sky.isBadWeather(weather)`.
- `copsAndRobbers.lua`:
  - New locals: `roundWeather`, `lightsState`, `lightsPlaced`, `lastLightsCheck`.
  - In `onRoundSetup`, set `roundWeather = d.sky and d.sky.weather`, `lightsState = ownLights.new(prefs.headlights)` and `lightsPlaced = false`.
  - In `onSky`, set `roundWeather = d.weather`.
  - In `updatePendingPlacement`, set `lightsPlaced = true` right after `sendServer("cnr_myVehicle", ...)`.
  - `updateOwnLights()` returns early unless `active and lightsState and not pendingPlacement`, and unless `lightsPlaced` or `clock - lastLightsCheck >= 1`. Otherwise it:
    - sets `lastLightsCheck = clock`
    - computes `cmd = ownLights.step(lightsState, prefs.headlights, sky.isNight() or sky.isBadWeather(roundWeather), lightsPlaced)`
    - sets `lightsPlaced = false`
    - queues `ownLights.HEADLIGHTS_ON` or `HEADLIGHTS_OFF` on `ownVehicle()` when `cmd` is set
  - `updateLightsAndPatch`: replace the `role == "cop"` line with `local n = ownLights.lightbarSignal(role, statusActive, prefs.siren, sirensAllowed)`, and `if n then veh:queueLuaCommand("electrics.set_lightbar_signal(" .. n .. ")") end`.
  - `endRound` sets `lightsState, roundWeather = nil, nil` and sends no headlight command.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`. The existing traffic headlight tests and `cops turn their emergency lights on and off` still pass.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/ownLights.lua client/lua/ge/extensions/copsAndRobbers/sky.lua client/lua/ge/extensions/copsAndRobbers/traffic.lua client/lua/ge/extensions/copsAndRobbers.lua tests/test_own_lights.lua tests/test_client.lua
git commit -m "feat: auto headlights and a cop siren from the player's switches"
```

### Task 5: The settings card in the HUD

**Files:**
- Create: `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue` (from `HudColor.vue`)
- Delete: `client/ui/modules/apps/CopsAndRobbersHud/HudColor.vue`
- Modify: `client/ui/modules/apps/CopsAndRobbersHud/app.vue`, `HudLobby.vue`, `HudPrep.vue`
- Modify: `client/ui/modules/copsAndRobbers/CnrRoot.vue` (shared `.cnr-btn`, `.cnr-swatch`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/inputs.lua:32` (`LOCK_MESSAGE`)
- Test: `tests/test_client.lua` (the lock message, if a test asserts its text; `grep -n "Colour button" tests/`)

**Interfaces:**
- Consumes:
  - `hud.settings = { color, headlights, siren, sirensAllowed }` (Task 2)
  - `ui({ action: "setting", key, value })` (Task 2)
  - the existing `ui({ action: "color", hex })` and `ui({ action: "color" })`
- Produces:
  - `HudSettings` props `settings: Object` and `draft: String` (v-model:draft)
  - `HudSettings` emits `pick(hex)`, `clear`, `setting(key, value)`, `close`
  - `HudLobby` and `HudPrep` emit `settings` (renamed from `color`)

- [ ] **Step 1: Shared styles**

Move the repeated parts into the global `<style>` of `CnrRoot.vue`:
- `.cnr-root .cnr-btn` (display font, weight 700, `--bng-button-margin: 0`, `--bng-content-align: center`)
- `.cnr-root .cnr-swatch` and `.cnr-swatch.empty` (1rem square, `--bng-corners-1`, muted ring)

In HudLobby and HudPrep, replace `hud-btn` with `cnr-btn` and `swatch` with `cnr-swatch`, and delete their local copies. Keep the local differences (HudPrep's 0.875rem size, `pointer-events: auto`).

- [ ] **Step 2: `HudSettings.vue`**

- Title "Your settings", closable.
- Section label "Car colour", then today's picker and hex row.
  - The hex field is bound to `draft` (initialised by the parent).
  - **No colour** emits `clear` and stays open.
  - **Done** sits in the card's `#actions`. It is disabled while `draft` is non-empty and invalid. When pressed, it emits `pick(normalized)` if the draft is valid and differs from `settings.color`, then `close`.
- A divider, then two `BngSwitch` rows with the exact copy from Global Constraints:
  - each switch emits `setting(key, value)`
  - the Siren row gets `:disabled="!settings.sirensAllowed"`, shows off, and swaps its sub-text to "Turned off by the host" when sirens aren't allowed

- [ ] **Step 3: `app.vue`**

- Rename `colorOpen` to `settingsOpen`, and add `colorDraft = ref("")`.
- Render one `<HudSettings v-if="settingsOpen && settingsAllowed" ...>` **after** both mode templates, so it stays mounted from lobby to prep.
- Hide HudLobby and HudPrep while it is open.
- Opening sets `colorDraft` to the saved colour (uppercased `#RRGGBB`), or "" when there is none.
- ✕, Done and the not-allowed watch close the card and clear `colorDraft`.
- `pick` sends `ui({ action: "color", hex })`, `clear` sends `ui({ action: "color" })` and clears the draft, and `setting` sends `ui({ action: "setting", key, value })`.
- Rename the button text **Colour** to **Settings** in HudLobby and HudPrep, keeping the swatch.

- [ ] **Step 4: Lock message**

`inputs.lua` `LOCK_MESSAGE` = "Parts and paint are locked during a round. Use Settings for your car colour". Update any test that asserts the old text.

- [ ] **Step 5: Verify**

Run: `make test && make vuecheck`
Expected: `0 failed`, vuecheck clean, and `grep -rn "HudColor\|hud-btn" client/ui` prints nothing.

- [ ] **Step 6: Commit**

```bash
git add -A client/ui/modules client/lua/ge/extensions/copsAndRobbers/inputs.lua tests
git commit -m "feat: one settings card in the HUD for colour, headlights and siren"
```

### Task 6: How to play and the docs

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` (`dist`, `kmh`, colour line, a settings line)
- Modify: `client/ui/modules/apps/CopsAndRobbersHowToPlay/app.vue` (pass `:units="hud.help.units"`)
- Modify: `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`

**Interfaces:**
- Consumes:
  - `help.units` (Task 1)
  - `help.rules.sirensAllowed` (Task 3; already copied by `helpBlock`)

- [ ] **Step 1: How to play**

- New prop `units: String`.
- `dist(key)`:
  - imperial: `Math.round(n * 3.28084)` + " ft" below 1000 ft, otherwise `round1(n / 1609.344)` + " mi"
  - metric: unchanged
- `kmh(key)`: imperial gives `round1(n * 0.621371)` + " mph".
- The colour line becomes "**Your settings:** use the Settings button for your car colour, auto headlights at night and in bad weather<span v-if siren>, and a siren as a cop</span>. A colour set in prep repaints your car straight away; otherwise it applies from the next round."
  - Show the siren part only when `r.sirensAllowed !== false`.
- The prep step reads "The host starts a round. You're frozen; open Settings for your colour."

- [ ] **Step 2: Docs**

- README and FEATURES:
  - the lobby card, prep line and per-player colour lines say Settings
  - add a short **Player settings** entry (card, the two switches, units follow the game, Host panel stays metric)
  - the Emergency lights lines say "no siren unless the cop turns it on in Settings (and the host allows Cop sirens)"
  - the FEATURES HUD section notes that the chase line's distance is in the mono font
- DEPENDENCIES:
  - `electrics.values.lights_state`, `electrics.setLightsState`, `electrics.set_lightbar_signal(2)` (lights and siren), `settings.getValue("uiUnitLength")`, `core_environment.getLightState().isNight` for the player's own car
  - an update check matching the spec's In-game check items 2, 4 and 6

- [ ] **Step 3: Verify**

Run: `make test && make vuecheck`
Expected: `0 failed`, vuecheck clean.

- [ ] **Step 4: Commit**

```bash
git add client/ui/modules/apps/CopsAndRobbersHowToPlay README.md docs/FEATURES.md docs/DEPENDENCIES.md
git commit -m "docs: player settings, units and Cop sirens in How to play, README and features"
```

### Task 7: In-game check with the user

**Files:**
- Modify: `README.md` (the cursor line, after the check)

- [ ] **Step 1: Install on the local test server**

Run: `make install-local`
Expected: `dist/` built and copied to `.testserver`.

- [ ] **Step 2: Hand the user the spec's In-game check list (items 1–8)**

Ask them to report each item, using the in-game testing workflow (console test extension and `beamng.log`) where something has to be read from the engine.

- [ ] **Step 3: Fix what they report and write the cursor control into the README**

Put the control and its default binding they found (item 8) into README's "Everything is clickable with the mouse cursor shown" line. Re-run `make test`. Record anything left unfixed under Issues in the branch's `TODO.md` if it concerns this branch's code.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README names the control that shows the mouse cursor"
```
