# Dependencies and compatibility checks

The mod has no package dependencies. It does lean on three external systems: BeamMP (server and client), BeamNG.drive and BeamNG.Earth. This file lists what we use from each one, where in our code we use it, and what to check when that system updates.

Versions in use on 2026-11-15:
- BeamNG.drive 0.40.5.0
- BeamMP Server 3.9.3 (Lua 5.3.5)
- BeamMP Launcher 2.8.1
- BeamNG.Earth mod API v1

## After any update: the quick check (about 15 minutes)

1. Run `make test` and `make vuecheck`. The tests show our own logic is intact, but the game APIs are stubbed, so they say nothing about the update itself. `vuecheck` compiles every Vue file (SCSS imports resolve against the installed game's UI sources), syntax-checks our `.js` files and checks that each icon name exists (see the UI section).
2. Run `make deploy`. The deploy log must say `Cops and Robbers <version> loaded`, with no `LUA ERROR`.
3. Check the client log after joining: `~/.local/share/BeamNG/BeamNG.drive/current/beamng.log`. Run `grep -n "copsAndRobbers\|CnR" beamng.log`. Look for Lua errors, plus the `Adding new Event Handler to "cnr_..."` lines.
4. Play a practice round from the panel (Practice: as cop), then press GO. Check:
   - **Setup:** the Announcements and HUD apps appear, your car is replaced and frozen, and the AI cars spawn.
   - **Countdown:** the countdown runs in the middle of the screen and GO releases you.
   - **Lights:** the light bar or beacon flashes on your car and on the AI cop.
   - **Reset rules:** pressing your reset button gets refused and highlighted, and after waiting the reset is allowed.
   - **Catching:** the catch bar fills when you hold the AI runner.
   - **End:** End chase shows the result card. Leaving the server removes our apps from the layout.
5. Open the control panel (Host panel button on the lobby card) and check:
   - The status line is filled in.
   - A stepper change saves ("Saved: ...").
   - Typing in Excluded cars doesn't move the car.
   - It folds into its bar on GO.
   - The leaderboard (lobby card button) opens, shows the Rounds tab, and hides during a round.
6. Also play one round on BeamNG.Earth if that map is in use (see its section below).

Then do the checks for whatever actually updated.

---

## BeamMP Server (plugin API)

**Used in:** `server/CopsAndRobbers/main.lua`. The `cnr/*.lua` modules are pure Lua and use no API.

**What we use:**
- **Functions:**
  - `MP.RegisterEvent`, `MP.TriggerClientEvent`. The mod sends no chat messages
  - `MP.GetPlayers` (pid → name), `MP.GetPlayerName`, `MP.GetPlayerIdentifiers` (expects `beammp` = account id), `MP.GetPlayerVehicles`
  - `MP.GetPositionRaw` (expects `{pos={x,y,z}, vel={...}}` plus an error string), `MP.RemoveVehicle`
  - `MP.CreateTimer():GetCurrent()`, `MP.CreateEventTimer` / `MP.CancelEventTimer` (the 250 ms `cnr_tick`)
  - `MP.Get(MP.Settings.Map)` (the map path; we parse `levels/<name>/`)
  - `Util.JsonEncode` / `JsonDecode` / `JsonPrettify`, `FS.CreateDirectory` / `Remove` / `Rename`
- **Events and the data shapes we parse:**
  - `onChatMessage(pid, name, msg)`: returning `1` hides the message. We use it only to hide a typed `/cnr ...` from chat; the sender gets a HUD notice pointing to the Cops and Robbers card instead.
  - `onVehicleSpawn(pid, vid, data)` and `onVehicleEdited(pid, vid, data)`. The data is `...:pid-vid:{json}`, and we parse from the first `{`. The JSON has `jbm` (model) and `vcf.partConfigFilename` / `vcf.parts`. Returning `1` from an edit **deletes the car**.
  - `onVehicleDeleted`, `onVehicleReset`, `onPlayerJoin`, `onPlayerDisconnect`.
- **Loading:**
  - The plugin chunk name has **no `@`**. `pluginDir` handles both forms.
  - The plugin folder is added to `package.path` and modules load as `require("cnr.x")`.
- **Lua version:** 5.3. We use integer/float formatting such as `%.10g` and `math.floor`.

**On update, check:**
- The deploy log line (step 2 above).
- **Vehicle data format:** start a round. A car that's wrongly refused or deleted means the spawn or edit data format changed (`parseVehicleData`, `vehicleAllowed`).
- **Parts edits:** during a round, change a part (through the console, since the menus are locked) and check that a yellow HUD notice shows `<name> changed parts during the round: <slots>`. If it shows up after a round setup, repaint or Apply, or when nothing changed, the `vcf.parts` shape changed or BeamMP reports it later than the quiet window in `main.lua` (`PARTS_SETTLE_SECONDS`).
- **Account identity:** play a round and check that the leaderboard shows the account names. If they're missing, the `GetPlayerIdentifiers` format changed.
- **Positions and catching:** catching needs `GetPositionRaw`. If the catch bar never fills, check its return shape.

## BeamMP Client (in-game Lua and launcher)

**Used in:** `client/lua/ge/extensions/copsAndRobbers.lua`, `copsAndRobbers/game.lua` and `copsAndRobbers/ai.lua`.

**What we use:**
- `AddEventHandler(name, fn)` and `TriggerServerEvent(name, string)`.
- `MPVehicleGE.isOwn(gameId)` and `MPVehicleGE.getVehicleByGameID(id).serverVehicleString`. That string is `"pid-vid"`, and we take the vid after the last `-`.
- `MPConfig.getPlayerServerID()`.
- **Line of sight:** `MPVehicleGE.getVehicles()`, keyed by `"pid-vid"` with `gameVehicleID`, `isSpawned` and `isDeleted`. Also `MPVehicleGE.getPlayers()[pid].activeVehicleID`, a `"pid-vid"` key for the car that player is driving or viewing. These are used to find the runner's car on a cop's game.
- The GE hook `onBeamMPServerLeave`.
- **Mod mounting:** the mod is mounted when you join. Our UI apps then need an `onFilesChanged` refresh.
- **Launcher on Arch:** the wrapper in `~/.local/bin/beammp-launcher` sets argv[0] and the working directory. The AUR binary name broke `CheckName()` before.

**On update, check:**
- The client log shows our handlers being added, and the round starts at all.
- `cnr_myVehicle` reaches the server: your own car counts in catch and reset checks. If the vid parse breaks, the server never learns which car is yours.
- The five apps appear in Esc > UI Apps (or are placed automatically, for Announcements and the HUD).
- Rejoin within the same game session. If notices or panel replies now show twice, `AddEventHandler` re-registration has changed.

## BeamNG.drive: game engine Lua (GE)

**Used in:** the client modules.

**What we use, by area:**
- **Vehicles** (`vehicles.lua`, main file):
  - `core_vehicles.getConfigList(true).configs`, using the fields `model_key`, `key`, `pcFilename`, `Type` and `Source`. `Source == "BeamNG - Official"` means stock.
  - `core_vehicles.getModel(model).model.{Name,Brand,Type}`.
  - `replaceVehicle` / `spawnNewVehicle(model, {config=<path or format-2 table>, paint, pos, rot, autoEnterVehicle})`.
  - `createVehiclePaint`, `jsonReadFile`, `deepcopy`.
  - Configs in `format: 4` are skipped for cop lights.
- **Placement and roads** (`roads.lua`):
  - `map.getMap().nodes[id].{pos,links}` and `map.findClosestRoad(pos)` (two node ids).
  - `spawn.safeTeleport(veh, pos, rot)`, `vec3`, `quatFromDir`.
- **Inputs** (`inputs.lua`):
  - `core_input_actionFilter.getActionTemplates().competitive`, `setGroup` and `addAction`.
  - `core_input_bindings.bindings[].contents.bindings[].action`.
  - The action names in `LOCKED_ACTIONS` and `RESET_BUTTONS`.
  - We replace the globals `resetGameplay` and `spawn.teleportToLastRoad`, and `freeroam_bigMapMode.teleportToPoi`.
- **Gas stations:** `freeroam_facilities.getFacilitiesByType("gasStation")` and `freeroam_gasStations.gasStationCenterRadius(f)`.
- **Evolving car mode:**
  - `core_vehicle_manager.getPlayerVehicleData().config` (a `partsTree` plus `vars` in 0.40) and `core_vehicle_partmgmt.partsTreeToPartsMap`, the same conversion the game's own "save config" uses.
  - `FS:getFileOriginInfo(pc).archivePath` (configs from `/mods/multiplayer/` count as server-provided).
  - The `parts_selector` action is the only way into the parts and paint menu, so closing it closes paint too.
  - On update, check that a changed part shows up in the HUD's change list, that Apply rebuilds everyone's car to match, and that the game's config format is still `format: 2` with `parts` and `vars`.
- **Car settings carry over** (`copsAndRobbers/modes.lua`): vehicle Lua `controller.getState()`/`setState()` and `powertrain.getState()`/`setState()`, the game's own state API for controllers (ESC, drive modes) and drivetrain devices (diff locks, transfer cases); plus `serialize` and `obj:queueGameEngineLua`. On update, check that turning traction control off and starting a new round keeps it off.
- **Line of sight** (`copsAndRobbers/sight.lua`):
  - `castRayStatic(origin, dirNormalized, length)` returns the distance to the first static hit (terrain, buildings), and `>= length` means clear. Vehicles don't block it.
  - We cast both ways, as the game's own `isVisible` does, because single-sided faces only block from one side.
  - Also used: `veh:getDirectionVector()` and the global `log`.
- **Other:**
  - `core_groundMarkers.setPath`, `guihooks.trigger`, `extensions.hook` / `load`. We no longer call `ui_message`.
  - `core_levels.getLevelTitle(id)` gives the map's real name for the panel and leaderboard (`game.lua`, `mapTitle`). If it goes missing we fall back to a prettified id.
  - `FS:fileExists`, `getCurrentLevelIdentifier`, `getObjectByID`, `getPlayerVehicle(0)`.
  - The hooks `onUpdate`, `onVehicleResetted`, `onClientEndMission`, `onExtensionLoaded` / `Unloaded` and `onWorldReadyState`.

**On update, check:**
- Every global we read still exists. This lists them:
  `for f in client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/*.lua; do luajit -bl "$f" | grep -o 'GGET.*"[a-zA-Z_]*"' | grep -o '"[a-zA-Z_]*"'; done | sort -u`
  Then grep the game's `lua/` folder for any name you're unsure about.
- **Reset buttons:** every bound reset or recover button is caught during a round, including recover, recover to road, load home and the big-map teleport.
  - If one suddenly works freely, an action was renamed or added.
  - Compare against the game's `lua/ge/extensions/core/input/actions/*.json`.
  - Also check the `competitive` template in `core/input/actionFilter.lua`.
- **Cop placement:** cops spawn on a road near the runner (map graph API), and the gas station list loads on West Coast. The server log shows `N gas stations loaded`.
- **Car pool:** only stock cars and trucks are picked. If mod cars show up, the `Source` naming changed.

## BeamNG.drive: vehicle Lua and jbeam (cop lights, freeze, recovery)

**Used in:** the command strings in `ai.lua`, `inputs.lua` and the main file, plus `lightbar.lua` and `vehicles.lua`.

**What we use:**
- **Vehicle commands:**
  - `electrics.set_lightbar_signal(1|0)`: light bar on with no siren. `1` means lights only.
  - `controller.setFreeze(1|0)`, `fire.explodeVehicle()`, `ai.setMode(...)`, `ai.setTargetObjectID(id)`.
  - We patch `recovery.startRecovering` / `stopRecovering` / `loadHome` (`VEHICLE_PATCH`) so that recovery buttons go through our rules.
  - The `beaconSpin` controller spins while `electrics.values.lightbar > 0` (`lua/vehicle/controller/beaconSpin.lua`).
- **Jbeam loading:**
  - `require("jbeam/io")`: `startLoading({"/vehicles/<model>/", "/vehicles/common/"})`.
  - `getPart(ctx, name)` returns a part with processed `slots2` entries (`name`, `allowTypes`, `denyTypes`, `default`).
  - `getAvailableSlotNameMap(ctx)` and `getCompatiblePartNamesForSlot(ctx, slot, map)`.
- **Recognising emergency lights:** we check the electrics a part uses. Emergency lights run on `lightbar`, `beaconSpin` or pattern channels such as `L1_b` / `R2_r`. Work lights run on `fog` or `highbeam`.
- **Part names:** a part only counts as the light itself if its name contains `lightbar` or `beacon`, and not `color`, `pattern` or `bulb`.

**On update, check:**
- Run the light scan against the new game files. It runs our real planner (`lightbar.plan`) on every stock config:
  ```
  python3 -I tools/lights/export.py .lightcheck          # all vehicles, or list models: ... .lightcheck etki burnside
  lua tools/lights/check.lua .lightcheck
  ```
  Compare the result with the last run. As of 0.40.5 these cars got a light on almost every non-police config:
  - etki: roof beacon, 33/35
  - burnside: beacon, 23/24
  - miramar: light bar, 27/27
  - pickup: police light bar, 61/73
  - midtruck: four beacons

  A car that drops to "nothing added" means BeamNG renamed parts or electrics, or moved slots.
- In game, a cop round in a car with a beacon (Burnside) and one with a light bar (Miramar): the lights flash and there's no siren.
- **Line of sight:** in a cop round, the client log shows `runner in sight (N m)` / `out of sight` as you drive past buildings and hills. If it never changes, `castRayStatic` or the MPVehicleGE fields changed.
- **Freeze and recovery:**
  - During prep you can't drive (freeze).
  - Pressing recover during the chase is refused and doesn't rewind the car. If it rewinds, the `recovery.*` function names changed.

## BeamNG.drive: UI (Vue apps, layouts)

**Used in:** the five apps in `client/ui/modules/apps/` (`CopsAndRobbersAnnouncements`, `CopsAndRobbersHud`, `CopsAndRobbersHowToPlay`, `CopsAndRobbersPanel`, `CopsAndRobbersLeaderboard`) and the shared kit in `client/ui/modules/copsAndRobbers/`, plus `hudfeed.lua`, `apps.lua` and `placement.lua`.

**What we use:**
- **Mod Vue loader** (`ui/ui-vue/src/services/uiMods/compiler.js`): it compiles `app.vue` at runtime. `app.json` uses `vue: true`, `directive`, `domElement`, `interactive`, `isAuxiliary` and `css` (the default placement).
- **Imports:**
  - `useEvents()` from `@/services/events`, `$translate` from `@/services` (map names), and `useBridge().api.engineLua` / `serializeToLua` from `@/bridge`.
  - Components from `@/common/components/base`: `BngButton` with `ACCENTS` (main, secondary, ghost, destructive), `BngTabs`, `BngIcon` with `icons`, `BngSwitch`, `BngDropdown` (items are `{value,label}`), `BngColorPicker` and `BngCardHeading`.
  - Directives from `@/common/directives`: `vBngTextInput` (it calls `setCEFTyping` so typing doesn't drive the car) and `vBngTooltip`.
  - We use none of the legacy ones (`styles/modules/legacy/*`, `bngOldIcon`, `bngDrawerOld`, `utility/tab.vue`, accent `custom_old`, class `bng-app`).
- **Design tokens** (on `:root`, no import needed; `ui/ui-vue/src/styles/modules/_colors.scss`), mapped to our meanings in `CnrRoot.vue` as `--cnr-*`:
  - Runner `--bng-add-red-500` (fills) and `-400` (text); cop `--bng-add-blue-500` and `-400`; attention `--bng-ter-yellow-200`; good `--bng-add-green-400`.
  - Accent `--bng-orange-b400`, main button `--bng-orange-500`, your own row `--bng-orange-300`.
  - Text `--bng-off-white`, muted `--bng-cool-gray-100` (only inside cards), surfaces `rgba(var(--bng-off-black-rgb), …)`, corners `--bng-corners-1` / `-2`.
  - Also read: `--bng-orange-200`, `--bng-orange-600`, `--bng-cool-gray-50` / `-400`, `--bng-ter-peach-100` / `-500`, `--bng-black-o2`, the `-rgb` triplets of the colours above.
- **Fonts:** `"Overpass", var(--fnt-defs)` for display text (`--fnt-defs` is Noto Sans), `var(--fnt-mono)` (Overpass Mono) with tabular numbers for times and counts.
- **Icons** (from `ui/ui-vue/src/assets/fonts/bngIcons/bngIcons.js`; an unknown name renders as a red placeholder): `abandon`, `arrowSmallDown`, `arrowSmallLeft`, `arrowSmallRight`, `arrowSmallUp`, `carChase01`, `caution`, `checkmarkBold`, `cogSolid`, `cup`, `danger`, `eyeSolidClosed`, `eyeSolidOpened`, `flag`, `info`, `lockClosed`, `mapPoint`, `minus`, `play`, `plus`, `restart`, `stopwatchArrows02`, `strobeLights`, `timer`, `undo`. `make vuecheck` checks every name against that file.
- **UI scale:** the game sets the root font size to 16px × UI scale, so our styles use `rem` (and `em` in `app.json` placements).
- **Layouts** (`ui_appLayouts`):
  - `getCurrentLayout()`, which returns `filename`, `apps` and `userFileExists`.
  - `getAvailableLayouts()`, `addApp(filename, app, placement)` (it writes silently), `removeApp(filename, index0)`, `setCurrentLayout(filename)` and `resetLayout(filename)`.
  - User layouts live in `/settings/ui_apps/layouts/` and the stock originals in `/settings/ui_apps/originalLayouts/`.
  - BeamMP ships its `beammp` layout inside `mods/multiplayer/beammp.zip` at the user path (`settings/ui_apps/layouts/default/beammp.uilayout.json`), not as an original. So `userFileExists` is already true, `resetLayout` has no original, and `addApp` writes a disk file that hides the zip's. We tell them apart with `FS:getFileOriginInfo(path).archivePath`.
- **How the apps open** (`apps.lua`, `placement.lua`):
  - Announcements and the HUD are sticky: placed automatically on join and put back if the player removes them.
  - How to play is added on demand (the lobby and prep buttons, and on a player's first join); the Panel and the Leaderboard are added and removed by the lobby card buttons or opened by the player in Esc > UI Apps. All are removed on leaving the server.
  - Opening and closing is `ui_appLayouts.addApp(ui_appLayouts.getCurrentLayout().filename, "<app>", placement)` and `removeApp(filename, index0)`, where the index is found in `getCurrentLayout().apps` by `appName`.
- **Click-through** (verified in game): `interactive: "no"` in `app.json`, a `pointer-events: none` container and `pointer-events: auto` on the cards and buttons. Clicks still reach the game and other apps under the empty area, and other apps can still be selected and moved in the layout editor. Our apps also set `css` placements (`left: 50%` for centred apps, sizes in `em`).
- **UI Apps picker:** `isAuxiliary: true` hides an app unless "Include auxiliary content" is on (`ui/appSelector/general.lua`). Announcements, the HUD and How to play are auxiliary; the Panel and the Leaderboard are not, so they show in the picker. In simple-menu mode apps with `interactive: "required"` are hidden too.
- **Shared kit** (verified in game): `client/ui/modules/copsAndRobbers/` (`CnrRoot.vue`, `CnrCard.vue`, `RoleChip.vue`, `hud.js`, `fit.js`, `format.js`) is imported by relative path from an app, e.g. `../../copsAndRobbers/CnrCard.vue`. Relative imports also work between files of one app.
- **`BngColorPicker`:** the model is `{hue, saturation, luminosity}`, all 0..1; `view="compact_luminosity"` works (the `luminosity` view shows only the saturation slider in simple-menu mode).
- **Game internals the leaderboard and panel rely on** (not documented API, so check them after an update):
  - `BngTabs` reads each tab's `tab-heading` from the vnode props.
  - The `#after-tab-list` slot of `BngTabs` renders between the tab list and the content (the leaderboard's filter row).
  - The CSS variable `--bng-tabs-content-overflow` controls the tab content's overflow.
  - `BngDropdown`'s `#display` slot shows the selected value (real map names, build names).
  - `BngButton` takes its text colour from `--bng-button-text-enabled-color`.
- **Placement format** (`ui/ui-vue/src/modules/apps/placementResolve.js`): centred axes are `"50%"` and sizes are in `em`. `margin: auto` is deprecated and read-only.
- **Debugging:** every app captures Vue errors and writes them to the game log as `log("E","cnr_ui","[cnr_ui] <app> <component> <info>: <message> | <at>")`, so a broken component names itself: `grep cnr_ui beamng.log`.

**On update, check:**
- **`make vuecheck`** passes: it compiles every Vue file's script, template and SCSS (SCSS imports resolve against the game's UI sources), syntax-checks the `.js` files under `client/ui` with `node --check`, and checks the icon names. It does not resolve JavaScript imports, so a renamed or removed game export only shows up in game (see Changed imports below).
- **All apps load:** no "Runtime compile error" for our apps and no `cnr_ui` lines in the client log.
- **Announcements and HUD:** they sit at top middle and bottom centre, scale with Options > Display > UI scale, come back by themselves if removed, and don't block clicks anywhere except on their cards and buttons.
- **Changed imports:** if an import broke, grep the game's `ui/ui-vue/src` for the name. Check the component props in `common/components/base/bng*.vue`. Check whether `@/bridge` still exports `useBridge` with `api.engineLua`.
- **Panel and leaderboard:**
  - The panel's buttons do something, which proves `engineLua` reaches `copsAndRobbers.panel`.
  - The tabs show the right headings, the leaderboard's filter row sits under its tabs, and the dropdowns open inside the app and show real map names.
- **Layout files:** leaving the server removes all our apps from the layout file in `settings/ui_apps/layouts/`. A stock layout copy we created gets deleted again, and so does the disk copy of BeamMP's `beammp` layout (check that `settings/ui_apps/layouts/default/beammp.uilayout.json` is gone from the user folder after leaving).
- **Placement format:** read the header comment of `placementResolve.js` again. If it changed, update the placements in `apps.lua` and the `css` in every `app.json`.

## BeamNG.Earth (mod API)

**Used in:** `copsAndRobbers/geo.lua` and the main file (geo mode is on when the map is `beamng_earth`). The server side is `cnr/geo.lua`, plus the geo paths in `main.lua`.

**What we use from `beamngEarth_api`:**
- `version() == 1`, `toGeo(x,y,z)` → `lat, lon, h`, and `toGame(lat, lon, h)` → `x, y, z`.
- `rebasing()`, `has("gps" | "places")`.
- `places(lat, lon, {radius, categories={"gas_station"}}, callback)`. The callback gets `{places={{lat, lon, name, open}}}`, and we skip places where `open == "permanently_closed"`.
- `gpsSet(lat, lon, label)`, `gps()`, which returns `.remaining` (metres) and `.planning`, and `gpsClear()`.
- The hook `onBeamNGEarthRebased(info)`, where `info.purpose` is `"teleport"` or something else.
- Each player has their own floating origin. That's why positions travel as lat/lon, and why the server converts with WGS84 → ENU (`cnr/geo.lua`).

**On update, check:**
- On `beamng_earth`, there's no "needs a newer BeamNG.Earth (API v1)" toast. If it appears, `version()` changed. Read the mod's `docs/ADDONS.md` for the new contract.
- **Distances:** cops see "Runner 2.4 km by road NE" after a last-seen ping (GPS), and the 1 km cop reset uses real distance.
- **Gas stations:** the server log shows `N new gas stations on beamng_earth` while you drive, so `places` works.
- **Teleports:** teleporting far away counts as a teleport for the runner (it's announced), and for a cop it moves the AI cars along with you. If not, the rebase hook changed.

## Development tools

- **Lua:** stock `lua` (5.3 or newer) for `make test`, `luajit` for compile checks (the game runs LuaJIT, so client code stays Lua 5.1 compatible), `make vuecheck` (Node, with the game's UI sources) for the Vue apps, and `python3` for `tools/lights/export.py`.
- **Build:** `zip` for `make package`.
