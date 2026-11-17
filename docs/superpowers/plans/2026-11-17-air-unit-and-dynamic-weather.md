# Air Unit and Dynamic Weather Implementation Plan (2.10.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (2.10.0):**
- The helicopter searches like a real air unit: a road search ahead after a refuel and after losing a moving runner, containment over a stopped one, a timed watch of each way out of a tunnel, and tracking from 100 m up and 60 m to the side.
- The weather changes during a chase on a schedule the server works out in advance, the same for every game; clouds, fog, rain, wind, grip, lights and the temperature follow it, a forecast shows the next change, and storm, fog and snow ground the helicopter until it clears.

**Architecture:**
- **Part C first (no behaviour change):** the flight lifecycle moves from `heli.lua` into a new `heliSearch.lua`; one jump check; then the gap fix.
- **Part A, client only:** `heliFlight.lua` gets the new heights and a "lead" to follow; `tunnels.lua` returns an ordered list of ways out with a per-node roof cache; a new pure `roadSearch.lua` builds and flies routes; `heliSearch.lua` picks the search mode; `heli.lua` aims the light across the road.
- **Part B, server:** `cnr/climate.lua` (moved from the client) and a new pure `cnr/weather.lua` work out the day-by-day turning points and every change of the round; `cnr/sky.lua` carries them in the sky payload; `cnr/helicopter.lua` grounds and returns; records get the worst and the start weather.
- **Part B, client:** a new pure `skyChanges.lua` reads the schedule; `sky.lua` steps clouds and fog, moves the temperature curve, cross-fades the wind and drives rain and grip; `surfaces.lua` blends grip; the HUD shows notices and the forecast.

**Tech Stack:** Lua (server: Lua 5.3; client: LuaJIT in game, Lua 5.x in tests), Vue 3. `make test`, `make vuecheck`, `make package`.

**Spec:** `docs/superpowers/specs/2026-11-17-air-unit-and-dynamic-weather-design.md`. It is binding for every rule and number. The game's Lua (read only) is at `~/.local/share/Steam/steamapps/common/BeamNG.drive/lua/`.

## Global Constraints

- **Style:** no code comments, no emojis; Lua module table `M`, camelCase locals; follow the surrounding files.
- **Branch:** no version bump; never edit `TODO.md` (main only). The spec's In-game check list goes to main's `TODO.md` after the merge (the controller's job).
- **Lua:**
  - No `goto`, `//` or bit operators.
  - In the pure client modules, build vectors with `vec3(x, y, z)` from numbers only; the test stub `vec3` has no operators.
  - Never test a position with `type(v) == "table"` (`vec3` is cdata in game); read `x`, `y`, `z` and check they are numbers.
  - Call sibling modules through their module table (`flight.step`, `tunnels.watch`, `roadSearch.routes`) so tests can replace or count them.
- **No new network message.** The schedule rides in the sky payload (`cnr_roundSetup`'s `sky` and `cnr_sky`); grounding rides in `cnr_heli`.
- **Determinism:** the server's seeds and the round clock (seconds since the countdown started, `clockSeconds`) decide; each game computes from the payload. Park–Miller (`x = x * 16807 % 2147483647`, `x / 2147483647`), as `heliFlight.seeded`.
- **Game time** (checked in the game source): 0 is noon, 0.5 midnight; 06:00 = 0.75, 09:00 = 0.875, 14:00 = 2/24, 18:00 = 0.25. The curve override is `{ {time, °C}, ... }` with strictly increasing times in [0, 1]; the game interpolates linearly and wraps from the last point to the first (`core/environment.lua` `normalizeTemperatureCurve`, `getCurveTemperatureC`).
- **The environment lock (anti-goal):** every mid-round environment write is `enableChanges(true)`, one instant `setState(...)` (no seconds), `enableChanges(false)`, inside a `pcall` that always relocks. Mid-round writes never carry `time`, `play`, `dayLength`, `year`, `month` or `day`.
- **Not verified in game, so fail safe:** the curve-only `setState` mid-round and `be:setGroundModel` pushes while driving. An error logs once (`log("E", "cnr_sky", ...)`) and stops that part for the round; the round goes on.
- **Part A numbers:**
  - `heliFlight.lua`: `FOLLOW_BACK = 40`, `FOLLOW_SIDE = 60`, `HELI_HEIGHT = 100`, `ORBIT_RADIUS = 80`, `SEARCH_RADIUS = 120`, `APPROACH_HEIGHT = 120`, `DEPART_DISTANCE = 600`, `DEPART_HEIGHT = 150`; unchanged: `MAX_SPEED = 70`, `MAX_ACCEL = 8`, `FOLLOW_GAIN = 0.4`, `JUMP_METERS = 30`, the periods and the hysteresis
  - `heli.lua`: `BRIGHTNESS = 160`; range max(120, slant + 30) capped at 400, as now
  - `heliSearch.lua`: `SEARCH_MOVING_SPEED = 5`, `WATCH_MIN_SPEED = 10`, `WATCH_FACTOR = 1.5`, `WATCH_MIN = 15`, `WATCH_MAX = 90`, `GUIDED_CHECK_SECONDS = 1`
  - `roadSearch.lua`: `MAX_ROAD_DISTANCE = 15`, `AHEAD_LENGTH = 2500`, `ALT_LENGTH = 1500`, `ALT_WITHIN = 500`, `BACK_LENGTH = 1000`, `MAX_NODES = 200`, `SEARCH_SPEED = 45`, `WAIT_RADIUS = 150`, `AIM_AHEAD = 60`, `AIM_SIDE = 15`, `AIM_PERIOD = 3`
  - `tunnels.lua` keeps `MAX_LENGTH = 3000`, `MAX_NODES = 200`, `MAX_ROAD_DISTANCE = 15`, `ROOF_HEIGHT = 1.5`, edge lengths from node positions (3D), never the graph's `len`
- **Part B numbers:**
  - `CHANGE_SECONDS = 60`, `DRY_SECONDS = 180`, `WINDOW_SECONDS = 120`, `HORIZON_SECONDS = 10800`, the client's `STEP_SECONDS = 0.5`, grip `STEP = 0.05` (the in-game fallback is 0.2, 5 steps a change)
  - thresholds: snow at T ≤ 1, rain at T ≥ 2, warm day at a high ≥ 15, foggy at T ≤ 12 between 18:00 and 09:00
  - turning points at 06:00 (lows) and 14:00 (highs); day 0's shift uniform(−4, 4), each next day + uniform(−3, 3) within ±6
  - settings: `weatherChanges` true, `weatherChangeMinMinutes` 3, `weatherChangeMaxMinutes` 8 (whole minutes, at least 1)
  - grounding weathers: storm, fog, snow; worst order clear 0 < cloudy 1 < rain 2 < fog 3 = snow 3 < storm 4
- **Kept:** the 2 s loss, sight 400 m by line of sight day and night, the cops' guidance, the instant re-acquire, the sound, the beam and its setting; nothing is left after a round, cancel, leave, map change or unload.

## Review Focus

1. **A weather change while the helicopter refuels, flies in or flies away, and chains of changes** (storm → rain → snow at once). The server goes refuelling → grounded → arriving; the reason moves from storm to snow without a return in between; every game flies an up helicopter away and never drops it in mid-air. Pinned in Tasks 12 and 13.
2. **Joining, New sky or GO during a change or a blend.** A joiner mid-change gets the in-between clouds, fog, grip and curve; a step never cancels the 3 s round blend or leaves the environment unlocked. Pinned in Tasks 15 and 16.
3. **Settings at their edges:** min = max, min 1 (a crossing deferred to a blend end lands on a slot), no time limit (180 min), Day length Off (no turning point and no 09:00 ever passes). Bounded, deterministic schedules with intervals inside [min, max]. Pinned in Tasks 9 and 11.
4. **Road data that is missing, cyclic, a dead end, a junction maze, a road just over 15 m away, or a car jump mid-search.** Routes stay bounded, the search falls back to containment and nothing loops. Pinned in Tasks 4, 5 and 6.
5. **A cop's sight flickering at a tunnel mouth, U-turns inside, guidance ending again and again.** At most one walk a second, node roofs from the cache, no ray storms, the helicopter never hovers over the roof. Pinned in Tasks 4 and 7.

## Calls this plan makes (where the spec leaves a choice)

- **Payload:** the sky payload also carries `gameStart` (the server's start game time) and `releaseAt` (the release on the round clock); `temps` entries are `{ t = days from gameStart, hour = 6 | 14, c = °C }`; crossing changes carry `cross = true`. `temps` is sent whenever the sky has a weather, also with Weather changes off (the table now lives only on the server).
- **The client's curve:** turning points are placed on the game's own clock (`wrapHalf(clockStart − gameStart) + roundTime / daySeconds`), so the curve moves on exactly when the game's time passes a turning point, even when the solar start differs from the server's table time.
- **Crossings:** from the release, the moment a weather stops fitting; at the end of every change, a weather that does not fit crosses then (this gives storm → rain → snow). A start weather that does not fit at the release (fog at noon) is not crossed until it has fitted and stops fitting; its first regular change still comes.
- **Fitting:** snow while T < 2; rain and storm while T > 1; fog while T ≤ 12 and the time is in [18:00, 09:00); clear and cloudy always. Sunset is 18:00 for the foggy window.
- **"That day's high"** is the higher of the two turning points around the moment. A high is at least the low before it + 2 °C (as `climate.range`). A snow start's shift is min(draw, 0). The two points around the start are day 0; each later 06:00 starts the next day.
- **Draw order:** all day shifts first (day 0 first); then per change in time order: the pick (none for snow → rain, rain → snow, storm → rain), the forecast offset, the interval to the next slot. A pick is `options[floor(r × n) + 1]` over the spec table's order, filtered. Crossings are found by a 1 s scan with linear refinement; 09:00 is solved exactly.
- **In effect:** the weather in effect at a moment is the `to` of the last change with `at` ≤ that moment. Records count a change once started; a fog/snow tie keeps the first.
- **Tunnel candidates:** the walk's tree path to each way out; the turn sum starts from the car's direction; ties by node id (as strings), the tied group rotated by `seed % n`; the walk behind gets its own budget and all its ways out come after the ahead ones. A watched candidate is circled and swept like a containment spot. After the last one: a road search from its node outward, whatever the speed.
- **Routes:** caps measured along each route from its start, the last segment clipped at the cap; a visited set per route; route 2 starts at its junction.
- **Guided in a tunnel:** the car's roof and closest edge are read at most once a second; the walk reruns only on an edge or direction change.
- **One jump rule:** a car jump shifts the flight, the spot, the lead, `lastKnown`, the search origin, the road run and the tunnel candidates.
- **Blends:** grip progress is linear; clouds, fog, cloud wind speed (`windSpeed`) and ground wind use smoothstep. A joiner mid-change sets rain to the old weather at once, then fades to the new one over the time left.
- **Wording:** see Task 14 (notices, forecast words, "within N min").
- **`flew()`** is "was ever up", so a round that ends before the first arrival records no helicopter.

---

### Task 1: Split the flight lifecycle into `heliSearch.lua`; one jump check (Part C)

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heliSearch.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/heli.lua` (move `carVelocity`, `dropFlight`, `fly`, `finite`, `exitAhead`, `spotFor`, `retarget`, `flightTick` at 363-523 and `soundLevel` at 636-643), `heliFlight.lua` (`step`'s jump check)
- Test: `tests/test_heli_client.lua`, `tests/test_heli_flight.lua` (add `"copsAndRobbers/heliSearch"` to the load lists; new tests below)

**Interfaces:**
- **Produces:**
  - `heliFlight.jumpOf(last, pos) -> jx, jy, jz | nil`: `pos − last` when its 3D length is over `JUMP_METERS`; nil when `last` is nil or it is not. `step` uses it on `f.lastCar`.
  - `heliSearch.tick(state, target, phase, last, clock, opts)`: today's `flightTick`, with the moved functions as locals and unchanged behaviour.
  - `heliSearch.drop(state)`: `state.flight`, `state.leftAt`, `state.flightRandom` to nil; never touches the light (today's `dropFlight` removed it; the light part already removes a light without a flight on the same tick).
  - `heliSearch.clear(state)`: resets `flight`, `leftAt`, `lastClock`, `lastCar`, `carVel`, `flightRandom`, `lastKnown`, `wasGuided`, `sweepAt`, `retargetAt`, `missingSince`, `tunnelLogged`, `flightFailed`, `jumpAt`.
  - `heliSearch.soundLevel(state, clock)` and `heliSearch.TARGET_MISSING_SECONDS = 2`, moved.
  - `state.jumpAt`: the clock of the last car jump, set where `carVelocity` today clears `state.sweepRayAt`.
- **`heli.lua` keeps** `set`, cover, the light, aim, sweep, beam, `wantsNight`, the two-part `pcall` in `lightTick` (its flight part calls `heliSearch.tick`, and `heliSearch.drop` on an error, still setting `flightFailed` and logging once with `flightLogged`) and `clear` (calls `heliSearch.clear`, then resets its own fields). It re-exports `M.soundLevel` and `M.TARGET_MISSING_SECONDS`.
- **The aim:** `aimStep` uses `flight.jumpOf(aim.lastCar, carPos)` and stores `z` in `aim.lastCar`, so all three checks agree (a vertical-only jump over 30 m now also resets the aim).
- **The sweep ray:** `sweepAim` also re-casts when `state.jumpAt ~= state.sweepRayJump`, then stores it.

- [ ] **Step 1: Write the failing tests:**
  - `test_heli_flight.lua` "jumpOf reports a jump over 30 m in 3D": nil without `last`; (0,0,0)→(29,0,0) nil; →(31,0,0) gives 31, 0, 0; →(0,0,31) gives 0, 0, 31; →(20,20,10) (30 m) nil.
  - `test_heli_client.lua`:
    - "the three jump checks agree on a vertical jump": "tracking" at night, then the car 40 m straight up in one tick: the helicopter's position equals a run without the jump plus 40 m up (1e-9), `state.jumpAt` is that clock, and `state.aim.velKnown` is false after the tick.
    - "a car jump re-casts the sweep's ground ray on the next tick": searching at night with a counting `castRayStatic`; a 2 km jump 0.1 s after a ray: one downward ray on the next tick.
    - "dropping the flight leaves the light to the light part": `heliSearch.drop(state)` with a light up: `state.light` still set, `state.flight` nil; after one `lightTick`, no light object.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_heli_flight.lua tests/test_heli_client.lua`. Expected: the new tests fail.
- [ ] **Step 3: Implement** as in Interfaces. Move code; change nothing else.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`. `git diff tests/` shows only load-list lines and the new tests.
- [ ] **Step 5: Commit:** "refactor: the helicopter's flight lifecycle moves into heliSearch.lua; one jump check"

### Task 2: A gap in the runner's car is not a jump (TODO issue)

**Files:** Modify `heliSearch.lua`. Test: `tests/test_heli_client.lua`.

**Interfaces:** in `heliSearch.tick`, on the first tick with a target after `state.missingSince` was set: `state.lastCar = nil` and, with a flight, `f.lastCar = vec3(car.x, car.y, car.z)` before it steps. No shift, `state.jumpAt` unchanged.

- [ ] **Step 1: Write the failing test** "the car coming back 200 m away after a gap moves nothing": a cop's game searching with spot S and `lastKnown` K; the target nil for 3 s; then the car 200 m from where it was: `f.spot` is S and `lastKnown` K (1e-9), the helicopter moved at most 70 × dt on that tick, `state.jumpAt` nil. The existing "a car jump moves the last known spot" stays as the guard that a jump without a gap still shifts.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_heli_client.lua`. Expected: FAIL (the spot moved by 200 m).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "fix: the runner's car coming back after a gap no longer reads as a jump"

### Task 3: Higher tracking, and a lead to follow

**Files:** Modify `heliFlight.lua`, `heli.lua` (`BRIGHTNESS`). Test: `tests/test_heli_flight.lua`, `tests/test_heli_client.lua`, `tests/test_client.lua`.

**Interfaces:**
- The Part A flight constants and `BRIGHTNESS = 160` (Global Constraints).
- **Produces `heliFlight.lead(f, pos, vel)`:** `f.lead = vec3(pos)`, `f.leadVel = vec3(vel)`, `f.spot` and `f.spotVel` nil. Called every tick by Task 6 (a direct assignment, like the guided spot).
- **`target`:** leaving wins; then the spot circle; then, with `f.lead`, the follow offsets from the lead with `headingOf(f.leadVel, f.headingX, f.headingY)` and `HELI_HEIGHT` above it; then circle and follow as now.
- **`step` with `f.lead`, not leaving:** heading from `leadVel`; wanted = `FOLLOW_GAIN` × (target − pos) + `leadVel`; no circle/follow switch, no orbit. A car jump also shifts `f.lead`. `search` and `follow` clear `f.lead` and `f.leadVel`.

- [ ] **Step 1: Write the failing tests** (`test_heli_flight.lua`):
  - "tracking settles 40 m back, 60 m to the side, 100 m up": a car at 30 m/s in +x for 60 s; `f.pos − car` within 3 m of (−40, 60 × side, 100).
  - "a stopped car is circled at 80 m and a search spot at 120 m", heights 100 ± 2.
  - "arrive starts 300 m out and 120 m up; leave aims 600 m out and 150 m up".
  - "the new heights keep the limits": speed ≤ 70 + 1e-6 and |Δvel| ≤ 8 × dt + 1e-6 while a 30 m/s car turns 90°.
  - "a lead is followed like a car": a lead at 45 m/s in +x for 60 s: (−40, 60 × side, 100) ± 3 from it.
  - "a lead that jumps 1 km keeps the limits"; "a car jump shifts the lead"; "search and follow clear the lead".
  - **Adapt** the 2.9.4 literals to the constants: in `test_heli_flight.lua` the radii 30 and 60, the heights 50 and 60, the leaving 400/80; in `test_heli_client.lua` `brightness` 80, 60 ± 3 circles, 50 heights, the 400 m leaving point; in `test_client.lua` the tunnel test's 60 ± 3. Keep every tolerance; where a settle needs longer at the larger distances, lengthen the run, never widen the tolerance.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_heli_flight.lua`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the helicopter tracks from 100 m up and 60 m to the side, and can follow a search point"

### Task 4: Every way out of a tunnel, in order, with cached roofs

**Files:** Modify `tunnels.lua`, `client/lua/ge/extensions/copsAndRobbers.lua` (`tunnelExit`). Test: rewrite `tests/test_tunnels.lua`.

**Interfaces:**
- **Produces `tunnels.watch(carPos, dirX, dirY, roads, roofedAt, seed, cache) -> list | nil`** (replaces `M.exit`, which goes):
  - **nil** in every case `exit` returned nil before walking (car not roofed, missing data, no closest node, a distance missing or over 15 m, a bad position).
  - **`{}`** when the car is roofed but neither walk finds a way out within its caps.
  - **Entries:** `{ id = nodeId, pos = vec3, from = parentId or nil, length = meters, turn = radians, behind = true or nil }`.
  - **The walks:** ahead from the forward node (the 2.9.4 rule) with the back node marked visited; behind from the back node with the forward node marked visited. Each is the 2.9.4 breadth-first walk with its own `MAX_LENGTH`/`MAX_NODES` budget, recording each node's parent.
  - **`length`:** the 3D distance from the car to the first node plus the edge lengths along the tree path.
  - **`turn`:** the summed absolute 2D angles between consecutive directions along the path, starting from (dirX, dirY) for ahead and its reverse for behind; with a zero direction the first edge adds nothing.
  - **Order:** ahead by `turn`, then behind by `turn`. Entries within 1e-6 rad form a tie group, sorted by id as strings and rotated by `seed % n` (no seed: no rotation).
  - **`cache`** (optional, `{ [nodeId] = boolean }`) keeps each node's roof result; a cached node calls no `roofedAt`. The car's own check is never cached.

- [ ] **Step 1: Write the failing tests,** keeping the 2.9.4 scenarios (`closest` returns a distance of 2 unless stated):
  - **straight tunnel** (nodes 1-5 at x = 0, 100, ..., 400, 2-4 roofed, the car at x = 150): heading +x gives `{5, 1}` with lengths 250 and 150 (± 1e-6) and `behind` on 1; heading −x gives `{1, 5}`.
  - **fork ahead:** a straight branch and a 30° branch: the straight exit first. **A symmetric fork** (±30°): seed 0 gives the lower id first, seed 1 the other.
  - **too long / ring / lengths from positions / a road too far (16 nil, 14 found, none nil) / not in a tunnel (closest never called) / missing data / just under a bridge / no direction:** as in 2.9.4, now on `watch`. Too long and the ring give `{}`.
  - **"a second walk with the same cache tests only the car's roof":** count `roofedAt` calls: the first walk tests every reached node; a second walk from 10 m further on calls it once.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_tunnels.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Until Task 6 replaces it, `copsAndRobbers.lua`'s `tunnelExit` returns `watch(...)[1].pos` (nil when nil or empty), so the 2.9.4 flow keeps working.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the tunnel walk returns every way out in order and caches node roofs"

### Task 5: Road search routes (`roadSearch.lua`, pure)

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/roadSearch.lua`, `tests/test_road_search.lua`.

**Interfaces (Produces):**
- **`roadSearch.routes(origin, dirX, dirY, roads, seed) -> list`** (`roads` as in `tunnels.watch`). Empty when `roads` or a part is missing, or `closest` gives no node or a distance missing or over 15 m. A route is `{ points = { vec3, ... }, dist = { cumulative meters }, length = meters }`.
  1. **Ahead:** the origin, then the forward node (the larger dot product with the direction, `n1` on a tie), then at each node the straightest continuation (smallest |turn| from the incoming direction), skipping the node it came from and nodes this route visited. Ties go by node id as strings, the tied group rotated by `seed % n`. It stops at `AHEAD_LENGTH` (the last segment clipped there), a dead end, or `MAX_NODES` nodes.
  2. **Alternative:** at the first node of route 1 within `ALT_WITHIN` of the origin (along the route) with two or more continuations, the second in that order. It starts at that junction and is walked the same way up to `ALT_LENGTH`. None without such a junction.
  3. **Back:** the origin, the other node, then walked the same way up to `BACK_LENGTH`.
- **`roadSearch.newRun(routes) -> run`**, **`roadSearch.step(run, heliPos, dt) -> pos, vel | nil`:**
  - the search point moves along the current route at `SEARCH_SPEED`, `vel` along the route
  - at a route's end the next route starts with `pos` at its start and `vel` 0 until the helicopter is within `WAIT_RADIUS` (horizontal)
  - a route under 1 m long is dropped from the list
  - nil once every route is done
- **`roadSearch.aimPoint(run, t) -> x, y, z`:** the route point `AIM_AHEAD` m ahead of the search point (clamped at the route's end), plus `AIM_SIDE` × sin(2π t / `AIM_PERIOD`) along the left normal of the route there; `z` is the route's.
- **`roadSearch.shift(run, jx, jy, jz)`:** moves every route point.

- [ ] **Step 1: Write the failing tests,** on hand-built graphs:
  - "the ahead route goes straight through a crossroads", and "ties at a symmetric fork go by id, then the seed"
  - "the alternative is the other branch at the first junction within 500 m": a junction at 300 m gives route 2 from it down the other branch; one at 600 m gives no route 2
  - "the back route walks the other way": its second point is the back node
  - "the caps": a 5 km straight road in 100 m segments gives lengths 2500, 1500 (a branch at 100 m) and 1000, to 1e-6; 10 m segments stop route 1 at 200 nodes (length 1990 ± 1e-6)
  - "no road within 15 m means no routes": a distance of 16, and nil data
  - "the same input gives the same routes", point by point
  - "a ring road ends": a 20-node ring gives a route of at most 20 points
  - "the search point moves at 45 m/s and waits within 150 m": `step` moves it 45 × dt; at route 1's end it stays at route 2's start while the helicopter is 300 m away, and moves on once it is at 140 m; nil after the last route
  - "aimPoint is 60 m ahead with a 15 m sweep across": a straight +x route, the point at 100 m: `aimPoint(run, 0.75)` is (160, 15, z) and `aimPoint(run, 0)` (160, 0, z), to 1e-6
  - "shift moves the routes"
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_road_search.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: road search routes ahead, along the best other branch and back"

### Task 6: The search modes after a loss, an arrival or a refuel

**Files:**
- Modify: `heliSearch.lua`, `heli.lua` (`startDepart`'s reference), `client/lua/ge/extensions/copsAndRobbers.lua` (`tunnelExit` becomes the `opts.roads` and `opts.roofedAt` wiring)
- Test: `tests/test_heli_client.lua`, `tests/test_client.lua`

**Interfaces:**
- **Consumes:** `flight.lead` (Task 3), `tunnels.watch` (Task 4), `roadSearch.*` (Task 5).
- **`opts.roads() -> { closest, links, nodes } | nil`** (resolved per call, nil-safe without `map`) and **`opts.roofedAt(pos)`** (`shelter.roofed` with `castUp`, only when `castRayStatic` exists). `opts.tunnelExit` goes.
- **`state.lastKnownVel`** is stored with `state.lastKnown` (tracking and guided ticks), shifted by nothing on a jump, cleared by `clear`. **`state.roofCache`** is the node roof cache, reset by `clear`.
- **`state.search = { mode = "contain" | "tunnel" | "road", origin = vec3, speed, list, i, since, run }`**, nil while tracking or guided.
- **`choose(state, f, pos, vel, target, clock, opts)`** (local):
  - the direction is `vel` when its horizontal speed is above 1 m/s, otherwise the live target's facing when `pos` is the live car, otherwise (0, 0); the speed is `vel`'s horizontal speed
  - `tunnels.watch(pos, dirX, dirY, opts.roads(), opts.roofedAt, state.seed, state.roofCache)`: a non-empty list gives **tunnel** (`search(f, list[1].pos)`, `i = 1`, `since = clock`); `{}` gives **contain**
  - nil and the speed at least `SEARCH_MOVING_SPEED` with routes from `roadSearch.routes(...)`: **road** (`run = newRun(routes)`)
  - otherwise **contain** (`search(f, pos)`)
  - in a `pcall`: an error logs once per round (`tunnelLogged`, "helicopter search failed: ...") and gives contain
  - always sets `state.sweepAt` and `state.retargetAt` to `clock`
- **`M.watchSeconds(length, speed)`** = clamp(length / max(speed, `WATCH_MIN_SPEED`) × `WATCH_FACTOR`, `WATCH_MIN`, `WATCH_MAX`).
- **Phase "searching", a flight not leaving.** The first that applies:
  1. lost (`last == "tracking"`): guided → circle the live car (2.9.4); otherwise `choose` from the car
  2. guidance starting: circle the live car
  3. guidance ended: `choose` from the car
  4. not guided and no `state.search`: `choose` from `state.lastKnown`/`lastKnownVel`, or the car
- **Then every tick:**
  - guided: as 2.9.4 (`f.spot`/`f.spotVel` the car, `lastKnown`/`lastKnownVel`), `state.search = nil`
  - tunnel: once `clock − since ≥ watchSeconds(list[i].length, speed)`, take the next (`search(f, pos)`, `since = clock`, `sweepAt`/`retargetAt`). After the last: routes from its `pos` with the direction from `nodes[from]` to it (or the old direction without `from`) → road, else contain there.
  - road: `roadSearch.step(run, f.pos, dt)` → `flight.lead(f, pos, vel)`; nil → contain at `origin` (`search(f, origin)`, `retargetAt = clock`)
- **Flight creation:** `fly()` only makes the flight (`arrive(car, random, carVel, origin)` after "arriving" or "refuelling", `at(car, carVel, random, origin)` otherwise), with `origin = not guided and lastKnown or car`; rule 4 then picks the mode on the same tick. So the first arrival uses the car, a refuel the last known state, a joiner the car.
- **Tracking:** with `f.spot` or `f.lead`, `follow(f, car, carVel)`; `state.search = nil`; store `lastKnown`/`lastKnownVel`.
- **A car jump** also shifts `state.search.origin`, `roadSearch.shift(run, ...)` and every candidate's `pos`.
- **The leaving reference** (`leave` in `fly`, `startDepart` in `heli.lua`) is `f.spot or f.lead or car`.

- [ ] **Step 1: Write the failing tests** in `test_heli_client.lua` (a `roads` helper builds graphs; `roofedAt` stubs roof chosen nodes):
  - "a moving runner lost on a road gets a road search ahead": a straight +x road, the car at 10 m/s: "tracking" → "searching" gives mode "road"; over 10 s `f.lead` moves +x at 45 ± 0.5 m/s; `f.spot` nil
  - "a runner under 5 m/s gets containment at the car": 4 m/s → "contain", `f.spot` the car
  - "under a roof with a way out gives a tunnel watch at the first candidate"
  - "the watch moves on after its time, then searches the road out of the last candidate": the straight tunnel, the car at 20 m/s: `f.spot` is node 5 until `watchSeconds(250, 20)` = 18.75 s, then node 1 until `watchSeconds(150, 20)` = 15 s more, then mode "road" from node 1 heading −x
  - "watchSeconds": (100, 0) = 15, (1000, 20) = 75, (3000, 10) = 90, (50, 30) = 15
  - "the first arrival chooses from the runner's car when it goes up": "arriving" → "searching" with the car at 20 m/s on the road gives "road" from the car
  - "a refuel chooses from the last known state": tracking at A at 20 m/s +x; "refuelling" 10 s while the car drives off and stops; "searching": mode "road", route 1 starting at A
  - "guidance overrides every mode": a road search, then guided: `f.lead` nil, `f.spot` the car each tick, `state.search` nil; guidance ends: `choose` from the car
  - "no road data gives containment"; "a failing roads() logs once over two losses and gives containment"
  - "after the last route it contains at the origin": a 100 m dead end; once `step` returns nil, mode "contain" and `f.spot` the origin
  - "a 2 km car jump shifts the road search with the car"
  - **Adapt** the 2.9.4 `tunnelExit` tests ("losing the runner in a tunnel searches the exit", "the tunnel direction is the car's velocity above 1 m/s, otherwise its facing", "guided follows the runner and recomputes when guidance ends", "a refuel while searching far away flies away from the spot", "the aim never jumps when the target changes") to `opts.roads`/`opts.roofedAt` graphs that give the same spots; assert on `f.spot`, not on stub arguments.
  - `test_client.lua` "a tunnel loss sends the helicopter to the exit ahead": circles node 5 (120 ± 3 m) at 15 s, and node 1 after node 5's watch time.
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_heli_client.lua tests/test_client.lua`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test` twice.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the helicopter picks a road search, containment or a timed tunnel watch"

### Task 7: Guided while the runner is in a tunnel

**Files:** Modify `heliSearch.lua`. Test: `tests/test_heli_client.lua`.

**Interfaces:**
- **While guided,** at once when guidance starts and then at most once per `GUIDED_CHECK_SECONDS` (`state.guidedCheckAt`; reset by `clear` and when guidance ends):
  - `roofed = opts.roofedAt(car + ROOF_HEIGHT up)`; the edge key from `roads.closest(car)` = the two ids sorted as strings, plus the sign of the direction (as `choose`) dotted with second − first
  - roofed and (the key changed or no walk yet): `tunnels.watch(...)` with the cache; `state.guidedExit = list[1] and list[1].pos or nil`; `state.guidedKey = key`
  - not roofed: `state.guidedExit = nil`
- **Applying:**
  - with `guidedExit`: `f.spot = guidedExit`, `f.spotVel = 0`
  - otherwise the live car (2.9.4)
  - when the exit appears, moves or goes: `search(f, newSpot)`, `sweepAt`/`retargetAt = clock`
- **Guidance ending inside:** rule 3 of Task 6 (`choose` from the car), which gives the timed watch.

- [ ] **Step 1: Write the failing tests** (the straight tunnel; the car between nodes 2 and 3):
  - "guided in a tunnel goes to the exit ahead, not above the runner": heading +x, guided: within 1 s `f.spot` is node 5 and stays there while the car moves inside
  - "a U-turn the cop sees flips it to the other end": the velocity flips to −x: within 1 s `f.spot` is node 1
  - "a branch moves it to that branch's exit": a fork; the car on the branch edge
  - "the walk runs at most once a second, and only on an edge or direction change": count `tunnels.watch` calls over 5 s on one edge (1), with a direction flip every 0.2 s (at most 6)
  - "a redone walk tests only the car's roof": after the first walk, each later walk adds one `roofedAt` call (the car's) on top of the once-a-second check
  - "guidance flickering 10 times in the tunnel tests the nodes once": `roofedAt` calls for nodes stay at the first walk's count
  - "back in the open it circles the live position", and "a tunnel with no exit within the caps circles the live position"
  - "guidance ending inside starts the timed watch from that moment": mode "tunnel", `list[1]` the exit ahead of the current direction
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_heli_client.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: guided in a tunnel, the helicopter waits at the exit ahead"

### Task 8: The light sweeps across the road ahead

**Files:** Modify `heli.lua` (`aimAt`, `sweepAim`), `heliSearch.lua`. Test: `tests/test_heli_client.lua`.

**Interfaces:**
- **Produces `heliSearch.roadAim(state, clock) -> x, y, z | nil`:** `roadSearch.aimPoint(state.search.run, clock − state.sweepAt)` while the mode is "road" and the run is not done; nil otherwise.
- **`aimAt`:** a road aim is used before the spot sweep. Its height is the ground ray below (x, y) from `z` (the 2.9.4 `groundBelow` with `z` as the reference), cast every `SWEEP_RAY_INTERVAL`, on a new `sweepAt` and after a jump. The fly-away drift and the switch offset apply as now (every mode change sets `retargetAt`).

- [ ] **Step 1: Write the failing tests:**
  - "on a road search the light aims 60 m ahead and sweeps 15 m across": a straight +x road at night; for 6 s each tick's aim point is 60 ± 1 m ahead (x) of `f.lead` and at y = road y + 15 sin(2π (clock − sweepAt) / 3) ± 0.5
  - "the road aim sits on the ground": downward rays returning 108 give the route's z − 8; at most 10 rays in 2 s
  - "switching from tracking to a road search doesn't jump the aim": on the switch tick the aim moves less than 1 m, and every tick stays within the bound of "the aim never jumps" with the road aim's speed (45 + 2π × 15 / 3 ≈ 76.5 m/s) in place of 126
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the searchlight sweeps across the road ahead on a road search"

### Task 9: The weather change settings

**Files:**
- Modify: `server/CopsAndRobbers/cnr/config.lua`, `client/ui/modules/apps/CopsAndRobbersPanel/settings.js` (Sky group)
- Test: `tests/test_config.lua`, `tests/test_panel.lua`

**Interfaces:**
- **`config.DEFAULTS`:** `weatherChanges = true`, `weatherChangeMinMinutes = 3`, `weatherChangeMaxMinutes = 8`. Both minute keys go into `WHOLE` and `strictlyPositive` (whole numbers of at least 1).
- **`merge`:** max below min warns `"weatherChangeMaxMinutes (%s) is below weatherChangeMinMinutes, using %s"` and raises max to min.
- **`setValue`:** after setting either key, when max < min it sets max = min in `updated` (a clamp, not a refusal; the copSpawn pair keeps its refusal).
- **Panel items after "Weather affects driving":**
  - `{ key: "weatherChanges", label: "Weather changes", kind: "bool", help: "The weather changes during the chase when the day allows it" }`
  - `{ key: "weatherChangeMinMinutes", label: "Shortest between changes", unit: "min", step: 1, min: 1, when: v => v("weatherChanges"), help: "The least time between two weather changes" }`
  - `{ key: "weatherChangeMaxMinutes", label: "Longest between changes", unit: "min", step: 1, min: 1, when: v => v("weatherChanges"), help: "The most time between two weather changes; never below the shortest" }`

- [ ] **Step 1: Write the failing tests:**
  - "weather changes default on, every 3 to 8 minutes"
  - "the minutes are whole and at least 1": 0, 1.5, −1 and "x" each give the default and a warning
  - "a max below the min is raised to the min": `merge({ weatherChangeMinMinutes = 5, weatherChangeMaxMinutes = 2 })` gives 5 and 5 with the warning
  - "setValue raises the max with the min, and clamps a lowered max": `setValue({ weatherChangeMaxMinutes = 4 }, "weatherChangeMinMinutes", "6")` gives 6/6; `setValue({ weatherChangeMinMinutes = 5 }, "weatherChangeMaxMinutes", "2")` gives max 5
  - `test_panel.lua` "applyValues raises the weather change max to the min": `{ weatherChangeMinMinutes = 10, weatherChangeMaxMinutes = 5 }` saves 10/10
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_config.lua tests/test_panel.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test` and `make vuecheck`.** Expected: `0 failed`, vuecheck clean.
- [ ] **Step 5: Commit:** "feat: settings for weather changes and the time between them"

### Task 10: The server's climate and the round's turning points

**Files:**
- Create: `server/CopsAndRobbers/cnr/climate.lua` (the client's table and `range`, moved; the client copy stays until Task 15), `server/CopsAndRobbers/cnr/weather.lua`, `tests/test_weather.lua`
- Modify: `server/CopsAndRobbers/cnr/sky.lua` (`DAY_SECONDS` moves to `weather.lua`; `sky.DAY_SECONDS = weather.DAY_SECONDS`), `tests/test_climate.lua` (requires `cnr.climate`)

**Interfaces (Produces):**
- **`climate.range(weather, month)`** as today. **`climate.normal(month) -> low, high`**; **`climate.offset(weather) -> lowOffset, highOffset`** (snow gets cloudy's).
- **`weather.DAY_SECONDS`**, `KEY_TIME = { sunrise = 0.775, morning = 0.825, noon = 0, afternoon = 0.175, sunset = 0.245, night = 0.5 }`, `START_LEAD = 1/24`, `LEAD_SECONDS = 75`, `HORIZON_SECONDS = 10800`.
- **`weather.seeded(seed) -> fn`**, as `heliFlight.seeded`.
- **`weather.releaseAt(cfg)`** = `runnerCountdownSeconds + headStartSeconds`. **`weather.endAt(cfg)`** = releaseAt + (`roundTimeLimitSeconds` > 0 and it or `HORIZON_SECONDS`).
- **`weather.gameStart(s, cfg)`** = (`KEY_TIME[s.time]` − lead) % 1, lead = min(`START_LEAD`, `LEAD_SECONDS` / ds) with ds = `DAY_SECONDS[cfg.dayLength]`, and 0 when ds is nil (as the client's `roundState`).
- **`weather.climate(s, cfg, random) -> c | nil`** (nil without `time`, `weather` or a known `month`):
  - `c = { gameStart, daySeconds, month, start, points, shifts }`
  - **`points[j] = { t, hour, day, c }`:**
    - `t` (days from `gameStart`): `points[1]` is the last 06:00 or 14:00 at or before the start (t ≤ 0); then alternately +1/3 (06 → 14) and +2/3 (14 → 06)
    - the list runs until a point at or after `endAt / ds + 0.25`; only two points when ds is nil
    - `hour` is 6 or 14
    - `day`: 0 for points 1 and 2; later, +1 at each 06:00
  - **`shifts[d]`** (all days drawn first, day 0 first): `shifts[0] = −4 + 8r` (a snow start: min of that and 0); `shifts[d] = clamp(shifts[d−1] − 3 + 6r, −6, 6)`
  - **points 1 and 2** get `climate.range(start, month)` + `shifts[0]`, the low to the 06:00 point and the high to the 14:00 point
- **`weather.fill(c, j, before)`** (j ≥ 3): a 06:00 point is `normal low + lowOffset(before) + shifts[day]`; a 14:00 point is `normal high + highOffset(before) + shifts[day]`, then at least `points[j−1].c + 2`.
- **`weather.temperature(points, daySeconds, seconds) -> °C`:** u = `seconds / daySeconds` (0 when nil); linear between the two filled points around u; before the first or past the last filled one, that point's value.

- [ ] **Step 1: Write the failing tests** (`tests/test_weather.lua`, with `script(list, rest)` returning the listed draws, then `rest`):
  - "the game time starts at the time key minus the lead": sunrise is 0.775 − 1/24 at fast (900) and moderate (1800), 0.775 − 75/7200 at slow, 0.775 with Day length Off
  - "turning points fall at 06:00 and 14:00 from the start on": a sunrise start at moderate: `points[1]` is 14:00 at t = −0.65 and `points[2]` 06:00 at t = 1/60, spacing 1/3 and 2/3 to 1e-9, days 0, 0, 0, 1, 1, ...; a noon start begins with a 06:00 point; Day length Off has 2 points
  - "day shifts walk within their limits": all draws 1 give 4, 6, 6, ...; all 0 give −4, −6, −6, ...; over 100 seeds day 0 is within ±4, each step within ±3 and every day within ±6
  - "the points around the start use the start range plus day 0's shift": a cloudy January noon start with first draw 0.75 gives 4 (06:00) and 7 (14:00)
  - "a snow start stays at or below 0 °C at its high": first draw 1 gives shift 0, so the high is −1 in January
  - "a later point takes the normal, the day's shift and the weather before it": in January, `fill` after "clear" at 06:00 is 0 + shift, after "cloudy" 2 + shift, after "snow" the same as "cloudy"; a 14:00 point is at least the low before it + 2
  - "the temperature is linear between points, like the game's curve": at a point its value; half way (in game time) the mean; Day length Off a constant
  - `test_climate.lua` passes unchanged apart from its require
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_weather.lua tests/test_climate.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the server works out each game day's low and high"

### Task 11: The weather schedule, worked out in advance

**Files:** Modify `server/CopsAndRobbers/cnr/weather.lua`, `server/CopsAndRobbers/cnr/sky.lua` (`pick`, `payload`). Test: `tests/test_weather.lua`, `tests/test_sky.lua`, `tests/test_main.lua`.

**Interfaces:**
- **Consumes:** Task 9's settings, Task 10's `climate`, `fill`, `temperature`, `releaseAt`, `endAt`, `gameStart`.
- **Produces `weather.build(s, cfg, random) -> { changes, temps, gameStart, releaseAt }`** (`random` defaults to `seeded(s.weatherSeed)`):
  - `changes = { { at, to, forecastFrom, cross = true | nil }, ... }` with `at` on the round clock; empty when `weatherChanges` is off or there is no `climate`
  - `temps = { { t, hour, c }, ... }` from the filled points (nil without a climate)
- **Conditions at a second:** T = `temperature`; tod = (`gameStart` + u) % 1; foggy = T ≤ 12 and 0.25 ≤ tod < 0.875; warm = the higher of the two points around u ≥ 15.
- **A slot** draws the next weather from the spec's table, its order filtered by the conditions then:

  | From | Options, in order |
  |---|---|
  | clear | cloudy; fog if foggy |
  | cloudy | clear; rain if T ≥ 2; snow if T ≤ 1; fog if foggy |
  | rain | cloudy; storm if warm; snow if T ≤ 1 |
  | storm | rain |
  | snow | cloudy; rain if T ≥ 2 |
  | fog | cloudy; clear |

- **Slots:** the first at `releaseAt` + interval; each next at the change before it + interval; interval = 60 × (min + (max − min) × r).
- **Crossings** (Calls: Fitting):
  - from `releaseAt`, outside a running change, the moment the weather stops fitting
  - at a change's end (`at + 60`), when its weather does not fit then
  - targets: snow → rain, rain → snow, storm → rain, fog → a pick of {cloudy, clear}
  - a crossing replaces the pending slot; the next slot is drawn from it
- **Scan** from `releaseAt` to `endAt` in 1 s steps. A threshold is placed by linear interpolation inside its step; 09:00 is solved exactly. Point j is filled with the weather in effect at point j − 1 when the scan reaches it (points at or before `releaseAt` with the start weather); after the scan, the rest with the last weather. Only changes with `at < endAt`.
- **Draw order:** Calls this plan makes. `forecastFrom = at − WINDOW_SECONDS × r`.
- **`sky.pick`:** after `windSeed`, `weatherSeed = random(1, 2147483646)`, then `build`; stores `changes`, `temps`, `gameStart`, `releaseAt` on the sky table (Earth: `{}`, no draws).
- **`sky.payload`:** adds those four fields when present.
- **Produces for later tasks:**
  - `weather.at(s, t) -> weather`: the `to` of the last change with `at` ≤ t, else `s.weather`
  - `weather.groundedAt(s, t) -> reason | nil`: that weather when it grounds; the old weather while a change away from a grounding weather runs (t < at + 60); nil for a nil `s`

- [ ] **Step 1: Write the failing tests:**
  - "no changes with Weather changes off, without a weather or on Earth; temps still come with a weather"
  - "each slot change comes min to max after the change before it, the first after the release": 30 seeds × months 1, 4, 7, 10 × the six times, with a 1800 s time limit (keeps `make test` fast): every non-crossing `at` minus the previous `at` (or `releaseAt`) is within [180, 480]
  - "changes run up to the time limit, or 180 minutes without one": with a 600 s limit every `at` < `releaseAt` + 600; without one the last `at` + 480 > `releaseAt` + 10800
  - "no count cap": a clear July start (no crossing can happen), min = max = 1, no limit: exactly 179 changes, every 60 s
  - "Day length Off: slots still come, crossings never": no change has `cross`
  - "each slot change goes to an allowed neighbour": the same seeds; each non-crossing change checked against the table with T, foggy and warm worked out at its `at`
  - "a summer round never sees snow": months 6-8, 50 seeds
  - "every forecast window is 120 s and contains its change": `at − 120 ≤ forecastFrom ≤ at`
  - "the same seed gives the same schedule, another seed another one"
  - **Crossings,** fast days, min = max = 1000 (no slot in the horizon), no limit:
    - "rain turns to snow at 1 °C and back to rain at 2 °C": `{ time = "night", weather = "rain", month = 3 }`, all draws 0. The first change is snow with `cross` and T(at) = 1 ± 0.05; the next is rain with T(at) = 2 ± 0.05.
    - "a storm that gets that cold becomes rain, then snow when the change ends": a night storm in March, draws 0.25 then 0. Storm → rain with T(at) = 1 ± 0.05; rain → snow exactly 60 s later.
    - "fog lifts at 09:00": `{ time = "sunrise", weather = "fog", month = 10 }`, draws 0.5. The first change is at the second where the game time is 09:00: (0.875 − (0.775 − 1/24)) × 900 = 127.5 ± 1e-6, to "clear".
    - "fog lifts when it warms above 12 °C": an October night fog start with draw 0.6875 (shift +1.5). It fits from about 04:00 and lifts at T = 12 ± 0.05 before 09:00.
    - "a crossing during a change waits for its end": over 50 seeds with min 1, every crossing is at least 60 s after the change before it
  - `test_sky.lua`:
    - "pick rolls a weather seed and a schedule": `weatherSeed` 1 with the `rng` helper; `changes` and `temps` are tables; `releaseAt` is 10 with the defaults
    - "payload carries the schedule"
    - "record keeps the conditions without the wind" passes unchanged
  - `test_main.lua` "the setup and New sky payloads carry the schedule": `cnr_roundSetup`'s and `cnr_sky`'s `sky` have `changes`, at least 2 `temps`, `gameStart` and `releaseAt`, and New sky's `changes` differ from the setup's
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_weather.lua tests/test_sky.lua tests/test_main.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the server works out the round's weather changes and forecasts in advance"

### Task 12: The weather grounds and returns the helicopter; records (server)

**Files:** Modify `server/CopsAndRobbers/cnr/helicopter.lua`, `round.lua` (around 355 and 390, `finish`), `sky.lua` (`record`). Test: `tests/test_helicopter.lua`, `tests/test_round.lua`, `tests/test_sky.lua`.

**Interfaces:**
- **Consumes:** `weather.groundedAt` (Task 11).
- **`helicopter.update(h, now, covered, guided, grounded)`:**
  - `grounded` (a weather): unless already grounded for that reason, the phase becomes "grounded" with that reason, `phaseEnd` nil, tracking off, guided off; returns true. A refuel or an arrival is cancelled.
  - nil while grounded: "arriving" with `phaseEnd = now + helicopterArrivalSeconds`, the reason cleared, then the usual loop (so 0 s goes up at once); returns true.
  - `enterUp` sets `h.flew = true` (a full `helicopterUpSeconds` on each return, as now). `helicopter.flew(h)` is `h.flew == true`.
- **round.lua:**
  - clock = `now − self.countdownStartedAt`
  - `helicopter.new(self.cfg, weather.groundedAt(self.sky, clock), now)`
  - `helicopter.update(..., self.inSight, weather.groundedAt(self.sky, clock))`
  - the record's `sky = sky.record(self.sky, self.cfg, clock)`
- **`sky.record(s, cfg, clock)`:** `weather` is the worst of the start weather and every change `to` with `at` ≤ clock (Global Constraints order; a tie keeps the first); `weatherStart = s.weather`.

- [ ] **Step 1: Write the failing tests:**
  - `test_helicopter.lua`:
    - "a change to storm, fog or snow grounds it from any phase": arriving, up and refuelling each go "grounded" with the reason, `update` returns true, `status` has the reason and no seconds
    - "it comes back through arriving when the weather clears": grounded at 100, `update(h, 200, true, false, nil)` gives "arriving" with seconds 60; at 260 it is up with seconds 120
    - "a full time up after each return"; "a grounding during a refuel cancels it"
    - "a new grounding reason is reported": storm then snow returns true and the reason "snow"
    - "flew is true once it has been up": false while arriving, true after
    - rewrite "storm, fog and snow ground it for good" as "a round that starts grounded stays grounded until the weather clears"
  - `test_round.lua`:
    - "the heli effect goes grounded when a change to storm starts and arriving when the change away ends": sky `{ weather = "rain", changes = { { at = 40, to = "storm" }, { at = 200, to = "rain" } } }`; a `heli` effect "grounded"/"storm" by clock 40.25; "arriving" by 260.25
    - "a round that starts in fog returns when the fog clears"
    - "a run records the worst weather and the start weather": cloudy → rain → storm → cloudy, caught after the storm: `weather` "storm", `weatherStart` "cloudy"; a change after the end doesn't count
  - `test_sky.lua` "record gives the worst weather and the start weather"
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_helicopter.lua tests/test_round.lua tests/test_sky.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: storm, fog and snow ground the helicopter until it clears; runs record the worst weather"

### Task 13: A grounded helicopter flies away and comes back searching (client)

**Files:** Modify `heliSearch.lua`, `heli.lua` (the light's phase table). Test: `tests/test_heli_client.lua`.

**Interfaces:**
- **heliSearch:**
  - "grounded" with a flight not leaving: `leave` and `leftAt`, as "refuelling"
  - "grounded" counts as up for the 8 s fly-away, also without a target
  - after "arriving", the flight and mode come from `lastKnown`/`lastKnownVel` (Task 6), which a grounding keeps
- **The light:** "tracking" or "searching" → "grounded" with a flight starts `startDepart`, as "refuelling"; a light in its fly-away is kept while "grounded".

- [ ] **Step 1: Write the failing tests:**
  - "grounded while up flies away with the light": at night, "tracking" then `set` grounded/storm: `f.leaving` set, `fx.mode == "depart"`, the light and flight gone at 8 s, `soundLevel` 0.5 at 6.5 s
  - "grounded during the fly-in flies away too"
  - "grounded during a refuel's fly-away keeps it going": no `resume`; dropped at `leftAt` + 8
  - "grounded without a target still drops the flight 8 s after it left"
  - "back from a grounding it searches from the last known state": tracking at A (still); grounded; the car moves 300 m; "arriving" → "searching": mode "contain" at A
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: a grounded helicopter flies away on every game and returns to search"

### Task 14: Reading the schedule on the client (`skyChanges.lua`, pure)

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/skyChanges.lua`, `tests/test_sky_changes.lua`.

**Interfaces (Produces):** `p` is a sky payload (Task 11).
- `CHANGE_SECONDS = 60`, `DRY_SECONDS = 180`, `WINDOW_SECONDS = 120`, `GROUNDED = { storm, fog, snow }`.
- **`at(p, t) -> from, to, progress, index`:** index = the number of changes with `at` ≤ t. `to` = that change's `to`; `from` = the one before (or `p.weather`); `progress` = min(1, (t − at) / 60). Index 0: `p.weather`, `p.weather`, 1, 0.
- **`current(p, t)`** = `to`; **`smooth(x)`** = x²(3 − 2x).
- **`notice(from, to) -> text`:**

  | Change | Text |
  |---|---|
  | clear → cloudy | "Weather: clouds coming in" |
  | → fog | "Weather: fog rolling in" |
  | cloudy → rain | "Weather: rain coming" |
  | cloudy → snow | "Weather: snow coming" |
  | rain → storm | "Weather: the rain is getting heavier" |
  | storm → rain | "Weather: the storm is easing" |
  | rain → snow | "Weather: the rain is turning to snow" |
  | snow → rain | "Weather: the snow is turning to rain" |
  | → clear or cloudy otherwise | "Weather: clearing up" |

- **`forecast(p, t, heliOn) -> { text, heli } | nil`:**
  - the next change has `at` > t; none gives nil
  - the word: "clearing up" for a change to clear or cloudy from rain, snow or fog; otherwise clear "clear skies", cloudy "clouds", rain "rain", storm "a storm", fog "fog", snow "snow"
  - t ≥ `forecastFrom`: "Forecast: <word> any minute"
  - otherwise a = (forecastFrom − t) / 60, b = a + 2, lo = floor(a), hi = ceil(b): "Forecast: <word> in lo-hi min" when lo ≥ 1, else "Forecast: <word> within hi min"
  - `heli` only with `heliOn`: "(helicopter grounded)" when the change goes to a grounding weather, "(helicopter returns)" when it goes from one to another weather
- **`prepForecast(p) -> text | nil`:** the first change against `p.releaseAt`, same rounding: "Forecast: rain 5-7 min after release", or "Forecast: rain within 2 min after release".
- **`grip(p, t) -> { dry, rain, storm, snow } | nil`** (nil unless `p.driving`), the weights summing to 1:
  - kind = the weather for rain, storm and snow, otherwise "dry"; the start is one-hot on the start weather's kind
  - in order, each change toward a wet kind blends from the weights in effect at its `at` toward that kind over 60 s
  - each change from a wet kind to a dry one blends toward dry over 180 s from `at + 60`
  - other changes leave the blend alone; progress is linear
- **`curve(p, clockStart, t) -> curve, index`** (nil without `temps`):
  - u = wrapHalf(clockStart − p.gameStart) + t / p.daySeconds (no second term without `daySeconds`)
  - index = the last j with `temps[j].t` ≤ u, clamped to [1, #temps − 1]
  - curve = the two points `{ tod(hour), c }` sorted by time, with tod(6) = 0.75 and tod(14) = 2/24

- [ ] **Step 1: Write the failing tests:**
  - "at": before, during (progress 0.5 at +30 s) and after a change, two changes, none
  - "the notices": all 14 pairs the server can make
  - "the forecast before, inside and after its window": window [300, 420], change at 400, t = 120 → "Forecast: rain in 3-5 min"; t = 150 → "in 2-5 min"; t = 280 → "within 3 min"; t = 310 → "any minute"; t = 410 with no later change → nil
  - "the shown minutes always cover the window": for t from 0 to the change in steps of 1 s, lo × 60 ≤ forecastFrom − t and hi × 60 ≥ forecastFrom + 120 − t (or "any minute" inside)
  - "the helicopter line only when it is on and the change grounds it or brings it back"
  - "the prep text for the first change": `releaseAt` 10, `forecastFrom` 310 → "Forecast: rain 5-7 min after release"; `forecastFrom` 0 → "within 2 min"
  - "nothing without changes"
  - "grip": cloudy → rain at 20: rain 0.5 at 50, 1 at 80; rain → cloudy at 200: rain 1 until 260, 0.5 at 350, 0 at 440; rain → storm halfway mixes 0.5/0.5; a wet change at 300 during the drying starts from the weights then; nil without `driving`
  - "the curve": the moderate noon fixture (gameStart 0.95833, points at t −0.20833, 0.125, 0.79167, 1.125): clockStart = gameStart moves to index 2 at t = 225 s; clockStart = gameStart + 0.02 (a solar offset) moves at 189 s; both curves give the same °C at 14:00
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_sky_changes.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: the client reads the weather schedule, its grip, curve and forecast"

### Task 15: The sky follows the schedule; rain at half way; the stale roof (TODO issue)

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/sky.lua`, `rain.lua`
- Delete: `client/lua/ge/extensions/copsAndRobbers/climate.lua`
- Test: `tests/test_sky_client.lua`, `tests/test_rain.lua`

**Interfaces:**
- **Consumes:** `skyChanges.*` (Task 14); the payload (Task 11).
- **`M.STEP_SECONDS = 0.5`.** While `started`, with `round.changes` or `round.temps`, and no `lockTimer` pending (a step would cancel the 3 s blend), every 0.5 s:
  - **clouds and fog:** `from, to, progress = skyChanges.at(round, roundTime)`; `cloudCover`, `fogDensity` and `windSpeed` = lerp of `M.WEATHER[from]` and `[to]` by `smooth(progress)`; written (Global Constraints' locked write) only when they differ from the last written
  - **the curve:** `skyChanges.curve(round, clockStart, roundTime)`; on a new index, a locked write of `{ temperatureCurveOverrideC = curve }`
  - **rain:** on a new index, `rain.target(M.WEATHER[to].precipitation, CHANGE_SECONDS × (1 − progress))`
  - a write error logs once and stops that part for the round
  - `forget` also resets the step state (last written values, the index, the failed flags)
- **`M.update(dt)`** returns `{ from, to, notice = skyChanges.notice(from, to) }` on the tick a new change is first seen, else nil. **`M.weather()`** = `skyChanges.current(round, roundTime)`, nil without a round.
- **Wind:** while `p.driving` and the old or new weather is windy (or the last push was not zero), the 0.25 s push is (1 − k) × `wind.at(from, ...)` + k × `wind.at(to, ...)`, k = `smooth(progress)`; one zero push when both become calm.
- **`roundState` at apply:**
  - clouds, fog and `windSpeed` are the in-between values at `p.clockSeconds or 0`
  - `temperatureCurveOverrideC` is `skyChanges.curve(...)`, or false without `temps`; `climate` is no longer used
  - `apply` calls `rain.resetRoof()`, then for a joiner mid-change `rain.target(fromSpec, 0)` and `rain.target(toSpec, time left)`; otherwise the weather in effect over `BLEND_SECONDS`
- **`M.label`:** the range is min/max of `temps[1].c` and `temps[2].c`, rounded by `units.temperature`.
- **rain.lua:**
  - `M.resetRoof()`: a new roof state; an existing object is un-hidden and the volume rewritten on the next write
  - a same-kind target with seconds > 0 sets the drop fields at seconds / 2 (counted in `update`), not at once

- [ ] **Step 1: Write the failing tests** (`test_sky_client.lua`; a fixture: cloudy at moderate, `changes = { { at = 20, to = "rain", forecastFrom = 0 } }`, temps as Task 14's):
  - "clouds and fog step twice a second, locked between steps": `startClock(0)`, updates of 0.1 s to 90 s. Between 20 and 80 s every `setState` has only `cloudCover`, `fogDensity` and `windSpeed`, no seconds, at most one per 0.5 s; the environment is locked after every update.
  - "the steps follow a smoothstep": `cloudCover` is 2.0 ± 0.02 at 50 s and 1.8625 ± 0.03 at 35 s
  - "a step never touches time, play, the day length, the date or the temperature"
  - "rain fades in over the change": drops 1500 ± 150 at 50 s
  - "the curve moves on only at a turning point, and the two curves agree there"
  - "the wind cross-fades": rain → cloudy at progress 0.5 pushes half of `wind.at("rain", ...)`, then one zero push at the end
  - "a joiner mid-change gets the in-between sky": apply with `clockSeconds = 50`
  - "update reports a change once, with its notice"; "weather() follows the schedule"
  - "no step while the round sky blends in"
  - "a failing step logs once and stays locked"
  - "the label's range comes from the turning points around the start"
  - replace "the temperature follows the weather and the server's month" with the `temps` version
  - `test_rain.lua`:
    - "rain to storm switches the drop size and speed at half the change": `target(STORM, 60)`; `dropSize` "1" at 29.9 s, "1.3" at 30.1 s
    - "a new round's rain during the last round's fade starts without the roof": roof at 3 m, full rain hidden; `target(nil, 3)`; 1 s later the roof gone, `resetRoof()`, `target(RAIN, 3)`; 0.3 s later not hidden, volume = drops / 3000
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_sky_client.lua tests/test_rain.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.** Delete the client `climate.lua`.
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: clouds, fog, rain, wind and the temperature follow the weather schedule"

### Task 16: Grip blends with the weather

**Files:** Modify `surfaces.lua`, `sky.lua`. Test: `tests/test_surfaces.lua`, `tests/test_sky_client.lua`.

**Interfaces:**
- **`surfaces.blend(weights)`** (`{ dry, rain, storm, snow }`):
  - on first use, saves the dry values of every model that any rule targets or copies from
  - each targeted model's field is Σ weight × that kind's value: dry is the saved value; a `become` rule gives the source's saved dry value; a multiplier rule gives saved × factor for the two friction fields (the others dry); a kind that doesn't target the model gives dry
  - pushes (`pushModels`) only when some weight moved at least `STEP − 1e-9` from the last push, or the weights reached a one-hot that differs from it; the first call pushes
  - `apply(weather)` = `blend` one-hot; `restore` and `drop` as now
- **sky.lua:** on the 0.5 s tick and at apply, `surfaces.blend(skyChanges.grip(round, t))` when `p.driving`; in a `pcall`, an error logs once and stops grip for the round.

- [ ] **Step 1: Write the failing tests:**
  - `test_surfaces.lua`:
    - "blend mixes dry and wet values": `{ dry = 0.5, rain = 0.5 }`: ASPHALT static (0.98 + 0.92) / 2, GRASS static 0.61 × 0.925
    - "a rain and snow mix reads the wet models' dry values": DIRT static (0.62 + 0.65) / 2
    - "a model is pushed only when the blend moved 5 % or reached its end": rain from 0 to 1 in steps of 0.01 gives 21 push batches
    - "restore puts the dry values back after a blend"
  - `test_sky_client.lua`:
    - "grip gets wet over the change and dries over 180 s after it": ASPHALT static at 50 s half way ± 0.06 of the way, wet at 80 s; after rain → cloudy at 200, half way dry at 350, dry at 440
    - "between wet kinds the blend runs over the change"
    - "driving off never changes grip"
    - "a joiner gets the grip in effect"
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** "feat: grip blends toward the new weather and roads dry over three minutes"

### Task 17: Notices, lights and the forecast on the HUD

**Files:**
- Modify:
  - `client/lua/ge/extensions/copsAndRobbers.lua` (`onUpdate`, `onRoundSetup`, `onSky`, `updateLightsAndPatch`, the `cnr_rules` handler)
  - `sky.lua` (`M.forecast`, `M.prepLabel`), `traffic.lua`, `hud.lua`, `hudfeed.lua`
  - `client/ui/modules/apps/CopsAndRobbersHud/HudChase.vue`
- Test: `tests/test_client.lua`, `tests/test_traffic.lua`, `tests/test_hud.lua`

**Interfaces:**
- **`sky.forecast(heliOn)`** = `skyChanges.forecast(round, roundTime, heliOn)` while started, else nil. **`sky.prepLabel(p)`** = `label(p, true)` .. " · " .. `prepForecast(p)` when there is one.
- **copsAndRobbers.lua:**
  - a change from `sky.update` → `traffic.setWeather(change.to)` and `hudfeed.event(change.notice, clock, "info")`
  - setup and New sky set `traffic.setWeather(sky.weather())` and show `sky.prepLabel` in prep; the "New sky: " notice keeps `label(d, true)`
  - `heliOn = r.helicopter == true` from `cnr_rules`; `hudfeed.update` info gains `forecast = sky.forecast(heliOn)`
  - `ai.lightsOn(sky.isNight() or sky.isBadWeather(traffic.weather()))`
- **traffic.lua:** a `setWeather` from bad to not bad marks the lights; the next lights tick that is not night sends `"electrics.setLightsState(0)"` to every traffic car once.
- **hud.lua:** `status.forecast = { text, heli }` when `info.forecast.text` is a string. **hudfeed** passes `forecast` through.
- **HudChase.vue:** under `.chase-top`, a `.chase-forecast` row in the `.item` style with `<BngIcon :type="icons.weather" />`, the text, and the `heli` hint on its own line below.

- [ ] **Step 1: Write the failing tests:**
  - `test_client.lua`:
    - "a weather change during the chase shows its notice and moves the lights and the beam": a running round whose sky changes cloudy → rain at 30; past 30 s the HUD events have "Weather: rain coming" and `traffic.weather()` is "rain"
    - "the forecast reaches the HUD under the timer, with the helicopter hint when it is on"
    - "prep shows the first change's forecast"
    - "no forecast without changes"
    - "practice AI cars switch their headlights on in bad weather by day"
  - `test_traffic.lua`: "traffic headlights go off once when it clears by day, and not at night"
  - `test_hud.lua`: "the forecast item carries its text and hint; nothing without text"
- [ ] **Step 2: Run** `lua tests/run.lua tests/test_client.lua tests/test_traffic.lua tests/test_hud.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test` and `make vuecheck`.** Expected: `0 failed`, vuecheck clean.
- [ ] **Step 5: Commit:** "feat: weather notices, the forecast line and lights that follow the weather"

### Task 18: Docs and panel help

**Files:**
- `docs/FEATURES.md` (the helicopter and the night and weather sections, the settings table)
- `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
- `README.md` (the config table, the helicopter text)
- `docs/DEPENDENCIES.md`
- `settings.js` (the helicopter help)

- [ ] **Step 1: Write the docs:**
  - **Helicopter:**
    - tracking from 100 m up, 60 m to the side and 40 m back
    - a road search ahead (and the other branch, and back) after a refuel and after losing a runner at 5 m/s or more, the light sweeping across the road
    - containment over a stopped runner
    - a timed watch of each way out of a tunnel, then the road beyond
    - guided in a tunnel it waits at the exit ahead
    - grounded in storm, fog and snow, back when it clears
  - **Weather:**
    - changes every 3 to 8 minutes (settable) only into a fitting weather; crossings at once
    - each day its own low and high
    - grip gets wet over a minute and dries over three
    - the notices and the forecast line ("Forecast: rain in 3-5 min", "any minute", the helicopter hint) and the prep forecast
    - records keep the worst and the start weather
  - **Settings:** `weatherChanges`, `weatherChangeMinMinutes`, `weatherChangeMaxMinutes` in README's and FEATURES' tables. The helicopter panel help: "Searches for the runner and tracks them while it sees them; grounded in storm, fog and snow until it clears".
  - **DEPENDENCIES:**
    - the stepped `setState({ cloudCover, fogDensity, windSpeed })` and `{ temperatureCurveOverrideC }` with the lock around each call
    - the curve's format and linear wrap
    - `be:setGroundModel` pushes during the round
    - the road graph for routes and the tunnel watch (`findClosestRoad`'s distance, `getGraphpath().graph`, `getMap().nodes`)
    - on update: a known tunnel still finds its exit and a road search follows the road
  - **FEATURES' title** stays at its current version (the bump happens on main).
- [ ] **Step 2: Run `make test`, `make vuecheck` and `make package`.** Expected: `0 failed`, vuecheck clean, a zip in `dist/Client`.
- [ ] **Step 3: Commit:** "docs: the air unit and dynamic weather"
