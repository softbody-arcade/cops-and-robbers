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
- The weather changes during a chase whenever the day allows it (worked out in advance on the server, at set intervals, only into logical neighbours for the temperature and time of day), the same for every player at the same moment. It blends over about a minute, and grip, wind, rain, sound and lights follow it.
- The helicopter is grounded when the weather turns to storm, fog or snow. It comes back when the weather clears.
- A forecast shows the next change roughly (a 2-minute window), the same for everyone, as a real crew and a real runner would check the weather.
- Everything stays deterministic across games: the server's seeds and the round clock decide; positions come from each game's copy of the runner's car, as in 2.9.4.

## Non-goals
- Syncing the helicopter's position over the network. Each game still simulates its own.
- Thunder and lightning (a separate Idea).
- A leaderboard conditions filter (a separate Idea). Records gain the start weather so the filter can use it later.
- BeamNG.Earth weather. The sky is off there, as now.
- Changing time of day or the date during a round. The temperature curve only moves on at its turning points (B2).

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
- **Weather logic:** changes only when the day allows it, worked out in advance, with no limit on their number and a set minimum and maximum time between them; snow only when the day's temperatures allow it, and in the southern hemisphere in its own winter.
- **Crossings and grip:** a temperature or fog crossing changes the weather at that moment, not at the next slot; grip changes gradually, and roads dry slower than they get wet.
- **Temperatures by day:** each game day of a round gets its own low and high, so a next day can be colder or warmer.
- **Forecast:** the next change only, with a rough 2-minute window, on the HUD and in prep. Chosen over an outlook in prep only and over an exact timeline.

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
- While the cops guide it, it circles the runner's live position, as in 2.9.4. Guidance overrides every mode, with one exception below.

**Guided while the runner is in a tunnel** (added at the user's question, 2026-11-17). A real crew told "in the tunnel, eastbound" goes to the east exit, because it can't see into a tunnel.
- **Where it goes:** while a cop sees the runner and the runner's car is under a roof, the helicopter goes to the exit ahead of the runner's current position and direction: the first candidate of the tunnel walk (A3), not the runner's live position.
- **A U-turn the cop sees:** the direction flips, the walk is redone, and the exit ahead becomes the other end, so the helicopter turns and flies there.
- **A branch the cop sees:** the walk from the runner's new position finds the exit on that branch.
- **When the walk is redone:** at most once a second, and only when the runner's closest road edge changes or their direction along it flips.
- **Roof results:** the roof check per road node is cached for the round, keyed by node id. Tunnels don't move, so a redone walk casts almost no rays.
- **Back in the open while guided:** it circles the live position again.
- **When guidance ends inside:** the timed tunnel watch (A3) starts from the runner's position and direction at that moment.
- **No exit found** (the walk's caps, or no road data): it circles the live position, as now.

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

### B1. Settings
- **`weatherChanges`:** a boolean, default true. Panel: Sky group, a "Weather changes" switch, help "The weather changes during the chase when the day allows it".
- **`weatherChangeMinMinutes`** (default 3) and **`weatherChangeMaxMinutes`** (default 8): the time between two changes, in whole minutes, at least 1. Min may not exceed max; the panel and the config clamp max up to min. Both are shown only while Weather changes is on.
- **Scope:** no effect on BeamNG.Earth (no sky).
- **Locked:** settings are locked during a round, as now.

### B2. The schedule: precalculated and logical (server, new pure module `cnr/weather.lua`)
- **Precalculated:** at `pick` (round start and New sky), when `weatherChanges` is on and the sky has a weather, the server works out every change of the round in advance. It uses a new `weatherSeed` (1..2147483646) and a seeded generator (Park–Miller, as the flight seed). New sky re-rolls it.
- **How many:** there is no fixed number. Each change comes uniform(`weatherChangeMinMinutes`, `weatherChangeMaxMinutes`) after the previous one; the first one after the cops' release. Changes are worked out up to the round's time limit, or 180 minutes without one.
- **The round clock:** times are seconds on the round clock the clients already keep (seconds since the countdown started, the same as `clockSeconds`).
- **Temperatures, day by day.** The server becomes the one source of the round's temperatures:
  - **The table:** the climate table (`LOW`, `HIGH` by month, `OFFSET` by weather; today `client/.../climate.lua`) moves to the server (`cnr/climate.lua`).
  - **Turning points:** each game day has its coldest moment at 06:00 and its warmest at 14:00. The server works out every turning point of the round in time order, from the start to the end of the schedule's horizon.
  - **Normal:** the month's `LOW` for a low, `HIGH` for a high.
  - **Day shift:** day 0 gets uniform(−4, 4) °C; each next day the previous day's shift plus uniform(−3, 3), kept within ±6 °C. Warm and cold spells last a few days, but a next day can be clearly different. A day starts at its 06:00 low.
  - **Weather offset:** a low takes the `OFFSET` of the weather in effect at the high before it (a clear evening gives a cold night, a cloudy one a milder night), and a high takes the weather at the low before it. Snow uses cloudy's offsets.
  - **The start:** the two turning points around the start use the start weather's range as now, plus day 0's shift. A snow start keeps its cold rule (its high at 0 °C or below), and its shift is never above 0.
  - **Between turning points** the server interpolates the way the game interpolates the curve override (the builder checks whether that is linear or smooth).
  - **Game time:** the server knows the game time of every moment on the round clock: the start time key's value (the game's table: sunrise 0.775, morning 0.825, noon 0, afternoon 0.175, sunset 0.245, night 0.5), minus the lead, plus the elapsed time divided by `daySeconds`. This approximates the game's solar sunrise, which moves with the date and latitude; good enough for "is it cold enough to snow".
  - **The game's curve:** the payload carries the turning points in order (their game hour and °C). The client sets the curve override to the two turning points around the current game time, at the server's hours (06:00 and 14:00, not the solar sunrise), so the game's temperature and the server's logic agree. At each turning point it moves the curve on by one point. The old and the new curve meet there, so the temperature never jumps. That is one `setState({temperatureCurveOverrideC})` with the environment unlocked only for that call.
  - **Prep label:** shows the low and the high around the start.
  - **Ranges this gives (clear, current table):** a January round about −4 to 12 °C on its first day and down to about −6 °C on later cold nights; a July round about 16 to 35 °C. The swing within a day stays at about 11 °C at most, as now.
- **Only logical changes.** At each change the next weather is drawn, with equal weights, from the neighbours the conditions allow. T is the temperature then; a day counts as warm when that day's high is 15 °C or more. Foggy conditions mean T ≤ 12 °C and the time between sunset and three hours after sunrise.

  | From | Allowed next |
  |---|---|
  | clear | cloudy; fog in foggy conditions |
  | cloudy | clear; rain if T ≥ 2 °C; snow if T ≤ 1 °C; fog in foggy conditions |
  | rain | cloudy; storm on a warm day; snow if T ≤ 1 °C (rain turning to snow) |
  | storm | rain |
  | snow | cloudy; rain if T ≥ 2 °C |
  | fog | cloudy; clear |

  - **Crossings change it at once.** The server finds the exact moment a weather stops fitting and puts a change there, between the regular slots:
    - snow becomes rain when the temperature reaches 2 °C
    - rain becomes snow when it falls to 1 °C; a storm that gets that cold becomes rain first
    - fog lifts (to cloudy or clear, equal odds) when the temperature rises above 12 °C or at 09:00, three hours after sunrise
    - such a change counts as a normal change: it blends over 60 s, the forecast shows it, and the next regular change comes min to max after it
    - a crossing that falls while a change is still blending happens when that change ends
  - **In-between temperatures:** between 1 and 2 °C both rain and snow hold.
  - **Always a neighbour:** every weather has at least one allowed neighbour, so each slot changes the weather.
- **Season and start:**
  - The date is still chosen from the start weather's window (as now), so a winter round with a snow start is cold, and a summer round never sees snow.
  - The month the server picks is the season (northern months). On a map in the southern hemisphere the client already shows the date six months on (since 2.4.0), so a local July there is winter and can snow. The server needs no latitude: it works in seasons.
  - A clear or cloudy start in winter can turn to snow only when the temperature drops to 1 °C or below: on a cold day, or late on a clear night.
- **Payload:** the sky payload gains `changes = { { at = seconds, to = weather, forecastFrom = seconds }, ... }` (possibly empty; `forecastFrom` is B8), plus `temps`, the turning points in order (game hour, °C). The base `weather` stays the start weather.
- **Server state:** the server keeps the schedule in `round.sky` and works out the current weather from its own round clock (B5, B6).

### B3. The change on the clients (client `sky.lua`, `rain.lua`, `surfaces.lua`, `wind.lua`)
- **Driver:** `sky.update` runs the schedule from `roundTime`, the clock the wind gusts already use.
- **Each change lasts `CHANGE_SECONDS = 60`:**
  - **Clouds and fog:** stepped twice a second from the old values to the new (smoothstep). Each step is an instant `setState({cloudCover, fogDensity})`, with the environment unlocked only around that one call.
  - **Never touched:** time, `play`, `dayLength` or the date. The temperature curve moves on only at its turning points (B2).
  - **Rain and snow:** `rain.target(newSpec, CHANGE_SECONDS)`. Rain ↔ storm ramps the drops and volume. The drop size and speed switch at the halfway point, not at once.
  - **Wind:** the base wind speed and the gust table cross-fade over the change. The gust cache is keyed by weather, so blend the two outputs.
- **Grip changes gradually**, the same on every game (worked out from the round clock):
  - **Getting wetter or snowier:** the surfaces blend from the values in effect to the new weather's values over the 60 s change, so full wet grip comes with full rain.
  - **Between wet kinds** (rain ↔ storm, rain ↔ snow): the same blend over the change; snow turning to rain goes from snowy to wet.
  - **Drying:** toward dry over `DRY_SECONDS = 180` from the end of the change that stopped the precipitation. Roads dry slower than they get wet, and snow clears the same way.
  - **How:** every field in the surface rules (`surfaces.lua`) is blended linearly between its dry and its target value; the multiplier rules (grass, rumble strips) scale with the blend too. It steps twice a second, on the clouds' tick, and pushes a model with `be:setGroundModel` only when its blend moved by at least 5 % of the way.
  - **Never tried before:** surfaces have only ever changed at round start. If the steps cause a stutter or a felt jolt, fall back to fewer, larger steps (5 over a change).
  - **Joiners** get the blend in effect at that moment.
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
  - "Weather: snow coming" (cloudy → snow)
  - "Weather: the rain is turning to snow" / "Weather: the snow is turning to rain"
- **The searchlight beam's strength** follows the current weather (it already reads `traffic.weather()` every frame; keep that up to date).
- **Joining or reconnecting mid-chase:** the setup payload carries the schedule and `clockSeconds`. The client applies the weather in effect at that moment. If a change is running, it uses the in-between values and runs the rest of the change from there.

### B4. Round start and New sky
Unchanged, except that the schedule is rolled with the sky. Prep shows the start weather and the forecast of the first change (B8); the rest of the schedule stays hidden.

### B5. The helicopter and the weather (server `helicopter.lua`, client `heli.lua`)
- **Grounding:**
  - When a change to storm, fog or snow starts, the helicopter is recalled: its phase becomes "grounded" with the reason (the new weather).
  - If it was up, every game flies it away first (the refuel fly-away, with the light fading) rather than dropping it.
- **Coming back:** when a change from storm, fog or snow to rain, cloudy or clear ends, a grounded helicopter becomes "arriving" with `helicopterArrivalSeconds`, then flies up as usual.
- **Rounds that start grounded:** a round that starts in storm, fog or snow starts grounded as now. It comes back when the weather turns to rain, cloudy or clear.
- **Snow** grounds it as well. Real crews avoid snow showers; this is the same rule as 2.9.0.
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
- How to Play: the helicopter, plus a line on weather changes, the forecast and grounding.
- README: the config table and the helicopter text.
- DEPENDENCIES: the environment calls, the road graph for the road search, and the stepped blend.
- The panel help.

### B8. Forecast (client `sky.lua` text, `hudfeed.lua`, the round HUD app)
- **What it shows:** only the next change, as a 2-minute window, the same on every game. It is never wrong: the change always lands inside the window.
- **The window:** each change gets `forecastFrom` = `at` − uniform(0, 120) s, drawn from the weather seed with the schedule. The window runs from `forecastFrom` for 120 s, so the change can fall anywhere in it and the middle doesn't give it away.
- **HUD line** during the chase, under the round timer, in the style of the helicopter status line:
  - before the window: "Forecast: rain in 3-5 min" (whole minutes from now; the shown range always covers the window)
  - inside the window: "Forecast: rain any minute"
  - while a change is running, and after it: the next change, or no line when there is none left
  - when the helicopter is on and the change grounds it (to storm, fog or snow): a second line "(helicopter grounded)"; when it brings it back (from those to rain, cloudy or clear): "(helicopter returns)"
- **Prep line:** the sky label gains "Forecast: rain 5-7 min after release" for the first change.
- **Hidden** when Weather changes is off, on BeamNG.Earth, or when the round has no sky weather.
- **New sky** re-rolls it with the schedule. Practice shows it the same way.

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
- **Guided in a tunnel:**
  - it goes to the exit ahead, not above the runner
  - a U-turn flips it to the other end
  - a branch moves it to that branch's exit
  - the walk is redone at most once a second, and only on an edge or direction change
  - the cached roof results keep a redone walk almost ray-free
  - back in the open, it follows the live position
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
  - changes come at intervals between the set minimum and maximum, without a count cap, up to the time limit or 180 min
  - each draw comes only from the logical neighbours: snow only at T ≤ 1 °C, rain only at T ≥ 2 °C, storm only on a warm day, fog only in foggy conditions
  - rain turns to snow when it gets cold, and snow to rain when it warms
  - a summer-season round never sees snow
  - the temperature estimate at known times
  - the turning points: 06:00 and 14:00 each day; day 0's shift within ±4, later shifts a walk of ±3 within ±6, from the seed; the weather offsets taken from the turning point before; snow with cloudy's offsets; a snow start's high at 0 °C or below
  - the interpolation between turning points matches the game's
  - the crossings: snow to rain at 2 °C, rain to snow at 1 °C, a storm to rain first, fog lifting above 12 °C or at 09:00; each counts as a change; one during a blend waits for its end
  - `temps` in the payload match the moved climate table
  - min ≤ max is enforced
  - off when `weatherChanges` is off or on BeamNG.Earth
  - New sky re-rolls it
- **Forecast:**
  - every window is 120 s, contains its change and comes from the seed (the same on every game)
  - the text before the window, inside it, during a change and with none left
  - the shown minutes always cover the window
  - the helicopter line only when the helicopter is on and the change grounds it or brings it back
  - the prep text for the first change
  - hidden when off, on Earth or with no sky weather
- **Weather on the client:**
  - clouds and fog step twice a second and the environment is locked between steps
  - time, play, date and temperature are never touched
  - rain fades over 60 s
  - grip blends over the change toward wetter or snowier, between wet kinds, and dries over 180 s after it; a model is pushed only when its blend moved 5 %
  - the temperature curve moves on only at a turning point, and the old and new curves agree there
  - the wind cross-fades
  - the traffic lights follow
  - the notice texts
  - a joiner mid-change gets the in-between values
- **Helicopter and weather:**
  - grounded at the start of a change to storm, fog or snow, with a fly-away on every game
  - arriving at the end of a change away from storm, fog or snow
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
  - grip changes gradually, with no stutter or felt steps (else the 5-step fallback)
  - the temperature curve moves on at 06:00 and 14:00 without a jump
  - the environment menu stays unavailable
  - the notice shows
  - the forecast line is readable, counts down, and the change lands inside its window
- **Storm, fog or snow arriving:** the helicopter flies away and the HUD says "GROUNDED". When it clears, the helicopter comes back.
- **A player joining mid-change** gets the same sky.

## Calls made (easy to change)
- the heights and distances in A1, brightness 160
- `SEARCH_MOVING_SPEED` 5 m/s, `SEARCH_SPEED` 45 m/s
- the route caps (2,500 / 1,500 / 1,000 m)
- the light's sweep across the road: 60 m ahead, ±15 m, 3 s
- the tunnel watch time clamp(len / max(v, 10) × 1.5, 15, 90)
- `CHANGE_SECONDS` 60, `DRY_SECONDS` 180, two steps a second, a push at 5 % of the way
- the weather logic: the thresholds 1 / 2 °C, warm day ≥ 15 °C, fog ≤ 12 °C between sunset and sunrise + 3 h; equal weights among allowed neighbours
- the crossings: at once, not at the next slot; fog lifting at 09:00 or above 12 °C, to cloudy or clear
- the temperatures by day: turning points at 06:00 and 14:00, the day shift ±4 then a walk of ±3 within ±6, the weather offsets from the turning point before, snow with cloudy's offsets
- the default interval 3 to 8 minutes; the horizon 180 minutes without a time limit
- the server's game-time estimate from the time keys' values, approximating the game's solar sunrise; the curve override at the server's hours, so the game and the server agree on the temperature
- snow grounds the helicopter, as in 2.9.0
- the forecast window 120 s, placed at random around the change; the helicopter hint lines
- the recall at the start of a change to storm, fog or snow, and the return at the end of a change away from them
- records keep the worst weather plus the start weather
- the first arrival uses the same mode choice as a loss, from the runner's car at that moment (the builder check asked)
- a full time up after each return from a grounding (the builder check asked)

## Left to the builder
- how the stepped blend interpolates (smoothstep) and the exact notice and forecast wording within the tone above
- the forecast's minute rounding, as long as the shown range covers the window
- how the wind blends the two gust tables
- the tunnel candidate list's return shape
