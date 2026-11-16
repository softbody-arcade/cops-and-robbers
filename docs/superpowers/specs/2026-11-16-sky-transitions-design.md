# Sky polish: smooth transitions, rain and its sound

Status: short design for review, 2026-11-16. Builds on night and weather rounds (`2026-11-16-night-weather-design.md`) and day length and date (`2026-11-16-day-length-and-date-design.md`).

## Why
- Every sky change snaps. Time, clouds, fog and wind jump, and rain or snow pops in and out. That happens at round start (your own sky changing to the round's), on New sky, and at round end (back to your own sky). Pressing New sky a few times in a row makes the sky flicker.
- Our rain falls at 0.1–0.3, slower than the stock maps' own rain (0.35–0.5), so it likely looks floaty, close to snow. A storm differs from rain only in drop count.
- Rain and storms are silent. Neither our rain object nor the game's rain effect has a sound, though the game ships a rain loop (`amb_rain_medium`).

## Goals
- **Blends:** round start, New sky and round end blend over up to 3 s, for every player the same way.
- **Rain and snow fade** in and out over the same blend instead of popping.
- **Rain looks like rain:**
  - rain falls at the stock maps' speed
  - a storm has faster, slightly bigger drops on top of its higher count
  - snow stays as it is
  - final numbers come from the user's screenshots in game
- **Sound:** the game's rain loop plays during rain and storm rounds (louder in a storm), fades with the blend and stops with the rain.

## Non-goals
- **Thunder and lightning.** The game has no lightning object in this version (its own editor marks it "not exists?") and no thunder sound. Decided against, 2026-11-16.
- BeamNG.Earth: the mod sets no sky there.
- **Blending wind, temperature or the date.** They change while cars are frozen (prep) or at round end, where nobody drives into it.
- A snow sound.

## Anti-goals
- **A blend stuck half-way.** GO during a blend, or a round that ends during one, must still end on the right sky.
- **An unlocked environment menu after the blend.** The mod locks the environment during a round. It may only be unlocked while a blend runs.
- **A rain object or sound left behind** after the round, a cancel, leaving the server or a map change.
- **Rapid New sky presses piling up.** Each press must head straight for the newest sky.

## Approaches
- **The game's own blend (picked).**
  - What the game does: `core_environment.setState(state, lerpSeconds)` blends clouds, fog, fog height and time with an eased curve. Time goes the short way round, so noon to sunset plays like a quick time-lapse. Bigger changes take the full time, smaller ones less (at least 0.12 s). If a new state arrives mid-blend, the game finishes the rest within 0.3 s and heads for the new one.
  - The catch: the blend only advances while environment changes are enabled, so the mod unlocks for the blend and locks again afterwards.
- **Our own per-frame blend.** Full control, wind and temperature included, but it duplicates what the game already does well. Rejected.
- **Rain fade:** step our rain object's `numDrops` from 0 to its target (and back) over the blend. The game itself changes `numDrops` at runtime (`core_environment.setPrecipitation`), so this is supported. The alternative, popping the rain at the end of the blend, was rejected as the very thing this fixes.

## Design

### Blends
- `sky.apply` passes a blend of **3 s** to `setState` for round start (including a rejoin mid-round) and New sky. `sky.restore` passes the same 3 s at round end and on cancel.
- **The lock:**
  - `apply` keeps environment changes enabled until the blend is over (3 s plus a small margin), then locks again. A second `apply` during a blend extends the unlock.
  - `restore` keeps changes enabled for the blend, then sets the lock back the way it was before the round (`wasLocked`). That needs a small "lock again at" timer that outlives the round's state.
- **GO during a blend:**
  - `startClock` sets `time`, `play` and `dayLength`, which cancels the game's blend and would leave clouds and fog half-way.
  - So when GO comes while a blend is still running, `startClock` first applies the round's full state at once (clouds, fog, time) and then starts the clock.
- **Ending during a blend:** `restore` replaces any running blend with the blend back to the saved sky.
- **`drop`** (map change or unload) applies nothing, as today, and must clear any pending relock.
- **Unchanged and instant:** wind, temperature, date, day length, ground wind and road surfaces.
- **Rapid presses:** each New sky calls `apply` again. The game shortens the running blend and heads for the newest sky, and the rain fade follows the newest target, so nothing queues.

### Rain and snow fade
- When the new sky has precipitation and ours doesn't exist yet, create it with `numDrops` 0 and raise it to the target over the blend.
- When the new sky has none, lower `numDrops` to 0 over the blend, then delete the object.
- When both old and new have precipitation:
  - **Same kind** (rain to storm): move `numDrops` from the current count to the new one.
  - **Different kind** (rain to snow): fade the old one out, then the new one in. Each half takes half the blend.
- The stepping runs from `sky.update`, about 10 times a second.
- The roof check (`shelter`) still hides the rain under cover, as today.

### Drop values
- **Rain:** speed 0.4–0.5, the stock maps' own range. Drop size 1, about 3000 drops.
- **Storm:** speed 0.6–0.8, drop size about 1.3, about 7000 drops.
- **Snow:** unchanged (0.1–0.3, size 0.2, 5000).
- **Take two settings from the stock maps' rain objects:**
  - `hitVehicles` true, so drops stop at a car's roof rather than falling through it in the interior camera
  - `splashSize` about 0.25
- These are starting points. The user sends screenshots of rain and storm at a couple of settings and the final numbers come from those, as for clouds and fog.

### Rain sound
- **What plays:** the game's `amb_rain_medium` profile (`art/sound/environment/amb_rain_medium.ogg`, a 2D loop). It plays while a rain or storm round has its rain object, through one unsaved sound emitter, created the way the game's own `core/audioForest.lua` creates its emitters.
- **Volume:** a storm is louder than rain (start at 0.6 for rain and 1.0 for a storm). The volume fades with the rain's `numDrops` during a blend.
- **Under cover** (tunnels, where the roof check hides the rain): the sound drops to about a third rather than stopping, because rain on the roof is still heard.
- **Lifetime:** the sound is deleted with the rain object, so `restore`, `drop` and leaving the server stop it.
- **Verify in game:** the exact call that plays a profile-based loop from Lua, with the console test extension.

## Tests
Lua, in `tests/test_sky_client.lua` with the environment stub (it records `setState` calls; it needs to record the blend seconds too):
- **Blend seconds:** `apply` and `restore` pass 3 s.
- **The lock:** changes stay enabled while a blend runs and are locked again after it. After `restore` the lock goes back to the player's own setting.
- **GO during a blend:** `startClock` applies the full round state before starting the clock.
- **Rain fade:**
  - New sky from clear to rain creates the object at 0 and steps it up to the target.
  - Rain to clear steps it down and then deletes it.
  - Rain to snow fades out, then in.
  - A second New sky mid-fade heads for the newest target.
- **Rain sound:**
  - the emitter exists while the rain object does, and is louder in a storm
  - it is lowered under cover
  - it is deleted by `restore` and by `drop`
- **Drop values:** the weather table carries the new speeds, sizes and `hitVehicles`.

## In-game check
1. Round start at night from a sunny freeroam: the sky blends into night over about 3 s while your car is placed.
2. Press New sky several times quickly: the sky heads for the last pick without stuttering, and everyone ends on the same sky.
3. New sky from clear to rain: the rain fades in and the sound comes up. Rain to clear: both fade out.
4. Press GO right after New sky: the sky lands on the new one, and the clock runs.
5. Round end: your own sky comes back over about 3 s, and the environment menu works again afterwards.
6. Screenshots of rain and storm (and snow for comparison) at the starting values, to settle the final numbers.
7. In a tunnel during rain: the rain is hidden and the sound is quieter. Interior camera: no rain falling through the roof.

## Calls made (not discussed, easy to change)
- **3 s blend for all three changes.** The game shortens it for small changes.
- **Rain to snow fades out, then in,** rather than crossfading two objects.
- **Starting values:** storm drops at 0.6–0.8 speed, size 1.3, 7000 drops; the volumes (0.6 rain, 1.0 storm, a third under cover).
- **`hitVehicles` and `splashSize`** copied from the stock maps' rain.

## Left to the builder
- How the relock timer and the rain fade are stored in `sky.lua` (it is about 230 lines; a small `fade.lua` next to `shelter.lua` is fine if it keeps `sky.lua` readable).
- The exact Lua call that plays the rain loop, verified in game.
- How the environment stub records blend seconds.
