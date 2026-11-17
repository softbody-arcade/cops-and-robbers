local M = {}

local game = require("copsAndRobbers/game")
local inputs = require("copsAndRobbers/inputs")
local roads = require("copsAndRobbers/roads")
local vehicles = require("copsAndRobbers/vehicles")
local ai = require("copsAndRobbers/ai")
local geo = require("copsAndRobbers/geo")
local hudfeed = require("copsAndRobbers/hudfeed")
local apps = require("copsAndRobbers/apps")
local sight = require("copsAndRobbers/sight")
local buildDiff = require("copsAndRobbers/build")
local modes = require("copsAndRobbers/modes")
local nearby = require("copsAndRobbers/nearby")
local sky = require("copsAndRobbers/sky")
local heli = require("copsAndRobbers/heli")
local heliSound = require("copsAndRobbers/heliSound")
local shelter = require("copsAndRobbers/shelter")
local tunnels = require("copsAndRobbers/tunnels")
local traffic = require("copsAndRobbers/traffic")
local hiding = require("copsAndRobbers/hiding")
local playerSettings = require("copsAndRobbers/playerSettings")
local ownLights = require("copsAndRobbers/ownLights")

local CLIENT_VERSION = "2.9.5"
local LIGHTS_OFF = "electrics.set_lightbar_signal(0)"
local SETUP_DELAY = 0.5
local PLACEMENT_TIMEOUT = 5
local FREEZE_REASSERT = 0.5
local POSE_JUMP = 30
local GEO_SEND_INTERVAL = 0.25
local SIGHT_CHECK_INTERVAL = 0.25
local CHANGE_CHECK_INTERVAL = 1
local BASELINE_DELAY = 1.5
local MODES_INTERVAL = 3
local MODES_SETTLE = 2.5
local RESET_LOCK = 2
local HIDING_INTERVAL = 1
local HELP_FILE = "settings/cnr_help_seen.json"
local BINDING_WARNING = "Bind a reset or recover button to reset during rounds"

local sendServer, ownVehicle = game.sendServer, game.ownVehicle

local clock = 0
local active = false
local role
local frozen = false
local resetAllowed = false
local serverResetAllowed = false
local resetLockUntil
local lastHint
local timerEnd, timerLabel
local roundModel, roundConfig, roundColor
local penaltyActive = false
local statusActive = false
local geoMode = false
local lastGeoSent = 0
local chaseStart
local lastStatusAt = 0
local infoParts
local infoSeenAt
local pendingPlacement
local rebuildId
local suppressResetUntil = 0
local lastPose
local lastFreezeAssert = 0
local runnerId
local runnerOut = false
local runnerShown = true
local hidingTarget
local hidingBuiltAt = -math.huge
local evolving = false
local sightMax = 0
local sightState = sight.new()
local lastSightCheck = 0
local infoTag
local spotted, nearestParts
local buildBaselineAt, buildBaseline
local lastChangeKey, lastChanges, lastChangeCheck = "", {}, 0
local modesState = modes.new()
local modesHoldUntil, lastModesCapture = 0, 0
local requestReset
local runnerObject
local helpSeen = false
local prefs = playerSettings.load(nil)
local sirensAllowed = true
local routeDrawn = false
local lightsState, lightsPlaced, lastLightsCheck = nil, false, 0
local lastLightSync, lightSyncCount = 0, 0

local function setFreeze(on)
  frozen = on
  local veh = ownVehicle()
  if veh then veh:queueLuaCommand("controller.setFreeze(" .. (on and 1 or 0) .. ")") end
end

local function startTimer(seconds, label)
  if seconds and seconds > 0 then
    timerEnd = clock + seconds
    timerLabel = label
  else
    timerEnd = nil
  end
end

local function teleport(veh, pos, rot)
  suppressResetUntil = clock + 2
  lastPose = { pos = pos, rot = rot }
  spawn.safeTeleport(veh, pos, rot)
end

local function placeVehicle(model, config, pos, rot, color)
  if ownVehicle() then
    core_vehicles.replaceVehicle(model, vehicles.options(config, color))
  else
    core_vehicles.spawnNewVehicle(model, vehicles.options(config, color))
  end
  pendingPlacement = { at = clock + SETUP_DELAY, deadline = clock + PLACEMENT_TIMEOUT, pos = pos, rot = rot, rebuild = rebuildId }
end

local function startStatus()
  statusActive = true
  chaseStart = clock
  lastStatusAt = 0
  infoParts, infoTag, infoSeenAt = nil, nil, nil
end

local function onSetupAI(data)
  ai.setup(jsonDecode(data) or {})
  hidingBuiltAt = -math.huge
end

local function onPickVehicle(data)
  local d = jsonDecode(data) or {}
  local model, config = vehicles.pick(d.includeMods, d.excludedModels)
  if not model then
    hudfeed.event("No vehicles available to pick", clock, "warn")
    return
  end
  sendServer("cnr_vehiclePicked", { model = model, config = config })
end

local function setupPosition(d)
  local resume = d.resumeGeo and geo.toGame(d.resumeGeo) or (d.resumePos and vec3(d.resumePos.x, d.resumePos.y, d.resumePos.z))
  if resume then
    local pos, rot = roads.nearestRoad(resume)
    if not pos then return resume, nil end
    return pos, rot
  end
  if d.inPlace then return nil end
  local own = ownVehicle()
  if role == "runner" then
    local at = own and own:getPosition()
    if not at then return nil end
    local pos, rot = roads.nearestRoad(at, own:getDirectionVector())
    if not pos then hudfeed.event("No road found nearby, you start where you are", clock, "warn") end
    return pos, rot
  end
  if role ~= "cop" then return nil end
  local runner = d.runnerGeo and geo.toGame(d.runnerGeo) or (d.runnerPos and vec3(d.runnerPos.x, d.runnerPos.y, d.runnerPos.z))
  local center = runner or (own and own:getPosition())
  local runnerCar = runner and not d.geo and runnerObject()
  local pos, rot
  if center then
    pos, rot = roads.findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, math.max(d.copIndex or 1, 1), runnerCar and runnerCar:getDirectionVector())
  end
  if not pos then hudfeed.event("No road found near the runner, you start where you are", clock, "warn") end
  return pos, rot
end

local function checkBinding(notice)
  local bound = inputs.resetIsBound()
  hudfeed.warning("binding", not bound and BINDING_WARNING or nil)
  if notice and not bound then hudfeed.event(BINDING_WARNING, clock, "warn") end
end

local function playerName(id)
  local players = MPVehicleGE and MPVehicleGE.getPlayers and MPVehicleGE.getPlayers() or {}
  local p = players[id] or players[tostring(id)]
  return type(p) == "table" and type(p.name) == "string" and p.name or nil
end

local heliState = heli.new()
local soundState = heliSound.new()

local function setHeli(h)
  heli.set(heliState, h, clock)
  if type(h) ~= "table" or type(h.phase) ~= "string" then
    hudfeed.heli(nil)
    return
  end
  local seconds = tonumber(h.seconds)
  hudfeed.heli({ phase = h.phase, reason = h.reason, endsAt = seconds and clock + seconds or nil })
end

local function onRoundSetup(data)
  local d = jsonDecode(data) or {}
  hudfeed.clearRound()
  hudfeed.clearResult()
  setHeli(d.heli)
  routeDrawn = false
  active = true
  role = d.role
  runnerId = d.runnerId
  runnerShown = d.runnerShown ~= false
  hidingBuiltAt = -math.huge
  evolving = d.evolving == true
  rebuildId = tonumber(d.rebuild)
  buildBaseline, lastChangeKey, lastChanges = nil, nil, {}
  buildBaselineAt = (evolving and d.role == "runner" and d.phase == "prep") and (clock + BASELINE_DELAY) or nil
  sightMax = tonumber(d.sightMaxMeters) or 0
  sightState = sight.new()
  roundModel, roundColor = d.model, d.color
  roundConfig = d.role == "cop" and vehicles.copConfig(d.model, d.config) or d.config
  resetAllowed, serverResetAllowed, resetLockUntil = false, false, nil
  lastHint = nil
  lastPose = nil
  inputs.lock(true, requestReset, d.practice == true)
  inputs.setResetKey()
  local mayChange = d.phase == "prep" and evolving and role == "runner"
  inputs.setPartsMenu(mayChange)
  inputs.lockEditing(mayChange and "paint" or "all")
  checkBinding(true)

  local pos, rot = setupPosition(d)
  placeVehicle(d.model, roundConfig, pos, rot, d.color)

  sky.apply(d.sky)
  local skyLabel = sky.label(d.sky, true)
  local phase = d.phase or "running"
  runnerOut = phase == "headstart" or phase == "running"
  traffic.setWeather(d.sky and d.sky.weather)
  lightsState = ownLights.new(prefs.headlights)
  lightsPlaced = false
  if phase == "countdown" or phase == "headstart" or phase == "running" then
    sky.startClock(d.sky and d.sky.clockSeconds or 0)
  end
  frozen = phase == "prep" or phase == "applying" or phase == "ready" or phase == "countdown" or (phase == "headstart" and role == "cop")
  if phase == "applying" then hudfeed.applying(true) end
  if phase == "prep" or phase == "applying" or phase == "ready" then
    hudfeed.prep(role, game.carName(d.model), (evolving and phase == "prep") and "change" or "go", d.runnerName or playerName(d.runnerId), skyLabel)
    timerEnd = nil
  elseif phase == "countdown" then
    startTimer(tonumber(d.countdownRemaining), "Runner starts in")
  elseif phase == "headstart" and role == "runner" then
    timerEnd = nil
    hudfeed.headStart(clock + (tonumber(d.headStartRemaining) or 0))
  elseif phase == "headstart" then
    startTimer(tonumber(d.headStartRemaining), "Cops released in")
  else
    timerEnd = nil
    if phase == "running" then
      startStatus()
      chaseStart = clock - (tonumber(d.chaseElapsed) or 0)
    end
  end
end

local function onSky(data)
  if not active then return end
  local d = jsonDecode(data) or {}
  sky.apply(d)
  traffic.setWeather(d.weather)
  local label = sky.label(d, true)
  hudfeed.prepSky(label)
  if label then hudfeed.event("New sky: " .. label, clock, "info") end
end

local function onCountdown(data)
  local d = jsonDecode(data) or {}
  sky.startClock(0)
  hudfeed.prep(nil)
  inputs.setPartsMenu(false)
  inputs.lockEditing("all")
  startTimer(tonumber(d.seconds), "Runner starts in")
end

local function onRunnerGo(data)
  local d = jsonDecode(data) or {}
  ai.releaseRunner()
  runnerOut = true
  heli.resetCover(heliState)
  traffic.release()
  if role == "runner" then
    timerEnd = nil
    setFreeze(false)
    hudfeed.flash("GO! RUN!", clock)
    hudfeed.headStart(clock + (tonumber(d.headStartSeconds) or 0))
  else
    startTimer(tonumber(d.headStartSeconds), "Cops released in")
  end
end

local function onPaint(data)
  local d = jsonDecode(data) or {}
  local veh = ownVehicle()
  if not veh or not roundModel then return end
  roundColor = d.color
  local config = roundConfig
  if evolving and role == "runner" and (buildBaseline or buildBaselineAt) then
    local now = vehicles.currentSetup()
    if now then config = { format = 2, model = roundModel, parts = now.parts, vars = now.vars } end
  end
  placeVehicle(roundModel, config, veh:getPosition(), game.uprightRotation(veh), d.color)
end

local function labelledChanges(setup)
  local list = {}
  local roots = buildDiff.group(buildDiff.diff(buildBaseline.parts, setup.parts), function(id) return vehicles.slotsOf(roundModel, id) end)
  for _, c in ipairs(roots) do
    list[#list + 1] = {
      label = vehicles.slotLabel(roundModel, c.slot, setup.parts) or buildDiff.label(c.slot, roundModel),
      from = vehicles.partName(roundModel, c.from), to = vehicles.partName(roundModel, c.to),
      extra = c.extra > 0 and c.extra or nil, parts = c.parts,
    }
  end
  for _, c in ipairs(buildDiff.varsDiff(buildBaseline.vars, setup.vars, setup.steps)) do
    local title = setup.titles and setup.titles[c.name]
    list[#list + 1] = { label = title or buildDiff.varLabel(c.name), from = buildDiff.formatValue(c.from), to = buildDiff.formatValue(c.to) }
  end
  return list
end

local function changeKey(list)
  local parts = {}
  for i, c in ipairs(list) do parts[i] = c.label .. "=" .. c.from .. ">" .. c.to end
  return table.concat(parts, "|")
end

local function updateBuild()
  if not buildBaselineAt or pendingPlacement or clock < buildBaselineAt then return end
  if not buildBaseline then
    buildBaseline = vehicles.currentSetup()
    lastChangeCheck = -math.huge
    return
  end
  if clock - lastChangeCheck < CHANGE_CHECK_INTERVAL then return end
  lastChangeCheck = clock
  local setup = vehicles.currentSetup()
  if not setup then return end
  lastChanges = labelledChanges(setup)
  local key = changeKey(lastChanges)
  if key ~= lastChangeKey then
    lastChangeKey = key
    sendServer("cnr_change", { changes = lastChanges })
  end
end

local function onRequestSetup()
  local setup = vehicles.currentSetup()
  if not setup then return end
  if buildBaseline then lastChanges = labelledChanges(setup) end
  sendServer("cnr_setup", { model = setup.model, parts = setup.parts, vars = setup.vars, changes = lastChanges })
end

local function onRebuild(data)
  local d = jsonDecode(data) or {}
  if not active or type(d.config) ~= "table" then return end
  rebuildId = tonumber(d.rebuild)
  buildBaselineAt, buildBaseline = nil, nil
  inputs.setPartsMenu(false)
  inputs.lockEditing("all")
  hudfeed.applying(true)
  roundConfig = role == "cop" and vehicles.copConfig(roundModel, d.config) or d.config
  local veh = ownVehicle()
  placeVehicle(roundModel, roundConfig, veh and veh:getPosition(), veh and game.uprightRotation(veh), roundColor)
  ai.rebuild(roundModel, d.config)
  hidingBuiltAt = -math.huge
  local missing = {}
  for _, part in pairs(type(d.config.parts) == "table" and d.config.parts or {}) do
    if not vehicles.hasPart(roundModel, part) then missing[#missing + 1] = part end
  end
  table.sort(missing)
  if #missing > 0 then sendServer("cnr_missing", { parts = missing }) end
end

local function onPenalty(data)
  local d = jsonDecode(data) or {}
  if d.aiId then return ai.penalty(d.aiId) end
  penaltyActive = true
  setFreeze(true)
  startTimer(tonumber(d.seconds), "Crash penalty")
end

local function onPenaltyEnd(data)
  local d = jsonDecode(data or "{}") or {}
  if d.aiId then return ai.penaltyEnd(d.aiId) end
  penaltyActive = false
  lastHint = nil
  timerEnd = nil
  setFreeze(false)
  hudfeed.flash("PENALTY OVER", clock)
end

local function onLastSeen(data)
  local d = jsonDecode(data) or {}
  local never, always = prefs.route == "never", prefs.route == "always"
  infoTag = d.live and "LIVE" or nil
  infoSeenAt = nil
  if never then
    if routeDrawn then
      geo.clearRoute()
      routeDrawn = false
    end
  end
  local inSight = d.live and d.route == false
  if inSight and not always then
    if not never then
      geo.clearRoute()
      routeDrawn = false
    end
    infoTag, infoParts, infoSeenAt = "IN SIGHT", nil, nil
    return
  end
  if inSight then infoTag = "IN SIGHT" end
  local target = d.geo and geo.toGame(d.geo) or (d.pos and vec3(d.pos.x, d.pos.y, d.pos.z))
  if not target then return end
  if not never then
    if geoMode and d.geo and geo.setGpsTarget(d.geo) then
      routeDrawn = true
      local info = geo.gpsInfo()
      infoParts = info or infoParts
      infoSeenAt = not d.live and info and clock or nil
      return
    end
    if core_groundMarkers then
      pcall(core_groundMarkers.setPath, target)
      routeDrawn = true
    end
  end
  local veh = ownVehicle()
  if veh then
    local here = veh:getPosition()
    local meters = math.floor(here:distance(target) + 0.5)
    infoParts = { before = d.live and "Runner" or "Runner seen", meters = meters, after = geo.compass(here, target) }
    infoSeenAt = not d.live and clock or nil
  end
end

local function runnerInfo()
  infoTag = spotted == true and "SPOTTED" or spotted == false and "HIDDEN" or nil
  return nearestParts
end

local function onNearestCop(data)
  local d = jsonDecode(data) or {}
  if d.dist then
    nearestParts = { before = "Nearest cop", meters = d.dist }
    infoParts = runnerInfo()
  end
end

local function onSpotted(data)
  local d = jsonDecode(data) or {}
  spotted = d.spotted == true
  infoParts = runnerInfo()
end

local function onMode(data)
  local d = jsonDecode(data) or {}
  geoMode = d.geo == true
  geo.resetPlaces()
  guihooks.trigger("CnRPanel", {})
  guihooks.trigger("CnRBoard", {})
  hudfeed.warning("earth", geoMode and not geo.api() and "Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map" or nil)
  local outdated = d.version and d.version ~= CLIENT_VERSION
  hudfeed.warning("version", outdated and string.format("Your copy is %s, the server runs %s: rejoin to update", CLIENT_VERSION, d.version) or nil)
  hudfeed.connect(true)
  if not helpSeen then
    local ok, seen = pcall(jsonReadFile, HELP_FILE)
    helpSeen = ok and type(seen) == "table" and seen.seen == true
    if not helpSeen then
      hudfeed.help(true)
      apps.open("howto")
    end
  end
end

local function onNotice(data)
  local d = jsonDecode(data) or {}
  if d.about ~= nil and MPConfig and d.about == MPConfig.getPlayerServerID() then return end
  if d.msg then hudfeed.event(d.msg, clock, d.tone == "warn" and "warn" or "info") end
end

local function onRelease()
  ai.releaseCops()
  hudfeed.headStart(nil)
  if role == "runner" and sightMax > 0 and spotted == nil then spotted = false end
  timerEnd = nil
  if frozen then setFreeze(false) end
  if role == "cop" then
    hudfeed.flash("GO!", clock)
  end
  startStatus()
  if role == "runner" then infoParts = runnerInfo() end
end

local function setResetAllowed(allowed)
  if allowed ~= resetAllowed then
    resetAllowed = allowed
    inputs.setResetKey()
  end
end

local function onState(data)
  local d = jsonDecode(data) or {}
  serverResetAllowed = d.resetAllowed and true or false
  resetLockUntil = nil
  setResetAllowed(serverResetAllowed)
  if d.resetHint then lastHint = d.resetHint end
  local p = tonumber(d.catchProgress) or 0
  hudfeed.catchSample(clock, p)
end

local function endRound(leaving)
  hudfeed.clearRound()
  heli.clear(heliState)
  heliSound.clear(soundState)
  lightsState = nil
  sky.restore(leaving)
  traffic.stop(clock)
  hiding.clear()
  hidingTarget = nil
  runnerShown = true
  runnerOut = false
  local own = ownVehicle()
  if active and role == "cop" and own then own:queueLuaCommand(LIGHTS_OFF) end
  active = false
  role = nil
  statusActive = false
  infoParts = nil
  infoTag = nil
  infoSeenAt = nil
  spotted, nearestParts = nil, nil
  runnerId = nil
  evolving = false
  buildBaselineAt, buildBaseline, lastChangeKey, lastChanges = nil, nil, "", {}
  geo.clearRoute()
  routeDrawn = false
  ai.remove()
  penaltyActive = false
  timerEnd = nil
  roundModel, roundConfig, roundColor = nil, nil, nil
  pendingPlacement = nil
  resetAllowed, serverResetAllowed, resetLockUntil = false, false, nil
  lastPose = nil
  if frozen then setFreeze(false) end
  inputs.unlockAll()
end

local function onRoundEnd(data)
  local d = jsonDecode(data) or {}
  local wasRunner = MPConfig and MPConfig.getPlayerServerID() == d.runnerId
  local wasActive = active
  local caughtCar
  if d.explode and wasRunner then
    caughtCar = ownVehicle()
  elseif d.explode and wasActive and role == "cop" and not ai.runnerObject() then
    caughtCar = runnerObject()
  end
  endRound()
  local cancelled = d.reason == "cancelled" or not hudfeed.isResultReason(d.reason)
  if cancelled and not wasActive then return end
  hudfeed.showResult(d, clock)
  if caughtCar then caughtCar:queueLuaCommand("fire.explodeVehicle()") end
end

local function onTop(data)
  hudfeed.top((jsonDecode(data) or {}).rows)
end

local function onMyColor(data)
  local d = jsonDecode(data) or {}
  hudfeed.color(d.hex)
  if type(d.error) == "string" then hudfeed.event(d.error, clock, "warn") end
end

local function onBoardState(data)
  local d = jsonDecode(data) or {}
  local function addCar(row)
    if type(row) == "table" and row.model then row.car = game.carName(row.model) end
  end
  for _, row in ipairs(type(d.runners) == "table" and d.runners or {}) do addCar(row) end
  addCar(d.mine)
  for _, row in ipairs(type(d.rounds) == "table" and d.rounds or {}) do
    addCar(row)
    if type(row) == "table" then
      row.skyLabel = sky.label(row.sky)
      row.trafficLabel = traffic.label(row.traffic, row.trafficRunnerOnly)
    end
  end
  local names = {}
  local function name(id)
    if type(id) == "string" and id ~= "" and id ~= "all" and not names[id] then names[id] = game.mapTitle(id) end
  end
  name(d.map)
  name(d.filter)
  for _, id in ipairs(type(d.maps) == "table" and d.maps or {}) do name(id) end
  for _, row in ipairs(type(d.rounds) == "table" and d.rounds or {}) do
    if type(row) == "table" then name(row.map) end
  end
  d.mapNames = names
  guihooks.trigger("CnRBoard", d)
end

local function onPanelState(data)
  local d = jsonDecode(data) or {}
  if type(d.map) == "string" and d.map ~= "" then d.mapName = game.mapTitle(d.map) end
  if type(d.car) == "string" and d.car ~= "" then d.carName = game.carName(d.car) end
  local excluded = type(d.settings) == "table" and d.settings.excludedModels
  if type(excluded) == "table" then
    local names = {}
    for _, model in ipairs(excluded) do
      if type(model) == "string" and model ~= "" then names[model] = game.carName(model) end
    end
    d.excludedNames = names
  end
  guihooks.trigger("CnRPanel", d)
end

local function onStationList(data)
  local d = jsonDecode(data) or {}
  local list = type(d.stations) == "table" and d.stations or {}
  local points = {}
  for _, s in ipairs(list) do
    if type(s) == "table" then
      local p = d.geo and geo.toGame(s) or (tonumber(s.x) and tonumber(s.y) and { x = s.x, y = s.y, z = tonumber(s.z) or 0 })
      if p then points[#points + 1] = p end
    end
  end
  local own = ownVehicle()
  local near = own and nearby.nearest(points, own:getPosition(), 3, d.geo == true) or {}
  local result = {}
  for i, n in ipairs(near) do result[i] = { meters = n.meters } end
  guihooks.trigger("CnRStations", {
    count = #list, nearest = result, canRemove = result[1] ~= nil and result[1].meters <= 50,
  })
end

local function onAutoNext()
  hudfeed.cancelNext()
end

local function onRequestStations()
  if not freeroam_facilities then extensions.load("freeroam_facilities") end
  if not freeroam_gasStations then extensions.load("freeroam_gasStations") end
  local stations = {}
  if freeroam_facilities and freeroam_gasStations then
    for _, f in ipairs(freeroam_facilities.getFacilitiesByType("gasStation") or {}) do
      local ok, center, radius = pcall(freeroam_gasStations.gasStationCenterRadius, f)
      if ok and center and center.x == center.x then
        stations[#stations + 1] = { x = center.x, y = center.y, z = center.z, r = radius or 0 }
      end
    end
  end
  sendServer("cnr_stations", { map = getCurrentLevelIdentifier(), stations = stations })
end

local function updatePendingPlacement()
  local p = pendingPlacement
  if not p or clock < p.at then return end
  local veh = ownVehicle()
  local vid = veh and game.serverVid(veh)
  if veh and vid then
    pendingPlacement = nil
    if p.pos then teleport(veh, p.pos, p.rot) end
    local restore = modes.restoreCommand(modes.forModel(modesState, roundModel))
    if restore then veh:queueLuaCommand(restore) end
    modesHoldUntil = clock + MODES_SETTLE
    if frozen then setFreeze(true) end
    sendServer("cnr_myVehicle", { vid = vid, rebuild = p.rebuild })
    lightsPlaced = true
  elseif clock >= p.deadline then
    pendingPlacement = nil
  end
end

local function updateResetLock()
  if not resetLockUntil or clock < resetLockUntil then return end
  resetLockUntil = nil
  setResetAllowed(serverResetAllowed)
end

local function updateOwnCar()
  if not active or pendingPlacement then return end
  local veh = ownVehicle()
  if not veh then return end
  local pos = veh:getPosition()
  if not lastPose or pos:distance(lastPose.pos) <= POSE_JUMP then
    lastPose = { pos = pos, rot = game.uprightRotation(veh) }
  end
  if frozen and clock - lastFreezeAssert >= FREEZE_REASSERT then
    lastFreezeAssert = clock
    veh:queueLuaCommand("controller.setFreeze(1)")
  end
end

local function updateModes()
  if not active or pendingPlacement or clock < modesHoldUntil or clock - lastModesCapture < MODES_INTERVAL then return end
  lastModesCapture = clock
  local veh = ownVehicle()
  if veh then veh:queueLuaCommand(modes.CAPTURE) end
end

local function updateLightsAndPatch()
  if not active or not inputs.patchDue(clock) then return end
  local veh = ownVehicle()
  if veh then
    veh:queueLuaCommand(inputs.VEHICLE_PATCH)
    local n = ownLights.lightbarSignal(role, statusActive, prefs.siren, sirensAllowed)
    if n then veh:queueLuaCommand(n == 2 and ownLights.SIREN_ON or ownLights.LIGHTS_ONLY) end
  end
  ai.lightsOn(sky.isNight())
end

local function updateOwnLights()
  if not (active and lightsState) or pendingPlacement then return end
  if not lightsPlaced and clock - lastLightsCheck < 1 then return end
  lastLightsCheck = clock
  local veh = ownVehicle()
  if not veh then return end
  local dark = sky.isNight() or sky.isBadWeather(traffic.weather())
  local cmd = ownLights.step(lightsState, prefs.headlights, dark, lightsPlaced)
  lightsPlaced = false
  if cmd then veh:queueLuaCommand(cmd == "on" and ownLights.HEADLIGHTS_ON or ownLights.HEADLIGHTS_OFF) end
end

local function updateLightSync()
  if not active or clock - lastLightSync < ownLights.SYNC_INTERVAL then return end
  lastLightSync = clock
  lightSyncCount = lightSyncCount + 1
  local cmd = ownLights.syncCommand(lightSyncCount)
  local veh = ownVehicle()
  if veh then veh:queueLuaCommand(cmd) end
  for _, car in ipairs(ai.objects()) do car.obj:queueLuaCommand(cmd) end
  for _, obj in ipairs(traffic.objects()) do obj:queueLuaCommand(cmd) end
end

local function updateGeo()
  if not geoMode then return end
  if clock - lastGeoSent >= GEO_SEND_INTERVAL then
    lastGeoSent = clock
    geo.sendGeo(ai.objects())
  end
  geo.lookupStations(clock)
end

local function updateGpsInfo()
  if not statusActive or clock - lastStatusAt < 1 then return end
  lastStatusAt = clock
  if geo.hasTarget() then
    local info = geo.gpsInfo()
    if info then infoParts = info end
  end
end

runnerObject = function()
  local aiRunner = ai.runnerObject()
  if aiRunner then return aiRunner end
  if not runnerId or not MPVehicleGE or not MPVehicleGE.getVehicles then return nil end
  local prefix = tostring(runnerId) .. "-"
  local vehicles = MPVehicleGE.getVehicles() or {}
  local function usable(key)
    local v = type(key) == "string" and key:sub(1, #prefix) == prefix and vehicles[key]
    if type(v) ~= "table" or v.isSpawned == false or v.isDeleted or not v.gameVehicleID then return nil end
    return getObjectByID(v.gameVehicleID)
  end
  local round = traffic.roundCar(runnerId)
  if round then return usable(round) end
  local players = MPVehicleGE.getPlayers and MPVehicleGE.getPlayers() or {}
  local runner = players[runnerId] or players[tostring(runnerId)]
  local key = type(runner) == "table" and runner.activeVehicleID
  if not key or traffic.isTraffic(key) then return nil end
  return usable(key)
end

local function sameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

local function copHidingSets()
  local keys, vids = {}, {}
  local runnerOwner = tostring(runnerId)
  for owner, key in pairs(traffic.roundCarOwners()) do
    if owner ~= runnerOwner then
      keys[key] = true
      local v = MPVehicleGE and MPVehicleGE.getVehicles and (MPVehicleGE.getVehicles() or {})[key]
      if type(v) == "table" and v.gameVehicleID then vids[v.gameVehicleID] = true end
    end
  end
  for _, car in ipairs(ai.objects()) do vids[car.obj:getID()] = true end
  return keys, vids
end

local function updateHiding(obj)
  if not active then return end
  local keys, vids
  if role == "runner" then
    if hidingTarget and clock - hidingBuiltAt < HIDING_INTERVAL then return hiding.tick(clock) end
    hidingBuiltAt = clock
    keys, vids = copHidingSets()
  elseif role == "cop" and not runnerShown then
    keys, vids = {}, {}
    local key = traffic.roundCar(runnerId)
    if key then keys[key] = true end
    if obj then vids[obj:getID()] = true end
  end
  if not keys then
    hiding.set(nil)
  else
    local minimap = not geoMode
    local t = hidingTarget
    if not t or t.minimap ~= minimap or not sameSet(t.keys, keys) or not sameSet(t.vids, vids) then
      hidingTarget = { vids = vids, keys = keys, minimap = minimap }
    end
    hiding.set(hidingTarget)
  end
  hiding.tick(clock)
end

local function updateSight(target)
  if role ~= "cop" or not statusActive or sightMax <= 0 or clock - lastSightCheck < SIGHT_CHECK_INTERVAL then return end
  lastSightCheck = clock
  local veh = ownVehicle()
  local seen, dist = false, nil
  if veh and target and castRayStatic then
    seen, dist = sight.visible(veh:getPosition(), target:getPosition(), target:getDirectionVector(), sightMax, castRayStatic)
  end
  local changed = seen ~= sightState.seen
  if not sight.step(sightState, clock, seen) then return end
  if changed and log then
    log("I", "cnr_sight", string.format("runner %s (%s m)", seen and "in sight" or "out of sight", dist and string.format("%.0f", dist) or "?"))
  end
  sendServer("cnr_sight", { seen = seen })
end

local function castUp(pos, range)
  return castRayStatic(pos, vec3(0, 0, 1), range)
end

local function closestRoad(p)
  if map and map.findClosestRoad then return map.findClosestRoad(p) end
end

local function roofedAt(p)
  return shelter.roofed(p, castUp)
end

local function tunnelExit(carPos, dirX, dirY, seed)
  local gp = map and map.getGraphpath and map.getGraphpath()
  local m = map and map.getMap and map.getMap()
  local roadData = { closest = closestRoad, links = gp and gp.graph, nodes = m and m.nodes }
  return tunnels.exit(carPos, dirX, dirY, roadData, roofedAt, seed)
end

local coverFailed = false

local function updateHeli(runnerObj)
  if runnerOut and castRayStatic then
    local car = role == "runner" and ownVehicle() or ai.runnerObject()
    if car then
      local ok, c = pcall(heli.coverTick, heliState, clock, car, castRayStatic)
      if not ok then
        if not coverFailed then
          coverFailed = true
          log("E", "cnr_heli", "cover check failed: " .. tostring(c))
        end
      elseif c ~= nil then
        sendServer("cnr_cover", { covered = c })
      end
    end
  end
  if active then
    local target = role == "runner" and ownVehicle() or runnerObj
    local opts = { weather = traffic.weather(), beam = prefs.beam ~= false }
    if castRayStatic then opts.tunnelExit = tunnelExit end
    heli.lightTick(heliState, target, heli.wantsNight(heliState) and sky.isNight(), clock, opts)
    local camPos = core_camera and core_camera.getPosition and core_camera.getPosition() or nil
    local level = prefs.sound ~= false and heli.soundLevel(heliState, clock) or 0
    heliSound.tick(soundState, heliState.flight and heliState.flight.pos, level, clock, camPos, castRayStatic)
  else
    heli.lightTick(heliState, nil, false, clock)
    heliSound.tick(soundState, nil, 0, clock)
  end
end

local function onUpdate(dtReal)
  clock = clock + (dtReal or 0)
  sky.update(dtReal or 0)
  updatePendingPlacement()
  updateResetLock()
  updateOwnCar()
  local report = ai.tick(clock)
  if #report > 0 then sendServer("cnr_aiVehicles", { ai = report }) end
  local trafficVids = traffic.tick(clock)
  if trafficVids then sendServer("cnr_trafficCars", { vids = trafficVids }) end
  updateLightsAndPatch()
  updateOwnLights()
  updateLightSync()
  updateGeo()
  local runnerObj = active and role == "cop" and runnerObject() or nil
  updateSight(runnerObj)
  updateHiding(runnerObj)
  updateHeli(runnerObj)
  updateBuild()
  updateModes()
  if active then inputs.enforceEditLock() end
  updateGpsInfo()
  hudfeed.update(clock, {
    active = active, role = role, chaseStart = statusActive and chaseStart or nil,
    resetAllowed = resetAllowed, resetHint = lastHint, penalty = penaltyActive, infoParts = infoParts, infoSeenAt = infoSeenAt, infoTag = infoTag,
    timer = timerEnd and { label = timerLabel, endsAt = timerEnd } or nil,
  })
end

local function onVehicleResetted(gameVid)
  if not active or clock < suppressResetUntil then return end
  local veh = ownVehicle()
  if geoMode then
    if veh and veh:getID() == gameVid then sendServer("cnr_relocated", {}) end
    return
  end
  if not lastPose or not veh or veh:getID() ~= gameVid then return end
  teleport(veh, lastPose.pos, lastPose.rot)
end

requestReset = function(kind)
  if not active then return end
  local veh = ownVehicle()
  if not veh then return end
  if not resetAllowed then
    hudfeed.resetFlash(clock)
    local msg = penaltyActive and "No reset during a crash penalty" or (lastHint or "Reset not available")
    if not statusActive then hudfeed.event(msg, clock, "warn") end
    return
  end
  resetAllowed = false
  resetLockUntil = clock + RESET_LOCK
  local pos, rot = veh:getPosition(), game.uprightRotation(veh)
  if kind == "road" and role == "cop" then
    local roadPos, roadRot = roads.nearestRoad(pos)
    if roadPos then
      pos, rot = roadPos, roadRot
    else
      hudfeed.event("No road found nearby, repaired in place", clock, "info")
    end
  end
  teleport(veh, pos, rot)
end

local function onBeamNGEarthRebased(info)
  if not active then return end
  suppressResetUntil = clock + 3
  lastPose = nil
  local purpose = type(info) == "table" and info.purpose or "rebase"
  if purpose ~= "teleport" then
    sendServer("cnr_relocated", {})
    return
  end
  local own = ownVehicle()
  local ids = ai.relocate(own and own:getPosition(), own and own:getDirectionVector())
  if #ids > 0 then sendServer("cnr_relocated", { ids = ids }) end
end

local function leaveServer()
  endRound(true)
  sirensAllowed = true
  hudfeed.clearResult()
  hudfeed.leave()
  hudfeed.connect(false)
  apps.leave()
  guihooks.trigger("CnRPanel", {})
  guihooks.trigger("CnRBoard", {})
end

local function onExtensionLoaded()
  local ok, saved = pcall(jsonReadFile, modes.FILE)
  modesState = modes.new(ok and saved or nil)
  local readOk, savedPrefs = pcall(jsonReadFile, playerSettings.FILE)
  prefs = playerSettings.load(readOk and savedPrefs or nil)
  hudfeed.settings(prefs)
  apps.refreshApps()
  apps.start(clock)
  inputs.setNotify(function(msg, tone) hudfeed.event(msg, clock, tone) end)
  ai.setNotify(function(msg, tone) hudfeed.event(msg, clock, tone) end)
  traffic.setNotify(function(msg, tone) hudfeed.event(msg, clock, tone) end)
  hudfeed.onLobbyRefresh(checkBinding)
  if not AddEventHandler then return end
  AddEventHandler("cnr_pickVehicle", onPickVehicle)
  AddEventHandler("cnr_roundSetup", onRoundSetup)
  AddEventHandler("cnr_release", onRelease)
  AddEventHandler("cnr_heli", function(data) setHeli(jsonDecode(data)) end)
  AddEventHandler("cnr_countdown", onCountdown)
  AddEventHandler("cnr_runnerGo", onRunnerGo)
  AddEventHandler("cnr_paint", onPaint)
  AddEventHandler("cnr_penalty", onPenalty)
  AddEventHandler("cnr_setupAI", onSetupAI)
  AddEventHandler("cnr_sky", onSky)
  AddEventHandler("cnr_trafficStart", function(data)
    local d = jsonDecode(data) or {}
    traffic.start(d.count, not runnerOut, clock)
  end)
  AddEventHandler("cnr_roundCars", function(data)
    traffic.setRoundCars((jsonDecode(data) or {}).keys)
    hidingBuiltAt = -math.huge
  end)
  AddEventHandler("cnr_runnerShown", function(data)
    runnerShown = (jsonDecode(data) or {}).shown ~= false
  end)
  AddEventHandler("cnr_notice", onNotice)
  AddEventHandler("cnr_top", onTop)
  AddEventHandler("cnr_autoNext", onAutoNext)
  AddEventHandler("cnr_mode", onMode)
  AddEventHandler("cnr_rules", function(data)
    local r = jsonDecode(data)
    hudfeed.rules(r)
    sirensAllowed = not (type(r) == "table" and r.sirensAllowed == false)
  end)
  AddEventHandler("cnr_lobby", function(data)
    hudfeed.lobby(jsonDecode(data))
    checkBinding()
  end)
  AddEventHandler("cnr_myColor", onMyColor)
  AddEventHandler("cnr_lastSeen", onLastSeen)
  AddEventHandler("cnr_nearestCop", onNearestCop)
  AddEventHandler("cnr_spotted", onSpotted)
  AddEventHandler("cnr_requestSetup", onRequestSetup)
  AddEventHandler("cnr_rebuild", onRebuild)
  AddEventHandler("cnr_applied", function()
    hudfeed.applying(false)
    hudfeed.prepWaiting("go")
    hudfeed.queued(nil)
    buildBaselineAt, buildBaseline = nil, nil
    inputs.setPartsMenu(false)
    inputs.lockEditing("all")
  end)
  AddEventHandler("cnr_queued", function(data)
    local d = jsonDecode(data) or {}
    local mine = role == "runner" and evolving and (buildBaseline ~= nil or buildBaselineAt ~= nil)
    local changes = {}
    for i, c in ipairs(type(d.changes) == "table" and d.changes or {}) do
      local missing
      for _, id in ipairs(type(c.parts) == "table" and c.parts or {}) do
        if not vehicles.hasPart(roundModel, id) then missing = true end
      end
      changes[i] = { label = c.label, from = c.from, to = c.to, extra = c.extra, missing = missing }
    end
    hudfeed.queued(d.runner, changes, mine)
  end)
  AddEventHandler("cnr_penaltyEnd", onPenaltyEnd)
  AddEventHandler("cnr_state", onState)
  AddEventHandler("cnr_roundEnd", onRoundEnd)
  AddEventHandler("cnr_requestStations", onRequestStations)
  AddEventHandler("cnr_boardState", onBoardState)
  AddEventHandler("cnr_panelState", onPanelState)
  AddEventHandler("cnr_stationList", onStationList)
  AddEventHandler("cnr_panelReply", function(data) guihooks.trigger("CnRPanelReply", jsonDecode(data) or {}) end)
end

function M.vehicleModes(data)
  if not active or not roundModel then return end
  if modes.remember(modesState, roundModel, data) then
    pcall(jsonWriteFile, modes.FILE, { byModel = modesState.byModel, last = modesState.last }, true)
  end
end

function M.applyChange()
  M.panel({ action = "apply" })
end

function M.configs(opts)
  guihooks.trigger("CnRConfigs", vehicles.configList(opts))
end

function M.newBuild(choice)
  choice = type(choice) == "table" and choice or {}
  local path = choice.config
  local b
  if choice.random then
    local list = vehicles.configList(choice)
    while #list > 0 and not b do
      local pick = table.remove(list, math.random(#list))
      path = pick.config
      b = vehicles.buildFrom(path)
    end
  else
    b = vehicles.buildFrom(path)
  end
  if not b then return guihooks.trigger("CnRPanelReply", { text = "That car can't start a build", tone = "warn" }) end
  M.panel({ action = "build", op = "new", model = b.model, name = b.name, parts = b.parts, vars = b.vars, from = choice.random and "random" or path })
end

function M.ui(msg)
  if type(msg) ~= "table" then return end
  local action = msg.action
  if action == "apply" then return M.applyChange() end
  if action == "color" then return sendServer("cnr_color", { hex = type(msg.hex) == "string" and msg.hex or nil }) end
  if action == "setting" then
    if playerSettings.set(prefs, msg.key, msg.value) then
      pcall(jsonWriteFile, playerSettings.FILE, prefs, true)
      hudfeed.settings(prefs)
    end
  elseif action == "toggleApp" then
    apps.toggle(msg.name)
  elseif action == "help" then
    hudfeed.help(msg.open == true)
    if msg.open == true then
      apps.open("howto")
    else
      apps.close("howto")
      helpSeen = true
      pcall(jsonWriteFile, HELP_FILE, { seen = true }, true)
    end
  elseif action ~= "hello" then
    return
  end
  hudfeed.pushNow()
end

function M.board(msg)
  if TriggerServerEvent and type(msg) == "table" then TriggerServerEvent("cnr_board", jsonEncode(msg)) end
end

function M.panel(msg)
  if TriggerServerEvent and type(msg) == "table" then TriggerServerEvent("cnr_panel", jsonEncode(msg)) end
end

M.requestReset = requestReset
M.onBeamNGEarthRebased = onBeamNGEarthRebased
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = function()
  hiding.unload()
  leaveServer()
  for name in pairs(package.loaded) do
    if name:find("^copsAndRobbers/") then package.loaded[name] = nil end
  end
end
M.onClientEndMission = function()
  sky.drop()
  leaveServer()
end
M.onBeamMPServerLeave = leaveServer
M.onGameStateUpdate = function()
  apps.layoutChanged(clock)
end
M.onWorldReadyState = function(st)
  if st == 2 then apps.start(clock) end
end
M.onUpdate = onUpdate
M.onVehicleResetted = onVehicleResetted

return M
