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
| `/cnr start <name\|random\|next\|again>` | Set up a round. `next` = whoever ran least this session, `again` = same runner |
| `/cnr reroll` | New random car during prep |
| `/cnr go` | Runner countdown, then cop head start |
| `/cnr end` | End the chase and record the runner's time |
| `/cnr stop` | Cancel the round (not recorded) and unlock everyone |
| `/cnr color <#hex\|off>` | Your car color for every round |
| `/cnr test <runner\|cop>` | Practice round against BeamNG AI (only you see it) |
| `/cnr top [cops\|all\|<map>]` | Leaderboards (default: current map) |
| `/cnr set <setting> <value>` | Change a setting (saved to config.json) |
| `/cnr config` / `/cnr reload` | Show settings / reload config.json |
| `/cnr addstation` / `/cnr removestation` | Edit this map's gas stations |

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
| `roundTimeLimitSeconds` | 0 | Runner escapes after this long (0 = no limit) |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Never picked |
| `explodeOnCatch` | false | Runner's car explodes when caught |
| `includeModVehicles` | false | Also pick mod vehicles |

## BeamNG.Earth

On `beamng_earth` the mod switches to geo mode automatically: positions are exchanged as latitude/longitude through
BeamNG.Earth's mod API (each player has their own coordinate origin there), and real gas stations near players are
looked up and remembered by the server as they drive. Players need a BeamNG.Earth version with API v1.

## Development

`make test` runs the rule and wiring tests with stock Lua. `make install-local` deploys to `.testserver/`.
