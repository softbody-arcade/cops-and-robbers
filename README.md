# Cops and Robbers for BeamMP

Server plugin plus auto-downloaded client mod that enforces our cops-and-robbers rules.

## Install

```
make package
```

- Copy `dist/Server/CopsAndRobbers` to the server's `Resources/Server/`.
- Copy `dist/Client/CopsAndRobbers.zip` to the server's `Resources/Client/`.
- Set `MaxCars` to at least 3 if you want to use practice rounds (the AI cars count as yours; watching the AI practise also takes 3, your own car is parked).
- Traffic counts too: every player needs room for their round car plus `trafficPerPlayer` traffic cars, so `MaxCars` of at
  least 1 + traffic per player (3 + traffic per player for practice rounds). With less room the mod spawns fewer traffic
  cars and the panel says so.

Start or restart BeamMP after copying the files. Check the server log for `Cops and Robbers <version> loaded` and
check for Lua errors. BeamMP downloads the client mod when players join. During rounds, Reset vehicle and Recover
repair in place. Load home and Recover to last road repair the runner in place and move cops to the nearest road.

### Upgrade an existing server

Overlay the packaged client ZIP and server plugin files. Keep the server's existing `config.json` and `data/`
inside `Resources/Server/CopsAndRobbers/`. For a local upgrade with `make install-local`, copy the installed
`config.json` to `server/CopsAndRobbers/config.json` in a disposable checkout before running the target, so the
package includes the local settings.

## The apps

The mod talks to players only through five apps. It sends no chat messages or pop-ups, and has no chat commands. Everything is clickable with the mouse.

| App | How it opens |
|---|---|
| **Cops and Robbers Announcements** | Added automatically on join. Role title, countdowns, GO and the result after a round. |
| **Cops and Robbers HUD** | Added automatically on join. Lobby card between rounds, prep line, chase line and catch bar, the spectating card, notices. |
| **Cops and Robbers How to play** | The How to play button on the lobby card or the prep line. It also opens by itself the first time a player joins. |
| **Cops and Robbers Panel** | The Host panel button on the lobby card or the prep line, or Esc > UI Apps. |
| **Cops and Robbers Leaderboard** | The Leaderboard button on the lobby card, or Esc > UI Apps. |

Announcements and the HUD can be moved and resized in the layout editor; if removed, they come back by themselves. To put the HUD away between rounds, use Hide on the lobby card. Leaving the server removes the apps the mod placed. Apps you add yourself in the layout editor stay, including ones you removed and then added back. The Panel and the Leaderboard show a ✕ to close them, and the Leaderboard and How to play hide themselves during a round you play in.

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

- **Lobby card** (between rounds): who is online, a line saying whether a round is waiting, buttons for Settings, How to play, Leaderboard, Host panel, Sit out and Hide, and a yellow line for a standing problem (a missing reset binding or outdated client mod).
- **Sit out:** keeps you out of rounds until you press it again (it then reads Play). You're never the runner, and when a round is set up your car leaves the map and comes back where it stood when the round ends. It lasts until you leave the server. Pressed during a round, it counts from the next one. Start only refuses when everyone sits out. Practice still works: with Sit out on, the panel's **Practice: watch the AI** runs an AI runner against two AI cops and you spectate them.
- **Spectating:** a player who sits out, or who joins while a round is running, watches instead of playing. The card shows "SPECTATING · Bob" (or "free camera"), the round clock and the helicopter, with Sit out (or Play), How to play, Leaderboard, Host panel and Settings. The game's own switch-car keys (Tab and Ctrl+Tab by default) go through the players' cars, the runner's too, and free camera (Shift+C by default) works. Spectators don't drive, can't spawn a car and count for nothing in the round. After the round they're back in the lobby and play the next one unless they sit out.
- **Hide:** folds the lobby card into a small "Cops and Robbers" tab at the same place; click the tab to bring the card back. The yellow warning lines still show above the tab. Your choice is saved in your own game. Your rounds always show the full HUD, and the lobby after them goes back to your choice.
- **Player settings.** The Settings button is available in the lobby, during prep, while chasing and while spectating. It opens a card with your car colour, six switches and a choice. **Auto headlights** (on by default) switches your low beam on at night and in rain, storms, thunderstorms, fog and snow. The lights go off again at sunrise in clear weather. The mod only acts when the conditions change, so your own light key still works. **Siren** (off by default) adds sound to a cop's light bar after release if the host allows Cop sirens. Turning off **Searchlight beam** (on by default) hides the beam in the air to help the frame rate while keeping its light and glare. Turning off **Helicopter sound** (on by default) fades out the rotor on your game. Turning off **Helicopter model** (on by default) hides the helicopter's body and aviation lights. The body is a flying Ibishu Pigeon van in its Bird Response livery, made once from your own game's Pigeon. Turning off **Lightning flashes** (on by default) hides flashes and bolts while thunder still plays. Cops can set **Route to the runner** to Always, Out of sight (default) or Never. These settings are saved in your own game and apply on every server. The chase line and How to play follow your game's distance and speed units. The Host panel uses metric units.
- **Colour:** a colour picker with a hex field, "No colour" and Done. The colour is used for every round car, repaints at once in prep and otherwise applies from the next round.
- **Prep:** the centre shows your role ("YOU'RE THE RUNNER" or "YOU'RE A COP", and for cops the runner's name). The bottom shows "Waiting for the host to press GO" with the Settings, How to play and Host panel buttons. In evolving mode it shows the runner's queued change instead, with Apply change for the runner.
- **Countdowns:** "RUNNER STARTS IN", "COPS RELEASED IN" and "CRASH PENALTY", then "GO!" or "PENALTY OVER".
- **Chase:** role, time (with the time limit when there is one), SPOTTED or HIDDEN for the runner, IN SIGHT or live and last-seen positions for cops (with how long ago a last-seen point was), the distance, and the reset status. A catch bar shows while the catch timer runs: red "BEING CAUGHT" for the runner, blue "HOLDING RUNNER" for cops.
- **Notices:** rule breaks (illegal resets, teleports, parts changes, crash penalties), build changes and personal warnings appear as short lines above the chase line or the lobby card (or its tab), at most two at a time.
- **Result:** the title, the runner's time and who caught them, the map's top 3 and "Next round in N" with automatic rounds.

## How to play

A five-tab card (Basics, Runner, Cop, Resets, Rules) that reads its numbers from the server's current settings, so it always matches the round (for example "no time limit" or "sight is off").

## Host panel

"Cops and Robbers Panel" has four tabs:

- **Round:** shows only what can be done now. The player list is the runner picker (the planned next runner is preselected: drawn at random among the players with the fewest runs, never the previous runner twice in a row). One main button does the next step: Start round, then GO, with a yellow line saying why it can't yet. Practice as runner and as cop (one "Practice: watch the AI" button while you sit out), New car, Cancel round, and the Automatic rounds switch. During a round the panel folds into a bar with the time, End chase and Cancel (a second click is needed during the chase). It opens again when the round ends.
- **Car:** Random car or Evolving build, the build summary, New build (choose a car or random) and Reset build, mod cars and excluded cars.
- **Map:** gas stations of this map, Add station here and Remove nearest.
- **Settings:** the common settings first, the rest under More settings, each with a one-line explanation. Changes save by themselves; a value that differs from the default is orange and has its own reset. Settings are locked during a round. "Reload config.json" picks up hand edits.

For a five-second lightning test, choose **Night** and **Thunderstorm** in the Sky settings. Under **More settings → Sky**, turn **Weather changes** off and set **Minimum strike interval** and **Maximum strike interval** to **5 s**. Turn **Lightning flashes** on in your player settings, then start a round and press **GO**. The first strike comes five seconds after the runner countdown starts, with another every five seconds. Watch the flashes outdoors. Thunder takes longer to arrive from distant strikes.

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
| `sightMaxMeters` | 400 | How far cops can see the runner (0 = sight off) |
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

## Traffic

Traffic is off by default. Set `trafficPerPlayer` above zero to spawn that many AI cars around each player during a round.
With **Traffic for the runner only** (`trafficRunnerOnly`), the runner's game spawns the traffic for better performance.
Practice rounds keep their traffic either way, except a practice you only watch (Sit out on), which has none. They spawn in prep, stand still until GO, and are removed when the round ends. There are no police or emergency
vehicles among them, and they have no name tags, so every car with lights is a cop and every name tag is a player. A
cop who drives into a traffic car gets the crash penalty ("crash penalty 10s (traffic)"), as with any crash only within
`copResetMinDistanceMeters` of the runner; one who gets hit by traffic doesn't. Traffic headlights follow the weather and switch on in rain, storms, thunderstorms, fog and snow. At night they follow the game's own lights.

Every player's game simulates everyone's traffic. If that gets heavy, BeamMP's "Simplify remote vehicles" option makes
other players' cars, traffic included, lighter to run.

## Players and cops

Players are recognised by their BeamMP account (leaderboard, colors, who runs next); guests by name, which
changes every session. Cops get a light bar with lights on (no siren unless the cop turns it on in Settings and the host allows Cop sirens): when the round car has none, the light bar
parts of a police config of the same model are added for cops.

## Credits

The helicopter's rotor sound is "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0
(shipped as a mono OGG in `client/art/sound/cnr/heli_rotor.ogg`, made louder by +6 dB with a limiter).

The thunder clips use three CC0 originals. To recreate the shipped clips, use [tools/thunder/cut.sh](tools/thunder/cut.sh).

- [sfx_thunder blast.wav by bajko](https://freesound.org/people/bajko/sounds/399656/)
- [Distant Thunder Clap_Gentle.wav by mikala_oidua](https://freesound.org/people/mikala_oidua/sounds/347562/)
- [230405 Thunder DRY rolling distant low rumbles, roof, EM272s, Toronto 7am by TRP](https://freesound.org/people/TRP/sounds/717845/)

## Development

See the compatibility checks for BeamMP and BeamNG.drive updates. [Dependencies](docs/DEPENDENCIES.md)

Run `python3 tools/previews/generate.py` to rebuild the app picker thumbnails from the mod logo and the names in each app's `app.json`. The generator uses Pillow and the DejaVu Sans Bold font.

`make test` runs the rule, wiring and client tests with stock Lua (`tests/test_client.lua` loads the real GE
extension against stubbed game functions). `make install-local` installs to `.testserver/` by default. Set `TESTSERVER`
to choose a different local BeamMP server directory.

The version lives in four places (server `main.lua`, client `copsAndRobbers.lua`, `mod_info/.../info.json`, the
`docs/FEATURES.md` heading); `tests/test_version.lua` checks they agree and the other tests read it from the server.
Feature branches never change it, so branches built side by side don't conflict: after a branch merges, run
`make version V=x.y.z` on main and commit the bump on its own. The target refuses on any other branch.

Client layout (`client/lua/ge/extensions/`): `copsAndRobbers.lua` holds round state, the server event handlers and the
`onUpdate` steps; `copsAndRobbers/` has `game` (GE helpers), `inputs` (locks, reset hooks), `roads` (spawn spots),
`vehicles` (car pick, cop lights), `lightbar` (emergency light planner), `ai` (practice cars),
`hud` (HUD model), `hudfeed` (HUD state and push), `apps` (opening and closing the apps) and `placement` (layout handling).

## Host-configured deployment

Set `CNR_DEPLOY_SCRIPT` to the path of a host-provided executable when running `make deploy`.

```sh
CNR_DEPLOY_SCRIPT=/path/to/deploy-cnr make deploy
```

The target builds the package and passes two absolute paths to the executable, in order.

1. The packaged client ZIP, `dist/Client/CopsAndRobbers.zip`.
2. The packaged server plugin directory, `dist/Server/CopsAndRobbers/`.

The host's executable handles the destination, preserves installed `config.json` and `data/`, restarts the server
and checks the server log for the expected `Cops and Robbers <version> loaded` line and any Lua errors.
`make deploy` fails if the executable is missing or exits with an error. `make package` and `make install-local`
work independently of the deployment hook.
