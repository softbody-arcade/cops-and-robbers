# Helicopter Line of Sight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the helicopter flies, cover is decided by whether the helicopter can see the runner's car (rays from the helicopter to the car), and every game flies the same helicopter (same side and directions) from a seed the server sends.

**Architecture:**
- **Server:** `cnr/helicopter.lua` picks a new seed each time the helicopter goes up and puts it in its status. `round.lua` and `main.lua` carry it in the existing `cnr_heli` message; the round setup's `heli` already carries the status.
- **Flight:** `heliFlight.lua` gets a small seeded generator. `heli.lua` draws each new flight's side and bearings from it, and the fly-away heading too.
- **Cover:** `shelter.lua` gets a pure line-of-sight check. `heli.coverTick` uses it while a flight exists, and the roof check otherwise.

**Tech Stack:** Lua (server: Lua 5.3; client: LuaJIT in game, Lua 5.x in tests). `make test`.

**Spec:** `docs/superpowers/specs/2026-11-17-visible-searchlight-beam-design.md`, section "Line of sight". It is the binding source for every rule and number.

## Global Constraints

- **Code style:** no code comments, no emojis. Lua module table `M`, camelCase locals. Follow the surrounding files.
- **No version bump** on the branch.
- **No new network message:** the seed rides in the existing `cnr_heli` status and the round setup's `heli`.
- **Lua compatibility:**
  - Client pure modules do maths per component and build vectors with `vec3(x, y, z)`; the test `vec3` stub has no operators.
  - No `goto`, `//` or bit operators (LuaJIT).
- **The generator must give the same numbers in LuaJIT and Lua 5.x:**
  - Use Park–Miller: `x = x * 16807 % 2147483647`, returning `x / 2147483647`.
  - It is exact in doubles.
- **Seeds:** integers in [1, 2147483646].
- **Cover numbers:**
  - every `COVER_INTERVAL = 0.25` s
  - points: the middle at `COVER_HEIGHT = 1.5` m above the car's position, plus 2 m ahead and 2 m behind it along the car's horizontal direction, at the same height
  - a point is seen when the ray reaches within 0.5 m of it
  - covered when no point is seen
- **Unchanged:** the two-reading smoothing (`shelter.step`, `CHECKS_TO_SWITCH = 2`), the server's `LOSE_SECONDS = 2`, instant re-acquire, the light cut while searching, the beam's own blocking ray, the flight numbers.

## Review Focus

1. **A game joining mid-round** (its first phase is "tracking", so it calls `at`) takes the same side and fly-away heading as a game that saw the arrival (`arrive`) with the same seed. Pinned in Task 2.
2. **A car with no horizontal direction** (standing on its nose, or a zero direction vector) gives only the middle point, with no NaN. Pinned in Task 3.
3. **The helicopter at or within 0.5 m of a point** counts that point as seen, with no division by zero. Pinned in Task 3.
4. **`castRayStatic` returning nil, the full distance, or more than it** counts the point as seen; only a hit shorter than the distance − 0.5 m blocks it. Pinned in Task 3.
5. **A status without a seed** (an older server, or a status sent before this change) falls back to the existing random with no error. A short refuel resumes the flight and ignores the new seed. Pinned in Task 2.

---

### Task 1: The server sends a seed per flight

**Files:**
- Modify:
  - `server/CopsAndRobbers/cnr/helicopter.lua`
  - `server/CopsAndRobbers/cnr/round.lua:383`
  - `server/CopsAndRobbers/main.lua:628`
- Test: `tests/test_helicopter.lua`, `tests/test_main.lua`

**Interfaces:**
- **Produces:** `helicopter.status(h, now)` includes `seed` (an integer in [1, 2147483646]) while the phase is "tracking" or "searching", and no `seed` otherwise.
  - A new seed is picked each time the helicopter enters the up phase (`enterUp`).
  - `helicopter.new(cfg, weather, now, random)` takes an optional `random` (a function like `math.random(lo, hi)`), defaulting to `math.random`. Tests pass a fixed one.
- **`cnr_heli`** carries `seed` next to `phase`, `seconds` and `reason`. The round setup's `heli` already is the status table.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_helicopter.lua`, "each flight gets its own seed, sent only while up":**
    - arriving has no `seed`
    - at 70 the status's `seed` is an integer in range
    - refuelling has no `seed`
    - after the refuel the up status has a seed, and with a stub `random` returning 11 and then 22, the two flights' seeds are 11 and 22
    - the seed stays the same while tracking turns to searching and back
  - **`tests/test_main.lua`, "cnr_heli carries the seed while up":** with `helicopterArrivalSeconds: 0` and `weather: clear`, after `runToChase`, the last `cnr_heli` decodes with a numeric `seed`, and the round setup sent to a joining cop has `heli.seed` (follow the existing "a rejoining cop gets runnerShown and heli in setup" test).
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_helicopter.lua` and `lua tests/run.lua tests/test_main.lua`. Expected: the new tests fail on a nil `seed`.
- [ ] **Step 3: Implement** as in Interfaces. `round.lua:383` copies `s.seed` into the effect, and `main.lua:628` sends `seed = e.seed`.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit** the changed files explicitly. Message: "feat: the server sends a seed for each helicopter flight"

### Task 2: Every game flies the same helicopter

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/heliFlight.lua`
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua`
- Test: `tests/test_heli_flight.lua`, `tests/test_heli_client.lua`

**Interfaces:**
- **Consumes:** the status `seed` from Task 1, arriving in `heli.set(state, d, clock)` as `d.seed`.
- **Produces:**
  - **`heliFlight.seeded(seed) -> function`:** returns a generator of floats in [0, 1), Park–Miller as in Global Constraints. A seed outside [1, 2147483646] is first brought into range with `seed % 2147483646 + 1` on its integer part.
  - **`heliFlight.arrive(carPos, random, carVel)`:** now draws the side first, then the heading, the same order as `at`, so the same generator gives `arrive` and `at` the same side.
  - **`heli.set`** stores `state.seed = tonumber(d.seed)`, or nil.
  - **`heli.lua` `fly()`:**
    - When it creates a flight (`arrive` or `at`), it uses `state.flightRandom = state.seed and flight.seeded(state.seed) or random`.
    - `leave` uses `state.flightRandom or random`.
    - `dropFlight` clears `state.flightRandom`. `resume` keeps the existing flight and generator, and ignores a new seed.
    - The operator sway keeps using `state.random or math.random`.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_heli_flight.lua`:**
    - **"seeded generators repeat":**
      - two generators from seed 42 give the same first 10 numbers, all in [0, 1)
      - seed 43 differs in its first number
      - seed 0 and seed 2147483647 give numbers in [0, 1) and no NaN
    - **"arrive and at draw the same side from the same generator":** for seeds 1 to 20, `arrive(car, seeded(s))` and `at(car, vec3(0, 0, 0), seeded(s))` give the same `side`.
  - **`tests/test_heli_client.lua`:**
    - **"two games with the same seed fly the same helicopter":**
      - two `heli.new()` states, both set to "arriving", then "tracking" with `seed = 777`, with different `state.random` stubs
      - after one tick each, the flights' `side` and `pos` match to 1e-9
      - after "refuelling", the `leaving` points match to 1e-9
    - **"a game joining mid-round takes the same side as one that saw the arrival":** state A goes "arriving" → "tracking" with seed 777; state B's first status is "tracking" with seed 777. Assert:
      - the same `side`
      - after both get "refuelling" on the same car position, the same fly-away turn: each `leaving` bearing from the car minus that flight's own bearing from the car just before `leave` is equal for A and B, to 1e-9 (their positions differ, since A flies in from 300 m and B starts on its target point, so the bearings themselves differ)
    - **"without a seed the flight uses the existing random":** a status with no `seed` creates a flight with no error, and `state.flightRandom` is `state.random`.
    - **"a short refuel resumes and ignores the new seed":** "tracking" with seed 5, then "refuelling", then "tracking" with seed 6 within 7 s. The same flight table and the same `side`, and `state.flightRandom` unchanged.
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_heli_flight.lua` and `lua tests/run.lua tests/test_heli_client.lua`.
- [ ] **Step 3: Implement** as in Interfaces. Adjust any existing test that depended on `arrive` drawing the heading first.
- [ ] **Step 4: Run `make test` twice.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: every game flies the same helicopter from the server's seed"

### Task 3: Cover is what the helicopter sees

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/shelter.lua`
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua` (`coverTick`)
  - `client/lua/ge/extensions/copsAndRobbers.lua:796-801` (`updateHeli`)
- Docs:
  - `docs/FEATURES.md:106` (Cover) and `:109` (the searchlight is blocked)
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue:67-68` and `:125-126`
  - `docs/DEPENDENCIES.md` (the `castRayStatic` line in the beam entry gets a cover line)
  - `README.md` wherever it describes cover (grep "cover")
- Test: `tests/test_shelter.lua`, `tests/test_heli_client.lua`, `tests/test_client.lua`

**Interfaces:**
- **Consumes:** `state.flight.pos` (Task 2 and earlier).
- **Produces:**
  - **`shelter.inSight(from, carPos, dirX, dirY, castRay) -> boolean`:** pure.
    - Points: the middle `(carPos.x, carPos.y, carPos.z + 1.5)`, plus ±2 m along the normalized horizontal `(dirX, dirY)` at the same height. With a horizontal length below 1e-6, only the middle.
    - For each point, d = the distance from `from`:
      - d ≤ 0.5 → seen
      - otherwise `hit = tonumber(castRay(from, unit direction, d))`, and the point is seen unless `hit` and `hit < d - 0.5`
    - It returns true at the first seen point.
  - **`heli.coverTick(state, clock, obj, castUp, castRay)`:** when `state.flight` and `castRay` exist, covered = `not shelter.inSight(state.flight.pos, obj:getPosition(), dir.x, dir.y, castRay)`, with `dir = obj:getDirectionVector()` (nil-safe: no direction → 0, 0). Otherwise the roof check as today. Spacing, the first report and the smoothing are unchanged.
  - **`copsAndRobbers.lua`:** passes `castRayStatic` as `castRay`.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_shelter.lua`:**
    - **"the helicopter sees the car when one ray gets through":** a `castRay` stub that blocks the rays to the middle and the front (returns 5 for a distance of 50) and lets the back through (returns nil) → true.
    - **"covered only when every ray is blocked":** all blocked → false.
    - **"a hit at the point itself does not block":** the stub returns d − 0.3 → true.
    - **"no direction gives only the middle point":** dirX = dirY = 0. The stub records its calls: one call, no NaN in its direction.
    - **"the helicopter at the point sees it":** `from` equals the middle point → true without calling `castRay`.
    - **"a nil, full or longer return counts as seen":** returns nil, d, and d + 10 → true each.
    - **"the points sit 1.5 m up and 2 m ahead and behind":** record the target points the rays aim at (from + dir × d) for a car at (10, 20, 5) heading +y: (10, 20, 6.5), (10, 22, 6.5), (10, 18, 6.5) to 1e-6.
  - **`tests/test_heli_client.lua`:**
    - **"with a helicopter, cover comes from its line of sight":**
      - set "tracking" and tick the light once, so the flight exists
      - `coverTick` with an open roof (`open`) and an all-blocking `castRay` reports true after two checks
      - with `castRay` letting rays through and `roofAll`, it reports false after two checks
    - **"without a helicopter the roof check decides":** no flight, a `castRay` that would block everything, `open` roof → reports false.
  - **`tests/test_client.lua`:** **"the runner's game reports cover from the helicopter's view":**
    - a runner round in the chase with the helicopter "tracking", and the game's `castRayStatic` stubbed to block every ray that doesn't point straight up
    - after enough ticks, the last `cnr_cover` sent is `covered = true`
    - with the stub letting rays through, it's `covered = false`
    - follow the existing cover tests in that file
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement** as in Interfaces. Update the docs:
  - Cover: the runner is lost after 2 s out of the helicopter's sight. That's behind buildings and hills, in tunnels and under covers, and while it flies in low. Before the helicopter arrives, the roof check decides.
  - How to Play: the runner tab says the helicopter must see you, and that buildings, hills, tunnels and garages hide you. The cop tab says the same from the cops' side.
  - DEPENDENCIES: `castRayStatic` from the helicopter to three points on the car, every 0.25 s.
- [ ] **Step 4: Run `make test` twice and `make vuecheck`.** Expected: `0 failed`, and vuecheck clean.
- [ ] **Step 5: Commit.** Message: "feat: cover is what the helicopter can see"
