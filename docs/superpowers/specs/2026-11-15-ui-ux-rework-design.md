# UI/UX rework: one native look, everything on screen (design)

## Intent and why
Nothing is broken. The HUD, the host panel and the leaderboard each grew one feature at a time, and they drifted apart: three headers, colours that mean different things in different places, clutter, and gaps. The user is a developer, not a UI/UX designer, and wants the mod to feel like one product made by someone who does UI, before the friend group starts playing it (today it is play-tested with one other person). The user handed the design calls to this design and approved each part from mockups.

At the same time the user wants the mod to talk to players **only through its apps**: "as little, preferably nothing, in text and toasts", and no chat commands.

Success:
- All apps look like part of BeamNG, built on the game's newest UI system.
- Each screen shows less, but the right things for that role and that moment.
- A first-time player understands what's going on without reading the docs or asking.
- Nothing the mod used to say in chat or in pop-ups is lost; it has a home in an app.

## Goals
1. **One native look** for every app, using BeamNG's newest UI system (the Vue system of 0.40.5) and the game's own components, colour variables, fonts and icons.
2. **A full-screen HUD** that is always there, click-through except its own buttons, and carries everything a player needs during and between rounds.
3. **The HUD is the front door:** between rounds a lobby card opens the Leaderboard and the Host panel for the player, sets their car colour, and opens How to play.
4. **A host panel that only shows what you can do right now**, with one main button for the next step and a reason whenever something can't happen yet.
5. **A leaderboard** in the style of the game's multiplayer scoreboard, with a new Rounds tab that keeps the record chat used to keep.
6. **How to play**, inside the HUD, filled from the server's live settings, opened by itself on a player's first join.
7. **Quiet:** the mod sends no chat messages and shows no toasts or `ui_message` pop-ups. All `/cnr` chat commands are removed.
8. **New preview images** (`app.png`) for the apps once the look is final.

## Non-goals
- **No gameplay or rule changes.** Catching, resets, crash penalties, sight, cop placement, the evolving car rules and the vehicle rules work exactly as today. This is about what players see and click.
- **No permission system.** Anyone can open the host panel, as today (trusted group; the user: almost always the user hosts, "but others should also be able to, no need to limit that").
- **No handling for outdated client copies beyond a HUD notice.** The user: "Outdated copy is no worry as we are still working on this."
- **No other TODO ideas** (traffic, hard mode, spike strips, escape route, infection, night and weather). They will be built later in this style.
- **No translations** (English only, as today) and **no gamepad navigation of our apps** (mouse, as today). (My calls.)

## Anti-goals (a failure even if it technically works)
- **A HUD that gets in the way:** blocking clicks on other apps or the game, or covering the road more than today.
- **Information that disappears:** something that was in chat or a pop-up and now shows nowhere.
- **A host who can't act mid-chase:** End chase and Cancel must stay one click away while driving.
- **Text that disagrees with the real settings** (How to play or the prep rule line saying 7 s when the server says 9 s).
- **Looking bolted on:** our own fonts, our own hand-picked colours or the game's legacy components instead of its current system.
- **A player who can lose the HUD** and with it every bit of round information.

## Constraints
- **Game UI system (verified in the installed game, 0.40.5):**
  - Mod apps are Vue single-file components compiled at runtime (`ui/ui-vue/src/services/uiMods/`). Imports with `@/` resolve to the game's UI sources; a mod's own files resolve under the mod's path. Mod SCSS is compiled with dart-sass and may `@use "@/styles/modules/mixins"`.
  - Design tokens live on `:root` (no import needed): the colour scales in `styles/modules/_colors.scss` (`--bng-orange-*`, `--bng-cool-gray-*`, `--bng-ter-blue-gray-*`, `--bng-add-red-*`, `--bng-add-green-*`, `--bng-add-blue-*`, `--bng-ter-yellow-*`, `--bng-off-black`, `--bng-off-white`, each with a `-rgb` triplet), corners `--bng-corners-1/2/3` (0.25/0.5/1 rem), fonts `--fnt-defs` (Noto Sans) and `--fnt-mono` (Overpass Mono), plus `"Overpass"` for display text.
  - There are no semantic tokens (success/danger/warning) and no spacing tokens; the game's own apps use a 0.25 rem grid.
  - The root font size is 16 px × UI scale, so all sizes are in `rem`/`em`, never `px`.
  - Components to use: `@/common/components/base` (`BngCard`, `BngCardHeading`, `BngTabs`, `BngButton` with `ACCENTS`, `BngIcon` + `icons`, `BngProgressBar`, `BngSwitch`, `BngDropdown`, `BngInput`, `BngColorPicker`, `BngPill`, `BngDivider`), `.../appsUtilities` (`BngSimpleDataDisplay`, `BngRaceStat`), directives (`v-bng-tooltip`, `vBngTextInput`). Avoid the legacy ones: `styles/modules/legacy/*`, `--bng-black-8`-style names, `bngOldIcon`, `bngDrawerOld`, `utility/tab.vue`, the `custom_old` button accent, the `bng-app` class.
  - Icons come from the game's icon set (`assets/fonts/bngIcons/bngIcons.js`, 1163 icons). Unknown names render as a red placeholder, so every name must be checked against that file. Names used in the mockups: `stopwatchArrows02`, `eyeSolidOpened`, `eyeSolidClosed`, `carChase01`, `strobeLights`, `restart`, `mapPoint`, `caution`, `danger`, `abandon`, `checkmarkBold`, `lockClosed`, `cup`, `group`, `info`, `cogSolid`, `play`, `flag`, `timer`.
- **Full-screen apps work.** Placement accepts `%` sizes (frame-relative) and clamps to the frame (`modules/apps/placementResolve.js`). Every app wrapper is `pointer-events: none` ("children decide what's interactive", `common/modules/overlay/components/OverlayItem.vue`); an app's host turns clicks on only when `app.json` `interactive` is not `"no"` (`modules/apps/components/AppHost.vue`). So a full-screen app with `"interactive": "no"` and `pointer-events: auto` on its own buttons is click-through everywhere else.
- **Clicking an app needs the mouse cursor**, as the Apply button does today.
- **Opening apps for the player** uses the same `ui_appLayouts` calls the HUD placement already uses (`addApp`, `removeApp`, see `placement.lua` and `docs/DEPENDENCIES.md`), including BeamMP's layout-in-a-zip special case.
- **Client Lua:** `copsAndRobbers.lua` is near LuaJIT's upvalue limit in `onUpdate`; new logic goes in modules (`hudfeed.lua`, `hud.lua`, new ones).
- **Tests:** about 400 Lua tests (`make test`), including client tests against stubbed game functions. Pure logic stays testable (as `hud.lua`'s payload is today). The Vue apps have no automated tests; they are checked in game.
- **BeamNG.Earth (geo mode)** must keep working: distances, stations and the Map tab use the same geo paths as today.

## Approaches considered

### Overall look (decided from mockups)
- **A. Native (chosen):** the game's own look, built on its newest system. The user: "Native, BeamNG is reworking their look so make sure we use their newest UI system."
- **B. Dispatch:** an own police-radio identity (square boxes, role-coloured edges, segmented bars, a red/blue stripe). Distinct, but more visual noise and not the game's look.
- **C. Broadcast:** a TV race overlay (no boxes, shadowed text, frosted panels). Cleanest, but its text depends on its shadow over bright ground, and the panels aren't the game's style.

### HUD treatment within the native look (decided from mockups)
- **1. Like the game's police chase HUD, `PoliceInfo` (chosen):** shadowed text and icons straight over the road, a thin bar like its Arrest/Evade bar. Covers the least of the view and matches what BeamNG players know from police chases.
- **2. Like the game's race HUD (data tiles):** every value in a labelled tile. Readable on any background, but covers more road.

### Where everything lives (decided)
- **B. The HUD is the front door (chosen; the user: "B sounds nicer"):** the always-present HUD shows a lobby card between rounds with the colour, How to play, and buttons that open the Leaderboard and the Host panel. Those two stay small and focused.
- **A. HUD + one big tabbed app:** one place for host controls, settings, leaderboard, history, colour and help. Rejected: big, mixes host controls into every player's screen, colour three clicks deep, and a first-timer still has to find it in Esc > UI Apps.
- **Dropped early:** today's three apps restyled, plus a fourth for colour and help. Everything would still be found through Esc > UI Apps, which works against a first-timer understanding without docs.

## The design

### 1. Shared look (all apps)
- **Fonts:** `"Overpass", var(--fnt-defs)` for display text (headings, HUD, buttons, numbers in big type), `var(--fnt-defs)` (Noto Sans) for body text, `var(--fnt-mono)` with `tabular-nums` for times, distances and counts.
- **Colour meanings, one each, from the game's tokens:**

  | Meaning | Token |
  |---|---|
  | Runner | `--bng-add-red-500` (fills), `--bng-add-red-400` (text) |
  | Cop | `--bng-add-blue-500` (fills), `--bng-add-blue-400` (text) |
  | Needs your attention / someone broke a rule | `--bng-ter-yellow-200` |
  | Good / go / saved | `--bng-add-green-400` |
  | Things you click, and "you" | `--bng-orange-b400` (accent), `--bng-orange-500` (main button), `--bng-orange-300` (your row outline) |
  | Text / muted text | `--bng-off-white` / `--bng-cool-gray-300` |

  Nothing else uses red or blue. The practice AI's car colours follow the same rule: the AI runner is red-ish, AI cops blue-ish (today the AI runner is blue). (My call.)
- **Cards (panel, leaderboard, lobby card, How to play):** `BngCard`-style surface (`rgba(var(--bng-off-black-rgb), .6)`, `--bng-corners-2`), `BngCardHeading` with the slanted orange bar, `BngTabs`, `BngButton` accents: main (orange) for the next step, secondary (blue-grey) for the rest, destructive outline for Cancel/Reset. Rows on `rgba(var(--bng-off-black-rgb), .5)` with `--bng-corners-1`.
- **Every card has a ✕** that closes it (the panel and leaderboard are removed from the layout, the same as their HUD button does).
- **Shared code:** tokens-on-top-of-tokens (our colour meanings), small shared components (role chip, notice line, card header with ✕) and the time/distance formatting live in one shared place that every app imports, for example `client/ui/modules/copsAndRobbers/`. Whether the mod loader resolves a relative import from an app folder to a shared folder must be verified first (see "Verify first"); if it can't, each app carries a copy of the small shared block. (My call.)

### 2. HUD (full screen, always there)
- **Placement:** `left 0, top 0, width 100%, height 100%`, `"interactive": "no"`, `pointer-events: auto` only on its own buttons. Auto-placed on join as today. **The player can't remove it:** the placement module no longer honours an opt-out for the HUD and puts it back on its next check (today it respects `optedOut`). It is still removed from the layout on leaving the server, as today.
- **Areas on screen:** the centre (big announcements: role, countdown numbers, GO flashes, the result, How to play) and the bottom centre (the lobby card, the chase line, catch bar and notices). Everything else is see-through.
- **Style:** the police-chase treatment. No boxes while driving: `Overpass`, a soft text shadow (`0 0 4px rgba(var(--bng-off-black-rgb), .6)`), icons from the game's set. Boxes (cards) only where there is something to click: the lobby card, the colour picker, the evolving change with Apply, and How to play.
- **Between rounds: the lobby card** (bottom centre):
  - Heading "Cops and Robbers", "N online".
  - A status line: "Waiting for the host to start a round", or "Practice round: Bob" when someone else runs a test round.
  - Buttons: **Colour** (a swatch of your colour), **How to play**, **Leaderboard**, **Host panel**. The last two open and close those apps (they show whether they're open).
  - A persistent yellow line for a standing problem: "Bind a reset or recover button to reset during rounds", "Your copy is 2.0.7, the server runs 2.1.0: rejoin to update", "Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map". (My call: these used to be one-time toasts; on the lobby card they stay until fixed.)
- **Colour picker** (opens from the lobby card's or prep's Colour button): the game's `BngColorPicker` plus a hex field, "No colour" (today's `off`) and Done. It sets the same per-player colour `/cnr color` sets today (stored on the server as hex); in prep it repaints straight away, otherwise it applies from the next round, as today.
- **Prep:**
  - Centre: the car's name (small), then **"YOU'RE THE RUNNER"** (red) or **"YOU'RE A COP"** (blue), then one rule line filled in from the live settings:
    - runner: "Survive as long as you can. Cops catch you by holding you under {catchMaxSpeedKmh} km/h within {catchRadiusMeters} m for {catchHoldSeconds} s."
    - cop: "**Bob** is the runner. You're released {headStartSeconds} s after the runner. Catch them by holding them under … for … s." (Cops today are never told who the runner is outside chat.)
  - Bottom: "Waiting for the host to press GO" with a lock icon, and buttons for Colour, How to play and **Host panel** (so a host who closed the panel, or whose automatic round just reached prep, can get to GO without Esc > UI Apps). (My call.)
  - **Evolving mode:** the bottom shows the runner's queued change as a card ("Your change" for the runner, "Bob's change" for others) with the change lines as today (label, from → to, "+ N parts come with it", "⚠ missing"), and **Apply change** for the runner only. After Apply: "APPLYING CHANGES" in the centre until everyone has loaded.
- **Countdown, head start, crash penalty:** one treatment: a small label ("RUNNER STARTS IN", "COPS RELEASED IN", "CRASH PENALTY") over a big number in the centre. The runner sees "GO! RUN!" in the same spot; cops "GO!" at release; a penalised cop "PENALTY OVER". During the head start the runner's chase line shows "Cops released in N".
- **Chase line** (bottom centre, one row plus small lines):
  - Role chip, stopwatch + survival time; with a time limit "3:12 / 10:00" (needs the limit sent to clients).
  - Sight: eye icon + SPOTTED (yellow) / HIDDEN (muted) for the runner; IN SIGHT / LIVE / last seen for cops, as today's tags.
  - Distance: the runner's nearest cop, or the cop's "Bob 640 m NE" / "2.4 km by road NE" on BeamNG.Earth.
  - Reset line: restart icon + "Reset ready" or the reason ("Stay still 4 s to reset", "Can't reset while being caught", "Penalty"). **No key binding is shown** (the user: players use different reset buttons and we can't map them all). Pressing reset when not allowed briefly highlights this line, as today.
  - Catch bar under the line, only while the catch timer runs: red "BEING CAUGHT n%" for the runner, blue "HOLDING RUNNER n%" for cops, thin like the game's Arrest bar, smooth as today.
- **Notices** (replace chat lines and pop-ups): an icon and one line above the chase line (or above the lobby card), a few seconds each (4 s as today), at most two at once. Yellow for "someone broke a rule" and personal warnings, muted white for information.
- **Result** (centre): the title (RUNNER CAUGHT, ROUND ENDED, ESCAPED, RUNNER LEFT, ROUND CANCELLED), "Bob survived 8:41 · caught by Ann, Kim", the map's top 3 with your row outlined, and "NEXT ROUND IN 12" when automatic rounds are on. It stays about 10 s (or until the next round starts), then the lobby card returns.
- **How to play:** a centre card inside the HUD (section 5).

### 3. Host panel
- **Opened** from the lobby card's Host panel button, or Esc > UI Apps. Default spot: right side of the screen (my call). Header: "Host panel", the version (as today), ✕.
- **Four tabs: Round, Car, Map, Settings.**
- **Round tab, by phase. Only what can be done now is shown; one main (orange) button does the next step; a yellow line says why when it can't:**
  - **No round:** status "No round", the map's real name and the car mode. **The player list is the runner picker:** each online player with their runs this session; the "next" player (fewest runs) is preselected and marked "next", the last runner is marked "last" (replaces "Same as last"), and a "Random runner" row. Main button: **"Start round with Bob"**. Below: **Practice as runner**, **Practice as cop**, and the **Automatic rounds** switch with its delay ("next one 15 s after a round").
  - **Picking cars:** status only.
  - **Prep:** status "Prep", the runner and the car (or build step). Player list with role chips and each player's state: ready (car loaded), changing (the evolving runner, with what), missing parts (⚠). The states are **for display only**: GO is held back exactly when it is today and no longer (in evolving mode until the change is applied and the cars have loaded, at most 20 s; never in random mode), so the round logic doesn't change. Main button **GO**, disabled with today's reason when it can't go ("Waiting for Bob to apply the change", "Applying the change: 2 cars still loading"). **New car** in random mode only. **Cancel round** (destructive). (My call.)
  - **Countdown, head start, chase:** the panel folds into one bar: a red dot, "Chase 3:12", "Bob running", **End chase** and **Cancel**, and ▾ to open it. It folds by itself on GO (as today) and opens again by itself when the round ends. During the chase Cancel asks for a second click, because it throws the run away. (My call.)
  - **After a round:** "Bob caught after 8:41"; with automatic rounds on, "Next round in 12 s with Kim (fewest runs)" with **Start now** (new: starts the scheduled round immediately) and **Stop automatic rounds**.
  - Every click gets feedback in the panel (the reply line, styled as a small status line), as today; nothing goes to chat.
- **Car tab:** a two-way switch **Random car / Evolving build**. In evolving mode a summary box (car, build step, last change and who made it), **New build: Choose a car…** (searchable dropdown, as today) and **Random**, both asking for a second click when a build exists, and **Reset build** (second click). Below, for both modes, "Cars that can be picked": Include mod cars, and the excluded cars (shown as names, editable). Locked during a round with a reason.
- **Map tab** (replaces `/cnr addstation` and `/cnr removestation`): "West Coast USA · 10 gas stations", **Add station here**, **Remove nearest** (disabled with "No station within 50 m to remove"), and the nearest stations with their distance from you. Works in geo mode, where stations are also discovered automatically.
- **Settings tab:**
  - Every setting gets a one-line explanation under its name.
  - **Common settings first** (my pick): Head start, Time limit, Hold time, Catch distance, Reset wait, Crash penalty. The other ~14 sit under a collapsed **More settings**, still grouped (Round, Catching, Resets, Crashes, Cops, Cars).
  - Changes still save by themselves 0.5 s after the last click; the panel confirms with a green "Saved: head start 8 s" line, and a refused value snaps back with the reason in yellow.
  - A value that differs from the default is orange and gets its own small reset; **Reset to default** for everything stays a two-click button. **Reload config.json** stays.
  - Locked during a round with "Stop the round first" (as today).
  - Unknown keys from a newer server still appear under "Other".

### 4. Leaderboard
- **Opened** from the lobby card's Leaderboard button or Esc > UI Apps. Default spot: left side (my call). Header "Leaderboard", ✕.
- **Look:** the game's multiplayer scoreboard (`ui/modules/apps/Scoreboard`): rows on off-black, uppercase small column headers, gold/silver/bronze rank badges, **your own row outlined** in `--bng-orange-300`.
- **Filters** in their own row under the tabs: map (This map, All maps, each map with runs; **real map names**, not ids) and car mode (All, Random, Evolving), as today.
- **Tabs: Runners, Cops, Players, Rounds.**
  - **Runners:** best survival time per player with the car (and the map when showing all maps). If you aren't in the visible top, your own row is pinned at the bottom with your rank.
  - **Cops:** catches, assists (moved here) and fastest catch.
  - **Players:** a table (runs, best, catches, assists); clicking a player shows their stats as tiles (runs, best, average, escapes, catches, assists, hidden %, lost the cops; "–" when sight was off, as today) and their last few rounds.
  - **Rounds (new):** every recorded round, newest first, grouped by day ("Today", "Yesterday", a date): an icon for how it ended, "Bob caught by Ann, Kim", the time of day, car and build step, the survival time, and a yellow flag line for anything that went wrong ("Kim reset illegally"). Clicking one shows its **timeline** (cops released, lost the cops, crash penalties, illegal resets, teleports, parts changed, the end) and each cop's share of the chase with the runner in sight. Older runs without a timeline show only the result. Practice and cancelled rounds are still not recorded. Long lists load more as you scroll or with "Show more" (builder's call).
- It refreshes after every round, as today.
- **During a round** it hides itself from GO until the round ends, then shows again (the app renders nothing in between; it is not removed from the layout), so it doesn't cover the road. It stays visible in prep. (My call.)

### Apps and rounds, in short
- **HUD:** always there; lobby card between rounds, round displays during one.
- **Host panel:** opened and closed only by the player (lobby card and prep buttons, ✕, Esc > UI Apps). It folds into its bar on GO and opens again when the round ends, as today. It never opens itself for anyone.
- **Leaderboard:** opened and closed only by the player; hidden from GO until the round ends.
- Nothing is opened or closed on someone's behalf because of a phase change, so the server doesn't need to know who "the host" is.

### 5. How to play
- **Where:** a centre card inside the HUD, so no extra app. Opened from the lobby card and from prep; **opens by itself on a player's first join** and is remembered on their own PC (a small file in `settings/`, like `cnr_vehicle_modes.json`; my call). Closed with ✕ or **Got it**.
- **Live values:** every number comes from the server's current settings (shown in orange mono), so it can't go out of date.
- **Five short tabs, no scrolling:**
  - **Basics:** one runner, everyone else a cop; everyone drives the same car; the score is survival time; the round as five steps (Prep, GO after {runnerCountdownSeconds} s, head start {headStartSeconds} s, Chase, Result); whoever has run least goes next.
  - **Runner:** being caught (and that the bar empties twice as fast as it fills), SPOTTED/HIDDEN, nearest cop, the time limit when set.
  - **Cop:** catching and shared credit, sight ({sightMaxMeters} m, live while any cop sees the runner, last seen every {lastSeenIntervalSeconds} s), crash penalty ({crashSpeedLossKmh} km/h in half a second → frozen {crashPenaltySeconds} s, getting hit doesn't count), emergency lights.
  - **Resets:** "You may" (standing still at a gas station; after standing still {resetWaitSeconds} s; cops {copResetMinDistanceMeters} m or more from the runner) next to "You may not" (being caught, crash penalty, frozen); any reset button works; runners repair in place, cops move to the nearest road; a reset at the wrong moment is shown to everyone.
  - **Rules:** what's locked during a round (teleports, parts and paint menus, free camera and the rest of today's list), the Colour button, and (only when evolving mode is on) the one-change rule and Apply.
- Settings that are off read sensibly ("no time limit", "sight is off").

### 6. Quiet: no chat, no pop-ups, no commands
Every message gets a new home:

| Today | New home |
|---|---|
| Round flow in chat ("Bob is the runner! Car: …", "Runner starts in 3s", "Bob is off! Cops released in 7s", "Cops released!", "Picking a new car...", test round explanations) | The HUD's prep, countdown and GO displays (no notice needed) |
| Results, top 5 and "Next round in 15s" in chat; the result toast | The HUD's result card and the Leaderboard's Rounds tab |
| Rule breaks in chat ("Ann reset illegally", "Ann teleported", "⚠ Ann changed parts during the round: …", "Ann: crash penalty 10s", AI penalties) | HUD notices for everyone (yellow) and the round's timeline |
| Build changes in chat ("Change 7 by Bob: …") | A HUD notice (muted), the Car tab's last change, and the round's timeline |
| Replies to the host's clicks (mirrored to chat today) | The panel's feedback line only |
| Personal pop-ups (no reset binding, no road found, couldn't spawn AI / MaxCars, no vehicles available, teleport disabled, parts menu locked, reset not allowed) | HUD notices for that player (reset not allowed keeps the reset-line highlight); standing problems also on the lobby card |
| Outdated client and BeamNG.Earth API pop-ups | The lobby card's yellow line |
| Toast fallback when the HUD isn't placed | Removed: the HUD is always placed |

- **Commands:** `/cnr color`, `/cnr addstation`, `/cnr removestation`, `/cnr help` and `/cnr version` are removed, with their help text. Their jobs move to the colour picker, the Map tab, How to play and the panel header. A message starting with `/cnr` is still swallowed (not shown in chat), and the sender gets a HUD notice: "Chat commands are gone: use the Cops and Robbers card at the bottom of your screen." (My call.)
- **The mod calls neither `MP.SendChatMessage` nor `ui_message`** any more (including `game.toast` and `hudfeed.notify`'s fallback).

### 7. Preview images
Redraw `tools/previews/hud.svg`, `panel.svg` and `board.svg` to show the new apps (the HUD preview shows the full-screen HUD mid-chase), and export them to each app's `app.png`, once the look is final.

### 8. Data the server and client need (new or changed)
- **To clients:**
  - the settings the HUD and How to play show (catching, resets, head start, countdown, crashes, sight, time limit), on join and whenever they change;
  - the time limit for the chase line;
  - notices as a structured event (text, tone, who it is for) instead of chat;
  - the online count for the lobby card.
- **Panel state:** players with runs this session, the next and last runner, each player's prep state (car loaded, changing, missing parts), why GO is blocked, the scheduled automatic round (when and with whom), the build summary with the last change, the station count and positions (for distances; geo positions as today).
- **Leaderboard state:** whose row is "you" (per recipient), real map names (looked up on the client from the level's title, falling back to a prettified id), and the round list with timelines.
- **Saved with each run (new):** a timeline of events, each with the chase time and who: lost the cops, crash penalty, illegal reset, teleport, parts changed, the end. Existing fields stay; `endedAt` already gives the time of day.
- **From clients (new):** set my colour (hex or none), add station here, remove nearest station, start the scheduled round now, open/close an app (handled on the client).

### 9. Docs
Update `README.md` and `docs/FEATURES.md` (apps, no commands, no chat), and `docs/DEPENDENCIES.md` for the new game dependencies: the full-screen click-through behaviour, opening apps from the HUD, the components, tokens, fonts and icon names used.

## Verify first (before building on it)
A short in-game spike, before the rest:
1. **Full-screen HUD:** `"interactive": "no"` with buttons on `pointer-events: auto`: the buttons click, everything under the empty area (the game, other apps) still clicks. Check the layout editor too: a full-screen app may cover other apps there and make them hard to grab; if so, find a way around it (z-order, or a smaller box that still reaches the centre).
2. **Shared files:** an app's `app.vue` can import a shared `.js`/`.vue`/`.scss` from another folder of the mod.
3. **`BngColorPicker`** works inside a mod app and its HSL value converts to and from our hex.
4. **Opening apps from the HUD** with `ui_appLayouts.addApp` while in a round and between rounds, including BeamMP's `beammp` layout, and removing them again on leave.

## Left to the builder
- Exact sizes, spacing (on the 0.25 rem grid), the text-shadow strength, and the order of small items inside each line.
- Exact wording of notices, explanations and How to play text (plain, short, matching the tone of the mockups).
- How the panel and leaderboard pick their default position and size; how the Rounds list pages.
- How the server works out "car loaded" per player in random mode.
- File and module names, and how the work splits into versions and commits.
- The build order. A sensible one: the spike → shared look + HUD + quiet (chat, pop-ups, commands) → lobby card, colour and How to play → host panel → leaderboard and the round timeline → preview images and docs.

## Calls made in this design (for the user to check)
- Practice AI car colours follow the colour meanings (runner red-ish, cops blue-ish).
- Standing problems (no reset binding, outdated copy, BeamNG.Earth API) stay on the lobby card until fixed instead of a one-time pop-up.
- A typed `/cnr …` is swallowed and answered with a HUD notice.
- Cancel asks for a second click during the chase.
- Prep's bottom line gets a Host panel button; nothing opens the panel by itself.
- The leaderboard hides itself from GO until the round ends.
- The panel's per-player "ready" states are display only; GO waits exactly as long as today.
- The six "common" settings shown first.
- Panel opens on the right, leaderboard on the left.
- How to play's "seen" flag is stored on the player's own PC.
- No translations and no gamepad navigation for our apps.

## Mockups
The approved mockups are in `.superpowers/brainstorm/470328-1794764964/content/` (local only, git-ignored): `native-hud.html` (look and HUD style), `app-lineup.html`, `hud-round.html`, `host-panel.html`, `leaderboard.html`, `how-to-play.html`. In `hud-round.html` the reset line still shows a key; that was dropped.
