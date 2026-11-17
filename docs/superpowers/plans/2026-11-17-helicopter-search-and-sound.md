# Helicopter Searching and Sound Implementation Plan (2.9.3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (2.9.3):**
- Searching becomes a real search. Every flight starts searching at a spot: where it was called in, where it last knew the runner was, or a tunnel exit ahead (turning around dodges it). The cops' sight guides it. It tracks only once it sees the runner itself, within 400 m.
- The searchlight stays on and sweeps while searching.
- Every game hears a rotor sound at the helicopter, with a "Helicopter sound" switch.
- 2.9.1 (the beam, the flight and line of sight) and 2.9.2 are merged and live; this branch starts from main.

**Architecture:**
- **Server:** `cnr/helicopter.lua` carries `guided` (a cop sees the runner) in its status, and `Round` counts the runner as covered until their game reports. The tracking rule itself doesn't change: every flight starts searching because the client counts the car as covered while it has no flight (Task 4).
- **Client, pure modules:**
  - `heliFlight.lua` gets a search mode (circle a spot, which moves with the runner while guided).
  - A new `tunnels.lua` finds tunnel exits on the game's road graph.
  - A new `heliSound.lua` runs the rotor emitter.
- **Client, `heli.lua`:** the spot lifecycle (reconciled every tick), sight-only cover, the flight's own protected step, the light's phase table, the sweep and the switch offset, the sound level.
- **`hud.lua`:** the refuel countdown shows while searching.
- **`copsAndRobbers.lua`:** wires the road graph, the roof check, the sound and the new setting.

**Tech Stack:** Lua (server: Lua 5.3; client: LuaJIT in game, Lua 5.x in tests), Vue 3. `make test`, `make vuecheck`, `make package`.

**Spec:** `docs/superpowers/specs/2026-11-17-visible-searchlight-beam-design.md`, sections "Line of sight", "Searching" and "Helicopter sound", and the phase table in "The light". They are the binding source for every rule and number.

## Global Constraints

- **Style:**
  - No code comments, no emojis.
  - Lua: module table `M`, camelCase locals. Follow the surrounding files.
- **No version bump** on the branch. **No new network message:** `guided` rides in the existing `cnr_heli` status and the round setup's `heli`.
- **Lua:**
  - In the pure client modules, do maths per component and build vectors with `vec3(x, y, z)` from numbers only (never `vec3(v)`); the test stub `vec3` takes three numbers and has no operators.
  - No `goto`, `//` or bit operators.
- **Search numbers:**
  - in `heliFlight.lua`: `SEARCH_RADIUS = 60`, `SEARCH_PERIOD = 40`; the height is the existing `HELI_HEIGHT = 50` above the spot
  - in `heli.lua`: `SWEEP_RADIUS = 150`, `SWEEP_PERIOD = 40`, `SWEEP_TURN = 8`, `SWEEP_RAY_HEIGHT = 100`, `SWEEP_RAY_LENGTH = 200`, `SWEEP_RAY_INTERVAL = 0.25`, `AIM_SWITCH_SECONDS = 0.5`, `SIGHT_RANGE = 400`, `TARGET_MISSING_SECONDS = 2`
- **Tunnel walk** (in `tunnels.lua`):
  - `MAX_LENGTH = 3000` m of road, `MAX_NODES = 200`, `MAX_ROAD_DISTANCE = 15`, `ROOF_HEIGHT = 1.5`
  - edge lengths from node positions (3D distance), never the graph's `len` (a routing cost with 10 km added on gated roads)
  - the pick is `exits[seed % #exits + 1]`, with the exits ordered by node id compared as strings, or the first exit without a seed
- **Sound** (in `heliSound.lua`):
  - `NAME = "cnr_heli_sound"`, `FILE = "/art/sound/cnr/heli_rotor.ogg"`
  - `REF_DISTANCE = 40`, `MAX_DISTANCE = 800`
  - `FADE_IN_SECONDS = 1`, `FADE_OUT_SECONDS = 1`, `MUFFLED = 0.5`, `MUFFLE_SECONDS = 0.5`, `RAY_INTERVAL = 0.25`, `VOLUME_STEP = 0.02`, `LEFTOVER_INTERVAL = 1`
  - made as `rain.lua:74-89` makes its sound: `createObject("SFXEmitter")`, `Sim.upcast` when `Sim` and `Sim.upcast` exist; the fields set with `setField`: `fileName`, `is3D` "1", `isLooping` "1", `referenceDistance`, `maxDistance`, `volume` "0"; then `canSave = false`, `registerObject(NAME)`; when `scenetree.findObject(NAME)` is nil, `delete()` and log; otherwise `scenetree.MissionGroup:addObject`, `setPosition`, `play()` (probe-verified)
  - always found with `scenetree.findObject(NAME)`; no object reference is kept between ticks
- **Kept:**
  - the server's tracking rule: `enterUp` sets `tracking = not covered`, `update` tracks whenever `covered` is false, and the 2 s loss
  - the 0.5 s client smoothing
  - the beam and its setting
  - the anti-goal that nothing is left after the round, a cancel, leaving, a map change or unload (light, emitter, flight)
- **Removed:**
  - the light cut while searching (`startRefound`, `REFOUND_AIM_OFFSET`)
  - the fly-in's aim offset (`AIM_SWEEP_OFFSET` and the fresh light's `offsetAim` in `startApproach`, with its helpers)
  - the roof check as a cover source, and `coverTick`'s `castUp` parameter (`shelter.roofed` stays for the rain and the tunnel walk)

## Review Focus

1. **A runner who is never seen** (a tunnel for the whole up phase). The helicopter stays "searching" all up phase and flies away on refuel with its light. It returns to the last known spot (the runner's position at that moment in a round where it never found them), not to the runner. Pinned in Task 4.
2. **Phase sequences the server really sends:** "arriving" → "searching"; a short refuel either way ("tracking" → "refuelling" → "searching", "searching" → "refuelling" → "tracking"); stale cover making a flight start "tracking". The spot is reconciled every tick, the light follows the phase table, and the fly-in keeps its 8 s ramp. Pinned in Tasks 4 and 5.
3. **Guided and lost in the same tick, guidance starting kilometres from the spot, or guidance ending inside a tunnel.** The spot is recomputed from that moment and never left at a stale live position; the circle and the sweep restart from the runner. Pinned in Task 4.
4. **A road graph that is missing, empty, cyclic, one node, a road over 15 m from the car, or a tunnel longer than 3 km.** `tunnels.exit` returns nil or an exit without looping, and the walk is bounded. An error in it falls back to the car. Pinned in Tasks 3 and 4.
5. **The aim switching target mid-sweep, the spiral turning back, a short refuel ending a fly-away, or the spot jumping 2 km** (a BeamNG.Earth origin shift). No jump of the aim point and no NaN; the spot and the last known position move with the car's jump. Pinned in Tasks 2, 4 and 5.
6. **Errors:** a flight error (no flight, covered, until the next valid status), a tunnel walk error (the car's position), a light error (the flight keeps going), a sound error (the emitter deleted). Each is logged once. Pinned in Tasks 4 and 6.
7. **The sound setting toggled mid-flight, a short refuel, a round end during the fly-away, a map change, a Lua reload, the runner's car missing on a cop's game.** No `cnr_heli_sound` is left, and the volume never jumps up. Pinned in Task 6.

---

### Task 1: The cops' guidance in the helicopter status; the runner covered until reported (server)

**Files:**
- Modify:
  - `server/CopsAndRobbers/cnr/helicopter.lua`
  - `server/CopsAndRobbers/cnr/round.lua` (`Round:clear` around line 84, the update call and the `heli` effect around line 381)
  - `server/CopsAndRobbers/main.lua` (the `cnr_heli` send, around line 628)
- Test: `tests/test_helicopter.lua`, `tests/test_round.lua`, `tests/test_main.lua`

**Interfaces:**
- **Already true, so not changed:** `enterUp` sets `tracking = not covered`, and `update` sets `tracking = true` whenever `covered` is false (`helicopter.lua:79-89`, `121-132`). "Every flight starts searching" comes from the client: without a flight the runner's game reports covered (Task 4), so the server enters each up phase "searching". Don't change `enterUp` or the tracking rule, and don't add tests that pass on today's code.
- **`helicopter.update(h, now, covered, guided)`:**
  - stores `h.guided = guided == true`
  - returns true when the phase name or the seed changed (as now), or when the phase is "up" after the update and `guided` differs from before it
- **`helicopter.status(h, now)`** includes `guided = true` only while the phase is "up" and `h.guided`; otherwise there is no `guided` field.
- **round.lua:**
  - the update passes `self.inSight` as `guided`
  - the `heli` effect gains `guided = s.guided`
  - the setup's `heli` is the whole status table, so it carries `guided` already
  - `Round:clear` (which `round.new` calls) sets `self.runnerCovered = true`. The runner's game always sends its first cover reading, which is "covered" while it has no flight (Task 4). So this only changes a game that never reports: it is no longer tracked at arrival.
- **main.lua:** the `cnr_heli` send adds `guided = e.guided`.
- **Timing:** `helicopter.update` runs before `sightTick` in `Round:tick`, so `guided` follows the cops' sight one server tick (0.25 s) late. That is fine; the tests allow for it.

- [ ] **Step 1: Write the failing tests.** Each one fails on today's code.
  - **`tests/test_helicopter.lua`:**
    - "guided is in the status only while up": `new(std(), "clear", 10)`; `update(h, 60, true, true)` → `status(h, 60).guided == nil` ("arriving"); `update(h, 70, true, true)` → phase "searching", `guided == true`; `update(h, 71, true, false)` → `guided == nil`; `update(h, 190, true, true)` → phase "refuelling", `guided == nil`.
    - "a change of guided is reported while up, and only then": `update(h, 70, true, false)` → true (the phase); `update(h, 71, true, true)` → true; `update(h, 72, true, true)` → false; `update(h, 73, true, false)` → true; `update(h, 190, true, false)` → true (the phase); `update(h, 191, true, true)` → false.
  - **`tests/test_round.lua`:**
    - "a new round counts the runner as covered until their game reports": `round.new(...).runnerCovered == true`, and again after `r:clear()`.
    - "a runner whose game never reports is not tracked at arrival": `started({helicopterArrivalSeconds=0})`, no `coverReport` and no sight report; ticks at 4 and 11 with `stillCars()`: the `heli` effect at 11 is "searching"; ticks from 12 to 20 with `farCars()` have no `live` effect.
    - "the heli effect carries guided while a cop sees the runner": `chasing({helicopterArrivalSeconds=0})` with `farCars()` (cop 2 at 300 m); `sightReport(12, 2, true)`; ticks at 12 and 12.25: a `heli` effect with `guided == true` by the second tick; `sightReport(13, 2, false)`; ticks every 0.25 s from 13 to 15: a later `heli` effect without `guided` (after the 1.5 s `sightGraceSeconds`, one tick late).
  - **`tests/test_main.lua`:** "cnr_heli carries guided when a cop sees the runner": boot with `helicopterArrivalSeconds` 0 and clear weather, `runToChase`, then `env.positions[2] = 300`, `cnr_sight` from 2 with seen true, and two `cnr_tick`s 0.25 s apart: the last `cnr_heli` decodes with `guided == true`. Then seen false and `cnr_tick`s past the 1.5 s grace plus one: the last `cnr_heli` has no `guided`.
  - **Existing tests that relied on `runnerCovered` starting false** (found by flipping the default; 11 fail). Restore today's start for them with a cover report of `false` from the runner in the head start, before the helicopter goes up: `coverReport(5, 1, false)` after the tick at 4, in the `chasing` helper and in the tests that call `started` directly (in `test_main`, `cnr_cover` from 1 with `{"covered":false}` after `env.go()`). Keep what each test checks:
    - `tests/test_round.lua`: "no last seen when sight is lost while the helicopter tracks", "no last seen when the helicopter loses the runner while a cop sees them", "a bridge pass under 2 s keeps the helicopter on the runner, 2 s of cover loses them once", "the helicopter alone: each loss sends one last seen and hides the runner, tracking again shows them", "the helicopter alone sends live updates to every cop with a route", "heli effects follow phase changes", "runnerShown hides the runner from the head start and shows them while tracked", "setup carries runnerShown and the helicopter status"
    - "cover only counts from the runner's game during the chase": flip it. Reports of `false` before the chase and from a cop leave `runnerCovered == true`; the runner's `false` sets it false and `true` sets it back. The same for the practice part (the AI runner's report is ignored, the issuer's counts).
    - `tests/test_main.lua`: "heli phases reach every player" (the `false` report before the helicopter goes up) and "cnr_cover from the runner reaches the round" (the `false` report, so a `cnr_heli` "tracking" comes first; then `true` gives "searching")
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_helicopter.lua`, `lua tests/run.lua tests/test_round.lua` and `lua tests/run.lua tests/test_main.lua`. The new tests fail; the adapted ones pass.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: the helicopter status carries the cops' guidance; the runner counts as covered until reported"

### Task 2: The flight's search mode

**Files:** Modify `client/lua/ge/extensions/copsAndRobbers/heliFlight.lua`. Test: `tests/test_heli_flight.lua`.

**Interfaces:**
- **`M.arrive(carPos, random, carVel, spot)`:**
  - without `spot`: as now
  - with `spot`: the fly-in starts `APPROACH_DISTANCE` out from the spot at the drawn heading, `APPROACH_HEIGHT` above the spot
  - `f.lastCar` is always the car, so the first `step` doesn't read the spot's distance as a car jump
  - the draws stay side, then heading; the mode is set by `startMode` as now
- **`M.search(f, spot)`:** `f.spot = vec3(spot.x, spot.y, spot.z)`, `f.spotVel = vec3(0, 0, 0)`, and `f.searchAngle` = the bearing of `f.pos` from the spot.
- **`M.follow(f, carPos, carVel)`:** clears `f.spot` and `f.spotVel`; `f.mode` is "follow" when the car's horizontal speed is `START_FOLLOW_SPEED` (6 m/s) or more, otherwise "circle"; `f.orbit` = the bearing of `f.pos` from the car (the existing `startMode`).
- **`M.at(carPos, carVel, random, spot)`:**
  - without `spot`: as now
  - with `spot`: the same draws in the same order (side, then the angle); `f.spot` set as in `search`, `f.searchAngle` = the drawn angle, `f.pos` = the circle point at that angle (`spot` + `SEARCH_RADIUS` × (cos, sin), `HELI_HEIGHT` up), `f.vel = vec3(0, 0, 0)`, `f.lastCar` = the car
- **`M.target(f, carPos, carVel)`:**
  - leaving wins, as now
  - with `f.spot`: `spot + SEARCH_RADIUS × (cos a, sin a)`, `HELI_HEIGHT` above the spot, with `a = f.searchAngle`
  - otherwise as now
- **`M.leave(f, ref, random)`:** unchanged; the reference is the caller's (Task 4 passes `f.spot or car`).
- **`M.step(f, carPos, carVel, dt)`:**
  - a car jump over `JUMP_METERS` also shifts `f.spot`
  - with `f.spot` and not leaving: `f.searchAngle` advances by 2π / `SEARCH_PERIOD` × `side` × dt. The wanted velocity is `f.spotVel` (0 when nil), plus the circle point's velocity (`SEARCH_RADIUS` × ω × (−sin a, cos a)), plus `FOLLOW_GAIN` × (target − pos). No `carVel`; the follow/circle mode switch and the orbit advance are skipped.
  - with `f.spot` and leaving: the leaving branch as now (no circle velocity, no `carVel`, no spot velocity)
  - without `f.spot`: as now
  - the speed and acceleration limits apply as now

- [ ] **Step 1: Write the failing tests:**
  - "search circles the spot": a still spot, 120 s. From 60 s on, the horizontal distance to the spot is 60 ± 3 and the height 50 ± 2 above it, and the bearing rate is 2π/40 ± 20 % with the sign of `side`.
  - "search ignores the car": the same run with the car driving away at 30 m/s gives the same positions, to 1e-9.
  - "search keeps the limits": speed ≤ 70 + 1e-6 and |Δvel| ≤ 8 × dt + 1e-6 when the spot jumps 500 m (a new `search`).
  - "a guided spot is circled while it moves": the spot moves at 30 m/s in +x, with `f.spot` and `f.spotVel = (30, 0, 0)` set before every step. From 60 s on, the horizontal distance to the moving spot is 60 ± 3 and the bearing rate keeps the sign of `side`.
  - "a car jump moves the spot": after a 2 km car jump, `f.spot` moved by the jump to 1e-9, and the step matches the run without the jump, relative to the spot.
  - "arrive at a spot 2 km from the car doesn't move the spot or the helicopter on the first step": `arrive(car, gen, vec3(0, 0, 0), spot)` with the spot 2 km from the car, then `search(f, spot)`. `f.lastCar` equals the car; after one step (dt 0.05, car still) `f.spot` is unchanged to 1e-9 and the helicopter moved at most 70 × 0.05.
  - "arrive with a spot starts 300 m out from it": horizontal distance 300 ± 1e-6 from the spot, 60 above it, at rest; the same side as `arrive` without a spot from the same generator.
  - "follow after a search starts the circle at the helicopter's bearing": a stopped car 200 m from the spot, 30 s of search, then `follow(f, car, vec3(0, 0, 0))`: `f.spot` nil, `f.mode == "circle"`, and the bearing of `target(f, car, vel)` from the car equals the helicopter's bearing from the car, to 1e-9. With the car at 20 m/s instead, `f.mode == "follow"`.
  - "follow after search returns to trailing": `follow(f, car, vel)` with a car at a steady 30 m/s: the existing settle test's target within 3 m after 60 s.
  - "leaving while searching adds no circle velocity": a searching flight and the same flight without a spot, both after `leave(f, ref, gen)` with the same reference and generator, step identically, to 1e-9.
  - "at with a spot starts on its circle": horizontal distance 60 ± 1e-6 from the spot, 50 up, vel 0, the same side as `at` without a spot from the same generator.
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_heli_flight.lua`.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: the helicopter can circle a search spot"

### Task 3: Tunnel exits on the road graph

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/tunnels.lua`. Test: create `tests/test_tunnels.lua`.

**Interfaces:**
- **`M.exit(carPos, dirX, dirY, roads, roofedAt, seed) -> vec3 | nil`:** pure.
  - `roads = { closest = function(pos) return n1, n2, dist end, links = { [id] = { [otherId] = link } }, nodes = { [id] = { pos = {x, y, z} } } }`. These are the shapes of `map.findClosestRoad`, `map.getGraphpath().graph` (both directions) and `map.getMap().nodes`.
  - `roofedAt(pos) -> boolean`.
  - **Nil** when `roofedAt` at the car (`ROOF_HEIGHT` up) is false, before `closest` is called; when `roads`, `closest`, `links` or `nodes` are missing; when `closest` returns no node; or when its `dist` is missing, not a number, or over `MAX_ROAD_DISTANCE`.
  - **The forward node:** of `n1` and `n2`, the one with the larger dot product of (node − car) with (dirX, dirY); `n1` on a tie (also a zero direction). The other one is never visited.
  - **The walk:** breadth-first through the links, only expanding roofed nodes (each node tested once, `ROOF_HEIGHT` up). An unroofed node reached is an exit and is not expanded. A link to a node missing from `nodes` is skipped. Edge lengths are the 3D distances between the node positions. The walk stops when the summed edge lengths exceed `MAX_LENGTH` or the visited count reaches `MAX_NODES`.
  - **The pick:** as in Global Constraints. It returns the chosen exit's position as a `vec3`, or nil when no exit was found.

- [ ] **Step 1: Write the failing tests in `tests/test_tunnels.lua`,** with small hand-built graphs (`closest` returns a distance of 2 unless stated):
  - **a straight tunnel:** nodes 1-5 on a line 100 m apart, 2-4 roofed, the car between 2 and 3. Heading towards 5 gives node 5. Heading towards 1 gives node 1 (turning around).
  - **a fork inside:** two exits. Seed 0 gives the first by id, seed 1 the second, and no seed the first.
  - **too long:** 41 roofed nodes 100 m apart (4 km), so nil. Also 250 roofed nodes in a ring (a cycle), so nil, with no endless loop.
  - **lengths from positions:** the 4 km tunnel with `len = 1` on every link still gives nil.
  - **a road too far:** `closest` returns a distance of 16, so nil; 14 gives the exit; no distance gives nil.
  - **not in a tunnel:** the car isn't roofed, so nil, and `closest` is never called.
  - **missing data:** nil `roads`, nil `links`, a nil `closest` result, a node missing from `nodes`: each gives nil with no error.
  - **just under a bridge:** the forward node is unroofed, so it is the exit.
  - **no direction:** a zero direction walks from `n1`.
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_tunnels.lua`.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: find the tunnel exit ahead on the road graph"

### Task 4: The search spot and sight-only cover

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua`
  - `client/lua/ge/extensions/copsAndRobbers/shelter.lua` (`inSight` gets a `maxRange`)
  - `client/lua/ge/extensions/copsAndRobbers.lua` (`updateHeli`)
- Test: `tests/test_heli_client.lua`, `tests/test_shelter.lua`, `tests/test_client.lua`

**Interfaces:**
- **Consumes:** `guided` (Task 1), `search` / `follow` / `arrive(..., spot)` / `at(..., spot)` / `f.spotVel` (Task 2), `tunnels.exit` (Task 3).
- **`heli.set`:**
  - a valid status: stores `state.guided = d.guided == true` and clears `state.flightFailed`
  - an invalid one: clears `guided` with the phase, reason, end time and seed
- **`M.lightTick(state, target, night, clock, opts)`** runs two parts:
  1. reads `phase = state.phase` and `last = state.lightPhase` once
  2. **the flight part,** unless `state.flightFailed`, in its own `pcall`: `flightTick(state, target, phase, last, clock, opts)`. On an error it drops the flight (`dropFlight`), sets `state.flightFailed = true` and logs once (`log("E", "cnr_heli", "helicopter flight stopped: " .. err)`).
  3. **the light part,** `tickLight(state, target, phase, last, night, clock, opts)` without `fly`: skipped while `state.failed` (with the leftover removal, as now), and in its own `pcall` as now. `state.failed` no longer stops the flight.
  4. writes `state.lightPhase = phase` after both, and only when `target` is not nil (the existing test "a phase change while the target is missing for a moment is not lost" depends on it)
- **`flightTick` without a target:** sets `state.missingSince = state.missingSince or clock`. The flight doesn't step and nothing is created, but the flight is dropped `DEPART_SECONDS` after `state.leftAt`, and when the phase is none of "tracking", "searching" and "refuelling".
- **`flightTick` with a target**, in this order:
  - `state.missingSince = nil`; the car, dt and `carVelocity` as now. `carVelocity`'s jump also shifts `state.lastKnown` by the same jump.
  - **`fly()`:**
    - **creating a flight** while up:
      - "searching": the spot is `state.lastKnown or car` after "refuelling", otherwise the car. After "arriving" or "refuelling": `arrive(car, random, carVel, spot)`, then `search(f, spot)`. Otherwise (a join): `at(car, carVel, random, car)`.
      - "tracking": as now (`arrive(car, random, carVel)` or `at(car, carVel, random)`), no spot
      - a flight made with a spot sets `state.sweepAt = clock` and `state.retargetAt = clock`
    - **resuming** a leaving flight: as now
    - **refuelling:** `leave(f, f.spot or car, random)` and `state.leftAt = clock`
    - **other phases:** drop the flight, as now
  - **The spot rules,** with a flight that isn't leaving:
    - phase "tracking": when `f.spot` is set, `follow(f, car, carVel)`. Then `state.lastKnown = car`.
    - phase "searching": the first of these that applies chooses a new spot:
      1. lost (`last == "tracking"`): `search(f, state.guided and car or spotFor(...))`
      2. guidance starting (`state.guided and not state.wasGuided`): `search(f, car)`
      3. guidance ended (`state.wasGuided and not state.guided`): `search(f, spotFor(...))`
      4. no spot (`f.spot == nil`): `search(f, state.lastKnown or car)`
    - then, while guided: `f.spot = vec3(car.x, car.y, car.z)` and `f.spotVel = carVel` every tick (a direct assignment, so the angle continues), and `state.lastKnown = car`. Otherwise `f.spotVel = vec3(0, 0, 0)`.
    - every `search(...)` from these rules sets `state.sweepAt = clock`; every `search(...)` and `follow(...)` sets `state.retargetAt = clock` (Task 5 reads both)
  - the 8 s drop: `state.leftAt` and `clock - state.leftAt >= DEPART_SECONDS` drop the flight (as now, moved here)
  - `state.wasGuided = state.guided`
- **`spotFor(state, car, target, carVel, opts) -> vec3`:**
  - the direction: `carVel` when its horizontal speed is above 1 m/s, otherwise `target:getDirectionVector()` when the target has it, otherwise (0, 0)
  - calls `opts.tunnelExit(car, dirX, dirY, state.seed)` in its own `pcall`
  - returns the result when it is a table with numeric `x`, `y` and `z`; otherwise the car
  - an error is logged once per round (`state.tunnelLogged`) and gives the car
- **`opts.tunnelExit`:** `copsAndRobbers.lua` passes it, only when `castRayStatic` exists, as a closure over `tunnels.exit` with:
  - `{ closest = function(p) return map.findClosestRoad(p) end, links = gp and gp.graph, nodes = m and m.nodes }`, where `gp = map.getGraphpath and map.getGraphpath()` and `m = map.getMap and map.getMap()`, resolved per call and nil-safe when `map` is missing
  - `roofedAt = function(p) return shelter.roofed(p, castUp) end`
  - the client stub's `map.findClosestRoad` (`tests/client_stubs.lua:114`) returns no distance, so the walk finds nothing unless a test stubs one
- **Cover (`coverTick(state, clock, obj, castRay)`, the `castUp` parameter removed):**
  - with a flight and `castRay`: `not shelter.inSight(f.pos, p, COVER_HEIGHT, dirX, dirY, castRay, SIGHT_RANGE)`, the direction from `obj:getDirectionVector()` as now
  - without a flight (also after a flight error, until the next valid status): covered = true
  - `state.failed` (the light) no longer matters
  - the spacing, the first report and the smoothing are unchanged
- **`shelter.inSight(from, carPos, height, dirX, dirY, castRay, maxRange)`:** a point further than `maxRange` (straight line from `from` to the point at `height`) is not seen, and no ray is cast for it. Without `maxRange`, as now.
- **`M.clear`** also resets `lastKnown`, `guided`, `wasGuided`, `sweepAt`, `retargetAt`, `flightFailed`, `missingSince` and `tunnelLogged`. (Task 5 adds its own fields; the sound's state is reset by `heliSound.clear`, Task 6.)

- [ ] **Step 1: Write the failing tests** (dt 0.05; a car that moves keeps under 30 m per tick, so the jump rule doesn't fire):
  - **`tests/test_shelter.lua`:** "points beyond the range are not seen": from (0, 0, 1.5), a ray that never hits and counts its calls, no direction, height 1.5. The car at (401, 0, 0) with `maxRange` 400 → false and no ray cast; at (399, 0, 0) → true; at (401, 0, 0) without `maxRange` → true.
  - **`tests/test_heli_client.lua`:**
    - "arrival searches where the runner was": "arriving" → "searching" with the car at A; the car then drives at 10 m/s to B, 200 m away, and stops. After 60 s the helicopter circles A at 60 ± 3 m and `f.spot` is A to 1e-9.
    - "a refuel returns to the last known spot": "tracking" at A for 2 s; "refuelling" for 10 s (the flight is dropped at 8 s) while the car drives at 10 m/s to B; "searching": the new flight starts 300 ± 1 m (horizontally) from A, and after 60 s circles A at 60 ± 3 m.
    - "a short refuel from tracking searches the last known spot": "tracking" at A for 2 s; "refuelling" while the car drives towards B; "searching" 5 s later: the same flight, `f.leaving` nil, `f.spot` is A to 1e-9, `state.sweepAt` is that tick's clock.
    - "a short refuel from searching back to tracking follows the car": "arriving" → "searching" at S; the car drives 200 m away and stops; "refuelling" at 30 s, "tracking" at 35 s: the same flight, `f.spot` nil, `f.mode == "circle"`, and 30 s later the helicopter is within 70 m of the car (3D).
    - "a flight created in tracking has no spot": "arriving" → "tracking", a join in "tracking", and "refuelling" over 8 s → "tracking": `f.spot` nil each time.
    - "losing the runner in a tunnel searches the exit":
      - an `opts.tunnelExit` stub returns E, 300 m from the car, and records its arguments
      - "tracking" → "searching" makes `f.spot` E, with one call that got the car's position and `state.seed`
      - a stub that returns nil makes it the car
      - a stub that errors makes it the car, logs one line over two losses, and leaves `state.flightFailed` nil
    - "the tunnel direction is the car's velocity above 1 m/s, otherwise its facing": a target whose `getVelocity` is (10, 0, 0) and `getDirectionVector` (0, 1, 0) gives the stub a direction parallel to (1, 0); with `getVelocity` (0.5, 0, 0), parallel to (0, 1).
    - "guided follows the runner and recomputes when guidance ends": searching at S, then guided while the car drives at 20 m/s: `f.spot` equals the car and `f.spotVel` the car's velocity every tick. Guidance ends: `tunnelExit` is called exactly once, the spot is its result, and `f.spotVel` is 0.
    - "guidance starting restarts the circle and the sweep from the runner": searching at S, 500 m from the car; guided turns true at clock c: `state.sweepAt == c`, `state.retargetAt == c`, `f.spot` is the car, and `f.searchAngle` is the helicopter's bearing from the car, to 1e-9.
    - "guided and lost in the same tick search the runner": "tracking" with guided, then "searching" with guided: `f.spot` is the car, and `tunnelExit` is never called.
    - "a refuel while searching far away flies away from the spot": the spot 1 km east of the car (a `tunnelExit` stub on a loss), "refuelling" on the first tick, 60 s or more after the loss, that the helicopter's bearing from the spot is within 30° of east. The leaving point is 400 m (horizontally) from the spot, to 1e-6; over the 8 s the helicopter is never within 900 m of the car, and ends more than 1000 m from it.
    - "a car jump moves the last known spot": "tracking" at A; "refuelling" for 10 s with a 2 km car jump at 9 s; "searching": the new flight's `f.spot` is A plus the jump, to 1e-9.
    - "clear forgets the last known spot and guidance": after "tracking" at A while guided, `clear`: `lastKnown`, `guided`, `wasGuided`, `sweepAt`, `retargetAt`, `flightFailed` and `missingSince` are nil or false. Then "refuelling" → "searching" with the car at C searches C, not A.
    - "an invalid status clears guided": a valid `set` with `guided = true`, then `set(state, nil)`: `state.guided` is false.
    - "cover is covered without a helicopter": "arriving", no flight: the first report is true, even with a free `castRay`.
    - "a light failure doesn't stop the flight": `createObject` returns nil at night, so `state.failed` is set; over 2 s the flight still moves, and `coverTick`'s rays start at its current position.
    - "a flight error drops the flight, logs once and counts as covered until the next status": `heliFlight.step` replaced by one that errors. Over 10 ticks: one log line, `state.flight` nil, `state.flightFailed` true, no new flight; the first cover report is true. With `step` restored and a new valid `set`: `flightFailed` is nil and a flight exists on the next tick.
    - "the flight keeps its timers without a target": "tracking", then "refuelling" with the target, then the target nil: the flight is dropped `DEPART_SECONDS` (± one tick) after `state.leftAt`, and `state.missingSince` is the first nil tick's clock.
    - "a phase change reaches both parts on the same tick": "arriving" → "tracking" at night: on that tick the flight exists 300 m out and `state.fx.mode == "approach"`.
    - **Adapt** to sight-only cover and the dropped `castUp` argument: "the first cover check reports not covered, then only changes", "cover checks are spaced by the interval" and "cover needs two equal checks to switch and is resent after a reset" (with a flight up and a `castRay` that is free or blocked); "with a helicopter, cover comes from its line of sight". **Remove** "the cover check is cast from above the car" (the 1.5 m height is pinned by `test_shelter`'s "the points sit 1.5 m up and 2 m ahead and behind"), "a failed light stops the flight, so cover falls back to the roof check" (replaced by "a light failure doesn't stop the flight") and "without a helicopter the roof check decides" (replaced by "cover is covered without a helicopter"). Any other test that this task's spot rules break is adapted to them; light behaviour stays for Task 5.
  - **`tests/test_client.lua`:**
    - "a tunnel loss sends the helicopter to the exit ahead":
      - stub `map.findClosestRoad` (returns 2, 3 and a distance of 2), `map.getGraphpath` (a line of nodes 1-5, 100 m apart in +x, both directions), `map.getMap` (their positions) and `castRayStatic` (upward rays within 5 m horizontally of nodes 2-4 or of the car hit 5 m up; nothing else hits)
      - the runner's game at night, with the car between nodes 2 and 3 heading +x: "tracking" → "searching". After 60 s the light circles node 5 at 60 ± 3 m.
      - follow the existing helicopter tests there
    - **Adapt:** "the runner reports cover from the head start, once, and a cop does not": the first report is now `covered = true` (no helicopter in the head start).
    - **Rewrite:** "practice as a cop: the practising cop's game reports cover for the AI runner". After `cnr_runnerGo`, fire `cnr_heli` `{ phase = "searching", seconds = 100, seed = 7 }`, so a flight is up. With a `castRayStatic` that blocks every slanted ray, the report is `covered = true`; with one that blocks none, after the two-reading smoothing, `covered = false`.
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test` twice.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: the helicopter searches where it last knew the runner was"

### Task 5: The light while searching; docs

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua`
  - `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`HELI_TIMED`)
- Docs:
  - `docs/FEATURES.md` (the helicopter section: tracking, cover, searching, the HUD line, the searchlight)
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` (runner and cop helicopter items)
  - `README.md` (the config table's "tracks the runner in the open" line and any helicopter description)
  - `docs/DEPENDENCIES.md` (the searchlight entry, the `castRayStatic` entry, Placement and roads)
- Test: `tests/test_heli_client.lua`, `tests/test_client.lua`, `tests/test_hud.lua`

**Interfaces:**
- **Consumes:** `f.spot`, `state.sweepAt`, `state.retargetAt` (Task 4).
- **When the light is wanted:**
  - `desired` is `(phase == "tracking" or phase == "searching") and night`
  - `M.wantsNight(state)` is true for "tracking", "searching" or an existing light
- **The phase table** replaces the block in `tickLight` that runs when `phase ~= last`:

  | From → to | The light |
  |---|---|
  | "arriving" or "refuelling" → "tracking" or "searching", at night | `startApproach`: a new light from 0, an existing one from its current factor |
  | the same, by day | unchanged |
  | "tracking" ↔ "searching" | kept; the switch offset comes from Task 4's `retargetAt` |
  | "tracking" or "searching" → "refuelling", with a flight and the light not in its night-end fade | `startDepart` |
  | anything else, with a light | `removeLight`, unless the light is in its fly-away and the phase is "refuelling" |

  After it, unchanged: night ending starts the fade; `desired` with no light creates one at full brightness; `desired` while it fades or flies away fades it in.
- **Removed:** `startRefound`, `REFOUND_AIM_OFFSET`, `AIM_SWEEP_OFFSET` and the fresh light's aim offset in `startApproach` (with `offsetAim` and its helper). "Refound" goes in this task only.
- **The aim point** (in `advance`):
  - `aimStep` runs every tick on the car, as now, whatever the light follows.
  - **The raw target:** with `f.spot`, the sweep point on the ground (below); otherwise the operator aim on the car. The fly-away drift (`fx.extra`) is added to either, as now.
  - **The switch offset:** when `state.retargetAt` differs from the one last handled, and a previous `state.aimPos` exists, `state.aimSwitch = { x, y, z = previous aimPos − raw, at = clock }`. Either way that `retargetAt` then counts as handled. The aim point is raw + `aimSwitch` × exp(−(clock − at) / `AIM_SWITCH_SECONDS`). So on the switch tick the aim point stays where it was. A new light has no previous aim point and no offset.
  - **A fly-away ended early** (`toMode` leaving "depart" with a drift): while the aim follows the car, the drift goes into `aim.offset` as now. While it follows the sweep (`f.spot` set), the drift is added to the switch offset's current, decayed value, which restarts its decay at that clock.
- **`M.sweepPoint(spot, t) -> vec3`:** pure, returned for tests.
  - `r = SWEEP_RADIUS × (1 − |1 − 2 × (t mod SWEEP_PERIOD) / SWEEP_PERIOD|)`, `θ = 2π × t / SWEEP_TURN`
  - returns `spot + (r cos θ, r sin θ)` at the spot's height
  - heli.lua calls it with `t = clock − state.sweepAt`
- **The sweep on the ground:**
  - every `SWEEP_RAY_INTERVAL`, and on the first tick after a new `state.sweepAt`: `castRayStatic(vec3(x, y, spot.z + SWEEP_RAY_HEIGHT), vec3(0, 0, -1), SWEEP_RAY_LENGTH)` above the sweep point
  - a returned distance d below `SWEEP_RAY_LENGTH` gives `state.sweepZ = spot.z + SWEEP_RAY_HEIGHT − d`; no hit, a nil return or no `castRayStatic` gives `spot.z`
  - between rays the last `sweepZ` is kept; the sweep's aim point is (x, y, `sweepZ`)
  - the beam's far plane (`z = aimPos.z`) then follows the ground with no beam change
- **Range and the beam's slant check:** to the aim point, not the car (`writeRange` and `beamTick`'s `slantOf`).
- **`startDepart(state, ref, clock)`:** the drift direction is the unit vector from `ref = f.spot or car` to `f.leaving`.
- **`M.clear`** also resets `aimSwitch`, the handled `retargetAt`, `sweepZ` and the sweep ray time.
- **`hud.lua`:** `HELI_TIMED` gains `searching = true`, so the refuel countdown shows while searching.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_heli_client.lua`:**
    - "arriving → searching at night ramps from 0 over 8 s" (re-bases "a helicopter that just arrived flies in from 300 m and sweeps onto the car", which goes): `night(0, "arriving")`, `night(1, "searching")`. The light exists at the flight, 300 ± 15 m (horizontally) from the spot and 60 ± 1 above it; the brightness is below 5 % of `BRIGHTNESS`; at 1 + 4 s it is 50 % ± 2 %; at 1 + 8.5 s it is `BRIGHTNESS`; the aim point stays within `SWEEP_RADIUS` + 1 m (horizontally) of the spot.
    - "tracking → refuelling → searching within 7 s keeps the same light object and ramps from its faded value" (re-bases "back from a short refuel the helicopter turns back from where it is, brightening, the aim point not jumping"): "tracking" at 0, "refuelling" at 2, "searching" at 9.05. The same light object and flight; `f.leaving` nil; the helicopter moved at most 70 × 0.05; the brightness on that tick within [b0 − 1e-6, b0 + 5 % of `BRIGHTNESS`] and `BRIGHTNESS` after 8.5 s; `f.spot` is the car's position at 2 s; every tick's aim move within the bound of "the aim never jumps".
    - "searching → refuelling → searching within 7 s keeps the spot and the light": the same light object, `f.spot` unchanged, the brightness ramps from its faded value, and every tick's aim move within the same bound.
    - "the light stays on while searching": at night, "tracking" → "searching": the same light object; `fx.bright` stays 1 and the `brightness` field 80 for 5 s.
    - "going searching during the fly-in keeps the light and its ramp" (replaces "going under cover during the fly-in cuts the light at once"): "arriving" → "tracking" at 1, "searching" at 3.05: the same light object, `fx.mode == "approach"`, `BRIGHTNESS` by 9.5.
    - "the sweep spirals out and back": the distance of `sweepPoint(spot, t)` from the spot is 0 at t = 0, 75 at t = 10, 150 at t = 20, 75 at t = 30 and 0 at t = 40, all to 1e-9; from t = 0 to 80 in steps of 0.01, no step moves the point more than 1.3 m; the bearing from the spot at t = 2 and t = 10 is the same, to 1e-9.
    - "the sweep point sits on the ground": a `castRayStatic` stub whose downward rays return 108 gives an aim point at the spot's height − 8, to 1e-9; returning nil gives the spot's height. At most 10 downward rays in 2 s, and one on the first tick after a new spot.
    - "the aim never jumps when the target changes": a still car; "tracking" at night for 5 s; "searching" with a `tunnelExit` stub giving a spot 120 m from the car, for 20 s; "tracking" again for 5 s. Every tick moves the aim point by at most |S| × (1 − e^(−dt / `AIM_SWITCH_SECONDS`)) + 126 × dt + 1 m. Here |S| is the size of the latest switch offset when it was set (0 before the first), and 126 m/s bounds the sweep point's speed (150 × 2π/8 + 2 × 150/40 ≈ 125.3). On each tick where `state.retargetAt` changes, the aim point moves less than 1 m.
    - "a refuel while searching flies away with the light": at night, searching, then "refuelling": `f.leaving` set, `fx.mode == "depart"`, `fx.dir` is the unit vector from `f.spot` to `f.leaving` (to 1e-9), the brightness is below 20 % from 7.5 s, and the light and the flight are gone at 8 s.
    - "the range follows the aim point": 20 s into a search (the sweep 150 m out), the `range` field is within 5 m (the write step) of min(400, round(max(120, slant from the light to the aim point + 30))).
    - **Adapt:** "the searchlight exists only while tracking at night" (to "while up at night", searching too) and "the searchlight goes when the phase ends or on clear" ("tracking" → "searching" keeps it).
    - **Rewrite:** "under cover the light is cut while the helicopter flies on, and on the way out it is back at once at the helicopter" becomes "while searching the light stays at the helicopter as it circles the spot, and found again the aim swings to the car without a jump".
    - **Remove:** "going under cover cuts the light at once" and "a re-found runner gets the light at once at full brightness, the aim 8 m off then swinging in".
  - **`tests/test_hud.lua`:** in "heliItem texts and times per phase", "searching" with `endsAt = 5` now has the time "0:05".
  - **`tests/test_client.lua`:**
    - "no searchlight by day or while the helicopter searches" becomes "no searchlight by day; at night it stays on while the helicopter searches": by day there is no light; at night (`nightTracking("runner")`), after `cnr_heli` "searching" and 0.2 s, the same light object is there.
    - "the game asks whether it is night only while the helicopter tracks or a light is up": it also asks while "searching".
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement as in Interfaces, then update the docs:**
  - **Searching:** every flight starts searching; it circles where it last knew you; tunnel exits ahead; turning around dodges it; the cops' sight guides it; it finds you only by seeing you within 400 m; the light keeps sweeping.
  - **Cover:** out of its sight for 2 s. Before it arrives and while it refuels, nothing sees you.
  - **`docs/FEATURES.md`:** the "Tracking" line (while it is up and sees the runner); the "Cover" line loses "Before the helicopter arrives, a roof check decides…"; a new "Searching" item; the HUD line shows "HELICOPTER SEARCHING 1:20"; the "Searchlight" item is on while it is up at night and loses "It goes out at once when the helicopter loses the runner and is back at once…".
  - **`docs/DEPENDENCIES.md`:**
    - the searchlight entry: "only while the helicopter tracks and it is night" becomes while it is up at night
    - the `castRayStatic` entry: cover up to 400 m; the sweep's ground ray; the roof check above road nodes for the tunnel walk
    - Placement and roads: `map.findClosestRoad` also returns the distance to the road, which `tunnels.lua` uses (15 m at most); the tunnel walk reads `getGraphpath().graph` and `getMap().nodes[].pos`; on update, check that a known tunnel still finds its exit
  - **Remove** every "in the open" wording.
- [ ] **Step 4: Run `make test` twice and `make vuecheck`.** Expected: `0 failed`, and vuecheck clean.
- [ ] **Step 5: Commit.** Message: "feat: the searchlight sweeps while the helicopter searches; docs"

### Task 6: The rotor sound

**Files:**
- Create:
  - `client/lua/ge/extensions/copsAndRobbers/heliSound.lua`
  - `client/art/sound/cnr/heli_rotor.ogg`, copied in Step 1 from `/tmp/claude-1000/cnr-sound/heli_rotor.ogg` (made from qubodup's CC0 "Helicopter Rotor Loop" #187681)
- Modify:
  - `Makefile` (the `package` target's client zip includes `art`)
  - `client/lua/ge/extensions/copsAndRobbers.lua` (`updateHeli`, `endRound`)
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua` (`M.soundLevel`)
  - `client/lua/ge/extensions/copsAndRobbers/playerSettings.lua`, `client/lua/ge/extensions/copsAndRobbers/hud.lua` (the settings payload)
  - `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue`
  - `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, How to Play's "Your settings" item
- Test: create `tests/test_heli_sound.lua`; also `tests/test_player_settings.lua`, `tests/test_hud.lua`, `tests/test_client.lua`, `tests/test_heli_client.lua`

**Interfaces:**
- **The volume call** (from Step 0):
  - if `setVolumePitchCT` changes a playing `fileName` emitter's volume: `obj:setVolumePitchCT(v, 1, 0, 0)`
  - otherwise: `obj:setField("volume", 0, tostring(v))`, then `obj:postApply()` so the emitter re-reads its fields
  - the controller records which in Step 0 before dispatching this task
- **`heliSound.new()`, `heliSound.tick(s, pos, level, clock, camPos, castRay)`, `heliSound.clear(s)`:**
  - **Wanted:** `pos` not nil and `level` > 0. The target volume is `level × muffle` while wanted, otherwise 0.
  - **Easing:** the eased volume `s.vol` moves towards the target, rising by at most dt / `FADE_IN_SECONDS` and falling by at most dt / `FADE_OUT_SECONDS` per tick. So it fades in on creation, when the setting turns on and when a short refuel lifts the level, and fades out when it stops.
  - **Making and moving it:**
    - while wanted and `scenetree.findObject(NAME)` finds nothing: create it (Global Constraints) with `s.vol = 0`
    - every tick while it exists: `setPosition` at `pos`, or at the last position while it fades out without one
    - not wanted and `s.vol` at 0: delete it
  - **Volume writes:** `s.vol` is written when it differs from the last written value by more than `VOLUME_STEP`, or when it reaches 0 or the target and differs from the last written value.
  - **Muffle:**
    - every `RAY_INTERVAL`, a `castRay` from `camPos` to the position: blocked when the hit is shorter than the distance − 2
    - the muffle eases towards `MUFFLED` or 1 over `MUFFLE_SECONDS`
    - no `camPos` or no `castRay`: no muffle
  - **Leftover:** while no sound is wanted and `s.vol` is 0, look for `NAME` about once a second (`LEFTOVER_INTERVAL`) and delete it, as `leftover()` in heli.lua does for the light.
  - **Errors:** the tick body runs in a `pcall`. An error deletes the emitter (found by name, in its own `pcall`), logs once, and sets `s.failed`. While failed, only the leftover look runs.
  - **`clear(s)`:** deletes the emitter at once and resets every field: the eased volume, the last written value, the muffle, the ray time, the leftover time, the last position, `failed`.
- **`heli.soundLevel(state, clock) -> number`:**
  - 0 without a flight
  - 0 while the target has been missing for more than `TARGET_MISSING_SECONDS` (`state.missingSince`, Task 4)
  - during the fly-away: min(1, max(0, (`DEPART_SECONDS` − (clock − `state.leftAt`)) / `DEPART_FADE_SECONDS`))
  - otherwise 1
  - no join special case: `heliSound` eases every rise
- **Setting:** `sound`, a boolean, default true.
  - The HUD switch goes after "Searchlight beam", with the same markup: name "Helicopter sound", desc "The police helicopter's rotor; heard from far off".
  - `updateHeli` calls `heliSound.tick(soundState, heliState.flight and heliState.flight.pos, prefs.sound ~= false and heli.soundLevel(heliState, clock) or 0, clock, camPos, castRayStatic)`, with `camPos` from `core_camera.getPosition()` when it exists. While not active it calls it with `nil` and 0, so fades end and leftovers go.
  - `endRound` calls `heliSound.clear`; the round's end, a cancel, leaving, a map change and unload all go through it.

- [ ] **Step 0 (the controller, before dispatching): the volume call.** The user is checking in game whether `setVolumePitchCT` changes a playing `fileName` emitter's volume. Record the answer here: **Volume call: _to be filled in_ (`setVolumePitchCT`, or `setField("volume")` + `postApply()`, or the call the check found).**
- [ ] **Step 1: Copy the sound file and write the failing tests.**
  - Copy `/tmp/claude-1000/cnr-sound/heli_rotor.ogg` to `client/art/sound/cnr/heli_rotor.ogg`.
  - **`tests/test_heli_sound.lua`,** with stubbed `createObject`, `scenetree`, `Sim.upcast` and the volume call:
    - "the emitter is made with the file and fields, registered and played": the fields of Global Constraints, `volume` "0", `canSave` false, registered as `cnr_heli_sound`, in the mission group, `play()` called, and `setPosition` at `pos` every tick
    - "an emitter that doesn't register is deleted and logged"
    - "it fades in over 1 s": the written volume is 0.5 ± 0.05 at 0.5 s and 1 at 1 s, and no tick raises it by more than dt / 1 + `VOLUME_STEP`
    - "a level that rises at once is eased": the level goes from 0.3 to 1 in one tick; the volume takes 0.7 s ± one tick to reach 1
    - "level 0 or a nil pos fades it out over 1 s and then removes it": the emitter is there at 0.5 s with the volume 0.5 ± 0.05, and gone by 1.1 s
    - "the muffle eases to half behind a wall and back", with rays only every 0.25 s
    - "the volume is only written on a change over 0.02, and when it reaches 0 or the target"
    - "it is always found by name": an emitter deleted from outside while wanted is made again on the next tick, starting from volume 0
    - "a leftover emitter is looked for about once a second and deleted while no sound is wanted": at most 2 lookups in 2 s; a planted `cnr_heli_sound` is gone within 1.1 s
    - "an error deletes the emitter, stops the sound and logs once": `setPosition` errors; the emitter is deleted, one log line over 10 ticks, and none is made again until `clear`
    - "clear deletes it at once and resets"
  - **Player settings and the HUD:** as for `beam`: `sound` true by default, false kept, a non-boolean rejected; the payload carries `sound`.
  - **`tests/test_heli_client.lua`:** "soundLevel follows the flight": 0 without a flight; 1 while up; at `leftAt` + 5 s 1, + 6.5 s 0.5, + 8 s 0; with the target missing 1.9 s it is 1, and 2.1 s 0.
  - **`tests/test_client.lua`:**
    - "the sound plays at the helicopter and is gone after the round": a `cnr_heli_sound` emitter at the light's position on a cop's and a runner's game; gone after the round's end, a cancel, leaving, a map change and unload (as the light test does)
    - "turning the sound off fades it out within about 1 s, and on fades it in": gone by 1.1 s after off; after on, the written volume rises over about 1 s
    - "a leftover emitter is deleted while no round runs"
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement** as in Interfaces. Then the docs:
  - **README and How to Play:** four switches; describe "Helicopter sound". README also names the sound's author: "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0.
  - **FEATURES:** the sound.
  - **DEPENDENCIES:**
    - the `SFXEmitter` fields and calls, with the volume call from Step 0
    - the file's credit: "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0
    - on update, check that the sound plays in 3D, its volume follows the fades, and it is gone after the round
- [ ] **Step 4: Run `make test` twice and `make vuecheck`, then `make package`** (plain `make` runs the tests) **and check that `dist/Client/CopsAndRobbers.zip` contains `art/sound/cnr/heli_rotor.ogg` (`unzip -l`).**
- [ ] **Step 5: Commit** the files explicitly, the OGG included. Message: "feat: the police helicopter's rotor sound"
