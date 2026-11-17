# The Pigeon as the helicopter

## Why
- **The user's ask:** "Let's work on the pigeon as helicopter… I want that to work".
- **Today:** the helicopter is only a light, a beam and a sound. It has no visible body.

## What was proven in game (freemode, 2026-11-17)
- **The model:** a static `TSStatic` of `/vehicles/pigeon/pigeon.dae` renders every optional part at once.
  - Static shapes have no per-mesh hiding (`setMeshAlpha` and the rest are nil on `TSStatic`; only `setHidden` exists).
- **Materials:** they resolve when the Pigeon's material files are loaded **before** the shape is created, with `loadJsonMaterialsFile` on:
  - `/vehicles/pigeon/main.materials.json`
  - `/vehicles/pigeon/dynamicDecals/main.materials.json`
  - `/vehicles/pigeon/skin.materials.json`
- **Paint:** `instanceColor`, `instanceColor1` and `instanceColor2` paint it.
- **The trimmed copy:** the model file is 108 top-level `<node>` elements with no nesting. Removing the unwanted nodes' `<node id="NAME" ...>…</node>` blocks and writing the result to the user folder (`/temp/cnr/...dae`) gives a clean Pigeon van: the cab, the box, the glass, the lights and the roof lamps.
  - Shapes are cached by path, so a changed copy needs a new file name.
- **The reference probe:** `.superpowers/cnrprobe-reference.lua` in this worktree (git-ignored) holds the exact hide list and the trim code that worked. Add `pigeon_taillight_L` and `pigeon_taillight_R`: they float behind the trimmed van.
- **Why not a real car:** a real Pigeon vehicle is not an option, because BeamMP syncs every spawned vehicle to every player and has no local-only spawn.

## Design (approved by the user in the conversation)
- **The copy:** each player's game makes the trimmed copy from its own installed Pigeon the first time it's needed. It loads the materials first, then reuses the copy in later rounds of the session.
  - Nothing from BeamNG ships in the mod.
  - If the copy can't be made (no Pigeon, a read or write error), the helicopter works as today without a body, and the failure is logged once.
- **Flight:** the van is placed at the helicopter's position every frame and points along its flight heading. It pitches nose-down while speeding up and nose-up while slowing, and banks into turns: a few degrees, smoothed, capped.
- **Paint:** white body (`0.9 0.9 0.92`) with near-black trim (`0.05 0.05 0.08`).
- **The searchlight** comes from under the van, where the light already is.
- **Lifecycle:** the van exists exactly when the helicopter's light or flight does: arriving, tracking, searching, and the fly-away for refuels and weather groundings. It is removed with them.
  - Nothing is left after a round end, a cancel, leaving, a map change or unload.
  - It is found by name, as the light and the sound are.
- **No wheels, no rotor:** a rotor disc can come later.
- **A personal setting, "Helicopter model":** on by default, next to "Helicopter sound" in the player settings (`playerSettings.lua`, the HUD settings), saved per player.

## Left to the builder
- **The pitch and bank:** the exact amounts and smoothing.
- **Scale and offsets:** the model's offset so the light sits under the van.
- **Mapping helpers:** the matrix and quaternion helpers for `setPosRot` or `setTransform`, using the existing math helpers.
- **The cache name and when to regenerate:** a new name per game session is fine.

## Tests
- **The trim:** pure. Given a small fake dae with flat nodes, the listed nodes are removed and the others kept.
- **Lifecycle:** the van is created with the light, follows the flight position and heading, and is removed on every exit path.
- **Failure:** a read or write failure, or no Pigeon, means no van, one log line, and the helicopter still works.
- **The setting:** off means no van.

## In-game check
- The van flies with the helicopter, tilts and banks believably, and is lit and painted.
- It disappears on a refuel or a grounding fly-away and after the round.
- No frame hitch the first time it's made.
