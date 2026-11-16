# Police Helicopter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the periodic 30 s last-seen ping with a police helicopter that tracks the runner in the open, and hide the runner from the cops' minimap and name tags unless spotted.

**Architecture:**
- **Server:** a pure server module `cnr/helicopter.lua` owns the phases. `Round` ticks it, merges it with cop sight into one `tracked` flag (live updates, one ping per loss) and a `shown` flag (hiding). `main.lua` turns the new effects into `cnr_heli`, `cnr_runnerShown` and `cnr_nearestCop` events, and takes `cnr_cover` from the game that owns the runner's car.
- **Client:**
  - `copsAndRobbers/heli.lua`: cover reporting, the searchlight and the minimap ring
  - `copsAndRobbers/hiding.lua`: the name tag and the minimap filter
  - `hud.lua`: the helicopter item

**Tech Stack:**
- Lua 5.x: the BeamMP server plugin and the BeamNG GE extension
- Vue 3: the BeamNG UI apps
- tests: the repo's own Lua runner (`make test`) and a Vue compile check (`make vuecheck`)

**Spec:** `docs/superpowers/specs/2026-11-16-police-helicopter-design.md`

## Global Constraints

- **Code style:**
  - No comments and no emojis in code (`AGENTS.md`).
  - Lua: camelCase locals, a module table `M`. Follow the surrounding file's style.
- **No version bumps** on the branch: `CLIENT_VERSION` and `VERSION` stay. Bumping happens on main after merge.
- **Config defaults** (exact):

  | Key | Default |
  |---|---|
  | `helicopter` | `true` |
  | `helicopterArrivalSeconds` | `60` |
  | `helicopterUpSeconds` | `120` |
  | `helicopterRefuelSeconds` | `90` |

  - `helicopterUpSeconds` is strictly positive.
  - Arrival and refuel are at least 0.
  - Refuel 0 means the helicopter stays up once up.
- **Retired:** `lastSeenIntervalSeconds` is retired (added to `RETIRED_KEYS`, removed from `DEFAULTS`, `rules.KEYS`, the panel and the docs).
- **Weather:**
  - Grounded weathers: `storm`, `fog`, `snow`.
  - The re-find time is 5 s in the open, and 10 s when the weather is `rain`.
  - The weather is read at cop release from the round's `sky.weather`.
- **One `lastSeen` per loss:** it fires when `tracked` (cop sight or the helicopter tracking) goes from true to false. There are no other `lastSeen` effects.
- **`shown`:**
  - true in every state before `headstart`, and whenever `sightMaxMeters` is 0
  - from `headstart` on, it equals `tracked`
- **The runner's nearest-cop update** comes every 30 s while running (`NEAREST_COP_SECONDS = 30`), besides the one carried by live updates.
- **HUD texts** (exact):

  | Phase | Text |
  |---|---|
  | arriving | `HELICOPTER IN` + `m:ss` |
  | tracking | `HELICOPTER` + `m:ss` (no time when refuel is 0) |
  | searching | `HELICOPTER SEARCHING` |
  | refuelling | `HELICOPTER REFUELLING` + `m:ss` |
  | grounded | `HELICOPTER GROUNDED (FOG)`, the reason upper-cased |

- **Client constants:**
  - cover check every `0.25` s, from `1.5` m above the car, with `shelter.step`
  - searchlight `cnr_heli_light`, `40` m above the runner's car, only while tracking and `sky.isNight()`
- **BeamNG.Earth** (`geoMode`): no minimap ring, and no minimap hiding. The name tag is still hidden.

## Review Focus

1. **A cop who rejoins mid-chase while the runner is hidden** must come back hidden, with the helicopter's current phase on the HUD. Task 2 (setup carries `runnerShown` and `heli`) and Task 3 (`cnr_roundSetup` passes them) pin this.
2. **Practice as the runner:** no `cnr_runnerShown` goes to the practising runner, and the runner's own game never hides anything. Task 3 and Task 6 pin it.
3. **A round that ends any way** (catch, cancel, leave, map change, extension unload) leaves no hidden name tag, no wrapped iterator and no searchlight behind. Task 5 and Task 6 pin each exit.
4. **New sky in prep turning the weather to fog** grounds the helicopter, because the weather is read at release, not at start. Task 2 pins it.
5. **A cover report from a cop, or before the head start,** changes nothing. Task 2 pins it.

---

### Task 1: Config, rules and the helicopter state machine

**Files:**
- Create: `server/CopsAndRobbers/cnr/helicopter.lua`
- Modify:
  - `server/CopsAndRobbers/cnr/config.lua` (`DEFAULTS`, `strictlyPositive`, `RETIRED_KEYS`)
  - `server/CopsAndRobbers/cnr/rules.lua` (`KEYS`)
- Test:
  - Create `tests/test_helicopter.lua`
  - Modify `tests/test_config.lua`, `tests/test_rules.lua`

**Interfaces:**
- Produces (`cnr/helicopter.lua`):
  - `M.GROUNDED = { storm = true, fog = true, snow = true }`
  - `M.REFIND_SECONDS = 5`, `M.RAIN_REFIND_SECONDS = 10`
  - `M.new(cfg, weather, now) -> h`
    - `weather` may be nil.
    - Grounded weathers give `h` in phase `grounded` forever.
    - Otherwise phase `arriving`, ending at `now + cfg.helicopterArrivalSeconds`.
  - `M.update(h, now, covered) -> boolean`
    - It advances every phase that has ended by `now` (loop), then applies the cover rule.
    - It returns true when `M.status(h, now).phase` differs from before the call.
  - `M.status(h, now) -> { phase = "arriving"|"tracking"|"searching"|"refuelling"|"grounded", seconds = number|nil, reason = string|nil }`
    - `seconds` is the time left in the current timer: arrival, up or refuel. It is nil when grounded, and while up with refuel 0.
    - `reason` is the weather key, only when grounded.
  - `M.tracking(h) -> boolean`
  - `M.flew(h) -> boolean`: true unless grounded.
- **Timers:**
  - `up` lasts `helicopterUpSeconds`, counting both tracking and searching. `refuelling` lasts `helicopterRefuelSeconds`.
  - Each new phase starts at the previous phase's end time, not at `now`.
  - With refuel 0, `up` never ends.
- **Cover rule while up:**
  - On entering up, `tracking = not covered`.
  - While tracking, `covered` switches to searching.
  - While searching, the runner being in the open continuously for the re-find time (`openSince`) switches back to tracking. Cover clears `openSince`.
  - Leaving up clears tracking.

- [ ] **Step 1: Write the failing tests** in `tests/test_helicopter.lua`:
  ```lua
  local helicopter = require("cnr.helicopter")
  local config = require("cnr.config")
  local function cfg(o) return (config.merge(o)) end

  test("the helicopter arrives, flies, refuels and flies again", function()
    local h = helicopter.new(cfg({ helicopterArrivalSeconds = 60, helicopterUpSeconds = 120, helicopterRefuelSeconds = 90 }), "clear", 10)
    assertEq(helicopter.status(h, 10).phase, "arriving"); assertEq(helicopter.status(h, 10).seconds, 60)
    assertEq(helicopter.update(h, 69, false), false)
    assertEq(helicopter.update(h, 70, false), true)
    assertEq(helicopter.status(h, 70).phase, "tracking"); assertEq(helicopter.status(h, 100).seconds, 90)
    assertEq(helicopter.update(h, 190, false), true)
    assertEq(helicopter.status(h, 190).phase, "refuelling"); assertEq(helicopter.status(h, 200).seconds, 80)
    helicopter.update(h, 280, false)
    assertEq(helicopter.status(h, 280).phase, "tracking"); assertEq(helicopter.status(h, 280).seconds, 120)
  end)
  test("time up keeps counting while searching", function() end)
  test("storm, fog and snow ground it for good", function() end)
  test("in the open again it finds the runner after 5 s, 10 s in rain", function() end)
  test("an arrival of 0 means it is up on the first update", function() end)
  test("a refuel of 0 keeps it up with no countdown", function() end)
  test("a long gap advances through several phases at once", function() end)
  test("going up while the runner is covered starts searching", function() end)
  ```
  Fill the empty bodies with these assertions:
  - **Time up while searching:** covered from 70 to 150 → `searching`, and `seconds` at 150 is 40. At 190 it is `refuelling`.
  - **Grounded:** for each of `storm`, `fog`, `snow`:
    - `phase == "grounded"` and `reason == weather`
    - `update(h, 10000, false)` returns false
    - `flew(h) == false`
  - **Re-find:** tracking at 70, covered at 80 → `searching`.
    - Open at 81: still `searching` at 85.9, `tracking` at 86.
    - With `"rain"`: `searching` at 90.9, `tracking` at 91.
    - Covered again at 83, before the 5 s are up, resets the count.
  - **Arrival 0:** `new(..., 10)` then `update(h, 10, false)` → `tracking`.
  - **Refuel 0:** `seconds == nil` while up, and still `tracking` at 10000.
  - **Long gap:** `update(h, 280, false)` straight after `new` at 10 (arrival 60, up 120, refuel 90) → `tracking` with `seconds == 120`.
  - **Covered on arrival:** `update(h, 70, true)` → `searching`.

  In `tests/test_config.lua`:
  - assert the four defaults
  - `config.merge({ helicopterUpSeconds = 0 })` warns and falls back to 120
  - `helicopterRefuelSeconds = 0` and `helicopterArrivalSeconds = 0` are kept
  - `config.DEFAULTS.lastSeenIntervalSeconds == nil`
  - `config.setValue({ lastSeenIntervalSeconds = 30 }, "headStartSeconds", "9").lastSeenIntervalSeconds == nil`
  - Replace the old `assertEq(c.lastSeenIntervalSeconds, 30)` line.

  In `tests/test_rules.lua`:
  - the count goes to 19 (`n` and `#rules.KEYS`)
  - `p.helicopter == true`, `p.helicopterUpSeconds == 120`, `p.lastSeenIntervalSeconds == nil`

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: FAILs in `test_helicopter.lua` (module not found), `test_config.lua` and `test_rules.lua`.

- [ ] **Step 3: Implement**
  - `cnr/helicopter.lua` as in Interfaces.
  - `config.lua`:
    - add the four `DEFAULTS` and `strictlyPositive.helicopterUpSeconds = true`
    - remove `lastSeenIntervalSeconds` from `DEFAULTS`
    - `RETIRED_KEYS = { clockSpeed = true, lastSeenIntervalSeconds = true }`
  - `rules.lua` `KEYS`: drop `lastSeenIntervalSeconds`, and append `"helicopter", "helicopterArrivalSeconds", "helicopterUpSeconds", "helicopterRefuelSeconds"`.

- [ ] **Step 4: Run the tests**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the three files pass.
  - Failures elsewhere that read `lastSeenIntervalSeconds` (`test_round`, `test_main`, `test_hud`, `test_client`) are expected until Tasks 2, 3 and 7. List them in the report; don't fix them here.

- [ ] **Step 5: Commit**
  `git add server/CopsAndRobbers/cnr/helicopter.lua server/CopsAndRobbers/cnr/config.lua server/CopsAndRobbers/cnr/rules.lua tests/test_helicopter.lua tests/test_config.lua tests/test_rules.lua && git commit -m "feat: helicopter state machine and settings; retire the last-seen interval"`

### Task 2: Round: one tracking source, pings, hiding and cover

**Files:**
- Modify: `server/CopsAndRobbers/cnr/round.lua`:
  - `clear`
  - `setupFor`
  - `tick` (around lines 322-377): the release step and the interval ping
  - `sightTick` (481-527)
  - `finish` (the record)
  - a new `coverReport`
- Test: `tests/test_round.lua`

**Interfaces:**
- Consumes: `helicopter.new/update/status/tracking/flew` (Task 1).
- Produces:
  - **New effects:**
    - `{ kind = "heli", phase, seconds, reason }`, when the helicopter is created at release and on every `update` that returns true
    - `{ kind = "runnerShown", shown = boolean }`, on every change of `self.shown`
    - `{ kind = "nearestCop", dist = number }`, every `NEAREST_COP_SECONDS` while running when some cop has a position
  - **Changed effects:**
    - `live` now also comes from the helicopter, with the same fields.
    - `lastSeen` now only comes from the one-per-loss rule.
  - **`setupFor` adds:**
    - `e.runnerShown = self.shown`
    - `e.heli = self.heli and helicopter.status(self.heli, now) or nil`
  - **`Round:coverReport(now, pid, covered)`**, which returns nothing:
    - It accepts only in `headstart` or `running`, and only from `pid == self.runnerId` (not AI), or from `self.issuerId` when `self.test` and the runner is AI.
    - It sets `self.runnerCovered = covered == true`.
  - **The run record gains** `helicopter = true` when `self.heli` exists and `flew`, else nil.
- **New fields in `clear`:**
  - `self.heli = nil`
  - `self.runnerCovered = false`
  - `self.tracked = false`
  - `self.shown = true`
  - `self.nearestAt = nil`
  - `lastSeenAt` goes away entirely.
- **Approach:**
  - **`sightTick`** keeps everything about cop sight: `seeing`, `self.inSight`, `spotted` effects, `copSight`, `hiddenSeconds`, `lostCount` and the "lost" note. It returns `seeing`, but no longer emits `live` or `lastSeen`.
  - **The nearest cop** comes from a helper that skips penalised cops and works with sight off: `Round:nearestCop(cars, runnerCar) -> number|nil`.
  - **A new `Round:trackTick(now, cars, runnerCar, seeing, nearest, fx)`:**
    - `tracked = self.inSight or (self.heli and helicopter.tracking(self.heli))`
    - **While tracked:** throttled by `liveAt` and `sightLiveIntervalSeconds`, it emits `live` with `noRoute` worked out as today for `seeing` cops only.
    - **On true → false:** `liveAt = nil`, and one `lastSeen`.
  - **At release:** create `self.heli` when `cfg.helicopter`, using `self.sky and self.sky.weather`. Also set `self.nearestAt = now`, so the first `nearestCop` comes 30 s after release.
  - **In the running branch:** before `trackTick`, call `helicopter.update(self.heli, now, self.runnerCovered)`, and emit `heli` when it returns true or the helicopter was just created.
  - **At the end of `tick`,** recompute `shown` (Global Constraints) and emit `runnerShown` on change. Before `headstart` nothing changes, so prep emits nothing.

- [ ] **Step 1: Update the existing tests and write the failing ones**
  - **Existing tests:**
    - Remove `lastSeenIntervalSeconds` overrides throughout `tests/test_round.lua`.
    - Rewrite the interval tests (~534-560) as "no periodic last seen any more".
    - Rewrite "sight is off when sightMaxMeters is 0" (~753): no `live` and no `lastSeen` through t = 200 with `helicopter = false`.
    - Where an existing test runs past t = 70 and counts `live`/`lastSeen`, pass `helicopter = false` so the helicopter doesn't add effects.
  - **New tests** (cars from `farCars()`; `chasing(o)` releases at t = 11):
    - `"no periodic last seen with the helicopter off"`: `chasing({ helicopter = false })`, ticks 12..200 → no `lastSeen`.
    - `"one last seen when sight is lost and the helicopter is not tracking"`: as the existing lost-sight test. Exactly one `lastSeen` across ticks 21..200 with `helicopter = false`.
    - `"no last seen when sight is lost while the helicopter tracks"`:
      - `chasing({ helicopterArrivalSeconds = 0 })`, sight on at 12 and off at 20
      - ticks to 30 → no `lastSeen`, and `live` keeps coming
    - `"no last seen when the helicopter loses the runner while a cop sees them"`:
      - arrival 0, sight on at 12
      - `coverReport(13, 1, true)` and ticks to 30 → no `lastSeen`
      - then sight off at 30 → exactly one `lastSeen` by 32
    - `"the helicopter alone sends live updates to every cop with a route"`:
      - arrival 0, no sight
      - `live` at 12, at most once per `sightLiveIntervalSeconds`
      - `next(e.noRoute) == nil`
    - `"live goes out once per tick when sight and helicopter both track"`: `count(fx, "live") <= 1` each tick.
    - `"the helicopter starts at release with the round's weather"`:
      - `r.sky = { weather = "fog" }` before release
      - the release tick has `find(fx, "heli").phase == "grounded"` and `.reason == "fog"`
      - with `"clear"` it is `"arriving"`, with `seconds == 60`
    - `"heli effects follow phase changes"`: arrival 60, up 120, refuel 90.
      - `heli` at release (`arriving`), at 71 (`tracking`), at 191 (`refuelling`)
      - none on ticks in between
    - `"helicopter off means no heli effects"`.
    - `"runnerShown hides the runner from the head start and shows them while tracked"`:
      - no `runnerShown` in `started()` and through the countdown
      - `shown == false` at the countdown → headstart tick
      - `true` when a cop sees the runner, and `false` again after the grace
    - `"sight off never hides the runner"`: `sightMaxMeters = 0` → no `runnerShown` effect ever, and `r.shown == true` through the chase.
    - `"setup carries runnerShown and the helicopter status"`:
      - `playerJoined` mid-chase (helicopter tracking) → setup `.runnerShown == true` and `.heli.phase == "tracking"`
      - in prep → `.runnerShown == true` and `.heli == nil`
    - `"cover only counts from the runner's game during the chase"`:
      - `coverReport` from a cop (pid 2) → `r.runnerCovered == false`
      - from the runner in prep → still false
      - from the runner while running → true
      - in practice as a cop (`r:start(0, nil, 2, players, { test = true, role = "cop" })`, then `vehiclePicked`, `go` and ticks until `running`), from issuer 2 → true
    - `"the runner gets the nearest cop every 30 s"`: with `helicopter = false` and no sight, `nearestCop` at 41, 71 and 101, with `dist == 300`.
    - `"runs note when the helicopter flew"`:
      - the record has `helicopter == true` after a clear round
      - nil with fog, and nil with `helicopter = false`

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new `test_round.lua` tests fail.

- [ ] **Step 3: Implement** as in Interfaces and Approach, with `local NEAREST_COP_SECONDS = 30` beside the other round constants, and `local helicopter = require("cnr.helicopter")`.

- [ ] **Step 4: Run the tests**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected:
  - `test_round.lua`, `test_helicopter.lua`, `test_config.lua` and `test_rules.lua` all pass.
  - The remaining failures are only in files later tasks own.

- [ ] **Step 5: Commit**
  `git commit -am "feat: the helicopter tracks the runner; one ping per loss; runner hidden unless spotted"`

### Task 3: Server wiring in main.lua

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`:
  - `applyEffects`, around lines 500-640
  - a new `cnrOnCover`
  - `MP.RegisterEvent`
- Test: `tests/test_main.lua`

**Interfaces:**
- Consumes: the Task 2 effects, and `current:coverReport(now, pid, covered)`.
- Produces these client events:
  - **`cnr_heli { phase, seconds, reason }`:** sent with `send(e.to or -1, ...)`.
  - **`cnr_runnerShown { shown }`:** to every pid in `current.players` that is not the runner and not AI. It ignores `e.to`, like `lastSeen` does.
  - **`cnr_nearestCop { dist }`:** to the runner when not AI.
  - **`cnr_roundSetup`** gains `runnerShown = e.runnerShown` and `heli = e.heli`.
  - **`cnr_cover`** is the server event the client sends (`{ covered = bool }`).
- `cnrOnCover(pid, data)` decodes like `cnrOnSight` and calls `current:coverReport(now(), pid, d.covered == true)`. Register `MP.RegisterEvent("cnr_cover", "cnrOnCover")`.

- [ ] **Step 1: Write the failing tests** in `tests/test_main.lua`, following the existing `boot()` helpers:
  - **Update the old tests:**
    - The tests at ~489 and ~608 that boot with `{"lastSeenIntervalSeconds": 5}` should test the new rule instead: a lost-sight ping still reaches cops with `pos`, or with `geo` on Earth.
    - Update the saved-config test at ~738, which drops retired keys, so it also drops `lastSeenIntervalSeconds`.
  - `"heli phases reach every player"`:
    - a round with arrival 0
    - after release the last `cnr_heli` to each player has `phase == "tracking"`
  - `"runnerShown goes to cops only"`:
    - at the head start, cops get `cnr_runnerShown` with `shown == false`
    - the runner gets none
  - `"practice as runner sends no runnerShown"`.
  - `"a rejoining cop gets runnerShown and heli in setup"`.
  - `"cnr_cover from the runner reaches the round"`:
    - fire `cnr_cover` with `{"covered":true}` from the runner while running
    - `current.runnerCovered == true` (reach it the way other main tests inspect the round, or through the next `heli` phase becoming `searching`)
  - `"the runner gets cnr_nearestCop every 30 s"`.

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new `test_main.lua` tests fail.

- [ ] **Step 3: Implement** the three effect branches, the setup fields, `cnrOnCover` and the registration.

- [ ] **Step 4: Run the tests**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: all server test files pass.

- [ ] **Step 5: Commit**
  `git commit -am "feat: send helicopter, hiding and nearest-cop events; take cover reports"`

### Task 4: HUD helicopter item

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`statusBlock`, a new `M.heliItem`)
  - `client/lua/ge/extensions/copsAndRobbers/hudfeed.lua` (`M.heli`, `clearRound`, `push`)
  - `client/lua/ge/extensions/copsAndRobbers.lua`: the `cnr_heli` handler, `onRoundSetup` (`d.heli`)
  - `client/ui/modules/apps/CopsAndRobbersHud/HudChase.vue`
- Test: `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- Produces:
  - **`hudfeed.heli(h)`:**
    - `h = { phase, endsAt, reason }` or nil
    - cleared by `hudfeed.clearRound()`
    - passed to `hud.payload` as `info.heli`
  - **`hud.heliItem(heli, now) -> { text = string, time = string|nil }|nil`**, with the texts in Global Constraints.
    - `time` is `M.formatTime(math.max(0, endsAt - now))` when `endsAt` is set and the phase is arriving, tracking or refuelling.
    - It returns nil for nil input or an unknown phase.
  - **`statusBlock` sets `status.heli = M.heliItem(info.heli, now)`.**
  - **The extension's `cnr_heli` handler and `onRoundSetup`** both turn `{ phase, seconds, reason }` into `hudfeed.heli({ phase, reason, endsAt = seconds and clock + seconds })`, or nil when the payload has no phase.
- **HudChase:** one more `.item` after the tag:
  - the icon, then `status.heli.text`, then `status.heli.time` in a `.mono` span when set
  - the icon is from the game's `icons` set: pick a helicopter or aircraft icon if `icons` has one, otherwise `icons.mapPoint`

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_hud.lua`:** `heliItem` for each phase.
    - `{ phase = "arriving", endsAt = 45 }` at 0 → `text == "HELICOPTER IN"`, `time == "0:45"`
    - `tracking` with `endsAt = 90` → `"HELICOPTER"`, `"1:30"`
    - `tracking` without `endsAt` → `time == nil`
    - `searching` → `"HELICOPTER SEARCHING"`, no time
    - `refuelling` → `"HELICOPTER REFUELLING"`
    - `grounded` with `reason = "fog"` → `"HELICOPTER GROUNDED (FOG)"`
    - an `endsAt` in the past → `"0:00"`
    - nil → nil
  - **`tests/test_client.lua`:**
    - `cnr_heli { phase = "arriving", seconds = 60 }` after release → `env.hud().status.heli.time == "1:00"`, and after `env.tick(10)` it is `"0:50"`
    - a `cnr_roundSetup` with `heli = { phase = "searching" }` and `phase = "running"` shows `"HELICOPTER SEARCHING"`
    - after `cnr_roundEnd` and a new setup, `status.heli == nil`

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run the tests and the UI check**
  Run: `make test 2>&1 | grep -E 'FAIL|passed' && make vuecheck`. Expected: the new tests pass, and vuecheck reports no errors.

- [ ] **Step 5: Commit**
  `git commit -am "feat: helicopter status on the HUD"`

### Task 5: Cover reporting, searchlight and minimap ring

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heli.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`:
  - `cnr_heli` and `onRoundSetup` also feed `heli.set`
  - `onUpdate`, `endRound`, `M.onDrawOnMinimap`
- Test: create `tests/test_heli_client.lua`, modify `tests/test_client.lua`

**Interfaces:**
- **Constants:**
  - `M.COVER_INTERVAL = 0.25`, `M.COVER_HEIGHT = 1.5`
  - `M.LIGHT_HEIGHT = 40`, `M.LIGHT_NAME = "cnr_heli_light"`
- **State:**
  - `M.new() -> state`
  - `M.set(state, d, clock)`: `d` is a `cnr_heli` payload or nil. It stores `phase` and `reason`, and `endsAt = seconds and clock + seconds`.
  - `M.tracking(state) -> boolean`: phase is `"tracking"`.
- **Cover:**
  - `M.coverTick(state, clock, obj, castUp) -> boolean|nil`
    - It checks at most every `COVER_INTERVAL`, at `obj:getPosition()` raised by `COVER_HEIGHT`, with `shelter.roofed(pos, castUp)` and its own `shelter.new()` state stepped by `shelter.step`.
    - It returns the covered value to send the first time after `M.resetCover`, and after each switch. Otherwise it returns nil.
  - `M.resetCover(state)`
- **Searchlight:**
  - `M.lightTick(state, target, night)`
    - While `M.tracking(state) and night and target`: create the light once and keep it `LIGHT_HEIGHT` above `target:getPosition()`, pointing straight down.
    - Create it with `createObject("SpotLight")`, `canSave = false`, `registerObject(M.LIGHT_NAME)`, and `scenetree.MissionGroup:addObject`, guarded with `pcall` like `rain.lua`.
    - Otherwise delete it.
  - `M.clear(state)`: deletes the light and resets the phase and the cover.
- **Ring:** `M.drawRing(state, target, utils)`
  - While tracking and a target exists, it calls `utils.simpleCircle(target:getPosition(), fill, stroke, radius)`.
  - The colours and radius are the builder's pick, with the same colour types the game's minimap uses.
- **Wiring in `copsAndRobbers.lua`:**
  - **The cover owner's car:**
    - `ownVehicle()` when `role == "runner"`
    - otherwise `ai.runnerObject()`, which is non-nil only on the practising cop's game that owns the AI runner
  - **Cover:** while `statusActive`, on that car:
    - `local c = heli.coverTick(heliState, clock, car, castUp)`
    - `if c ~= nil then sendServer("cnr_cover", { covered = c }) end`
    - `castUp` casts `castRayStatic(pos, vec3(0, 0, 1), range)`. Call `heli.resetCover` in `onRelease` so the first check is always sent.
  - **The searchlight target:** `ownVehicle()` for the runner, `runnerObject()` otherwise. Call `heli.lightTick(heliState, target, sky.isNight())` every frame while `active`.
  - **The ring:**
    - `M.onDrawOnMinimap = function(td) if active and not geoMode and ui_apps_minimap_utils then heli.drawRing(heliState, ringTarget(), ui_apps_minimap_utils) end end`
    - `ringTarget()` is the same target as the searchlight's, so the runner sees the ring on themselves too.
  - **Cleanup:** `endRound` calls `heli.clear(heliState)`.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_heli_client.lua`:** use `dofile("tests/env_stubs.lua")` and `fakeEnvironment()` for `createObject` and `scenetree`, and a fake target `{ getPosition = function() return vec3(...) end }`.
    - **Cover:**
      - the first `coverTick` returns `false` in the open
      - nil on the next calls while unchanged
      - nil within 0.25 s
      - `true` only after two covered checks (`shelter.CHECKS_TO_SWITCH`)
      - and again after `resetCover`
    - **The searchlight is created only when tracking and night:**
      - `fake.objects["cnr_heli_light"]` exists at night while tracking
      - none by day
      - deleted when the phase turns `searching`, when night ends, and on `clear`
      - its position follows the target at `z + 40`
    - **The ring:** `drawRing` calls `utils.simpleCircle` once while tracking, and not while `searching` or with a nil target.
  - **`tests/test_client.lua`:**
    - as runner after `cnr_release`, `env.lastSent("cnr_cover").covered == false`
    - as cop, no `cnr_cover` is sent
    - `M.onDrawOnMinimap` with `geoMode` set draws nothing (stub `ui_apps_minimap_utils`)

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run the tests**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: all pass except files Task 7 owns.

- [ ] **Step 5: Commit**
  `git commit -am "feat: cover reports, night searchlight and minimap ring for the helicopter"`

### Task 6: Hiding the runner on cops' games

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/hiding.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`:
  - a `cnr_runnerShown` handler, and `onRoundSetup` (`d.runnerShown`)
  - `onUpdate`, `endRound`, `M.onExtensionUnloaded`
- Test: create `tests/test_hiding.lua`, modify `tests/test_client.lua`

**Interfaces:**
- **Target:** `M.set(target)`, where `target = { vid = number|nil, key = string|nil, minimap = boolean }` or nil to show everything.
  - It is called every frame, so it must be cheap.
  - When the key changes or the target becomes nil, it clears `hideNametag` on the key it had set.
  - `vid` is the runner's game vehicle id, skipped on the minimap when `minimap` is true.
  - `key` is the BeamMP vehicle key whose `hideNametag` is set.
- **`M.tick(clock)`**, at most once a second:
  - It re-asserts `MPVehicleGE.getVehicles()[key].hideNametag = true` while a key is hidden.
  - It wraps `ui_apps_minimap_vehicles.drawOtherVehicles` when that extension exists and the function isn't the wrapper.
- **The wrapper:**
  - While `target.minimap and target.vid`, it swaps the global `activeVehiclesIterator` for one that skips `vid`. It calls the original with `pcall(original, ...)`, restores the global, and re-raises nothing.
  - Otherwise it calls the original directly.
- **`M.clear()`:** clears the name tag it set (`hideNametag = nil` on its key) and the target. It keeps the wrap in place, which passes through.
- **`M.unload()`:** `M.clear()`, then puts the original `drawOtherVehicles` back only if the current one is still the wrapper.
- **Wiring:**
  - Keep `runnerShown` (from setup and `cnr_runnerShown`), defaulting to true.
  - Each frame while `active and role == "cop"`:
    - `hiding.set(runnerShown and nil or { vid = obj and obj:getID(), key = traffic.roundCar(runnerId), minimap = not geoMode })`, where `obj = runnerObject()`
    - then `hiding.tick(clock)`
  - In practice as a cop, `runnerObject()` returns the AI runner and `key` is nil.
  - `endRound` calls `hiding.clear()`. `M.onExtensionUnloaded` calls `hiding.unload()` before the module cache is dropped.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_hiding.lua`:** stub globals:
    - `MPVehicleGE.getVehicles` returning a table with key `"2-0"`
    - `activeVehiclesIterator`, iterating ids 1, 2, 3
    - `ui_apps_minimap_vehicles = { drawOtherVehicles = function() collect ids via activeVehiclesIterator end }`
  - **Hiding tests:**
    - **The name tag:** `set({ vid = 2, key = "2-0", minimap = true })` then `tick(0)`:
      - `hideNametag == true`
      - the wrapped draw sees ids 1 and 3 only
      - afterwards the global `activeVehiclesIterator` is the original again
    - **The original throws:** the global is still restored, and the error doesn't escape.
    - **Pass-through:** `set(nil)` → the draw sees 1, 2 and 3.
    - **`minimap = false`:** the name tag is hidden, and the draw sees all three.
    - **`clear()`:** `hideNametag == nil`.
    - **Re-assert:** BeamMP rebuilding the vehicle table (a new table without the flag) gets `hideNametag` back within one second of ticks.
    - **The lazy wrap:**
      - with no `ui_apps_minimap_vehicles` at first, the first `tick` wraps nothing
      - once it appears, the next tick wraps it
      - after the extension is replaced by a fresh table, the next tick wraps the new one
    - **`unload()`:** restores the original, and leaves a foreign replacement in place.
  - **`tests/test_client.lua`:**
    - **Cop:** after `cnr_runnerShown { shown = false }`, `env.mpVehicles["2-0"].hideNametag == true` (set up the round-car keys with `cnr_roundCars { keys = { "2-0" } }` and a vehicle entry). After `{ shown = true }` it is nil again, and after `cnr_roundEnd` it is nil.
    - **Runner:** with `role = "runner"`, nothing is ever hidden.

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run the tests**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: all pass except files Task 7 owns.

- [ ] **Step 5: Commit**
  `git commit -am "feat: hide the runner's name tag and minimap marker from cops unless spotted"`

### Task 7: Panel, How to Play and docs

**Files:**
- Modify:
  - `client/ui/modules/apps/CopsAndRobbersPanel/settings.js`
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
  - `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`helpBlock`)
  - `docs/FEATURES.md`, `README.md`, `docs/DEPENDENCIES.md`
- Test: `tests/test_hud.lua`, `tests/test_client.lua` (the rules fixtures at `test_hud.lua:6` and `test_client.lua:1249`)

**Interfaces:**
- **`helpBlock`:**
  - drops `lastSeenOff`
  - adds `r.heliOn = rules.helicopter == true` and `r.refuelNever = (tonumber(rules.helicopterRefuelSeconds) or 0) <= 0`
- **The panel:**
  - Remove the "Last seen every" row.
  - Add a group `{ title: "Helicopter", items: [...] }` after "Cops":
    - `helicopter` (bool, "Police helicopter", help: "Tracks the runner in the open; grounded in storm, fog and snow")
    - `helicopterArrivalSeconds` ("Arrives after", s, step 15, min 0, duration, `zeroText: "at release"`, `when: v => v("helicopter")`)
    - `helicopterUpSeconds` ("Time up", s, step 15, min 15, duration, `when`)
    - `helicopterRefuelSeconds` ("Refuel", s, step 15, min 0, duration, `zeroText: "stays up"`, `when`)
    - each with a one-line help
  - `shown()` returns `item.zeroText` when it is set and the value is 0, checked before `offAtZero`.
- **How to Play:**
  - **Runner tab:**
    - The sight line keeps SPOTTED / HIDDEN and drops the "every N s" sentence.
    - A new helicopter line (when `heliOn`): it arrives after the arrival time, flies for the time up, refuels for the refuel time (or stays up), tracks you in the open, loses you under tunnels, bridges and roofs, and stays grounded in storm, fog and snow.
    - A hiding line: cops only see you on the minimap and by name tag while you're spotted.
    - The "Nearest cop" line always shows.
  - **Cop tab:** mirror that. With sight Off: "Sight is off: you see the runner on the minimap all round."
  - Use the existing `sec()` and `duration()` helpers for values.
- **Docs:**
  - The config tables in `README.md` and `docs/FEATURES.md`: drop `lastSeenIntervalSeconds`, and add the four keys with their defaults.
  - A short helicopter and hiding section in `FEATURES.md`.
  - `docs/DEPENDENCIES.md` gets entries for:
    - wrapping the game's `ui_apps_minimap_vehicles.drawOtherVehicles` and swapping the global `activeVehiclesIterator`
    - BeamMP's `hideNametag` on the runner's key
    - the `SpotLight` object
    - the `onDrawOnMinimap` hook with `ui_apps_minimap_utils.simpleCircle`

- [ ] **Step 1: Update the fixtures and write the failing tests**
  - Replace `lastSeenIntervalSeconds = 30` in the two rules fixtures with `helicopter = true, helicopterArrivalSeconds = 60, helicopterUpSeconds = 120, helicopterRefuelSeconds = 90`.
  - `test_hud.lua:278` asserts `heliOn == false` with `helicopter = false`, and `refuelNever == true` with refuel 0.

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the `helpBlock` assertions fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run all checks**
  Run: `make test && make vuecheck && grep -rn lastSeenInterval server client tests README.md docs/FEATURES.md`. Expected:
  - `make test` ends with `0 failed`
  - vuecheck is clean
  - grep prints nothing

- [ ] **Step 5: Commit**
  `git commit -am "docs: helicopter and hiding in the panel, How to Play and docs"`
