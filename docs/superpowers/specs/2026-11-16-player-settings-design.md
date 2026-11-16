# Player settings card

Status: approved 2026-11-16, with the host's Cop sirens switch added at approval. Replaces the HUD's colour card with one card for a player's own options. Builds on the HUD app (`2026-11-15-hud-app-design.md`) and changes one decision from night and weather rounds (`2026-11-16-night-weather-design.md`): the mod still never switches a player's headlights on by itself, but a player can now ask it to.

## Why
- A player's own choices should live in one place. Today the only one is the car colour, behind a Colour button in the lobby card and on the prep line.
- Night and weather rounds made headlights matter, and the mod leaves them to the player. A player who wants them handled should be able to say so once.
- Cops drive with lights and no siren, and the mod puts "lights only" back every 2 s, so even the game's own siren key is cut off. A cop who wants a siren has no way to get one.
- Chase distances show in metres and kilometres only, also for players whose game is set to imperial.

## Goals
- **One settings card** in the HUD, opened from a **Settings** button that replaces the Colour button in the lobby card and on the prep line. It holds:
  - **Car colour:** today's colour picker, unchanged in what it does.
  - **Auto headlights** (on by default, changed from off after the build, 2026-11-16): your round car's headlights come on at night and in rain, storm, fog and snow, and go off when neither applies.
  - **Siren** (off by default): as a cop, your light bar runs with its siren once cops are released.
- **Host switch: Cop sirens** (on by default) in the Host panel's Settings tab. Off grays out the Siren option on every player's card and silences every cop, also those who had their Siren switched on (asked for at approval, 2026-11-16).
- **Units follow the game.** Every distance and speed the mod shows players follows the game's own unit setting (metric or imperial): the HUD and How to play. No switch on the card. The Host panel stays metric.
- **Folded-in issues** (their TODO lines go when this merges):
  - Colour picker: the lobby card and the prep line each have their own `HudColor`, so a hex typed in the lobby is lost when prep starts. One card fixes it.
  - HUD styles repeated across components: the `.hud-btn` and `.swatch` part (HudLobby, HudPrep, HudColor) moves into the shared kit. The rest of that issue (`.title`, `.tone-*`, `.mono`, the root containers) is in the Announcements app and the chase line, which this work doesn't restyle, so it stays in TODO with the line shortened.
  - Chase line distances ("Runner 640 m NE") use the display font, not the mono font, because they arrive inside one text (`HudChase.vue` `info-text`). Units rewrite exactly this text, so the distance now arrives on its own (see Units) and shows in the mono font.
  - README says "Everything is clickable with the mouse cursor shown" without saying how a player shows the cursor. The Settings card is one more thing players have to click, and the README's HUD lines change anyway, so the line gets the game's actual control (checked in game).

## Non-goals
- Sit out rounds and a runner preference. Both are separate Ideas in TODO.md.
- The card during the chase. It opens in the lobby and in prep only, like the colour card today. During the chase the game's own light key still works.
- Auto headlights outside rounds. In the lobby the car and the sky are the player's own business.
- Lights or siren for practice AI cars or traffic. Their rules stay as they are.
- A units switch on the card. The game's setting is the switch.
- Imperial in the Host panel (decided 2026-11-16). Its Settings tab edits config values stored in metric with +/- steppers, which don't round well in feet or mph; its Map tab's station distances and the server's "No gas station within 50 m" reply stay metric too. No server change.

## Anti-goals
- The mod fighting the player over lights. Auto headlights act only when something changes (car placed, night starts or ends, the weather changes). They never re-send every second the way traffic lights do. A runner who switches the lights off to hide keeps them off until the next change.
- A siren during prep, the countdown or the head start, when every cop is standing still on the same road.
- Losing an unsaved colour when the round moves from lobby to prep.

## Approaches
**Where the settings are saved** (picked: A)
- **A. In the player's own game (picked).** Headlights and siren go in `settings/cnr_settings.json` in the game's user folder, next to the How to play "seen" file (`settings/cnr_help_seen.json`). The colour stays on the server (`data/colors.json`), because the server paints everyone's round cars and needs it even while the player's game is closed. The switches work instantly with no server change, and they apply on every server running the mod. They don't follow the player to another PC.
- **B. Everything on the server.** `colors.json` becomes a per-player settings store. The settings follow the player to another PC on that server, but this needs new server events, a migration of `colors.json`, and a round trip for every switch. Nothing on the server uses headlights or siren.
- **C. Colour moves to the player's game too, sent on join.** Rejected: the server would lose colours for players who aren't online, and existing `colors.json` entries would be dropped.

**The card's layout** (picked: 1)
- **1. One card, colour on top, switches below (picked).** Today's picker stays as it is, with two switch rows under it. Everything is visible at once.
- **2. Tabs (Colour / Car).** Smaller, but it hides the switches behind a tab for the sake of two rows.

## Design

### The card
```
┌ Your settings ──────────────────────────────── ✕ ┐
│ CAR COLOUR                                       │
│ [ colour picker (compact, with luminosity)     ] │
│ [■] [#2FB36B ]  [No colour]                      │
│ ──────────────────────────────────────────────── │
│ Auto headlights                           [ ◯ ] │
│ On at night and in bad weather                   │
│ Siren                                     [ ◯ ] │
│ As a cop, once cops are released                 │
│                                         [ Done ] │
└──────────────────────────────────────────────────┘
```
- **Opening:** the lobby card and the prep line show **Settings** in place of **Colour**. The colour swatch stays inside the button, so your colour is still visible at a glance. While the card is open it takes the place of the lobby card or the prep line, as the colour card does today.
- **One instance:** `app.vue` renders the card once, whether you opened it from the lobby or from prep. An open card stays open with its typed hex when the round moves from lobby to prep. If the HUD briefly has neither a lobby nor a prep payload between the two, the draft must survive that too (keep it in the app, not only in the card).
- **Closing:** the card closes on ✕ or Done, and when it isn't allowed any more (the chase starts, the HUD hides), as today.
- **Colour:** works as today. The picker and the hex field edit a draft. **Done** saves the draft colour if it's valid and changed, then closes. While the hex field holds something invalid, Done is disabled and the "Use six hex digits" hint shows. **No colour** clears the saved colour at once (the swatch empties) and leaves the card open. ✕ closes without saving the draft. In prep a saved colour still repaints straight away, and otherwise applies from the next round.
- **Switches** (the game's `BngSwitch`, as in the panel) save the moment they flip. They take effect as described below.
- **Title:** "Your settings", so it can't be mixed up with the Host panel's settings.

### Saving the switches
- The client reads `settings/cnr_settings.json` when the extension loads. A missing or broken file, or a missing or non-boolean value, means Auto headlights on and Siren off. The client writes the file on every change.
- The HUD feed carries the current switch values (next to `color`), and the card sends `{ action = "setting", key = "headlights" | "siren", value = true | false }` through `copsAndRobbers.ui`. Unknown keys and values that aren't booleans are ignored.

### Auto headlights
- **Wanted state:** lights are wanted when the switch is on, you have a round car (normal or practice round, any phase), and it is night (`sky.isNight()`) or the round's weather is rain, storm, fog or snow (the same list `traffic.lua` uses).
- **When the mod acts:** it only acts when something changes, never on a timer that re-sends:
  - **Your round car is placed:** at the start, on New car, after an evolving rebuild, or when you rejoin mid-round. A fresh car has its lights off, so if lights are wanted the mod switches on low beam.
  - **Lights become wanted mid-round** (sunset, or New sky to bad weather): low beam on, unless they're already on. Main beam stays main beam.
  - **Lights stop being wanted mid-round** (sunrise in clear weather, or New sky to clear by day): lights off.
  - **The switch is flipped during prep:** on applies the wanted state now. Off leaves the lights as they are.
- **What stays the player's:** between those moments the game's light key works as normal. A vehicle reset keeps the light state (the game's `electrics.reset` doesn't touch it), so a reset needs no action.
- **Round end:** the mod leaves the lights as they are. The car goes back to the player.
- **Checking for changes:** about once a second the mod checks whether lights are wanted, reusing the client's existing update loop. It sends a command only when the answer changes or a car was just placed.
- **BeamNG.Earth:** the mod sets no sky or weather there, so only night counts, as far as `core_environment.getLightState()` reports it. Check in game.

### Siren
- With the switch on, a cop's light bar runs with siren (`electrics.set_lightbar_signal(2)`) from the moment cops are released (client phase `running`) until the round ends. Before that it stays lights only (`1`), as today.
- The client's 2-second lights loop (`updateLightsAndPatch`) sends `2` instead of `1` while the siren is wanted, so the mod keeps the state it chose. The game's siren key is still overridden, as today: the switch is the control.
- Flipping the switch in prep takes effect at release. The runner, practice AI cops and traffic are unchanged. At round end the light bar goes off as today (`LIGHTS_OFF`).

### Host switch: Cop sirens
- **Config:** `sirensAllowed` (boolean, default `true`) in `cnr/config.lua` `DEFAULTS`, validated like the other booleans (`explodeOnCatch`, `weatherDriving`).
- **Panel:** a bool row in the Settings tab's **Cops** group: label "Cop sirens", help "Cops may turn a siren on in their settings; off keeps every cop silent". Like every panel setting it saves only between rounds ("Stop the round first" during a round), so it never changes mid-chase.
- **To the players:** `sirensAllowed` joins `rules.KEYS`, so it travels in `cnr_rules`, which is already pushed to everyone after a save and to each player who joins.
- **The card:** while sirens are not allowed, the Siren row is grayed out and can't be flipped. Its switch shows off, and its sub-text reads "Turned off by the host".
- **The client:** the siren is wanted only when the player's switch is on **and** `sirensAllowed` is true. Otherwise the lights loop sends lights only (`1`) to every cop, whatever their switch says.
- **The player's own choice is kept, not cleared.** The switch lives in the player's game and applies on every server (Approach A). If one host's rule wiped it, it would be off on other servers too. While sirens are off on this server the switch shows off and grayed. When the host allows them again, the player's own choice is back.
- **How to play:** the Siren line shows only while sirens are allowed.

### Units
- The client reads the game's length unit (`settings.getValue("uiUnitLength")`: `"metric"` or `"imperial"`, metric if missing or unknown) each time it builds a feed. A change in the game's options shows up within a second, with no rejoin.
- **Metric** stays exactly as today: `640 m`, `2.4 km`, `km/h`.
- **Imperial, chase line:** under 1000 ft shows as feet rounded to 10 ft (`520 ft`), from 1000 ft as miles with one decimal (`0.4 mi`, `2.4 mi`). A rough figure is fine for a moving distance.
- **Imperial, rule values** (How to play): these are thresholds, so they keep about the precision metric shows today (`round1`): whole feet under 1000 ft (catch radius 10 m is `33 ft`), miles to two decimals from 1000 ft up to 1 mile (sight range 400 m is `0.25 mi`), miles to one decimal from 1 mile, mph to one decimal (catch speed 3 km/h is `1.9 mph`). Rounding them as roughly as the chase line would turn 3 km/h into "2 mph" and mislead a runner about when they count as held.
- **Where it applies:** every distance and speed the mod shows players:
  - the chase line ("Runner 640 m NE", "Runner seen …", "Nearest cop …", "Runner 2.4 km by road NE" on Earth; built in `copsAndRobbers.lua` and `geo.lua` with `geo.formatDistance`)
  - How to play's rule values (catch radius, reset distance, speeds; `HowToPlay.vue` `unit`/`kmh` helpers)
  - any other player-facing place the builder finds (not the Host panel, see Non-goals).
- **The chase line's distance arrives on its own.** Today `infoText` and `nearestText` are finished strings. They become parts: the words before the distance ("Runner", "Runner seen", "Nearest cop"), the distance already formatted by Lua (`geo.formatDistance`, which learns imperial and is covered by Lua tests), and the words after it ("by road", the compass direction). `HudChase.vue` shows the words in the display font and the distance in the mono font. The exact shape of the parts is the builder's call. Tags like IN SIGHT stay as they are.
- How to play gets the unit in its feed and formats its rule values in the UI. The UI never reads the game setting on its own, so Lua and the UI can't disagree.

### Text that changes
- The edit lock message (`inputs.lua` `LOCK_MESSAGE`): "Use the Colour button for your car colour" becomes "Use Settings for your car colour".
- How to play: the prep step ("pick your colour") and "Your colour: use the Colour button…" point to Settings, and a line about Auto headlights and Siren goes with it.
- README: "Everything is clickable with the mouse cursor shown" names the game's control for showing the cursor (checked in game, folded-in issue).
- README and `docs/FEATURES.md`: the lobby card, prep line and per-player colour lines say Settings. A short **Player settings** entry covers the card, the two switches and units. The Emergency lights line says cops have no siren unless they turn it on.
- README config table and `docs/FEATURES.md`: `sirensAllowed` (true): "Cops may use a siren (each cop turns it on in their settings)".
- `docs/DEPENDENCIES.md`: `electrics.setLightsState`, the lights state read for "already on" (if used), `set_lightbar_signal(2)` (siren), `settings.getValue("uiUnitLength")`, `core_environment.getLightState().isNight` for the player's car. Add an update check (see In-game check).

### Tests
Lua tests, as for the rest of the client:
- **Settings file:** missing or broken file means Auto headlights on and Siren off; a change is written and read back; unknown keys and non-booleans are ignored.
- **Headlights:**
  - wanted at night, in each bad weather, not on a clear or cloudy day, never with the switch off
  - placing a car while lights are wanted sends low beam once; placing one when they aren't sends nothing
  - sunset sends on and sunrise sends off, once each
  - no command is re-sent while nothing changes
  - switching off in prep sends nothing
  - round end sends nothing.
- **Siren:** `1` before release and `2` from `running` with the switch on, `1` throughout with it off, the runner always `1`, and `0` at round end.
- **Cop sirens (host):** `sirensAllowed` defaults to true, a non-boolean is refused or replaced like the other booleans, `rules.payload` carries it; a cop with the switch on gets `1` throughout while it is false and `2` again after it turns true; the player's saved switch is never written by it.
- **Units:** `geo.formatDistance` metric unchanged (existing tests keep passing), imperial at the edges (0, 999 ft, 1000 ft, km values), and unknown values of the game setting falling back to metric. The repo has no JavaScript test runner and this work adds none: How to play's formatting is covered by `tools/vuecheck` (it compiles) and the in-game check.
- **Chase line parts:** the HUD feed carries the runner, last-seen, nearest-cop and Earth by-road info as words plus the formatted distance on its own (in the player's unit), never one finished string.

### In-game check
1. Type a hex in the lobby without saving, then let the host start a round: the card is still open in prep, with the hex.
2. Auto headlights on, night round: lights on when your car is placed. Turn them off with the light key: they stay off. Sunrise at Fast day length: they go off. New sky to Rain: they come on.
3. Auto headlights off: the mod never touches your lights.
4. Siren on as a cop: no siren in prep or the head start, siren from release, off at round end. Another player hears it. In an Ibishu Pigeon (no siren sound) the lights stay on and there is no siren.
5. Host turns **Cop sirens** off between rounds: the Siren row is grayed out with "Turned off by the host", and a cop whose switch was on gets no siren after release. Turned back on: that cop's switch is on again and the siren runs.
6. Game set to imperial: the chase line and How to play show ft, mi and mph; the Host panel stays metric. Back to metric: as before. The chase line's distance shows in the mono font, the words around it in the display font.
7. On BeamNG.Earth at night: auto headlights come on (or note what `isNight` reports there).
8. Find the game's control for showing the mouse cursor (default binding and its name in Options > Controls) and put it in the README line.

## Calls made (not discussed, easy to change)
- **Auto headlights on by default** (the user's call after the build; a runner who wants to hide at night turns it off in Settings), **Siren off by default**, which keeps today's "no siren".
- Auto headlights also cover **bad weather**, not only night, matching the traffic rule.
- Lights go **off at sunrise** when the mod would no longer want them, like a car's real auto lights.
- Siren only **from cop release**, never while cops stand frozen.
- **Cop sirens** is on by default, so a player's own Siren switch works out of the box. Off overrides every player's switch without clearing it.
- Button label **Settings**, card title **Your settings**. The colour swatch stays on the button.
- **No colour** no longer closes the card. With more on the card, clearing the colour shouldn't throw you out of it.
- Imperial switches from feet to miles at **1000 ft**.
- Chase line distances are rough (10 ft steps), How to play's rule values are precise (whole feet under 1000 ft, two decimals for miles under 1 mi, one decimal for miles from 1 mi and for mph).
- The chase line's distance is formatted in Lua, so it is tested; no JavaScript test tooling is added.

## Left to the builder
- Where the shared `.hud-btn` and `.swatch` styles live in the kit (`client/ui/modules/copsAndRobbers/`).
- How the colour draft survives a gap between the lobby and prep payloads (app state, a small store, or keeping the card mounted).
- How the client tells "already on" before switching on low beam: a vehicle-side check of the lights state, or tracking what it sent.
- The order of the switch rows, their exact sub-texts, and how the card fits the HUD's height (`useFit` shrinks it). Check in game.
- Any other player-facing place that shows a distance or speed (the Host panel stays metric).
