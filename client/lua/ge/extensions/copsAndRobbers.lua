local M = {}

local hud = require("copsAndRobbers/hud")
local game = require("copsAndRobbers/game")
local inputs = require("copsAndRobbers/inputs")
local roads = require("copsAndRobbers/roads")
local vehicles = require("copsAndRobbers/vehicles")
local ai = require("copsAndRobbers/ai")
local geo = require("copsAndRobbers/geo")
local hudfeed = require("copsAndRobbers/hudfeed")
local sight = require("copsAndRobbers/sight")

local CLIENT_VERSION = "1.6.0"
local LIGHTS_ON = "electrics.set_lightbar_signal(1)"
local LIGHTS_OFF = "electrics.set_lightbar_signal(0)"
local SETUP_DELAY = 0.5
local PLACEMENT_TIMEOUT = 5
local FREEZE_REASSERT = 0.5
local POSE_JUMP = 30
local GEO_SEND_INTERVAL = 0.25
local SIGHT_CHECK_INTERVAL = 0.25
local ACTIONS_FILE = "/lua/ge/extensions/core/input/actions/copsAndRobbers.json"

local toast, sendServer, ownVehicle = game.toast, game.sendServer, game.ownVehicle
local formatTime = hud.formatTime

local clock = 0
local active = false
local role
local frozen = false
local resetAllowed = false
local lastHint
local timerEnd, timerLabel, lastCountdown
local roundModel, roundConfig, roundColor
local penaltyActive = false
local statusActive = false
local geoMode = false
local lastGeoSent = 0
local chaseStart
local lastStatusAt = 0
local infoText
local pendingPlacement
local suppressResetUntil = 0
local lastPose
local lastFreezeAssert = 0
local runnerId
local sightMax = 0
local sightState = sight.new()
local lastSightCheck = 0
local infoSuffix = ""
local spotted, nearestText
local requestReset

local function setFreeze(on)
  frozen = on
  local veh = ownVehicle()
  if veh then veh:queueLuaCommand("controller.setFreeze(" .. (on and 1 or 0) .. ")") end
end

local function startTimer(seconds, label)
  if seconds and seconds > 0 then
    timerEnd = clock + seconds
    timerLabel = label
    lastCountdown = nil
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
  pendingPlacement = { at = clock + SETUP_DELAY, deadline = clock + PLACEMENT_TIMEOUT, pos = pos, rot = rot }
end

local function startStatus()
  statusActive = true
  chaseStart = clock
  lastStatusAt = 0
  infoText = nil
end

local function onSetupAI(data)
  ai.setup(jsonDecode(data) or {})
end

local function onPickVehicle(data)
  local d = jsonDecode(data) or {}
  local model, config = vehicles.pick(d.includeMods, d.excludedModels)
  if not model then
    toast("No vehicles available to pick", 6)
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
  if not pos then toast("No road found near the runner, you start where you are", 6, "cnr_reset") end
  return pos, rot
end

local function onRoundSetup(data)
  local d = jsonDecode(data) or {}
  hudfeed.clearRound()
  hudfeed.clearResult()
  active = true
  role = d.role
  runnerId = d.runnerId
  sightMax = tonumber(d.sightMaxMeters) or 0
  sightState = sight.new()
  roundModel, roundColor = d.model, d.color
  roundConfig = d.role == "cop" and vehicles.copConfig(d.model, d.config) or d.config
  resetAllowed = false
  lastHint = nil
  lastPose = nil
  inputs.lock(true, requestReset)
  inputs.setResetKey()
  inputs.setPartsMenu(d.phase == "prep")
  if not inputs.resetIsBound() then
    toast("Bind a reset or recover button to reset during rounds", 10, "cnr_binding")
  end

  local pos, rot = setupPosition(d)
  placeVehicle(d.model, roundConfig, pos, rot, d.color)

  local phase = d.phase or "running"
  frozen = phase == "prep" or phase == "countdown" or (phase == "headstart" and role == "cop")
  if phase == "prep" then
    hudfeed.prep(role, game.carName(d.model))
    hudfeed.notify(role == "runner" and 'You are the runner! Change your paint if you like, waiting for "/cnr go"'
      or 'You are a cop! Change your paint if you like, waiting for "/cnr go"', 8, "cnr_go")
    timerEnd = nil
  elseif phase == "countdown" then
    startTimer(tonumber(d.countdownRemaining), "Runner starts in")
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

local function onCountdown(data)
  local d = jsonDecode(data) or {}
  hudfeed.prep(nil)
  inputs.setPartsMenu(false)
  startTimer(tonumber(d.seconds), "Runner starts in")
end

local function onRunnerGo(data)
  local d = jsonDecode(data) or {}
  ai.releaseRunner()
  if role == "runner" then
    timerEnd = nil
    setFreeze(false)
    hudfeed.flash("GO! RUN!", clock)
    hudfeed.notify("GO! Run!", 4, "cnr_go")
  else
    startTimer(tonumber(d.headStartSeconds), "Cops released in")
  end
end

local function onPaint(data)
  local d = jsonDecode(data) or {}
  local veh = ownVehicle()
  if not veh or not roundModel then return end
  roundColor = d.color
  placeVehicle(roundModel, roundConfig, veh:getPosition(), game.uprightRotation(veh), d.color)
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
  hudfeed.notify("Penalty over, go!", 3, "cnr_go")
end

local function onLastSeen(data)
  local d = jsonDecode(data) or {}
  infoSuffix = d.live and " · live" or ""
  if d.live and d.route == false then
    geo.clearRoute()
    infoText = "IN SIGHT"
    return
  end
  local target = d.geo and geo.toGame(d.geo) or (d.pos and vec3(d.pos.x, d.pos.y, d.pos.z))
  if not target then return end
  if geoMode and d.geo and geo.setGpsTarget(d.geo) then
    local info = geo.gpsInfo()
    infoText = info and (info .. infoSuffix) or infoText
    if info and not d.live then hudfeed.notify(infoText, 4, "cnr_seen") end
    return
  end
  if core_groundMarkers then pcall(core_groundMarkers.setPath, target) end
  local veh = ownVehicle()
  if veh then
    local here = veh:getPosition()
    local meters = math.floor(here:distance(target) + 0.5)
    if d.live then
      infoText = string.format("Runner %s %s · live", geo.formatDistance(meters), geo.compass(here, target))
    else
      infoText = string.format("Runner seen %d m %s", meters, geo.compass(here, target))
      hudfeed.notify(infoText, 4, "cnr_seen")
    end
  end
end

local function runnerInfo()
  local tag = spotted == true and "SPOTTED" or spotted == false and "HIDDEN" or nil
  if tag and nearestText then return tag .. " · " .. nearestText end
  return tag or nearestText
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
  if geoMode and not geo.api() then
    toast("Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map", 10, "cnr_mode")
  end
  if d.version and d.version ~= CLIENT_VERSION then
    toast(string.format("Cops and Robbers: your copy is %s, the server runs %s. Rejoin to update.", CLIENT_VERSION, d.version), 10, "cnr_version")
  end
end

local function onNotice(data)
  local d = jsonDecode(data) or {}
  if d.about ~= nil and MPConfig and d.about == MPConfig.getPlayerServerID() then return end
  if d.msg then
    hudfeed.event(d.msg, clock)
    hudfeed.notify(d.msg, 4, "cnr_notice")
  end
end

local function onRelease()
  ai.releaseCops()
  timerEnd = nil
  if frozen then setFreeze(false) end
  if role == "cop" then
    hudfeed.flash("GO!", clock)
    hudfeed.notify("GO!", 3, "cnr_go")
  end
  startStatus()
end

local function onState(data)
  local d = jsonDecode(data) or {}
  if d.resetAllowed ~= resetAllowed then
    resetAllowed = d.resetAllowed and true or false
    inputs.setResetKey()
  end
  if d.resetHint and d.resetHint ~= lastHint then
    lastHint = d.resetHint
    if not penaltyActive and not statusActive then toast(d.resetHint, 3, "cnr_reset") end
  end
  local p = tonumber(d.catchProgress) or 0
  hudfeed.catchSample(clock, p)
  if p > 0 then
    local pct = math.floor(p * 100 + 0.5)
    hudfeed.notify(string.format(role == "runner" and "BEING CAUGHT %d%%" or "HOLDING RUNNER %d%%", pct), 1, "cnr_catch")
  end
end

local function endRound()
  hudfeed.clearRound()
  local own = ownVehicle()
  if active and role == "cop" and own then own:queueLuaCommand(LIGHTS_OFF) end
  active = false
  role = nil
  statusActive = false
  infoText = nil
  infoSuffix = ""
  spotted, nearestText = nil, nil
  runnerId = nil
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

local function showEndToast(d)
  if d.reason == "caught" then
    local by = (type(d.catchers) == "table" and #d.catchers > 0) and (" by " .. table.concat(d.catchers, ", ")) or ""
    toast(string.format("Runner caught%s! %s survived %s", by, tostring(d.runnerName), formatTime(d.survivedSeconds)), 8, "cnr_end")
  elseif d.reason == "called" then
    toast(string.format("Round ended: %s survived %s", tostring(d.runnerName), formatTime(d.survivedSeconds)), 8, "cnr_end")
  elseif d.reason == "escaped" then
    toast(string.format("%s escaped! Survived %s", tostring(d.runnerName), formatTime(d.survivedSeconds)), 8, "cnr_end")
  elseif d.reason == "disconnect" then
    toast(string.format("%s left after %s", tostring(d.runnerName), formatTime(d.survivedSeconds)), 8, "cnr_end")
  else
    toast("Round cancelled", 5, "cnr_end")
  end
end

local function onRoundEnd(data)
  local d = jsonDecode(data) or {}
  local wasRunner = MPConfig and MPConfig.getPlayerServerID() == d.runnerId
  local wasActive = active
  endRound()
  local cancelled = d.reason == "cancelled" or not hudfeed.isResultReason(d.reason)
  if cancelled and not wasActive then return end
  hudfeed.showResult(d, clock)
  if not hudfeed.placed() then showEndToast(d) end
  if d.explode and wasRunner then
    local veh = ownVehicle()
    if veh then veh:queueLuaCommand("fire.explodeVehicle()") end
  end
end

local function onTop(data)
  hudfeed.top((jsonDecode(data) or {}).lines)
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
    if frozen then setFreeze(true) end
    sendServer("cnr_myVehicle", { vid = vid })
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

local function updateLightsAndPatch()
  if not active or not inputs.patchDue(clock) then return end
  local veh = ownVehicle()
  if veh then
    veh:queueLuaCommand(inputs.VEHICLE_PATCH)
    if role == "cop" then veh:queueLuaCommand(LIGHTS_ON) end
  end
  ai.lightsOn()
end

local function updateGeo()
  if not geoMode then return end
  if clock - lastGeoSent >= GEO_SEND_INTERVAL then
    lastGeoSent = clock
    geo.sendGeo(ai.objects())
  end
  geo.lookupStations(clock)
end

local function updateStatusToast()
  if not statusActive or clock - lastStatusAt < 1 then return end
  lastStatusAt = clock
  local parts = { formatTime(clock - chaseStart) }
  if penaltyActive then
    parts[#parts + 1] = "Penalty"
  elseif resetAllowed then
    parts[#parts + 1] = "Reset OK"
  elseif lastHint then
    parts[#parts + 1] = lastHint
  end
  if geo.hasTarget() then
    local info = geo.gpsInfo()
    if info then infoText = info .. infoSuffix end
  end
  if infoText then parts[#parts + 1] = infoText end
  hudfeed.notify(table.concat(parts, "  |  "), 1.5, "cnr_status")
end

local function updateCountdownToast()
  if not timerEnd then return end
  local left = math.ceil(timerEnd - clock)
  if left > 0 and left ~= lastCountdown then
    lastCountdown = left
    hudfeed.notify(string.format("%s %d", timerLabel, left), 1.2, "cnr_go")
  elseif left <= 0 then
    timerEnd = nil
  end
end

local function runnerObject()
  local aiRunner = ai.runnerObject()
  if aiRunner then return aiRunner end
  if not runnerId or not MPVehicleGE or not MPVehicleGE.getVehicles then return nil end
  local prefix = tostring(runnerId) .. "-"
  for key, v in pairs(MPVehicleGE.getVehicles() or {}) do
    if type(key) == "string" and key:sub(1, #prefix) == prefix and type(v) == "table"
      and v.isSpawned ~= false and not v.isDeleted and v.gameVehicleID then
      local obj = getObjectByID(v.gameVehicleID)
      if obj then return obj end
    end
  end
  return nil
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
  updatePendingPlacement()
  updateOwnCar()
  local report = ai.tick(clock)
  if #report > 0 then sendServer("cnr_aiVehicles", { ai = report }) end
  updateLightsAndPatch()
  updateGeo()
  updateSight()
  updateStatusToast()
  hudfeed.update(clock, {
    active = active, role = role, chaseStart = statusActive and chaseStart or nil,
    resetAllowed = resetAllowed, resetHint = lastHint, penalty = penaltyActive, infoText = infoText,
    timer = timerEnd and { label = timerLabel, endsAt = timerEnd } or nil,
  })
  updateCountdownToast()
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
    if hudfeed.placed() then
      if not statusActive then hudfeed.event(msg, clock) end
    else
      toast(msg, 3, "cnr_reset")
    end
    return
  end
  resetAllowed = false
  local pos, rot = veh:getPosition(), game.uprightRotation(veh)
  if kind == "road" and role == "cop" then
    local roadPos, roadRot = roads.nearestRoad(pos)
    if roadPos then
      pos, rot = roadPos, roadRot
    else
      toast("No road found nearby, repaired in place", 4, "cnr_reset")
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

local function refreshActions()
  extensions.hook("onFileChanged", ACTIONS_FILE, "modified")
end

local function leaveServer()
  endRound()
  hudfeed.clearResult()
  hudfeed.leave()
  guihooks.trigger("CnRPanel", {})
end

local function onExtensionLoaded()
  refreshActions()
  hudfeed.refreshApps()
  hudfeed.start(clock)
  if not AddEventHandler then return end
  AddEventHandler("cnr_pickVehicle", onPickVehicle)
  AddEventHandler("cnr_roundSetup", onRoundSetup)
  AddEventHandler("cnr_release", onRelease)
  AddEventHandler("cnr_countdown", onCountdown)
  AddEventHandler("cnr_runnerGo", onRunnerGo)
  AddEventHandler("cnr_paint", onPaint)
  AddEventHandler("cnr_penalty", onPenalty)
  AddEventHandler("cnr_setupAI", onSetupAI)
  AddEventHandler("cnr_notice", onNotice)
  AddEventHandler("cnr_top", onTop)
  AddEventHandler("cnr_autoNext", onAutoNext)
  AddEventHandler("cnr_mode", onMode)
  AddEventHandler("cnr_lastSeen", onLastSeen)
  AddEventHandler("cnr_nearestCop", onNearestCop)
  AddEventHandler("cnr_spotted", onSpotted)
  AddEventHandler("cnr_penaltyEnd", onPenaltyEnd)
  AddEventHandler("cnr_state", onState)
  AddEventHandler("cnr_roundEnd", onRoundEnd)
  AddEventHandler("cnr_requestStations", onRequestStations)
  AddEventHandler("cnr_panelState", function(data) guihooks.trigger("CnRPanel", jsonDecode(data) or {}) end)
  AddEventHandler("cnr_panelReply", function(data) guihooks.trigger("CnRPanelReply", jsonDecode(data) or {}) end)
end

function M.command(text)
  if TriggerServerEvent then TriggerServerEvent("cnr_command", tostring(text)) end
end

function M.panel(msg)
  if TriggerServerEvent and type(msg) == "table" then TriggerServerEvent("cnr_panel", jsonEncode(msg)) end
end

M.requestReset = requestReset
M.onBeamNGEarthRebased = onBeamNGEarthRebased
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = function()
  leaveServer()
  refreshActions()
  for name in pairs(package.loaded) do
    if name:find("^copsAndRobbers/") then package.loaded[name] = nil end
  end
end
M.onClientEndMission = leaveServer
M.onBeamMPServerLeave = leaveServer
M.onGameStateUpdate = function()
  hudfeed.layoutChanged(clock)
end
M.onWorldReadyState = function(st)
  if st == 2 then hudfeed.start(clock) end
end
M.onUpdate = onUpdate
M.onVehicleResetted = onVehicleResetted

return M
