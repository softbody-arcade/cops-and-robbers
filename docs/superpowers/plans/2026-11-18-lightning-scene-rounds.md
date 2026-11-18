# Native Lightning in Multiplayer Rounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal** Bring the playtested native lightning bolt, upper glow and bolt-centered shadows to multiplayer rounds.

**Architecture** The native renderer owns one strike's geometry, cloud taper and glow. `lightning.lua` owns strike capture, the single light, audio scheduling and round lifecycle. `strikes.lua` supplies the existing seeded event and shape.

**Tech Stack** BeamNG GE LuaJIT, Torque scene objects and the existing Lua test suite.

**Spec** [Native lightning in multiplayer rounds](../specs/2026-11-18-lightning-scene-rounds-design.md).

## Global constraints

- Use emissive factor 12 and a 4,000 m inclusive 3D camera-to-landing cutoff.
- Keep existing round seed, clock, weather and thunder behavior. Add no settings.
- Use the accepted freeroam implementation under `/tmp/cnr-bolt-overcast/` as the port reference.

## Review focus

- At 4,000 m and just beyond, check which scene objects are created and which light placement is used.
- If registration fails partway through a strike, check that every rod is removed and the flash and thunder still work.
- While a pulse is visible, move the camera with dense cloud enabled and check that the core fades into the clouds and remains bright below the cloud base.
- During a gap between pulses, enter cover or turn flashes off and check immediate visual cleanup with pending thunder intact.
- When a client skips past a strike or joins late, check that the remaining schedule and thunder cursor retain their existing behavior.

## Task 1 — port the native renderer

**Files** `client/art/shapes/cnrLightning/cnrLightningRod.dae`, `client/art/shapes/cnrLightning/main.materials.json` and `client/lua/ge/extensions/copsAndRobbers/lightningScene.lua`.

**Interfaces** `create(shape, landing, distance, uniqueSerial, shapeSeed)` creates one scene and rolls back partial objects on failure. `render(scene, cam, pulseIndex, pulseLevel)` drives the current pulse, with a nil pulse index hiding the rods. `remove(scene)` releases its rods.

- [ ] Cover the segment count, pulse visibility, later-pulse branch widths, cloud taper and cleanup after a partial registration failure with scene-object stubs in `tests/test_lightning_scene.lua`.
- [ ] Port the approved opaque rod and material under the `cnrLightning` asset path. Create hidden, unsaved, non-colliding rods using `cnrLightningBoltRod`, and use per-strike names so simultaneous strikes can coexist.
- [ ] Port the width scaling, haze attenuation, cloud taper and depth-tested upper glow. Prefer the existing seeded bolt shape and keep glow randomness independent of the strike timeline.
- [ ] Run `lua tests/run.lua tests/test_lightning_scene.lua` and `luajit -bl client/lua/ge/extensions/copsAndRobbers/lightningScene.lua >/dev/null`, then commit and request independent review.

## Task 2 — integrate the round renderer

**Files** `client/lua/ge/extensions/copsAndRobbers/lightning.lua`, `tests/test_lightning.lua`.

- [ ] Update scene tests to assert the inclusive range, actual seeded midpoint, full-strength shadow pulses nearby, overhead flash beyond range, and continued thunder on visual failure. Verify expiry, hide, seed change and clear remove rods as well as the light, including after an inactive pulse frame.
- [ ] Replace the line drawing path with native scene ownership per visual. Keep the public `new`, `tick`, `hide`, `clear` and `hasVisualTail` behavior. Reuse the round's captured landing and pulse times to drive the scene and light. Preserve the existing roof checks and sound path.
- [ ] Run `luajit -bl client/lua/ge/extensions/copsAndRobbers/lightning.lua >/dev/null` and `make test`, then commit and request independent review.

## Task 3 — verify the reviewed build

- [ ] Have a fresh reviewer check the whole branch, then run `make package` and check that the client ZIP includes the rod, material and GE renderer.
- [ ] Stage the reviewed SHA from `git archive` on the local test server using the repository workflow, preserve its installed configuration, restart the server and report the SHA.
- [ ] In a West Coast USA Night + Thunderstorm round, check shadow direction beside a car or tree, cloud fade while moving, and near and far pulse brightness and frame pacing. Check cover, the Lightning flashes switch, round end and delayed thunder. Compare the next strike with a second player who joins after GO. Wait for the multiplayer playtest result or explicit deferral before merging.
