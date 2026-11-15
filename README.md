# Cops and Robbers for BeamMP

Server plugin plus auto-downloaded client mod that enforces our cops-and-robbers rules.

## Install

```
make package
```

- Copy `dist/Server/CopsAndRobbers` to the server's `Resources/Server/`.
- Copy `dist/Client/CopsAndRobbers.zip` to the server's `Resources/Client/`.
- Set `MaxCars` to at least 3 if you want to use practice rounds (the AI cars count as yours).

Players install nothing; BeamMP downloads the client mod on join. Every reset button works during a round and
follows the round's reset rules: Reset vehicle and Recover repair in place; Load home and Recover to last road
repair in place for the runner and move cops to the nearest road.

## Controls

Everything runs through two apps (Esc > UI Apps):

- **Cops and Robbers Panel** (for whoever runs the game): start rounds (runner: next, same, random or a player), GO,
  End chase, Cancel, automatic rounds, practice rounds, the evolving car build and Apply, and every setting
  (saved automatically; "Reload config.json" picks up hand edits).
- **Cops and Robbers Leaderboard** (anyone): best times, top cops and player stats.

Only five chat commands remain:

| Command | |
|---|---|
| `/cnr color <#hex\|off>` | Your car color for every round (the only way to paint: the game's paint menu is closed in rounds) |
| `/cnr addstation` / `/cnr removestation` | Edit this map's gas stations |
| `/cnr help` / `/cnr version` | Help / mod version |

## Evolving car mode

Switch "Evolving car" on in the panel. Instead of a random car each round, everyone drives one shared **build**:

- Start a build from a random car or one you pick (vanilla configs and base cars from mods the server hands out).
- In each round's prep, only the runner may change **one thing** (an engine swap, one performance stage, one
  axle of wheels, plus whatever a swap needs to work). Everyone sees the queued change live in their HUD and keeps
  each other honest.
- **Apply change** locks it in: every car is rebuilt with it (the HUD shows APPLYING CHANGES until everyone has
  loaded, at most 20 s), then GO. Parts someone doesn't have are flagged in the HUD.
- The build is saved after every change and continues next session until "Reset build" (backups are kept in
  `data/build-<time>.json`). Practice rounds use the build but never change it.

## HUD

On join the "Cops and Robbers HUD" app is added automatically to the player's current UI layout, at bottom centre
(movable and resizable like any app), and removed again on leaving the server. During the chase it shows the status
line (role, time, reset status, distance info) and a catch bar (red "BEING CAUGHT" for the runner, blue "HOLDING
RUNNER" for cops) in 1% steps, plus countdowns, GO flashes, the prep line, short event lines and a result card
(with the map's top 3) after each round. When the app is not in the current layout, the old pop-up messages are shown
instead.

## Control panel

"Cops and Robbers Panel" is a clickable app for whoever runs the game. It is not placed automatically: add it yourself
via Esc > UI Apps. The Round tab shows the phase, map and players, and has Start round (runner: next, same as last,
random or a player), New car, GO, End chase, Cancel, an Automatic rounds switch and practice rounds. Buttons are only
enabled when they would do something. The Settings tab lists every setting with -/+ steppers, switches and a text field
for excluded cars; changes save automatically half a second after the last click. Settings are locked during a round.
"Reset to default" needs a second click. The ▾ button collapses the panel to a one-line status; it collapses by itself
on GO and opens again when the round ends.

## Leaderboard app

"Cops and Robbers Leaderboard" (Esc > UI Apps) shows each player's best survival time, the top cops by catches,
and per-player stats (runs, best and average, escapes, catches, assists, time hidden from cops, times they lost the
cops), filtered by map. It refreshes after every round. The leaderboard started fresh in 1.7.0; the old file is kept
as `data/leaderboard-1.6.json`.

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
| `sightLiveIntervalSeconds` | 1 | Live runner position for all cops while one sees him (at least 3 s on BeamNG.Earth) |
| `sightNoRouteSeconds` | 5 | A cop who sees the runner within his speed × this many seconds gets no route |
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

## Players and cops

Players are recognised by their BeamMP account (leaderboard, colors, `start next/again`); guests by name, which
changes every session. Cops get a light bar with lights on (no siren): when the round car has none, the light bar
parts of a police config of the same model are added for cops.

## BeamNG.Earth

On `beamng_earth` the mod switches to geo mode automatically: positions are exchanged as latitude/longitude through
BeamNG.Earth's mod API (each player has their own coordinate origin there), and real gas stations near players are
looked up and remembered by the server as they drive. Players need a BeamNG.Earth version with API v1.

## Development

See `docs/DEPENDENCIES.md` for everything the mod depends on and what to check when BeamMP, BeamNG or BeamNG.Earth updates.

`make test` runs the rule, wiring and client tests with stock Lua (`tests/test_client.lua` loads the real GE
extension against stubbed game functions). `make install-local` deploys to `.testserver/`, `make deploy` to the server.

Client layout (`client/lua/ge/extensions/`): `copsAndRobbers.lua` holds round state, the server event handlers and the
`onUpdate` steps; `copsAndRobbers/` has `game` (GE helpers), `inputs` (locks, reset hooks), `roads` (spawn spots),
`vehicles` (car pick, cop lights), `lightbar` (emergency light planner), `ai` (practice cars), `geo` (BeamNG.Earth),
`hud` (HUD model), `hudfeed` (HUD state and push) and `placement` (layout handling).
