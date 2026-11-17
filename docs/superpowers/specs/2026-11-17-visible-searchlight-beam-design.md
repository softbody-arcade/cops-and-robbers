# Visible searchlight beam and a flying helicopter

Status: approved 2026-11-17 for 2.9.1. Revised the same day after a spec and plan review. After the first in-game test the same day, two parts were added: cover from the helicopter's line of sight (approved) and a helicopter sound (proposed). It builds on the police helicopter (`docs/superpowers/specs/2026-11-16-police-helicopter-design.md`). The light now hangs from a helicopter that really flies, so the beam's angle and the light's sway come from the helicopter's own motion.

## Why
- **No beam in the air:** BeamNG lights only light the surfaces they hit; the engine renders only clouds as volumes. So the 2.9.0 searchlight is a bright spot on the road with no shaft in the air. In real life the beam is visible from the side and from below: faintly on a clear night, and clearly in haze, cloud or rain.
- **No real helicopter:** the 2.9.0 light sat straight above the car and moved with it instantly. A real police helicopter holds off to one side, trails a fast car, swings wide on turns and circles a stopped car, while the operator keeps the spot on the car.

## Approaches (tried in game with a throwaway probe, 2026-11-17)
- **A cone drawn with the game's debug drawer:** see-through triangles drawn every frame.
  - It lines up with the lit spot and sits behind wires and poles properly.
  - Soft layers and a fade along the length make it read as a beam.
  - A fade near the camera removes the see-through sheets when the camera is inside the beam.
  - **Picked.**
- **The game's hologram marker meshes** (`single_faded_column.dae`, `s_mm_gatecone.dae` as `TSStatic`): they render solid and opaque at full glow, and don't line up with the car. Rejected; a good mesh would need our own model.
- **Glare at the light source:** a SpotLight can use one of the game's flare definitions (`flareType`). `BNG_LightFlare_1` (in the game's `art/datablocks/lights.datablocks.json`) gives a soft halo where the helicopter is when you look up. **Added** on top of the cone.

## Helicopter flight
- **Each game simulates the helicopter** while it is up (tracking or searching). It keeps flying by day and with the light off, so it is in the right place when the light comes on. No network messages are added: random choices are local, so two players may see it on different sides of the runner. Nobody can compare the views.
- **The car's velocity:** from `target:getVelocity()` when the object has it, otherwise from position deltas over the real frame time. With a frame time of 0 or less the flight keeps its last velocity and doesn't step. The simulation step is clamped to 0.1 s.
- **Chasing:** every frame the helicopter steers towards a target point.
  - Its wanted velocity is the car's velocity, plus the target point's own velocity relative to the car (while circling), plus `FOLLOW_GAIN` 0.4/s × (target − position).
  - That is capped at `MAX_SPEED` 70 m/s (about 250 km/h).
  - Its velocity moves towards the wanted one by at most `MAX_ACCEL` 8 m/s² × dt.
  - So it keeps up with steady driving, lags and overshoots on sudden changes, and never jumps.
- **Target point while the car moves:** `FOLLOW_BACK` 25 m behind the car along its horizontal direction of travel, `FOLLOW_SIDE` 15 m to one side (`side` ±1, picked at random on arrival), `HELI_HEIGHT` 50 m above the car.
- **Target point when the car is slow or stopped:** a circle of `ORBIT_RADIUS` 30 m around the car, 50 m up, one lap every `ORBIT_PERIOD` 40 s.
  - It turns counter-clockwise for `side` +1 and clockwise for −1.
  - The circle starts at the helicopter's current bearing from the car, so switching modes doesn't make it turn back.
  - The angle advances in the step, not in the target calculation.
  - It enters the circle below `SLOW_SPEED` 5 m/s and leaves above `FAST_SPEED` 7 m/s, so jitter doesn't flip the modes.
- **Starting mode** (on arrival or when joining): follow when the car's horizontal speed is 6 m/s or more, otherwise circle, starting at the current bearing (a random bearing for a helicopter placed on joining).
- **Jumps:** a car jump over `JUMP_METERS` 30 m in one frame shifts the helicopter's position (and its leaving point) by the same jump.
  - This covers a reset, a teleport, and BeamNG.Earth moving its origin.
  - The car's velocity counts as unchanged for that frame, so the helicopter keeps its place relative to the car. This also holds when the velocity comes from position deltas: the jump frame keeps the last velocity.
- **Arrival (fly-in):** when the helicopter goes up after arriving or refuelling and no flight exists, it starts `APPROACH_DISTANCE` 300 m out in a random heading, `APPROACH_HEIGHT` 60 m above the car, at rest, and flies in.
- **Short refuel:** if a flight still exists, because a refuel shorter than 8 s ended while it was leaving, it stops leaving and turns back from where it is. No teleport.
- **Joining mid-round:** when a game first sees the helicopter already up, the helicopter starts at its target point with the car's current velocity.
- **Leaving (fly-away):** on refuel the helicopter heads for a point `DEPART_DISTANCE` 400 m from the car, `DEPART_HEIGHT` 80 m above it.
  - The heading is within ±60° of the helicopter's current bearing from the car, so it never flies back over the runner.
  - After `DEPART_SECONDS` 8 s the flight is dropped.
- **Under cover and back:** while searching, the helicopter keeps flying its target point around the car; the crew knows where the cover ends. At the exit the light appears at once where the helicopter is.
- **Constants:** `APPROACH_*` and `DEPART_*` live in the flight module only. The searchlight code uses them from there.

## The light
- **Position and aim:** it sits at the helicopter's position and aims at the operator's aim point.
- **The operator's aim** keeps the 2.9.0 spring, nudges and tremor:
  - **Lag kick:** now from the change in the car's velocity relative to the helicopter, not the car alone. When the car brakes or the helicopter swings round, the spot slips and is brought back. When both brake together, it doesn't slip.
  - **Fly-in sweep:** the aim starts 15 m off the car (`AIM_SWEEP_OFFSET`) and is pulled in.
  - **Fly-away drift:** the aim drifts off the car towards the direction of travel (`DEPART_AIM_DRIFT`), up to 60 m by 8 s.
    - When a fly-away ends early (a short refuel, night ending into a fade, or night returning), the current drift is added to the aim's offset. The spring then pulls the spot back over a few seconds instead of snapping 40+ m in one frame. The offset cap is max(6, the current offset), as in 2.9.0.
  - **Refound:** the aim starts 8 m off the car (`REFOUND_AIM_OFFSET`).
  - **Hover drift removed:** `HOVER_DRIFT` and the sine waves on the light's position go; the real flight replaces them.
- **Brightness effects**, on the light's brightness factor `fx.bright`:
  - fly-in: rising to full over `APPROACH_SECONDS` 8 s, from 0 for a new light, or from the current factor when the light already exists
  - fly-away: full, then fading to 0 over the last `DEPART_FADE_SECONDS` 3 s of the 8 s; then the light is removed, after that frame's update
  - night ending: a 1.5 s fade
  - night returning: a 1 s fade-in
  - refound: at once, at full brightness
  - going under cover still cuts the light at once
- **Range:** max(120, slant distance to the car + 30), rounded to whole metres and capped at 400.
  - It's written when the light is created, and again whenever it differs from the last written value by more than 5 m.
  - The spot grows when the helicopter is further off (cone 16°), as a real one would.

## The beam
- **Who sees it:** every player whose game has the light: the helicopter is tracking at night, and the player's "Searchlight beam" setting is on.
  - Its strength is the weather strength × `fx.bright`.
  - So it follows the fly-in, fly-away and fades.
- **Shape:**
  - The beam follows the light's cone from a lamp-sized top (radius 0.4 m) at the light.
  - Each side line ends at the first of two points: where it meets the horizontal plane through the aim point (`z = aimPos.z`), or the straight-line distance D from the light. D = min(2 × the axis length, the occlusion hit distance). The game's depth test hides anything below the ground.
  - So on a slanted beam the far end lies on the road over the lit spot, not as a disc hanging in the air.
  - 5 nested layers give a soft edge, with the centre brightest.
  - The strength fades to half along each side line, towards the ground.
- **A vertical axis:** the ring's basis uses the x axis as the helper when the axis is nearly vertical (|axis.z| / |axis| > 0.9), so there's no NaN.
- **Blocked by solid things:** every 0.25 s a static ray is cast from the light, `castRayStatic(lightPos, normalized direction to the aim point, axis length)`.
  - A hit means the returned distance d < the axis length. Something is in the way, like a bridge deck, a building or a tunnel roof, so D = d and every side line ends at most d from the light.
  - A hit counts only when d < the axis length − 2 m and the hit point (lightPos.z + the direction's z × d) is more than 2 m above the aim point's height (`aimPos.z` + 2). Any other hit counts as no hit.
    - Within 2 m of the aim point along the ray: that's the road itself, or an aim point just under it.
    - At or below `aimPos.z` + 2: that's the ground at the lit spot. Over a flat road the ray reaches the aim point first. But where the ground at the lit spot is up to h above `aimPos.z` (the car's reference height), for example when the aim offset carries the aim point onto higher ground on a slope or a camber, a low beam's ray hits it h/sin(elevation) before the aim point. That is more than 2 m once h > 2·sin(elevation): 0.38 m at 11°, 0.68 m at 20°. Counting it would end the beam's upper half as an upright half-disc over the car.
    - Bridge decks and tunnel roofs over the car are well above `aimPos.z` + 2, so they still count.
  - When `castRayStatic` doesn't exist, the ray is skipped.
  - When D is 1 m or less (the light sits at or inside something), there's no beam.
- **Strength by the round's weather** (the client's round weather, `traffic.weather()`):
  - clear, cloudy and rain: 0.06, 0.12 and 0.2
  - any other value, nil (the map's own weather) and BeamNG.Earth: 0.06
  - storm, fog and snow ground the helicopter, so there's no light then
- **Near the camera:** each quad fades by the camera's distance to the quad's surface.
  - The fade runs from invisible within 6 m to full at 18 m.
  - **The plane:** every side line of a layer passes through the cone's virtual apex, so all the quads between two neighbouring side lines lie in one plane.
  - **Inside the quad:** when the camera projects inside the quad, the distance is the in-plane one, the camera's distance to that plane. Inside means between both side lines and past one rung but not the next, found by sign tests in the plane. Otherwise it is the distance to the nearest of the quad's four edges: its two side-line segments and its two ring segments (rungs).
  - **Planes:** once per pair of neighbouring side lines (at most 120 a frame): the normal, the camera's squared distance to the plane, and the camera's side of both side lines.
  - **Side lines:** once per side line (per layer and side), the camera is projected onto the line and the parameter kept. For each segment, that parameter is clamped to the segment's [t_j, t_(j+1)] and the distance taken (at most 1,200 segments a frame).
  - **Rungs:** each ring segment's distance and the camera's side of it in the plane are worked out once per frame (at most 1,320).
  - **Cost:** distances are kept squared, and the square root is taken only for a quad's nearest distance, and only when it is within 18 m.
  - **Why the surface, not vertices or edges:** a segment is a tenth of its side line, and the ring grows with the slant, so a quad can be tens of metres long and wide. A camera can be inside such a quad with every vertex and every edge beyond 18 m. On low beams that happens on the road 100–380 m past the lit spot.
  - So no drawn quad comes within 6 m of the camera.
- **Glare:**
  - The light gets `flareType` `BNG_LightFlare_1`.
  - `flareScale` follows `fx.bright`, rewritten when it changes by more than 0.05.
  - The glare belongs to the light, so the beam setting doesn't touch it.
- **Cost:**
  - Each ring's vertices are built once per frame. The colour objects are cached per alpha value. The quad list is kept between frames and reused, so no new quad entries are made each frame.
  - Each quad is drawn once, only in the winding that faces the camera (one dot product per quad), as two triangles through the game's FFI `require("utils/debugDraw").drawTriSolid` with the packed `color()` number and the depth test on. (Built first with `debugDrawer:drawQuadSolid`, which refuses the packed colour in 0.40: "expect userdata, got number", found in the first in-game test.)
    - That's at most 5 layers × 10 lengths × 24 sides = 1,200 quads a frame, which is 2,400 FFI triangle calls, or 4,800 (both windings) when the camera position is unknown.
    - The game's own editor code draws both windings for the same reason (`editor/api/gui.lua`: "keep backface cull off").
  - Budget: at most 0.5 ms a frame for the beam (an in-game check).
  - With the slant distance over the 400 m range cap, there's no beam.
- **Safety:** the beam, both working out its quads and drawing them, runs in its own `pcall`. An error stops the beam for the rest of the round (`beamFailed`), but never removes the light.
  - The beam also needs `debugDrawer` and `color` to exist.
- **The player setting:** "Searchlight beam" in the HUD settings card, on by default. Off removes the beam, the cone in the air, on that player's game. The light and its glare stay.

## Line of sight (added after the first in-game test, approved 2026-11-17)
- **Why:** cover was a roof check: rays straight up from the car. A building between the helicopter and the car never counted, so the light could be blocked on screen while the server still said "tracking". Now the helicopter has a position, so cover can be what the helicopter sees.
- **The check:** on the game that reports cover today (the runner's, or the issuer's in practice), every 0.25 s while that game's helicopter flight exists:
  - `castRayStatic` from the flight's position to three points on the runner's car: the middle at 1.5 m above the car's position, and 2 m ahead and 2 m behind it along the car's direction, at the same height
  - a point is seen when the ray reaches within 0.5 m of it
  - the car is covered when no point is seen
- **Before the helicopter exists** (head start, the arrival countdown, a refuel after the fly-away): the roof check as today, so the head-start hiding and the state at arrival still work.
- **Unchanged:**
  - the client needs the same reading twice in a row (about 0.5 s) before it reports a change, and the server needs 2 s of cover before "searching"
  - tracking again the moment a point is seen
  - the light is cut while searching
  - the beam's own blocking ray
- **The same helicopter on every game:**
  - The server picks a new random seed each time the helicopter goes up (from "arriving" or "refuelling") and sends it in the helicopter status it already sends (`cnr_heli` and the round setup's `heli`).
  - Each game draws the flight's side, its fly-in bearing and its fly-away heading from a small generator seeded with it, separate from the operator sway's randomness.
  - A game joining mid-round (`at`) draws from the same seed in the same order, so it takes the same side and bearing.
  - Positions still differ a little between games: network lag on the runner's car, and a joiner starts on its target point instead of mid-fly-in.
  - A short refuel resumes the existing flight and ignores the new seed.
- **Gameplay:** the runner loses the helicopter behind buildings, in valleys and while it flies in low from 300 m. That is intended. The height (50 m) and side offset (15 m) become balance values, tuned in game.
- **Trees:** whatever `castRayStatic` hits counts. The game's drone camera uses the same call for line of sight. Whether trees block it is an in-game check.

## Helicopter sound (proposed 2026-11-17)
- **Why:** you hear a police helicopter long before you see it, and the runner hearing it is part of the chase.
- **The sound:** one looping 3D `SFXEmitter` named `cnr_heli_sound` at the simulated helicopter, on every game, moved with it every frame.
  - It plays day and night while the flight exists, and is removed with it: on the drop after the fly-away, `clear`, the round's end, a cancel, leaving, a map change and unload. No emitter is left behind.
  - The game's 3D audio fades it with distance, so the fly-in and the fly-away get louder and quieter by themselves. The reference and maximum distances are tuned in game (start: 40 m and 800 m).
  - It fades in over 1 s when the flight starts close (a game joining mid-round) and fades out over the fly-away's last 3 s, so it never cuts off.
  - **Muffled when hidden:** one ray every 0.25 s from the camera to the helicopter. When it's blocked, the volume eases down to half over 0.5 s, and back up when it's clear.
  - **A player setting** "Helicopter sound", on by default, next to "Searchlight beam".
- **The file:** one mono OGG loop of a helicopter's rotor heard from a distance, shipped in the mod at `art/sound/cnr/heli_rotor.ogg` (the client zip gains its `art` folder). Its licence and credit go in `docs/DEPENDENCIES.md` and `README.md`. A CC BY-NC sound is fine for this free mod, credited; it would have to be replaced if the mod or the server were ever sold.
- **First, a quick in-game probe:** an emitter made from Lua with `fileName` pointing into the mod's zip plays 3D, loops and follows `setPosition`.
- **Not doing:** Doppler, and a separate close-up sound.

## Code
- **`client/lua/ge/extensions/copsAndRobbers/heliFlight.lua` (new, pure):**
  - the flight: position, velocity, side, orbit, leaving point
  - `arrive`, `at`, `leave`, `step`, target points, jump shift
  - all maths per component, building results with `vec3(x, y, z)` (the test stubs' `vec3` has no operators)
  - the bearing uses `math.atan2`, which exists in the game's LuaJIT; tests add the shim from `client_stubs.lua`
- **`client/lua/ge/extensions/copsAndRobbers/beam.lua` (new, pure):** strength, and the quads with their colours and windings for a light, aim point, hit distance and camera.
- **`client/lua/ge/extensions/copsAndRobbers/heli.lua`:**
  - the flight lifecycle and the light at the helicopter
  - the brightness effects, range, aim with relative velocity
  - the occlusion ray, the beam drawn in its own pcall, the flare
- **`client/lua/ge/extensions/copsAndRobbers.lua`:** passes the round weather and the beam setting to the searchlight tick.
- **Player settings:**
  - `playerSettings.lua`: a `beam` boolean, default true
  - `hud.lua`: carries it in the settings payload
  - `HudSettings.vue`: a "Searchlight beam" switch
- **Docs:**
  - **How to Play:** the helicopter items at `HowToPlay.vue` (runner tab around lines 58-71, cop tab around 115-126) get a line that the beam can be turned off in your settings.
  - **`README.md`:** the player settings line says three switches.
  - **`docs/FEATURES.md`:** the searchlight section: the flight, the beam, the glare, the setting.
  - **`docs/DEPENDENCIES.md`:**
    - update the SpotLight entry, which still says it "hovers 40 m above"
    - add the FFI `utils/debugDraw` `drawTriSolid` with the packed `color()`, `core_camera.getPosition()`, the vehicle's `getVelocity()`, `castRayStatic` for the occlusion, and the `BNG_LightFlare_1` flare datablock
  - **The 2.9.0 spec's searchlight lines** point here for the flight.

## Tests
- **Flight** (dt 0.05 unless stated):
  - The speed never goes above 70 m/s, and the velocity never changes by more than 8 × dt per step.
  - Behind a car at a steady 30 m/s (+x) it settles within 3 m of (−25, 15 × side, 50) from the car.
  - When a 30 m/s car stops, it overshoots, then circles at 30 ± 2 m, 50 ± 2 m up, at 2π/40 rad/s ± 20%, in its side's direction.
  - The fly-in from 300 m (car still) is within 5 m of its target point at 20 s.
  - After a fly-away with the heading within ±60° of its bearing, it's more than 200 m from a still car at 8 s, and the distance grows every second.
  - No step moves further than 70 × dt.
  - `at()` starts on the target point with the car's velocity.
  - Hysteresis: speeds between 5 and 7 m/s don't switch the mode.
- **Jumps:**
  - After a 2 km car jump, the helicopter's step matches the same step without the jump, to 1e-9.
  - With car and helicopter both at 30 m/s in +x and a 50 m car jump in +x, the helicopter's x velocity doesn't increase.
- **Short refuel:** "tracking" → "refuelling" → "tracking" within 7 s doesn't move the helicopter more than 70 × dt per step, doesn't call `arrive`, and ramps the brightness up from its faded value.
- **Aim:**
  - Car and helicopter braking together from 30 to 0 over 1 s keep the offset within `NUDGE_RADIUS` + 0.3.
  - The car braking alone gives an offset above 1 m.
- **Light:**
  - It sits at the helicopter.
  - Range: 130 at 100 m, 120 at 60 m, and written on creation even when the stored value matches.
  - It's cut under cover.
  - Refound happens at once, at full brightness.
  - The fly-away fades and is removed after 8 s, with the flight dropped after the light update.
  - By day there's no light, and the flight is dropped after a day refuel.
- **Beam:**
  - strength per weather and brightness
  - the call count: 1,200 with a camera, 2,400 without, at strength 0.2
  - a vertical beam draws only finite vertices
  - a 60° beam's far ring lies at `aimPos.z` ± ε
  - no drawn quad's surface comes within 6 m of the camera:
    - with the camera at the aim point
    - for an 11° beam and an 8° beam at a 400 m slant, with the camera 0.5 m above the centre of the near-ground quad whose nearest vertex is farthest from its centre, and 0.5 m above the middle of the longest side-line segment
    - for 13° (80 m up), 18° (80 m), 16° (70 m), 11.3° (78 m) and a 60° tracking beam, with cameras 0.5 m and 2 m above the road on a grid over the whole footprint, up to about 380 m past the lit spot
  - an occlusion hit at half the axis leaves no vertex further than the hit + 1e-6 from the light, also for 30° and 11° beams
  - a hit within 2 m of the aim point is ignored
  - at about 11°, a hit 2.6 m short of the aim point (the road at the lit spot, under `aimPos.z` + 2) is ignored; a deck 5 m above the spot ends the beam
  - a hit 0.1 m from the light gives no beam (no NaN)
  - a low (11°) beam has no vertex further than 2 × the axis length + 1e-6 from the light
  - nothing is drawn without a light, by day, with the setting off, or at a slant over 400 m
  - an error in the drawer, or in working out the quads, stops the beam and keeps the light
  - a fly-away ended early by a short refuel adds the drift to the aim's offset, with no jump in the aim point
  - the flare is set with the light whatever the setting, and its scale follows `fx.bright`

## In-game check
- **Flight:**
  - it trails and swings on a twisty road at speed
  - it circles a stopped car
  - the fly-in and fly-away look like flight
  - the sway feels like an operator correcting, not like noise
  - a reset or teleport doesn't fling it
- **Light:** the spot's brightness at the new slant of about 58 m (twice the spot area of the 2.9.0 light at 40 m), so brightness 80 may need retuning.
- **Beam:**
  - from a distance in clear, cloudy and rain rounds
  - banding at the clear strength
  - no sheets from the runner's car
  - a bridge deck ending the beam
  - toggling the setting while the light is on: the cone goes and comes back, and the glare stays
- **Glare:**
  - looking up
  - it follows the fly-in and fly-away
  - whether the spot dims when the helicopter's position is hidden from the camera (flares can change their light)
- **Line of sight:**
  - "SEARCHING" shows about 2.5 s after a building is between the helicopter and the car
  - trees
  - stopping under a bridge versus driving under it
- **Frame rate:** the beam on and off, within 0.5 ms.

## Calls made (not discussed, easy to change)
- **Flight numbers:** 70 m/s, 8 m/s², 0.4/s, 25 m behind, 15 m to the side, 50 m up, a 30 m circle every 40 s, 5 / 7 m/s hysteresis, fly-away to 400 m at 80 m up within ±60°. To be tuned in game.
- **Range cap:** 400 m, with no beam beyond it.
- **Beam blocking:** a ray every 0.25 s, so the beam ends at a bridge or a roof.
- **Glare:** its scale follows the light's brightness. The beam setting turns off only the cone; the glare stays with the light, since it costs nothing and is part of how a real light looks.
- **Each game simulates its own helicopter.** Since the line-of-sight change, the server's seed makes them take the same side and directions; positions are not synced.

## Left to the builder
- The test stubs for the debug drawer, `color`, the camera position and `getVelocity`.
- Exact colour: the light's own cool white (0.85, 0.92, 1), as 217, 235, 255.
