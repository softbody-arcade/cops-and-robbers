# Thunderstorms: thunder and lightning

Status: design, 2026-11-18. Branch `thunder`.

## Intent

The user asked for thunder and lightning: "Let's do Thunder and lightning in storm rounds", with the thunder recordings coming from freesound.org (CC0), like the helicopter's rotor sound. Reading the first draft, they added: "Probably just another type 'thunderstorm'". So this adds a new weather, the thunderstorm, and keeps today's storm (a gale: strong wind and heavy rain, spring and autumn) as it is, without lightning. That is also closer to reality: thunderstorms are a warm-weather thing. The project's standing aim is the most realism with gameplay balance in mind, so this is atmosphere only: it must never change who sees or catches whom.

## Goals

- A new weather type, `thunderstorm` ("Thunderstorm"), that fits into the weather system everywhere the other types do (see "The thunderstorm weather" below).
- While the weather is a thunderstorm, lightning strikes now and then around the chase. Each strike has:
  - a flash that lights the landscape for a moment;
  - a visible bolt, if it is close enough;
  - thunder that arrives after the flash, delayed by the distance at the speed of sound, and that sounds like that distance (a sharp crack close by, a low rumble far away).
- Every player gets the same strikes at the same moment and in the same place, with no extra network traffic. This works the way the wind gusts already do (`wind.lua`): each game works the strikes out from a seed the server sends with the round's sky, plus the shared round clock.
- A player can turn the flashes off ("Lightning flashes" in the HUD settings) for comfort or photosensitivity. Thunder always plays.

## Non-goals

- Gameplay effects. A flash may light up the runner for a moment, but it is never a sighting, never touches cop sight, the helicopter (already grounded in storms), catching or the leaderboard.
- Lightning in any other weather. The storm (gale), rain, snow and fog have none.
- Lightning on BeamNG.Earth: Earth rounds have no mod weather.
- Strikes hitting cars or the ground with effects (fires, damage, sparks).
- Thunder in prep: strikes start at GO.

## Anti-goals

- A flash shining inside tunnels or under bridges. The flash light casts no shadows, so it would light the road straight through a roof.
- Any frame-rate cost outside the half second of a flash. The light exists only during a flash, and the bolt is drawn only during its pulses.
- Changing the player's own graphics or sound settings, even for a moment.

## What was tried in game (spikes, 2026-11-18, freeroam, West Coast USA at midnight in a storm sky)

These were done with a throwaway console helper. The user ran each one and reported the result.

| Approach | Result |
|---|---|
| ScatterSky `skyBrightness` × 7 and × 21, with `applyChanges()` | no visible change |
| `PostEffectLocalExposureObject.exposureBiasEV` + 2 to 6 EV | "did not work great or at all" |
| `PointLight` 500 m up, 800 m ahead, `brightness`/`intensity` 3000, radius 3000 | no visible change (far too weak in this game's physical light units) |
| `PointLight` 300 m above the camera, radius 1500, no shadows, intensity 1e6 / 1e8 / 1e10 | works. The user: "6 is too little, 8 is good and 10 is for really close" |
| Bolt drawn with `require("utils/debugDraw").LineInstance_MinArg` (jagged lines from 900 m up to the ground, 1200 m ahead, 4 px wide, colour 235 240 255), shown only during the flash pulses | "looked great"; "this already looks pretty dang good" |

The older idea notes (2026-11-16) flashed the sky through `core_environment.setSkyBrightness`. In this game version that call only logs "Sky brightness has been deprecated" and does nothing, so it is not an option.

## Approaches considered

- **Flash through the sky's brightness or the exposure** (cheap, whole screen). Both did nothing visible in game, so they are out.
- **Flash with a strong light above the player** (chosen). It is proven in game, it lights the landscape the way lightning does, and the light's strength can follow the strike's distance with real inverse-square falloff.
- **Bolt.** The user first chose "flash only, and spike the bolt". The spike looked great, so the bolt is in.
- **Lightning in every storm, or a separate thunderstorm type.** The first draft put lightning in the existing storm. The user chose a separate type, so storms stay as they are and thunderstorms get the lightning.

## The thunderstorm weather

It is a new weather key, `thunderstorm`, labelled "Thunderstorm" and named "a thunderstorm" in sentences. It works like the storm except where stated below. These are my calls, to tune on the local server.

**Look and feel:**
- **Clouds, fog and rain:** the same as the storm (`sky.lua` `M.WEATHER`: cloud cover 3.0, fog density 8, the storm's rain).
- **Grip:** the storm's wet grip (`surfaces.lua` uses its `storm` rules for a thunderstorm).
- **Wind:** gusty but less steady than a gale. The client's `wind.lua` gets `thunderstorm = { steady = 10, peak = 24, every = { 4, 12 }, length = { 1, 4 }, turn = 45 }`.
- **Lightning:** strikes, flashes, bolts and thunder, as below.

**When it happens:**
- **As the round's starting weather:** it joins the random bad-weather pick (server `sky.lua` `BAD`). Its date window is May to September (`WINDOWS.thunderstorm = { 5, 6, 7, 8, 9 }`). Its temperature offset for the day is `{ 2, -6 }` (`climate.lua` `OFFSET`): the high is cut by the storm.
- **During a round** (`weather.lua` `NEXT`), it can come:
  - from cloudy when it is hot, at half the weight of each other option (the user: "I feel like it happens to often");
  - from rain when it is hot, at the normal weight.

  "Hot" is a new condition: the higher of the two surrounding temperature points is 20 °C or more, worked out the way `warm` is (15 °C).
- **Afterwards:** a thunderstorm moves on to rain or cloudy.
- **If the temperature falls through freezing:** it turns into rain (`CROSS`), the same as the storm.
- **When it can stop:** it is in `CAN_STOP`, with the same temperature fit as rain and storm.

**Everywhere the weather types are listed:**
- **The helicopter:** it is grounded in a thunderstorm (server `weather.lua` `GROUNDS` and `helicopter.lua` `GROUNDED`; client `skyChanges.lua` `GROUNDED`).
- **Server lists:**
  - the bad-weather lists (server `sky.lua` `BAD`, client `sky.lua` `BAD_WEATHER`);
  - `RANK` (4, the same as the storm);
  - the panel's weather setting (`config.lua` `weather`, panel `settings.js` options and help texts).
- **Client text:**
  - the change notice word and `CLEARING_FROM`;
  - the forecast;
  - How to Play (helicopter grounding);
  - the leaderboard's and HUD's weather labels.
- **The rest:** grep for `storm` gives the full list, and every place that lists the types gets the new one.
- A hand-picked "Thunderstorm" in the panel works like any hand-picked weather.
- As a starting weather it goes through the existing random-weather settings (the bad-weather chance and the rest), like the other bad weathers. The user: "bad weather should use the normal random weather percentage and other stuff that we already do for dynamic weather".
- It never changes straight to or from the storm (gale); the user agreed.

## Planned changes can keep the weather

The user: "it should be possible for the same weather to chain so clear -> clear and then the forecast just shows nothing for that cycle".

**How a planned change picks:** each planned change slot (every `weatherChangeMinMinutes`–`weatherChangeMaxMinutes`) picks from the allowed options plus "stay". "Stay" is the current weather, with weight 1, and is always allowed. The pick has two steps, so the existing "Bad weather chance" (`badWeatherChancePercent`, default 25) decides every roll that can lead to bad weather. The user: "I want to reuse badWeatherChancePercent for everything that normally is bad weather in the roll that uses that".
1. **Group.** Split the allowed options (including "stay") into calm (clear, cloudy) and bad (rain, storm, fog, snow, thunderstorm: the server's `BAD` list). If both groups have options, roll the bad group with `badWeatherChancePercent` and the calm group otherwise. If only one group has options, use that one.
2. **Weather.** Pick inside the group by the weights in the table below.

Over a long round the share of bad weather then follows `badWeatherChancePercent`. It runs below it when the temperature rules out every bad option from a calm weather: on a hot day clear can't turn foggy, so it only goes calm. Worked out for a hot day (20 °C or more) at 25%, the long-run shares are clear 35%, cloudy 47%, rain 10%, thunderstorm 5.5% and storm 2%, so 17% bad. At 25%:
- From cloudy on a cool day: 75% stays calm (cloudy again or clear), 25% turns bad (rain, snow or fog, as the temperature allows).
- From rain: 25% stays bad (rain again, storm, snow or thunderstorm), 75% clears to cloudy.

The panel shows "Bad weather chance" when Weather is Random (as today) and also when "Weather changes" is on (`settings.js` `when`). Its help text then says it covers the starting weather and the changes.

**When it stays:**
- Nothing is added to the change list: no change, no notice, no forecast.
- The next slot is drawn as usual, so the forecast shows nothing until the next real change's forecast window (up to 2 minutes before it), exactly as it would for any change.

**What doesn't change:**
- Forced changes (temperature crossings, fog lifting) never stay.
- `weather.build` stays deterministic from `weatherSeed`.
- The 3-hour horizon cap stays.

**The pick becomes weighted** (`pick` in `weather.lua`). Each `NEXT` option takes an optional weight, defaulting to 1, used inside its group. The options with weights:

| From | Options (weight) |
|---|---|
| clear | stay (1), cloudy (1), fog (1, if foggy) |
| cloudy | stay (1), clear (1), rain (1, if wet), snow (1, if cold), fog (1, if foggy), thunderstorm (0.5, if hot) |
| rain | stay (1), cloudy (1), storm (1, if warm), snow (1, if cold), thunderstorm (1, if hot) |
| storm | stay (1), rain (1) |
| snow | stay (1), cloudy (1), rain (1, if wet) |
| fog | stay (1), cloudy (1), clear (1) |
| thunderstorm | stay (1), rain (1), cloudy (1) |

With "stay", a weather can last over several slots. How long bad spells last follows the bad weather chance: they are short at low settings and long at high ones. The existing schedule property tests need updating, and a new test pins that a "stay" adds no change and no forecast.

## The design

### When strikes happen

- Only after GO, and only while the round's weather (`skyChanges.at(round, t)`) is a thunderstorm or is changing to or from one.
- **Rate:** on average one strike every 25 s in a full storm. In practice, candidate strikes come at random intervals (exponential, mean 25 s), and each candidate is kept with a probability equal to the storm's weight at that moment. The weight is 1 in a thunderstorm, 0 outside one, and the change's smoothed progress (`skyChanges.smooth`) while it changes, so strikes thin out as a thunderstorm clears and build up as it arrives.
- **The same for everyone:**
  - The server adds a `lightningSeed` to the round's sky, next to `windSeed` (`server/CopsAndRobbers/cnr/sky.lua`, sent with the sky payload). The client draws everything about the strikes from this seed and the round clock: times, distances, bearings, bolt shapes, pulse timing and sound choices. A joiner, or a client that applies the sky again, gets the same strikes.
  - Use the project's existing seeded generator style (Park–Miller, as in `wind.lua` and the server's `weather.seeded`).
  - Strikes are worked out ahead in a bounded window, as the wind schedule is, and cached per seed.
  - A round without `lightningSeed` (an older payload) has no lightning.

### Where a strike lands

- **Distance from the reference point:**
  - 10%: 300 m – 1 km
  - 35%: 1 – 3 km
  - 55%: 3 – 6 km

  Pick the band from the seed, then a uniform distance inside it. Bearing: uniform 0–360°.
- **Reference point:** the runner's car at the moment of the strike, as this game sees it. That is the player's own car for the runner, and the runner's car for cops and spectators, through the same `runnerObject()` the helicopter uses. If the runner's car isn't available here (not loaded yet, or a spectator without it), use the camera position instead. Positions differ between players only by network lag (metres), which doesn't matter at these distances, so players see bolts and hear thunder consistently.
- **Ground height at the strike spot:** a downward static ray from 2500 m (the spike used `castRayStatic(vec3(x, y, 2500), vec3(0, 0, -1), 5000)`). Fall back to the reference point's height.

### The flash

- A `PointLight` 300 m above the camera, radius 1500 m, colour `0.75 0.82 1 1`, no shadows, created at the strike and deleted after the last pulse. It is unsaved, named, and added to `MissionGroup`, the way the helicopter's searchlight is made (`heli.lua` `createLight`).
- **Strength:** intensity `1e10 × (300 / d)²`, where d is the strike's distance from the camera in metres, capped at `1e10`. That gives about 1e9 at 1 km, 1e8 at 3 km and 3e7 at 6 km. The spike wrote both `brightness` and `intensity` plus `isEnabled` and `postApply()`; the builder settles which field this game version actually uses, during the early in-game check below.
- **Pulses:** each strike is 2–4 pulses within about 0.5 s, from the seed. The spike's three-pulse pattern was (start, length, level): (0, 0.07, 1), (0.13, 0.05, 0.55), (0.30, 0.12, 0.85).
- **No flash under a roof:** use the same roof check as the rain (`shelter.lua` through `rain.lua`'s cover state; expose it rather than casting a second set of rays). While the camera is roofed there is no flash and no bolt, and thunder still plays.
- **Lightning flashes setting off:** no light and no bolt; thunder still plays.

### The bolt

- **Which strikes:** strikes up to 4 km from the camera.
- **Shape:**
  - A jagged line from 900 m above the strike spot's ground down to the ground, made by midpoint displacement (the spike: 6 levels of subdivision, roughness 0.35), plus 1–3 side branches going down and outwards (4 levels, roughness 0.4, 150–350 m long).
  - The shape comes from the strike's seed, so everyone sees the same bolt.
  - It is built once per strike, not every frame.
- **Drawing:** `debugDraw.LineInstance_MinArg` per segment, only during the flash pulses, colour 235 240 255.
- **Tweaks:** the user is happy with the spike but welcomes tweaks. Suggested, for the builder to try and tune on the local test server:
  - a thicker main channel (about 4 px) with thinner branches (about 2 px);
  - a slight fade of the branches between pulses;
  - drawing the bolt during every pulse, not just the first.

  These are constants in the module, so tuning is a one-line change.

### Thunder

- **Delay:** `d / 343` seconds after the strike, where d is the distance from the camera at the strike.
- **Recording by distance:**

  | Distance | Recordings |
  |---|---|
  | under 1 km | close |
  | 1–3 km | medium |
  | over 3 km | far |

  The recording within the set is chosen from the strike's seed.
- **Volume:** 1.0 at 500 m or closer, falling smoothly to about 0.35 at 6 km. The exact curve is the builder's to tune by ear on the local server.
- **Playback:** non-positional (heard all around, not from a direction), one-shot.
  - Use the proven `SFXEmitter` with `fileName` from `heliSound.lua`, with `is3D` "0" and `isLooping` "0", deleted once its clip has finished.
  - Each recording's length is in a table next to its file name.
  - At most 3 thunders play at once; a strike whose thunder would make a fourth plays none.
  - The builder checks early, in game, that a non-3D one-shot emitter plays at the set volume. If it doesn't, put the emitter 30 m from the camera in the strike's direction with `is3D` "1".
- **Clean-up:** all thunder emitters, the flash light and the bolt are removed at round end, leave and level unload, on the same paths that clear the rain and the helicopter sound.

### Sound files

All CC0 from freesound.org. The user downloaded the originals into `~/Downloads`. The files are cut and levelled as in the previews already made (`~/Downloads/cnr-thunder-preview`): mono, 48 kHz, Vorbis q5, peak −1 dBFS, fade-in and fade-out. They go in `client/art/sound/cnr/`.

**Close:**
- `thunder_close_1.ogg`: "sfx_thunder blast.wav" by bajko, https://freesound.org/people/bajko/sounds/399656/. From 0 to 15 s, fade-out over the last 3 s.
- `thunder_close_2.ogg`: the same recording pitched down about 8% (a deeper copy), for variety.

**Medium:**
- `thunder_medium_1.ogg`: "Distant Thunder Clap_Gentle.wav" by mikala_oidua, https://freesound.org/people/mikala_oidua/sounds/347562/. The whole 18.4 s, fade-out over the last 2 s.

**Far:** `thunder_far_1.ogg` … `thunder_far_7.ogg`, the seven rumbles cut from "230405 Thunder DRY rolling distant low rumbles, roof, EM272s, Toronto 7am" by TRP, https://freesound.org/people/TRP/sounds/717845/, at the quiet gaps. Each has a 0.3 s fade-in and a 1.5 s fade-out:

| File | Cut (s) |
|---|---|
| `thunder_far_1.ogg` | 2.0–8.0 |
| `thunder_far_2.ogg` | 44.5–57.0 |
| `thunder_far_3.ogg` | 59.7–65.0 |
| `thunder_far_4.ogg` | 69.5–74.0 |
| `thunder_far_5.ogg` | 76.7–90.0 |
| `thunder_far_6.ogg` | 125.7–135.5 |
| `thunder_far_7.ogg` | 146.7–161.0 |

**Left out, and why:**
- "Close lightning strike 2018 07 07" by csengeri: the user hears dogs barking before and after the strike.
- The cut script is in the job's temp folder. The plan should copy it into `tools/` so the cuts can be remade.

**Credits:** CC0 needs no credit, but the README and `docs/DEPENDENCIES.md` name each recording, as they already do for the rotor sound. The total is about 1 MB.

### The setting

- A new player setting `lightning` (boolean, default true), shown in the HUD settings as "Lightning flashes", right after "Helicopter model".
- It is wired like the other player settings: `playerSettings.lua` `KEYS` and `DEFAULTS`, the HUD payload, and the HUD settings row.
- Turning it off mid-flash removes the light and the bolt at once.

### Where the code goes

These are the builder's to refine.

- A new pure module for the schedule (seeded strike times, distances, bearings, pulse patterns, sound picks and bolt shapes), tested without the game. This is like `wind.lua` and `skyChanges.lua`.
- A new scene module for the flash light, the bolt drawing and the thunder emitters, like `heliSound.lua` and `heliVan.lua`.
- `sky.lua` already owns the round's sky, round clock and weather. It exposes what the lightning needs (the storm weight at time t, and `lightningSeed`). The client's update loop drives the lightning each frame, after the sky.
- The server's `sky.lua` adds `lightningSeed`.

### Docs

- `docs/FEATURES.md`: storms have lightning and thunder; the "Lightning flashes" setting.
- `docs/DEPENDENCIES.md`, in the GE section:
  - `PointLight` with its fields, and the intensity scale found in game;
  - `debugDraw.LineInstance_MinArg`;
  - the one-shot `SFXEmitter`;
  - why sky brightness and the exposure bias are not used;
  - the sound files' sources;
  - what to check after a game update.
- How to Play, if it describes storms: one line.
- README: the sound credits.

## Left to the builder

- The exact volume curve.
- The bolt tweaks and widths.
- The pulse-pattern randomisation within 2–4 pulses in about 0.5 s.
- How the candidate-strike window is cached.
- Module names.
- Whether the roof state comes from `rain.lua` or a shared shelter instance. Either way, the roof check must keep running for the lightning even when the rain is faded out at the edges of a change; `rain.lua` only checks while its rain is active (builder check, 2026-11-18).
- The first plan task makes the final sound files with the names above from the downloads (the previews in `~/Downloads/cnr-thunder-preview` have other names), and puts the cut script in `tools/`.

## In-game checks (local test server)

1. Thunderstorms show up: pick "Thunderstorm" in the panel, and on random weather in summer they also come from cloudy or rain on hot days. The panel, the notices, the forecast and How to Play name them.
2. A storm (gale) has no lightning.
2a. A planned change can keep the weather: some cycles show no forecast and nothing changes, then the next real change is forecast as usual.
3. Strikes come in a thunderstorm at about the expected rate and stop when it clears.
4. The flash strength suits the distances.
5. The bolt shows at the right spot and only for strikes up to 4 km, and it looks right with the tweaks.
6. The thunder delay matches the distance (about 3 s per km), with the right recording per distance and a sensible volume.
7. In a tunnel or under a bridge there is no flash and no bolt.
8. The "Lightning flashes" setting turns flashes and bolts off.
9. Two players on the local server see the same strikes.
10. Nothing is left in the scene after the round: no light, no emitters.
11. The frame rate doesn't drop outside flashes.
