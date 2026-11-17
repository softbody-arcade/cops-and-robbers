# Dependencies and compatibility checks

The mod has no package dependencies. It does lean on three external systems: BeamMP (server and client), BeamNG.drive and BeamNG.Earth. This file lists what we use from each one, where in our code we use it, and what to check when that system updates.

Versions in use on 2026-11-15:
- BeamNG.drive 0.40.5.0
- BeamMP Server 3.9.3 (Lua 5.3.5)
- BeamMP Launcher 2.8.1
- BeamNG.Earth mod API v1

Checked against: the game-engine facts in this file were last checked on 2026-11-16 against BeamNG.drive 0.40.5.0, the BeamMP client mod 4.23.1 and BeamMP Server 3.9.3.

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
   - **Sky:** with Time of day Night and Weather Rain (panel), rain shows, the AI cars have headlights, and everything is back after End chase. The prep card shows the round's date (a December or January one for Snow). Set Time of day and Weather back to Random afterwards: the panel writes the live server's `config.json`.
   - **Traffic** (needs `MaxCars` of 4 or more for practice): traffic cars spawn in prep and stand still until GO; they have no name tags and there are no police, emergency vehicles or taxis among them; driving into one gives "crash penalty 10s (traffic)"; all are gone after End chase. With Night and Clear weather, traffic standing still before GO is lit; with Night and Fog, traffic is lit while standing and while driving; with Rain it slows on wet roads and gusts push it.
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
  - Our own client→server events are registered with `MP.RegisterEvent` too, among them `cnr_sitOut` (`{ on = boolean }`; anything else is ignored)
  - `MP.CreateTimer():GetCurrent()`, `MP.CreateEventTimer` / `MP.CancelEventTimer` (the 250 ms `cnr_tick`)
  - `MP.Get(MP.Settings.Map)` (the map path; we parse `levels/<name>/`) and `MP.Get(MP.Settings.MaxCars)` (a number; it caps the traffic per player, and anything else means no cap)
  - `Util.JsonEncode` / `JsonDecode` / `JsonPrettify`, `FS.CreateDirectory` / `Remove` / `Rename`
- **Events and the data shapes we parse:**
  - `onChatMessage(pid, name, msg)`: returning `1` hides the message. We use it only to hide a typed `/cnr ...` from chat; the sender gets a HUD notice pointing to the Cops and Robbers card instead.
  - `onVehicleSpawn(pid, vid, data)` and `onVehicleEdited(pid, vid, data)`. The data is `...:pid-vid:{json}`, and we parse from the first `{`. The JSON has `jbm` (model) and `vcf.partConfigFilename` / `vcf.parts`. Returning `1` from an edit **deletes the car**.
  - **Traffic is synced like any car:** BeamMP sends every car a player's game spawns, traffic included, through `onVehicleSpawn`, counts it against `MaxCars` and shows it to everyone. Nothing in the data marks traffic, so the server trusts the game's own report (`cnr_trafficCars`) and caps the extra cars. Moving a traffic car to a new spot reaches us as `onVehicleReset` for that car.
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
- **Line of sight:** `MPVehicleGE.getVehicles()`, keyed by `"pid-vid"` with `gameVehicleID`, `isSpawned` and `isDeleted`. Also `MPVehicleGE.getPlayers()[pid].activeVehicleID`, a `"pid-vid"` key for the car that player is driving or viewing. The server's round car list (`cnr_roundCars`) comes first; these are used to find the runner's car on a cop's game.
- **Name tags:** setting `MPVehicleGE.getVehicles()[key].hideNametag = true` hides BeamMP's name tag over that car (the check is in BeamMP's name tag drawing, `MPVehicleGE.lua`). We set it on every traffic car and clear it after the round. On update, check that traffic cars still show no name tag in a round.
- The GE hook `onBeamMPServerLeave`.
- **Spectating** (`copsAndRobbers/spectator.lua`):
  - `MPVehicleGE.getOwnMap()` (game vehicle id → vehicle, for every car this game owns, traffic included) finds a sitting-out player's cars even while they watch someone else's car; `gameplay_traffic.getTrafficData()[id].isAi` leaves traffic out of it. Their own AI traffic goes first with `gameplay_traffic.deleteVehicles()` (`traffic.removeOwn`, as round players' traffic goes), and a walker (`unicycle`) is removed but never brought back.
  - `MPVehicleGE.getVehicleByGameID(id).ownerName` (or the pid in `serverVehicleString`) names the watched car.
  - A car the game deletes with `veh:delete()` is removed for everyone (`onVehicleDestroyed` sends `Od`), and one it spawns is sent like any car. BeamMP's own snapshot of a car is `MPHelpers.simplifyVehConfig` plus `MPHelpers.getColorsFromVehObj(veh)` for the paint; we use the latter for the parked car's paint.
  - Entering another player's car is allowed (`onVehicleSwitched`). With `skipOtherPlayersVehicles` on, BeamMP throws you off other players' cars while this game owns any vehicle (`localVehiclesExist`, walkers and traffic included), which is why a spectator's own cars, walker and traffic are all removed. BeamMP marks other players' cars as remote (`mpVehicleType` `R`) and turns local input off on them (`input.setAllowedInputSource(name, "local", false)` in `MPInputsVE.lua`), so a spectator never drives them.
  - On update, check: a sitting-out player's car disappears for the others in prep and comes back where it stood after the round; Tab goes from car to car on a spectator's game and the car doesn't react to the spectator's keys; the HUD names the watched player.
- **Hiding name tags:** `MPVehicleGE.getVehicles()[key].hideNametag = true` on the runner's key in cops' games (while cops don't see the runner) and on every cop's key in the runner's game (the whole round). Cleared when spotted, after the round and on leaving. On update, check the tags still hide and return.
- **Lights for other players:** BeamMP sends a car's electrics only when a value changes (`MPElectricsVE.check()`, 15 times a second). It also sends a replaced car (`core_vehicles.replaceVehicle`, same model) to the others only after a 15 s delay (`MPVehicleGE.lua` `editSyncTimer`), and that rebuilds their copy with every light off. So lights the mod set at placement never reached the others. During a round, every 5 s (`ownLights.SYNC_INTERVAL`) the client sends the light state of the cars it owns (round car, practice AI cars, traffic) through `MPElectricsGE.sendElectrics(json, gameVehicleID)`. The payload is `lights_state`, `lightbar` and a changing `cnrLightSync` counter that gets past BeamMP's duplicate check; the other games apply it in `MPElectricsVE.applyElectrics` (`setLightsState`, `set_lightbar_signal`).
- **Mod mounting:** the mod is mounted when you join. Our UI apps then need an `onFilesChanged` refresh.
- **Launcher on Arch:** the wrapper in `~/.local/bin/beammp-launcher` sets argv[0] and the working directory. The AUR binary name broke `CheckName()` before.

**On update, check:**
- The client log shows our handlers being added, and the round starts at all.
- `cnr_myVehicle` reaches the server: your own car counts in catch and reset checks. If the vid parse breaks, the server never learns which car is yours.
- The five apps appear in Esc > UI Apps (or are placed automatically, for Announcements and the HUD).
- Rejoin within the same game session. If notices or panel replies now show twice, `AddEventHandler` re-registration has changed.
- With a second player in a round: about 20 s after the round starts, they see your headlights at night and, as a cop, your light bar (and siren, if on).

## BeamNG.drive: game engine Lua (GE)

**Used in:** the client modules.

**What we use, by area:**
- **Vehicles** (`vehicles.lua`, main file):
  - `core_vehicles.getConfigList(true).configs`, using the fields `model_key`, `key`, `pcFilename`, `Type` and `Source`. `Source == "BeamNG - Official"` means stock.
  - `core_vehicles.getModel(model).model.{Name,Brand,Type}`.
  - `replaceVehicle` / `spawnNewVehicle(model, {config=<path or format-2 table>, paint, pos, rot, autoEnterVehicle})`.
  - `createVehiclePaint`, `jsonReadFile`, `deepcopy`.
  - Configs in `format: 4` are skipped for cop lights.
- **Hiding the runner on the minimap** (`hiding.lua`): we wrap the game's `ui_apps_minimap_vehicles.drawOtherVehicles` and, while it runs, swap the global `activeVehiclesIterator` for one that skips the hidden cars (the runner on cops' games, every cop on the runner's game), then restore it. The wrapper falls back to the original if anything is off and is unloaded before the extension. Each wrapper keeps the original of the table it wrapped: when the minimap extension reloads as a new table, the old table gets its own original back and the new one is wrapped, so no table ever calls another table's draw. On update, check that those two names still exist and the minimap still lists other cars; if not, the hidden cars show on the minimap again.
- **Helicopter searchlight** (`heli.lua`): a `SpotLight` scene object named `cnr_heli_light` (`createObject`, `registerObject`, `canSave = false`, `scenetree.MissionGroup:addObject`, `scenetree.findObject`, `setPosition`, `delete`), with `brightness`, `range`, `innerAngle`, `outerAngle`, `color`, `castShadows`, `flareType` (`BNG_LightFlare_1`) and `flareScale` set when it is made. Each frame it sets `rotation` from `quatFromDir(dir, up)` turned with `toTorqueQuat()` and written as "x y z w", the way the game's flowgraph `spawnLight` node does, and it sets `brightness` and `flareScale` while it flies in, flies away or fades, and `range` when the distance to the lit spot changes. The light sits at the flying helicopter (50 m up, trailing or circling the runner's car, or circling where it searches), only while the helicopter is up (tracking or searching) and it is night. Night comes from the mod's own `sky.isNight()`, which reads `core_environment.getLightState().isNight`. The light is deleted after the round, a cancel, leaving and a map change. On update, check: the light still appears at night and points down at the car, it sweeps the ground around the spot while the helicopter searches, a bridge deck or tunnel roof blocks the beam, and no `cnr_heli_light` is left in the scene afterwards.
- **Helicopter beam in the air** (`heli.lua`, `beam.lua`):
  - `require("utils/debugDraw").drawTriSolid(a, b, c, packedColor, true)` (the game's FFI `BNG_DBG_DRAW_TriSolid`, as its road editor uses it) draws a solid, see-through, depth-tested triangle. Each beam quad is two triangles in the quad's winding. It is backface-culled, so each quad is drawn in the winding that faces the camera. `color(r, g, b, a)` returns a packed number in 0.40, which the FFI call takes; `debugDrawer:drawQuadSolid` refuses it ("expect userdata, got number"), so the beam doesn't use it.
  - `core_camera.getPosition()` gives the camera position, for the winding and the fade near the camera, and for the rotor sound's muffle.
  - The vehicle's `getVelocity()` gives the runner's velocity for the helicopter's flight; without it we use position deltas.
  - `castRayStatic(origin, dir, maxDist)` returns the distance to the first static hit. We cast it:
    - from the light to the lit spot every 0.25 s, so a bridge deck or tunnel roof ends the beam
    - for cover, from the helicopter to three points on the car up to 400 m away (`copsAndRobbers/shelter.lua` `inSight`), every 0.25 s
    - while the helicopter searches, straight down from 100 m above the sweep point (200 m long) every 0.25 s, so the lit spot lies on the ground
    - for the tunnel walk (`tunnels.lua`), as the roof check (`shelter.roofed`, upward rays) 1.5 m above the car and above each road node it walks
    - from the camera to the helicopter every 0.25 s, to muffle the rotor sound (`heliSound.lua`)
  - `BNG_LightFlare_1` is a flare datablock in the game's `art/datablocks/lights.datablocks.json` (inside gameengine.zip). It is the light's `flareType` and gives the glare.
  - On update, check: the beam still draws as a soft cone ending on the road, it fades near the camera, a deck over the car ends it, and the glare shows when you look up at the light.
- **Helicopter sound** (`heliSound.lua`):
  - An unsaved `SFXEmitter` named `cnr_heli_sound`, made as the rain sound is: `createObject("SFXEmitter")`, `Sim.upcast` when it exists, and the fields `fileName` (`/art/sound/cnr/heli_rotor.ogg`), `is3D` "1", `isLooping` "1", `referenceDistance` "40", `maxDistance` "800" and `volume` "0" set with `setField`. Then `canSave = false`, `registerObject` (checked with `scenetree.findObject`; if it didn't register, `delete()` and a log line), `scenetree.MissionGroup:addObject`, `setPosition` and `play()`. Probe-verified in game (2026-11-17): made this way it plays the file in 3D and loops.
  - Every frame it is looked up by name (`scenetree.findObject`, no reference is kept) and moved to the helicopter with `setPosition`; it is removed with `delete()`.
  - **The volume call:** `setVolumePitchCT(volume, 1, 0, 0)`, written as it fades. The game and our rain only call it on `track` emitters; on a playing `fileName` emitter it works too (checked in game on 2.9.4, 2026-11-17: the rotor is heard). On update, check it still changes the volume; if not, write the `volume` field instead (`setField("volume", 0, tostring(v))`, then `postApply()`).
  - **The file:** "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0 (cut from a US government video, marked loopable), converted to a mono OGG (Vorbis q5, 48 kHz, 6.3 s, 64 KB) at `client/art/sound/cnr/heli_rotor.ogg`. `make package` adds the client's `art` folder to the zip. CC0 needs no credit; the author asks for a link, so this file and the README name it.
  - On update, check: the sound plays in 3D at the helicopter (louder as it flies in, quieter as it flies away), its volume follows the fades (Helicopter sound off and on fades it out and in over about 1 s, and it fades over the fly-away's last 3 s), it is quieter behind a building, and no `cnr_heli_sound` is left in the scene after the round.
- **Placement and roads** (`roads.lua`, `tunnels.lua`):
  - `map.getMap().nodes[id].pos` and `map.findClosestRoad(pos, radius)` (two node ids, then the distance to the road; the nearest edge by straight distance, whatever its direction, so next to a narrow median it can be the other carriageway. We check it against the runner car's `getDirectionVector()` and, if it points the wrong way, take a fitting edge at most 5 m further, `MEDIAN_WIDTH`. `tunnels.lua` uses the distance and walks only from a road at most 15 m away).
  - `map.getGraphpath().graph[a][b].{oneWay,inNode,gated}`: every link from both ends. Its `len` is a routing cost (length divided by drivability, plus 10 km on gated roads), so lengths come from node positions. Only the link where a private road meets a public one is gated (`processPrivateRoads` and `createTrafficExclusionArea` in `lua/ge/map.lua`); the private roads behind it have `gated` 0.
  - `map.getMap().nodes[a].links[b].type == "private"` (one-sided, so we look from both ends) marks those private roads. Only the straight-line fallback reads it, so a cop is never placed behind a gate; the search by road never crosses a gated link anyway.
  - The tunnel walk reads `getGraphpath().graph` for the links and `getMap().nodes[].pos` for the positions.
  - `spawn.safeTeleport(veh, pos, rot)`, `vec3`, `quatFromDir`.
  - On update, check: `getMap().nodes[].links` is still one-sided (`convertToSingleSided` in `lua/ge/map.lua`; we read only its `type`, from both ends), the graph fields above keep their names, in game cops start a short drive from the runner, facing it, and losing the helicopter in a known tunnel still sends it to the exit ahead.
- **Inputs** (`inputs.lua`):
  - `core_input_actionFilter.getActionTemplates().competitive`, `setGroup` and `addAction`.
  - `core_input_bindings.bindings[].contents.bindings[].action`.
  - The action names in `LOCKED_ACTIONS` and `RESET_BUTTONS`.
  - Free cam in practice leaves the game's `actionTemplates.freeCam` actions (`toggleCamera`, `dropCameraAtPlayer`) open, so on update `FREE_CAM_ACTIONS` in `inputs.lua` must still match that template.
  - `commands.isFreeCamera` and `commands.setGameCamera`, to leave free cam when a real round starts.
  - Spectators: `switch_next_vehicle` and `switch_previous_vehicle` (Tab and Ctrl+Tab by default) stay open with the free camera actions. They run `core_input_vehicleSwitching.switchCycleVehicle`, which enters the next vehicle in the game's own order and then fires the GE hook `onVehicleCycleSwitchPerformedByUser(dir, player, vehId)`; when that isn't a round car we `be:enterVehicle(0, car)` the next round car instead, and `commands.setGameCamera()` from free cam. `commands.setFreeCamera()` before a sitting-out player's car is removed keeps the camera where it was. On update, check the hook still fires and the order still skips `unicycle` and `playerUsable = false` cars.
  - Spectators' cars come back with `core_vehicles.spawnNewVehicle(model, { config, pos, rot, autoEnterVehicle })` from `core_vehicle_manager.getVehicleData(id).config` with its `partsTree` flattened by `core_vehicle_partmgmt.partsTreeToPartsMap` (as the career inventory does).
  - We replace the globals `resetGameplay` and `spawn.teleportToLastRoad`, and `freeroam_bigMapMode.teleportToPoi`.
- **Gas stations:** `freeroam_facilities.getFacilitiesByType("gasStation")` and `freeroam_gasStations.gasStationCenterRadius(f)`.
- **Evolving car mode:**
  - `core_vehicle_manager.getPlayerVehicleData().config` (a `partsTree` plus `vars` in 0.40) and `core_vehicle_partmgmt.partsTreeToPartsMap`, the same conversion the game's own "save config" uses.
  - `FS:getFileOriginInfo(pc).archivePath` (configs from `/mods/multiplayer/` count as server-provided).
  - The `parts_selector` action is the only way into the parts and paint menu, so closing it closes paint too.
  - On update, check that a changed part shows up in the HUD's change list, that Apply rebuilds everyone's car to match, and that the game's config format is still `format: 2` with `parts` and `vars`.
- **Car settings carry over** (`copsAndRobbers/modes.lua`): vehicle Lua `controller.getState()`/`setState()` and `powertrain.getState()`/`setState()`, the game's own state API for controllers (ESC, drive modes) and drivetrain devices (diff locks, transfer cases); plus `serialize` and `obj:queueGameEngineLua`. Those states mix driver settings with physical state (the frozen flag `frzn`, door couplers `_groupState`, the current gear `grb_idx`, post-crash brake, fuel and positions), so only keys on an allow list of setting suffixes are saved and put back (`modes.lua` `isSetting`). On update, check that turning traction control off and starting a new round keeps it off, and look for new controller states in `lua/vehicle/controller/` worth adding to the list.
- **Line of sight** (`copsAndRobbers/sight.lua`):
  - `castRayStatic(origin, dirNormalized, length)` returns the distance to the first static hit (terrain, buildings), and `>= length` means clear. Vehicles don't block it.
  - We cast both ways, as the game's own `isVisible` does, because single-sided faces only block from one side.
  - Also used: `veh:getDirectionVector()` and the global `log`.
- **Sky, weather and grip** (`copsAndRobbers/sky.lua`, `surfaces.lua`, `wind.lua`):
  - `core_environment`: `getState` / `setState(state, lerpSeconds)` (the 3 s sky blend: clouds, fog, fog height and time; it only advances while changes are enabled, so we unlock for the blend and lock again; a new state mid-blend shortens it to 0.3 s, so we clear it first with `setState(nil)`; fields `time`, `play`, `dayLength`, `year`, `month`, `day`, `cloudCover`, `fogDensity` in thousandths, `windSpeed`, `groundWind`, `temperatureCurveOverrideC`), `getInitState` (`cloudCover` runs 0 to 3 and `fogDensity` 0 to 50 in the game's environment menu; our weathers use clear 0.4, fog 1.5, cloudy 1.8, rain and snow 2.2, storm 3.0, and fog density clear 0.4, cloudy 1, rain 4, snow 5, storm 8, fog 15, picked from screenshots; you see roughly 3000 / fog density metres; cloud wind `windSpeed` runs 0 to 10 with the map's own at 0.1, ours clear and fog 0.1, cloudy 0.3, snow 0.4, rain 0.5, storm 1.5, because 8 looked really rapid in game), `enableChanges` / `canChange` (the lock: every setter, `setState` and its fade do nothing while locked), `getSolarTimeOfDayValue(key, state)` (works the named time out from that state's date, latitude and longitude; the date is set in the same `setState` as the time, and the game applies it before the time and the night lights; the mod only reads `latitude` from `getState`, to move the date six months on maps south of the equator) and `timeOfDayKeyToTime` (keys sunrise, morning, noon, afternoon, sunset, night), `setTemperatureProfile({ averageC, minC, maxC })` (does nothing on maps with no curve; we send our own two-point `temperatureCurveOverrideC` in `setState` instead), `getLightState().isNight`, `groundModels[name].{cdata, isAlias, parent}`.
  - `be:setGroundModel(name, cdata)`, `be:queueAllObjectLua(cmd)`, `be:setGroundWind(vec3)`.
  - `createObject("Precipitation")` with the fields `dataBlock`, `numDrops`, `dropSize`, `minSpeed`, `maxSpeed`, `boxWidth`, `boxHeight`, `useWind`; `numDrops` (lowering it on live rain thins it at once, probe-verified 2026-11-16; raising it from 0 is checked in game; the sky fade steps it) and `splashSize`; `registerObject`, `delete`, `scenetree.findObject`, `scenetree.MissionGroup:addObject`, and `setHidden` (or the `hidden` field) to hide it under a roof. The engine's own `doCollision` (on by default) does not keep rain out of tunnels, because drops are created inside the box around the camera, under the roof too; the roof check (`copsAndRobbers/shelter.lua`) uses `core_camera.getPosition()` and upward `castRayStatic`. On update, check: driving into a tunnel in a rain round hides the rain, and it keeps raining under a high bridge.
  - **Rain sound:** an unsaved `SFXEmitter` with `track = "amb_rain_medium"` (`art/sound/environment/amb_rain_medium.ogg`, a 2D loop), created like `core/audioForest.lua` does and added to the mission group; `setVolumePitchCT(volume, 1, 0, 0)` and `play()`. Volume 1.0 in rain, 2.0 in a storm, half under a roof. On update, check: rain in a round makes the sound, it fades with the rain, and it is gone after the round.
  - **Game data:** the precipitation datablocks `rain_medium` and `Snow_menu` (`art/datablocks/managedDatablocks.datablocks.json` in `gameengine.zip`); the ground models and their alias lists in `art/groundmodels.json` (targets ASPHALT, ASPHALT_OLD, ASPHALT_PREPPED, COBBLESTONE, RUMBLE_STRIP, GRAVEL, DIRT, DIRT_DUSTY, DIRT_DUSTY_LOOSE, GRASS, GRAVEL_WET, MUD; sources ASPHALT_WET, GRAVEL_WET, MUD, SNOW).
  - **Map materials:** maps say which surface a road or terrain layer is by naming one of those ground models or an alias (`groundmodelName` / `groundType` in their material files). Checked on 0.40.5 for west_coast_usa, Utah, italy, east_coast_usa, johnson_valley and jungle_rock_island. A surface name we don't list, or a map with its own `groundModels/` folder (a mod map), stays dry in rain and snow.
  - `getState().groundWind` and `getInitState().groundWind` are the game's live wind vector, not copies; we copy it when saving.
  - The gusts (`be:queueAllObjectLua`) and the grip swap act on every car in the game, traffic included. The vehicle AI reads grip from the ground model (`obj:getStaticFrictionCoef()` in `lua/vehicle/ai.lua`), so traffic slows on wet roads and snow by itself.
  - While the sky is locked the game skips its own `onVehicleSpawned = applyGroundWind` (the lock check in `applyGroundWind`), so cars spawned during a round get wind only from our 0.25 s updates.
  - On a map change the game's `onClientEndMission` reloads ground models, clears the temperature override and zeroes the wind, but never undoes `enableChanges(false)`; that's why our `drop()` puts the lock back. Check after an update: leave mid-round or change map, and on the next map the environment menu works and grip is normal.
  - On update, check: the functions above still exist (grep the game's `lua/ge/extensions/core/environment.lua`); `groundmodels.json` still has the listed names and aliases with similar values; the two datablocks still exist; the map scan below shows no new road, dirt or grass surface names (add any to `surfaces.lua` `RULES`); in game, a practice round with Night and Rain shows rain and night lights, wet roads slide, gusts push the car, the environment menu is greyed out, and after End chase the sky, grip, wind and menu are back. Also check the sky blends: round start blends into the sky over about 3 s; New sky pressed several times quickly heads for the last pick; New sky from clear to rain fades the rain and sound in, and rain to clear fades both out; GO right after New sky lands the sky at once; round end blends your own sky back and the environment menu works again; in a tunnel in rain the rain is hidden and the sound is quieter, but not under a street-light arm; the environment menu's temperature in a December snow round is below 0 °C and in a July clear noon around 30 °C, also on Hirochi Raceway.
  - The map scan (prints each map's surface names with counts):
    ```bash
    for z in ~/.local/share/Steam/steamapps/common/BeamNG.drive/content/levels/*.zip; do echo "== $(basename "$z" .zip): $(unzip -p "$z" '*.json' 2>/dev/null | grep -oi '"groundmodelName" *: *"[^"]*"\|"groundType" *: *"[^"]*"' | sed 's/.*: *"//;s/"//' | tr a-z A-Z | sort | uniq -c | sort -rn | awk '{printf "%s(%s) ", $2, $1}')"; done
    ```
- **Traffic** (`copsAndRobbers/traffic.lua`, `gameplay_traffic` in `lua/ge/extensions/gameplay/traffic.lua`):
  - `gameplay_traffic.deleteVehicles()` (removes only cars in the traffic table that are AI or carry the `isTraffic` dyn field, never our practice AI cars). Before each call we take the player's own car out with `removeTraffic(id)` and clear its `isTraffic` field, because a player who switched into a lobby traffic car (the off-by-default `trafficEnableSwitching`) gets that object reused as their round car. `setTrafficVars({ aiMode = "traffic", activeAmount, enableRandomEvents = false })`, `spawnTraffic(amount, group)` and `getTrafficData()[id].isAi`.
  - We call `spawnTraffic`, not `setupTraffic`: `setupTraffic` adds police cars (`gameplay/police.lua`, when asked) and a reserved taxi (`gameplay/taxi.lua`) on top of the amount, which would go over `MaxCars`. `spawnTraffic` spawns exactly the group we pass, but it doesn't reset `aiMode`, which the game's "AI: all vehicles chase/flee" menu changes; that's why we set it.
  - `gameplay_traffic_trafficUtils.createTrafficGroup(n)` gives `{ model, config }` entries. We keep the ones whose config list entry (`core_vehicles.getConfigList(true).configs`, matched on `model_key` and `key`) has `Source == "BeamNG - Official"`, a `Config Type` other than `Police` or `Service` (taxis, ambulances, fire chiefs, prison buses, security cars, tow trucks), and no police, sheriff, interceptor, ambulance, fire, rescue, emergency or taxi in its `key` or `Name`.
  - **Headlights:** the game's own rule (`gameplay/traffic/vehicle.lua`, `onTrafficTick`): lights on in the solar night window (`core_solarTimeOfDay.getSolarNightWindow` on `core_environment.getTimeOfDay()`) and in tunnels, off in daylight, and off whenever a car is moved to a new spot. While traffic is held (frozen) before GO we also send `electrics.setLightsState(1)` every second at night (`sky.isNight()`, the same check as the practice AI cars), so held cars are lit whether or not the game's rule runs on frozen cars. In bad-weather rounds we send it every second throughout, which is why the moves don't leave cars dark for long. At night the game also respawns traffic less often (`spawnValue * 0.25`).
  - **On update, check:** the functions above still exist with the same arguments; `setupTraffic` still adds special vehicles that `spawnTraffic` skips; the config list still has the four fields; and the traffic quick check in step 4 above.
- **Player settings** (the player's own car only):
  - `electrics.values.lights_state` (read, so the mod acts only when the wanted state changes) and `electrics.setLightsState(1)` (low beam), sent as a vehicle command to the player's car.
  - `electrics.set_lightbar_signal(2)` (light bar with siren) for cops from release; `1` stays lights only.
  - `v.data.soundscape.siren` (vehicle Lua): a car without it has no siren sound, and `set_lightbar_signal(2)` would turn its lights off. The siren command is guarded on it and falls back to `1`.
  - `settings.getValue("uiUnitLength")` (metric or imperial, for the HUD chase line and How to play) and `core_environment.getLightState().isNight` for the night check.
  - On update, check: these still exist; in game, with Auto headlights on a night round the lights are on at placement, switching them off with the light key keeps them off, and Rain turns them on again; a cop with Siren on has no siren in prep or the head start and a siren from release; Siren on as a cop in an Ibishu Pigeon (or midtruck/ATV): lights stay on, no siren; with the game set to imperial the chase line and How to play show ft, mi and mph while the Host panel stays metric.
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
  - `obj:setWind(x, y, z)`, sent to every car through `be:queueAllObjectLua` (the gusts of the sky code), and `electrics.setLightsState(1)` (headlights on practice AI cars at night).
  - `controller.setFreeze(1|0)`, `fire.explodeVehicle()`, `ai.setMode(...)`, `ai.setTargetObjectID(id)`.
  - BeamMP doesn't sync a vehicle's fire or explosion, so with `explodeOnCatch` each game in the round queues `fire.explodeVehicle()` on its own copy of the runner's car: the runner's game on its own car, a cop's game on the runner's remote copy. Whether BeamMP's vehicle sync (position, damage) then undoes the explosion on a remote copy is an in-game check: a cop should see the caught car burst and stay wrecked.
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
- **Icons** (from `ui/ui-vue/src/assets/fonts/bngIcons/bngIcons.js`; an unknown name renders as a red placeholder): `abandon`, `arrowSmallDown`, `arrowSmallLeft`, `arrowSmallRight`, `arrowSmallUp`, `carChase01`, `caution`, `checkmarkBold`, `cogSolid`, `cup`, `danger`, `eyeSolidClosed`, `eyeSolidOpened`, `flag`, `info`, `lockClosed`, `mapPoint`, `minus`, `movieCamera`, `pause`, `play`, `plus`, `radar`, `restart`, `stopwatchArrows02`, `strobeLights`, `timer`, `undo`. `make vuecheck` checks every name against that file.
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
  - `BngTabs` reads each tab's `tab-heading` from the vnode props. Its `change` event carries the active tab's `heading`; the Leaderboard keys its filters off that (`onTab`), so after an update check the payload still has `heading`, or the filters never hide on the player and round detail views.
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
- We send no sky on `beamng_earth`: a change through `core_environment` flips the player's Earth sky to Manual and saves it in their Earth settings.
- We run no round traffic on `beamng_earth`: its `navgraph.lua` manages any traffic that runs. `guard()` moves traffic cars that stood still 45 s, `onTeleport()` hides all traffic until the new road graph arrives (round setup moves cops far), and `checkRegion()` sets traffic up again with the player's own amount and police choice. Working around that would need BeamNG.Earth internals beyond its mod API.
- Each player has their own floating origin. That's why positions travel as lat/lon, and why the server converts with WGS84 → ENU (`cnr/geo.lua`).

**On update, check:**
- On `beamng_earth`, there's no "needs a newer BeamNG.Earth (API v1)" toast. If it appears, `version()` changed. Read the mod's `docs/ADDONS.md` for the new contract.
- **Distances:** cops see "Runner 2.4 km by road NE" after a last-seen ping (GPS), and the 1 km cop reset uses real distance.
- **Gas stations:** the server log shows `N new gas stations on beamng_earth` while you drive, so `places` works.
- **Teleports:** teleporting far away counts as a teleport for the runner (it's announced), and for a cop it moves the AI cars along with you. If not, the rebase hook changed.

## Development tools

- **Lua:** stock `lua` (5.3 or newer) for `make test`, `luajit` for compile checks (the game runs LuaJIT, so client code stays Lua 5.1 compatible), `make vuecheck` (Node, with the game's UI sources) for the Vue apps, and `python3` for `tools/lights/export.py`.
- **Build:** `zip` for `make package`.
