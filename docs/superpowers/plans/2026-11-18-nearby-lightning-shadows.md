# Nearby lightning shadows implementation plan

**Goal.** Cast directional shadows for strikes under 1 km and preserve the existing distant flash. Implement with Superpowers subagent-driven development in the `nearby-lightning-shadows` worktree. [Approved behavior and design](../specs/2026-11-18-nearby-lightning-shadows-design.md).

**Architecture.** Capture a close strike's fixed light position alongside its existing visual state. For each frame, the strongest pulse drives the single PointLight. The renderer already handles bolt geometry, audio, cover and object lifetime. The change is local to the client.

**Stack.** BeamNG game Lua, LuaJIT, GE PointLight, the existing Lua scene test harness.

## Global constraints

Use the captured 3D camera-to-landing distance, existing 1,500 m radius and existing intensity curve. Register one light through the current scene API. Preserve all current behavior when player visuals are disabled or covered and when the round or seed changes.

## Review focus

Check the exact 1 km boundary and elevated cameras, a coincident aim point, moving the free camera between close pulses, mixed overlapping strikes changing winners, and safe teardown under cover or after the round.

## Task 1 — Shadow placement and shared light ownership

- [ ] In `tests/test_lightning.lua`, use the existing `scene` harness to pin a nonvertical bolt with a landing 600 m north of a ground-level camera. The halfway-up aim point is 450 m above it, giving a source at `(0, 240, 180)` and intensity `2.5e9` for the first full pulse. Assert shadow flag enabled, radius 1,500 m, identical close source on the next pulse after a camera move, and unchanged bolt foot and queued sound. Add exact-1-km and elevated-camera cases using 3D distance. Test a camera coincident with the aim point, using a separate runner origin so the horizontal displacement resolves to zero.
- [ ] Exercise overlap using the existing injected events. Give one close and one distant pulse near the 1 km boundary different levels so the winner switches from close to distant within the same light object's lifetime. Check the winner's position, shadow flag and strength together, the same object identity, both bolt shapes, and correct return to overhead placement. Test two equally strong nearby bolts on opposite bearings and expect the newer one to win. Retain the cover, preference, pulse-gap, cleanup, failed registration and no-camera cases.
- [ ] Run `lua tests/run.lua tests/test_lightning.lua` and confirm the new close-shadow and selection cases fail against the previous overhead-light behavior.
- [ ] In `client/lua/ge/extensions/copsAndRobbers/lightning.lua`, compute the optional fixed close-flash position only in the visible capture path. Normalize the vector from camera to landing plus 450 m vertical, multiply by 300 and add the camera. Use the upward 300 m fallback for zero length. Keep the current `strikes.strength(distance)`, clip selection, delay and geometry.
- [ ] In `render`, retain the visual for the strongest active pulse alongside its weighted strength. Take a strictly stronger replacement while walking newest to oldest, so a tie keeps the newer visual. In `updateLight`, apply the winning source's position and shadow flag before the existing field writes and `postApply`. During dark gaps disable the emitter; reuse the existing object and cleanup. Keep shadow mode changes on the light itself or in its existing state, resetting any cached state when the light is removed or creation fails.
- [ ] Update the PointLight contract and in-game checks in `docs/DEPENDENCIES.md` and the lightning description in `docs/FEATURES.md`. Run `luajit -bl client/lua/ge/extensions/copsAndRobbers/lightning.lua >/dev/null`, `make test` and `git diff --check`. Commit the tested implementation and independently review it against the full branch diff.
- [ ] From an archived reviewed SHA, run `make package` before local staging. Have the coordinator schedule the local build and preserve the installed config. Request the close-shadow, distant flash, tunnel, cleanup and frame-pacing checks in the design. Record the observations in the shared ledger before merge.
