# Cops and Robbers 2.11.0: features

A BeamMP server plugin with a client mod that BeamMP downloads automatically. The mod enforces the group's cops-and-robbers rules. It is one mod for every map, and it switches to geo mode on BeamNG.Earth by itself.

## Round flow

All round controls are in the Cops and Robbers Panel (Host panel button on the lobby card, or Esc > UI Apps). Players see everything in five apps on screen: the mod sends no chat messages, no pop-ups and has no chat commands.

| Step | What happens |
|---|---|
| Start round | Needs one player who isn't sitting out ("Everyone is sitting out" otherwise). Picks a random car (a car model first, each equally likely, then one of its configs; with mod vehicles on, only mod cars the server provides) or the evolving build. Everyone gets the same one. Cops are placed on a road 50–150 m by road from the runner, facing toward the runner, and the runner is moved to the nearest road, facing the way their car was pointing (in practice they stay where they are). Everyone is frozen. |
| Prep | No time limit. Everyone sees only their role (and cops the runner's name) and "Waiting for the host to press GO". Colors come from the Settings card only: the game's parts and paint menu is closed for everyone (except the runner in evolving mode, for their one change). A parts change the mod didn't make is shown to everyone as a notice (with the slots that changed), but not undone. New car picks another car (random mode). Once a player's car is placed, their game spawns its traffic (see Traffic), which stands still until GO. |
| Apply change (evolving only, the runner's HUD button) | Locks in the runner's change and rebuilds every car; the screen shows APPLYING CHANGES until everyone has loaded (at most 20 s). |
| GO | "Runner starts in 3", then the runner is released. |
| Head start | Cops stay frozen for 7 s and see a countdown. |
| Chase | Cops are released and the survival clock starts. A status line shows `time \| reset status \| distance info`. |
| End | The round ends when the runner is caught, on End chase, when the time limit runs out, or when the runner disconnects. The run is recorded and the result card shows the time, who caught the runner and the map's top 3. |
| Automatic next round | Optional (panel switch). The next round is prepared with the next runner (see below). It still waits for GO. |

### Choosing the runner
- The Round tab's player list is the runner picker: Next (drawn at random among the players with the fewest runs this session, never the previous runner while another can go, and only the previous runner if they are the sole candidate; the draw is kept, so the panel's "next" mark and the runner Start gets are the same player, and it is drawn again only when that player leaves, sits out or no longer has the fewest runs, or after a round; preselected; only rounds that really end count as a run, not a cancelled round or a practice), the last runner (marked "last"), Random, or any player by name (sent as an exact name, so names like "next" work).
- A player sitting out is marked "sitting out" in the list and is never the runner: Next and Random skip them, and picking them by name or with Again says "Bob is sitting out".

## Evolving car mode

- **The build:** one shared car (model, parts and tuning) instead of a random car each round. Switch "Evolving car" on in the panel. Start a build from a random car or a chosen one: vanilla configs and base cars from mods the server distributes only, never a player's own saved car, so everyone can spawn it.
- **One change per round:** during prep only the runner can change parts and tuning (from any menu). The group's rule: one change that works on its own (an engine swap, one performance stage, wheels one axle at a time, plus whatever a swap needs). The mod doesn't enforce it: everyone sees the queued change live in the HUD, on a "Bob's change" card ("1 change"): "Engine 2.0L I4 → 3.0L I6", "+ 12 parts come with it" (parts that come with a swap are grouped under it, names from the game), and tuning values that really changed (within half a step) and keep each other honest. A player whose game lacks a part of the change sees that line marked "⚠ missing" right away.
- **Apply change:** the runner presses **Apply change** on the change card in the HUD (only the runner sees it; in practice as cop, whoever started it can apply). The runner's exact setup becomes the build (liveries are paint and stay out), every car is rebuilt in place (cops keep their emergency lights), and the HUD shows APPLYING CHANGES until everyone's car has loaded (at most 20 s). GO only works after that. Each game checks it has every part and the HUD warns "⚠ Ann is missing: …" if not.
- **Record:** a notice announces each change ("Change 7 by Bob: Engine 4.5L V8 → 6.0L V8") and the Car tab shows the last one. The build is saved after every change in `data/build.json` and continues next session until "Reset build"; resetting or starting a new build keeps a backup (`data/build-<time>.json`). Practice rounds use the build but never change it.
- **Leaderboard:** runs record the mode and build step, and the leaderboard app filters by mode (all, random, evolving).

## Rules enforced

### Catching
- The runner is caught after being held for 7 s: runner under 3 km/h with a cop within 10 m (centre to centre).
- A runner rocking back and forth (moving under 3 m in 4 s while going back and forth) counts as held too, at any speed, so a stuck car can't escape by rocking. A slow straight crawl doesn't count. In the first 4 s after the cops' release only the speed counts.
- The hold timer drains at twice the speed it fills, so one jolt does not wipe the progress.
- Cops serving a crash penalty do not count toward a catch.
- No catch is possible during the head start.
- Cops within the radius at the catch get the credit ("caught by Bob, Ann").

### Resets
- **When a reset is allowed:**
  - at a gas station, when standing still
  - after standing still for 7 s anywhere; rocking in place (within 3 m, such as on your side) still counts
  - for a cop who is 1 km or more from the runner, at any time
  - for the runner, once, right after a cop crashes into them (the cop at fault): a free reset without standing still, while that cop serves the crash penalty. It isn't allowed while the runner is being caught, and using it (or any reset) ends it. The HUD shows "Free reset (cop crashed into you)".
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
  - the server log notes each round setup sent, each refused car with its model and vid (at most once per 10 s per player), each spawn and edit of a car that is being placed, each placement report, each teleport with its distance and each crash penalty

### Crash penalty (cops)
- A cop who loses 50 km/h within 0.5 s (about 2.8 G on average) gets frozen for 10 s.
- Only within 1 km of the runner (`copResetMinDistanceMeters`), where a cop can't reset freely. Further away a crash gives no penalty, whatever the cause, traffic included.
- The 7 s reset wait only starts after the penalty.
- **Fault:** when another car was within 15 m, only the one who drove into the other is penalised. A runner who rams a cop, or a cop who gets hit, is not penalised. Rear-ending a runner who brake-checks still counts against the cop. Traffic cars count here too: driving into one is the cop's fault, being hit by one is not.
- Everyone sees a notice "<name>: crash penalty 10s", with "(traffic)" after it when the cop drove into traffic. The round's timeline shows the same.
- A cop who reconnects keeps whatever is left of the penalty.

### Locked during a round
- **Teleporting and recovery:** home, set home, drop the car at the camera, reload, reset all cars.
- **Parts, tuning and paint:** locked for everyone during a round, whichever menu is used (the game's part, tuning and paint functions refuse and the HUD says so). Only the evolving runner may change parts and tuning, in prep until Apply. Color comes from the Settings card.
- **Parts check on the server:** a client that gets around the lock anyway is caught by the server: "⚠ Ann changed parts during the round: engine, intake" is shown to everyone as a notice, once per player per round. The car is never replaced. Changes the mod makes itself (round setup, repaint, Apply rebuild) and the evolving runner's prep change never count; for a few seconds after the mod places a car, BeamMP's reports only set the new baseline.
- **Physics:** slow motion and the node grabber.
- **Cameras and modes:** switching vehicles, free camera (both open for spectators, free camera open in practice; dropping the car at the camera stays locked), photo mode, walking mode.
- **Tools:** the editor, track builder, AI traffic, and the "fun stuff" (fire, boost, fling, force field and so on).
- **Consoles:** the Lua console, the UI console and Lua reload.
- **Big map:** "teleport to this point".
- **Radial menu:** repair, flip and recover disappear.

### Vehicle rules
- Only the round car is allowed: other models or configs are refused, and extra parked cars are removed.
- **Traffic cars** are the exception: once the server has told a player's game to spawn its traffic, that player may have up to that many extra cars of any model. They never count as the player's car for catching, resets, teleports, sight or the parts check, and the server never removes them mid-round. Players still can't switch the game's traffic on themselves during a round.
- **Pool:** official Car and Truck types. City bus, semi, medium-duty truck, tractor and crawler are excluded by default (`excludedModels`).

## Cops

- **Emergency lights:** cops drive with their emergency lights on (a runner in a police car has the light bar and siren forced off and their keys locked during a round), with no siren unless the cop turns it on in Settings (and the host allows Cop sirens). When the round car has none, the mod walks the car's actual part tree and fills every empty slot that accepts an emergency light: a light bar first, otherwise a beacon (Burnside, I-Series roof beacon, midtruck beacons). Lights are recognised by their wiring (light bar or beacon signals), so white off-road light bars on fog or high beam are never used, and parts for slots the car doesn't have are never picked. Checked against every stock vehicle config.
- **Line of sight:** each cop's game checks 4 times a second whether it can see the runner: rays from eye height to the runner's car, blocked by terrain and buildings (not by other cars), up to `sightMaxMeters` (400 m), mirrors included.
  - While any cop sees the runner, every cop gets the runner's position live (every second, every 3 s on BeamNG.Earth): "Runner 640 m NE · live".
  - A cop who sees the runner and is within their own speed × 5 s (at least 50 m) gets no route and reads "IN SIGHT". This is the Out of sight default: a cop's Route to the runner setting can keep the route while in sight (Always) or turn it off (Never).
  - When the runner stops being spotted (no cop has sight and the helicopter isn't tracking, after a 1.5 s grace), one "last seen" ping goes out at that spot: a route line on the road and minimap with "Runner seen 640 m NE · 12 s ago" (the age counts up, in minutes after the first minute), or on BeamNG.Earth a destination in its own GPS ("Runner last seen"). There are no other pings.
  - The client log notes each change ("runner in sight (120 m)"), handy to check what blocks sight on BeamNG.Earth.
- **Runner:** sees "SPOTTED" or "HIDDEN" plus "Nearest cop 1.2 km", which updates every 30 s and with every live update. The runner never sees the cops on the minimap or by name tag for the whole round (a cop car that turns up mid-round is hidden within a second; the minimap part is skipped on BeamNG.Earth); cops still see each other.
- **Cop placement:** cops start a short drive from the runner (by road, following one-way roads), facing toward the runner, and spread out so they do not overlap. The search widens until it covers at least 2 km by road. On a divided road with a narrow median (up to 5 m), the runner counts as being on the carriageway its car points along, even when the other one is a little closer. A runner on a piece of road that isn't connected to the rest gets cops placed by straight-line distance, still at least the minimum start distance away and never on a gated road or a private road behind one. If no road is found at all, the cop gets a notice and starts where they are.
- **Runner placement:** at round start the runner's new car is placed on the nearest road, facing the direction of that road closest to the way their car was heading, so nobody starts stuck on a wall or a rock or turned around. Practice rounds keep the runner where they are. If no road is found, the runner gets a notice ("No road found nearby, you start where you are") and starts where they are.
- **Late joiners and reconnects:**
  - Someone who joins after the round's car is picked spectates until the round ends (see Spectators and Sit out). Before that, during the pick, they still play.
  - A cop who reconnects comes back near the road where they left (also when they left in prep or the countdown).
  - The mod's own move of their car into the round is never a teleport, an illegal reset or a crash: the server holds those checks until their game reports the car placed, and for 3 s after (at most 1 minute without a report).

## Spectators and Sit out

- **Sit out:** a button on the lobby card ("Sit out", reading "Play" while on) and on the spectating card. It is kept per player on the server for the session; leaving the server clears it. In the lobby it applies to the next round; once a round is set up a change counts from the next round, with a notice saying so. The lobby line reads "You're sitting out".
- **Who spectates:** everyone with Sit out on when a round is started, and a new player who joins after the round's car is picked. A player who left mid-round and comes back still plays on in their role.
- **Not in the round:** spectators have no role and no rule counts them: catching, sight, the nearest cop, the helicopter's guidance, resets, penalties, the leaderboard and the traffic note's player count. The lobby's online count still includes them.
- **Practice while sitting out:** starting practice with Sit out on (the panel then offers one button, **Practice: watch the AI**, with the line "You're sitting out: an AI runner against two AI cops, and you watch") runs the practice with AI only: an AI runner (red) against AI cop 1 and AI cop 2 (blue), the cops of practice as runner. You spectate it as a sitting-out player spectates a round: your cars are parked and come back afterwards, your traffic is removed, Tab and Ctrl+Tab go through the three AI cars (the card names them, "SPECTATING · AI runner"), free camera works, and the card has the round clock and the forecast. The AI runner starts on the road nearest to where your car stood (or under the camera if you had none), facing the way your car pointed, and the AI cops start 50–150 m by road from it, facing it. Without a player cop the runner flees from the nearest AI cop, checked once a second. The rest is practice as usual: only you get its events, New car, New sky, GO, End chase, Stop and the result card work, nothing is recorded, and leaving ends it. It has no traffic. Sit out changed during it counts from the next practice or round.
- **The sitting-out player's car:** when the round is set up, their own game notes each of their cars (model, configuration, paint and where it stood, upright) and removes it, so BeamMP removes it for everyone. Their own AI traffic and a walking character are removed too and don't come back. When the round ends or is cancelled the cars come back where they stood and the player is put in the first one; a car the game can't spawn then gets the notice "Your car could not be put back". On a map change or leaving they are forgotten (BeamMP removes every car then). A spectator can't spawn a car until the round ends ("You can't spawn a car while spectating").
- **Watching:** the game's own switch-car keys (Tab and Ctrl+Tab by default) go through the round players' cars, the runner's included; a press that would land on a traffic car moves on to the next player's car, and from free camera the camera goes to the car. Free camera (Shift+C by default) works. Spectators never drive: BeamMP keeps another player's car on that player's inputs. The rest of the round's locks stay (teleporting, the vehicle menu, walking, the parts menu and so on).
- **HUD:** "SPECTATING · Bob" with the watched player's name or "free camera", the countdowns, the round clock with the time limit and the helicopter, as a cop sees them, and buttons for Sit out or Play, How to play, Leaderboard and Host panel. No reset, penalty or role lines. The sky, the helicopter's light and sound and New sky follow the round, and the result card shows at the end. How to play and the Leaderboard stay open while spectating.

## Police helicopter and hiding

- **A tracking rule, not a model:** the game ships no helicopter model, but you hear its rotor, and at night you see its searchlight, the beam in the air and the glare. On by default (`helicopter`).
- **Phases:** it arrives `helicopterArrivalSeconds` (60 s) after the cops are released, flies for `helicopterUpSeconds` (120 s), then refuels for `helicopterRefuelSeconds` (90 s) and comes back, until the chase ends. With refuel 0 it stays up once it has arrived.
- **Tracking:** while it is up and sees the runner, every cop gets the runner's live position, like cop sight. With sight Off it still sends them.
- **Cover:** the runner's game checks 4 times a second what the helicopter can see, up to 400 m away. The runner is lost after 2 s out of its sight in a row: behind buildings and hills, in tunnels and under covers, more than 400 m away, and while it flies in low. Then it searches. Before it arrives and while it refuels, nothing sees the runner. The moment it sees them again it tracks them at once, in any weather. If no cop sees the runner either, one last-seen ping goes out where the runner is when it gives up, about 2.5 s after they left its sight.
- **Searching:** every flight starts searching. It finds the runner only by seeing them itself, within 400 m.
  - **A moving runner** (5 m/s or more, not under a roof) gets a road search, at arrival, after a refuel and when it loses them. A search point flies at 45 m/s along the road ahead of where the runner was (2500 m), then along the best other branch at the first junction within 500 m (1500 m), then back (1000 m), and the helicopter follows it. At night the light sweeps across the road 60 m ahead of the point, 15 m to each side every 3 s; while the helicopter flies to the next road's start, it sweeps the ground 60 m ahead of the helicopter, toward that start. When the search is done it circles where it started.
  - **Over a stopped runner** (under 5 m/s) it contains instead: it circles the spot.
  - It starts at arrival where the runner was when it went up; after a refuel, where it last tracked them or the cops last guided it; when it loses them, where they were then.
  - **Lost in a tunnel,** it watches each way out in turn for a set time: the straightest exit ahead first, then the others, then the entrance. Each watch lasts the way's length divided by the runner's speed (at least 10 m/s) times 1.5, from 15 s to 90 s. After the last one it does a road search out of the tunnel, ahead and along the best other branch but not back into it. Each game follows the road from the car through the tunnel up to 3 km.
  - **Guided in a tunnel:** while a cop sees the runner inside a tunnel, it waits at the exit ahead, and follows U-turns and branches the cops see.
  - While any cop sees the runner, it flies to them and circles them. It still says SEARCHING until it sees them itself. AI cops don't guide it.
  - At night its light keeps sweeping: a spiral around the spot, out to 150 m and back in, on the ground.
- **Weather:** grounded while the weather is storm, fog or snow, and back when it clears. A round that starts in one of them starts grounded and the helicopter never arrives until the weather turns to rain, cloudy or clear. When the weather changes to storm, fog or snow mid-round, the helicopter is recalled: if it is up, it flies away like at a refuel (the light fades), and a refuel in progress is cancelled. When the weather turns back to rain, cloudy or clear (the change ends), it arrives again after `helicopterArrivalSeconds`, searches, and gets a full `helicopterUpSeconds` (the crew refuelled while it was down). Rain doesn't affect it. The forecast line says in advance when a change will ground it or bring it back.
- **HUD:** everyone sees its state: "HELICOPTER IN 0:45", "HELICOPTER 1:20" or "HELICOPTER SEARCHING 1:20" (no time when refuel is 0), "HELICOPTER REFUELLING 0:30" or "HELICOPTER GROUNDED (FOG)". When it is coming back after the weather cleared it reads "HELICOPTER IN 1:00".
- **Searchlight (night only):** while it is up at night, a searchlight hangs from the helicopter. While it tracks, the light keeps its spot on the runner's car with small corrections, as an operator would. While it searches, the light sweeps around the spot. The helicopter really flies, in every game: it trails a moving car 40 m behind, 60 m to one side and 100 m up, swings wide on turns, circles a stopped car at 80 m, flies in from 300 m out and flies away on refuel. The light casts shadows, so a bridge deck or tunnel roof blocks it. It stays on while the helicopter searches, and when the helicopter finds or loses the runner the spot swings over smoothly.
  - **Beam in the air:** a soft, see-through cone from the light down to the lit spot, drawn with the game's debug drawer. It is faint on a clear night (strength 0.06), stronger in cloud (0.12) and clearest in rain (0.2), and it fades in and out with the light. A bridge deck or tunnel roof over the lit spot ends it, and it fades out near the camera so you never see a sheet up close.
  - **Glare:** the light has a soft halo, so you see where the helicopter is when you look up.
  - **Setting:** Searchlight beam in the player settings, on by default. Off removes the beam in the air on your game; the light and its glare stay.
  - There is no minimap ring or icon.
- **Sound (day and night):** the rotor plays from the flying helicopter on every game, as a looping 3D sound, so you hear it long before you see it. The game's 3D audio fades it with distance (reference distance 130 m, maximum distance 1500 m), so the fly-in and the fly-away get louder and quieter by themselves.
  - It never jumps up or cuts off: every rise is eased over 1 s (a new flight, joining mid-round, the setting turned on, a short refuel bringing it back). It fades out over the fly-away's last 3 s, and over 1 s whenever it stops otherwise. The round's end, a cancel, leaving and a map change remove it at once, and nothing is left after them or after a Lua reload.
  - On a cop's game, if the runner's car is missing for more than 2 s, it fades out, and back in when the car is back.
  - When something solid is between your camera and the helicopter, it is muffled to half over 0.5 s, and comes back when the view is clear.
  - **Setting:** Helicopter sound in the player settings, on by default. Off fades it out on your game.
- **Hiding:** from the runner's release (the head start) on, the runner's name tag and minimap marker show on the cops' games only while the runner is spotted (a cop has sight, or the helicopter is tracking). Prep and the countdown show the runner as before. With the sight range Off the runner is never hidden. On BeamNG.Earth the minimap is not hidden (the name tag still is).
- **Runs** record whether the helicopter flew (`helicopter`; it counts if it was ever up, also after a grounding); the leaderboard has no filter for it.

## Players

- **Car settings carry over:** your in-car switches (traction/stability control, drive mode, diff locks, 4WD range and anything else the car lets you toggle) are noted every few seconds during a round and put back on every car the mod spawns for you (new round, repaint, Apply). They are saved per car model in `settings/cnr_vehicle_modes.json` on your own PC, so they also survive a game restart. A car that doesn't have a setting just keeps its own default. Only driver settings carry over: traction and stability control, drive and control modes, gearbox mode and behaviour, diff locks and ranges, truck switches (lift axle, compression brake, retarder, hill assist), launch control and anti-lag, ride height and the light bar pattern. Physical state never does: doors, bonnet and boot, the frozen state, the current gear, the post-crash brake, fuel, suspension positions and tyre pressure.

- **Player settings:** the Settings button (lobby card or prep line) opens a card titled "Your settings" with the car colour, four switches and a choice. **Auto headlights** (on by default): your own round car gets low beam at night and in rain, storm, fog and snow, and the lights go off again at sunrise in clear weather; the mod only acts when something changes, so your own light key still works. **Siren** (off by default): as a cop, the light bar runs with siren once cops are released. The host's Cop sirens switch (`sirensAllowed`, on by default) grays out the Siren row ("Turned off by the host") and silences every cop without clearing anyone's own switch. **Searchlight beam** (on by default): off removes the helicopter's beam in the air on your game; the light and its glare stay. **Helicopter sound** (on by default): the police helicopter's rotor, heard from far off; off fades it out on your game. **Route to the runner** (as a cop): Always, Out of sight (default) or Never. All are saved in your own game (`settings/cnr_settings.json`) and apply on every server. Distances and speeds on the chase line and in How to play follow the game's unit setting (metric or imperial); the Host panel stays metric.
- **Per-player color:** the colour picker in the Settings card has a hex field, "No colour" and Done. The colour is applied to every round car. Set during prep, it repaints straight away; otherwise it applies from the next round. It is saved on the server per player.
- **How to play:** a five-tab card (Basics, Runner, Cop, Resets, Rules) that opens by itself the first time a player joins (remembered on their own PC in `settings/`) and from the How to play buttons. Every number in it comes from the server's current settings, so it matches the round; settings that are off read "no time limit" or "sight is off". With traffic on, Basics says how many traffic cars each player has and the crash line says driving into traffic counts. It hides itself during a round.
- **Identity:** players are recognised by their BeamMP account for the leaderboard, colors and who runs next. Guests are recognised by name, which changes every session.
- **Warnings:** a yellow line on the lobby card (or above its tab while the HUD is hidden) for a standing problem: no reset or recover button bound, an outdated copy of the mod, or a BeamNG.Earth that is too old. It stays until fixed: bind a reset button and the line goes within a couple of seconds. Without a reset binding, a round also starts with a warning notice.

## Leaderboards (saved permanently)

- Shown in the Cops and Robbers Leaderboard app, and the top 3 in the result card after each round.
- **Saved per run:** runner, time, map, car, the round's conditions (time of day, the worst weather of the round and the weather it started with, day length, date, whether weather affected driving), the traffic per player and whether it was for the runner only, end reason (caught, called, escaped, disconnect), catchers, every cop in the round with their seconds of sight, the runner's hidden time and how often they lost the cops, the car mode and build step, and a timeline of what happened (cops released, lost the cops, crash penalties, illegal resets, teleports, parts changes, the end).
- A cancelled round and a practice round are never recorded.
- **Fresh start in 1.7.0:** the leaderboard file has a new format. An older file is moved to `data/leaderboard-1.6.json` (kept, not used).

## Leaderboard app

- "Cops and Robbers Leaderboard" has the look of the game's multiplayer scoreboard: rows on dark cards, gold, silver and bronze rank badges, and your own row outlined in orange. Open it from the lobby card or Esc > UI Apps. It has a ✕, refreshes after every round and hides itself during a round.
- **Filters:** map (this map by default, all maps, or any map that has runs, shown with its real name), car mode (all, random, evolving) and traffic (all, traffic per player, traffic for the runner, no traffic; rounds from before traffic count as no traffic, and rounds with traffic from before 2.9.3 count as per player).
- **Runners:** each player's best survival time with the car (and the map when showing all maps). When you are not in the visible top, your own row is pinned at the bottom with your rank.
- **Cops:** catches per player, assists and the fastest catch.
- **Players:** runs, best, catches and assists per player; click a player for all stats and their last rounds:
  - **Runs, best and average survival, escapes** (outlasted the time limit).
  - **Catches:** rounds credited with the catch.
  - **Assists:** caught rounds where the cop had sight of the runner for at least `assistMinSightPercent` (20%) of the chase without being credited. Sight counts from the release, so seeing the runner at the start alone only earns an assist in a very short chase. Changing the setting re-scores past rounds.
  - **Hidden from cops:** the share of their chases the runner spent out of every cop's sight.
  - **Lost the cops:** how often they broke all cops' sight.
  - Rounds played with sight off (`sightMaxMeters = 0`) show "–" for the last two.
- **Rounds:** every recorded round, newest first, grouped by day. Each row shows how it ended, who ran and who caught them, the time of day, car (followed by the conditions, for example "Gavril D-Series · Night · Rain · Traffic") and build step, the survival time, and a yellow line for anything that went wrong ("Kim reset illegally"). Click a round for its timeline and each cop's share of the chase with the runner in sight; its heading names the traffic ("Traffic: 5 per player", or "Traffic: 5 for the runner"). Rounds saved before the timeline existed show only the result. Long lists load more with "Show more".

## Traffic

- **Around every player:** during a round each player's game runs `trafficPerPlayer` AI traffic cars (5 by default, 0 = off) around itself with the game's own traffic system, so there is traffic wherever anyone drives. With Traffic for the runner only (`trafficRunnerOnly`), only the runner's game spawns it, with the same count, and cops spawn none, for better performance; practice rounds keep their traffic, except a practice you watch while sitting out, which has none.
- **Capped by `MaxCars`:** the server leaves room for the round car (and the two AI cars in practice), so with `MaxCars` 4 a player gets 3 traffic cars. The panel says when the cap applies.
- **In the round:** traffic spawns once a player's car is placed in prep and stands still until the runner's GO, so it can't drive into the frozen cars. A player who joins mid-round gets traffic that drives at once. Everyone's traffic is removed at the end of the round, on Cancel and on leaving. If a game can't spawn its traffic, that player gets one notice ("Traffic could not spawn") and the round goes on.
- **Which cars:** official vehicles only, never police, emergency vehicles, taxis or other service vehicles (security cars, prison buses, tow trucks), and no random traffic events. Traffic cars have no name tags, so every car with lights is a cop and every name tag is a player, also for players in the lobby watching someone's practice round.
- **Lights:** traffic drives with its headlights on while it rains, storms, fogs or snows, and follows the weather as it changes. At night it follows the game's own rule (lights on from sunset, and in tunnels), which also thins traffic out at night; traffic standing still before GO is lit at night too.
- **Weather:** traffic slows down on wet roads and snow by itself, and gusts push it like any car.
- **Crashes:** see Crash penalty. Traffic never helps catch the runner.
- **Not on BeamNG.Earth yet:** BeamNG.Earth manages any traffic that runs, so traffic stays off there and the panel says so.

## Night and weather

- **Settings:** a Sky group in the panel: Time of day, Night chance, Day length, Weather, Bad weather chance, Weather affects driving, Weather changes and the shortest and longest time between changes. Time of day and Weather are a fixed choice or random (random by default); every round sets the sky.
- **Random:** with Time of day on random, a roll under the night chance gives night, otherwise sunrise, morning, noon, afternoon or sunset. With Weather on random, a roll under the bad weather chance gives rain, storm, fog or snow, otherwise clear or cloudy. Both chances are 25% by default, so hard rounds stay occasional.
- **Same for everyone:** everyone in a round gets the same time, weather, rain or snow, and wind, also a player who rejoins mid-round. The game's environment menu is locked during the round. Practice rounds get a sky too, and the AI cars switch their headlights on at night.
- **New sky:** a button next to New car in prep, only while time or weather is random. It picks new values without re-placing the cars. New car keeps the sky; each new round picks again. Press it several times quickly and the sky heads for the last pick.
- **Clock:** with Day length Off the clock is stopped. Otherwise it stays stopped in prep and starts at GO, so the round starts in the time you saw, and a full day lasts the chosen length: Fast 15 min, Moderate 30 min (the default), Slow 2 h or Realtime 24 h, the game's own presets. With the clock moving, every named time (sunrise to night) is set a little early, so the round reaches it during the chase: one game hour, but never more than 75 s of real time (a full hour at Fast and Moderate, 15 game minutes at Slow, about a minute at Realtime). A sunset round starts in daylight instead of going dark at once; a sunrise round starts just before dawn.
- **Date:** each round gets a date that fits its weather: snow in December or January, fog in October or November, rain and storms in March, April, October or November, clear and cloudy any day. On a map south of the equator (Automation Test Track) the date moves six months, so snow still comes with short winter days. It sets sunrise, sunset and how long the night lasts, it is the same for everyone, and it shows on the prep card and in the New sky message ("Sunset · Snow · 14 Dec").
- **Grip:** with Weather affects driving, rain turns asphalt and gravel wet and dirt to wet gravel; grass and rumble strips lose a little grip. A storm also turns dirt into mud. Snow covers everything you drive on. These are the game's own surfaces, so tires matter: drag tires slide more on wet roads than road tires. Clear, cloudy and fog change no grip. Surfaces the mod doesn't know (a mod map's own) stay dry. When the weather changes, grip changes with it: it gets wet (or snowy) gradually over the minute-long change (the game's ground models are updated each time the blend has moved 5 %, and when it reaches its target), so full wet grip comes with full rain, and it dries over 3 minutes after the rain or snow has stopped. A player who joins mid-round gets the grip in effect at that moment.
- **Shelter:** rain and snow stop in tunnels, under bridge decks and under canopies: 4 times a second the game looks up from the camera, and when there's a roof within 12 m straight above and cover on both sides (front or back, and left or right), the rain is hidden until you're back in the open. It switches after half a second. Street-light arms and traffic-light gantries cover one direction only and don't count. Under a high bridge it keeps raining.
- **Wind:** realistic strengths: rain 5 m/s gusting to 8, snow 4 gusting to 6, a storm a 17 m/s gale gusting to 26. Gusts last a few seconds, turn up to 15° (30° in a storm), and come at the same moment for every player.
- **Temperature:** follows the weather and the round's month, on every map, through our own day curve. Each game day has its own low (at 06:00) and high (at 14:00): the month's normal range, shifted by a warm or cold spell (up to 4 °C on the first day, then drifting by up to 3 °C a day, never beyond 6 °C) and by the weather around it, so a clear evening gives a colder night than a cloudy one. A December snow round reaches about -8 to 0 °C, an April rain round around 10 to 13 °C and a clear July day around 20 to 31 °C, and later days differ. The game's temperature follows the server's day curve, so it never jumps. The prep line and the New sky message end with the day's range ("Night · Snow · 14 Dec · -4 to 0 °C"), in °F when the game is set to Fahrenheit.
- **After the round:** sky, date, grip, wind, temperature and the environment menu go back to what each player had, at the end, on cancel and on leaving. A map change drops it without applying anything.
- **Prep line:** shows the conditions after the car, for example "Gavril D-Series · Night · Snow · 14 Dec · -4 to 0 °C".
- **Blends:** at round start, on New sky and at round end the sky blends over up to 3 s (clouds, fog and time of day). Every change blends from where the sky is. Pressing GO right after New sky lands the sky at once and the clock starts. A rejoin after GO gets the sky at once, and leaving the server ends everything at once.
- **Rain and snow:** they fade in and out with the blend. Rain falls like the stock maps' rain; a storm has faster, bigger and more drops. Snow is unchanged.
- **Rain sound:** the game's own rain loop plays during rain and storm, louder in a storm, at half volume under a roof, and fades with the rain.
- **Weather changes:** with Weather changes on (`weatherChanges`, on by default; no effect on BeamNG.Earth or in a round with no weather) the weather changes during the chase. The server works out the whole schedule when the round or New sky picks the sky, so it is the same on every game, also for a rejoin. It runs to the time limit or 3 hours, whichever comes first.
  - **When:** the first change comes after the cops are released, then each one a random time later, between `weatherChangeMinMinutes` (3) and `weatherChangeMaxMinutes` (8) minutes. The panel keeps the longest at or above the shortest, and the settings show only while Weather changes is on.
  - **Only into a fitting weather:** clear goes to cloudy (or fog in foggy conditions: 12 °C or colder, from 18:00 to 09:00). Cloudy goes to clear, to rain from 2 °C up, to snow at 1 °C or below, or to fog. Rain goes to cloudy, to a storm on a warm day (the day's current turning points reach 15 °C), or to snow at 1 °C or below. A storm eases to rain. Snow goes to cloudy, or to rain from 2 °C up. Fog goes to cloudy or clear. Each is equally likely among the ones allowed.
  - **Crossings come at once:** when the temperature crosses a line, the change happens at that moment, between the regular ones: snow turns to rain at 2 °C, rain to snow at 1 °C (a storm that cold eases to rain first), and fog lifts above 12 °C or at 09:00. The next regular change comes after it by the usual time.
  - **The change:** it takes a minute. Clouds, fog and wind blend over it, rain and snow fade in and out, the grip follows (see Grip) and the helicopter's beam and the lights follow the weather. The environment menu stays locked.
  - **Notices:** a change shows a notice for 4 s, like New sky: "Weather: rain coming", "Weather: the rain is getting heavier", "Weather: the storm is easing", "Weather: clearing up", "Weather: clouds coming in", "Weather: fog rolling in", "Weather: snow coming", "Weather: the rain is turning to snow" or "Weather: the snow is turning to rain".
  - **Forecast:** players and spectators see the next change on a line under the round clock, never wrong, because the change always lands inside the window: "Forecast: rain in 3-5 min" (or "within 3 min" in the last minutes), then "Forecast: rain any minute" from when the window starts, up to two minutes before the change. While a change runs, the line shows the next one, or none. With the helicopter on, a second part says what the change does to it: "(helicopter grounded)" when it goes to storm, fog or snow, "(helicopter returns)" when it comes from one. Prep shows the first change after the sky: "Forecast: rain 5-7 min after release". New sky draws a new schedule and forecast. Practice shows it too.
  - **Lights:** traffic headlights follow the current weather, on in rain, storm, fog and snow and off again when it clears, and the practice AI cars light up in bad weather. Your own auto headlights already followed it.
  - **Records** keep the worst weather of the round as `weather` (clear, cloudy, rain, fog and snow, storm, in that order) and the start weather as `weatherStart`. The label and the filters use `weather`.
- **No thunder:** the game has no lightning or thunder in this version.
- **Not on BeamNG.Earth:** the server sends no sky there, and the panel says so.

## Test rounds against AI (only you see them)

| Command | You | AI |
|---|---|---|
| Practice as runner | Runner (red) | Two cops (blue) that chase you |
| Practice as cop | Cop (blue) | A runner (red) that flees, plus a partner cop (blue) |
| Practice: watch the AI (Sit out on) | Spectator | A runner (red) that flees from the nearest cop, plus two cops (blue) that chase it |

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
- **Lobby card** (between rounds): "Cops and Robbers", the number online, "Waiting for the host to start a round" or "Practice round: Bob", and the buttons Settings, How to play, Leaderboard, Host panel and Hide (Leaderboard and Host panel open and close those apps and show when they are open). Standing problems show as a yellow line.
- **Hide:** for players just driving between rounds. It folds the lobby card into a small "Cops and Robbers" tab with an up arrow at the same place, and clicking the tab brings the card back. Notices and the yellow warning lines still show above the tab, an open Leaderboard or Host panel stays open, and Settings opens only from the full card. The choice is saved with the personal settings (`hudHidden` in `settings/cnr_settings.json`), so it lasts over a restart and a rejoin. Prep, the chase and the result (also of your own practice round) always show in full, and the lobby after them goes back to your choice.
- **Prep:** the role in the centre ("YOU'RE THE RUNNER" in red, "YOU'RE A COP" in blue, with "Bob is the runner" for cops) and the car's name, no rule text. At the bottom "Waiting for the host to press GO" with Settings, How to play and Host panel buttons.
- **Chase line:** role chip, survival time (`3:12 / 10:00` with a time limit), SPOTTED or HIDDEN for the runner (IN SIGHT, live or last seen for cops), the nearest cop or the cop's distance and direction (for a last-seen point also how long ago it was seen), and the reset status ("Reset ready", "Stay still 4 s to reset", "Can't reset while being caught"). The distance is shown in the mono font. No key is named, because players use different reset buttons. Pressing reset when it is not allowed briefly highlights the line.
- **Catch bar:** shown while the catch timer is running. It is red with "BEING CAUGHT" for the runner and blue with "HOLDING RUNNER" for cops, uses 1% steps, and moves smoothly between server updates.
- **Countdowns:** "RUNNER STARTS IN", "COPS RELEASED IN" and "CRASH PENALTY" over a large number; then "GO! RUN!" (runner), "GO!" (cops) and "PENALTY OVER", each for 2 s. During the head start the runner's chase line shows "Cops released in N".
- **Notices:** an icon and one line above the chase line (or the lobby card or its tab), 4 s each, at most 2 at once. Yellow for rule breaks and personal warnings ("Bob: crash penalty 10s", "Ann reset illegally", "Ann teleported", "Ann changed parts during the round: engine, intake", "Only the round car is allowed", no road found, could not spawn AI, no vehicles), white for information (build changes).
- **Result:** shown for about 10 s after a round. The title (RUNNER CAUGHT, ROUND ENDED, ESCAPED, RUNNER LEFT, ROUND CANCELLED), the runner's time, who caught them (or, for a cancelled round, why: "Runner left, round cancelled"), the map's top 3 with your row outlined, and "Next round in N" when Automatic rounds is on. Leaving the server clears it.
- **Evolving mode:** during prep the bottom shows the runner's queued change as a card ("Your change" or "Bob's change") with Apply change for the runner only; after Apply the centre shows APPLYING CHANGES.
- **Format:** Vue 3 apps built on the game's own components, colours and fonts (see `docs/DEPENDENCIES.md`).

## Control panel (UI app)

- **Who:** "Cops and Robbers Panel" is for whoever runs the game. It never opens by itself: use the Host panel button on the lobby card or the prep line, or Esc > UI Apps. The server does not check who uses it. It has the version in its header and a ✕.
- **Four tabs:** Round, Car, Map, Settings.
- **Round tab** shows only what can be done now, with one main button for the next step and a yellow line saying why it can't happen yet:
  - **No round:** the status, the map's real name and the car mode, the player list as the runner picker (runs this session, "next" and "last" marks, and a Random runner row), **Start round with Bob**, Practice as runner / as cop (while you sit out, one **Practice: watch the AI** button instead), and the Automatic rounds switch with its delay.
  - **Prep:** the runner and the car's name (or build step), the players with their role and state (ready, changing, missing parts; display only), **GO** (disabled with the reason, for example "Waiting for Bob to apply the change"), New car (random mode) and Cancel round.
  - **Countdown, head start, chase:** the panel folds into a bar with the phase, the runner, **End chase** and **Cancel** (a second click during the chase), and ▾ to open it. It folds by itself on GO and opens again when the round ends.
  - **Someone's practice round:** the practice's own controls, plus the runner picker and **Start round with Bob** under "Start a real round" (starting one ends the practice).
  - **After a round:** the result line ("Bob caught after 8:41"), and with automatic rounds on, "Next round in 12 s with Kim" with **Start now** and **Stop automatic rounds**.
  - A reply line shows the server's answer to every click, in yellow when it refuses ("Stop the round first", "Only the runner can apply the change", "Not available from the panel"). Nothing goes to chat.
- **Car tab:** a Random car / Evolving build switch. In evolving mode a summary (car, build step, last change and who made it), New build (choose a car, or random; a second click when a build exists) and Reset build (a second click). For both modes: Include mod cars and the excluded cars. Locked during a round.
- **Map tab:** "West Coast USA · 10 gas stations", **Add station here**, **Remove nearest** (disabled with "No station within 50 m to remove") and the nearest stations with their distance (flat distance on BeamNG.Earth, updated every 2 s while the tab is open). Works on BeamNG.Earth, where stations are also discovered automatically.
- **Settings tab:**
  - Every setting has a one-line explanation. The common ones come first (Head start, Time limit, the Sky choices, Traffic and, while traffic is on, Traffic for the runner only, Hold time, Catch distance, Reset wait, Crash penalty); the rest are under More settings, grouped into Round, Sky, Catching, Resets, Crashes, Cops and Cars. Traffic reads "5 per player", or "5 for the runner" with Traffic for the runner only on, and has a line under it with what it costs ("5 each · 30 cars with 6 players", or "5 cars in all with 6 players" for the runner only) or how `MaxCars` caps it. On BeamNG.Earth the Sky and Traffic groups say "Not available on BeamNG.Earth yet" instead. A setting the panel doesn't know yet appears under "Other".
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
| `resetWaitSeconds` | 7 | Stand still this long to reset anywhere; rocking in place (within 3 m) still counts |
| `stillMaxSpeedKmh` | 1 | "Standing still" threshold; it only sets where the 7 s wait starts, after that staying within 3 m counts |
| `gasStationRadiusMeters` | 25 | Gas station reset area |
| `copResetMinDistanceMeters` | 1000 | Cops this far from the runner may always reset and get no crash penalty |
| `copSpawnMinMeters` / `copSpawnMaxMeters` | 50 / 150 | Cop start distance from the runner, by road |
| `crashSpeedLossKmh` | 50 | Speed lost within 0.5 s that counts as a crash |
| `crashPenaltySeconds` | 10 | Freeze for the cop at fault, within `copResetMinDistanceMeters` of the runner |
| `helicopter` | true | Police helicopter that searches for the runner and tracks them while it sees them; grounded in storm, fog and snow until the weather clears |
| `helicopterArrivalSeconds` | 60 | It arrives this long after the cops are released (0 = at release) |
| `helicopterUpSeconds` | 120 | How long it flies before it refuels (more than 0) |
| `helicopterRefuelSeconds` | 90 | How long it is away refuelling (0 = stays up) |
| `sightMaxMeters` | 400 | How far cops can see the runner (0 = sight off) |
| `sightLiveIntervalSeconds` | 1 | Live runner position for all cops while one sees the runner (at least 3 s on BeamNG.Earth) |
| `sightNoRouteSeconds` | 5 | A cop who sees the runner within their speed × this many seconds gets no route (with the default Out of sight route setting) |
| `sightNoRouteMinMeters` | 50 | ...and always within this distance |
| `carMode` | random | `random` (a random car each round) or `evolving` (the shared build) |
| `sightGraceSeconds` | 1.5 | Sight still counts this long after a cop loses it |
| `assistMinSightPercent` | 20 | Share of the chase a cop needs sight of the runner for an assist |
| `roundTimeLimitSeconds` | 0 | Runner escapes after this long (0 = no limit) |
| `autoNextRound` | false | Prepare the next round automatically |
| `autoNextDelaySeconds` | 15 | Delay before the next round is prepared |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Models that are never picked |
| `explodeOnCatch` | false | The runner's car explodes when caught, and every player in the round sees it explode (not the AI runner in practice, which is removed at once) |
| `includeModVehicles` | false | Also pick mod vehicles |
| `timeOfDay` | random | `sunrise`, `morning`, `noon`, `afternoon`, `sunset`, `night` or `random` |
| `nightChancePercent` | 25 | Chance of night when Time of day is random |
| `dayLength` | moderate | How long a full day lasts during the chase: `off` (stopped), `fast` (15 min), `moderate` (30 min), `slow` (2 h) or `realtime` (24 h) |
| `weather` | random | `clear`, `cloudy`, `rain`, `storm`, `fog`, `snow` or `random` |
| `badWeatherChancePercent` | 25 | Chance of rain, storm, fog or snow when Weather is random |
| `weatherDriving` | true | Weather changes grip and adds wind (not on BeamNG.Earth) |
| `weatherChanges` | true | The weather changes during the chase, only into a weather that fits the temperature and time of day (not on BeamNG.Earth) |
| `weatherChangeMinMinutes` | 3 | The least time between two weather changes, in whole minutes (at least 1) |
| `weatherChangeMaxMinutes` | 8 | The most time between two weather changes (never below the minimum) |
| `sirensAllowed` | true | Cops may use a siren (each cop turns it on in their settings) |
| `trafficPerPlayer` | 5 | AI traffic cars around each player during a round (0 = off, at most 20; normal maps only) |
| `trafficRunnerOnly` | false | Only the runner's game spawns traffic, with the same count |

## Host and robustness

- **Install:** players install nothing. The server needs the plugin in `Resources/Server` and the zip in `Resources/Client`.
- **Mods panel:** the zip carries a title, description, version and icon (`mod_info`) for mod panels.
- **Stuck controls:** Cancel always unlocks everyone, and so does a plugin restart.
- **Bad files:** a broken `config.json` gives a warning and uses the defaults. A broken or malformed leaderboard is moved aside.
- **Tests:** The automated tests cover the rules, the server wiring and the client, which runs against stubbed game functions in `tests/test_client.lua` (run with `make test`).
