# Directional cop visibility implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement one task at a time once the user approves the plan and authorizes the build. Steps use checkboxes for tracking.

**Goal:** Let human and Practice AI cops acquire the runner according to gaze, rear-view mirror coverage, actual lighting, weather and clear line of sight.

**Architecture:** The client computes the effective range and tests the existing car-to-car rays. Each cop has a separate report stream. The server validates the sender, roster and distance before feeding the observation to its existing tracking and scoring code.

**Tech stack:** BeamNG GE LuaJIT, BeamMP client and server Lua, the repository’s Lua test runner and existing Vue player instructions.

**Spec:** [Where a cop can spot the runner](../specs/2026-11-18-cop-visibility-design.md)

## Global constraints

- Default clear-day range is 400 m looking at the runner. Looking forward gives 200 m to the side and 200 m directly behind the car. Looking sideways gives 100 m directly opposite the gaze. The mirror floor stays fixed to each human or AI cop car. Scale with the current host maximum, then apply the environmental factors in the spec. Off = 0.
- Sample at 4 Hz. Human observer position is the assigned round car. Practice AI always uses its own car and heading. Preserve 3 target points, two-way static clearance, 5 s keepalive, 11 s staleness, configured grace (default 1.5 s) and the existing server cap of maximum + 50 m.
- Production authority belongs to the reporting human cop. Practice AI observations belong to the reporting issuer’s rostered negative cop slots. Practice generates no leaderboard records. AI cops continue pursuing the assigned runner when sight drops. Existing BeamNG driving commands stay independent of sight reports.
- Work on an isolated feature worktree rebased or brought up to date with reviewed main when authorized. Read current main guidance and the shared ledger before implementation. Follow current round-car placement, bystander and spectator flows where main has evolved. Keep version changes on main after merge. Add source comments only on request.

## Review focus

| Failure mode | Check |
|---|---|
| Free camera, parked personal car or spectator watching the runner shifts the sight origin | Task 4 verifies the bound origin, fallback gaze and mirror axis with independent car, seat and camera poses. |
| A replacement runner temporarily inherits lit lamps from the previous vehicle | Task 2 changes the target, reuses its ID and delays the new bridge value. |
| A lamp leaks through a wall or comes from a camera, or dense scenery stalls the chase | Task 3 counts lookups and rays, including an obstructed spotlight and overflow cell. |
| Two Practice cops overwrite one another, or somebody else reports for them | Tasks 4 and 5 exercise independent client keepalives, roster validation and all three Practice roles. |
| A missing weather input or unusual map date jumps to clear-day range | Tasks 1 and 2 sample wraparound, polar, non-finite and absent values. |

## Task 1 · Calculate the effective range

**Files**

- Create `client/lua/ge/extensions/copsAndRobbers/visibility.lua` for the pure calculation.
- Create `tests/test_visibility.lua`. Use `test`, `assertEq` and `assertNear` supplied by `tests/run.lua`.

**Interfaces**

- `visibility.bearing(axis, delta) -> cosine or nil` takes two vectors with X and Y components. A valid −1 means the vectors point opposite ways. Return nil if either horizontal direction is unusable.
- `visibility.daylight(time, sunrise, sunset) -> factor or nil` takes normalized BeamNG times.
- `visibility.range(maxMeters, gazeCos, carForwardCos, daylight, lampsOn, streetStrength, rawFog, precipitationFactor) -> metres` returns a finite value between zero and the configured maximum.

- [ ] **1. Write the compass tests.** Face +Y and put the runner north, east, west and south. Expect cosines 1, 0, 0 and −1. Scale both vectors and change their Z values. Expect identical results. For zero separation, a missing heading, non-finite XY or horizontal length ≤0.001, expect nil. With the mirror unavailable, verify the 45° gaze range is `400 * 2 ^ (math.sqrt(0.5) - 1)` and sweep gaze angles from 0° to 180° for decreasing range.

  To isolate the mirror, keep gaze directly opposite the runner (gaze cosine −1). Rotate the target to both sides of the car’s rear axis. At rear offsets 0°, 15°, 30°, 45° and 90°, expect 200, 150, 100, 100 and 100 m at R=400. Sweep from 0° to 30° for a non-increasing floor. Hold a rear target fixed and turn the gaze from forward to straight back. Expect 200 then 400 m. Repeat with a side target opposite a sideways gaze and expect 100 m. With no car bearing and a valid forward gaze expect 400 m. With both bearings missing expect 100 m.

- [ ] **2. Write the environmental table test.** Each row gives D, lamps, streetlight, raw fog, precipitation and rounded distances for direct gaze, a side target with forward gaze and a target opposite a sideways gaze. A direct rear target with forward gaze must reproduce the side column. A deliberate direct rear gaze must reproduce the direct-gaze column. Also test R=200 for 200/100/50 m in the three columns and 100 m in the rear mirrors. At R=0 every geometry gives 0.

  ```lua
  local cases = {
    {1, false, 0, 0.0004, 1.00, 400, 200, 100},
    {1, false, 0, 0.0010, 1.00, 390, 195,  98},
    {1, false, 0, 0.0020, 0.85, 318, 159,  79},
    {1, false, 0, 0.0040, 0.70, 239, 119,  60},
    {1, false, 0, 0.0050, 0.75, 243, 122,  61},
    {1, false, 0, 0.0150, 1.00, 160,  80,  40},
    {0, false, 0, 0.0004, 1.00, 120,  60,  30},
    {0, true,  0, 0.0004, 1.00, 220, 110,  55},
    {0, false, 1, 0.0004, 1.00, 200, 100,  50},
    {0, true,  1, 0.0004, 1.00, 300, 150,  75},
  }
  for _, row in ipairs(cases) do
    local bearings = {{1,1,6}, {0,0,7}, {-1,0,8}, {-1,-1,7}, {1,-1,6}}
    for _, pair in ipairs(bearings) do
      local m = visibility.range(400, pair[1], pair[2], row[1], row[2], row[3], row[4], row[5])
      assert(m == m and math.abs(m) < math.huge)
      assertEq(math.floor(m + 0.5), row[pair[3]])
    end
  end
  ```

  Replay the spec's 170 m night drive with raw fog 0.0015 and precipitation 0.925. At D=0, check the rounded forward ranges for (lamps, S) = (off, 0.5), (on, 0.5), (on, 0), (off, 0): 141, 230, 194 and 106 m. The corresponding range decisions are false, true, true and false. At D=1 all four give about 353 m. Sweep increasing raw fog and decreasing precipitation separately at night and by day, checking each range is no larger than the previous one.

- [ ] **3. Pin invalid measurements.** Replace each numeric input separately with nil, NaN and ±infinity. Assert finite results using the fallback for that input (maximum 0, missing gaze cosine −1, missing car cosine disables the mirror, D/S 0, fog 0.015, precipitation 0.70). Only boolean true turns lamps on. Pin clamping separately with valid out-of-domain values, including raw fog under 0.0004 and above 0.015. Dense fog on a fully streetlit night with lamps on gives 120 m forward.
- [ ] **4. Write the twilight test.** Use sunrise 0.75, sunset 0.25 and `w = 30 / 1440`. Check D=1 at 0 and D=0 at 0.5. For offsets `{-w, -w/2, 0, w/2, w}` from sunrise expect `{0, 0.15625, 0.5, 0.84375, 1}`. Reverse the sequence at sunset. Repeat a crossing adjacent to clock wrap, use `assertNear` with 1e−9, and expect nil for non-finite, missing or coincident anchors.
- [ ] **5. Run red.** Run `lua tests/run.lua tests/test_visibility.lua`. The new test file should fail because `copsAndRobbers/visibility` does not exist.
- [ ] **6. Implement the three functions.** Normalize X/Y before taking and clamping the dot product. For daylight find the nearer boundary on the circular clock, give the distance its sign from sunrise-to-sunset membership, then smoothstep across ±30 minutes. For range, compute gaze as `2^(gazeCos - 1)`. For a valid car-forward cosine compute `beta = math.deg(math.acos(-carForwardCos))` after clamping the cosine to [−1,1]. With `u = clamp(1 - beta / 30, 0, 1)`, the mirror floor is `0.25 + 0.25 * u * u * (3 - 2 * u)`. Multiply R by the higher of gaze and the floor. Use gaze alone if the car bearing is unavailable. Apply lighting, fog and precipitation once to the result. Do not round in production.
- [ ] **7. Run green.** Run the focused command from step 5 (0 failed) and `luajit -bl client/lua/ge/extensions/copsAndRobbers/visibility.lua >/dev/null` (exit 0).
- [ ] **8. Commit the module and tests** as `feat: calculate directional visibility range`.

## Task 2 · Read daylight, weather and runner lamps

**Files**

- Create `client/lua/ge/extensions/copsAndRobbers/sightConditions.lua` for the GE adapters and solar cache.
- Create `tests/test_sight_conditions.lua`. Reuse the real `copsAndRobbers/sky` preset table. Stub its `weatherBlend()` return tuple and restore it and the GE globals between fixtures.

**Interfaces**

- `sightConditions.sample(runner) -> daylight, lampsOn, rawFog, precipitationFactor`. The argument is the assigned vehicle object or nil.
- `sightConditions.reset()` discards local target and solar cache state. Task 4 owns its lifecycle calls.

- [ ] **1. Write the solar precedence test.** Supply `core_environment.getTimeOfDay()` with time 0, latitude, longitude, year, month, day, utcOffset and dstRule. Have `core_solarTimeOfDay.getSolarTimeOfDayValues(tod)` return `{sunrise=0.75, sunset=0.25}`. Set `getLightState().isNight=true` and expect D=1. Move just the clock to 0.75 and expect 0.5 with the same anchor lookup count. Change each cache key in turn, including map identifier, and expect one new lookup per change. Expect the first sample after reset to fetch anchors anew.
- [ ] **2. Write the solar fallback test.** Remove anchors and have `getSolarTimeOfDayEvents(tod)` return `{polar="day"}` or `{polar="night"}`. Expect D=1 or 0 even with the opposing `isNight`. Without either solar signal, `isNight=false` gives 1, true gives 0, and nil or a non-boolean gives 0. Include a failed getter and a non-finite clock sample.
- [ ] **3. Write the weather precedence test.** Use clear→rain, progress 0.5. For `getFogDensity() -> 0, nil` expect raw fog 0.0012 and precipitation 0.925. For `0, levelInfo` expect 0 and 0.925. For `0.0035, levelInfo` expect 0.0035 and 0.925. NaN with LevelInfo uses the preset blend. Repeat with stable clear/cloudy/fog, rain, snow, storm and thunderstorm and check each precipitation factor. Missing progress for different endpoints uses the denser fog and lower precipitation. Unknown endpoints contribute 0.015 and 0.70. Clamp finite progress to [0,1].
- [ ] **4. Write the lamp lifetime test.** Stub the actual calls `registerValueChangeNotification(vehicle, "lights_state")` and `getCachedVehicleData(gameId, "lights_state")`. Maintain a stub cache keyed by ID with separate value and registered-key tables. Count calls separately from newly queued vehicle notifications. Run this sequence:

  | Sample | Bridge state | Expected lamps |
  |---|---|---|
  | A, ID 41 | Value 2, another caller already registered the key | On, zero additional vehicle notifications |
  | B, ID 42 | No registered key or cached value | Off, one new notification |
  | B again | Values 1, then 0, then an unrecognized value | On, off, off, no duplicate notification |
  | Replacement B, also ID 42 | Bridge destruction/replacement cleared entry 42 | Off, one new notification, then on once 2 arrives |
  | No runner, then reset | A’s unrelated subscription survives | Off, zero unregister calls |

- [ ] **5. Run red.** Run `lua tests/run.lua tests/test_sight_conditions.lua`. Expect the missing `copsAndRobbers/sightConditions` module.
- [ ] **6. Implement the solar read.** Use the wrapped time and normalized anchors with Task 1’s `daylight`. Cache the anchors or polar result by the keys in step 1. Read the current time each sample. Use the fallback order tested in step 2.
- [ ] **7. Implement fog and precipitation.** Distinguish both returns of the actual raw getter. Blend `sky.WEATHER` fogDensity values in slider units and divide by 1000 once when fallback is needed. Use `sky.weatherBlend()`'s already-smoothed progress for both interpolations.
- [ ] **8. Implement the bridge read.** Register the current runner’s key before each cache read. The bridge deduplicates this operation for the lifetime of the vehicle and clears its own state on destruction/replacement. Treat only electrical values 1 and 2 as on. Release local references on reset.
- [ ] **9. Run green.** Repeat the command in step 5 and compile the adapter with `luajit -bl client/lua/ge/extensions/copsAndRobbers/sightConditions.lua >/dev/null`. Expect 0 failed and exit 0.
- [ ] **10. Commit the adapter and tests** as `feat: sample visibility conditions from the game`.

## Task 3 · Locate authored streetlights near the runner

**Files**

- Create `client/lua/ge/extensions/copsAndRobbers/streetLights.lua` for map discovery and sampling.
- Create `tests/test_street_lights.lua` for a fake scene with class lists, indexed TSStatic fields, ID/name lookups, transforms and a counted ray function.

**Interfaces**

- `streetLights.beginMissionIndex()` queues map scene names once. `advance()` processes at most 128 queued names per frame.
- `streetLights.strength(targetCenter, cast) -> 0..1` reads the built cells. `clear()` discards all mission state.

- [ ] **1. Test emitter discovery.** Model West Coast’s `bridge_lightpole_light1111111` as a SpotLight with `nightLight="1"`, range 22 and outerAngle 160. Model Italy’s `areaLight_cityWallLights_0360631` as a PointLight with radius 10. Exercise direct and dynamic fields, including `"0"`. Add an untagged light named by an indexed TSStatic `child`, another with positive `nightIntensity`, a `nightEmissive` mesh with no emitter and an unmarked vehicle/camera searchlight. Only the two map emitters, child and intensity-managed light can yield positive samples.
- [ ] **2. Test live strength.** Place the radius-10 point overhead. Target distances 5, 7.5 and 10 m give 1, 0.5 and 0. Toggle the same object’s live `isEnabled` and intensity after indexing and expect 0 when disabled or at zero intensity. Give two overlapping lamps strengths 0.5 and 0.8 and expect 0.8. Check missing/non-finite position, intensity, radius or spot direction and expect no light from that emitter.
- [ ] **3. Test spotlight geometry and occlusion.** Set transform column 1 to (0,0,−1), target directly below within 11 m, clear ray returning cast length. Expect 1. Aim the spot up and expect 0. Put a target 79° then 81° off its axis, both inside range. Expect a positive result then 0. For the downward spot, have the ray return length −0.51 and then length −0.49. Expect 0 then 1. A nil, failing or non-finite ray gives 0.
- [ ] **4. Test indexing budgets.** Queue 300 names, including a fixture with multiple indexed/comma-separated children. Count names resolved on each advance, including work deferred from fixtures. Expect ≤128. Place the only eligible light last in the enumeration and expect strength 0 before it is processed. Call begin twice without clearing and assert each class list was fetched once. Clear and begin again and assert it was fetched twice.
- [ ] **5. Test query budgets and identity.** Cross x=0 with target and source on opposite sides. Use radius 80 and target distances 16, 24 and 32 m to assert the 32 m cap. Fill all nine cells with 17 emitters each, discovered in descending ID order, including a duplicate via a child. Assert the lowest 16 distinct IDs survive each cell, ≤144 indexed entries are considered and at most eight clearance rays run. With nine equally near eligible emitters make only the highest ID unobstructed. Expect 0. Remove a retained ID or resolve it to a different named emitter. Expect no bonus from the stale entry. Use counted lookup/cast stubs and fixture outcomes without shipping counters.
- [ ] **6. Run red.** Run `lua tests/run.lua tests/test_street_lights.lua`. Expect the new streetlight module to be missing.
- [ ] **7. Implement discovery and incremental indexing.** Enumerate PointLight, SpotLight and TSStatic names once per mission via the scene tree. In `advance()`, handle indexed `child` names using the installed `core/environment.lua`’s `refreshnightLightsObjects` / `addLinkedNightLights` conventions. Budget queued child lookups like top-level names. Validate class and authoring evidence, deduplicate and insert by stable scene ID into 32 m XY cells. Keep the lowest 16 entries per cell.
- [ ] **8. Implement the query.** Inspect the target cell and eight neighbours. Resolve and validate the stored emitters, order by 3D distance then ID, and apply the eight-candidate limit. Check live enabled state, positive intensity and capped radius/range. Gate spots by outer half-angle. Cast once per contributing candidate from emitter to runner centre with 0.5 m tolerance. Return the strongest clear contribution, or 0.
- [ ] **9. Run green.** Repeat step 6 (0 failed) and run `luajit -bl client/lua/ge/extensions/copsAndRobbers/streetLights.lua >/dev/null` (exit 0).
- [ ] **10. Commit the index and fixtures** as `feat: sample authored streetlights near the runner`.

## Task 4 · Sample from the assigned cars on the client

**Files**

- Modify `client/lua/ge/extensions/copsAndRobbers.lua` for round identities, targeted Practice setup, cadence, mission lifecycle and reports.
- Modify `client/lua/ge/extensions/copsAndRobbers/sight.lua` for attached-camera selection and guarded two-way rays.
- Modify `client/lua/ge/extensions/copsAndRobbers/ai.lua` for spawn serials, observer enumeration and the assigned human runner chase target.
- Modify `tests/client_stubs.lua` and `tests/test_client.lua`. Keep test spies on the new sight adapters local to the relevant tests.

**Interfaces**

- `sight.lookDirection(cop, useAttachedCamera) -> look, carForward` returns the selected gaze and the assigned car’s forward vector from this sample. Either may be nil. For AI both use the same heading. Compute `bearing(look, delta)` and `bearing(carForward, delta)` against the same car-to-runner displacement and pass both to `visibility.range` in that order. Use `sight.visible(eyePos, runnerPos, runnerDir, effectiveMeters, cast)` for final 3D distance and clearance.
- `ai.objects()` items gain `role`, `instance` and `reported`, retaining `id` and `obj`. The existing per-car `reported` flag identifies lifetimes included in the registration batch by `ai.tick(clock)`. The frame sends that batch before sight. `ai.tick(clock)` registrations become `{id, vid, instance}`. Each successful AI spawn gets a positive serial greater than any this connection has already issued.
- `cnr_sight` carries `{seen=boolean}` for the human or `{aiId=slot, instance=serial, seen=boolean}` for one AI cop. Task 5 consumes these fields.

- [ ] **1. Set up the client harness.** Extend the fake vehicle’s `getDirectionVector()` with a per-object override and its existing +Y default. In the sight fixtures explicitly set clear/dry noon, valid raw fog, a positive attached camera mode and free camera off. Use `env.tick(0.25, 0.25)` for exactly one sample. Keep unrelated helicopter and streetlight calls out of sight-ray counts by spying on the cast passed to `sight.visible`. Count calls to the conditions and streetlight adapters separately.
- [ ] **2. Write the side-street test.** Call `copInChase(env)`, put the round cop at (0,0,0) and `env.objects[300]` at (290,0,0). Its registered key is already `2-0`. Keep the cop’s heading +Y. Change only the camera for successive samples:

  | Camera / seat | Expected result for this human cop |
  |---|---|
  | Orbit, seat is cop, look +Y | false, no sight ray |
  | Orbit, seat is cop, look +X | true, first outgoing origin (0,0,1.2) |
  | Driver, chase, occupant or onboard driving view, +X | true |
  | Free camera, path, map, cinematic, relative or unknown mode looking +X | false using cop heading |
  | Another vehicle occupied, camera looks +X | false using original cop heading |
  | Re-enter cop, camera lookup throws or forward vector is near vertical | false using cop heading |

  Isolate rows or assert both the previous state and the change count with `countSentEv`: an unchanged value within five seconds sends no packet. While orbit looks +X, move the camera beyond a wall at x=5 and block all three outgoing car rays. Expect false.

  Using separate clear-day fixtures and a cop facing +Y, move the runner to (0,−180,0). Expect true with the gaze +Y. At (0,−260,0) expect false looking +Y and true looking −Y. Place the runner at (180,0,0) while the gaze is −X and expect false. This catches a mirror lobe that rotates with the camera. With the car heading unavailable and gaze +Y, a target at (0,−180,0) misses and one at (0,260,0) is seen. Block all three rays to the rear target at 180 m and expect false even with a valid mirror angle.

- [ ] **3. Pin the sight geometry.** In a direct `sight.visible` test place the cop origin at z=0 and runner origin at z=0.2 so the offset eyes are level. At exactly the effective range acquire. Move just outside it and expect false and zero casts. For a runner facing +Y block centre and front, clear the aft point in both directions and expect true. Block only the return from aft and expect false. Check the two-metre offsets, 0.5 m tolerance, invalid positions and nil/failed/non-finite cast results. Increase vertical separation enough to exceed the range while XY still fits and expect zero casts.
- [ ] **4. Pin remote target identity.** Use `env.addObject(301, vec3(0,50,0))` as a visible spare and `env.mpPlayers[2] = {activeVehicleID="2-1"}`. Add its `env.mpVehicles["2-1"]` entry. For the four steps below use `env.fire("cnr_roundCars", {keys=...})` and keep the spare visible throughout.

  | Round-car registration | Matching object | Sight / clearance work |
  |---|---|---|
  | Empty | Spare only | false, zero casts |
  | `{"2-0"}` | Spawned 300 at (0,100,0) | true, two clear casts |
  | Same | Entry marked unspawned/deleted, or GE object gone | false, zero casts |
  | Removed | Spare is still active | false, zero casts |

- [ ] **5. Test local placement lifetime.** Exercise initial replacement, a fresh personal spawn, repaint/rebuild and failed replacement. For each successful placement move focus to a different car before the next sight sample. Assert the new assigned ID still supplies the cop origin (or supplies the runner target in Practice). Destroy the assigned car, including while its acknowledgement is pending. Expect no acquisition from a spare or a reused stale identity. Follow the existing placement/cleanup tests when simulating the server-announced replacement.
- [ ] **6. Write the independent Practice reports test.** From `watchPractice` / `aiOnlySetup` use AI runner −10 and cops −11 and −12. Put the runner 290 m ahead of the first cop and behind the second in open daylight. Set the host maximum on the targeted setup to 400. Collect `env.sent` entries by `data.aiId`; AI iteration order is unspecified. Use the serials emitted by `cnr_aiVehicles`. With time relative to the first running sample, expect:

  | Time | Change | `cnr_sight` emitted |
  |---|---|---|
  | Prep and head start | Tick with all cars placed | None |
  | 0 | Release, first running sample | −11 true, −12 false |
  | +0.25 s | Flip −12 to face runner | −12 true only |
  | +4.75 s | No change | None since +0.25 |
  | +5.00 s | No change | −11 true only |
  | +5.25 s | No change | −12 true only |
  | +5.50 s | Remove visible −11 | −11 false using its previous serial |

  In a separate AI-only fixture place the runner 180 m directly behind one cop. Expect true even as the issuer rotates their camera. Move the runner to 210 m on the same axis and expect false. Rotate that cop car to face the runner and expect true.

  Repeat the attribution check for Practice as runner (two AI cop IDs and no human report) and as cop (human plus AI partner). An issuer changing camera direction affects only their attached human cop. Rebuild and assert the new registrations have strictly newer serials and fresh first observations. End and rejoin as an ordinary spectator or bystander. Expect no reports.

  **Late BeamMP vehicle IDs.** In an AI-only round hold back `MPVehicleGE.getVehicleByGameID(gameId)` for just one fake car, using the late-ID stub in the existing local placement test. Keep the AI cop looking straight at the AI runner at 290 m in daylight. Filter `env.sent` to that observer’s sight and both the observer and target registrations, retaining event order. Run each row from a fresh fixture and advance in 0.25 s frames:

  | At GO and +0.25 s | At +0.50 s | Expected order and timing |
  |---|---|---|
  | Runner registered. Cop’s GE object exists, but its VID is unavailable | Make the cop VID available | No sight report for this cop before registration. Emit its `cnr_aiVehicles` first, then its initial true at the first eligible sight tick, within 0.25 s of registration |
  | Cop registered. New AI runner’s GE object exists, but its VID is unavailable | Make the runner VID available | No true for the new target before its registration. Emit the runner registration first, then a fresh true at the first eligible sight tick |

  For the second order also rebuild a previously visible AI runner, leave its replacement VID unavailable for two ticks and allow the prior sight loss. The first true for the newly registered runner must arrive within one sight interval even if the cop’s previous true was less than five seconds ago. Compare the registration and sight indices in `env.sent` when both fire on one frame.

- [ ] **7. Test that HIDDEN leaves the AI pursuit running.** In Practice as a human runner, save the assigned runner object and change the occupied seat before `cnr_release`. Assert each cop’s `targetsOf(veh)` ends at that saved ID and its commands include `ai.setMode("chase")`. Save a command cursor. Expose the runner, block it with a wall, then clear it. Expect true/false/true and zero further `ai.setMode` or `ai.setTargetObjectID` commands from those three outcomes. Fire `cnr_penalty` / `cnr_penaltyEnd` with the cop slot while still in the other seat and assert the resumed target again. Repeat the release check with maximum 0: chase starts and no sight packet is sent. Exercise the existing late-`cnr_setupAI` after GO fixture for this target too.
- [ ] **8. Test bounded shared work.** For in-range humans and AI on the same tick expect one conditions sample. Expect one streetlight query at night and zero in full daylight. If all observers are beyond the host maximum or the target is missing expect zero such samples or rays and the necessary false report. An Off round, ordinary spectator and parked bystander generate no discovery or sight work. Start an eligible round, end it, spend a frame idle and start another on the same map: assert indexing pauses and resumes without another class scan. Exercise mission end, leave and extension unload separately. The next mission starts with an empty index.
- [ ] **9. Run red.** Run `lua tests/run.lua tests/test_client.lua` and inspect the failures. Existing radial sight can acquire the 290 m side target, the old remote lookup can select the active spare and Practice emits no per-AI observations.
- [ ] **10. Resolve the human cop and runner identities.** In `copsAndRobbers.lua`, use the existing `roundVehicle()` for the local round car. Main already uses `pendingPlacement.gameId` during placement and `personalCarId` afterwards. `placeVehicle` records the successful ID, `onVehicleDestroyed` and `endRound` clear it, and `updateCarCleanup` can recover a registered replacement for a public round. Ensure a failed placement/destruction cannot let sight reuse the prior assignment or a stale pending ID. For an AI runner use `ai.runnerObject()`. For a remote human runner extract the existing owner-prefix, spawned/deleted and GE-object checks inside `runnerObject()` and apply them only to `traffic.roundCar(runnerId)` for sight. Keep the active-vehicle fallback for existing non-sight callers.
- [ ] **11. Implement the camera and casts in `sight.lua`.** Use `commands.isFreeCamera()`, `core_camera.getActiveCamName(0)`, a matching assigned car in seat 0 and `core_camera.getForward()`. Accept `orbit`, `chase`, legacy `driver` and the `occupant.` and `onboard.` driving name prefixes (for example `onboard.hood`). Read the assigned cop car’s heading independently of camera success and return it as the second result. On missing or failed camera API, detached mode, wrong seat or unusable horizontal camera forward, use that heading for gaze as well. Feed the car’s world position to the existing 1.2 m eye calculation and fail a sample safely when its inputs or either required ray are unusable.
- [ ] **12. Bind AI driving and registration to the assigned cars.** In `ai.lua`, generate the next serial on every successful setup or rebuild spawn. Expose it through `objects()` and `tick()`. Pass the current bound human runner’s game ID into the chase resolver from `onRelease`, the late-release path in `onSetupAI` and `onPenaltyEnd`. Prefer the AI runner when one is assigned. Remove the occupied-seat fallback in that resolver. Keep flee targeting and existing driving commands in their release/penalty paths.
- [ ] **13. Connect the sampling loop.** Accept the maximum and AI authority from targeted `cnr_setupAI`, including when setup waited for local placement. Use the existing frame order that sends `ai.tick(clock)` registrations before sight. Expose the locally emitted registration state for each AI instance (including an AI runner). Wait to cache or send an AI cop’s first observation until its registration has been emitted. A new AI target becomes eligible for acquisition after its own registration is emitted. Reset the affected observer send state at each newly eligible lifetime so that the first observation goes out on the next sight tick even when its boolean matches a previous lifetime. Begin/advance the mission index during eligible setup/frames. At the 0.25 s sight gate, require running status, positive maximum and an authorized observer. Resolve the one runner, reject invalid or distant observer/target pairs, sample shared conditions once, and compute range separately from each observer’s gaze and car-forward cosines. Preserve nil car bearings through the range call. Query streetlighting once when D<1 and at least one observer can be in range. Reuse `sight.new()/step()` per observer. Retain enough state to send false on disappearance. Reset the relevant state at setup/replacement, teardown or role change and clear mission data on leave/end/unload. Keep helicopter, hiding and sight-independent driving on their existing paths.
- [ ] **14. Run green.** Run `lua tests/run.lua tests/test_visibility.lua tests/test_sight_conditions.lua tests/test_street_lights.lua tests/test_client.lua`. Expect 0 failed. Compile each changed game-side file:

  ```bash
  for file in client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/{ai,sight}.lua; do
    luajit -bl "$file" >/dev/null || exit 1
  done
  ```

- [ ] **15. Commit the client integration and fixtures** as `feat: evaluate sight from each assigned cop car`.

## Task 5 · Validate and attribute Practice AI reports on the server

**Files**

- Modify `server/CopsAndRobbers/main.lua` for targeted setup, `cnrOnAiVehicles`, `cnrOnSight`, deletion and registration lifetime.
- Modify `server/CopsAndRobbers/cnr/round.lua` for Practice authorization and observer invalidation. Reuse the grace/stale functions in `cnr/sight.lua` and the 3D distance check in the round’s existing sight aggregation.
- Modify `tests/test_round.lua` (observations, timing and records) and `tests/test_main.lua` (registered event handlers, vehicle ownership and payloads). Run the existing leaderboard suite as a regression check.

**Interfaces**

- `Round:sightReport(now, pid, seen)` accepts a human cop. `Round:aiSightReport(now, issuerPid, aiId, seen)` accepts an authorized Practice observation under the AI’s slot.
- `cnrOnAiVehicles` receives `{ai={{id, vid, instance}, ...}}` from the issuer. `carFor(slot)` continues to sample that issuer’s mapped VID. `cnrOnSight` checks the current registration before passing an AI observation to the round.

- [ ] **1. Write the round timing test.** Start a human-runner Practice using the setup from `test runner: AI cops can catch, nothing is recorded`, with helicopter off. Use `car(0)` for runner 1, `car(300)` for cop −10 and `car(450)` for cop −11. All are outside catch distance. Advance through countdown and head start to running before sending these reports. Check the effects returned by `r:tick(t, cars, {})` using `find`, with 0.25 s samples between transitions.

  | Time | Input | Expected aggregate |
  |---|---|---|
  | 12 | −10 reports true | `spotted=true`, live runner position |
  | 13 | −11 true, −10 false | Still spotted. The second cop is exactly within 400+50 |
  | 15 | Move −11 to 451 m, past −10’s grace | `spotted=false`, last-seen at runner |
  | 16 | −11 back at 300 m, fresh true | `spotted=true` |
  | 17 | −11 false | Remains spotted through 18.25 |
  | 18.5 | Exactly 1.5 s since loss | `spotted=false` |
  | 19 | −10 true with no subsequent keepalive | Counts at 30, expires at 30.25 |

  Check cop sight time goes to the slot that was in range. Use the previous tick’s total to detect a slot gaining sight time. In a separate test change the grace setting and verify loss at the configured boundary. End the Practice with `endCalled` and assert no `record` effect.

- [ ] **2. Write the server event fixture.** Use `boot()`, `env.panel(1, "test runner")`, `env.call("cnr_vehiclePicked", 1, PICK)`, `cnr_myVehicle` acknowledgement for the driving issuer, and the existing `env.go()` / 0.25 s `cnr_tick` loop. For AI-only, start with `sitOut(env, 1, true)` and the existing watcher fixture. Assert `decodeJson(sentTo(env, "cnr_setupAI", 1)).sightMaxMeters == 400` and `sentTo(env, "cnr_setupAI", 2) == nil`. Populate `env.vehicles[1][vid]` **and** `env.vidPositions["1-" .. vid]` for each fake live car. The harness's spawn hook and position stub do not populate the owner’s vehicle table.

  ```lua
  env.call("cnr_aiVehicles", 1, encode({ai={
    {id=-10, vid=2, instance=7},
    {id=-11, vid=3, instance=8},
  }}))
  env.call("cnr_sight", 1, encode({aiId=-10, instance=7, seen=true}))
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  assertEq(decodeJson(sentTo(env, "cnr_spotted", 1)).spotted, true)
  ```

  This event example is for the **human runner** fixture. In human-cop and AI-only fixtures, −10 is the AI runner and −11 is a cop. Check internal aggregate sight with round effects for all three roles. Check network deliveries against the existing audience for each role.

- [ ] **3. Test authorization and malformed inputs.** Repeat with a bystander sender, ordinary spectator, public round, head start, Off, AI runner slot, unknown negative slot, positive ID, fractional ID or instance, numeric strings, missing mapping, non-owned VID, wrong or absent serial, instance-only payload, non-boolean `seen` and invalid JSON. Use a valid report before and after each case to distinguish a rejected false from a real loss. In particular send a malformed AI payload from a valid human cop while the runner is visible to them: assert it neither creates a human true report nor clears an existing human sighting. Keep a positive control with legacy human `{"seen":true}`.
- [ ] **4. Test vehicle lifetime in the grace window.** With cop −10 seeing and cop −11 out of range, repeat its exact registration. Expect continued sight without another packet. Now report false to enter grace and replace the registration. For each row below, reset the fixture and inspect the next tick. Expect previous seen, lost-at and freshness to be invalidated immediately. A fresh matching report can reacquire.

  | Change | Delayed report to reject |
  |---|---|
  | Owner deletes slot −10’s VID 2, then reuses VID 2 with serial 9 | −10 / 7 |
  | Owner remaps −10 from VID 2 to VID 4 with serial 9 | −10 / 7 |
  | VID 2 moves from −10 to −11 with serial 9 | −10 / 7 |
  | Replace the AI runner while multiple cops have seen it | Existing reports clear immediately and fresh observations can reacquire |
  | Another owner deletes its own VID 2 | −10 / 7 remains valid under its actual owner |

  Exercise delayed superseded **registration** as well as a delayed sight message after same-VID reuse: the previous serial must not displace the new live instance. End and start a new Practice, reuse the same slot and VID, and repeat the stale-report assertion.

- [ ] **5. Pin scoring and persistence.** Complete a Practice with a successful AI sighting and assert `io.open(env.dir .. "data/leaderboard.json") == nil` on a fresh fixture. Run the existing recorded human sight/hidden-time and catch/assist fixtures. Add a two-human-cop test using `chasing({helicopter=false})` and both cars at 290 m. Replay the spec's timeline relative to a running tick: report true for cop 2 at 0, false at 2, true for cop 3 at 3, then false at 5. Tick every 0.25 s. Expect one spotted-on at 0, overlapping sight at 3 through 3.25, only cop 3 accruing sight from 3.5, and spotted-off plus one last-seen at 6.5. Advance the runner position after 6.5 and verify the sent last-seen position stays at the loss location before the next scheduled ping. Check human record and assist fixtures against their existing samples.
- [ ] **6. Run red.** Run `lua tests/run.lua tests/test_round.lua tests/test_main.lua tests/test_leaderboard.lua`. Expect failure for the missing round method, targeted maximum and accepted AI observation before implementation.
- [ ] **7. Implement round attribution.** Keep ordinary human reports restricted to running, rostered human cops. In `aiSightReport` require a running Practice, its exact issuer, positive host maximum, a rostered integer AI cop and boolean sight. Record via `sight.report(self.sight, aiId, seen, now)`. Keep distance eligibility in the existing per-tick aggregation against `carFor(slot)`. Grace, stale timeout, helicopter tracking and Practice record exclusion already have owners.
- [ ] **8. Implement registration lifetime.** In `cnrOnAiVehicles` validate the issuer, roster, integer fields and actual ownership/liveness of each supplied VID. Track serial ordering per affected slot/VID so registrations for independent vehicles can arrive in either order. Track each current instance alongside the slot–VID mapping. A newer spawn takes over its slot and invalidates any former user of its VID. Ignore duplicate live registrations and stale serials. Preserve the existing AI position, chase/catch and traffic registration consumers. If a legacy registration has no serial, it cannot authorize sight. Update their harness fixtures for the real owner vehicle list and new wire form where appropriate.
- [ ] **9. Wire invalidation and event dispatch.** Use `sight.forget` for every affected observing slot, and clear all observers when the assigned AI runner is removed/replaced. Keep enough lifetime information to reject delayed old registrations after deletion. Clear mappings throughout existing round teardown/reset paths. In `cnrOnSight` enforce the boolean before dispatch. If either optional AI field is supplied validate both fields, current issuer, roster, live mapping and instance. Put the host maximum in the pending targeted AI setup payload so both immediate and delayed sends carry it.
- [ ] **10. Run green.** Repeat step 6 and run `make test`. Expect 0 failed in both, including existing Practice movement, AI-only catching, human leaderboard and helicopter cases.
- [ ] **11. Commit the round, handler and fixtures** as `feat: validate sight reports for practice AI cops`.

## Task 6 · Explain, verify and stage the reviewed build

**Files**

- Modify `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` (runner and cop instructions), `client/ui/modules/apps/CopsAndRobbersPanel/settings.js` (Sight range help) and `README.md` (chase/HUD explanation).
- Modify `docs/DEPENDENCIES.md` with the camera, solar events/values, raw fog + LevelInfo, keyed vehicle bridge and map-light interfaces. Record each map fixture by name and what its live state establishes.

- [ ] **1. Update player copy.** Describe Sight range as the clear-day distance in the direction the cop looks. Explain the mirrors’ half-range directly behind the car, full range on a deliberate look back, darkness, weather, runner lights and the shared ground-sight indicator. Keep the existing `dist("sightMaxMeters")` unit conversion, Off help, HUD labels and helicopter exception.
- [ ] **2. Run repository checks.** Run `make test` (0 failed), `make vuecheck` (Vue, JS and UI tests exit 0), then `make package` (both `dist/Client/CopsAndRobbers.zip` and `dist/Server/CopsAndRobbers/main.lua` exist). Byte-compile every changed game-side Lua file:

  ```bash
  for file in client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/{ai,sight,visibility,sightConditions,streetLights}.lua; do
    luajit -bl "$file" >/dev/null || exit 1
  done
  ```

- [ ] **3. Commit and review.** Commit the UI and docs as `docs: explain sight direction and visibility conditions`. Have a fresh reviewer inspect the full branch diff, particularly registration versus sight ordering and setup arriving after GO. Re-review fixes and rerun affected checks. Stage the resulting reviewed SHA.
- [ ] **4. Install the reviewed snapshot locally.** From the reviewed feature worktree run the following with its reviewed HEAD. Then restart the local BeamMP server from the main checkout’s `.testserver` using its existing launch method. Check `.testserver/Server.log` for the expected loaded version and Lua errors. Report the recorded SHA to the player. The player handles game and launcher restarts.

  ```bash
  set -e -o pipefail
  reviewed_sha=$(git rev-parse HEAD)
  test_server=<repo>/.testserver
  snapshot=$(mktemp -d)
  git archive "$reviewed_sha" | tar -x -C "$snapshot"
  (
    set -e
    cd "$snapshot"
    if test -f "$test_server/Resources/Server/CopsAndRobbers/config.json"; then
      cp "$test_server/Resources/Server/CopsAndRobbers/config.json" server/CopsAndRobbers/config.json
    fi
    make install-local TESTSERVER="$test_server"
  )
  ```

- [ ] **5. Probe the engine APIs first.** Use a temporary GE extension in the game’s current `lua/ge/extensions/` directory. In freeroam, log tagged camera mode/forward readings while changing driving/free views, solar anchors and clock, LevelInfo and raw fog, and bridge values as the assigned vehicle’s lamps change. Sample the named West Coast spot under its light and outside it, and inspect Italy’s named point light at night. Check live enabled state, intensity, radius/range, transform column 1 for the spot, and whether the lit road returns positive strength. Read the probe tag in `~/.local/share/BeamNG/BeamNG.drive/current/beamng.log`.
- [ ] **6. Capture each observer’s gaze angle, rear angle and sight result.** In the temporary probe wrap the shared module functions used by the reviewed build. Call each original exactly once and preserve its return values.
  - At each `sight.lookDirection(cop, useAttachedCamera)` call, discard any unfinished sample. Start a new one with the observer’s game ID, position and both returned vectors (gaze and assigned-car forward). Match AI game IDs to `ai.objects()` for slot and serial. A human uses the assigned cop object passed to this call.
  - Wrap the two `visibility.bearing(axis, delta)` calls for the current observer. Record each input and result in call order (gaze first, car forward second), including nil results. Verify both calls use the same XY delta. At `visibility.range` confirm the two cosine arguments match the captured results and retain the effective metres returned. At `sight.visible(eyePos, runnerPos, runnerDir, effectiveMeters, cast)` require a matching cop position, delta and effective metres. Log the observer, both positions, gaze angle θ, rear angle β, effective range and the original distance and sight result. Compute θ with `deg(acos(gazeCos))` and β with `deg(acos(-carForwardCos))` for available values. Log unavailable angles as missing.
  - Clear pending data after each visible call, at the next observer’s look call, and each frame and round boundary. An observer rejected before direction or distance sampling contributes no completed row. Omit unmatched or incomplete rows. Check the log with two opposed AI headings, then remove one cop or move it beyond the host maximum. Only the remaining cop should produce paired readings on the next tick.
  - Restore the wrapped functions on probe unload. Supply one comment-free GE console line per experiment and ask before deleting the probe from the player’s game folder.
- [ ] **7. Single player, looking down a side street.** In clear-day Practice as cop, hold the car heading with the AI runner 200–400 m away in an open side street. Turn the attached view toward and away. Expect that cop’s acquisition when looking down the street and loss after grace when looking away. If the partner cop sees the runner, inspect individual probe readings. Orbit over a wall with the car behind it and expect that car’s sight to stay blocked. This checks camera classification, wall placement and how turning feels.

  On an open straight, hold the car heading with the runner about 260 m directly behind the car. Turn the attached view from forward to straight back. Look for β near zero in both samples and range rising from about 200 to 400 m as the cop acquires. This checks how the mirror allowance and deliberate look feel in pursuit.
- [ ] **8. Single player, night lighting.** In night Practice as runner, cross from a visibly lit patch into darkness and toggle low beam. Compare a cop’s logged ranges at similar bearing. Account for its movement using logged distance. Expect shorter range off the lit patch and longer range with lamps on. This checks whether the sampled light matches what the driver sees.
- [ ] **9. Two clients, remote lamps.** On a clear night leave about 170 m on an unlit straight between a runner and the cop looking toward them. Turn off automatic headlights and toggle the runner’s lamps. Allow time for replication and grace. Expect on/off on the cop’s GE bridge, SPOTTED/HIDDEN on the runner and the corresponding sight transition on the cop. This check needs a second client to observe remote electrics.
- [ ] **10. Close the local check.** Wait for results or explicit deferral. Record any deferred actions, expected results and uncertainty in main’s ledger under **In-game checks**. After authorized merge follow main’s separate version bump and verification before clearing the entry. Live deployment requires the user’s request for this release.
