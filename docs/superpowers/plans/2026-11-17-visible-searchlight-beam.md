# Visible Searchlight Beam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The helicopter really flies (follows, trails, circles, flies in and away), its searchlight hangs from it, and a soft beam in the air and a glare at the source show the light, faint in clear weather and stronger in cloud and rain.

**Architecture:**
- **Flight:** a pure flight module `copsAndRobbers/heliFlight.lua` simulates the helicopter on each game.
- **Searchlight:** `copsAndRobbers/heli.lua` places the light at the helicopter and keeps only brightness effects (fly-in ramp, fly-away fade, night fade, refound).
- **Aim:** the operator's lag kick comes from the change in relative velocity.
- **Beam:** a pure module `copsAndRobbers/beam.lua` works out the beam's triangles. `heli.lua` draws them with the game's debug drawer after placing the light, and sets the flare.
- **Setting:** a player setting turns the beam and glare off.

**Tech Stack:**
- Lua: the BeamNG GE client extension
- Vue 3: the HUD settings card
- tests: `make test` (Lua binary `lua`), `make vuecheck`

**Spec:** `docs/superpowers/specs/2026-11-17-visible-searchlight-beam-design.md`

## Global Constraints

- **Code style:**
  - No code comments, no emojis.
  - Lua: module table `M`, camelCase locals. Follow the surrounding files.
- **No version bump** on the branch: 2.9.1 is set on main after the merge.
- **Flight constants** (exact):
  - `MAX_SPEED = 70` (m/s), `MAX_ACCEL = 8` (m/s²), `FOLLOW_GAIN = 0.4` (1/s)
  - `SLOW_SPEED = 5` (m/s)
  - `FOLLOW_BACK = 25`, `FOLLOW_SIDE = 15`, `HELI_HEIGHT = 50` (m)
  - `ORBIT_RADIUS = 30` (m), `ORBIT_PERIOD = 40` (s)
  - `APPROACH_DISTANCE = 300`, `APPROACH_HEIGHT = 60`, `DEPART_DISTANCE = 400`, `DEPART_HEIGHT = 80` (m)
  - `APPROACH_SECONDS = 8`, `DEPART_SECONDS = 8`, `DEPART_FADE_SECONDS = 3` (s)
- **Light:**
  - cone 8°/16°, brightness 80, cool white
  - `range` = max(120, slant distance + 30), rewritten only when it changes by more than 5 m
- **Beam:**
  - `STRENGTH = { clear = 0.06, cloudy = 0.12, rain = 0.2 }`; any other weather, nil or Earth gives 0.06
  - `LAYERS = 5`, `SEGMENTS = 10`, `SIDES = 24`, `LAMP = 0.4` (m), `GROUND = 0.5` (strength factor at the ground end)
  - `NEAR = 6`, `FAR = 18` (m, the near-camera fade)
  - `HALF_ANGLE = 8` (degrees)
  - at most 4,800 triangles a frame
  - colour (0.85, 0.92, 1)
- **Glare:** `flareType` `BNG_LightFlare_1`, `flareScale` 1. It is cleared (`flareType ""`) when the beam setting is off.
- **The anti-goals of 2.9.0 still hold:**
  - no light left after the round, a cancel, leaving, a map change or unload
  - going under cover cuts the light at once
  - by day there's no light or beam
- **Each game simulates its own helicopter:** no network messages are added.

## Review Focus

1. **The runner resets or teleports.** A >30 m car jump must not fling the helicopter or the spot: the car velocity counts as 0 for that step. Task 1 pins this.
2. **A player joins mid-round while the helicopter is up.** The helicopter starts at its target point, with no fly-in and no light flash from 300 m. Task 1 pins this.
3. **The beam's ends coincide or the camera sits exactly on the axis.** No NaN and no triangles. Task 2 pins this.
4. **The beam setting is toggled while the light exists.** The flare is set or cleared on the next frame, and the beam stops drawing at once. Task 2 and Task 3 pin this.
5. **Refuel by day.** The flight is dropped after `DEPART_SECONDS` without ever creating a light. Task 1 pins this.

---

### Task 1: The helicopter flies; the light hangs from it

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heliFlight.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/heli.lua`
- Test:
  - Create `tests/test_heli_flight.lua`
  - Modify `tests/test_heli_client.lua`, and `tests/test_client.lua` where a test reads the light's position

**Interfaces:**
- **Produces** (`heliFlight.lua`; positions and velocities are `vec3`):
  - constants as in Global Constraints
  - `M.arrive(carPos, random) -> f`: `APPROACH_DISTANCE` out in a random heading, `APPROACH_HEIGHT` above the car, velocity 0, side ±1 at random.
  - `M.at(carPos, carVel, random) -> f`: placed at its target point with the car's velocity, side ±1 at random. Used when the helicopter is already up as this game first sees it (joining mid-round).
  - `M.leave(f, carPos, random)`: sets `f.leaving` to a world point `DEPART_DISTANCE` away from the car in a random heading, `DEPART_HEIGHT` above it.
  - `M.target(f, carPos, carVel, dt) -> vec3`:
    - if `f.leaving`, that point
    - else if the car's horizontal speed is above `SLOW_SPEED`: the car − `FOLLOW_BACK` × its horizontal direction of travel + `FOLLOW_SIDE` × `f.side` × the left-hand perpendicular + `HELI_HEIGHT` up
    - else a circle point: `f.orbit` is the angle, which starts at the helicopter's current bearing from the car when entering the slow mode and advances 2π/`ORBIT_PERIOD` per second; the point is `ORBIT_RADIUS` out, `HELI_HEIGHT` up
  - `M.step(f, carPos, carVel, dt)`:
    - wanted velocity = `carVel` (zero when leaving) + `FOLLOW_GAIN` × (target − pos), with its length capped at `MAX_SPEED`
    - the velocity moves towards the wanted one by at most `MAX_ACCEL` × dt
    - pos += vel × dt
    - `dt` is clamped to 0..0.1
- **Changes in `heli.lua`:**
  - `state.flight` lifecycle:
    - created with `arrive` when the phase becomes "tracking" or "searching" right after "arriving" or "refuelling"
    - created with `at` when this game first sees an up phase with no earlier phase (`lightPhase` nil)
    - `leave` when the phase becomes "refuelling" after "tracking" or "searching"
    - dropped `DEPART_SECONDS` after leaving, on `clear`, and whenever the phase is "arriving", "grounded" or nil
  - The flight steps every tick while it exists, also by day and with no light.
    - Car velocity comes from position deltas (`f.lastCar`). A jump over `JUMP_METERS` (30 m) counts as velocity 0 for that step.
  - The light sits at `state.flight.pos` and aims at the operator's aim point.
    - `lightPose`, `HOVER_DRIFT` and the position glides (`glide`, `startOff`, the approach and depart position maths) go.
    - The brightness effects stay:
      - "approach": 0 → 1 over `APPROACH_SECONDS`, when the light is created right after an arrive
      - "depart": full, then fading to 0 over the last `DEPART_FADE_SECONDS` of `DEPART_SECONDS`, then the light is removed
      - "fade": night ending, 1.5 s
      - "fadein": night returning, 1 s
      - refound: at once, full brightness, the aim starting 8 m off
    - Under cover the light is still cut at once, and the flight keeps going.
  - `M.aimStep(aim, carPos, dt, clock, random, heliVel)`: the lag kick uses the change in (car velocity − `heliVel`); `heliVel` nil means zero.
  - Range: `state.lightRange`, rewritten as specified.
  - Expose `state.aimPos` (the last aim point) for Task 2.

- [ ] **Step 1: Write the failing tests**
  - **`tests/test_heli_flight.lua`**, with a fixed `random`:
    - `"speed and acceleration stay within the limits"`: random car motion for 120 s at dt 0.05. Every step has |vel| ≤ 70 + 1e-6 and |Δvel| ≤ 8 × dt + 1e-6.
    - `"it settles behind and to the side of a steady car"`: the car at 30 m/s along +x for 60 s. The final offset from the car is within 3 m of (−25, 15 × side, 50).
    - `"a stopping car makes it overshoot, then circle"`: 30 m/s for 30 s, then stopped. The horizontal distance to the car goes below 25 m at some point, or the helicopter passes the car. After 60 s more its horizontal distance stays within 30 ± 3 m, and the bearing changes by about 2π/40 rad/s (±20%).
    - `"the fly-in reaches the target point"`: `arrive` at 300 m with the car still. Within 15 s the helicopter is within 5 m of its target point.
    - `"the fly-away moves off"`: after `leave`, the distance to the car grows, and after 8 s it's above 250 m.
    - `"no jumps"`: every step moves at most 70 × dt + 1e-6.
    - `"at() starts on the target point"`.
  - **`tests/test_heli_client.lua`** (update the 2.9.0 light tests to the flight):
    - At night, after "arriving" → "tracking", the light exists, sits at `state.flight.pos` and starts about 300 m out; its brightness rises over 8 s.
    - "tracking" → "searching" removes the light at once; `state.flight` still exists and keeps moving. "searching" → "tracking" re-creates the light at `state.flight.pos` at full brightness, with the aim 8 m off.
    - "tracking" → "refuelling" keeps the light 8 s, fading over the last 3 s, then removes it and drops the flight.
    - By day, "arriving" → "tracking" → "refuelling": the flight exists, no light is ever created, and the flight is dropped after 8 s.
    - Joining mid-round (first `set` is "tracking", `lightPhase` nil): `state.flight` starts at its target point, not 300 m out.
    - A 50 m car jump: the helicopter's velocity changes by at most 8 × dt that step.
    - Range: with the helicopter 100 m from the car, the light's `range` is 130; at 60 m it stays 120.
    - `aimStep` with car and helicopter both at a steady 30 m/s: no lag kick (the offset stays within nudge radius + tremor).
    - `clear` mid-approach and mid-depart removes the light and the flight at once (existing tests, adapted).

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run the tests**
  Run: `make test` twice. Expected: both runs end with `0 failed`.

- [ ] **Step 5: Commit**
  `git add` the files explicitly. Message: "feat: the police helicopter flies and the searchlight hangs from it"

### Task 2: The beam in the air and the glare

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/beam.lua`
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua`
  - `client/lua/ge/extensions/copsAndRobbers.lua` (the `updateHeli` call)
- Test: create `tests/test_beam.lua`, modify `tests/test_heli_client.lua`

**Interfaces:**
- **Consumes** (Task 1): `state.light`, `state.fx.bright`, `state.aimPos`, and the light position (`state.flight.pos`).
- **Produces** (`beam.lua`):
  - constants as in Global Constraints
  - `M.strength(weather, bright) -> number`: `STRENGTH[weather]` or 0.06, times `bright` clamped to 0..1.
  - `M.draw(lightPos, aimPos, strength, camPos, drawTri, colorFn) -> number`
    - It returns the triangles drawn.
    - It draws `LAYERS` nested cones from `lightPos` to `aimPos`. Layer j of `LAYERS` has radius (`LAMP` + (R − `LAMP`) × t) × j/`LAYERS`, where R = length × tan(`HALF_ANGLE`) at the far end and t is 0..1 along the axis.
    - The axis is cut into `SEGMENTS` lengths and the circle into `SIDES` sides. Each quad is drawn as two triangles in both windings.
    - Per segment the alpha is round(255 × strength × (1 − (1 − `GROUND`) × t_mid) × near / `LAYERS`). near = clamp((distance from `camPos` to the segment's axis midpoint − `NEAR`) / (`FAR` − `NEAR`), 0, 1), or 1 when `camPos` is nil.
    - Segments with alpha < 1 are skipped.
    - The colour is `colorFn(217, 235, 255, alpha)`.
    - A zero-length axis draws nothing.
- **`heli.lua` changes:**
  - `M.lightTick(state, target, night, clock, opts)`, with `opts = { weather = string|nil, beam = boolean }` (nil `opts` means beam on, weather nil).
  - After the light is placed, when `opts.beam ~= false`, `debugDrawer` exists and `state.light` exists: `beam.draw(lightPos, state.aimPos, beam.strength(opts.weather, state.fx.bright), core_camera and core_camera.getPosition(), function(a, b, c, clr) debugDrawer:drawTriSolid(a, b, c, clr) end, color)`.
  - Flare: when the light is created, and whenever `opts.beam` changes while a light exists, set `flareType` (`BNG_LightFlare_1`, or "" when off) and `flareScale` "1". pcall-guarded, like the other field writes.
- **`copsAndRobbers.lua`:** `updateHeli` passes `{ weather = traffic.weather(), beam = prefs.beam ~= false }`.

- [ ] **Step 1: Write the failing tests**
  - **`tests/test_beam.lua`**:
    - `strength`:
      - clear 0.06, cloudy 0.12, rain 0.2
      - nil and "storm" give 0.06
      - `bright` 0.5 halves it; −1 and 2 clamp
    - `draw` with a counting `drawTri` and a recording `colorFn`:
      - a 40 m beam with `camPos` nil draws exactly 5 × 10 × 24 × 4 = 4,800 triangles
      - every colour's alpha is ≤ round(255 × 0.2 / 5) at strength 0.2
      - a camera at the aim point skips the segments whose midpoints are within 6 m (fewer triangles than 4,800)
      - a camera 100 m away draws all 4,800
      - strength 0 draws 0
      - `lightPos == aimPos` draws 0 and doesn't error
      - the first segment's vertices lie within `LAMP` + ε of the light's axis point, and the last segment's within R + ε of `aimPos`
  - **`tests/test_heli_client.lua`**, with `_G.debugDrawer` counting `drawTriSolid`, `_G.color` and `_G.core_camera` stubbed and restored:
    - at night while tracking with `opts.beam` true, triangles are drawn and `fields.flareType == "BNG_LightFlare_1"`
    - with `opts.beam` false, no triangles and `flareType == ""`; toggling back sets it again on the next tick
    - by day or with no light, no triangles

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
  - `client/lua/ge/extensions/copsAndRobbers/hud.lua` (the settings payload)
  - `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue`
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
  - `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `README.md` (if it lists player settings)
  - the 2.9.0 spec's searchlight lines (`docs/superpowers/specs/2026-11-16-police-helicopter-design.md`): point to the new spec for the flight
- Test: `tests/test_player_settings.lua`, `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- **`playerSettings.lua`:** `beam` boolean, default true.
- **`hud.lua` settings payload:** `beam = prefs.beam ~= false`.
- **`HudSettings.vue`:** a switch row after the headlights row, with the same markup.
  - name "Searchlight beam"
  - desc "The helicopter's beam in the air; off helps the frame rate"
  - it emits `setting` `beam`
- **How to Play:** where the searchlight is described, add "You can turn the beam in the air off in your settings."
- **Docs:**
  - `FEATURES.md` searchlight: the flight (trails, swings, circles a stopped car, flies in and away), the beam strength by weather, the glare, and the setting.
  - `DEPENDENCIES.md`:
    - the debug drawer (`debugDrawer:drawTriSolid` with `color()`) and `core_camera.getPosition()`
    - the flare datablock `BNG_LightFlare_1` (game `art/datablocks/lights.datablocks.json`)
    - the SpotLight's `range` and `flareType`/`flareScale` fields

- [ ] **Step 1: Write the failing tests**
  - `tests/test_player_settings.lua`:
    - `ps.load(nil).beam == true`
    - `ps.load({ beam = false }).beam == false`
    - `ps.set(p, "beam", false)` returns true, and `ps.set(p, "beam", "no")` returns false
  - `tests/test_hud.lua`: the settings payload has `beam == true` by default and false when `prefs.beam` is false.
  - `tests/test_client.lua`: `M.ui({ action = "setting", key = "beam", value = false })` saves the setting, and while tracking at night (debug drawer stubbed) no beam triangles are drawn on the next ticks.

- [ ] **Step 2: Run them to make sure they fail**
  Run: `make test 2>&1 | grep -E 'FAIL|passed'`. Expected: the new tests fail.

- [ ] **Step 3: Implement** as in Interfaces.

- [ ] **Step 4: Run all checks**
  Run: `make test` (twice) and `make vuecheck`. Expected: `0 failed` both times, and vuecheck clean.

- [ ] **Step 5: Commit**
  `git add` the files explicitly. Message: "feat: a player setting for the searchlight beam; docs"
