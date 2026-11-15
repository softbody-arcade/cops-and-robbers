# Cop line of sight: live sharing and no route up close (short design)

## Intent
Cops should be able to see the runner, not just ping where he was. While any cop has eyes on the runner, every cop gets his position live. A cop who is right on him (sees him and is close for his speed) gets no route and chases by eye. Sight-based scoring comes later with player stats (it's in the TODO). The user approved this proposal: "go ahead".

## Behaviour
- **Sight check (in each human cop's game, 4×/s, only while the chase is running):**
  - Rays go from about eye height (cop car position + 1.2 m) to the runner car's roof, front and rear (1 m up, ±2 m along its direction), using `castRayStatic`.
  - The runner is seen if any ray reaches him and he is within `sightMaxMeters` (400).
  - There is no field-of-view limit, because mirrors count.
  - The game reports to the server only when this changes, plus a keep-alive every 5 s.
  - It logs each change with the distance, so BeamNG.Earth's buildings can be checked.
- **Who counts as the runner:** for a human runner, the car whose BeamMP id belongs to the runner's player id. In a practice round as a cop, the AI runner car.
- **In sight (server):** the runner is in sight while any cop reports seeing him. A cop who loses sight still counts for `sightGraceSeconds` (1.5) so it doesn't flicker.
- **Live sharing:** while he's in sight, all human cops get the runner's position every `sightLiveIntervalSeconds` (1). On BeamNG.Earth it's at least every 3 s, because its GPS re-plans each time. The regular 30 s ping is suppressed meanwhile.
- **Lost sight:** one immediate "last seen" ping goes out at the runner's position at that moment. After that the regular pings run every `lastSeenIntervalSeconds`.
- **No route up close:** a cop who sees the runner and is within `max(sightNoRouteMinMeters, own speed × sightNoRouteSeconds)` (50 m, 5 s) gets no route. His status line shows "IN SIGHT". Other cops get the route and "Runner 640 m NE · live" (on BeamNG.Earth, "Runner 2.4 km by road NE · live").
- **Runner:** the status line shows "SPOTTED" or "HIDDEN" in front of "Nearest cop …". The nearest-cop distance is also updated with each live update.
- **Off switch:** `sightMaxMeters = 0` turns the feature off, which gives the old behaviour.
- **Settings:** all five appear in the panel under Cops: sight range, live update interval, no-route seconds, no-route minimum and grace.

## Changes
- **Server:**
  - A new pure module `cnr/sight.lua` holds the reports, the grace, the no-route rule and the "in sight" state.
  - `round.lua` keeps a sight state, gets `sightReport(pid, seen, now)`, and emits `live` and lost-sight `lastSeen` effects from `tick`.
  - In `main.lua`: a new event `cnr_sight {seen}`, which is accepted only from cops in a running round. The `live` effect is sent as `cnr_lastSeen {live=true, route=bool, ...}`. The runner gets `cnr_spotted {spotted}`. The geo interval is at least 3 s.
  - `roundSetup` carries `sightMaxMeters`.
  - The five config keys come with defaults.
- **Client:**
  - A new module `copsAndRobbers/sight.lua` has the pure ray plan and the change and keep-alive logic, with the ray caster injected.
  - The main file runs it in `onUpdate` for cops and handles `live`, `route` and `cnr_spotted`.
- **Panel:** the five settings are added to the Cops group.
- **Version:** 1.7.0.

## Approaches
- **Sight checked in each cop's game (chosen):** only the game has world geometry, through `castRayStatic`. The server only knows positions.
- **Server-side distance only:** this can't tell that a building or hill is in the way. Rejected.

## Left to the builder
- Exact ray points and eye height.
- The HUD wording beyond what's listed above.
- Whether the HUD styles "IN SIGHT" differently.
