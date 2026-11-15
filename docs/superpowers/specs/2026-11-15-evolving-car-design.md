# Evolving car mode, and UI-only controls (design)

## Intent and why
This is a friend's idea, refined with the user. Instead of a random stock config each round, the group shares one **build**: a real car with custom parts and tuning that evolves over the evening.
- Each round the runner makes **one change** during prep, and that change goes onto everyone's car. The evolved car carries over to the next runner.
- The fun is in building and adapting a car together, one change per round. The runner picks a change that suits his escape, knowing the cops get it too.
- At the same time the user wants the mod to be run **only through the apps** from now on. All chat commands and key bindings go, except five.

## Goals
- **Part A, UI-only controls:**
  - Remove every `/cnr` chat command and all key bindings, except `/cnr color`, `/cnr addstation`, `/cnr removestation`, `/cnr help` and `/cnr version`.
  - Everything else runs through the control panel and the leaderboard app.
- **Part B, the evolving car mode:**
  - A new car mode, `carMode = "evolving"`. It sits next to today's `"random"` mode, which stays the default.
  - A new build starts from a **random** stock config or from **a chosen player's current car**.
  - The build is **saved** after every applied change and continues in the next session until someone resets it.
  - Round flow in evolving mode: **prep → Apply → GO → countdown → head start → chase**.
  - **Everyone sees the runner's queued change live in the HUD during prep.** The group polices the one-change rule itself (user: "police each other by making everyone able to see what is currently queued as a change").

## Non-goals
- **No automatic enforcement of "one change".** The user's rule is a judgement call: an engine swap is one change, performance stages go one step at a time, wheels one axle at a time, and fixing parts that a swap left essential-but-missing counts as part of that change. People enforce it, not code.
- **No undo or history browser** for builds. Reset starts over.
- **No chat or key-binding control** for anything new (user: "only UI app for that from now on").

## Anti-goals (a failure even if it technically works)
- **Cars that differ** between players after Apply, so the chase isn't fair.
- **A round stuck** waiting on one player whose car won't load.
- **Losing a build** the group spent an evening on (a crash, a bad save, a restart).
- **Changes that don't show** in the queued-change list (silent changes defeat the policing).

## Part A: UI-only controls
- **Chat:**
  - Only `color`, `addstation`, `removestation`, `help` and `version` are handled.
  - Any other `/cnr …` command replies: "Use the Cops and Robbers Panel (Esc > UI Apps)".
  - `/cnr help` lists the five commands and points to the panel and leaderboard apps.
- **Key bindings:**
  - The actions file `core/input/actions/copsAndRobbers.json` and the `cnr_command` event (and its server handler) are removed.
  - Keep the client code that hot-reloads action files only if something still needs it. Otherwise remove it.
- **Panel:**
  - It already covers start, GO, new car, end chase, cancel, auto rounds, practice and settings.
  - Add a **"Reload config.json"** button to the Settings tab. It does what `reload` did, and is refused during a round.
  - The leaderboard app replaces `/cnr top`.
- **Texts that mention commands** move to panel wording. For example:
  - "waiting for "/cnr go"" → "waiting for GO"
  - "type "/cnr go"" → "press GO in the panel"
  - "("/cnr auto off" to stop)" → "(turn off Automatic rounds in the panel)"
  - the prep toast and HUD prep line
  
  Search the server and client for `"/cnr` and update every one.
- **Docs:** README, FEATURES and DEPENDENCIES lose the command table and the key-binding section. They gain a short "Controls" section listing the panel, the leaderboard app and the five remaining commands.

## Part B: Evolving car mode

### Settings and panel
- **Mode:** `carMode` is `"random"` (default) or `"evolving"`. It shows in the panel as a switch on the Round tab ("Evolving car"), and only while no round is active.
- **Panel build section** (Round tab, shown when evolving is on):
  - The build's name and step, for example "Gavril D-Series · change 7".
  - **New build: random** picks a random stock config, the same way the random mode picks (excluded cars and mod settings apply).
  - **New build: from player ▾** uses the same player list as the runner picker. It takes that player's current car (parts, tuning and model) as change 0.
  - **Reset build** needs two clicks, like Reset to default. It clears the build, and the next round in evolving mode asks for a new one: the GO/Start buttons show "Start a new build first".
- **Starting a round in evolving mode with no build** is refused, with the panel reply "Start a new build first".
- **The New build buttons** are disabled during an active round.

### Round flow (evolving mode)
1. **Setup.** Everyone, the runner included, gets the **build's** car instead of a random config. Cops still get their emergency lights added on top.
   - Each player's `/cnr color` is applied as today.
   - "New car" (reroll) is not available in evolving mode, because the car is the build.
2. **Prep.**
   - **Only the runner** has the parts menu, so he can make his change. Cops' parts menus stay closed so their cars can't drift from the build.
   - **Nobody** can use the game's paint menu to change color; color is `/cnr color` only. The runner's parts menu includes a paint tab, but paint is never taken into the build: Apply ignores paint, and everyone keeps their own `/cnr color`.
   - **The queued change:** the runner's game compares his current car with the build about once a second. When it differs, it sends the list of changes to the server, which forwards it to all players in the round.
   - **Everyone's HUD shows the change** in place of the prep line:
     ```
     BOB'S CHANGE (2)
     Engine      4.5L V8  →  6.0L V8
     Intake      Stock    →  6.0L V8 Intake
     Gear ratio 1   3.10  →  3.45
     ```
     - Part ids become display names on each player's own game (from the part's jbeam info name). A slot that's removed shows "(none)". A part this player doesn't have shows "⚠ missing: <part id>".
     - Tuning (vars) changes show with their values.
     - With no change: "BOB'S CHANGE: none yet".
     - If the list is longer than the HUD can show, it shows the first lines plus "+N more".
3. **Apply** (panel button "Apply change"; the runner or whoever runs the game may press it).
   - The server asks the runner's game for its exact current setup: model, parts and vars in **format 2**, without paint.
   - It saves that as the new build: step + 1, with who changed what.
   - It then has **every** player's car rebuilt from it. Cops get lights; everyone gets their color.
   - The HUD shows **"APPLYING CHANGES"** with "N/M ready".
   - Each game reports back when its car is rebuilt and placed, using the existing `cnr_myVehicle` path.
   - When everyone has reported, or after a **20 s timeout** (whoever isn't ready starts as they are), the round moves on to "ready for GO".
   - **After Apply the runner's parts menu closes.** A second Apply isn't possible. Apply with no change is allowed and keeps the build as it is (the step doesn't increase).
4. **GO.** Allowed in evolving mode only after Apply has finished. Before that, the panel's GO button is disabled with "Apply the change first".
5. **Countdown, head start and chase:** as today.

### Missing parts
- **On Apply, each game checks that every part in the build exists locally** (jbeam lookup).
  - If one doesn't, that game reports it, and the HUD shows to all: "⚠ Ann is missing: <part id>, <part id>".
  - The round continues: the game spawns what it can.
- **Server-distributed mods** are the same for everyone, so this only catches parts from someone's local mods.
- **Undo is manual.** The runner can pick a different part next round, or the group can Reset.

### Persistence
- **The build file:** `data/build.json` = `{ model, parts, vars, step, startedFrom ("random" | "<player name>"), startedAt, history = [{ step, by, at, changes = [{slot, from, to}] }] }`.
- **Saving:** it's written atomically, like the leaderboard (write to a temporary file, then rename), after every Apply that changes something, and on New build. A broken file is moved aside, and the server logs that there's no build.
- **Keeping it:** the build survives server restarts and continues next session. Reset deletes it only after moving it to `data/build-<time>.json`, so a build is never lost by accident.

### Leaderboard
- **New fields on each run:** `mode` (`"random"` | `"evolving"`) and, in evolving mode, `buildStep` and `buildName` (for example "Gavril D-Series").
- **A mode filter** joins the map dropdown in the leaderboard app: All modes / Random / Evolving.
- **Older 1.7 runs** have no mode and count as random.

### Messages
- **Chat** keeps the record of each applied change: "Change 7 by Bob: Engine 4.5L V8 → 6.0L V8 (+1 more)". It's a server message to all, not a command.
- **Toasts as fallback** when the HUD isn't placed, as today.

## Constraints
- **Same stack:**
  - Lua 5.3 server plugin, LuaJIT client (no new top-level locals pressure since the split, but keep the main file lean).
  - Vue 3 apps.
  - Tests with stock Lua, and `tests/test_client.lua` for client wiring.
- **The build is spawned the same way cops' light-modified cars are today:** a format-2 config table passed to `core_vehicles.replaceVehicle`.
- **Reading the runner's setup:** the runner's game reads `core_vehicle_manager.getPlayerVehicleData().config`. It turns it into format-2 `parts` + `vars` the same way the game's own "save config" does (`core/vehicle/partmgmt.lua`, `savePartConfigFileStage2_Format2`; `partsTreeToPartsMap` if only a parts tree is present).
- **Payload size:** a full config is a few KB of JSON, which is fine over BeamMP events. The queued-change list is small.
- **Deploying:** only when the server is empty, when the user says so. The release is **1.8.0**.

## Approaches
- **The runner's game is the source of truth (chosen):**
  - It computes the queued change and sends its exact setup on Apply. The server stores and forwards it.
  - Each game names parts locally.
  - It reuses the proven "spawn from a config table" path.
- **The server reads BeamMP's own vehicle-edit reports:** rejected. They arrive in two different shapes, and that is why parts enforcement is still only logged.
- **Builds saved as .pc files inside the mod:** rejected. It needs repacking and a restart per change.

## Decisions made with the user
- One change per round. The group polices it by seeing the queued change; the code doesn't enforce it.
- Only the HUD shows the queued change. The panel and leaderboard apps don't (they load less).
- The stage order is Apply → GO → countdown.
- A new build starts from random or from a player's car. Builds are saved and continue across sessions, and can be reset.
- Paint only through `/cnr color`, for everyone.
- All chat commands and key bindings are removed except color, addstation, removestation, help and version.

## My calls (confirm or correct)
- Both the runner and whoever runs the game can press Apply.
- The ready timeout is 20 s.
- Apply with no change is allowed, and the step stays the same.
- New car (reroll) is disabled in evolving mode.
- Practice rounds use the build, but their Apply never changes the saved build.
- Reset keeps a backup file.
- Leaderboard runs record the mode, and the app gets a mode filter.

## Left to the builder
- How exactly to compare the runner's car with the build: slot-by-slot over format-2 parts, plus vars.
- How to look up part display names, and the fallback to the id.
- The HUD layout of the change list (within the existing 230 px HUD; shrink fonts or use "+N more").
- The exact panel layout.
- How the server asks the runner's game for its setup on Apply (request/response events).
- Test design, which follows the existing patterns (pure modules first).

## Verify early (risk)
- **Reading the config:** before building on it, spike reading `getPlayerVehicleData().config` on 0.40.5. Check whether it gives `parts` and `vars` directly or only a parts tree, and that spawning a second car from that table reproduces the same car (engine and tuning).
- **The parts menu:** check that the parts menu (`parts_selector` action) can be opened for the runner only, and stay closed for cops, in the same way `setPartsMenu` works today.
