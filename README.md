# Cops and Robbers for BeamMP

Server plugin plus auto-downloaded client mod that enforces our cops-and-robbers rules.

## Install

```
make package
```

- Copy `dist/Server/CopsAndRobbers` to the server's `Resources/Server/`.
- Copy `dist/Client/CopsAndRobbers.zip` to the server's `Resources/Client/`.
- Set `MaxCars` to at least 3 if you want to use practice rounds (the AI cars count as yours).
- Traffic counts too: every player needs room for their round car plus `trafficPerPlayer` traffic cars, so `MaxCars` of at
  least 1 + traffic per player (3 + traffic per player for practice rounds). With less room the mod spawns fewer traffic
  cars and the panel says so.

Players install nothing; BeamMP downloads the client mod on join. Every reset button works during a round and
follows the round's reset rules: Reset vehicle and Recover repair in place; Load home and Recover to last road
repair in place for the runner and move cops to the nearest road.

## The apps

The mod talks to players only through five apps. It sends no chat messages or pop-ups, and has no chat commands. Everything is clickable with the mouse cursor shown.

| App | How it opens |
|---|---|
| **Cops and Robbers Announcements** | Added automatically on join. Role title, countdowns, GO and the result after a round. |
| **Cops and Robbers HUD** | Added automatically on join. Lobby card between rounds, prep line, chase line and catch bar, notices. |
| **Cops and Robbers How to play** | The How to play button on the lobby card or the prep line. It also opens by itself the first time a player joins. |
| **Cops and Robbers Panel** | The Host panel button on the lobby card or the prep line, or Esc > UI Apps. |
| **Cops and Robbers Leaderboard** | The Leaderboard button on the lobby card, or Esc > UI Apps. |

Announcements and the HUD can be moved and resized in the layout editor; if removed, they come back by themselves. Every app is removed from the layout again on leaving the server. The Panel and the Leaderboard show a ✕ to close them, and the Leaderboard and How to play hide themselves during a round.

## Evolving car mode

Switch "Evolving car" on in the panel. Instead of a random car each round, everyone drives one shared **build**:

- Start a build from a random car or one you pick (vanilla configs and base cars from mods the server hands out).
- In each round's prep, only the runner may change **one thing** (an engine swap, one performance stage, one
  axle of wheels, plus whatever a swap needs to work). Everyone sees the queued change live in their HUD and keeps
  each other honest.
- The runner presses **Apply change** on the change card in the HUD (not the panel) to lock it in: every car is rebuilt with it (the screen shows APPLYING CHANGES until everyone has
  loaded, at most 20 s), then GO. Parts someone doesn't have are flagged in the HUD.
- The build is saved after every change and continues next session until "Reset build" (backups are kept in
  `data/build-<time>.json`). Practice rounds use the build but never change it.

## HUD

- **Lobby card** (between rounds): who is online, a line saying whether a round is waiting, buttons for Colour, How to play, Leaderboard and Host panel, and a yellow line for a standing problem (no reset button bound, an outdated copy, BeamNG.Earth too old).
- **Colour:** the Colour button opens a colour picker with a hex field, "No colour" and Done. The colour is used for every round car, repaints at once in prep and otherwise applies from the next round.
- **Prep:** the centre shows your role ("YOU'RE THE RUNNER" or "YOU'RE A COP", and for cops the runner's name). The bottom shows "Waiting for the host to press GO" with the Colour, How to play and Host panel buttons. In evolving mode it shows the runner's queued change instead, with Apply change for the runner.
- **Countdowns:** "RUNNER STARTS IN", "COPS RELEASED IN" and "CRASH PENALTY", then "GO!" or "PENALTY OVER".
- **Chase:** role, time (with the time limit when there is one), SPOTTED or HIDDEN for the runner, IN SIGHT or live and last-seen positions for cops, the distance, and the reset status. A catch bar shows while the catch timer runs: red "BEING CAUGHT" for the runner, blue "HOLDING RUNNER" for cops.
- **Notices:** rule breaks (illegal resets, teleports, parts changes, crash penalties), build changes and personal warnings appear as short lines above the chase line or the lobby card, at most two at a time.
- **Result:** the title, the runner's time and who caught them, the map's top 3 and "Next round in N" with automatic rounds.

## How to play

A five-tab card (Basics, Runner, Cop, Resets, Rules) that reads its numbers from the server's current settings, so it always matches the round (for example "no time limit" or "sight is off").

## Host panel

"Cops and Robbers Panel" has four tabs:

- **Round:** shows only what can be done now. The player list is the runner picker (the player with the fewest runs is preselected). One main button does the next step: Start round, then GO, with a yellow line saying why it can't yet. Practice as runner and as cop, New car, Cancel round, and the Automatic rounds switch. During a round the panel folds into a bar with the time, End chase and Cancel (a second click is needed during the chase). It opens again when the round ends.
- **Car:** Random car or Evolving build, the build summary, New build (choose a car or random) and Reset build, mod cars and excluded cars.
- **Map:** gas stations of this map, Add station here and Remove nearest.
- **Settings:** the common settings first, the rest under More settings, each with a one-line explanation. Changes save by themselves; a value that differs from the default is orange and has its own reset. Settings are locked during a round. "Reload config.json" picks up hand edits.

## Leaderboard

"Cops and Robbers Leaderboard" has the look of the game's multiplayer scoreboard and four tabs: **Runners** (best survival times), **Cops** (catches, assists, fastest catch), **Players** (stats per player) and **Rounds** (every recorded round, newest first, with a timeline of what happened and each cop's share of sight). Filter by map, car mode and traffic. It refreshes after every round. The leaderboard started fresh in 1.7.0; the old file is kept as `data/leaderboard-1.6.json`.

## Settings (`config.json`)

| Setting | Default | |
|---|---|---|
| `runnerCountdownSeconds` | 3 | Countdown before the runner may drive |
| `headStartSeconds` | 7 | Cops frozen after the runner goes |
| `catchHoldSeconds` | 7 | Time the runner must be held |
| `catchRadiusMeters` | 10 | Cop distance (centre to centre) that counts as holding |
| `catchMaxSpeedKmh` | 3 | Runner speed below which they count as held |
| `resetWaitSeconds` | 7 | Stand still this long to reset anywhere |
| `stillMaxSpeedKmh` | 1 | "Standing still" threshold |
| `gasStationRadiusMeters` | 25 | Gas station reset area |
| `copResetMinDistanceMeters` | 1000 | Cops this far from the runner may reset any time |
| `copSpawnMinMeters` / `copSpawnMaxMeters` | 50 / 150 | Cop placement around the runner |
| `crashSpeedLossKmh` | 50 | Speed lost within 0.5 s that counts as a crash (~2.8 G) |
| `crashPenaltySeconds` | 10 | Freeze for the cop at fault |
| `lastSeenIntervalSeconds` | 30 | Runner location ping for cops (0 = off) |
| `sightMaxMeters` | 400 | How far cops can see the runner (0 = sight off) |
| `sightLiveIntervalSeconds` | 1 | Live runner position for all cops while one sees the runner (at least 3 s on BeamNG.Earth) |
| `sightNoRouteSeconds` | 5 | A cop who sees the runner within their speed × this many seconds gets no route |
| `sightNoRouteMinMeters` | 50 | ...and always within this distance |
| `carMode` | random | `random` (a random car each round) or `evolving` (the shared build) |
| `sightGraceSeconds` | 1.5 | Sight still counts this long after a cop loses it |
| `assistMinSightPercent` | 20 | Share of the chase a cop needs sight of the runner for an assist |
| `roundTimeLimitSeconds` | 0 | Runner escapes after this long (0 = no limit) |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Never picked |
| `explodeOnCatch` | false | Runner's car explodes when caught |
| `includeModVehicles` | false | Also pick mod vehicles |
| `autoNextRound` | false | Prepare the next round automatically (panel switch) |
| `autoNextDelaySeconds` | 15 | Delay before the next round is prepared |
| `timeOfDay` | map | `map` (the map's own), `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night` or `random` |
| `nightChancePercent` | 25 | Chance of night when Time of day is random |
| `clockSpeed` | 0 | Speed of the sky clock during a round: 0 stopped, 1 real time, a whole number up to 120 |
| `weather` | map | `map` (the map's own), `clear`, `cloudy`, `rain`, `storm`, `fog`, `snow` or `random` |
| `badWeatherChancePercent` | 25 | Chance of rain, storm, fog or snow when Weather is random |
| `weatherDriving` | true | Weather changes grip and adds wind (not on BeamNG.Earth) |
| `trafficPerPlayer` | 5 | AI traffic cars around each player during a round (0 = off; normal maps only, not on BeamNG.Earth yet) |

## Traffic

During a round every player's game runs a few AI traffic cars around itself (`trafficPerPlayer`, 5 by default, 0 turns it
off). They spawn in prep, stand still until GO, and are removed when the round ends. There are no police or emergency
vehicles among them, and they have no name tags, so every car with lights is a cop and every name tag is a player. A
cop who drives into a traffic car gets the crash penalty ("crash penalty 10s (traffic)"); one who gets hit by traffic
doesn't. In rain, storm, fog and snow rounds traffic drives with its headlights on; at night it follows the game's own
lights. Traffic is off on BeamNG.Earth for now.

Every player's game simulates everyone's traffic. If that gets heavy, BeamMP's "Simplify remote vehicles" option makes
other players' cars, traffic included, lighter to run.

## Players and cops

Players are recognised by their BeamMP account (leaderboard, colors, who runs next); guests by name, which
changes every session. Cops get a light bar with lights on (no siren): when the round car has none, the light bar
parts of a police config of the same model are added for cops.

## BeamNG.Earth

On `beamng_earth` the mod switches to geo mode automatically: positions are exchanged as latitude/longitude through
BeamNG.Earth's mod API (each player has their own coordinate origin there), and real gas stations near players are
looked up and remembered by the server as they drive. Players need a BeamNG.Earth version with API v1.

## Development

See `docs/DEPENDENCIES.md` for everything the mod depends on and what to check when BeamMP, BeamNG or BeamNG.Earth updates.

App preview images are drawn from `tools/previews/*.svg`: `rsvg-convert -w 1000 -h 560 -o client/ui/modules/apps/<App>/app.png tools/previews/<name>.svg`.

`make test` runs the rule, wiring and client tests with stock Lua (`tests/test_client.lua` loads the real GE
extension against stubbed game functions). `make install-local` deploys to `.testserver/`, `make deploy` to the server.

Client layout (`client/lua/ge/extensions/`): `copsAndRobbers.lua` holds round state, the server event handlers and the
`onUpdate` steps; `copsAndRobbers/` has `game` (GE helpers), `inputs` (locks, reset hooks), `roads` (spawn spots),
`vehicles` (car pick, cop lights), `lightbar` (emergency light planner), `ai` (practice cars), `geo` (BeamNG.Earth),
`hud` (HUD model), `hudfeed` (HUD state and push), `apps` (opening and closing the apps) and `placement` (layout handling).
