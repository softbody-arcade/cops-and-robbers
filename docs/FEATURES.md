# Cops and Robbers 1.5.0: features

A BeamMP server plugin with a client mod that BeamMP downloads automatically. The mod enforces the group's cops-and-robbers rules. It is one mod for every map, and it switches to geo mode on BeamNG.Earth by itself.

## Round flow

| Step | What happens |
|---|---|
| `/cnr start <runner>` | Picks a random car and config. Everyone gets the same one. Cops are placed on a road 50–150 m from the runner. Everyone is frozen. |
| Prep | No time limit. Players may change paint only. A parts or tuning change puts the car back to the round setup. `/cnr reroll` picks a new car. |
| `/cnr go` | "Runner starts in 3", then the runner is released. |
| Head start | Cops stay frozen for 7 s and see a countdown. |
| Chase | Cops are released and the survival clock starts. A status line shows `time \| reset status \| distance info`. |
| End | The round ends when the runner is caught, on `/cnr end`, when the time limit runs out, or when the runner disconnects. The run is recorded and the top 5 for the map is shown. |
| Automatic next round | Optional (`/cnr auto on`). The next round is prepared with whoever has run least. It still waits for `/cnr go`. |

### Choosing the runner
- `/cnr start <name>`: case-insensitive. A unique prefix is enough, and ambiguous names give an error.
- `random`, `next` (whoever has run least this session), and `again` (the same runner).

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
- **Menus:** the vehicle selector and the vehicle debug menu. Vehicle config is allowed only during prep, for paint.
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

- **Light bar:** cops drive with the light bar on, with no siren. When the round car has no light bar, cops get the light bar parts from a police config of the same model.
- **Last seen:** every 30 s cops get the runner's last position:
  - **Normal maps:** a route line on the road and minimap, plus "Runner seen 640 m NE".
  - **BeamNG.Earth:** a destination in BeamNG.Earth's own GPS ("Runner last seen"). The status line shows the distance by road, for example "Runner 2.4 km by road NE".
- **Runner:** sees "Nearest cop 1.2 km".
- **Cop placement:** cops are spread out so they do not overlap. The search widens up to 2 km when no road is near. If no road is found at all, there is a message and the cop starts where they are.
- **Late joiners and reconnects:**
  - Someone who joins mid-round becomes a cop.
  - A cop who reconnects comes back near the road where they left.

## Players

- **Per-player color:** `/cnr color #ff0000` (or `off`) is applied to every round car. Set during prep, it repaints straight away; otherwise it applies from the next round.
- **Identity:** players are recognised by their BeamMP account for the leaderboard, colors and `start next/again`. Guests are recognised by name, which changes every session.
- **Warnings:**
  - a message at round start when no reset or recover button is bound
  - a message when a player's cached copy of the mod is outdated

## Leaderboards (saved permanently)

- `/cnr top`: best runners on the current map.
- `/cnr top all`: best runners across all maps.
- `/cnr top <map>`: best runners on that map.
- `/cnr top cops`: catches and fastest catch per cop.
- **Saved per run:** runner, time, map, car, end reason (caught, called, escaped, disconnect) and catchers.
- A cancelled round (`/cnr stop`) and a test round are never recorded.

## Test rounds against AI (only you see them)

| Command | You | AI |
|---|---|---|
| `/cnr test runner` | Runner (blue) | Two cops (green, red) that chase you |
| `/cnr test cop` | Cop (green) | A runner (blue) that flees, plus a partner cop (red) |

- All rules apply, including crash penalties for the AI.
- Leaving the server, or another player using `/cnr start`, ends the test round.
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

- **Placement:** "Cops and Robbers HUD" is added automatically at bottom centre of the current UI layout on join. That includes BeamNG.Earth's MP layout after it switches. The app can be moved and resized, and it is removed from the layout again when leaving the server.
- **Status line:** during the chase it shows `ROLE  m:ss | reset status | distance info`.
- **Catch bar:** shown while the catch timer is running. It is red with "BEING CAUGHT" for the runner and blue with "HOLDING RUNNER" for cops, uses 1% steps, and moves smoothly between server updates.
- **Countdowns:** "RUNNER STARTS IN 3", "COPS RELEASED IN 7" and "CRASH PENALTY 10", with a large number.
- **GO flashes:** "GO! RUN!", "GO!" and "PENALTY OVER", each shown for 2 s.
- **Prep line:** your role, the car's name, and "waiting for "/cnr go"".
- **Reset feedback:** pressing reset when it is not allowed briefly highlights the reset part of the status line.
- **Event line:** for example "Bob: crash penalty 10s", shown for 4 s, at most 2 at once.
- **Result card:** shown for 10 s after a round. It contains the title, the runner and their time, who caught them, the top 3 for the map, and "Next round in N" when `/cnr auto` is on.
- **Fallback:** when the app is not in the current layout, the old pop-up messages are used. Chat stays the record, and rare warnings stay pop-ups.
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
  - The reply line confirms each save ("Saved: Head start 8 s"). Saves don't post to chat.
  - "Reset to default" needs a second click within 3 s.
  - Settings are locked during a round ("Stop the round first").
- **Live:** the panel follows changes made by anyone, including chat commands, within a quarter of a second.

## Key bindings

Options > Controls > Gameplay contains "Cops & Robbers: ..." actions that can be bound to wheel buttons. Nothing is bound by default.

| Action | Same as |
|---|---|
| Next step (set up / go) | `/cnr continue`: sets up a round with the next runner, or starts it during prep |
| Start round: next / same / random runner | `/cnr start next` / `again` / `random` |
| Go | `/cnr go` |
| New car | `/cnr reroll` |
| End chase (record time) | `/cnr end` |
| Cancel round | `/cnr stop` |
| Automatic rounds on/off | `/cnr auto` |
| Leaderboard | `/cnr top` |
| Practice as runner / cop | `/cnr test runner` / `cop` |

## Commands

| Command | |
|---|---|
| `/cnr start <name\|random\|next\|again>` | Set up a round |
| `/cnr reroll` | New car during prep |
| `/cnr go` | Start the countdown |
| `/cnr continue` | Next step: set up a round, or start it |
| `/cnr end` | End the chase and record the time |
| `/cnr stop` | Cancel without recording, and unlock everyone |
| `/cnr auto on\|off` | Prepare the next round automatically |
| `/cnr color <#hex\|off>` | Your car color |
| `/cnr test <runner\|cop>` | Practice round against AI |
| `/cnr top [cops\|all\|<map>]` | Leaderboards |
| `/cnr set <setting> <value>` | Change a setting (saved; only when no round is running) |
| `/cnr config` / `/cnr reload` | Show settings / reload `config.json` |
| `/cnr addstation` / `/cnr removestation` | Edit gas stations |
| `/cnr version` / `/cnr help` | Version / command list |

## Settings (`config.json`, or `/cnr set`)

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
| `roundTimeLimitSeconds` | 0 | Runner escapes after this long (0 = no limit) |
| `autoNextRound` | false | Prepare the next round automatically |
| `autoNextDelaySeconds` | 15 | Delay before the next round is prepared |
| `excludedModels` | citybus, us_semi, md_series, percheron, rockbouncer | Models that are never picked |
| `explodeOnCatch` | false | The runner's car explodes when caught |
| `includeModVehicles` | false | Also pick mod vehicles |

## Host and robustness

- **Install:** players install nothing. The server needs the plugin in `Resources/Server` and the zip in `Resources/Client`.
- **Mods panel:** the zip carries a title, description, version and icon (`mod_info`) for mod panels.
- **Stuck controls:** `/cnr stop` always unlocks everyone, and so does a plugin restart.
- **Bad files:** a broken `config.json` gives a warning and uses the defaults. A broken or malformed leaderboard is moved aside.
- **Tests:** 217 automated tests cover the rules and the server wiring (run with `make test`).
