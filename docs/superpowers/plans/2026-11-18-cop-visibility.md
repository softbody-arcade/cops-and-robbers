# Directional cop visibility implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement one task at a time once the user approves the plan and authorizes the build. Steps use checkboxes for tracking.

**Goal:** Let human and Practice AI cops acquire the runner according to look direction, actual lighting, weather and clear line of sight.

**Architecture:** The client computes the effective range and tests the existing car-to-car rays. Each cop has a separate report stream. The server validates the sender, roster and distance before feeding the observation to its existing tracking and scoring code.

**Tech stack:** BeamNG GE LuaJIT, BeamMP client and server Lua, the repository’s Lua test runner and existing Vue player instructions.

**Spec:** [Where a cop can spot the runner](../specs/2026-11-18-cop-visibility-design.md)

## Global constraints

- Default clear-day front/side/rear = 400/200/100 m. Scale with the current host maximum. Off = 0. Use the proportions and proposed environmental factors in the spec.
- Sample at 4 Hz. Human observer position is the assigned round car. Practice AI always uses its own car and heading. Preserve 3 target points, two-way static clearance, 5 s keepalive, 11 s staleness, configured grace (default 1.5 s) and the existing server cap of maximum + 50 m.
- Production authority belongs to the reporting human cop. Practice AI observations belong to the reporting issuer’s rostered negative cop slots. Practice generates no leaderboard records. AI cops continue pursuing the assigned runner when sight drops. Existing BeamNG driving commands stay independent of sight reports.
- Work on an isolated feature worktree rebased or brought up to date with reviewed main when authorized. Read current main guidance and the shared ledger before implementation. Follow current round-car placement, bystander and spectator flows where main has evolved. Keep version changes on main after merge. Add source comments only on request.

## Review focus

| Failure mode | Check |
|---|---|
| Free camera, parked personal car or spectator watching the runner shifts the sight origin | Task 4 verifies the bound car and fallback heading with independent car, seat and camera poses. |
| A replacement runner temporarily inherits lit lamps from the previous vehicle | Task 2 changes the target, reuses its ID and delays the new bridge value. |
| A lamp leaks through a wall or comes from a camera, or dense scenery stalls the chase | Task 3 counts lookups and rays, including an obstructed spotlight and overflow cell. |
| Two Practice cops overwrite one another, or somebody else reports for them | Tasks 4 and 5 exercise independent client keepalives, roster validation and all three Practice roles. |
| A missing weather input or unusual map date jumps to clear-day range | Tasks 1 and 2 sample wraparound, polar, non-finite and absent values. |

## Task 1 · Range calculation

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/visibility.lua` and `tests/test_visibility.lua`. The GE-facing modules follow in later tasks.

**Interfaces:** `visibility.range(maxMeters, cosAngle, daylight, lampsOn, streetStrength, rawFog, precipitationFactor) -> metres` consumes finite numbers plus a boolean lamp state. `visibility.bearing(look, delta) -> cosAngle` accepts vectors with x/y. `visibility.daylight(time, sunrise, sunset) -> 0..1 or nil` uses normalized clock values.

- [ ] Add failing range and bearing tests using the spec’s examples. Include left/right symmetry, looking backwards, gradients between anchors, scaling, 0 and unusable XY vectors. Include the whole weather/light table, fog clamping and non-finite results. Example assertions:

  ```lua
  assertNear(visibility.range(400, 0, 1, false, 0, 0.0004, 1), 200, 1e-9)
  assertNear(visibility.range(400, -1, 0, true, 1, 0.0004, 1), 75, 1e-9)
  assertNear(visibility.range(400, 1, 1, false, 0, 0.015, 1), 160, 1e-9)
  assertEq(visibility.range(0, 1, 1, true, 1, 0, 1), 0)
  assertEq(visibility.bearing({x=0, y=0}, {x=0, y=1}), -1)
  ```

- [ ] Add a wrapped day (sunrise 0.75, sunset 0.25), asserting D=1 at time 0, 0 at 0.5 and 0.5 at both crossings. Check ±30 minutes around each crossing, identical anchors and missing inputs. Run `lua tests/run.lua tests/test_visibility.lua` and see the new tests fail for the absent module.
- [ ] Implement the three pure functions. Clamp the normalized XY dot, treat lengths ≤0.001 as unusable, and use finite individual defaults (Off for an invalid maximum, shortest angle, dark, unlit, dense fog and 0.70 for invalid inputs). Unit-clamp D and S and bound the precipitation multiplier to [0.70,1]. Implement the spec’s smoothstep around the nearest circular sunrise/sunset boundary.
- [ ] Run the focused test again (0 failed) and compile the new game-side file with `luajit -bl client/lua/ge/extensions/copsAndRobbers/visibility.lua >/dev/null`. Commit as `feat: calculate directional visibility range`.

## Task 2 · Read daylight, weather and runner lamps

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/sightConditions.lua` and `tests/test_sight_conditions.lua`. Reuse the sky module’s `WEATHER` and `weatherBlend()`, and Task 1’s daylight helper.

**Interfaces:** `sightConditions.sample(runner) -> daylight, lampsOn, rawFog, precipitationFactor`; `sightConditions.reset()` drops cached mission/target state. Reads from GE environment, solar and vehicle bridge adapters through the existing game globals. The runner argument is a vehicle object or nil.

- [ ] Pin solar fallback precedence, polar day/night, date/location/timezone change, wrapped twilight, direct raw density (including 0 with LevelInfo present), and absent LevelInfo (engine can return 0,nil). Assert that a midpoint between clear and rain gives fallback raw fog 0.0012 and precipitation 0.925. With valid raw 0.0035, retain that exact density. Test nil/unknown endpoints, invalid progress and stable equal endpoints.
- [ ] Stub the real bridge signatures. With runner A reporting 2 and B initially nil, expect true then false, then true when B’s cache reaches 1, false when it reaches 0. Reuse B’s ID after a bridge destruction or replacement and ensure the current vehicle gets a new registration and the missing value gives false. Count registrations/queued notifications, include an existing third-party subscription and prove reset cannot disable it.
- [ ] Run `lua tests/run.lua tests/test_sight_conditions.lua` and see the missing adapter fail. Implement the interface, including the spec’s clock cache key, finite checks and fallback precedence. `registerValueChangeNotification` is idempotent in the shared cache. Calling it for the current runner before reading on each 4 Hz sample handles same-ID replacements while the bridge suppresses duplicate vehicle commands. Do not unregister shared listeners. Use the raw fog getter’s second return to distinguish an absent LevelInfo; if a fallback preset is needed, convert its density from slider units once.
- [ ] Run the focused suite (0 failed) and compile the new file with `luajit -bl client/lua/ge/extensions/copsAndRobbers/sightConditions.lua >/dev/null`. Commit as `feat: sample visibility conditions from the game`.

## Task 3 · Locate streetlight illumination

**Files:** Create `client/lua/ge/extensions/copsAndRobbers/streetLights.lua` and `tests/test_street_lights.lua`.

**Interfaces:** `streetLights.beginMissionIndex()` captures map light/fixture lists once, `streetLights.advance()` processes up to 128 queued names per frame, `streetLights.strength(targetCenter, cast) -> 0..1` queries the built cells, and `streetLights.clear()` releases mission data. These functions read the scene tree and never create or mutate light objects.

- [ ] Add scene fixtures shaped like the West Coast bridge spot and Italy point light named in the spec. Include an enabled linked child, intensity-managed fixture, unlit emissive mesh, unmarked searchlight, disabled lamp, enabled zero-intensity lamp, wrong facing spot, point directly above, out-of-range runner, and a wall between fixture and runner. Assert full strength at 0.5 radius, 0.5 at 0.75 radius and 0 at the boundary, using 3D distance. Assert the maximum when two lamps overlap.
- [ ] Pin work limits across frames and queries. Cover negative cell coordinates, 32 m cap, shared cell overflow, duplicates via child and tag, missing/reused/deleted IDs, and a change of mission. Use counters to assert one discovery per mission, ≤128 names processed per frame, ≤144 stored entries examined per query and ≤8 single obstruction rays. A partial index returns only established positive matches.
- [ ] Run `lua tests/run.lua tests/test_street_lights.lua` to see the missing module fail. Index scene names via `scenetree.findClassObjects`, `findObject`, and TSStatic indexed `child` fields following `core/environment.lua`’s `refreshnightLightsObjects`. Read direct, dynamic and ordinary fields with proper string-bool parsing. Resolve stable IDs back to expected emitters at query time and recheck live `isEnabled` and intensity. Require valid positive point `radius` or spot `range`. Use the spot transform’s local +Y axis (column 1), half of `outerAngle` in degrees, and a clear segment to the runner’s centre (0.5 m tolerance). Reject unknowns. Ignore duplicate IDs and retain the lowest 16 per cell.
- [ ] Run the focused suite (0 failed) and compile the new game-side file. Commit as `feat: sample authored streetlights near the runner`.

## Task 4 · Evaluate human and Practice cop sight on the client

**Files:** Modify `client/lua/ge/extensions/copsAndRobbers.lua`, `client/lua/ge/extensions/copsAndRobbers/sight.lua`, `client/lua/ge/extensions/copsAndRobbers/ai.lua`, `tests/client_stubs.lua` and `tests/test_client.lua`.

**Interfaces:** Extend `ai.objects()` items with `role`, retaining `id` and `obj`, and expose the current `instance` (positive integer spawn serial). Continue using `sight.visible(eyePos, runnerPos, runnerDir, maxMeters, cast)`, now with the computed range. Add `sight.lookDirection(cop, useAttachedCamera) -> vec3 or nil` with Task 1’s bearing fallback. Keep `sight.new()/step()` per human or AI observer. AI reports add numeric `aiId` and `instance` together.

- [ ] Add client tests with separated car, camera, traffic and runner objects. With a runner 290 m to the side in clear daylight expect false, then true after rotating the attached camera. Place a wall between the cars and move the camera beyond it. Expect false and capture ray origins at the cop car. Free, path, map, unknown, vertical and failed camera reads use the bound car’s heading. A detached camera pointing at the target must never increase the range. Test newly spawned and rebuilt round cars, a missing car and a switched seat.
- [ ] Exercise Practice as runner, cop and AI-only watcher. Two AI cops facing opposite ways must send independent `seen` values, transitions and 5 s keepalives. Removing one previously visible car gives that slot a false update. After GO, capture the AI cop’s queued driving commands. Force sight true → false behind cover and verify a false report, the original `ai.setTargetObjectID` and chase mode, and zero subsequent target-clear, mode-change or retarget commands caused by the sight loss. Changing the issuer camera should affect only the driving human cop. Confirm no events before GO, as a regular spectator/bystander, or while Off, and no stale AI state after round-end, reconnect, setup/rebuild or role change. Count 1 weather/runner-lamp sample and at most 1 streetlight query per sight tick across all observers, zero ineligible work when Off.
- [ ] Run `lua tests/run.lua tests/test_client.lua`, observe failures for side acquisition and AI events. Update existing sight test fixtures to explicitly represent a clear day, dry weather and an attached forward-looking camera where those facts determine the assertion.
- [ ] Bind the local round vehicle ID on every successful `placeVehicle` and clear it on failure/end. For an in-place setup verify that the current local vehicle is the round car. Resolve a Practice human runner from that ID; retain `runnerObject()` for AI and remote runners with existing round-car registration/traffic exclusion. Use the captured car as the origin even after a seat change. Use `commands.isFreeCamera()`, `core_camera.getActiveCamName(0)`, matching seat ID and `core_camera.getForward()` only for positively identified driving modes (`orbit`, `chase`, `driver`, `occupant.*`, `onboard.*`). Missing API, exception or near-vertical XY length ≤0.001 falls back to car forward.
- [ ] Wire Tasks 1–3 into the existing 0.25 s cadence. Order the work by active phase and observer authority, actual target and coarse max range, shared conditions, effective per-observer range, then two-way sight rays. Handle missing or failing ray results as blocked and retain the existing point heights/spread/tolerance. Assign a new session-monotonic serial on every successful AI spawn or rebuild. Include it in `ai.tick`’s existing {id,vid} registration and AI sight reports. Keep per-slot change/keepalive state, iterate prior slots to flush a disappeared observer, and reset state when round setup or identities change. Initialize and advance the index outside sight sampling only in eligible non-Off rounds. Drop mission caches on leave, teardown and unload. Read `sightMaxMeters` for the Practice issuer from its targeted `cnr_setupAI` too, independent of human role or spectator status.
- [ ] Rerun client and new focused suites (0 failed), compile the changed client Lua files, then commit as `feat: evaluate sight from each assigned cop car`.

## Task 5 · Accept authorized Practice AI reports

**Files:** Modify `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/cnr/round.lua`, `tests/test_main.lua` and `tests/test_round.lua`. Existing `cnr/sight.lua` supplies grace and expiry.

**Interfaces:** Keep `Round:sightReport(now, pid, seen)` for human cops. Add `Round:aiSightReport(now, issuerPid, aiId, seen)`. The server handler checks a registered `aiVid[aiId]` and matching positive-integer instance serial for the current Practice before dispatch. Keep server-side `carFor(aiId)` for observed distance.

- [ ] Drive the registered event in tests with two AI cops and an issuer driving as runner, cop and watching. Only the issuer’s valid report for a mapped, rostered AI cop in running Practice can update that slot. Exercise foreign issuers, bystanders, public rounds, head start, Off, absent vehicle mapping, the runner’s negative slot, positive ids, numeric strings, fractional/unknown IDs, invalid JSON stale or missing instance serials and nonboolean `seen`. A malformed AI report must never fall through as a human report. Assert only targeted AI setup carries the needed max to the watching issuer.
- [ ] Place the two cops at different sampled positions. Assert only a positive in-range observer counts, a cop at 451 m with host max 400 cannot spot, false transitions respect 1.5 s grace, staleness expires after 11 s, and losing one cop preserves aggregate sight while the other still sees. Delete a registered vehicle, remap a slot, reassign its former VID to another slot, and reuse a VID for a new instance in the grace window. Assert both old true and lost-at state disappear immediately. A delayed old-instance report cannot revive sight. Verify the existing leaderboard persistence path receives no practice record, and a normal human-only round retains sight/hidden time and assist credit with the same recorded samples.
- [ ] Run `lua tests/run.lua tests/test_main.lua tests/test_round.lua tests/test_leaderboard.lua` and see the new valid AI report and setup tests fail. Dispatch the two payload forms only on strict type/range/issuer/role/phase checks and use the slot in `sight.report`. Include the existing config’s maximum in targeted `cnr_setupAI`. Reuse existing server roster, vehicle-registration and Practice exclusion rules; check registration belongs to the issuer and refers to a live owned VID. Track the current instance alongside the existing slot–VID mapping. On `cnrOnVehicleDeleted`, remap, VID reassignment and teardown, clear mapping and use `sight.forget` for each affected cop (all observers if the AI runner changed). An identical repeat registration preserves state. Require a fresh matching report for the new registration.
- [ ] Rerun these suites (0 failed) and `make test`. Commit as `feat: validate sight reports for practice AI cops`.

## Task 6 · Explain, verify and stage

**Files:** Update the existing sight entries in `README.md`, `docs/DEPENDENCIES.md`, `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` and `client/ui/modules/apps/CopsAndRobbersPanel/settings.js`.

- [ ] Describe the setting as clear-day range in the look direction. Keep translated distance formatting, Off help and existing HUD labels. Explain how turning the view, poor weather and runner lighting affect spotting. Add the checked camera, solar, fog, light bridge and map object interfaces to the compatibility guide with the two named map fixtures.
- [ ] Run `make test`, `make vuecheck`, `make package` and `luajit -bl path/to/file.lua >/dev/null` for each changed game-side Lua file. Expect zero failed tests, successful compilation and both packaged payloads. Commit as `docs: explain sight direction and visibility conditions`. Pass the full diff to a fresh reviewer. Resolve findings and rerun the affected checks.
- [ ] Stage the reviewed SHA from a disposable `git archive` snapshot with the installed local config copied into the snapshot before `make install-local`. Follow main’s AGENTS.md for the absolute test-server path and restart. Report the SHA and check the server log. Leave the game/launcher restart to the user.
- [ ] First probe the engine in freeroam. Use a temporary tagged GE extension to sample camera mode/forward, solar anchors, raw fog with LevelInfo, runner bridge transitions and the live bridge spot/Italy point’s actual transform, enabled state, intensity and reach. Read its output in `beamng.log`. Verify that the West Coast spot points toward the road and grants strength under it, then zero outside it. Issue one comment-free GE console line per experiment. Ask before deleting the probe.
- [ ] **Single player, feel of looking.** In clear-day Practice as cop, use an open side street with the AI runner 200–400 m away. Hold the car heading, rotate the attached view toward and away from the runner. Expect acquisition facing them and loss after grace facing away when no other cop sees them. Check individual sight in the tagged log if the AI partner maintains aggregate sight. For a wall, look over it with orbit camera while the car stays behind it. Expect the car’s sight to remain blocked.
- [ ] **Single player, night lighting.** In night Practice as runner, drive from a lit patch onto a dark stretch and toggle low beam. Use the tagged per-cop distance and range with a consistent bearing to distinguish actual changes from the AI moving. The readable range should decrease outside the lit patch and increase when lamps come on. Compare the sampled values with the pool of light the player sees.
- [ ] **Two clients, remote lamps only.** In a night round on an unlit straight, park the runner about 170 m ahead of a cop looking at them. Disable automatic headlights, toggle runner lamps on/off, wait for replication and grace. The cop’s bridge state and sight should follow and the runner’s HUD should report the transition. This resolves remote electrics delivery across independently running clients.
- [ ] Wait for the local result or explicit deferral of any outstanding game checks, recording deferred steps in main’s ledger. Merge only after authorization requirements are met. Follow main’s separate post-merge version bump and verification before clearing the ledger. Live deployment needs its own user request.
