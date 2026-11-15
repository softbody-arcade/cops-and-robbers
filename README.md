# Cops and Robbers for BeamMP

Server plugin plus auto-downloaded client mod that enforces our cops-and-robbers rules.

## Install

```
make package
```

- Copy `dist/Server/CopsAndRobbers` to the server's `Resources/Server/`.
- Copy `dist/Client/CopsAndRobbers.zip` to the server's `Resources/Client/`.
- Set `MaxCars` to at least 3 if you want to use `/cnr test` (the AI cars count as yours).

Players install nothing; BeamMP downloads the client mod on join. Every reset button works during a round and
follows the round's reset rules: Reset vehicle and Recover repair in place; Load home and Recover to last road
repair in place for the runner and move cops to the nearest road.

## Commands

| Command | |
|---|---|
| `/cnr start <name\|random\|next\|again>` | Set up a round. `next` = whoever ran least this session, `again` = same runner, `=<name>` = exactly that player |
| `/cnr reroll` | New random car during prep |
| `/cnr go` | Runner countdown, then cop head start |
| `/cnr continue` | Next step: set up a round (next runner), or start it during prep |
| `/cnr auto on\|off` | Prepare the next round automatically after each round (still needs `/cnr go`) |
| `/cnr end` | End the chase and record the runner's time |
| `/cnr stop` | Cancel the round (not recorded) and unlock everyone |
| `/cnr color <#hex\|off>` | Your car color for every round |
| `/cnr test <runner\|cop>` | Practice round against BeamNG AI (only you see it) |
| `/cnr top [cops\|all\|<map>]` | Leaderboards (default: current map) |
| `/cnr set <setting> <value>` | Change a setting (saved to config.json) |
| `/cnr config` / `/cnr reload` | Show settings / reload config.json |
| `/cnr version` | Show the mod version |
| `/cnr addstation` / `/cnr removestation` | Edit this map's gas stations |

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

## Key bindings

Options > Controls > Gameplay lists the "Cops & Robbers: ..." actions (bind them to wheel buttons): Next step
(set up / go), Start round (next / same / random runner), Go, New car, End chase, Cancel round, Automatic rounds
on/off, Leaderboard, Practice as runner / cop. They send the same commands as chat.

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
| `sightGraceSeconds` | 1.5 | Sight still counts this long after a cop loses it |
| `roundTimeLimitSeconds` | 0 | Runner escapes after this long (0 = no limit) |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Never picked |
| `explodeOnCatch` | false | Runner's car explodes when caught |
| `includeModVehicles` | false | Also pick mod vehicles |
| `autoNextRound` | false | Prepare the next round automatically (`/cnr auto`) |
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
