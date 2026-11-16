# Cops and Robbers 2.3.0: features

A BeamMP server plugin with a client mod that BeamMP downloads automatically. The mod enforces the group's cops-and-robbers rules. It is one mod for every map, and it switches to geo mode on BeamNG.Earth by itself.

## Round flow

All round controls are in the Cops and Robbers Panel (Host panel button on the lobby card, or Esc > UI Apps). Players see everything in five apps on screen: the mod sends no chat messages, no pop-ups and has no chat commands.

| Step | What happens |
|---|---|
| Start round | Picks a random car and config (or the evolving build). Everyone gets the same one. Cops are placed on a road 50–150 m from the runner. Everyone is frozen. |
| Prep | No time limit. Everyone sees only their role (and cops the runner's name) and "Waiting for the host to press GO". Colors come from the Colour button only: the game's parts and paint menu is closed for everyone (except the runner in evolving mode, for their one change). A parts change the mod didn't make is shown to everyone as a notice (with the slots that changed), but not undone. New car picks another car (random mode). Once a player's car is placed, their game spawns its traffic (see Traffic), which stands still until GO. |
| Apply change (evolving only, the runner's HUD button) | Locks in the runner's change and rebuilds every car; the screen shows APPLYING CHANGES until everyone has loaded (at most 20 s). |
| GO | "Runner starts in 3", then the runner is released. |
| Head start | Cops stay frozen for 7 s and see a countdown. |
| Chase | Cops are released and the survival clock starts. A status line shows `time \| reset status \| distance info`. |
| End | The round ends when the runner is caught, on End chase, when the time limit runs out, or when the runner disconnects. The run is recorded and the result card shows the time, who caught the runner and the map's top 3. |
| Automatic next round | Optional (panel switch). The next round is prepared with whoever has run least. It still waits for GO. |

### Choosing the runner
- The Round tab's player list is the runner picker: Next (whoever has run least this session, preselected), the last runner (marked "last"), Random, or any player by name (sent as an exact name, so names like "next" work).

## Evolving car mode

- **The build:** one shared car (model, parts and tuning) instead of a random car each round. Switch "Evolving car" on in the panel. Start a build from a random car or a chosen one: vanilla configs and base cars from mods the server distributes only, never a player's own saved car, so everyone can spawn it.
- **One change per round:** during prep only the runner can change parts and tuning (from any menu). The group's rule: one change that works on its own (an engine swap, one performance stage, wheels one axle at a time, plus whatever a swap needs). The mod doesn't enforce it: everyone sees the queued change live in the HUD, on a "Bob's change" card ("1 change"): "Engine 2.0L I4 → 3.0L I6", "+ 12 parts come with it" (parts that come with a swap are grouped under it, names from the game), and tuning values that really changed (within half a step) and keep each other honest. A player whose game lacks a part of the change sees that line marked "⚠ missing" right away.
- **Apply change:** the runner presses **Apply change** on the change card in the HUD (only the runner sees it; in practice as cop, whoever started it can apply). The runner's exact setup becomes the build (liveries are paint and stay out), every car is rebuilt in place (cops keep their emergency lights), and the HUD shows APPLYING CHANGES until everyone's car has loaded (at most 20 s). GO only works after that. Each game checks it has every part and the HUD warns "⚠ Ann is missing: …" if not.
- **Record:** a notice announces each change ("Change 7 by Bob: Engine 4.5L V8 → 6.0L V8") and the Car tab shows the last one. The build is saved after every change in `data/build.json` and continues next session until "Reset build"; resetting or starting a new build keeps a backup (`data/build-<time>.json`). Practice rounds use the build but never change it.
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
  - a reset that slips through anyway is shown to everyone as "reset illegally" (with 1.5 s of grace for latency)
  - any position jump that no allowed reset explains is shown as "teleported"

### Crash penalty (cops)
- A cop who loses 50 km/h within 0.5 s (about 2.8 G on average) gets frozen for 10 s.
- The 7 s reset wait only starts after the penalty.
- **Fault:** when another car was within 15 m, only the one who drove into the other is penalised. A runner who rams a cop, or a cop who gets hit, is not penalised. Rear-ending a runner who brake-checks still counts against the cop. Traffic cars count here too: driving into one is the cop's fault, being hit by one is not.
- Everyone sees a notice "<name>: crash penalty 10s", with "(traffic)" after it when the cop drove into traffic. The round's timeline shows the same.
- A cop who reconnects keeps whatever is left of the penalty.

### Locked during a round
- **Teleporting and recovery:** home, set home, drop the car at the camera, reload, reset all cars.
- **Parts, tuning and paint:** locked for everyone during a round, whichever menu is used (the game's part, tuning and paint functions refuse and the HUD says so). Only the evolving runner may change parts and tuning, in prep until Apply. Color comes from the Colour button.
- **Parts check on the server:** a client that gets around the lock anyway is caught by the server: "⚠ Ann changed parts during the round: engine, intake" is shown to everyone as a notice, once per player per round. The car is never replaced. Changes the mod makes itself (round setup, repaint, Apply rebuild) and the evolving runner's prep change never count; for a few seconds after the mod places a car, BeamMP's reports only set the new baseline.
- **Physics:** slow motion and the node grabber.
- **Cameras and modes:** switching vehicles, free camera, photo mode, walking mode.
- **Tools:** the editor, track builder, AI traffic, and the "fun stuff" (fire, boost, fling, force field and so on).
- **Consoles:** the Lua console, the UI console and Lua reload.
- **Big map:** "teleport to this point".
- **Radial menu:** repair, flip and recover disappear.

### Vehicle rules
- Only the round car is allowed: other models or configs are refused, and extra parked cars are removed.
- **Traffic cars** are the exception: once the server has told a player's game to spawn its traffic, that player may have up to that many extra cars of any model. They never count as the player's car for catching, resets, teleports, sight or the parts check, and the server never removes them mid-round. Players still can't switch the game's traffic on themselves during a round.
- **Pool:** official Car and Truck types. City bus, semi, medium-duty truck, tractor and crawler are excluded by default (`excludedModels`).

## Cops

- **Emergency lights:** cops drive with their emergency lights on, with no siren. When the round car has none, the mod walks the car's actual part tree and fills every empty slot that accepts an emergency light: a light bar first, otherwise a beacon (Burnside, I-Series roof beacon, midtruck beacons). Lights are recognised by their wiring (light bar or beacon signals), so white off-road light bars on fog or high beam are never used, and parts for slots the car doesn't have are never picked. Checked against every stock vehicle config.
- **Last seen:** every 30 s cops get the runner's last position:
  - **Normal maps:** a route line on the road and minimap, plus "Runner seen 640 m NE".
  - **BeamNG.Earth:** a destination in BeamNG.Earth's own GPS ("Runner last seen"). The status line shows the distance by road, for example "Runner 2.4 km by road NE".
- **Line of sight:** each cop's game checks 4 times a second whether it can see the runner: rays from eye height to the runner's car, blocked by terrain and buildings (not by other cars), up to `sightMaxMeters` (400 m), mirrors included.
  - While any cop sees the runner, every cop gets the runner's position live (every second, every 3 s on BeamNG.Earth) instead of the 30 s ping: "Runner 640 m NE · live".
  - A cop who sees the runner and is within their own speed × 5 s (at least 50 m) gets no route and reads "IN SIGHT".
  - When all cops lose sight (after a 1.5 s grace), one "last seen" ping goes out at that spot, then the normal pings resume.
  - The client log notes each change ("runner in sight (120 m)"), handy to check what blocks sight on BeamNG.Earth.
- **Runner:** sees "SPOTTED" or "HIDDEN" plus "Nearest cop 1.2 km".
- **Cop placement:** cops are spread out so they do not overlap. The search widens up to 2 km when no road is near. If no road is found at all, the cop gets a notice and starts where they are.
- **Late joiners and reconnects:**
  - Someone who joins mid-round becomes a cop.
  - A cop who reconnects comes back near the road where they left.

## Players

- **Car settings carry over:** your in-car switches (traction/stability control, drive mode, diff locks, 4WD range and anything else the car lets you toggle) are noted every few seconds during a round and put back on every car the mod spawns for you (new round, repaint, Apply). They are saved per car model in `settings/cnr_vehicle_modes.json` on your own PC, so they also survive a game restart. A car that doesn't have a setting just keeps its own default.

- **Per-player color:** the Colour button (lobby card or prep line) opens a colour picker with a hex field, "No colour" and Done. The colour is applied to every round car. Set during prep, it repaints straight away; otherwise it applies from the next round. It is saved on the server per player.
- **How to play:** a five-tab card (Basics, Runner, Cop, Resets, Rules) that opens by itself the first time a player joins (remembered on their own PC in `settings/`) and from the How to play buttons. Every number in it comes from the server's current settings, so it matches the round; settings that are off read "no time limit" or "sight is off". With traffic on, Basics says how many traffic cars each player has and the crash line says driving into traffic counts. It hides itself during a round.
- **Identity:** players are recognised by their BeamMP account for the leaderboard, colors and who runs next. Guests are recognised by name, which changes every session.
- **Warnings:** a yellow line on the lobby card for a standing problem: no reset or recover button bound, an outdated copy of the mod, or a BeamNG.Earth that is too old. It stays until fixed: bind a reset button and the line goes within a couple of seconds. Without a reset binding, a round also starts with a warning notice.

## Leaderboards (saved permanently)

- Shown in the Cops and Robbers Leaderboard app, and the top 3 in the result card after each round.
- **Saved per run:** runner, time, map, car, the round's conditions (time of day, weather, clock speed, whether weather affected driving), the traffic per player, end reason (caught, called, escaped, disconnect), catchers, every cop in the round with their seconds of sight, the runner's hidden time and how often they lost the cops, the car mode and build step, and a timeline of what happened (cops released, lost the cops, crash penalties, illegal resets, teleports, parts changes, the end).
- A cancelled round and a practice round are never recorded.
- **Fresh start in 1.7.0:** the leaderboard file has a new format. An older file is moved to `data/leaderboard-1.6.json` (kept, not used).

## Leaderboard app

- "Cops and Robbers Leaderboard" has the look of the game's multiplayer scoreboard: rows on dark cards, gold, silver and bronze rank badges, and your own row outlined in orange. Open it from the lobby card or Esc > UI Apps. It has a ✕, refreshes after every round and hides itself during a round.
- **Filters:** map (this map by default, all maps, or any map that has runs, shown with its real name), car mode (all, random, evolving) and traffic (all, with traffic, no traffic; rounds from before traffic count as no traffic).
- **Runners:** each player's best survival time with the car (and the map when showing all maps). When you are not in the visible top, your own row is pinned at the bottom with your rank.
- **Cops:** catches per player, assists and the fastest catch.
- **Players:** runs, best, catches and assists per player; click a player for all stats and their last rounds:
  - **Runs, best and average survival, escapes** (outlasted the time limit).
  - **Catches:** rounds credited with the catch.
  - **Assists:** caught rounds where the cop had sight of the runner for at least `assistMinSightPercent` (20%) of the chase without being credited. Sight counts from the release, so seeing the runner at the start alone only earns an assist in a very short chase. Changing the setting re-scores past rounds.
  - **Hidden from cops:** the share of their chases the runner spent out of every cop's sight.
  - **Lost the cops:** how often they broke all cops' sight.
  - Rounds played with sight off (`sightMaxMeters = 0`) show "–" for the last two.
- **Rounds:** every recorded round, newest first, grouped by day. Each row shows how it ended, who ran and who caught them, the time of day, car (followed by the conditions, for example "Gavril D-Series · Night · Rain · Traffic") and build step, the survival time, and a yellow line for anything that went wrong ("Kim reset illegally"). Click a round for its timeline and each cop's share of the chase with the runner in sight. Rounds saved before the timeline existed show only the result. Long lists load more with "Show more".

## Traffic

- **Around every player:** during a round each player's game runs `trafficPerPlayer` AI traffic cars (5 by default, 0 = off) around itself with the game's own traffic system, so there is traffic wherever anyone drives.
- **Capped by `MaxCars`:** the server leaves room for the round car (and the two AI cars in practice), so with `MaxCars` 4 a player gets 3 traffic cars. The panel says when the cap applies.
- **In the round:** traffic spawns once a player's car is placed in prep and stands still until the runner's GO, so it can't drive into the frozen cars. A player who joins mid-round gets traffic that drives at once. Everyone's traffic is removed at the end of the round, on Cancel and on leaving. If a game can't spawn its traffic, that player gets one notice ("Traffic could not spawn") and the round goes on.
- **Which cars:** official vehicles only, never police, emergency vehicles or taxis, and no random traffic events. Traffic cars have no name tags, so every car with lights is a cop and every name tag is a player, also for players in the lobby watching someone's practice round.
- **Lights:** in rain, storm, fog and snow rounds traffic drives with its headlights on. At night it follows the game's own rule (lights on from sunset, and in tunnels), which also thins traffic out at night.
- **Weather:** traffic slows down on wet roads and snow by itself, and gusts push it like any car.
- **Crashes:** see Crash penalty. Traffic never helps catch the runner.
- **Not on BeamNG.Earth yet:** BeamNG.Earth manages any traffic that runs, so traffic stays off there and the panel says so.

## Night and weather

- **Settings:** a Sky group in the panel: Time of day, Night chance, Clock speed, Weather, Bad weather chance and Weather affects driving. Time of day and Weather can be the map's own (the default, nothing changes), a fixed choice or random.
- **Random:** with Time of day on random, a roll under the night chance gives night, otherwise sunrise, morning, noon, afternoon or sunset. With Weather on random, a roll under the bad weather chance gives rain, storm, fog or snow, otherwise clear or cloudy. Both chances are 25% by default, so hard rounds stay occasional.
- **Same for everyone:** everyone in a round gets the same time, weather, rain or snow, and wind, also a player who rejoins mid-round. The game's environment menu is locked during the round. Practice rounds get a sky too, and the AI cars switch their headlights on at night.
- **New sky:** a button next to New car in prep, only while time or weather is random. It picks new values without re-placing the cars. New car keeps the sky; each new round picks again.
- **Clock:** at clock speed 0 the clock is stopped. At a speed above 0 it stays stopped in prep and starts at GO, so the round starts in the time you saw. Speed 60 runs dusk into night in a few minutes.
- **Grip:** with Weather affects driving, rain turns asphalt and gravel wet and dirt to wet gravel; grass and rumble strips lose a little grip. A storm also turns dirt into mud. Snow covers everything you drive on. These are the game's own surfaces, so tires matter: drag tires slide more on wet roads than road tires. Clear, cloudy and fog change no grip. Surfaces the mod doesn't know (a mod map's own) stay dry.
- **Shelter:** rain and snow stop in tunnels and under low roofs: 4 times a second the game looks up from the camera, and when there's a roof within 12 m straight above and around it, the rain is hidden until you're back in the open. Under a high bridge it keeps raining.
- **Wind:** realistic strengths: rain 5 m/s gusting to 8, snow 4 gusting to 6, a storm a 17 m/s gale gusting to 26. Gusts last a few seconds, turn up to 15° (30° in a storm), and come at the same moment for every player.
- **Temperature:** follows the weather (cold in snow, so exhausts steam) and the map's day curve.
- **After the round:** sky, grip, wind, temperature and the environment menu go back to what each player had, at the end, on cancel and on leaving. A map change drops it without applying anything.
- **Prep line:** shows the conditions after the car, for example "Gavril D-Series · Night · Rain".
- **Not on BeamNG.Earth:** the server sends no sky there, and the panel says so.

## Test rounds against AI (only you see them)

| Command | You | AI |
|---|---|---|
| Practice as runner | Runner (red) | Two cops (blue) that chase you |
| Practice as cop | Cop (blue) | A runner (red) that flees, plus a partner cop (blue) |

- All rules apply, including crash penalties for the AI.
- Leaving the server, or another player starting a round, ends the test round.
- On BeamNG.Earth, the AI cars are placed near you again after you teleport.
- In evolving mode, Apply rebuilds the AI cops in place with the new build too.
- The AI needs `MaxCars` of 3 or more. On BeamNG.Earth it also needs BeamNG.Earth traffic turned on (for the road graph).

## Gas stations

- **Normal maps:** stations are detected from the map data (10 on West Coast USA, 12 on Italy) and saved per map.
- **BeamNG.Earth:** while players drive, real gas stations within 3 km are looked up through BeamNG.Earth's places API. The server merges them (duplicates within 50 m are dropped) into a list that keeps growing.
- The Map tab of the host panel shows the stations of this map, with Add station here and Remove nearest.

## BeamNG.Earth (geo mode)

- Every player has their own coordinate origin there, so positions travel between the games and the server as latitude/longitude, through BeamNG.Earth's mod API (`toGeo` and `toGame`). The server calculates all distances in one shared frame.
- **Moves by BeamNG.Earth itself** (rebase, resync, setting the car down) do not count as resets or teleports. Teleporting yourself during a round does.
- **Needs:** BeamNG.Earth with mod API v1. Road resets for cops, cop placement and the AI also need BeamNG.Earth traffic turned on.
- **No round traffic yet:** BeamNG.Earth moves, hides and rebuilds any traffic that runs (after a teleport, a region change, or cars standing still), so the mod's traffic stays off there for now.

## HUD (UI apps)

- **Two apps, both placed automatically:** "Cops and Robbers Announcements" (upper middle: role title, countdowns, GO flashes, APPLYING CHANGES, the result) and "Cops and Robbers HUD" (bottom centre: everything else). They are added to the current UI layout on join, including BeamNG.Earth's MP layout after it switches. Players can move and resize them but not remove them, and both are removed again when leaving the server. A stock layout copy that only existed because of them is reset to the original on leave.
- **Click-through:** both apps let clicks through to the game and other apps everywhere except their own buttons and cards. Clicking needs the mouse cursor shown.
- **UI scale:** all apps follow the game's UI scale, and their content scales down to fit a small box.
- **Lobby card** (between rounds): "Cops and Robbers", the number online, "Waiting for the host to start a round" or "Practice round: Bob", and the buttons Colour, How to play, Leaderboard and Host panel (the last two open and close those apps and show when they are open). Standing problems show as a yellow line.
- **Prep:** the role in the centre ("YOU'RE THE RUNNER" in red, "YOU'RE A COP" in blue, with "Bob is the runner" for cops) and the car's name, no rule text. At the bottom "Waiting for the host to press GO" with Colour, How to play and Host panel buttons.
- **Chase line:** role chip, survival time (`3:12 / 10:00` with a time limit), SPOTTED or HIDDEN for the runner (IN SIGHT, live or last seen for cops), the nearest cop or the cop's distance and direction, and the reset status ("Reset ready", "Stay still 4 s to reset", "Can't reset while being caught"). No key is named, because players use different reset buttons. Pressing reset when it is not allowed briefly highlights the line.
- **Catch bar:** shown while the catch timer is running. It is red with "BEING CAUGHT" for the runner and blue with "HOLDING RUNNER" for cops, uses 1% steps, and moves smoothly between server updates.
- **Countdowns:** "RUNNER STARTS IN", "COPS RELEASED IN" and "CRASH PENALTY" over a large number; then "GO! RUN!" (runner), "GO!" (cops) and "PENALTY OVER", each for 2 s. During the head start the runner's chase line shows "Cops released in N".
- **Notices:** an icon and one line above the chase line (or the lobby card), 4 s each, at most 2 at once. Yellow for rule breaks and personal warnings ("Bob: crash penalty 10s", "Ann reset illegally", "Ann teleported", "Ann changed parts during the round: engine, intake", no road found, could not spawn AI, no vehicles), white for information (build changes).
- **Result:** shown for about 10 s after a round. The title (RUNNER CAUGHT, ROUND ENDED, ESCAPED, RUNNER LEFT, ROUND CANCELLED), the runner's time, who caught them (or, for a cancelled round, why: "Runner left, round cancelled"), the map's top 3 with your row outlined, and "Next round in N" when Automatic rounds is on. Leaving the server clears it.
- **Evolving mode:** during prep the bottom shows the runner's queued change as a card ("Your change" or "Bob's change") with Apply change for the runner only; after Apply the centre shows APPLYING CHANGES.
- **Format:** Vue 3 apps built on the game's own components, colours and fonts (see `docs/DEPENDENCIES.md`).

## Control panel (UI app)

- **Who:** "Cops and Robbers Panel" is for whoever runs the game. It never opens by itself: use the Host panel button on the lobby card or the prep line, or Esc > UI Apps. The server does not check who uses it. It has the version in its header and a ✕.
- **Four tabs:** Round, Car, Map, Settings.
- **Round tab** shows only what can be done now, with one main button for the next step and a yellow line saying why it can't happen yet:
  - **No round:** the status, the map's real name and the car mode, the player list as the runner picker (runs this session, "next" and "last" marks, and a Random runner row), **Start round with Bob**, Practice as runner / as cop, and the Automatic rounds switch with its delay.
  - **Prep:** the runner and the car's name (or build step), the players with their role and state (ready, changing, missing parts; display only), **GO** (disabled with the reason, for example "Waiting for Bob to apply the change"), New car (random mode) and Cancel round.
  - **Countdown, head start, chase:** the panel folds into a bar with the phase, the runner, **End chase** and **Cancel** (a second click during the chase), and ▾ to open it. It folds by itself on GO and opens again when the round ends.
  - **Someone's practice round:** the practice's own controls, plus the runner picker and **Start round with Bob** under "Start a real round" (starting one ends the practice).
  - **After a round:** the result line ("Bob caught after 8:41"), and with automatic rounds on, "Next round in 12 s with Kim (fewest runs)" with **Start now** and **Stop automatic rounds**.
  - A reply line shows the server's answer to every click. Nothing goes to chat.
- **Car tab:** a Random car / Evolving build switch. In evolving mode a summary (car, build step, last change and who made it), New build (choose a car, or random; a second click when a build exists) and Reset build (a second click). For both modes: Include mod cars and the excluded cars. Locked during a round.
- **Map tab:** "West Coast USA · 10 gas stations", **Add station here**, **Remove nearest** (disabled with "No station within 50 m to remove") and the nearest stations with their distance (flat distance on BeamNG.Earth, updated every 2 s while the tab is open). Works on BeamNG.Earth, where stations are also discovered automatically.
- **Settings tab:**
  - Every setting has a one-line explanation. The common ones come first (Head start, Time limit, the Sky choices, Traffic, Hold time, Catch distance, Reset wait, Crash penalty); the rest are under More settings, grouped into Round, Sky, Catching, Resets, Crashes, Cops and Cars. Traffic has a line under it with what it costs ("5 each · 30 cars with 6 players") or how `MaxCars` caps it. On BeamNG.Earth the Sky and Traffic groups say "Not available on BeamNG.Earth yet" instead. A setting the panel doesn't know yet appears under "Other".
  - Numbers have −/+ steppers, on/off settings have switches, and excluded cars is a comma-separated text field.
  - Changes save automatically 0.5 s after the last click. A value that differs from the default is orange with its own small reset. A refused value snaps back with the reason in yellow, and the reply line confirms each save in green ("Saved: Head start 8 s").
  - "Reset to default" needs a second click within 3 s. Settings are locked during a round ("Stop the round first").
  - **Reload config.json** picks up hand edits (not during a round).
- **Live:** the panel follows changes made by anyone within a quarter of a second.

## Quiet

- **No chat commands.** `/cnr color`, `/cnr addstation`, `/cnr removestation`, `/cnr help` and `/cnr version` are gone. Their jobs moved to the colour picker, the Map tab, How to play and the panel header. A typed `/cnr ...` is hidden from chat, and the sender gets a notice pointing to the Cops and Robbers card.
- **No chat messages and no pop-ups.** Round flow, results, rule breaks and build changes show in the apps as they happen (see HUD). The Leaderboard's Rounds tab keeps each round's result and timeline; for the build, the Car tab shows the last change and the full history stays in `data/build.json`. Replies to the host's clicks show in the panel's reply line.

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
| `sightLiveIntervalSeconds` | 1 | Live runner position for all cops while one sees the runner (at least 3 s on BeamNG.Earth) |
| `sightNoRouteSeconds` | 5 | A cop who sees the runner within their speed × this many seconds gets no route |
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
| `timeOfDay` | map | `map` (the map's own), `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night` or `random` |
| `nightChancePercent` | 25 | Chance of night when Time of day is random |
| `clockSpeed` | 0 | Speed of the sky clock during a round: 0 stopped, 1 real time, a whole number up to 120 |
| `weather` | map | `map` (the map's own), `clear`, `cloudy`, `rain`, `storm`, `fog`, `snow` or `random` |
| `badWeatherChancePercent` | 25 | Chance of rain, storm, fog or snow when Weather is random |
| `weatherDriving` | true | Weather changes grip and adds wind (not on BeamNG.Earth) |
| `trafficPerPlayer` | 5 | AI traffic cars around each player during a round (0 = off; normal maps only) |

## Host and robustness

- **Install:** players install nothing. The server needs the plugin in `Resources/Server` and the zip in `Resources/Client`.
- **Mods panel:** the zip carries a title, description, version and icon (`mod_info`) for mod panels.
- **Stuck controls:** Cancel always unlocks everyone, and so does a plugin restart.
- **Bad files:** a broken `config.json` gives a warning and uses the defaults. A broken or malformed leaderboard is moved aside.
- **Tests:** The automated tests cover the rules, the server wiring and the client, which runs against stubbed game functions in `tests/test_client.lua` (run with `make test`).
