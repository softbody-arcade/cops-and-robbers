# The Pigeon as the Helicopter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the helicopter gets a visible body: a trimmed, scaled Pigeon van in the Bird Response livery that flies with the helicopter, tilts and banks, and runs aviation lights.

**Architecture:**
- **Pure:** `copsAndRobbers/heliModel.lua` holds the trim (`trim`), the livery rename (`skin`), the attitude (`newPose`, `step`), the model-to-world mapping (`place`), the light offsets (`LIGHTS`) and the beacon timing (`beaconOn`). No game calls.
- **Game-facing:** `copsAndRobbers/heliVan.lua` makes the copy once per session (`prepare`), creates, moves and removes the `TSStatic` named `cnr_heli_van` (`tick`, `clear`), and draws the lights. It is shaped like `heliSound.lua`: found by name every tick, guarded with `pcall`, one log line per failure.
- **Wiring:** `heliSearch.flying(state, clock)` says when the helicopter is present (it already drives the sound level). `copsAndRobbers.lua` prepares the copy when the round's helicopter is set, ticks the van after the light, and clears it in `endRound`. A new player setting `model` gates it.

**Tech Stack:** Lua (LuaJIT in game, Lua 5.x in tests), Vue 3 for the settings row. `make test`, `make vuecheck`, `make package`.

**Spec:** `docs/superpowers/specs/2026-11-17-pigeon-helicopter-design.md`, plus the user's additions relayed during the build: 3x scale, the Bird Response livery, aviation lights. The probe `.superpowers/cnrprobe-reference.lua` holds the proven hide list and trim.

## Global Constraints

- No code comments, no emojis. LuaJIT-safe: no `goto`, `//` or bit operators; `vec3` is cdata in game.
- No version bump, no `TODO.md` edit.
- **Source:** `/vehicles/pigeon/pigeon.dae`. **Materials, loaded before any shape is made:** `/vehicles/pigeon/main.materials.json`, `/vehicles/pigeon/dynamicDecals/main.materials.json`, `/vehicles/pigeon/skin.materials.json`.
- **Hide list:** the probe's 46 names plus `pigeon_taillight_L`, `pigeon_taillight_R`.
- **Livery:** in the copy, `<material id="pigeon-material" name="pigeon">` gets `name="pigeon.skin.birdabduction"`; nothing else changes.
- **Paint:** `instanceColor` `0.9 0.9 0.92 1`, `instanceColor1` and `instanceColor2` `0.12 0.47 0.74 1`.
- **Scale:** `heliModel.SCALE = 3`, uniform; the searchlight's anchor under the van scales with it.
- **Lights:** red left, green right, white at the box's rear, steady; red beacons on the roof and underneath, on 0.15 s every 1.0 s. Drawn as debug spheres (core plus glow), no light sources, no white strobes.
- **Setting:** `model`, default true, "Helicopter model", next to "Helicopter sound".
- **Nothing left behind:** no `cnr_heli_van` after a round end, a cancel, leaving, a map change or unload.

## Review Focus

1. **A copy that can't be made** (no Pigeon, `readFile` nil or throwing, `writeFile` nil, no listed part found) means no van, one log line for the session, and the light and sound unchanged. Pinned in Task 2 and Task 3.
2. **A hover or slow flight** keeps the last heading instead of snapping to a noisy velocity. Pinned in Task 1.
3. **A new flight** (after a refuel) starts a fresh pose, so the old velocity gives no spurious tilt. Pinned in Task 2.
4. **A van deleted by someone else** is made again on the next tick; a leftover van while none is wanted is swept about once a second. Pinned in Task 2.
5. **The same copy on a later session** is not rewritten, so the game's compiled shape cache stays valid; older copies are removed. Pinned in Task 2.

---

### Task 1: the pure model module

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heliModel.lua`
- Test: `tests/test_heli_model.lua`

**Interfaces:**
- **Produces:** `trim(src, names) -> text, removed`; `skin(text, id, name) -> text, changed`; `newPose() -> pose`; `step(pose, vel, dt)`; `place(pose, pos, mx, my, mz) -> x, y, z`; `beaconOn(clock) -> boolean`; constants `SOURCE`, `MATERIAL_FILES`, `HIDE`, `BODY_MATERIAL` (`"pigeon-material"`), `SKIN` (`"pigeon.skin.birdabduction"`), `SCALE`, `ANCHOR_Y`, `ANCHOR_Z`, `LIGHTS` (`{ x, y, z, r, g, b, beacon }` in model metres), `BEACON_PERIOD`, `BEACON_ON`. The pose carries `yaw` (radians), `pitch`, `bank` (degrees, pitch positive nose-down, bank positive left side down) and the frame `fx fy fz` (nose), `ux uy uz` (roof), `lx ly lz` (left).

- [ ] **Step 1: Write the failing tests** in `tests/test_heli_model.lua`:
  - "trim removes the listed flat nodes and keeps the rest": a fake dae with nodes `a`, `a_b`, `c` and a `library_geometries` tail; `trim(src, { "a", "c", "missing", "a" })` keeps `a_b` and the tail byte for byte, removes `a` and `c`, returns `removed == 2`.
  - "the hide list carries the tail lights": `HIDE` holds `pigeon_taillight_L`, `pigeon_taillight_R` and 48 names.
  - "skin renames only the body material": `skin` turns `<material id="pigeon-material" name="pigeon">` into `name="pigeon.skin.birdabduction"`, leaves `instance_material ... target="#pigeon-material"` and other materials untouched, returns `changed == true`; without the element it returns the text unchanged and `false`.
  - "the pose points along the flight and holds it when slow": velocity `(10, 0, 0)` then `(0, 10, 0)` turns the yaw toward `pi/2` over about 1 s, never jumping; velocity `(0.5, 0.5, 0)` keeps the last yaw.
  - "speeding up pitches the nose down, slowing pitches it up, capped": rising forward speed gives `pitch > 0`, falling gives `pitch < 0`, never past `PITCH_MAX`, and the first frame after a change moves it by less than a third of the way.
  - "a left turn banks the roof to the left, capped": a velocity turning counterclockwise gives `bank > 0` and `ux*lx + uy*ly + uz*lz`-side tilt to the left (roof leans toward `l`), never past `BANK_MAX`.
  - "place keeps left on the left as it turns": for yaws 0, 90, 200 degrees the port light (`LIGHTS` red) lands left of the nose and the starboard light right; the anchor `(0, ANCHOR_Y, ANCHOR_Z)` lands on `pos`; distances scale by `SCALE`.
  - "the beacon flashes 0.15 s each second": `beaconOn` true at 0, 0.1, 1.05, false at 0.2, 0.9, 1.5.
- [ ] **Step 2: Run** `make test`. Expected: the new file fails (module not found).
- [ ] **Step 3: Implement** `heliModel.lua`. The trim cuts each listed name's `<node id="NAME"` up to its `</node>` once, sorted, skipping overlaps. The van's nose is model `-Y`, roof `+Z`, left `+X`. The pose smooths the horizontal acceleration (`TILT_SECONDS`) and the yaw (`TURN_SECONDS`); pitch is `PITCH_PER_ACCEL` x forward acceleration, bank `BANK_PER_ACCEL` x left acceleration, each capped.
- [ ] **Step 4: Run** `make test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: the helicopter model's trim, livery, attitude and light offsets`.

### Task 2: the van in the scene

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/heliVan.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/heliSearch.lua` (`flying`), `heli.lua` (`M.flying`)
- Modify: `tests/env_stubs.lua` (`setPosRot`, `setScale` on fake objects), `tests/client_stubs.lua` (`quatFromDir` result gets `setFromDir`)
- Test: `tests/test_heli_van.lua`

**Interfaces:**
- **Consumes:** Task 1.
- **Produces:** `heliVan.NAME = "cnr_heli_van"`, `new()`, `prepare(s) -> path|nil`, `tick(s, flight, clock, night, camPos)`, `clear(s)`; `heliSearch.flying(state, clock) -> flight|nil` (nil when there is no flight or the target has been missing over `TARGET_MISSING_SECONDS`), re-exported as `heli.flying`.

- [ ] **Step 1: Write the failing tests** in `tests/test_heli_van.lua` with stubbed `createObject`, `scenetree`, `readFile`, `writeFile`, `FS`, `loadJsonMaterialsFile`, `quatFromDir`, `color` and `utils/debugDraw`:
  - "prepare loads the materials, trims, renames the livery and writes one copy per session": the written path is `/temp/cnr/pigeon_heli_<length>.dae`, the text has no hidden node and the skin name; a second `prepare` reads nothing; one info log line.
  - "an unchanged copy is not rewritten and older copies are removed".
  - "no Pigeon, a read error, a write error or no known part means no van and one log line": `tick` then never creates an object; `prepare` is not retried.
  - "the van is made with the shape, paint, scale and no collision, then follows the flight": fields `shapeName`, the three colours, `collisionType` and `decalType` `None`, `canSave false`, registered and in the mission group, `setScale` `(3, 3, 3)`, the materials loaded before `createObject`; each tick one `setPosRot` at `place(pose, f.pos, 0, 0, 0)` with the quaternion from `quatFromDir(-nose, roof)`.
  - "a new flight starts a fresh pose".
  - "no flight removes it at once; it is found by name and made again; a leftover is swept about once a second".
  - "a failing call removes it and logs once; clear deletes it and resets".
  - "the lights follow the van, the beacons flash, nothing is drawn without a van": five core spheres while the beacon is on, three while it is off, at `place` of each offset; glow spheres only at night; none after the van is gone.
- [ ] **Step 2: Run** `make test`. Expected: the new file fails.
- [ ] **Step 3: Implement.** The copy is named by its length, so the same copy is reused and the game's `.cdae` cache stays valid. After writing, `prepare` makes and deletes one unseen `TSStatic` so the shape import happens at round setup, not when the helicopter appears. The quaternion object and two `vec3` are kept on the state and refilled with `setFromDir`.
- [ ] **Step 4: Run** `make test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: the Pigeon van flies with the helicopter`.

### Task 3: setting, wiring and docs

**Files:**
- Modify: `playerSettings.lua` (`KEYS`, `DEFAULTS`: `model = true`), `hud.lua` (`settings.model`), `HudSettings.vue` (row "Helicopter model"), `copsAndRobbers.lua` (`setHeli`, `updateHeli`, `endRound`), `HowToPlay.vue`, `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`
- Test: `tests/test_player_settings.lua`, `tests/test_hud.lua`, `tests/test_client.lua`, `tests/client_stubs.lua` (`readFile`, `writeFile`, `loadJsonMaterialsFile` fakes on `env.files`)

- [ ] **Step 1: Write the failing tests:**
  - settings: `load(nil).model == true`, `load({ model = "no" }).model == true`, `set(p, "model", false) == true`.
  - hud: `payload(...).settings.model` true by default, false when off.
  - client: "the van flies with the helicopter by day and night and is gone on every exit" (the five exits of the sound test); "Helicopter model off removes the van and draws no lights, on brings it back"; "without a Pigeon there is no van and the light and sound still work".
- [ ] **Step 2: Run** `make test`. Expected: they fail.
- [ ] **Step 3: Implement** the wiring and the settings row; then the docs: FEATURES (helicopter section, player settings count), How to Play (the settings line), README (the setting), DEPENDENCIES (paths, trim, livery, `TSStatic` fields, `setPosRot`, `setScale`, debug spheres, what to check on update).
- [ ] **Step 4: Run** `make test`, `make vuecheck`, `make package`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: Helicopter model setting, wiring and docs`.
