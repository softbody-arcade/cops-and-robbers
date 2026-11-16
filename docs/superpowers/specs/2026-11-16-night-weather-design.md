# Night and weather rounds

Status: design for review, 2026-11-16. The approach is agreed, a builder check is done, and the open game questions were settled with in-game tests (see "Tested in game"). Earth support is split off to a TODO item; the research for it is kept at the end of this doc. Visibility-based cop sight is a separate design that follows this one.

## Why
Some rounds should feel and play differently: night, rain, snow, fog. That adds atmosphere, and on some runs extra difficulty (harder to spot the runner, harder to read the road, less grip). It should not be every run. The host sets it in the panel, and everyone in a round gets the same conditions.

## Goals
- Panel settings for **Time of day** and **Weather**. Each can be the map's own (the default), a fixed choice, or random.
- Random follows **configurable chances** (night chance, bad weather chance) so hard rounds stay occasional unless the host wants more.
- A **Clock speed** setting: 0 is a stopped clock, 1 is real time, up to 120 times real time, so a round can run from dusk into night.
- **Weather affects grip** (a panel switch, on by default): rain makes roads and dirt wet, a storm also turns dirt roads to mud, snow covers everything you drive on, using the game's own wet, mud and snow surfaces, so tires matter (drag tires slide more on wet than road tires).
- The temperature follows the weather (cold in snow, so exhausts steam).
- A **New sky** button in prep picks new random values, like New car does for the car.
- Everyone in the round gets the same conditions, including a player who rejoins mid-round. Nobody can change the sky from the game's environment menu during the round.
- After the round, each player gets back the sky and the grip they had before.
- The prep card shows the round's conditions.

## Non-goals
- **BeamNG.Earth.** Separate TODO item. On `beamng_earth` the server sends no sky and the panel says the sky settings don't work there yet.
- **A date setting.** Time of day already gives sunrise, sunset and night; the date only shifts sun angle and day length.
- **Ice.** Tested: too much for a chase.
- **Snow or water building up on the ground.** The game has no build-up; its rain and snow are falling particles only (tested).
- **Wind pushing cars** (`groundWind`). Wind only moves the clouds.
- **Hard mode.** Not built yet. When it is, it raises both chances (noted on its TODO item).
- **Recording conditions in the leaderboard.** Could come later.
- **Player headlights.** The mod does not switch them on at night; driving with or without lights is the player's choice (the host's decision). Practice AI cars are the exception, see Design. A per-player headlight toggle belongs to the player settings card (TODO item).
- **Cop sight.** This design leaves sight as it is. Sight that follows visibility (fog thickness, darkness, street lights, whether the runner's lights are on) is the next design, built after this one.

## Anti-goals
- Hard rounds becoming the norm by default.
- A player's game left changed after the round or after leaving the server (stuck at night, wet roads or cold in freeroam).
- Players in one round getting different conditions.
- Anything changing for existing setups: time and weather default to the map's own, the clock speed to 0.

## Constraints (found in the game and in our code)
Game, BeamNG.drive 0.40.5, `lua/ge/extensions/core/environment.lua` unless noted:
- `core_environment.getState()` (`:1364`) returns the whole sky as one table: time fields (`time`, `play`, `dayLength`, ...), `cloudCover`, `fogDensity` (times 1000), `fogAtmosphereHeight`, `numOfDrops`, `windSpeed`, gravity, temperature (`temperatureCurveOverrideC`, `false` when the map's own). `setState(state, lerpSeconds)` (`:1511`) applies any subset of it.
- `core_environment.enableChanges(false)` (`:1765`) locks the sky; `canChange()` reads it. While locked, **every** setter does nothing, ours included, and the environment menu is greyed out. So: unlock, apply, lock again.
- `setState`'s fade only covers clouds and fog, and it **stops while locked** (`updateStateLerp`, `:1561`). So the sky is applied at once, not faded. Setup re-places every car anyway, so a jump is not noticeable.
- `time` runs 0 to 1, noon = 0, midnight = 0.5. Setting it switches the map's night lights. The game has named times (`defaultTimeOfDayOptions`, `:660`: sunrise, morning, noon, afternoon, sunset, night, and a few more). `getSolarTimeOfDayValue(key)` gives the value for the map's real sun, so "sunrise" is sunrise on every map. `dayLength` is the real seconds for one full day while `play` is on.
- **Temperature:** each map has a temperature curve over the day (`LevelInfo:getTemperatureCurveC()`); every frame the game sets the air temperature from the curve at the current time (`onUpdate`, `:1818`). `setTemperatureProfile({ averageC, minC, maxC })` (`:1409`) shifts or stretches the curve, −50 to 60 °C. Cars use it for engine, oil and brake cooling and fire; exhausts steam below 10 °C (`combustionEngineThermals.lua:161`). It does not change grip.
- **Rain on the map:** `numOfDrops` only writes to the map's first Precipitation object, and some maps (Utah, Johnson Valley) have none. We use our own object instead (tested, below).
- **Grip:** surfaces are ground models in `art/groundmodels.json`, loaded into `core_environment.groundModels[name].cdata`; aliases share their parent's `cdata` (`isAlias`, `parent`). `be:setGroundModel(name, cdata)` changes a surface live (the game's own `util/groundModelDebug.lua` does the same); `core_environment.reloadGroundModels()` puts the file values back. Grip is the surface value times the tire's multipliers; a tire's `treadCoef` (slick and race 0, sport 0.5, standard 0.7, off-road 0.85 to 1) is multiplied with the surface's `roughnessCoefficient`, which is 0 on dry asphalt and 0.2 on wet asphalt, so tread only starts to matter on wet or loose surfaces.
- The game's own surfaces used here (static / sliding grip, roughness): ASPHALT 0.98 / 0.70 / 0; ASPHALT_WET 0.92 / 0.55 / 0.2; GRAVEL 0.69 / 0.74 / 0.44; GRAVEL_WET 0.62 / 0.60 / 0.38; MUD 0.55 / 0.55 / 0.5 with depth 0.15 (cars sink in); SNOW 0.65 / 0.40 / 0.3.
- Which surfaces maps use: the materials of west_coast_usa, Utah, italy, east_coast_usa, johnson_valley and jungle_rock_island only name surfaces from the game's shared file (often by an alias, like CONCRETE for ASPHALT or DIRT_SANDY for DIRT_DUSTY_LOOSE). No vanilla map ships its own `groundModels/` folder; a mod map can, and those surfaces are unknown to us.
- Each player's car is simulated in their own game, so every player's game must apply the same surfaces and temperature for the round to be fair.

Our code:
- `cnr_roundSetup` (`main.lua:438`) can reach a player more than once in a round: New car, a rejoin, an evolving rebuild. The player's own sky must be saved only once per round, or we'd save our own round sky.
- `onClientEndMission` is wired to `leaveServer` (`copsAndRobbers.lua:860`), which calls `endRound`. On a map change the saved sky belongs to the level being unloaded and must be dropped, not applied.
- Settings are checked by `config.merge` (`cnr/config.lua`), with `CHOICES` for string settings and `MAXIMA` for upper bounds, and are locked during a round.
- The server already knows the map (`geoMode = mapName == "beamng_earth"`, `main.lua:1272`) and puts `map`/`geo` in the panel state.

## Tested in game (2026-11-16, west_coast_usa, throwaway console extension)
- A Precipitation object of our own (`createObject("Precipitation")`, `dataBlock` `Snow_menu` or `rain_medium`, `registerObject`, added to `MissionGroup`) shows snow and rain; deleting it stops it. Rain through the map's own object (`setPrecipitation`) works too.
- No snow builds up, at any amount or speed.
- Scaling every surface's friction (`be:setGroundModel`) makes cars slide. Copying the game's ASPHALT_WET values onto ASPHALT (and its 4 aliases) works live; **drag tires slide more on it than road tires**. SNOW on asphalt is fun; ICE is too much.
- Not tested yet: our own rain object on Utah; mud.

## Approaches
- **A. The game's environment state plus the lock (picked).** Save with `getState`, apply with `setState`, lock with `enableChanges`, put the saved state back after. Uses the same path as the game's own environment menu.
- **B. Weather presets shipped in the mod (`core_weather`, `art/weather/*.json`).** Presets have no undo, so A's save and restore would still be needed. The files are global and show up in every map's preset list. Time would still go through `core_environment`. Extra parts for nothing we need.
- **C. The server sends raw numbers instead of names.** The prep card and the panel need names anyway, and tuning numbers still means redeploying the mod.

For grip:
- **Swap in the game's own wet and snow surfaces (picked).** Tested: tires behave differently, as they would for real.
- **A flat grip cut on every surface.** Tested: it slides, but it hurts every tire the same and touches grass and sand too.

For rain and snow:
- **Our own precipitation object (picked).** Works on every map, also those without rain, and snow needs it anyway.
- **The map's own object.** Missing on some maps, rain only.

## Design

### Settings (server `cnr/config.lua`)
| Key | Values | Default |
|---|---|---|
| `timeOfDay` | `map`, `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night`, `random` | `map` |
| `nightChancePercent` | 0 to 100 | 25 |
| `clockSpeed` | 0 to 120, whole numbers | 0 |
| `weather` | `map`, `clear`, `cloudy`, `rain`, `storm`, `fog`, `snow`, `random` | `map` |
| `badWeatherChancePercent` | 0 to 100 | 25 |
| `weatherGrip` | true / false | true |

The two string keys go in `CHOICES`; the percentages and `clockSpeed` in `MAXIMA` (100 and 120).

### Panel
- A new **Sky** group in `settings.js` `GROUPS`: Time of day, Night chance, Clock speed, Weather, Bad weather chance, Weather affects grip. Time of day and Weather are `common` (in the short list).
- A new item kind for a pick-one setting (a list of values with labels: "Map default", "Sunrise", ..., "Random"), rendered in `PanelSettings.vue` and handled by `shown()`.
- Each chance item only shows while its setting is on random (a show-when condition on the item). Clock speed shows "stopped" at 0 and "N×" otherwise.
- On `beamng_earth` the group shows one line: "Not available on BeamNG.Earth yet".

### Picking (server, new pure module `cnr/sky.lua`, random function passed in)
- `pick(cfg, random)` returns `{ time = key or nil, weather = key or nil }`; `nil` means the map's own.
- Time on random: a roll under `nightChancePercent` gives `night`; otherwise one of `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, evenly.
- Weather on random: a roll under `badWeatherChancePercent` gives one of `rain`, `storm`, `fog`, `snow`, evenly; otherwise `clear` or `cloudy`, evenly.
- A fixed choice gives that key; `map` gives `nil`.
- On `beamng_earth`, nothing is picked.
- When: once at round start, practice rounds included, and again on New sky. New car and an evolving rebuild keep the sky. Each automatic next round picks fresh. The pick is kept on the current round.

### Sending
- `cnr_roundSetup` gets `sky = { time, weather, clockSpeed, grip, clockSeconds }` (fields left out when not set). `clockSpeed` is sent when above 0, `grip` when `weatherGrip` is on. `clockSeconds` is how long the round's clock has run so far (see Clock), so a rejoining player lands on the same time as everyone else. That covers setup, New car and rejoins.
- New sky sends a new `cnr_sky` message with the same shape to everyone in the round (in practice, only the host). A separate message, because a new sky must not re-place the cars.
- New sky also sends a short notice to the round's players, for example "New sky: Night · Rain".

### New sky button
- A new panel command (in `panel.lua` `COMMANDS`) and a **New sky** button next to New car in `PanelRound.vue`.
- Available before GO (`prep`, and `ready` in evolving mode) and only while time or weather is on random. That goes through `panel.can`, which gets to know whether either setting is random. Also in evolving mode: the sky is not tied to the car.
- Refused at other times, with a reply like "You can only change the sky before GO".

### Clock
- With `clockSpeed` 0 the clock is stopped for the whole round.
- With a speed N, the clock is stopped in prep and starts at GO (the countdown), so the picked time of day is what the chase starts in. It runs with `play = true` and `dayLength = 86400 / N`. My call: otherwise a long prep at a high speed would turn "sunset" into night before anyone drives.
- The server counts the seconds since GO and sends them as `clockSeconds`; a client sets `time = start + clockSeconds * N / 86400` and lets the clock run from there. The countdown message tells clients to start the clock.
- The temperature follows the clock through the map's curve, so nights get colder.

### Client (new module `copsAndRobbers/sky.lua`)
- **Times:** key to `core_environment.getSolarTimeOfDayValue(key)`, falling back to `timeOfDayKeyToTime[key]`.
- **Weather:** a table from key to sky values `{ cloudCover, fogDensity, fogAtmosphereHeight?, windSpeed }`, precipitation `{ dataBlock, numDrops, dropSize, minSpeed, maxSpeed }`, a temperature, and surfaces. Starting points:

| Weather | Sky | Precipitation | Temperature (curve average) |
|---|---|---|---|
| clear | few clouds | none | map's own |
| cloudy | heavy clouds | none | map's own |
| rain | heavy clouds, light fog | `rain_medium`, drop size 1, about 3000 | about 8 °C |
| storm | dark clouds, fog, fast clouds | `rain_medium`, more drops | about 8 °C |
| fog | light clouds, thick fog | none | about 5 °C |
| snow | heavy clouds, light fog | `Snow_menu`, drop size about 0.15 to 0.2, about 3000 to 8000 | about −5 °C |

  The values in game get tuned while building; the tested ones are the start.
- **Surfaces** (only with `sky.grip`; clear, cloudy and fog change none). "Becomes X" copies all physics fields of the game's surface X; "× n" multiplies only the two friction values and keeps everything else. Each group includes its aliases.

| Surface group | Rain | Storm | Snow |
|---|---|---|---|
| Paved: ASPHALT (CONCRETE, GROUNDMODEL_ASPHALT1, GRID), ASPHALT_OLD, ASPHALT_PREPPED, COBBLESTONE | becomes ASPHALT_WET | becomes ASPHALT_WET | becomes SNOW |
| RUMBLE_STRIP | static × 0.94, sliding × 0.79 (the dry-to-wet asphalt step, keeping its rumble) | as rain | becomes SNOW |
| Gravel: GRAVEL (DIRT_LOOSE) | becomes GRAVEL_WET | becomes GRAVEL_WET | becomes SNOW |
| Dirt: DIRT (DIRT_GRASS), DIRT_DUSTY (ROCKYDIRT, DIRT_ROCKY, DIRT_ROCKY_LARGE), DIRT_DUSTY_LOOSE (DIRT_SANDY, DIRT_LOOSE_DUSTY) | becomes GRAVEL_WET | becomes MUD | becomes SNOW |
| Grass: GRASS (GRASS2 to 4, FOREST, FOREST_FLOOR) | × 0.85 | × 0.75 | becomes SNOW |
| Already wet: GRAVEL_WET, MUD | as is | as is | becomes SNOW |
| Everything else: sand, rock, leaves, branches, metal, wood, plastic, a mod map's own surfaces | as is | as is | as is |

  My calls (the host left them to me): rain is moderate, so no mud; a storm turns dirt (not gravel, which drains) into mud; grass loses some grip in rain so a field isn't grippier than the wet road; snow covers everything you drive on. Mud is not tested yet: if road cars get stuck too easily in it, storm dirt becomes GRAVEL_WET like rain.
- **apply(sky):** if the sky has nothing set (time and weather on the map's own, clock speed 0), do nothing: no change, no lock. Otherwise, if nothing is saved yet this round, save `getState()`, whether the sky was locked (`canChange()`), and nothing else yet. Unlock, apply, then lock:
  - a set time: `time` from the key, `play = false` (the clock starts at GO, see Clock);
  - a set weather: the sky values, then the temperature with `setTemperatureProfile({ averageC })` when the weather has one;
  - a part on the map's own takes the map's default values from `core_environment.getInitState()`, not whatever the player had, so everyone in the round shares one sky even when only one part is set;
  - precipitation: our own Precipitation object (name like `cnr_precipitation`), created or updated for rain, storm and snow, deleted for the others; `numOfDrops` is not passed to `setState`, so the map's own rain object is left alone;
  - grip, when `sky.grip` is set and the weather has surfaces: before the first change this round, save the physics fields of each target surface; then for each rule in the Surfaces table either copy the source surface's physics fields (friction, hydrodynamic friction, Stribeck velocity, roughness, depth, strength, fluid fields) onto the target, or multiply its two friction values, and call `be:setGroundModel` for the target and each of its aliases. Groups whose surface the map doesn't have are skipped. A New sky first puts the saved surfaces back, then applies the new ones.
- **startClock(clockSeconds):** at GO, unlock, set `play = true`, `dayLength`, and `time` as in Clock, lock.
- **restore():** if something is saved: unlock, `setState(saved)` (this also puts back the temperature and the clock where it was at round start), put the saved surface fields back and `be:setGroundModel` them, delete our precipitation object, put the lock back the way it was before the round, and forget everything saved.
- **drop():** forget everything saved and put the lock back the way it was, without applying anything (the level, our object and its surfaces are being unloaded, and the game reloads surfaces on the next level).
- **Wiring:** `onRoundSetup` calls `apply(d.sky)` and, if the round is past GO, `startClock`. A `cnr_sky` handler calls `apply` and updates the prep card. The countdown handler calls `startClock(0)`. `endRound` calls `restore`, which covers round end, cancel and leaving the server. `onClientEndMission` calls `drop` before `leaveServer`.

### Practice AI cars
- AI cars can't switch their own lights on, so in a practice round at night (`core_environment.getLightState().isNight` after the sky is applied) `ai.lua` turns their headlights on when it places them (`electrics.setLightsState(1)`), next to the lightbar it already sets for AI cops. Without this an AI runner drives dark.

### Prep card
- `hudfeed.prep` takes a sky label and `hud.lua`'s role card gets a `sky` field, shown on the car line: `Gavril D-Series · Night · Rain`.
- Labels: Sunrise, Morning, Noon, Afternoon, Sunset, Night; Clear, Cloudy, Rain, Storm, Fog, Snow. A part on the map's own sky is left out. With neither set, the line is just the car, as today.

### Tests
- Server: config (new keys, choices, the caps); `sky.pick` with a fixed random function (chances of 0 and 100, fixed choices, `map` gives `nil`, snow in the bad pool, nothing on Earth); setup carries the sky, clock speed and grip; `clockSeconds` counts from GO and is 0 before; New car keeps the sky; New sky only before GO and only with a random setting; practice gets a sky; `panel.can`.
- Client (with `tests/client_stubs.lua`, stubbing `core_environment`, `be`, `createObject` and `scenetree`): saves once across repeated setups; restore puts back the state, the surfaces and the earlier lock and deletes our precipitation object; drop applies nothing; a sky with nothing set changes nothing; the sky is locked after apply; a part on the map's own comes from `getInitState()`; grip off leaves surfaces alone; aliases get the same surface; a New sky from rain to clear puts the surfaces back; the clock time from `clockSeconds`; AI cars get headlights at night and not by day.
- In game: rain and snow on west_coast_usa and Utah; night lights at night; the weather values look right on two or three maps; drag tires against road tires on wet and snow; a road car on a storm's muddy dirt road on Utah (stuck too easily means storm dirt falls back to GRAVEL_WET); exhaust steam in snow; clock speed 60 runs dusk into night; a rejoin mid-chase lands on the same time; after the round the sky, grip and temperature are back and the environment menu works again.

### Left to the builder
- The weather values and the exact times, starting from the table above, and fine-tuning the grass factors.
- Panel layout and wording, the command name, the notice text.
- How the pick-one item kind and the show-when condition are built in the panel code.
- Where the pick and the GO clock sit between `Round:start` and `main.lua`, as long as `cnr/sky.lua` stays pure and tested.

## BeamNG.Earth research (for the TODO item)
Kept from the first round of research, for when Earth support is built (`mods/unpacked/beamng_earth/lua/ge/extensions/beamngEarth/`).
- Earth's sky and weather only take over on its own map, `beamng_earth` (`sky.lua` `LEVEL_ID`, `inOurLevel`). Other maps are left alone.
- **Sky** (`sky.lua`): in 'real' mode it keeps TimeOfDay on the real clock and date for where the player is, and re-syncs every 30 s.
- **Weather** (`weather.lua`): real weather from Open-Meteo.
- **Manual takeover:** any other change, including ours through `core_environment`, flips that player's Sky or Weather to Manual, shows a toast and saves it in their Earth settings, so it outlasts our server. Don't use `core_environment` there.
- **Earth's own way in for a BeamMP server:** `beamngEarth_sky.setServerClock({ hours, speed, epoch })` / `serverClock()`, and `beamngEarth_weather.setPreset(name)` / `preset()`. `nil` hands back to the real clock or weather. No toast, no saved setting. `mpsession.applyServerSky` already uses them for Earth's own server plugin.
- **Limits:** the date is always today's real date; weather is one of six presets (clear, cloudy, rain, storm, snow, fog); a new preset fades in, 95 % after 60 s; players on Manual keep their own sky.
- **Undo:** read `serverClock()` and `preset()` before the round and put them back after it.
