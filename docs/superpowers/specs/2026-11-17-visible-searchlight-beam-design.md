# Visible searchlight beam

Status: approved 2026-11-17, a small change for 2.9.1. It builds on the police helicopter searchlight (`docs/superpowers/specs/2026-11-16-police-helicopter-design.md`).

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

## Code
- `client/lua/ge/extensions/copsAndRobbers/heli.lua`:
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
- **Strength:** per weather, scaled by the light's brightness factor.
- **Nothing drawn:**
  - without a light, by day, or with the setting off
  - with the setting off, the flare fields are cleared
- **Near-camera fade:** no triangles drawn for a part within 6 m of the camera, and full strength beyond 18 m.
- **Triangle budget:** at most 4,800 a frame.
- **Shape:** the beam starts at the light and ends at the aim point.

## In-game check
- **Distance views:** the beam from a distance in clear, cloudy and rain rounds, and the glare looking up.
- **Inside the beam:** no sheets from the runner's car.
- **Frame rate:** with the beam on and off.
- **Setting off:** the beam and glare go, and the light stays.

## Left to the builder
- How the beam step gets the camera position and the debug drawer in tests (stubs).
- Exact colour: the light's own cool white (0.85, 0.92, 1).
