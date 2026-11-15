# Cops and Robbers 2.0.2: features

A BeamMP server plugin with a client mod that BeamMP downloads automatically. The mod enforces the group's cops-and-robbers rules. It is one mod for every map, and it switches to geo mode on BeamNG.Earth by itself.

## Round flow

All round controls are in the Cops and Robbers Panel (Esc > UI Apps).

| Step | What happens |
|---|---|
| Start round | Picks a random car and config (or the evolving build). Everyone gets the same one. Cops are placed on a road 50–150 m from the runner. Everyone is frozen. |
| Prep | No time limit. Colors come from `/cnr color` only: the game's parts and paint menu is closed for everyone (except the runner in evolving mode, for his one change). Parts changes during the round are logged (with the slots that changed) but not undone yet. New car picks another car (random mode). |
| Apply change (evolving only) | Locks in the runner's change and rebuilds every car; the HUD shows APPLYING CHANGES until everyone has loaded (at most 20 s). |
| GO | "Runner starts in 3", then the runner is released. |
| Head start | Cops stay frozen for 7 s and see a countdown. |
| Chase | Cops are released and the survival clock starts. A status line shows `time \| reset status \| distance info`. |
| End | The round ends when the runner is caught, on End chase, when the time limit runs out, or when the runner disconnects. The run is recorded and the top 5 for the map is shown. |
| Automatic next round | Optional (panel switch). The next round is prepared with whoever has run least. It still waits for GO. |

### Choosing the runner
- The panel's runner list: Next (whoever has run least this session), Same as last, Random, or any player by name (sent as an exact name, so names like "next" work).

## Evolving car mode

- **The build:** one shared car (model, parts and tuning) instead of a random car each round. Switch "Evolving car" on in the panel. Start a build from a random car or a chosen one: vanilla configs and base cars from mods the server distributes only, never a player's own saved car, so everyone can spawn it.
- **One change per round:** during prep only the runner can change parts and tuning (from any menu). The group's rule: one change that works on its own (an engine swap, one performance stage, wheels one axle at a time, plus whatever a swap needs). The mod doesn't enforce it: everyone sees the queued change live in the HUD: "BOB'S CHANGE (1)", "Engine 2.0L I4 → 3.0L I6, + 12 parts come with it" (parts that come with a swap are grouped under it, names from the game), and tuning values that really changed (within half a step) and keeps each other honest.
- **Apply change:** the runner's exact setup becomes the build (liveries are paint and stay out), every car is rebuilt in place (cops keep their emergency lights), and the HUD shows APPLYING CHANGES until everyone's car has loaded (at most 20 s). GO only works after that. Each game checks it has every part and the HUD warns "⚠ Ann is missing: …" if not.
- **Record:** chat logs each change ("Change 7 by Bob: Engine 4.5L V8 → 6.0L V8"). The build is saved after every change in `data/build.json` and continues next session until "Reset build"; resetting or starting a new build keeps a backup (`data/build-<time>.json`). Practice rounds use the build but never change it.
- **Leaderboard:** runs record the mode and build step, and the leaderboard app filters by mode (all, random, evolving).

## Rules enforced

### Catching
- The runner is caught after being held for 7 s: runner under 3 km/h with a cop within 10 m (centre to centre).
- The hold timer drains at twice the speed it fills, so one jolt does not wipe the progress.
- Cops serving a crash penalty do not count toward a catch.
- No catch is possible during the head start.
- Cops within the radius at the catch get the credit ("caught by Bob, Ann").

### Resets
- **When a reset is allowed:**
  - at a gas station, when standing still
  - after standing still for 7 s anywhere
  - for a cop who is 1 km or more from the runner, at any time
- **When a reset is not allowed:**
  - for the runner while the catch timer is running
  - during a crash penalty
  - during prep, countdown and head start (for frozen players)
- **All reset buttons work.** Each one goes through these rules, so players can keep their own wheel button:

| Button | Runner | Cop |
|---|---|---|
| Reset vehicle | Repair in place, upright | Repair in place, upright |
| Recover / rewind (both) | Repair in place | Repair in place |
| Load home | Repair in place | Repair and move to the nearest road |
| Recover to last road | Repair in place | Repair and move to the nearest road |

- When a reset is not allowed, the button shows why, for example "Stay still 4s to reset" or "Can't reset while being caught".
- **Server checks:**
  - a reset that slips through anyway is announced as "reset illegally" (with 1.5 s of grace for latency)
  - any position jump that no allowed reset explains is announced as "teleported"

### Crash penalty (cops)
- A cop who loses 50 km/h within 0.5 s (about 2.8 G on average) gets frozen for 10 s.
- The 7 s reset wait only starts after the penalty.
- **Fault:** when another car was within 15 m, only the one who drove into the other is penalised. A runner who rams a cop, or a cop who gets hit, is not penalised. Rear-ending a runner who brake-checks still counts against the cop.
- Everyone sees "<name>: crash penalty 10s" on screen.
- A cop who reconnects keeps whatever is left of the penalty.

### Locked during a round
- **Teleporting and recovery:** home, set home, drop the car at the camera, reload, reset all cars.
- **Parts, tuning and paint:** locked for everyone during a round, whichever menu is used (the game's part, tuning and paint functions refuse with a message). Only the evolving runner may change parts and tuning, in prep until Apply. Color comes from `/cnr color`.
- **Physics:** slow motion and the node grabber.
- **Cameras and modes:** switching vehicles, free camera, photo mode, walking mode.
- **Tools:** the editor, track builder, AI traffic, and the "fun stuff" (fire, boost, fling, force field and so on).
- **Consoles:** the Lua console, the UI console and Lua reload.
- **Big map:** "teleport to this point".
- **Radial menu:** repair, flip and recover disappear.

### Vehicle rules
- Only the round car is allowed: other models or configs are refused, and extra parked cars are removed.
- **Pool:** official Car and Truck types. City bus, semi, medium-duty truck, tractor and crawler are excluded by default (`excludedModels`).

## Cops

- **Emergency lights:** cops drive with their emergency lights on, with no siren. When the round car has none, the mod walks the car's actual part tree and fills every empty slot that accepts an emergency light: a light bar first, otherwise a beacon (Burnside, I-Series roof beacon, midtruck beacons). Lights are recognised by their wiring (light bar or beacon signals), so white off-road light bars on fog or high beam are never used, and parts for slots the car doesn't have are never picked. Checked against every stock vehicle config.
- **Last seen:** every 30 s cops get the runner's last position:
  - **Normal maps:** a route line on the road and minimap, plus "Runner seen 640 m NE".
  - **BeamNG.Earth:** a destination in BeamNG.Earth's own GPS ("Runner last seen"). The status line shows the distance by road, for example "Runner 2.4 km by road NE".
- **Line of sight:** each cop's game checks 4 times a second whether it can see the runner: rays from eye height to the runner's car, blocked by terrain and buildings (not by other cars), up to `sightMaxMeters` (400 m), mirrors included.
  - While any cop sees him, every cop gets his position live (every second, every 3 s on BeamNG.Earth) instead of the 30 s ping: "Runner 640 m NE · live".
  - A cop who sees him and is within his own speed × 5 s (at least 50 m) gets no route and reads "IN SIGHT".
  - When all cops lose sight (after a 1.5 s grace), one "last seen" ping goes out at that spot, then the normal pings resume.
  - The client log notes each change ("runner in sight (120 m)"), handy to check what blocks sight on BeamNG.Earth.
- **Runner:** sees "SPOTTED" or "HIDDEN" plus "Nearest cop 1.2 km".
- **Cop placement:** cops are spread out so they do not overlap. The search widens up to 2 km when no road is near. If no road is found at all, there is a message and the cop starts where they are.
- **Late joiners and reconnects:**
  - Someone who joins mid-round becomes a cop.
  - A cop who reconnects comes back near the road where they left.

## Players

- **Car settings carry over:** your in-car switches (traction/stability control, drive mode, diff locks, 4WD range and anything else the car lets you toggle) are noted every few seconds during a round and put back on every car the mod spawns for you (new round, repaint, Apply). They are saved per car model in `settings/cnr_vehicle_modes.json` on your own PC, so they also survive a game restart. A car that doesn't have a setting just keeps its own default.

- **Per-player color:** `/cnr color #ff0000` (or `off`) is applied to every round car. Set during prep, it repaints straight away; otherwise it applies from the next round.
- **Identity:** players are recognised by their BeamMP account for the leaderboard, colors and `start next/again`. Guests are recognised by name, which changes every session.
- **Warnings:**
  - a message at round start when no reset or recover button is bound
  - a message when a player's cached copy of the mod is outdated

## Leaderboards (saved permanently)

- Shown in the Cops and Robbers Leaderboard app, and the top 3 in the HUD's result card after each round.
- **Saved per run:** runner, time, map, car, end reason (caught, called, escaped, disconnect), catchers, every cop in the round with their seconds of sight, the runner's hidden time and how often he lost the cops, and the car mode and build step.
- A cancelled round and a practice round are never recorded.
- **Fresh start in 1.7.0:** the leaderboard file has a new format. An older file is moved to `data/leaderboard-1.6.json` (kept, not used).

## Leaderboard app

- "Cops and Robbers Leaderboard" (Esc > UI Apps) can be added by anyone. It is not placed automatically, collapses with ▾, and refreshes after every round.
- **Map filter:** this map (default), all maps, or any map that has runs.
- **Runners:** each player's best survival time with the car (and the map when showing all maps).
- **Cops:** catches per player, then the fastest catch.
- **Players:** runs, best, catches and assists per player; click a player for all stats:
  - **Runs, best and average survival, escapes** (outlasted the time limit).
  - **Catches:** rounds credited with the catch.
  - **Assists:** caught rounds where the cop had sight of the runner for at least `assistMinSightPercent` (20%) of the chase without being credited. Sight counts from the release, so seeing him at the start alone only earns an assist in a very short chase. Changing the setting re-scores past rounds.
  - **Hidden from cops:** the share of his chases the runner spent out of every cop's sight.
  - **Lost the cops:** how often he broke all cops' sight.
  - Rounds played with sight off (`sightMaxMeters = 0`) show "–" for the last two.

## Test rounds against AI (only you see them)

| Command | You | AI |
|---|---|---|
| Practice: as runner | Runner (blue) | Two cops (green, red) that chase you |
| Practice: as cop | Cop (green) | A runner (blue) that flees, plus a partner cop (red) |

- All rules apply, including crash penalties for the AI.
- Leaving the server, or another player starting a round, ends the test round.
- On BeamNG.Earth, the AI cars are placed near you again after you teleport.
- The AI needs `MaxCars` of 3 or more. On BeamNG.Earth it also needs BeamNG.Earth traffic turned on (for the road graph).

## Gas stations

- **Normal maps:** stations are detected from the map data (10 on West Coast USA, 12 on Italy) and saved per map.
- **BeamNG.Earth:** while players drive, real gas stations within 3 km are looked up through BeamNG.Earth's places API. The server merges them (duplicates within 50 m are dropped) into a list that keeps growing.
- `/cnr addstation` and `/cnr removestation` edit the list by hand.

## BeamNG.Earth (geo mode)

- Every player has their own coordinate origin there, so positions travel between the games and the server as latitude/longitude, through BeamNG.Earth's mod API (`toGeo` and `toGame`). The server calculates all distances in one shared frame.
- **Moves by BeamNG.Earth itself** (rebase, resync, setting the car down) do not count as resets or teleports. Teleporting yourself during a round does.
- **Needs:** BeamNG.Earth with mod API v1. Road resets for cops, cop placement and the AI also need BeamNG.Earth traffic turned on.

## HUD (UI app)

- **Placement:** "Cops and Robbers HUD" is added automatically at bottom centre of the current UI layout on join. That includes BeamNG.Earth's MP layout after it switches. The app can be moved and resized, and it is removed from the layout again when leaving the server. A stock layout copy that only existed because of the HUD is reset to the original on leave.
- **UI scale:** both apps (and the HUD's placement) follow the game's UI scale setting.
- **Status line:** during the chase it shows `ROLE  m:ss | reset status | distance info`.
- **Catch bar:** shown while the catch timer is running. It is red with "BEING CAUGHT" for the runner and blue with "HOLDING RUNNER" for cops, uses 1% steps, and moves smoothly between server updates.
- **Countdowns:** "RUNNER STARTS IN 3", "COPS RELEASED IN 7" and "CRASH PENALTY 10", with a large number.
- **GO flashes:** "GO! RUN!", "GO!" and "PENALTY OVER", each shown for 2 s.
- **Prep line:** your role, the car's name, and "waiting for GO".
- **Reset feedback:** pressing reset when it is not allowed briefly highlights the reset part of the status line.
- **Event line:** for example "Bob: crash penalty 10s", shown for 4 s, at most 2 at once.
- **Result card:** shown for 10 s after a round. It contains the title, the runner and their time, who caught them, the top 3 for the map, and "Next round in N" when Automatic rounds is on (it disappears when someone turns auto off). Leaving the server clears it.
- **Fallback:** when the app is not in the current layout, the old pop-up messages are used. Chat stays the record, and rare warnings stay pop-ups.
- **Evolving mode:** during prep everyone sees the runner's queued change in place of the prep line; Apply shows APPLYING CHANGES.
- **Format:** a Vue 3 app, the newest UI system in BeamNG 0.40.

## Control panel (UI app)

- **Who:** "Cops and Robbers Panel" is for whoever runs the game. It is never placed automatically: add it via Esc > UI Apps. It needs the mouse shown to click. The server does not check who uses it, just like the chat commands.
- **Round tab:**
  - The status line shows the phase ("No round", "Picking cars", "Prep: waiting for GO", "Countdown", "Runner head start" or "Chase m:ss"), the map and the number of players. It also shows the runner's name, with "(practice)" in a test round.
  - Runner picker: "Next (fewest runs)", "Same as last", "Random", or any online player.
  - Buttons: Start round, New car, GO, End chase and Cancel, each enabled only when it would do something. End chase is enabled once the chase is running.
  - An Automatic rounds switch, and Practice "as runner" / "as cop".
  - A reply line shows the server's answer to the last click. The answer also appears in chat.
- **Settings tab:**
  - Every `config.json` setting, grouped into Round, Catching, Resets, Crashes, Cops and Cars. A setting the panel doesn't know yet appears under "Other".
  - Numbers have −/+ steppers, on/off settings have switches, and excluded cars is a comma-separated text field.
  - Changes save automatically 0.5 s after the last click, all at once. Excluded cars save on Enter or when you click away. A value that would be invalid saves nothing and snaps back.
  - The reply line confirms each save ("Saved: Head start 8 s"). Saves don't post to chat. A change still waiting to be saved is saved when the panel closes.
  - "Reset to default" needs a second click within 3 s.
  - Settings are locked during a round ("Stop the round first").
- **Live:** the panel follows changes made by anyone within a quarter of a second.
- **Evolving car:** the Round tab has the Evolving car switch, the build controls (New build: random, choose a car + Start build, both asking for a second click when a build exists; Reset build) and Apply change. Phases include Applying the change and Ready for GO.
- **Reload config.json:** on the Settings tab, picks up hand edits to `config.json` (not during a round).
- **Collapse:** the ▾ button shrinks the panel to one line with the live status (click it or ▸ to open again). It collapses by itself when the countdown starts (GO) and opens again when the round ends.

## Chat commands

Everything else runs through the panel and the leaderboard app. Any other `/cnr` command points to the panel.

| Command | |
|---|---|
| `/cnr color <#hex\|off>` | Your car color for every round (the only way to paint) |
| `/cnr addstation` / `/cnr removestation` | Edit gas stations |
| `/cnr help` / `/cnr version` | Help / version |

## Settings (`config.json`, or the panel)

| Setting | Default | |
|---|---|---|
| `runnerCountdownSeconds` | 3 | Countdown before the runner may drive |
| `headStartSeconds` | 7 | Cops frozen after the runner goes |
| `catchHoldSeconds` | 7 | How long the runner must be held |
| `catchRadiusMeters` | 10 | Distance at which a cop is holding the runner |
| `catchMaxSpeedKmh` | 3 | Runner speed below which they count as held |
| `resetWaitSeconds` | 7 | Stand still this long to reset anywhere |
| `stillMaxSpeedKmh` | 1 | "Standing still" threshold |
| `gasStationRadiusMeters` | 25 | Gas station reset area |
| `copResetMinDistanceMeters` | 1000 | Cops this far from the runner may always reset |
| `copSpawnMinMeters` / `copSpawnMaxMeters` | 50 / 150 | Cop placement around the runner |
| `crashSpeedLossKmh` | 50 | Speed lost within 0.5 s that counts as a crash |
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
| `autoNextRound` | false | Prepare the next round automatically |
| `autoNextDelaySeconds` | 15 | Delay before the next round is prepared |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Models that are never picked |
| `explodeOnCatch` | false | The runner's car explodes when caught |
| `includeModVehicles` | false | Also pick mod vehicles |

## Host and robustness

- **Install:** players install nothing. The server needs the plugin in `Resources/Server` and the zip in `Resources/Client`.
- **Mods panel:** the zip carries a title, description, version and icon (`mod_info`) for mod panels.
- **Stuck controls:** Cancel always unlocks everyone, and so does a plugin restart.
- **Bad files:** a broken `config.json` gives a warning and uses the defaults. A broken or malformed leaderboard is moved aside.
- **Tests:** 385 automated tests cover the rules, the server wiring and the client, which runs against stubbed game functions in `tests/test_client.lua` (run with `make test`).
