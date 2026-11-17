# Visible Searchlight Beam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The helicopter really flies (follows, trails, circles, flies in and away), its searchlight hangs from it, and a soft beam in the air and a glare at the source show the light, faint in clear weather and stronger in cloud and rain.

**Architecture:**
- **Flight:** a pure module `copsAndRobbers/heliFlight.lua` simulates the helicopter on each game.
- **Searchlight:** `copsAndRobbers/heli.lua` places the light at the helicopter, keeps the brightness effects, and aims with relative velocity.
- **Beam:** a pure module `copsAndRobbers/beam.lua` works out the beam's quads. `heli.lua` draws them with the game's debug drawer (in their own pcall), ends them at the first static hit, and sets the flare.
- **Setting:** a player setting turns the beam and glare off.

**Tech Stack:**
- Lua: the BeamNG GE client extension (LuaJIT in game; the tests run on Lua 5.x)
- Vue 3: the HUD settings card
- tests: `make test` (Lua binary `lua`), `make vuecheck`

**Spec:** `docs/superpowers/specs/2026-11-17-visible-searchlight-beam-design.md`. It is the binding source for every rule and number. This plan names the files, interfaces and tests.

## Global Constraints

- **Code style:**
  - No code comments, no emojis.
  - Lua: module table `M`, camelCase locals. Follow the surrounding files.
- **No version bump** on the branch (2.9.1 is set on main after the merge).
- **Lua compatibility:**
  - In `heliFlight.lua` and `beam.lua`, do every maths step per component and build results with `vec3(x, y, z)`; the test stub `vec3` (`tests/env_stubs.lua`) has no operators.
  - Use `math.atan2` for bearings. The new tests define `math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end`, as `tests/client_stubs.lua:37` does.
- **Flight constants** (in `heliFlight.lua` only; `heli.lua` uses them from there):
  - `MAX_SPEED = 70`, `MAX_ACCEL = 8`, `FOLLOW_GAIN = 0.4`
  - `SLOW_SPEED = 5`, `FAST_SPEED = 7`
  - `FOLLOW_BACK = 25`, `FOLLOW_SIDE = 15`, `HELI_HEIGHT = 50`
  - `ORBIT_RADIUS = 30`, `ORBIT_PERIOD = 40`
  - `APPROACH_DISTANCE = 300`, `APPROACH_HEIGHT = 60`, `DEPART_DISTANCE = 400`, `DEPART_HEIGHT = 80`, `DEPART_HEADING_SPREAD = 60` (degrees)
  - `APPROACH_SECONDS = 8`, `DEPART_SECONDS = 8`, `DEPART_FADE_SECONDS = 3`
  - `JUMP_METERS = 30`, `MAX_STEP = 0.1`
- **Light:**
  - cone 8°/16°, brightness 80, cool white
  - range max(120, slant + 30), rounded and capped at 400; written on creation and when it differs by more than 5 m from the last written value
  - aim offsets: `AIM_SWEEP_OFFSET = 15`, `REFOUND_AIM_OFFSET = 8`, `DEPART_AIM_DRIFT = 60`
- **Beam** (`beam.lua`):
  - `STRENGTH = { clear = 0.06, cloudy = 0.12, rain = 0.2 }`, otherwise 0.06
  - `LAYERS = 5`, `SEGMENTS = 10`, `SIDES = 24`, `LAMP = 0.4`, `GROUND = 0.5`
  - `NEAR = 6`, `FAR = 18`, `HALF_ANGLE = 8`, `MAX_LENGTH_FACTOR = 2`
  - colour 217, 235, 255
  - one `drawQuadSolid` per quad in the camera-facing winding (≤ 1,200 calls), or both windings without a camera (≤ 2,400)
  - the occlusion ray every `RAY_INTERVAL = 0.25` s
- **Glare:** `flareType` `BNG_LightFlare_1`, `flareScale` = `fx.bright` (rewritten when it changes by > 0.05); `flareType ""` when the setting is off.
- **The 2.9.0 anti-goals still hold:**
  - no light left after the round, a cancel, leaving, a map change or unload
  - under cover the light is cut at once
  - by day there's no light or beam
  - a beam error never removes the light
- **No network messages are added.**

## Review Focus

1. **A BeamNG.Earth origin shift or a runner reset (a car jump over 30 m).** The helicopter keeps its offset from the car: no fly-back from kilometres away, and no beam that long. Tasks 1a and 1b pin this.
2. **A refuel of 0 to 8 s ends while the helicopter is still leaving.** It turns back from where it is: no teleport to 300 m out. Task 1b pins this.
3. **The helicopter is low or far out** (fly-in at 11° elevation, a car faster than 70 m/s). The beam ends on the ground plane, never as an upright disc, and there's no beam over a 400 m slant. Task 2 pins this.
4. **The camera is right next to a wide beam's wall, or the beam is vertical.** No sheet within 6 m, and no NaN. Task 2 pins this.
5. **The beam setting is toggled while the light is on, or the drawer errors.** The flare follows on the next frame, the beam stops, and the light stays. Tasks 2 and 3 pin this.

---

### Task 1a: The flight module

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heliFlight.lua`
- Test: create `tests/test_heli_flight.lua`

**Interfaces** (positions and velocities are tables with x, y, z; results are built with `vec3`):
- **`M.arrive(carPos, random) -> f`:**
  - `APPROACH_DISTANCE` out in a random heading, `APPROACH_HEIGHT` above the car
  - velocity 0, `side` ±1 at random
- **`M.at(carPos, carVel, random) -> f`:** placed on its target point (follow or circle by the car's speed), velocity = `carVel`, `side` at random.
- **`M.leave(f, carPos, random)`:** sets `f.leaving` to a world point `DEPART_DISTANCE` from the car, `DEPART_HEIGHT` above it, with the heading = the helicopter's bearing from the car ± up to `DEPART_HEADING_SPREAD`.
- **`M.resume(f)`:** clears `f.leaving`; position and velocity are kept.
- **`M.step(f, carPos, carVel, dt)`:**
  - `dt` ≤ 0 does nothing; `dt` is clamped to `MAX_STEP`
  - a car jump over `JUMP_METERS` since `f.lastCar` shifts `f.pos` and `f.leaving` by the jump
  - mode with hysteresis: circle below `SLOW_SPEED`, follow above `FAST_SPEED`; entering the circle sets `f.orbit` to the current bearing
  - the circle advances `f.orbit` by ω × dt, with ω = 2π/`ORBIT_PERIOD` × `side`
  - wanted velocity = (`carVel` + the circle point's velocity relative to the car, while circling) + `FOLLOW_GAIN` × (target − pos), with only the gain term when leaving; length capped at `MAX_SPEED`
  - velocity moves towards the wanted one by at most `MAX_ACCEL` × dt; pos += vel × dt
- **`M.target(f, carPos, carVel) -> vec3`:**
  - pure, no side effects
  - follow: car − `FOLLOW_BACK` × the horizontal direction of travel + `FOLLOW_SIDE` × `side` × the left perpendicular + `HELI_HEIGHT` up
  - circle: car + `ORBIT_RADIUS` × (cos `f.orbit`, sin `f.orbit`) + `HELI_HEIGHT` up
  - leaving: `f.leaving`

- [ ] **Step 1: Write the failing tests** in `tests/test_heli_flight.lua`, with a seeded random and dt 0.05. Each assertion is the spec's Tests → Flight and Jumps:
  - **limits:** over 120 s of random car motion, |vel| ≤ 70 + 1e-6 and |Δvel| ≤ 8 × dt + 1e-6 on every step
  - **settle:** within 3 m of (−25, 15 × side, 50) from a car at a steady 30 m/s in +x, after 60 s
  - **stop then circle:** 30 m/s for 30 s, then the car stops. It overshoots (the horizontal distance goes below 25 m at some point). From 40 s after the stop, the horizontal distance stays within 30 ± 2, the height within 50 ± 2, and the bearing rate within 2π/40 ± 20% with the sign of `side`.
  - **fly-in:** `arrive`, car still; within 5 m of `M.target` at 20 s
  - **fly-away:** after `leave`, the distance from a still car grows every second and is above 200 m at 8 s, for 20 random seeds
  - **no jumps:** each step moves ≤ 70 × dt + 1e-6
  - **at:** starts on `M.target` with `vel == carVel`
  - **hysteresis:** a car at 6 m/s keeps whichever mode it was in
  - **jump shift:** after a 2 km car jump, the offset from the car is unchanged (1e-6)
  - **jump velocity:** car and helicopter both at 30 m/s in +x, then a 50 m car jump in +x; the helicopter's x velocity doesn't increase
  - **dt 0:** the state is unchanged, and nothing is NaN
- [ ] **Step 2: Run them to make sure they fail**
  Run: `lua tests/run.lua tests/test_heli_flight.lua`. Expected: they fail, because the module is missing.
- [ ] **Step 3: Implement** `heliFlight.lua` as in Interfaces.
- [ ] **Step 4: Run the tests**
  Run: `make test` twice. Expected: both runs end with `0 failed`.
- [ ] **Step 5: Commit**
  `git add` the two files explicitly. Message: "feat: a flight model for the police helicopter"

### Task 1b: The light hangs from the helicopter

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/heli.lua`
- Test: `tests/test_heli_client.lua`, and `tests/test_client.lua` where a test reads the light's position

**Interfaces:**
- **Consumes:** `heliFlight` (Task 1a).
- **`state.flight` lifecycle** in `tickLight`:
  - `arrive` when the phase becomes "tracking" or "searching" after "arriving" or "refuelling" and no flight exists
  - `resume` instead when a flight exists (short refuel)
  - `at` when this game first sees an up phase (`lightPhase` nil)
  - `leave` when the phase becomes "refuelling" after "tracking" or "searching"
  - dropped `DEPART_SECONDS` after leaving (after that frame's light update), on `clear`, and when the phase is "arriving", "grounded" or nil
  - `step` every tick while a flight exists, also by day and with no light
- **The car's velocity:**
  - `target:getVelocity()` when present, otherwise the position delta over the real frame time
  - kept when the frame time is ≤ 0
- **The light:**
  - at `state.flight.pos`, aiming at the aim point
  - `lightPose`, `HOVER_DRIFT`, `glide` and the position parts of approach and depart go
  - kept: the brightness effects (approach from the current `fx.bright` up to 1 over `APPROACH_SECONDS`; depart; fade; fadein; refound), `AIM_SWEEP_OFFSET` on a fresh fly-in, `REFOUND_AIM_OFFSET`, and the `DEPART_AIM_DRIFT` `extra` along the leave direction
- **`M.aimStep(aim, carPos, dt, clock, random, heliVel)`:** the lag kick uses the change in (car velocity − `heliVel`); `heliVel` nil means zero.
- **Range:** written on creation and by the 5 m rule, as in Global Constraints.
- **For Task 2:** expose `state.aimPos` and `state.lightPos`.
- **Tests:** `load()` in `test_heli_client.lua` clears `copsAndRobbers/heliFlight` from `package.loaded`, along with the modules it clears now.

- [ ] **Step 1: Update and write the tests** in `tests/test_heli_client.lua`. Decisions on the existing 2.9.0 tests:
  - **Keep, adapted to the flight:**
    - **:247 (fly-in aim sweep):** the light now starts at `state.flight.pos` about 300 m out. Assert the aim starts 15 ± 1 m off the car.
    - **:266 and :443 (fly-away):** replace "distance > 60 m after 3-4 s" with "the light follows `state.flight.pos`, which moves away, and the light is removed after 8 s". The flight is nil after that frame.
    - **:379 (refuel during a fly-in):** the helicopter position stays continuous (≤ 70 × dt per step).
    - **:401 (short refuel):** "refuelling" → "tracking" within 3 s calls `resume`, so there's no teleport, and the brightness ramps from the current value.
    - **:461 (night returning):** fades back in over 1 s at the helicopter's position.
  - **Delete:** the hover-drift and orbit position tests that assert `lightPose` or `HOVER_DRIFT`.
  - **New tests:**
    - the light sits at `state.flight.pos`
    - under cover the light is cut, the flight keeps stepping, and on the way out the light is back at once at full brightness with the aim 8 m off
    - by day: "arriving" → "tracking" → "refuelling" creates a flight and never a light; the flight is dropped after 8 s
    - joining mid-round (first `set` is "tracking"): `state.flight` starts on its target point, not 300 m out
    - a 2 km car jump keeps the light's offset from the car
    - range: 130 with the helicopter 100 m from the car, 120 at 60 m, and written on creation even when `state.lightRange` already holds the same value
    - aim: car and `heliVel` braking together 30 → 0 over 1 s keep the offset within `NUDGE_RADIUS` + 0.3, while the car alone gives > 1 m
    - a fake vehicle with `getVelocity` is used when present
    - `clear` mid-approach and mid-depart removes the light and the flight at once
- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run the tests**
  Run: `make test` twice. Expected: both runs end with `0 failed`.
- [ ] **Step 5: Commit**
  `git add` the files explicitly. Message: "feat: the searchlight hangs from the flying helicopter"

### Task 2: The beam in the air and the glare

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/beam.lua`
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua`
  - `client/lua/ge/extensions/copsAndRobbers.lua` (the `updateHeli` call)
- Test: create `tests/test_beam.lua`, modify `tests/test_heli_client.lua`

**Interfaces:**
- **`beam.strength(weather, bright) -> number`.**
- **`beam.quads(lightPos, aimPos, strength, hitDist, camPos) -> list`:**
  - Entries are `{ a, b, c, d, alpha, both }`.
  - Geometry, per the spec's "The beam":
    - side lines from the lamp ring follow the cone and end on the plane `z = aimPos.z`, capped at `MAX_LENGTH_FACTOR` × the axis length
    - when `hitDist` < the axis length, every side line is scaled by `hitDist` / the axis length
    - `LAYERS` × `SEGMENTS` × `SIDES` quads
    - the x helper basis when the axis is nearly vertical
  - Alpha per quad: round(255 × strength × (1 − (1 − `GROUND`) × u) × near / `LAYERS`), where:
    - u is the quad's mid position along its side line, 0 to 1
    - near = clamp((|quad centre − camPos| − `NEAR`) / (`FAR` − `NEAR`), 0, 1), or 1 without a camera
  - Quads with alpha < 1 are left out.
  - `both` is true without a camera. With a camera the winding is chosen so the quad faces the camera (one dot product), and `a..d` are in that order.
  - A zero-length axis gives an empty list.
- **`beam.draw(list, drawQuad, colorFn) -> calls`:**
  - It caches `colorFn(217, 235, 255, alpha)` per alpha within the call.
  - It calls `drawQuad(a, b, c, d, clr)` once per quad, and again reversed when `both`.
- **`heli.lua`:**
  - `M.lightTick(state, target, night, clock, opts)`, with `opts = { weather, beam }` (nil `opts` means beam on).
  - The occlusion ray: every `RAY_INTERVAL`, `castRayStatic(lightPos, dir, axisLen)` sets `state.beamHit`, or nil when there's no hit.
  - After the light is placed, when `opts.beam ~= false` and `state.light`, `debugDrawer`, `color` and `core_camera` exist, the slant is ≤ 400 and `state.beamFailed` isn't set, it runs `pcall(beam.draw, beam.quads(...), function(a, b, c, d, clr) debugDrawer:drawQuadSolid(a, b, c, d, clr) end, color)`. An error sets `state.beamFailed`; the light stays.
  - Flare: on creation, and when `opts.beam` changes, `flareType` (`BNG_LightFlare_1` or ""); `flareScale` follows `fx.bright` (> 0.05 change). pcall-guarded.
- **`copsAndRobbers.lua`:** `updateHeli` passes `{ weather = traffic.weather(), beam = prefs.beam ~= false }`.
- **Tests:** `load()` also clears `copsAndRobbers/beam`.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_beam.lua`**, at strength 0.2 unless stated:
    - **strength:** per weather (clear, cloudy, rain, nil, "storm"), scaled by bright 0.5, with −1 and 2 clamped
    - **call counts:** 1,200 calls with a camera 100 m to the side of the axis midpoint; 2,400 without
    - **vertical beam:** without a camera, draws 2,400 calls with finite vertices only
    - **far ring:** for a 60° beam, every far-ring vertex has z = `aimPos.z` ± 1e-6
    - **low beam:** at 11° elevation, no vertex lies beyond 2 × the axis length from the light
    - **near camera:** with the camera at the aim point, no drawn quad has a vertex within 6 m of it
    - **occlusion:** `hitDist` = half the axis puts no vertex further than half the axis + 1e-6 from the light
    - **nothing:** strength 0 gives an empty list; light == aim gives an empty list without error
    - **colours:** at most 11 distinct `colorFn` calls in one `draw`
  - **`tests/test_heli_client.lua`**, with `_G.debugDrawer` (counting `drawQuadSolid`), `_G.color`, `_G.core_camera` and `_G.castRayStatic` stubbed and restored:
    - **on:** at night while tracking, quads are drawn and `fields.flareType == "BNG_LightFlare_1"`
    - **setting off:** `opts.beam` false draws no quads and sets `flareType == ""`; toggling back sets it again on the next tick
    - **nothing drawn:** by day, with no light, or at a slant over 400 m
    - **drawer error:** `drawQuadSolid` erroring sets `state.beamFailed`, and the light stays
    - **flare scale:** `flareScale` follows `fx.bright` during the fly-in
- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run the tests**
  Run: `make test` twice. Expected: both runs end with `0 failed`.
- [ ] **Step 5: Commit**
  `git add` the files explicitly. Message: "feat: a soft searchlight beam in the air and a glare at the light"

### Task 3: The player setting and the docs

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/playerSettings.lua`
  - `client/lua/ge/extensions/copsAndRobbers/hud.lua` (the settings payload, around line 237)
  - `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue`
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
  - `README.md` (line 52)
  - `docs/FEATURES.md` (the searchlight line, around 109)
  - `docs/DEPENDENCIES.md` (the SpotLight entry, around 103)
  - the 2.9.0 spec's searchlight lines
- Test: `tests/test_player_settings.lua`, `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- **`playerSettings.lua`:** `beam` boolean, default true.
- **`hud.lua`:** `beam = prefs.beam ~= false` in the settings payload.
- **`HudSettings.vue`:** a switch row after the headlights row, with the same markup.
  - name "Searchlight beam"
  - desc "The helicopter's beam in the air; off helps the frame rate"
  - it emits `setting` `beam`
- **How to Play:** append "You can turn the beam in the air off in your settings." to the "Police helicopter" items (runner tab around lines 61-66, cop tab around 118-123).
- **README:** line 52 says three switches and describes Searchlight beam (on by default; off removes the beam in the air and the glare, not the light).
- **FEATURES:**
  - the searchlight line: the helicopter flies (trails, swings, circles a stopped car, flies in and away)
  - the beam, its strength by weather, the glare, the setting
- **DEPENDENCIES:**
  - the SpotLight entry: the light sits at the flying helicopter, `range` is updated, and `flareType` / `flareScale` are set
  - new entries: `debugDrawer:drawQuadSolid` with `color()`, `core_camera.getPosition()`, the vehicle's `getVelocity()`, `castRayStatic` for the beam's blocking, and the `BNG_LightFlare_1` datablock (game `art/datablocks/lights.datablocks.json`)
- **The 2.9.0 spec:** its searchlight lines point to the new spec for the flight and beam.

- [ ] **Step 1: Write the failing tests:**
  - `tests/test_player_settings.lua`:
    - `load(nil).beam == true`
    - `load({ beam = false }).beam == false`
    - `set(p, "beam", false)` returns true; `set(p, "beam", "no")` returns false
  - `tests/test_hud.lua`: the settings payload's `beam` is true by default and false when `prefs.beam` is false.
  - `tests/test_client.lua`: `M.ui({ action = "setting", key = "beam", value = false })` saves the setting, and on the next ticks while tracking at night (drawer stubbed) no quads are drawn and `flareType` is "".
- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run all checks**
  Run: `make test` (twice) and `make vuecheck`. Expected: `0 failed` both times, and vuecheck clean.
- [ ] **Step 5: Commit**
  `git add` the files explicitly. Message: "feat: a player setting for the searchlight beam; docs"
