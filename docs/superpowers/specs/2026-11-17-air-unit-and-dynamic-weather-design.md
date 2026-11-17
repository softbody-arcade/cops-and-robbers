# The helicopter as a real air unit, and dynamic weather (2.10.0)

Status: for the user's approval, 2026-11-17, after a builder check. Builds on 2.9.4. That release made the helicopter fly, search where it last knew the runner was, wait at tunnel exits, take guidance from the cops' sight, sweep its light and make a rotor sound (`2026-11-17-visible-searchlight-beam-design.md`). It also builds on the night and weather rounds (`2026-11-16-night-weather-design.md`, `2026-11-16-sky-transitions-design.md`).

## Why
- **The user's brief:** "most realism with gameplay balance in mind". Every helicopter behaviour should be what a real police air unit would do.
- **Searching:** in 2.9.4 a search after a refuel, or after losing a runner who was driving away, circles the spot where they were last seen. A real crew searches ahead along the road the suspect was on, because they keep driving.
- **Tunnels:** after a loss in a tunnel, the helicopter waits at the exit ahead forever. A real crew works out when the suspect should come out, and checks the next way out when they don't.
- **Tracking position:** the helicopter tracks from 50 m up and 25 m behind. That is too close for a real air unit, and it is often blocked by buildings, which matters now that it has to see the runner.
- **Weather:** a round's weather is fixed for the whole chase. Real weather moves: rain clears or builds to a storm. Real air units don't fly in storms or thick fog.

## Goals
- The helicopter searches like a real crew:
  - after a refuel, and after losing a moving runner: a road search ahead along the road the runner was on
  - over a stopped runner: containment
  - at a tunnel: a timed watch of each way out
- It tracks from a realistic height and stand-off, sees over most buildings, and keeps its light useful.
- The weather can change once or twice during a chase, the same for every player at the same moment. It blends over about a minute, and grip, wind, rain, sound and lights follow it.
- The helicopter is grounded when the weather turns to storm or fog. It comes back when the weather clears.
- Everything stays deterministic across games: the server's seeds and the round clock decide; positions come from each game's copy of the runner's car, as in 2.9.4.

## Non-goals
- Syncing the helicopter's position over the network. Each game still simulates its own.
- Thunder and lightning (a separate Idea).
- A leaderboard conditions filter (a separate Idea). Records gain the start weather so the filter can use it later.
- BeamNG.Earth weather. The sky is off there, as now.
- Changing time of day, the date or the temperature curve during a round.

## Anti-goals (a failure even if it works)
- Two players' helicopters doing visibly different things after the same loss, beyond network lag and tunnel-mouth timing (accepted in 2.9.4).
- The game's environment menu staying unlocked during the chase, open to players for more than an instant at a time.
- A weather change that resets the clock, the time of day or the date.
- The helicopter vanishing in mid-air when it is grounded. It flies away.
- A search that never ends or gets stuck: every search has a bounded route and a fallback.
- Per-frame cost growing noticeably. Route building happens on events, never per frame.

## The user's decisions
- **Sight:** the helicopter's sight stays a thermal view. It sees the runner by line of sight within 400 m, day and night, and the light plays no part ("as is; thermals would allow them to anyway").
- **Tunnels:** the timed tunnel watch as described below.
- **Version:** this is 2.10.0, with dynamic weather folded in.

## Approaches
- **Road search:**
  - (a) Build a route on the road graph ahead of the loss and fly it, sweeping the road. **Picked:** this is what a crew does, and it reuses the tunnel walk's graph code.
  - (b) Widen the 2.9.4 spiral over time. Rejected: it doesn't follow roads and isn't realistic.
  - (c) Predict the runner's position from their speed and jump the search spot there. Rejected: it reads as cheating and fails at junctions.
- **Weather change on the clients:**
  - (a) The server sends a schedule once, in the sky payload. Every game runs it from the round clock. **Picked:** no new messages, joiners compute the current state, and it is deterministic.
  - (b) The server sends a message at each change. Rejected: more network traffic, and joiners would need the state replayed.
- **Blending:**
  - (a) A game blend over 60 s. Rejected: the environment would be unlocked for the whole minute, which breaks an anti-goal of the sky transitions spec.
  - (b) **Picked:** our own stepped blend. Clouds and fog step twice a second through an instant `setState`, with the environment unlocked only for each call. Rain uses its own fade, and wind its own push.

## Part A: the helicopter as an air unit

### A1. Height and stand-off (`heliFlight.lua`)

| Constant | 2.9.4 | 2.10 |
|---|---|---|
| `FOLLOW_BACK` | 25 | 40 |
| `FOLLOW_SIDE` | 15 | 60 |
| `HELI_HEIGHT` | 50 | 100 |
| `ORBIT_RADIUS` (circling a stopped runner) | 30 | 80 |
| `SEARCH_RADIUS` (containment circle) | 60 | 120 |
| `APPROACH_HEIGHT` | 60 | 120 |
| `DEPART_DISTANCE` | 400 | 600 |
| `DEPART_HEIGHT` | 80 | 150 |

- The other flight values stay: `MAX_SPEED` 70, `MAX_ACCEL` 8, `FOLLOW_GAIN` 0.4, the periods and the hysteresis.
- Tracking slant is about 123 m (was about 58 m). A real crew keeps a stand-off to keep the car in view. Height also sees over most buildings, which balances the harder searching.
- **The light:**
  - `BRIGHTNESS` goes from 80 to 160, a start value tuned in game. The spot is about 4.5 times larger in area at the new slant.
  - Range is still max(120, slant + 30), capped at 400.
  - The beam is unchanged.
- **Sight** stays 400 m. From 100 m up it reaches about 387 m along the ground.

### A2. How a loss is searched
When the helicopter loses the runner, or the cops' guidance ends while searching, each game picks a search mode from the runner's car at that moment:
- **Tunnel watch:** the car is under a roof (the roof check), and a tunnel walk finds at least one exit (`tunnels.lua`). See A3.
- **Road search:** the car's horizontal speed is at least `SEARCH_MOVING_SPEED = 5` m/s and it is not in a tunnel. See A4.
- **Containment:** otherwise (a stopped or slow runner, or no road data). The 2.9.4 behaviour: circle the spot at `SEARCH_RADIUS` and sweep the spiral.

**At the first arrival of a round:**
- The same choice, from the runner's car when the helicopter goes up: where dispatch says they are, which way they are heading, and how fast. A real crew gets "heading north on X road" from the ground units.
- Balance: the arrival delay (`helicopterArrivalSeconds`, 60 s) is what the runner gets. In the open within 400 m it sees them at once anyway.

**After a refuel:**
- The same choice, made from the last known state. When this game last tracked the runner, or the cops last guided it, it stored the position, direction of travel and speed.
- A joiner without a last known state uses the runner's current car, as in 2.9.4.
- While the cops guide it, it circles the runner's live position, as in 2.9.4. Guidance overrides every mode.

### A3. Tunnel watch (`tunnels.lua` extended)
- **Candidates:** the walk returns an ordered list of ways out. Exits ahead come first, straightest-on first (the smallest turn summed along the path), with ties by node id and the seed. Then comes the entrance behind the car (a U-turn). Each candidate carries its road path length from the car.
- **Watching:** the helicopter watches each candidate in turn. Watch time = clamp(path length / max(speed at the loss, 10 m/s) × 1.5, 15, 90) s, counted from when it switches to that candidate.
- **No exit seen in time:** it moves to the next candidate.
- **After the last candidate:** it switches to a road search starting at that candidate's node, outward along its road (A4), with the speed at the loss.
- **Cost:** the same walk as 2.9.4, done once per loss. It returns the candidate list instead of one exit.

### A4. Road search (new pure module `roadSearch.lua`)
- **Routes,** built once when the search starts, from the origin (the car's position, or the last known position), its direction and its speed:
  1. **Ahead:** from the closest road (within 15 m, as `tunnels.lua`), walk forward. At each junction take the straightest continuation; break ties by node id and then the seed. Stop at 2,500 m, at a dead end or at 200 nodes.
  2. **Alternative:** the best other branch at the first junction on route 1 within 500 m of the origin, walked the same way for up to 1,500 m.
  3. **Back:** walk the other way from the origin (a U-turn) for up to 1,000 m.
- **Fallback:** with no road within 15 m (off-road, or no graph on BeamNG.Earth), there is no route and the search is containment.
- **Flying the route:** a search point moves along each route in turn at `SEARCH_SPEED = 45` m/s (faster than most runners, so it can gain on them). The helicopter follows that point in follow mode with the A1 offsets, as if the point were a car driving the route.
  - At the end of a route, the next route starts. The helicopter flies there under its normal speed limits; the search point waits at the next route's start until the helicopter is within 150 m.
  - After all routes, containment at the origin.
- **The light during a road search:** it sweeps across the road ahead. The aim point is 60 m ahead of the search point along the route, plus a side offset of 15 m × sin(2π t / 3 s) across the road. Its height comes from the 2.9.4 ground ray.
- **Determinism:** routes depend only on the graph, the origin, the direction and the seed. Each game builds its own; small origin differences from lag can pick a different road at a junction. That is accepted, like the tunnel mouth.

### A5. Searching after the weather grounds it
See B5. A grounded helicopter flies away and drops its search. When it comes back, it starts a new search as after a refuel (A2).

### A6. Unchanged
- The cops' guidance.
- Sight: a thermal view within 400 m, day and night.
- The 2 s loss and the instant re-acquire.
- The tunnel exit seed rule (now an order).
- The sound.
- The beam and its setting.

## Part B: dynamic weather

### B1. Setting
- **`weatherChanges`:** a boolean, default true. Panel: Sky group, a "Weather changes" switch with the help "The weather may change once or twice during the chase".
- **Scope:** no effect on BeamNG.Earth (no sky), and none when the round's weather is snow (B2).
- **Settings are locked during a round,** as now.

### B2. The schedule (server `cnr/sky.lua`)
- **When:** at `pick` (round start and New sky), when `weatherChanges` is on and the sky has a weather. The schedule uses a new `weatherSeed` (1..2147483646) through a seeded generator (Park–Miller, as the flight seed), so New sky re-rolls it.
- **Number of changes:** 0 (40%), 1 (45%) or 2 (15%).
- **Times,** on the round clock that the clients already keep (seconds since the countdown started, `clockSeconds`):
  - first change at countdown + head start + uniform(120, 360) s
  - second change at the first + uniform(180, 360) s
- **Transitions** (the next weather, weighted):

  | From | To |
  |---|---|
  | clear | cloudy |
  | cloudy | clear 0.4, rain 0.4, fog 0.2 |
  | rain | cloudy 0.5, storm 0.5 |
  | storm | rain |
  | fog | cloudy |
  | snow | none: snow rounds don't change (one snow preset, and the date is in winter) |

- **Payload:** the sky payload gains `changes = { { at = seconds, to = weather }, ... }`. The base `weather` stays the start weather.
- **Server state:** the server keeps the schedule in `round.sky` and works out the current weather from its own round clock (B5, B6).

### B3. The change on the clients (client `sky.lua`, `rain.lua`, `surfaces.lua`, `wind.lua`)
- **Driver:** `sky.update` runs the schedule from `roundTime`, the clock the wind gusts already use.
- **Each change lasts `CHANGE_SECONDS = 60`:**
  - **Clouds and fog:** stepped twice a second from the old values to the new (smoothstep). Each step is an instant `setState({cloudCover, fogDensity})`, with the environment unlocked only around that one call.
  - **Never touched:** time, `play`, `dayLength`, the date or the temperature curve.
  - **Rain and snow:** `rain.target(newSpec, CHANGE_SECONDS)`. Rain ↔ storm ramps the drops and volume. The drop size and speed switch at the halfway point, not at once.
  - **Wind:** the base wind speed and the gust table cross-fade over the change. The gust cache is keyed by weather, so blend the two outputs.
- **Grip:**
  - **Getting wetter:** wet surfaces when the precipitation passes half its target.
  - **Drying:** dry surfaces `DRY_SECONDS = 60` after the precipitation has fully stopped, since roads stay wet for a while.
  - **Driving off:** with `weatherDriving` off, grip never changes, as now.
- **Lights:**
  - traffic headlights follow the current weather; today they never switch off when it clears
  - practice AI cars switch on in bad weather too
  - own auto headlights already follow it
- **HUD notice** at the start of each change, shown 4 s like "New sky":
  - "Weather: rain coming"
  - "Weather: the rain is getting heavier" (rain → storm)
  - "Weather: the storm is easing" (storm → rain)
  - "Weather: clearing up" (to clear or cloudy from rain or fog)
  - "Weather: clouds coming in" (clear → cloudy)
  - "Weather: fog rolling in"
- **The searchlight beam's strength** follows the current weather (it already reads `traffic.weather()` every frame; keep that up to date).
- **Joining or reconnecting mid-chase:** the setup payload carries the schedule and `clockSeconds`. The client applies the weather in effect at that moment. If a change is running, it uses the in-between values and runs the rest of the change from there.

### B4. Round start and New sky
Unchanged, except that the schedule is rolled with the sky. Prep shows only the start weather. The schedule is a surprise.

### B5. The helicopter and the weather (server `helicopter.lua`, client `heli.lua`)
- **Grounding:**
  - When a change to storm or fog starts, the helicopter is recalled: its phase becomes "grounded" with the reason (the new weather).
  - If it was up, every game flies it away first (the refuel fly-away, with the light fading) rather than dropping it.
- **Coming back:** when a change from storm or fog to rain, cloudy or clear ends, a grounded helicopter becomes "arriving" with `helicopterArrivalSeconds`, then flies up as usual.
- **Rounds that start grounded:** a round that starts in storm or fog (or snow, which never changes) starts grounded as now, and can come back the same way.
- **The server:**
  - `helicopter.update` gets the current weather (B2 state). Grounded is no longer final.
  - `flew()` is true if it was ever up.
  - **Time up:** each time it goes up, it gets a full `helicopterUpSeconds`, because the crew refuels while grounded. Time up only runs while it is up.
  - A grounding during a refuel cancels the refuel. It comes back through "arriving" when the weather clears.
- **HUD:** "HELICOPTER GROUNDED (STORM)" as now. When it is coming back: "HELICOPTER IN 1:00".

### B6. Records
- `weather` in a run's record is the **worst** weather of the round: clear 0 < cloudy 1 < rain 2 < fog 3 = snow 3 < storm 4.
- New field `weatherStart`: the start weather.
- The label and the existing filters keep using `weather`.

### B7. Docs
- FEATURES: the helicopter and night and weather sections.
- How to Play: the helicopter, plus a line on weather changes and grounding.
- README: the config table and the helicopter text.
- DEPENDENCIES: the environment calls, the road graph for the road search, and the stepped blend.
- The panel help.

## Part C: split the flight lifecycle out of `heli.lua` (first, no behaviour change)
- **Why first:** `heli.lua` is 646 lines, and Part A changes the flight lifecycle heavily. A 2.9.4 review recommended this split before the next helicopter feature.
- **New module** `heliSearch.lua` owns:
  - the functions `carVelocity`, `fly`, `retarget`, `spotFor`/`exitAhead`, `flightTick` and `soundLevel`
  - the state fields `flight`, `leftAt`, `lastClock`, `lastCar`, `carVel`, `flightRandom`, `lastKnown`, `wasGuided`, `sweepAt`, `retargetAt`, `missingSince`, `tunnelLogged` and `flightFailed`
  - the interface `tick(state, target, phase, last, clock, opts)`, `drop(state)` and `clear(state)`
- **`heli.lua` keeps** the status (`set`), cover, the light, aim, sweep, beam, the two-part `pcall` in `lightTick`, and `clear`.
- **Couplings to cut:**
  - `dropFlight` removing the light: the light part already removes a light without a flight.
  - `carVelocity` resetting `sweepRayAt`: expose a jump time for the light to read.
- **Jump detection** moves into one helper (the TODO Issue).
- **All existing tests pass unchanged,** apart from requires.

## Tests (outline; the plan pins the numbers)
- **Flight:** the new constants keep the limits; the tracking settle point is about (−40, 60·side, 100); circling a stopped car at 80 m; containment at 120 m.
- **Road search** (pure):
  - straight-on routes through junctions
  - the alternative branch at the first junction
  - the back route
  - the caps (2,500 / 1,500 / 1,000 m, 200 nodes)
  - no road within 15 m means no routes
  - deterministic for the same input
  - a ring road terminates
  - the search point moves at 45 m/s
- **Tunnel watch:** the candidate order (straightest exit first, then the others, then the entrance); the watch times; the switch to the next candidate; a road search after the last.
- **Mode choice:**
  - the same choice at the first arrival, from the runner's car when it goes up
  - moving ≥ 5 m/s gives a road search
  - slower gives containment
  - under a roof with an exit gives a tunnel watch
  - after a refuel, from the last known state
  - guidance overrides everything
- **Light during a road search:** the aim point is 60 m ahead plus a 15 m sweep across the road; no jump when switching modes (the 2.9.4 switch offset).
- **Weather schedule** (server):
  - the counts, times and transitions from a fixed seed
  - snow never changes
  - off when `weatherChanges` is off or on BeamNG.Earth
  - New sky re-rolls it
- **Weather on the client:**
  - clouds and fog step twice a second and the environment is locked between steps
  - time, play, date and temperature are never touched
  - rain fades over 60 s
  - grip goes wet at half and dry 60 s after
  - the wind cross-fades
  - the traffic lights follow
  - the notice texts
  - a joiner mid-change gets the in-between values
- **Helicopter and weather:**
  - grounded at the start of a change to storm or fog, with a fly-away on every game
  - arriving at the end of a change away from storm or fog
  - a full time up after each return
  - a grounding during a refuel
  - `flew()`
- **Records:** the worst weather and `weatherStart`.
- **Part C:** no behaviour change. The whole suite passes after the split, before Part A.

## In-game check
- **Tracking:** from 100 m up and 60 m to the side; whether the spot is bright enough at brightness 160; line of sight downtown.
- **Road search after a refuel, and after losing a runner at speed:**
  - it follows the road ahead
  - the light sweeps across the road
  - it doubles back to the alternative and the back route
  - it ends in containment
- **Tunnel watch:** a U-turn in a tunnel is found at the entrance after the exit's watch time.
- **Containment:** a runner stopped in a garage.
- **A weather change during a chase:**
  - the clouds and fog blend smoothly with no stepping, and no frame hitch at 2 steps a second
  - rain fades in or out, and the sound follows
  - grip changes when expected
  - the environment menu stays unavailable
  - the notice shows
- **Storm or fog arriving:** the helicopter flies away and the HUD says "GROUNDED". When it clears, the helicopter comes back.
- **A player joining mid-change** gets the same sky.

## Calls made (easy to change)
- the heights and distances in A1, brightness 160
- `SEARCH_MOVING_SPEED` 5 m/s, `SEARCH_SPEED` 45 m/s
- the route caps (2,500 / 1,500 / 1,000 m)
- the light's sweep across the road: 60 m ahead, ±15 m, 3 s
- the tunnel watch time clamp(len / max(v, 10) × 1.5, 15, 90)
- the weather change odds 40/45/15, the times, the transition weights, `CHANGE_SECONDS` 60, `DRY_SECONDS` 60, two steps a second
- snow doesn't change
- the recall at the start of a change to storm or fog, and the return at the end of a change away from them
- records keep the worst weather plus the start weather
- the first arrival uses the same mode choice as a loss, from the runner's car at that moment (the builder check asked)
- a full time up after each return from a grounding (the builder check asked)

## Left to the builder
- how the stepped blend interpolates (smoothstep) and the exact notice wording within the tone above
- how the wind blends the two gust tables
- the tunnel candidate list's return shape
