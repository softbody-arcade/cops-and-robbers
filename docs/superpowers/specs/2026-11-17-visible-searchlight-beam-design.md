# Visible searchlight beam

Status: approved 2026-11-17 for 2.9.1. It builds on the police helicopter searchlight (`docs/superpowers/specs/2026-11-16-police-helicopter-design.md`). Extended the same day with a helicopter that really flies (see "Helicopter flight"), so the beam's angle and the light's sway come from the helicopter's own motion.

## Why
BeamNG lights only light the surfaces they hit; the engine renders only clouds as volumes. So the helicopter's searchlight shows as a bright spot on the road, but there is no shaft in the air. In real life a searchlight beam is visible from the side and from below:
- faintly on a clear night
- clearly in haze, cloud or rain

## Approaches (tried in game with a throwaway probe, 2026-11-17)
- **A cone drawn with the game's debug drawer:** see-through triangles drawn every frame.
  - It lines up exactly with the lit spot and sits behind wires and poles properly.
  - Soft layers and a fade along the length make it read as a beam.
  - **Picked.**
- **The game's hologram marker meshes** (`single_faded_column.dae`, `s_mm_gatecone.dae` as `TSStatic`):
  - they render solid and opaque at full glow, so the strength setting does nothing visible
  - they don't line up with the car
  - Rejected. A good mesh would need our own model.
- **Glare at the light source:** a SpotLight can use one of the game's flare definitions (`flareType`). `BNG_LightFlare_1` gives a soft halo where the helicopter is when you look up. **Added** on top of the cone.

## Design
- **Who sees it:** every player, while the searchlight exists, which means the helicopter is tracking at night.
  - The beam follows the light's fly-in, sway, fly-away and fades: its strength is the light's brightness factor (`fx.bright`, 0 to 1) times the weather strength.
- **Shape:**
  - It runs from the light's position to the point the light aims at, as wide as the light's cone (outer angle 16°, so the radius at a distance d is d·tan 8°).
  - It has a lamp-sized top: radius 0.4 m.
  - The edge is soft: 5 nested layers, so the centre is brightest.
  - It's brightest at the light and fades to half by the ground.
- **Strength by the round's weather** (the client's round weather, `traffic.weather()`):
  - clear, cloudy and rain: 0.06, 0.12 and 0.2
  - the map's own weather (no weather set) and BeamNG.Earth: 0.06
  - storm, fog and snow ground the helicopter, so no light and no beam
- **Near the camera:** a part of the beam within 6 m of the camera is invisible, and it is fully back by 18 m. So there are no see-through sheets around a car that is inside the beam.
- **Glare:** the light gets `flareType` `BNG_LightFlare_1` and `flareScale` 1.
- **Cost:**
  - 5 layers × 10 lengths × 24 sides, each quad drawn from both sides: about 4,800 triangles a frame, only while the light exists. The probe drew about 14,000.
  - A player setting, "Searchlight beam", in the HUD settings card, on by default. Off removes the beam and the glare on that player's game; the light itself stays.

## Helicopter flight
Until now the light sat straight above the car (40 m up, ±2 m drift) and moved with it instantly. A real helicopter holds off to one side, trails a fast car, swings wide on turns and circles a stopped one. The operator keeps the spot on the car from there.

- **The helicopter has its own position and velocity.** Each game simulates it while the helicopter is up (tracking or searching), also by day and with the light off, so it is where it should be when the light comes on.
  - **Chasing:** every frame it steers towards a target point.
    - Its wanted velocity is the car's velocity plus `FOLLOW_GAIN` (0.4 per second) × the distance to the target point, capped at `MAX_SPEED` 70 m/s (about 250 km/h).
    - It changes velocity by at most `MAX_ACCEL` 8 m/s².
    - So it keeps up with steady driving, lags and overshoots on sudden changes, and never jumps.
  - **Target point while the car moves** (above `SLOW_SPEED` 5 m/s, horizontally): `FOLLOW_BACK` 25 m behind the car along its direction of travel, `FOLLOW_SIDE` 15 m to one side, `HELI_HEIGHT` 50 m above the car. The side is picked at random on arrival.
  - **Target point when the car is slow or stopped:** a circle of `ORBIT_RADIUS` 30 m around the car, 50 m up, one lap every `ORBIT_PERIOD` 40 s. The circle starts at the helicopter's current bearing from the car, so switching modes doesn't make it turn back.
- **Arrival (fly-in):**
  - When the helicopter goes up after arriving or refuelling, it starts `APPROACH_DISTANCE` 300 m out in a random heading, `APPROACH_HEIGHT` 60 m up, at rest, and flies in under the same chase rule.
  - At night the light is on during the fly-in, rising from dark to full over `APPROACH_SECONDS` 8 s.
- **Leaving (fly-away):**
  - On refuel the target point moves 400 m away in a random heading, 80 m up.
  - At night the light stays on for `DEPART_SECONDS` 8 s, its brightness fading out over the last 3 s, then it's removed. The helicopter's position is dropped with it.
- **Under cover and back:** while searching, the helicopter keeps flying its target point around the car; the crew knows where the cover ends. At the exit the light appears at once where the helicopter is.
- **The light:**
  - It sits at the helicopter's position and aims at the operator's aim point.
  - Its reach (`range`) follows the slant distance to the car plus 30 m, never below 120 m. It's only rewritten when it changes by more than 5 m.
  - The spot grows when the helicopter is further off, as a real one would (cone 16°).
- **The operator's aim** keeps the spring, nudges and tremor tuned in 2.9.0, with one change:
  - The lag kick now comes from the change in the car's velocity relative to the helicopter, not from the car alone. When the car brakes or the helicopter swings round, the spot slips and is brought back.
  - The hover drift (`HOVER_DRIFT`, the sine waves on the light's position) is removed; the real flight replaces it.
- **Each game flies its own copy:** random choices (side, headings) are local, so two players may see the helicopter on different sides of the runner. That's acceptable, since nobody can compare the views.

## Code
- `client/lua/ge/extensions/copsAndRobbers/heli.lua`:
  - the helicopter flight: position and velocity, chase step, target points, fly-in and fly-away
  - the light placed at the helicopter, and its range
  - a beam step drawn after the light is placed each frame, from the light's position, its aim point and `fx.bright`
  - the weather strength table
  - the flare fields, set when the light is created and when the setting changes
- `client/lua/ge/extensions/copsAndRobbers.lua`: passes the round weather and the player setting to the searchlight tick.
- Player settings:
  - `playerSettings.lua`: a `beam` boolean, default true
  - `hud.lua`: carries it in the settings payload
  - `HudSettings.vue`: a "Searchlight beam" switch
- Docs:
  - How to Play: one line, the beam can be switched off in your settings
  - `docs/FEATURES.md`: the searchlight section
  - `docs/DEPENDENCIES.md`: the debug drawer's `drawTriSolid` with `color()`, `core_camera.getPosition()`, and the `BNG_LightFlare_1` flare datablock from the game's `art/datablocks/lights.datablocks.json`

## Tests
- **Flight:**
  - The speed never goes above 70 m/s, and the velocity never changes by more than 8 m/s² × dt.
  - Following a car at a steady 30 m/s, it settles near the target point 25 m behind, 15 m to the side and 50 m up.
  - When a car at 30 m/s stops, it overshoots and then circles at about 30 m radius, one lap in about 40 s.
  - The fly-in from 300 m reaches the target point. The fly-away moves away.
  - The position is continuous: no step longer than the top speed allows.
  - While searching, the helicopter keeps following, and the light reappears at its position.
  - The light's range follows the slant distance + 30 m, with a 120 m floor.
- **Aim:** the lag comes from the change in relative velocity. A car and helicopter moving together at a steady speed give no kick.
- **Strength:** per weather, scaled by the light's brightness factor.
- **Nothing drawn:**
  - without a light, by day, or with the setting off
  - with the setting off, the flare fields are cleared
- **Near-camera fade:** no triangles drawn for a part within 6 m of the camera, and full strength beyond 18 m.
- **Triangle budget:** at most 4,800 a frame.
- **Shape:** the beam starts at the light and ends at the aim point.

## In-game check
- **Flight:**
  - the helicopter trails and swings on a twisty road at speed
  - it circles a stopped car
  - the fly-in and fly-away look like flight
  - the sway feels like an operator correcting, not like noise
- **Distance views:** the beam from a distance in clear, cloudy and rain rounds, and the glare looking up.
- **Inside the beam:** no sheets from the runner's car.
- **Frame rate:** with the beam on and off.
- **Setting off:** the beam and glare go, and the light stays.

## Calls made (not discussed, easy to change)
- **Flight numbers:** 70 m/s top speed, 8 m/s², gain 0.4/s, 25 m behind, 15 m to the side, 50 m up, a 30 m circle every 40 s below 5 m/s, fly-away to 400 m at 80 m up. All are to be tuned in game.
- **Each game simulates its own helicopter** (no network sync).

## Left to the builder
- How the beam step gets the camera position and the debug drawer in tests (stubs).
- Exact colour: the light's own cool white (0.85, 0.92, 1).
