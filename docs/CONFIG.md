# Settings (`config.json`)

The server reads these from `Resources/Server/CopsAndRobbers/config.json`. Most can also be changed in the host panel's Settings tab, which saves them back to the file; see [Hosting](HOSTING.md#host-panel).

## All settings

| Setting | Default | |
|---|---|---|
| `runnerCountdownSeconds` | 3 | Countdown before the runner may drive |
| `headStartSeconds` | 7 | Cops frozen after the runner goes |
| `catchHoldSeconds` | 7 | Time the runner must be held |
| `catchRadiusMeters` | 10 | Cop distance (centre to centre) that counts as holding |
| `catchMaxSpeedKmh` | 3 | Runner speed below which they count as held |
| `resetWaitSeconds` | 7 | Stand still this long to reset anywhere; rocking in place (within 3 m) still counts |
| `stillMaxSpeedKmh` | 1 | "Standing still" threshold; it only sets where the wait starts, after that staying within 3 m counts |
| `gasStationRadiusMeters` | 25 | Gas station reset area |
| `copResetMinDistanceMeters` | 1000 | Cops this far from the runner may reset any time and get no crash penalty |
| `copSpawnMinMeters` / `copSpawnMaxMeters` | 50 / 150 | Cop start distance from the runner, by road |
| `crashSpeedLossKmh` | 50 | Speed lost within 0.5 s that counts as a crash (~2.8 G) |
| `crashPenaltySeconds` | 10 | Freeze for the cop at fault, within `copResetMinDistanceMeters` of the runner |
| `helicopter` | true | Police helicopter that searches for the runner and tracks them while it sees them. Grounded in storms, thunderstorms, fog and snow until the weather clears |
| `helicopterArrivalSeconds` | 60 | It arrives this long after the cops are released (0 = at release) |
| `helicopterUpSeconds` | 120 | How long it flies before it refuels (more than 0) |
| `helicopterRefuelSeconds` | 90 | How long it is away refuelling (0 = stays up) |
| `sightMaxMeters` | 400 | Clear-day distance in the direction the cop looks (0 = ground sight off) |
| `sightLiveIntervalSeconds` | 1 | Live runner position for all cops while one sees the runner |
| `sightNoRouteSeconds` | 5 | A cop who sees the runner within their speed × this many seconds gets no route (with the default Out of sight route setting) |
| `sightNoRouteMinMeters` | 50 | ...and always within this distance |
| `carMode` | random | `random` (a random car each round) or `evolving` (the shared build) |
| `sightGraceSeconds` | 1.5 | Sight still counts this long after a cop loses it |
| `assistMinSightPercent` | 20 | Share of the chase a cop needs sight of the runner for an assist |
| `roundTimeLimitSeconds` | 1800 | Runner escapes after 30 minutes by default. The host panel adjusts the limit in 5-minute steps (0 = no limit) |
| `excludedModels` | `[]` | Never picked |
| `explodeOnCatch` | false | Runner's car explodes when caught, for every player in the round (the AI runner in practice as a cop is deleted at once) |
| `sirensAllowed` | true | Cops may use a siren (each cop turns it on in their settings) |
| `includeModVehicles` | false | Also pick mod vehicles |
| `autoNextRound` | false | Prepare the next round automatically (panel switch) |
| `autoNextDelaySeconds` | 15 | Delay before the next round is prepared |
| `timeOfDay` | random | `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night` or `random` |
| `nightChancePercent` | 25 | Chance of night when Time of day is random |
| `dayLength` | moderate | How long a full day lasts during the chase: `off` (stopped), `fast` (15 min), `moderate` (30 min), `slow` (2 h) or `realtime` (24 h) |
| `weather` | random | `clear`, `cloudy`, `rain`, `storm`, `thunderstorm`, `fog`, `snow` or `random` |
| `badWeatherChancePercent` | 25 | Chance of picking the bad-weather group (rain, storm, thunderstorm, fog or snow) for a random start or at a planned slot with both calm and bad options |
| `lightningMinSeconds` | 5 | Shortest wait between strikes in a full thunderstorm, in whole seconds (at least 1) |
| `lightningMaxSeconds` | 20 | Longest wait between strikes. Set both intervals to the same value for a fixed cadence |
| `weatherDriving` | true | Weather changes grip and adds wind |
| `weatherChanges` | true | Planned slots during the chase can keep the current weather or pick an eligible change based on the current weather, temperature and time of day |
| `weatherChangeMinMinutes` | 3 | Shortest wait before the next planned slot, in whole minutes (at least 1). The wait starts at cop release, the previous slot or a forced change |
| `weatherChangeMaxMinutes` | 8 | Longest wait drawn from the same starting point (at least the minimum). A forced change restarts the wait, and stays can extend the time between actual changes |
| `trafficPerPlayer` | 0 | AI traffic cars around each player during a round (0 = off, at most 20) |
| `trafficRunnerOnly` | false | Only the runner's game spawns traffic (the same `trafficPerPlayer` count); cops spawn none. Fewer AI cars for better performance |
