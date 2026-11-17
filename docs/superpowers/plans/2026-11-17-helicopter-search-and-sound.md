# Helicopter Searching and Sound Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Searching becomes a real search. Every flight starts searching at a spot: where it was called, where it last knew the runner was, or a tunnel exit ahead. The cops' sight guides it. It tracks only once it sees the runner itself.
- The searchlight stays on and sweeps while searching.
- Every game hears a rotor sound at the helicopter.

**Architecture:**
- **Server:** `cnr/helicopter.lua` starts each up phase as searching, and carries `guided` (a cop sees the runner) in its status.
- **Client, pure modules:**
  - `heliFlight.lua` gets a search mode (circle a spot).
  - A new `tunnels.lua` finds tunnel exits on the game's road graph.
  - A new `heliSound.lua` runs the rotor emitter.
- **Client, `heli.lua`:** owns the spot lifecycle, the sight-only cover, the flight's own protected step, and the light's sweep.
- **`copsAndRobbers.lua`:** wires the road graph, the roof check, the sound and the new setting.

**Tech Stack:** Lua (server: Lua 5.3; client: LuaJIT in game, Lua 5.x in tests), Vue 3. `make test`, `make vuecheck`.

**Spec:** `docs/superpowers/specs/2026-11-17-visible-searchlight-beam-design.md`, sections "Line of sight", "Searching" and "Helicopter sound". They are the binding source for every rule and number.

## Global Constraints

- **Style:**
  - No code comments, no emojis.
  - Lua: module table `M`, camelCase locals. Follow the surrounding files.
- **No version bump** on the branch. **No new network message:** `guided` rides in the existing `cnr_heli` status and the round setup's `heli`.
- **Lua:**
  - In the pure client modules, do maths per component and build vectors with `vec3(x, y, z)`; the test stub `vec3` has no operators.
  - No `goto`, `//` or bit operators.
- **Search numbers** (in `heliFlight.lua` unless stated):
  - `SEARCH_RADIUS = 60`, `SEARCH_PERIOD = 40`; the height is the existing `HELI_HEIGHT = 50` above the spot
  - in `heli.lua`: `SWEEP_RADIUS = 150`, `SWEEP_PERIOD = 40`, `SWEEP_TURN = 8`, `AIM_SWITCH_SECONDS = 0.5`, `SIGHT_RANGE = 400`
- **Tunnel walk** (in `tunnels.lua`):
  - `MAX_LENGTH = 3000` m of road, `MAX_NODES = 200`
  - the roof check at 1.5 m above a node
  - the pick is `exits[seed % #exits + 1]`, with the exits ordered by node id compared as strings, or the first exit without a seed
- **Sound** (in `heliSound.lua`):
  - `NAME = "cnr_heli_sound"`, `FILE = "/art/sound/cnr/heli_rotor.ogg"`
  - `REF_DISTANCE = 40`, `MAX_DISTANCE = 800`
  - `FADE_IN_SECONDS = 1`, `MUFFLED = 0.5`, `MUFFLE_SECONDS = 0.5`, `RAY_INTERVAL = 0.25`
  - the emitter fields set with `setField`: `fileName`, `is3D` "1", `isLooping` "1", `referenceDistance`, `maxDistance`, `volume`; then `canSave = false`, `registerObject`, `scenetree.MissionGroup:addObject`, `setPosition`, `play()` (probe-verified)
- **Kept:**
  - the 2 s loss and instant re-acquire on the server
  - the 0.5 s client smoothing
  - the beam and its setting
  - the anti-goal that nothing is left after the round, a cancel, leaving, a map change or unload (light, emitter, flight)
- **Removed:**
  - the light cut while searching (and `startRefound` / `REFOUND_AIM_OFFSET`)
  - the roof check as a cover source (`shelter.roofed` stays for the rain and the tunnel walk)

## Review Focus

1. **A runner who is never seen** (a tunnel for the whole up phase). The helicopter stays "searching" all up phase and flies away on refuel with its light. It returns to the last known spot, not to the runner. Pinned in Tasks 1 and 4.
2. **Guided and lost in the same tick, or guidance ending inside a tunnel.** The spot is recomputed from that moment and never left at a stale live position. Pinned in Task 4.
3. **A road graph that is missing, empty, cyclic, one node, or a tunnel longer than 3 km.** `tunnels.exit` returns nil or an exit without looping, and the walk is bounded. Pinned in Task 3.
4. **The aim switching target mid-sweep, or the spot jumping 2 km** (a BeamNG.Earth origin shift). No jump of the aim point and no NaN; the spot moves with the car's jump. Pinned in Tasks 2 and 5.
5. **The sound setting toggled mid-flight, a round end during the fly-away, a map change.** No `cnr_heli_sound` is left, and the volume never jumps up. Pinned in Task 6.

---

### Task 1: Each flight starts searching; the cops' sight guides it (server)

**Files:**
- Modify:
  - `server/CopsAndRobbers/cnr/helicopter.lua`
  - `server/CopsAndRobbers/cnr/round.lua` (around line 381)
  - `server/CopsAndRobbers/main.lua` (the `cnr_heli` send, around line 628)
- Test: `tests/test_helicopter.lua`, `tests/test_main.lua`

**Interfaces:**
- **`enterUp(h, start)`** always sets `tracking = false`. The `covered` argument no longer decides the first state.
- **`helicopter.update(h, now, covered, guided)`:**
  - stores `h.guided = guided == true`
  - returns true when the phase name, the seed, or (while up) `guided` changed
- **`helicopter.status(h, now)`** includes `guided = true` only while the phase is up and `h.guided`.
- **The caller** in round.lua passes `self.inSight`. The heli effect and `cnr_heli` carry `guided`.

- [ ] **Step 1: Write the failing tests.**
  - **Existing tests:** update every test that expects "tracking" right at arrival or after a refuel. It is now "searching" until an update with `covered = false`.
  - **New tests in `tests/test_helicopter.lua`:**
    - "a flight starts searching and tracks on the first open report"
    - "a runner never seen keeps it searching until refuel"
    - "guided is in the status only while up and when a cop sees the runner, and a change of it is reported"
  - **New test in `tests/test_main.lua`:** "cnr_heli carries guided when a cop sees the runner". Follow the existing sight tests there.
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_helicopter.lua` and `lua tests/run.lua tests/test_main.lua`.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: each helicopter flight starts searching; the cops' sight guides it"

### Task 2: The flight's search mode

**Files:** Modify `client/lua/ge/extensions/copsAndRobbers/heliFlight.lua`. Test: `tests/test_heli_flight.lua`.

**Interfaces:**
- **`M.search(f, spot)`:** sets `f.spot = vec3(spot)` and `f.searchAngle` = the bearing of `f.pos` from the spot.
- **`M.follow(f)`:** clears `f.spot`.
- **`M.at(carPos, carVel, random, spot)`:** with `spot`, starts in search mode on its circle point at the current angle drawn as before, with velocity 0.
- **`M.target(f, carPos, carVel)`:**
  - with `f.spot` and not leaving: `spot + SEARCH_RADIUS × (cos a, sin a) + HELI_HEIGHT` up, where `a = f.searchAngle`
  - leaving still wins
- **`M.step(...)`:**
  - with `f.spot`: `f.searchAngle` advances by 2π/`SEARCH_PERIOD` × `side` × dt, and the wanted velocity is the circle point's velocity plus `FOLLOW_GAIN` × (target − pos), without `carVel`
  - the speed and acceleration limits apply as now
  - a car jump over `JUMP_METERS` also shifts `f.spot`

- [ ] **Step 1: Write the failing tests:**
  - "search circles the spot": a still spot, 120 s. From 60 s on, the horizontal distance to the spot is 60 ± 3 and the height 50 ± 2 above it, and the bearing rate is 2π/40 ± 20% with the sign of `side`.
  - "search ignores the car": the same run with the car driving away at 30 m/s gives the same positions, to 1e-9.
  - "search keeps the limits": speed ≤ 70 + 1e-6 and |Δvel| ≤ 8 × dt + 1e-6 when the spot jumps 500 m (a new spot).
  - "a car jump moves the spot": after a 2 km car jump, `f.spot` moved by the jump to 1e-9, and the step matches the run without the jump, relative to the spot.
  - "follow after search": `M.follow(f)` returns to trailing the car (the existing settle test's target within 3 m after 60 s).
  - "at with a spot starts on its circle": distance 60 ± 1e-6 from the spot, 50 up, vel 0.
- [ ] **Step 2: Run them to make sure they fail.** Run `lua tests/run.lua tests/test_heli_flight.lua`.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: the helicopter can circle a search spot"

### Task 3: Tunnel exits on the road graph

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/tunnels.lua`. Test: create `tests/test_tunnels.lua`.

**Interfaces:**
- **`M.exit(carPos, dirX, dirY, roads, roofedAt, seed) -> vec3 | nil`:** pure.
  - `roads = { closest = function(pos) return n1, n2 end, links = { [id] = { [otherId] = link } }, nodes = { [id] = { pos = {x, y, z} } } }`. These are the shapes `roads.lua` reads from `map.getGraphpath().graph` and `map.getMap().nodes`.
  - `roofedAt(pos) -> boolean`.
  - It returns nil when `roofedAt` at the car (1.5 m up) is false, or when `roads`, `closest` or the nodes are missing.
  - **The forward node:** of `n1` and `n2`, the one with the larger dot product of (node − car) with (dirX, dirY). The other one is never visited.
  - **The walk:** breadth-first through the links, only expanding roofed nodes (each node tested once, 1.5 m up). An unroofed node reached is an exit and is not expanded. The walk stops when the summed edge lengths exceed `MAX_LENGTH` or the visited count reaches `MAX_NODES`.
  - **The pick:** as in Global Constraints. It returns the chosen exit's position as a `vec3`, or nil when no exit was found.

- [ ] **Step 1: Write the failing tests in `tests/test_tunnels.lua`,** with small hand-built graphs:
  - **a straight tunnel:** nodes 1-5 on a line, 2-4 roofed. Heading towards 5 gives node 5. Heading towards 1 gives node 1 (turning around).
  - **a fork inside:** two exits. Seed 0 gives the first by id, seed 1 the second, and no seed the first.
  - **too long:** roofed for 4 km, so nil. Also 250 roofed nodes in a ring (a cycle), so nil, with no endless loop.
  - **not in a tunnel:** the car isn't roofed, so nil, and `closest` is never called.
  - **missing data:** nil `roads`, a nil `closest` result, a node missing from `nodes`: each gives nil with no error.
  - **just under a bridge:** the forward node is unroofed, so it is the exit.
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
- **Consumes:** `guided` (Task 1), `search` / `follow` / `at(..., spot)` (Task 2), `tunnels.exit` (Task 3).
- **`heli.set`:** stores `state.guided = d.guided == true`.
- **Spot lifecycle in `fly()`:**
  - **Creating a flight while up:**
    - after "arriving": spot = car
    - after "refuelling": spot = `state.lastKnown` or car
    - otherwise (join): spot = car
  - **How it's created:**
    - after "arriving" or "refuelling": `arrive(spot, …)` then `search(f, spot)`
    - a join: `at(car, carVel, random, phase == "searching" and spot or nil)`
  - **Phase changes:**
    - "tracking" → "searching": `search(f, spotFor(...))`
    - "searching" → "tracking": `follow(f)`
  - **While searching and guided:** `f.spot` is the car's position every tick (a direct assignment, not `search`, so the angle continues).
  - **Guided turning false while searching:** `search(f, spotFor(...))`.
  - **`state.lastKnown`:** the car position while tracking, or while guided.
- **`spotFor(state, car, target, opts)`:** returns `opts.tunnelExit(car, dir.x, dir.y, state.seed)` when that function exists and returns a position; otherwise the car.
- **`opts.tunnelExit`:** `copsAndRobbers.lua` passes it as a closure over `tunnels.exit`, with:
  - `{ closest = map.findClosestRoad, links = map.getGraphpath().graph, nodes = map.getMap().nodes }`, all nil-safe and resolved per call
  - `roofedAt = function(p) return shelter.roofed(p, castUp) end`
- **Cover (`coverTick(state, clock, obj, castRay)`, the `castUp` parameter removed):**
  - with a flight and `castRay`: `not shelter.inSight(f.pos, p, COVER_HEIGHT, dir, castRay, SIGHT_RANGE)`. A point further than `SIGHT_RANGE` from the helicopter isn't seen.
  - without a flight: covered = true
  - the spacing, the first report and the smoothing are unchanged
- **The flight's own protected step:**
  - `M.lightTick` first runs the flight part (`carVelocity`, `fly`, the spot lifecycle, the 8 s drop) in its own `pcall`. On an error it logs once and drops the flight.
  - Then it runs the light part (unchanged entry, without `fly`).
  - `state.failed` from the light no longer stops the flight.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_shelter.lua`:** "points beyond the range are not seen" (a free ray, a point at 401 m → false; at 399 m → true).
  - **`tests/test_heli_client.lua`:**
    - "arrival searches where the runner was"
      - "arriving" → "searching" with the car at A
      - then the car drives to B, 200 m away
      - after 60 s the helicopter circles A at 60 ± 3 m
    - "a refuel returns to the last known spot"
      - track at A
      - refuel while the car moves to B
      - come back "searching": the helicopter circles A
    - "losing the runner in a tunnel searches the exit"
      - an `opts.tunnelExit` stub returns E
      - "tracking" → "searching" makes the spot E
      - a stub that returns nil makes it the car
    - "guided follows the runner and recomputes when guidance ends"
      - while guided, `f.spot` equals the car every tick
      - guided ends: the spot comes from `tunnelExit`, called once
    - "cover is covered without a helicopter"
      - "arriving", no flight
      - the first report is true, even with a free `castRay`
    - "a light failure doesn't stop the flight"
      - `createLight` fails at night, so `state.failed` is set
      - the flight still steps and cover still casts from its moving position
    - "a flight error drops the flight and logs once"
    - adapt the existing cover, arrival, refound and searching tests to the new rules. Refound is removed; the light-on-while-searching tests are in Task 5.
  - **`tests/test_client.lua`:** "a tunnel loss sends the helicopter to the exit ahead"
    - stub `map.findClosestRoad`, `map.getGraphpath`, `map.getMap` and `castRayStatic` (roofed above nodes 2-4)
    - the runner's game with "tracking" → "searching" puts its flight's spot at node 5
    - follow the existing helicopter tests there
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run `make test` twice.** Expected: `0 failed`.
- [ ] **Step 5: Commit.** Message: "feat: the helicopter searches where it last knew the runner was"

### Task 5: The light while searching; docs

**Files:**
- Modify `client/lua/ge/extensions/copsAndRobbers/heli.lua`.
- Docs:
  - `docs/FEATURES.md` (the helicopter section: tracking, cover, searching, searchlight)
  - `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` (runner and cop helicopter items)
  - `README.md` (the config table's "tracks the runner in the open" line and any helicopter description)
  - `docs/DEPENDENCIES.md` (the road graph for tunnel exits)
- Test: `tests/test_heli_client.lua`, `tests/test_client.lua`

**Interfaces:**
- **When the light is wanted:**
  - `desired` is `(phase == "tracking" or phase == "searching") and night`
  - `M.wantsNight(state)` is true for "tracking", "searching" or an existing light
- **Removed:** `startRefound`, `REFOUND_AIM_OFFSET` and the light removal on "tracking" → "searching".
- **Aim:**
  - **While tracking:** the operator aim on the car, as now.
  - **While searching:** `M.sweepPoint(spot, t)` around `f.spot`, with t = clock − the time of the last `search(...)` call (guided updates of `f.spot` move the centre but don't reset t):
    - `r = SWEEP_RADIUS × ((t % SWEEP_PERIOD) / SWEEP_PERIOD)`, `θ = 2π × t / SWEEP_TURN`
    - returns `spot + (r cos θ, r sin θ)` at the spot's height
    - it is pure, and returned for tests
  - **On every change of target** (found, lost, a new `search(...)`; not the continuous guided updates): the aim keeps a switch offset = the previous aim point − the new target. It decays as `exp(-(clock - t0) / AIM_SWITCH_SECONDS)`, so the aim point never jumps.
- **Range and the beam's slant check:** they use the aim point instead of the car.
- **Refuel:** while searching it also starts the fly-away fade (`startDepart`), as from tracking.

- [ ] **Step 1: Write the failing tests in `tests/test_heli_client.lua`:**
  - "the light stays on while searching": at night, "tracking" → "searching". The light object is the same and its brightness factor stays 1.
  - "the sweep spirals out and starts again":
    - `sweepPoint` at t = 0 is the spot
    - at t = 20 it is 75 m out
    - at t = 39.9 it is about 150 m out
    - at t = 40 it is the spot again
    - the angle advances 2π every 8 s
  - "the aim never jumps when the target changes": over "tracking" → "searching" → "tracking" with a spot 120 m from the car, every tick moves the aim point by ≤ 150 m × dt / 0.5 + 1 m, and never by more than 0.5 × the distance between the targets in one tick.
  - "a refuel while searching flies away with the light": `leaving` is set and the brightness fades over the last 3 s.
  - "the range follows the aim point": with the sweep 150 m out, the range is the slant to the aim point + 30, rounded.
  - Adapt the existing light tests (the cut-under-cover, refound and tunnel tests) to the new rules.
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement as in Interfaces, then update the docs:**
  - **Searching:** every flight starts searching; it circles where it last knew you; tunnel exits ahead; turning around dodges it; the cops' sight guides it; it finds you only by seeing you within 400 m; the light keeps sweeping.
  - **Cover:** out of its sight for 2 s.
  - **Remove** every "in the open" wording.
- [ ] **Step 4: Run `make test` twice and `make vuecheck`.** Expected: `0 failed`, and vuecheck clean.
- [ ] **Step 5: Commit.** Message: "feat: the searchlight sweeps while the helicopter searches; docs"

### Task 6: The rotor sound

**Files:**
- Create:
  - `client/lua/ge/extensions/copsAndRobbers/heliSound.lua`
  - `client/art/sound/cnr/heli_rotor.ogg`, copied from `/tmp/claude-1000/cnr-sound/heli_rotor.ogg` (made from qubodup's CC0 "Helicopter Rotor Loop" #187681)
- Modify:
  - `Makefile` (the client zip includes `art`)
  - `client/lua/ge/extensions/copsAndRobbers.lua` (`updateHeli`, `endRound`)
  - `client/lua/ge/extensions/copsAndRobbers/heli.lua` (`M.soundLevel`)
  - `client/lua/ge/extensions/copsAndRobbers/playerSettings.lua`, `client/lua/ge/extensions/copsAndRobbers/hud.lua` (the settings payload)
  - `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue`
  - `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, How to Play's "Your settings" item
- Test: create `tests/test_heli_sound.lua`; also `tests/test_player_settings.lua`, `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- **`heliSound.new()`, `heliSound.tick(s, pos, level, clock, camPos, castRay)`, `heliSound.clear(s)`:**
  - **Making and moving it:**
    - `pos` nil or `level` ≤ 0 removes the emitter
    - otherwise it is created when missing (fields as in Global Constraints) and moved with `setPosition` every tick
  - **Volume:** `level × muffle`, written with `setVolumePitchCT(volume, 1, 0, 0)` only when it changes by more than 0.02.
  - **Muffle:**
    - every `RAY_INTERVAL`, a `castRay` from `camPos` to `pos`: blocked when the hit is shorter than the distance − 2
    - the muffle eases towards `MUFFLED` or 1 over `MUFFLE_SECONDS`
  - **Errors:** an error logs once and stops the sound for the round, like `beamFailed`.
- **`heli.soundLevel(state, clock) -> number`:**
  - 0 without a flight
  - 1 normally
  - (DEPART_SECONDS − elapsed) / DEPART_FADE_SECONDS during the fly-away's last 3 s
  - min(1, (clock − createdAt) / FADE_IN_SECONDS) for a flight made by `at` (a join)
  - `state.flight.pos` is the position
- **Setting:** `sound`, a boolean, default true.
  - The HUD switch goes after "Searchlight beam", with the same markup: name "Helicopter sound", desc "The police helicopter's rotor; heard from far off".
  - `updateHeli` passes `level = prefs.sound ~= false and heli.soundLevel(...) or 0`.
  - `endRound` and the leave/unload paths call `heliSound.clear`.

- [ ] **Step 1: Write the failing tests:**
  - **`tests/test_heli_sound.lua`,** with stubbed `createObject`, `scenetree` and `setVolumePitchCT`:
    - "the emitter is made with the file and fields, moved, and removed"
    - "level 0 and nil pos remove it"
    - "the muffle eases to half behind a wall and back"
    - "the volume is only written on a change over 0.02"
    - "an error stops the sound and logs once"
  - **Player settings and the HUD:** as for `beam`: `sound` true by default, false kept, a non-boolean rejected; the payload carries `sound`.
  - **`tests/test_client.lua`:**
    - "the sound plays at the helicopter and is gone after the round"
    - "turning the sound off removes it on the next tick"
  - **`tests/test_heli_client.lua`:** "soundLevel fades in for a join and out over the fly-away".
- [ ] **Step 2: Run them to make sure they fail.**
- [ ] **Step 3: Implement** as in Interfaces. Then the docs:
  - **README and How to Play:** four switches; describe "Helicopter sound".
  - **FEATURES:** the sound.
  - **DEPENDENCIES:**
    - the `SFXEmitter` fields and calls
    - the file's credit: "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0
    - on update, check that the sound plays in 3D and is gone after the round
- [ ] **Step 4: Run `make test` twice and `make vuecheck`, then `make` and check that `dist/Client/CopsAndRobbers.zip` contains `art/sound/cnr/heli_rotor.ogg` (`unzip -l`).**
- [ ] **Step 5: Commit** the files explicitly, the OGG included. Message: "feat: the police helicopter's rotor sound"
