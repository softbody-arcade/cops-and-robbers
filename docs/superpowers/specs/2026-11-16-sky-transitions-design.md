# Sky polish: smooth transitions, rain and its sound

Status: short design for review, 2026-11-16. Builds on night and weather rounds (`2026-11-16-night-weather-design.md`) and day length and date (`2026-11-16-day-length-and-date-design.md`).

## Why
- Every sky change snaps. Time, clouds, fog and wind jump, and rain or snow pops in and out. That happens at round start (your own sky changing to the round's), on New sky, and at round end (back to your own sky). Pressing New sky a few times in a row makes the sky flicker.
- Our rain falls at 0.1–0.3, slower than the stock maps' own rain (0.35–0.5), so it likely looks floaty, close to snow. A storm differs from rain only in drop count.
- The outside temperature ignores the round's date. Bad weather shifts the map's own day curve to one fixed average (rain and storm 8 °C, fog 5 °C, snow −5 °C), and clear and cloudy rounds keep the map's own curve. A clear December round can be as warm as a clear July one, and a snow round at noon can land above freezing.
- Rain and storms are silent. Neither our rain object nor the game's rain effect has a sound, though the game ships a rain loop (`amb_rain_medium`).

## Goals
- **Blends:** round start, New sky and round end blend over up to 3 s, for every player the same way.
- **Rain and snow fade** in and out over the same blend instead of popping.
- **Rain looks like rain:**
  - rain falls at the stock maps' speed
  - a storm has faster, slightly bigger drops on top of its higher count
  - snow stays as it is
  - final numbers come from the user's screenshots in game
- **Temperature fits the weather and the date:** each round gets a sensible low and high for its month and weather, and snow never goes above freezing.
- **Sound:** the game's rain loop plays during rain and storm rounds (louder in a storm), fades with the blend and stops with the rain.

## Non-goals
- **Thunder and lightning.** The game has no lightning object in this version (its own editor marks it "not exists?") and no thunder sound. Left out of this work and kept as an idea in TODO.md (2026-11-16).
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
- **Rain fade:** step our rain object's `numDrops` from 0 to its target (and back) over the blend. Verified in game (probe, 2026-11-16): setting `obj.numDrops` on live rain thins it at once, as does `setPercentage`; the fade uses `obj.numDrops`, as the game's own `core_environment.setPrecipitation` does. The alternative, popping the rain at the end of the blend, was rejected as the very thing this fixes.

## Design

### Blends
- `sky.apply` passes a blend of **3 s** to `setState` for round start and New sky. `sky.restore` passes the same 3 s at round end and on cancel.
- **Every change gets a full blend from where the sky is.** Before each blend the mod clears any running one with `setState(nil)`, which clears without applying anything (`environment.lua:1512-1514`). Without that, the game would cut a blend that arrives mid-blend to 0.3 s, starting 35 % in, which is a visible jump (review finding, 2026-11-16).
- **A rejoin past GO snaps:** `onRoundSetup` applies the sky and starts the clock in one go, and GO always lands the full sky at once. A rejoin in prep blends like a round start.
- **The lock:**
  - `apply` keeps environment changes enabled until the blend is over (3 s plus a small margin), then locks again. A second `apply` during a blend extends the unlock.
  - `restore` keeps changes enabled for the blend, then sets the lock back the way it was before the round (`wasLocked`). That needs a small "lock again at" timer that outlives the round's state.
- **GO during a blend:**
  - `startClock` sets `time`, `play` and `dayLength`, which cancels the game's blend and would leave clouds and fog half-way.
  - So when GO comes while a blend is still running, `startClock` first applies the round's full state at once (clouds, fog, time) and then starts the clock.
- **Ending during a blend:** `restore` replaces any running blend with the blend back to the saved sky.
- **A round starting during the round-end blend** (a cancel and a quick restart) saves the player's own sky and lock from the pending restore, not the half-blended sky.
- **Leaving the server, unloading the mod or changing map end at once:** `leaveServer` restores without a blend, removes the rain and its sound straight away and puts the lock back. A blend or fade would never finish there. `drop` likewise puts the lock back at once and cancels the timer.
- **`drop`** (map change or unload) applies nothing, as today, and must clear any pending relock.
- **Unchanged and instant:** wind, temperature, date, day length, ground wind and road surfaces.
- **Rapid presses:** each New sky calls `apply` again, which starts a fresh 3 s blend from wherever the sky is, and the rain fade follows the newest target, so nothing queues.

### Rain and snow fade
- When the new sky has precipitation and ours doesn't exist yet, create it with `numDrops` 0 and raise it to the target over the blend.
- When the new sky has none, lower `numDrops` to 0 over the blend, then delete the object.
- When both old and new have precipitation:
  - **Same kind** (rain to storm): move `numDrops` from the current count to the new one.
  - **Different kind** (rain to snow): fade the old one out, then the new one in. Each half takes half the blend.
- The stepping runs from `sky.update`, about 10 times a second.
- **The roof check (`shelter`) hides the rain under cover, with two changes** (added 2026-11-16, after the user saw rain stop under street lights):
  - **A roof must cover both directions.** At least one side ray hits front or back, and at least one hits left or right. A street-light arm or traffic-light gantry covers only one direction, so it no longer counts. Tunnels, bridge decks and gas-station canopies still do.
  - **It switches after 1 s** (four checks in a row) instead of half a second, so a short pass under anything overhead never interrupts the rain.

### Drop values
- **Rain:** speed 0.4–0.5, the stock maps' own range. Drop size 1, about 3000 drops.
- **Storm:** speed 0.6–0.8, drop size about 1.3, about 7000 drops.
- **Snow:** unchanged (0.1–0.3, size 0.2, 5000).
- **`splashSize` 0.25**, as on the stock maps' `rain_medium` objects.
- **No `hitVehicles`:** the stock `rain_medium` objects don't set it, and at 7000 drops it may cost. The in-game check looks at the interior camera; only if rain falls through the roof does it get turned on.
- These are starting points. The user sends screenshots of rain and storm at a couple of settings and the final numbers come from those, as for clouds and fog.

### Temperature
- **New pure module `climate.lua`** (next to `wind.lua`): `climate.range(weather, month) -> lowC, highC`.
- **Monthly normals** for a temperate mid-latitude climate, roughly the stock maps' latitudes (38–44°):

| Month | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Low °C | 0 | 1 | 4 | 8 | 12 | 17 | 20 | 19 | 15 | 10 | 5 | 1 |
| High °C | 8 | 10 | 14 | 18 | 23 | 28 | 31 | 30 | 26 | 20 | 13 | 9 |

- **Weather changes the normals:**

| Weather | Low | High |
|---|---|---|
| Clear | as is | as is |
| Cloudy | +2 | −3 |
| Rain | +2 | −5 |
| Storm | +1 | −7 |
| Fog | as is | −6 |
| Snow | at most high − 4 | at most 0 °C (normal high − 9, capped at 0) |

  With the date windows that gives, for example:
  - snow in December: −4 to 0 °C, and in January: −5 to −1 °C
  - fog in October or November: 5 to 14 °C
  - rain in April: 10 to 13 °C
  - clear in July: 20 to 31 °C
- **The month is the server's pick, before the six-month shift for maps south of the equator.** The server picks months in northern-season terms, so the unshifted month is the season the round is in. Looking up the shifted month would give a snow round on Automation Test Track summer temperatures.
- **A low always below the high:** where the offsets would meet (a storm in November or winter), the high is raised to the low + 2 °C. A low equal to the high would make the game's curve flat all day.
- **Applying it: our own day curve on every map.** The round state carries `temperatureCurveOverrideC` with two points:
  - the low at the round's sunrise
  - the high two hours after solar noon (both from `getSolarTimeOfDayValue` for the round's date)

  This is what the game itself builds when a map's curve is flat (`environment.lua` `createTemperatureCurveFromExtremes`). It works on maps with no temperature curve at all (Hirochi Raceway, Driver Training, Gridmap, Small Grid, Glow City), where `setTemperatureProfile` does nothing. It replaces today's average-only call and the `temperatureC` values in the weather table. The map's own curve shape is no longer kept (review finding, 2026-11-16).
- **No date or no weather** (the map's own sky, BeamNG.Earth): the temperature is left alone, as today for clear and cloudy rounds.
- **The temperature does not blend.** It changes at once, like wind; nobody drives during prep or after the round.
- **Round end** restores the player's own temperature with the rest of the saved sky, as today.
- **Shown on the prep bar** (added 2026-11-16): where the date already shows (the prep bar and the New sky notice), the label ends with the day's range, for example `Night · Snow · 14 Dec · -4 to 0 °C`. It uses the game's temperature unit (`uiUnitTemperature`; Fahrenheit when set to `f`, Celsius otherwise) and whole degrees. The leaderboard's Rounds tab is unchanged.

### Rain sound
- **What plays:** the game's `amb_rain_medium` profile (`art/sound/environment/amb_rain_medium.ogg`, a 2D loop). It plays while a rain or storm round has its rain object, through one unsaved sound emitter, created the way the game's own `core/audioForest.lua` creates its emitters.
- **Volume:** rain 1.0 and a storm 2.0, from the in-game probe (0.6 was quiet next to a sports car's engine and 0.15 nearly silent; 2.0 sounded like a storm). The volume fades with the rain's `numDrops` during a blend.
- **Under cover** (tunnels, where the roof check hides the rain): the sound drops to half rather than stopping, because rain on the roof is still heard.
- **Lifetime:** the sound fades out and is deleted with the rain object at round end; leaving the server and `drop` delete it at once. It is also added to the mission group like the rain object, so a map unload removes it.
- **Verified in game (probe, 2026-11-16):** an `SFXEmitter` with `track = "amb_rain_medium"`, `setVolumePitchCT(volume, 1, 0, 0)` and `play()` plays the loop, and the volume changes live.

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
- **Temperature:**
  - `climate.range` gives the table's values for each weather in a sample of months
  - snow is never above 0 °C, and the low is always below the high
  - the round state's curve has the low at sunrise and the high two hours after noon, from the server's month even on a map south of the equator
  - no date means no temperature call
- **Drop values:** the weather table carries the new speeds, sizes and `splashSize`.

## In-game check
1. Round start at night from a sunny freeroam: the sky blends into night over about 3 s while your car is placed.
2. Press New sky several times quickly: the sky heads for the last pick without stuttering, and everyone ends on the same sky.
3. New sky from clear to rain: the rain fades in and the sound comes up. Rain to clear: both fade out.
4. Press GO right after New sky: the sky lands on the new one, and the clock runs.
5. Round end: your own sky comes back over about 3 s, and the environment menu works again afterwards.
6. Screenshots of rain and storm (and snow for comparison) at the starting values, to settle the final numbers.
7. The environment menu's temperature (also on Hirochi Raceway, which has no curve of its own) after a round starts: a December snow round reads below 0 °C, a July clear noon reads around 30 °C.
8. In a tunnel during rain: the rain is hidden and the sound is quieter. Interior camera: no rain falling through the roof.

## Calls made (not discussed, easy to change)
- **3 s blend for all three changes.** The game shortens it for small changes.
- **Rain to snow fades out, then in,** rather than crossfading two objects.
- **Starting values:** storm drops at 0.6–0.8 speed, size 1.3, 7000 drops. Volumes from the probe: rain 1.0, storm 2.0, half under cover.
- **One temperate climate for every map**, roughly the stock maps' latitudes. Desert and tropical maps (Utah, Johnson Valley, Jungle Rock Island) get the same climate, just as they get every weather today. The table's numbers and the weather offsets are my calls.
- **`splashSize`** copied from the stock maps' rain; no `hitVehicles` unless the interior camera shows rain through the roof.

## Left to the builder
- How the relock timer and the rain fade are stored in `sky.lua` (it is about 230 lines; a small `fade.lua` next to `shelter.lua` is fine if it keeps `sky.lua` readable).
- How the environment stub records blend seconds.
