# Sky Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sky changes blend over up to 3 s. Rain and snow fade, and rain falls at the stock maps' speed with a storm heavier. The game's rain sound plays in rain and storm. The outside temperature follows the weather and the round's date.

**Architecture:**
- Two new pure-ish client modules:
  - `climate.lua`: temperature range by weather and month.
  - `rain.lua`: our precipitation object, its fade, the roof check and the rain sound.
- `sky.lua` keeps the state blend (the game's `setState(state, seconds)`), the lock timing and the wiring. Everything stays client-side.
- The server is unchanged: it already sends `weather`, `time`, `month` and `day`.

**Tech Stack:** Lua (BeamNG GE extension). Tests: `make test` (`tests/run.lua`, stubs in `tests/env_stubs.lua` and `tests/client_stubs.lua`).

**Spec:** `docs/superpowers/specs/2026-11-16-sky-transitions-design.md`

## Global Constraints

- **Branch and ledger:**
  - Work in a worktree branch.
  - `TODO.md` is edited only on main: before entering the worktree, the controller updates the In progress entry on main with the branch name.
  - No version bump in the branch (`make version` on main after the merge).
- **Timing:**
  - Blend length `BLEND_SECONDS = 3`. Every blend is started as `env.setState(nil)` then `env.setState(state, 3)`, so a change that arrives mid-blend gets a full blend from where the sky is (the game's own shortcut would cut it to 0.3 s).
  - The lock goes back on `BLEND_SECONDS + 0.5` s after the last blend started.
  - The rain fade writes `numDrops` at most 10 times a second (`FADE_INTERVAL = 0.1`).
- **Climate, monthly normals** (°C), indexed by month 1–12:
  - low `{ 0, 1, 4, 8, 12, 17, 20, 19, 15, 10, 5, 1 }`
  - high `{ 8, 10, 14, 18, 23, 28, 31, 30, 26, 20, 13, 9 }`
- **Weather offsets:**

  | Weather | Low | High |
  |---|---|---|
  | clear | +0 | +0 |
  | cloudy | +2 | −3 |
  | rain | +2 | −5 |
  | storm | +1 | −7 |
  | fog | +0 | −6 |

  - **Snow:** `high = min(normalHigh − 9, 0)` and `low = min(normalLow, high − 4)`.
  - **Every weather except snow:** if `high < low + 2` then `high = low + 2`. A storm in November gives 6 to 8.
- **Temperature: our own day curve,** set in the round state as `temperatureCurveOverrideC` (applied at once by `setState`; no `setTemperatureProfile` call any more):
  - two points, sorted by time: `{ sunriseT, low }` and `{ (noonT + 2 / 24) % 1, high }`
  - `sunriseT = env.getSolarTimeOfDayValue("sunrise", solar)` and `noonT = env.getSolarTimeOfDayValue("noon", solar)`, with the same `solar` table `roundState` already builds for the round's date
  - `low, high = climate.range(p.weather, p.month)`: the month the server sent, never the hemisphere-shifted one
  - when that returns nil (no weather or no month), `temperatureCurveOverrideC = false` as today (the map's own curve)
- **Precipitation specs** (every one also has `boxWidth = 40`, `boxHeight = 20`, `useWind = 1`, `splashSize = 0.25`; no `hitVehicles`):
  - **rain:** `dataBlock = "rain_medium"`, `numDrops = 3000`, `dropSize = 1`, `minSpeed = 0.4`, `maxSpeed = 0.5`, `volume = 1.0`
  - **storm:** `dataBlock = "rain_medium"`, `numDrops = 7000`, `dropSize = 1.3`, `minSpeed = 0.6`, `maxSpeed = 0.8`, `volume = 2.0`
  - **snow:** `dataBlock = "Snow_menu"`, `numDrops = 5000`, `dropSize = 0.2`, `minSpeed = 0.1`, `maxSpeed = 0.3`, no `volume`
- **Rain sound:**
  - an `SFXEmitter` registered as `cnr_rain_sound`, with field `track = "amb_rain_medium"` and `canSave = false`
  - started with `play()`; volume set with `setVolumePitchCT(volume, 1, 0, 0)`, the way `core/audioForest.lua` does it
  - added to `scenetree.MissionGroup` like the rain object, so a map unload removes it
  - volume = `spec.volume × drops / spec.numDrops`, times 1/2 while the rain is hidden by the roof check (both verified by the in-game probe, 2026-11-16)
- **Object names:** the precipitation object stays `cnr_precipitation`.
- **Project style:** no code comments, no emojis.

## Review Focus

1. **New sky pressed several times quickly.** Each press heads straight for the newest sky and the rain fade follows the newest target. No second precipitation object or sound piles up. Test in Task 3: `a second target mid-fade heads for the newest one and never makes two objects`.
2. **GO pressed right after New sky.** Clouds and fog land on the new sky, the clock runs, and the environment is locked. Test in Task 2: `GO during a blend lands the full sky and locks`.
3. **A new round starting within 3 s of the last one ending** (a cancel then a quick start). The player's own sky is saved, not a half-blended one. Test in Task 2: `a round starting during the restore blend saves the player's own sky`.
4. **Leaving the server or changing map during a fade or blend** (`leaveServer` runs on server leave and on extension unload). No rain object, no sound and no pending lock may be left behind. Tests: `leaving the server mid-rain removes the rain at once` (Task 2) and `drop removes rain and sound at once and cancels the lock timer` (Task 3).
5. **A storm in a month where the offsets meet** (November). Low below high. Test in Task 1: `the low is always below the high`.

---

### Task 1: Temperature from weather and date

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/climate.lua`
- Create: `tests/test_climate.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua` (the `M.WEATHER` `temperatureC` entries, `roundState`, the temperature call in `M.apply`)
- Modify: `tests/test_sky_client.lua` (tests at lines 85-104 that assert `averageC` 8 and 5)

**Interfaces:**
- Produces: `climate.range(weather, month) -> lowC, highC` (two numbers), or `nil` when either argument is unknown.

- [ ] **Step 1: Write the failing tests**

`tests/test_climate.lua`:
```lua
local climate = require("copsAndRobbers/climate")
test("climate gives the table's range per weather and month", function()
  local lo, hi = climate.range("clear", 7); assertEq(lo, 20); assertEq(hi, 31)
  lo, hi = climate.range("rain", 4); assertEq(lo, 10); assertEq(hi, 13)
  lo, hi = climate.range("fog", 10); assertEq(lo, 10); assertEq(hi, 14)
  lo, hi = climate.range("cloudy", 1); assertEq(lo, 2); assertEq(hi, 5)
  lo, hi = climate.range("snow", 12); assertEq(lo, -4); assertEq(hi, 0)
  lo, hi = climate.range("snow", 1); assertEq(lo, -5); assertEq(hi, -1)
end)
test("the low is always below the high", function()
  for _, w in ipairs({ "clear", "cloudy", "rain", "storm", "fog", "snow" }) do
    for m = 1, 12 do
      local lo, hi = climate.range(w, m)
      assertEq(lo < hi, true, w .. " " .. m)
      if w == "snow" then assertEq(hi <= 0, true, "snow " .. m) end
    end
  end
  local lo, hi = climate.range("storm", 11); assertEq(lo, 6); assertEq(hi, 8)
end)
test("unknown weather or month gives nothing", function()
  assertEq(climate.range("hail", 5), nil)
  assertEq(climate.range("rain", 13), nil)
  assertEq(climate.range(nil, 5), nil)
  assertEq(climate.range("rain", nil), nil)
end)
```
In `tests/test_sky_client.lua`:
- `"a round sky is applied and locked"` stops asserting `profiles[1].averageC == 8`. RAIN_NIGHT has no month, so the state's `temperatureCurveOverrideC == false` and `#fake.profiles == 0`.
- `"a part on the map's own comes from the map's start values"` stops asserting `averageC == 5`; same two asserts.
- Add `test("the temperature follows the weather and the server's month")`:
  - `sky.apply(WINTER)` (snow, month 12). The state's `temperatureCurveOverrideC` has two points. With the stub's times (noon 0, sunrise 0.775): `{ 2 / 24, 0 }` then `{ 0.775, -4 }`.
  - On a fresh load with `fake.state.latitude = -44.57`, the same `sky.apply(WINTER)` gives the same temperatures: the server's December, not the shifted June.
  - `#fake.profiles == 0` in both cases.

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `lua tests/run.lua tests/test_climate.lua tests/test_sky_client.lua`
Expected: FAIL (`copsAndRobbers/climate` not found; the profile asserts).

- [ ] **Step 3: Implement**

- `climate.lua`: tables and offsets from Global Constraints, the snow rule, then the `low + 2` floor for every weather except snow.
- `sky.lua`: drop `temperatureC` from `M.WEATHER` and the `setTemperatureProfile` call. `roundState` sets `state.temperatureCurveOverrideC` from Global Constraints.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/climate.lua client/lua/ge/extensions/copsAndRobbers/sky.lua tests/test_climate.lua tests/test_sky_client.lua
git commit -m "feat: outside temperature from the weather and the round's month"
```

### Task 2: Blends and the lock

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua` (`M.apply`, `M.startClock`, `M.update`, `M.restore`, `M.drop`, `forget`)
- Modify: `tests/env_stubs.lua`: `env.setState(s, seconds)` records `fake.lerps[#fake.setStates] = seconds`; `env.setState(nil)` counts `fake.resets` and returns
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`endRound(leaving)`, `leaveServer` calls `endRound(true)`, which calls `sky.restore(true)`)
- Modify: `tests/test_client.lua`
- Modify: `tests/test_sky_client.lua`

**Interfaces:**
- Consumes: `climate.range` (Task 1, already wired).
- Produces:
  - `sky.BLEND_SECONDS = 3`
  - `sky.update(dt)` must now run its lock timer even when no round is set. `copsAndRobbers.lua` already calls `sky.update` every frame.

- [ ] **Step 1: Write the failing tests**

In `tests/test_sky_client.lua`, using `fake.lerps`:
- `test("a round sky blends in over 3 s and locks after the blend")`:
  - `sky.apply(RAIN_NIGHT)`
  - the last `setState` was recorded with `fake.lerps[#fake.setStates] == 3`
  - `fake.locked == false`
  - `sky.update(3.4)` keeps `fake.locked == false`; `sky.update(0.2)` gives `fake.locked == true`
- `test("a second sky during a blend restarts the lock timer")`:
  - apply, `update(3)`, apply again, `update(1)`: still unlocked
  - `update(2.6)`: locked
- `test("GO during a blend lands the full sky and locks")`:
  - `sky.apply({ time = "sunset", weather = "rain", daySeconds = 1440, month = 4, day = 2, windDir = 0, windSeed = 1 })`, then `sky.startClock(0)` straight away
  - among the `setState` calls after the apply, one carries `cloudCover == 2.2` with no lerp, before the clock call (`play == true`)
  - `fake.locked == true`
- `test("GO after the blend only starts the clock")`: apply, `update(4)`, `startClock(0)`. The only new `setState` is the clock one (`play == true`, no `cloudCover`).
- `test("restore blends back over 3 s and then puts the earlier lock back")`:
  - `load({ locked = true })`, apply, `update(4)`, restore
  - the restore `setState` has `fake.lerps == 3`, and `fake.locked == false` during the blend
  - after `update(4)`, `fake.locked == true`
  - unlocked case: the same flow ends with `fake.locked == false`
- `test("every blend clears a running one first")`: two applies and a restore give `fake.resets == 3`, each reset straight before its blended `setState`.
- `test("an immediate restore lands at once and locks back")`: apply, `update(1)`, `restore(true)`. The restore `setState` has no lerp, the lock is back the way it was before the round, and `update(5)` changes nothing.
- In `tests/test_client.lua`, `test("leaving the server mid-rain removes the rain at once")`: a rain round, `env.tick(1)`, then `env.M.onBeamMPServerLeave()`. `env.sky.objects.cnr_precipitation == nil` straight away.
- `test("a round starting during the restore blend saves the player's own sky")`:
  - `fake.state.cloudCover = 0.05`
  - apply RAIN_NIGHT, `update(4)`, restore
  - set `fake.state.cloudCover = 1.1`, which simulates a half-blended sky
  - apply RAIN_NIGHT again, `update(4)`, restore, `update(4)`
  - `fake.state.cloudCover == 0.05`
- Update the existing tests that assert the lock straight after `apply` or `restore`. They assert it after `sky.update(4)` instead:
  - `"a round sky is applied and locked"`
  - `"wind updates don't touch the lock"`
  - `"restore puts the earlier lock back"`
- These must keep their meaning:
  - `"a failing apply still relocks and restore still works"`: a failing apply locks at once, because no blend is running. Restore still gives the earlier sky back after its blend: assert after `sky.update(4)`.
  - `"drop forgets without applying"`: drop also cancels any pending lock timer, and the lock goes back the way it was.

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `lua tests/run.lua tests/test_sky_client.lua`
Expected: FAIL (no lerp recorded, locked straight after apply).

- [ ] **Step 3: Implement in `sky.lua`**

- **`apply`:**
  - `env.setState(state, M.BLEND_SECONDS)`
  - keep `target = state` for GO
  - leave changes enabled and set the lock timer to `BLEND_SECONDS + 0.5`, with the lock to apply afterwards being "locked"
  - when the protected call fails, lock at once and clear the timer, as today
  - when saving the player's sky, use the restore target if a restore blend is still running, instead of `env.getState()`, and keep the earlier `wasLocked` with it (the environment is unlocked during that blend, so `env.canChange()` would read wrong)
- **`startClock`:** if the lock timer is running, `env.setState(target)` with no blend first, then the clock state as today. Then lock and clear the timer.
- **`restore`:**
  - `env.enableChanges(true)`, then `env.setState(saved, M.BLEND_SECONDS)`
  - keep `restoring = saved` until the timer ends
  - set the timer with the lock to apply afterwards being `wasLocked`
  - then `forget()` the round as today, keeping the timer and `restoring`
- **`update(dt)`:**
  - count the timer down first, even without a round
  - at zero: `env.enableChanges(not lockAfter)`, clear the timer and `restoring`
  - then the existing round work
- **`drop`:** clear the timer and `restoring`, and set the lock back the way it was before the round at once, as today.
- **`restore(immediate)`:** with `immediate`, `env.setState(saved)` with no blend, remove our rain object at once, set the lock back now, no timer.
- **Every blend:** `env.setState(nil)` straight before `env.setState(state, M.BLEND_SECONDS)`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/sky.lua tests/env_stubs.lua tests/test_sky_client.lua
git commit -m "feat: sky changes blend over 3 s and the lock waits for the blend"
```

### Task 3: Rain object, fade and sound

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/rain.lua`
- Create: `tests/test_rain.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua`:
  - move `createPrecipitation`, `removePrecipitation`, `updateCover`, `setHidden` and `castUp` into `rain.lua`
  - give `M.WEATHER` the new precipitation specs
  - call `rain.target`, `rain.update` and `rain.clear`
- Modify: `tests/env_stubs.lua`: `createObject` objects also get `play`, `stop` and `setVolumePitchCT(v, p, a, b)`, which records `self.volume = v`; `setTransform` is a no-op
- Modify: `tests/test_sky_client.lua`: precipitation asserts now go through `rain`'s fade, so advance with `sky.update`

**Interfaces:**
- Consumes: `sky.BLEND_SECONDS` (Task 2).
- Produces:
  - `rain.target(spec, seconds)`: spec is a precipitation spec from Global Constraints, or nil for none
  - `rain.update(dt)`: the fade, the roof check every 0.25 s as today, and the sound volume
  - `rain.clear()`: delete the object and the sound at once
  - `rain.active() -> bool`: true while an object exists or a fade is pending
  - `rain.NAME = "cnr_precipitation"`, `rain.SOUND = "cnr_rain_sound"`

- [ ] **Step 1: Write the failing tests**

`tests/test_rain.lua`:
- `dofile("tests/env_stubs.lua")`, `fakeEnvironment()`, and a fresh `require` of `copsAndRobbers/rain` per test, with `package.loaded` cleared the way `test_sky_client.lua` does it.
- `RAIN` and `STORM` and `SNOW` copy the Global Constraints specs.

```lua
test("rain fades in over the blend with its sound", function()
  rain.target(RAIN, 3)
  rain.update(0.1)
  local obj = fake.objects.cnr_precipitation
  assertEq(obj:getField("dataBlock"), "rain_medium"); assertEq(obj:getField("splashSize"), "0.25"); assertEq(obj:getField("hitVehicles"), nil)
  assertEq(obj:getField("minSpeed"), "0.4"); assertEq(obj.canSave, false)
  for _ = 1, 14 do rain.update(0.1) end
  assertNear(tonumber(obj:getField("numDrops")), 1500, 120)
  for _ = 1, 20 do rain.update(0.1) end
  assertEq(obj:getField("numDrops"), "3000")
  local snd = fake.objects.cnr_rain_sound
  assertEq(snd:getField("track"), "amb_rain_medium"); assertNear(snd.volume, 1.0, 1e-6)
end)
```

Also in `tests/test_rain.lua`:
- `test("rain to clear fades out, then removes rain and sound")`: rain at full; `target(nil, 3)`; after 1.5 s about 1500; after 3.1 s both objects gone.
- `test("rain to storm moves the count and raises the volume")`: rain at full; `target(STORM, 3)`; after 3.1 s `numDrops == "7000"`, `minSpeed == "0.6"`, sound volume 2.0, and only one precipitation object ever existed.
- `test("rain to snow fades out, then snow fades in without a sound")`:
  - after 1.6 s the rain object is gone or at 0, and no sound is playing
  - after 3.1 s the object's `dataBlock == "Snow_menu"` with `numDrops == "5000"`, and `fake.objects.cnr_rain_sound == nil`
- `test("a second target mid-fade heads for the newest one and never makes two objects")`: `target(RAIN, 3)`, 1 s, `target(STORM, 3)`, 1 s, `target(nil, 3)`, 3.1 s. Everything is gone, and `fake.deleted` names `cnr_precipitation` once.
- `test("the roof lowers the sound to half and hides the rain")`: reuse the `withRoof` helper from `test_sky_client.lua` (copy it). Under a roof at 3 m, after two 0.25 s checks: hidden, and the sound volume is `0.5`.
- `test("drop removes rain and sound at once and cancels the lock timer")`: this test lives in `tests/test_sky_client.lua`, since it needs `sky`. Apply RAIN_NIGHT, `update(1)`, `drop()`. Rain and sound are gone at once, and `update(5)` changes nothing (no new `setState`, lock as before the round).
- `test("round end fades the rain out")`, also in `test_sky_client.lua`: apply RAIN_NIGHT, `update(4)`, restore. The rain is still there right after restore, and gone after `update(3.2)`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `lua tests/run.lua tests/test_rain.lua tests/test_sky_client.lua`
Expected: FAIL (module `copsAndRobbers/rain` not found).

- [ ] **Step 3: Implement `rain.lua` and wire it**

The fade (the part the tests leave open):
- **State:** `cur = { spec, drops }` when an object exists, `goal` (spec or nil), `rateOut`, `rateIn`, `sinceWrite`.
- **`target(spec, seconds)`:**
  - **same `dataBlock` as `cur`:** write the new spec's other fields now; `rateIn = max(1, |spec.numDrops - cur.drops|) / seconds`
  - **both present with a different kind:** `rateOut = cur.drops / (seconds / 2)` and `rateIn = spec.numDrops / (seconds / 2)`
  - **only `spec`:** `rateIn = spec.numDrops / seconds`
  - **only `cur`:** `rateOut = cur.drops / seconds`
  - **`seconds <= 0`:** jump straight to the goal
- **`update(dt)`:**
  1. If `cur` exists and `goal` is nil or a different kind, lower `cur.drops` by `rateOut * dt`. At 0, delete the object and the sound, and clear `cur`.
  2. Otherwise, if `goal` exists and `cur` doesn't, create the object at 0 drops from `goal`, with the sound if `goal.volume`.
  3. If `cur` and `goal` are the same kind, move `cur.drops` toward `goal.numDrops` by `rateIn * dt`.
  4. Write the drop count as `obj.numDrops = math.floor(drops)` (the in-game probe confirmed it thins live rain at once, 2026-11-16) and the sound volume, when `FADE_INTERVAL` has passed or the target was just reached. The stub object needs `numDrops` readable after this assignment: `getField("numDrops")` returns the assigned value as a string, so tests can keep reading the field.
  5. Run the roof check as today, hiding the object and applying the 1/3 volume.

In `sky.lua`:
- `apply` calls `rain.target(M.WEATHER[p.weather] and M.WEATHER[p.weather].precipitation or nil, M.BLEND_SECONDS)`. This replaces the old remove-and-create.
- `update` calls `rain.update(dt)` whenever `rain.active()`, even without a round.
- `restore` calls `rain.target(nil, M.BLEND_SECONDS)`; `restore(true)` and `drop` call `rain.clear()`.
- On a failing apply: `rain.clear()`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`. The existing roof tests (`"rain stops under a close roof…"`, `"rain keeps falling under a high bridge"`, `"the roof check runs before GO…"`) still pass, with updates added first to let the rain fade in.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/rain.lua client/lua/ge/extensions/copsAndRobbers/sky.lua tests/env_stubs.lua tests/test_rain.lua tests/test_sky_client.lua
git commit -m "feat: rain and snow fade with the sky, faster rain, heavier storms, rain sound"
```

### Task 4: Docs

**Files:**
- Modify: `docs/FEATURES.md` (the Night and weather section: blends, rain speeds, rain sound, temperature)
- Modify: `README.md` (the weather lines, if they describe how the sky changes or the temperature)
- Modify: `docs/DEPENDENCIES.md`

- [ ] **Step 1: Docs**

- **FEATURES and README:**
  - sky changes blend over about 3 s (round start, New sky, round end), and New sky pressed quickly heads for the last pick
  - rain and snow fade in and out
  - rain falls like the stock maps' rain; storms have faster, bigger and more drops
  - the game's rain sound plays in rain and storm, louder in a storm and quieter under cover
  - the outside temperature follows the weather and the round's date (a December snow round −4 to 0 °C, a clear July day 20 to 31 °C)
  - no thunder
- **DEPENDENCIES:**
  - `core_environment.setState(state, lerpSeconds)`: blends clouds, fog, fog height and time; only advances while changes are enabled; a new state mid-blend shortens it to 0.3 s
  - `setTemperatureProfile({ averageC, minC, maxC })`
  - `Precipitation.numDrops` set on live rain (probe-verified), `splashSize`
  - the `SFXEmitter` with the `amb_rain_medium` profile, `setVolumePitchCT` and `play()`
  - an update check matching the spec's In-game check

- [ ] **Step 2: Verify and commit**

Run: `make test`
Expected: `0 failed`.
```bash
git add docs/FEATURES.md README.md docs/DEPENDENCIES.md
git commit -m "docs: sky blends, rain, rain sound and temperature"
```

### Task 5: In-game check with the user

**Files:** `client/lua/ge/extensions/copsAndRobbers/sky.lua` / `rain.lua` / `climate.lua` (for any value the user's screenshots or the check change)

- [ ] **Step 1: Install on the local server and start it**

Run `make install-local` and start `.testserver/BeamMP-Server`.

- [ ] **Step 2: Hand the user the spec's In-game check list (items 1–8)**

For item 6, they send screenshots of rain, storm and snow at the starting values. Listen to the rain and storm volume next to a car's engine and in a tunnel.

- [ ] **Step 3: Apply the agreed values and commit**

Run: `make test`
Expected: `0 failed`.
```bash
git commit -am "fix: rain values from the in-game check"
```
