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
local traffic = require("copsAndRobbers/traffic")

local CLIENT_VERSION = "2.4.1"
local LIGHTS_ON = "electrics.set_lightbar_signal(1)"
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
local HELP_FILE = "settings/cnr_help_seen.json"
local BINDING_WARNING = "Bind a reset or recover button to reset during rounds"

local sendServer, ownVehicle = game.sendServer, game.ownVehicle

local clock = 0
local active = false
local role
local frozen = false
local resetAllowed = false
local lastHint
local timerEnd, timerLabel
local roundModel, roundConfig, roundColor
local penaltyActive = false
local statusActive = false
local geoMode = false
local lastGeoSent = 0
local chaseStart
local lastStatusAt = 0
local infoText
local pendingPlacement
local rebuildId
local suppressResetUntil = 0
local lastPose
local lastFreezeAssert = 0
local runnerId
local runnerOut = false
local evolving = false
local sightMax = 0
local sightState = sight.new()
local lastSightCheck = 0
local infoTag
local spotted, nearestText
local buildBaselineAt, buildBaseline
local lastChangeKey, lastChanges, lastChangeCheck = "", {}, 0
local modesState = modes.new()
local modesHoldUntil, lastModesCapture = 0, 0
local requestReset
local helpSeen = false

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
  infoText, infoTag = nil, nil
end

local function onSetupAI(data)
  ai.setup(jsonDecode(data) or {})
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
  if role ~= "cop" or d.inPlace then return nil end
  local own = ownVehicle()
  local runner = d.runnerGeo and geo.toGame(d.runnerGeo) or (d.runnerPos and vec3(d.runnerPos.x, d.runnerPos.y, d.runnerPos.z))
  local center = runner or (own and own:getPosition())
  local pos, rot
  if center then
    pos, rot = roads.findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, math.max(d.copIndex or 1, 1))
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

local function onRoundSetup(data)
  local d = jsonDecode(data) or {}
  hudfeed.clearRound()
  hudfeed.clearResult()
  active = true
  role = d.role
  runnerId = d.runnerId
  evolving = d.evolving == true
  rebuildId = tonumber(d.rebuild)
  buildBaseline, lastChangeKey, lastChanges = nil, nil, {}
  buildBaselineAt = (evolving and d.role == "runner" and d.phase == "prep") and (clock + BASELINE_DELAY) or nil
  sightMax = tonumber(d.sightMaxMeters) or 0
  sightState = sight.new()
  roundModel, roundColor = d.model, d.color
  roundConfig = d.role == "cop" and vehicles.copConfig(d.model, d.config) or d.config
  resetAllowed = false
  lastHint = nil
  lastPose = nil
  inputs.lock(true, requestReset)
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
  infoTag = d.live and "LIVE" or nil
  if d.live and d.route == false then
    geo.clearRoute()
    infoTag, infoText = "IN SIGHT", nil
    return
  end
  local target = d.geo and geo.toGame(d.geo) or (d.pos and vec3(d.pos.x, d.pos.y, d.pos.z))
  if not target then return end
  if geoMode and d.geo and geo.setGpsTarget(d.geo) then
    local info = geo.gpsInfo()
    infoText = info or infoText
    return
  end
  if core_groundMarkers then pcall(core_groundMarkers.setPath, target) end
  local veh = ownVehicle()
  if veh then
    local here = veh:getPosition()
    local meters = math.floor(here:distance(target) + 0.5)
    if d.live then
      infoText = string.format("Runner %s %s", geo.formatDistance(meters), geo.compass(here, target))
    else
      infoText = string.format("Runner seen %s %s", geo.formatDistance(meters), geo.compass(here, target))
    end
  end
end

local function runnerInfo()
  infoTag = spotted == true and "SPOTTED" or spotted == false and "HIDDEN" or nil
  return nearestText
end

local function onNearestCop(data)
  local d = jsonDecode(data) or {}
  if d.dist then
    nearestText = "Nearest cop " .. geo.formatDistance(d.dist)
    infoText = runnerInfo()
  end
end

local function onSpotted(data)
  local d = jsonDecode(data) or {}
  spotted = d.spotted == true
  infoText = runnerInfo()
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
  if role == "runner" then infoText = runnerInfo() end
end

local function onState(data)
  local d = jsonDecode(data) or {}
  if d.resetAllowed ~= resetAllowed then
    resetAllowed = d.resetAllowed and true or false
    inputs.setResetKey()
  end
  if d.resetHint then lastHint = d.resetHint end
  local p = tonumber(d.catchProgress) or 0
  hudfeed.catchSample(clock, p)
end

local function endRound()
  hudfeed.clearRound()
  sky.restore()
  traffic.stop(clock)
  runnerOut = false
  local own = ownVehicle()
  if active and role == "cop" and own then own:queueLuaCommand(LIGHTS_OFF) end
  active = false
  role = nil
  statusActive = false
  infoText = nil
  infoTag = nil
  spotted, nearestText = nil, nil
  runnerId = nil
  evolving = false
  buildBaselineAt, buildBaseline, lastChangeKey, lastChanges = nil, nil, "", {}
  geo.clearRoute()
  ai.remove()
  penaltyActive = false
  timerEnd = nil
  roundModel, roundConfig, roundColor = nil, nil, nil
  pendingPlacement = nil
  resetAllowed = false
  lastPose = nil
  if frozen then setFreeze(false) end
  inputs.unlockAll()
end

local function onRoundEnd(data)
  local d = jsonDecode(data) or {}
  local wasRunner = MPConfig and MPConfig.getPlayerServerID() == d.runnerId
  local wasActive = active
  endRound()
  local cancelled = d.reason == "cancelled" or not hudfeed.isResultReason(d.reason)
  if cancelled and not wasActive then return end
  hudfeed.showResult(d, clock)
  if d.explode and wasRunner then
    local veh = ownVehicle()
    if veh then veh:queueLuaCommand("fire.explodeVehicle()") end
  end
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
    if type(row) == "table" then row.skyLabel = sky.label(row.sky) end
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
  elseif clock >= p.deadline then
    pendingPlacement = nil
  end
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
    if role == "cop" then veh:queueLuaCommand(LIGHTS_ON) end
  end
  ai.lightsOn(sky.isNight())
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
    if info then infoText = info end
  end
end

local function runnerObject()
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

local function updateSight()
  if role ~= "cop" or not statusActive or sightMax <= 0 or clock - lastSightCheck < SIGHT_CHECK_INTERVAL then return end
  lastSightCheck = clock
  local veh, target = ownVehicle(), runnerObject()
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

local function onUpdate(dtReal)
  clock = clock + (dtReal or 0)
  sky.update(dtReal or 0)
  updatePendingPlacement()
  updateOwnCar()
  local report = ai.tick(clock)
  if #report > 0 then sendServer("cnr_aiVehicles", { ai = report }) end
  local trafficVids = traffic.tick(clock)
  if trafficVids then sendServer("cnr_trafficCars", { vids = trafficVids }) end
  updateLightsAndPatch()
  updateGeo()
  updateSight()
  updateBuild()
  updateModes()
  if active then inputs.enforceEditLock() end
  updateGpsInfo()
  hudfeed.update(clock, {
    active = active, role = role, chaseStart = statusActive and chaseStart or nil,
    resetAllowed = resetAllowed, resetHint = lastHint, penalty = penaltyActive, infoText = infoText, infoTag = infoTag,
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
  local ids = ai.relocate(own and own:getPosition())
  if #ids > 0 then sendServer("cnr_relocated", { ids = ids }) end
end

local function leaveServer()
  endRound()
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
  end)
  AddEventHandler("cnr_notice", onNotice)
  AddEventHandler("cnr_top", onTop)
  AddEventHandler("cnr_autoNext", onAutoNext)
  AddEventHandler("cnr_mode", onMode)
  AddEventHandler("cnr_rules", function(data) hudfeed.rules(jsonDecode(data)) end)
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
  if not b then return guihooks.trigger("CnRPanelReply", { text = "That car can't start a build" }) end
  M.panel({ action = "build", op = "new", model = b.model, name = b.name, parts = b.parts, vars = b.vars, from = choice.random and "random" or path })
end

function M.ui(msg)
  if type(msg) ~= "table" then return end
  local action = msg.action
  if action == "apply" then return M.applyChange() end
  if action == "color" then return sendServer("cnr_color", { hex = type(msg.hex) == "string" and msg.hex or nil }) end
  if action == "toggleApp" then
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
