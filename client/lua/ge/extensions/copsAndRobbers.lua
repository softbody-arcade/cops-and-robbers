local M = {}

local LOCKED_ACTIONS = {
  "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road", "loadHome", "saveHome",
  "reload_vehicle", "reload_all_vehicles", "reset_all_physics", "vehicle_selector",
  "dropPlayerAtCamera", "dropPlayerAtCameraNoReset", "nodegrabberGrab", "switch_next_vehicle",
  "switch_previous_vehicle", "toggleWalkingMode",
}
local RESET_ACTIONS = { "reset_physics" }
local PARTS_ACTIONS = { "parts_selector" }
local ALLOWED_TYPES = { Car = true, Truck = true }
local COP_SPACING = 8
local SETUP_DELAY = 0.5
local PLACEMENT_TIMEOUT = 5
local FREEZE_REASSERT = 0.5
local POSE_JUMP = 30

local clock = 0
local active = false
local role
local runnerId
local frozen = false
local resetAllowed = false
local lastHint
local timerEnd
local timerLabel
local lastCountdown
local roundModel
local roundConfig
local roundColor
local penaltyActive = false
local aiCars = {}
local statusActive = false
local chaseStart
local lastStatusAt = 0
local infoText
local runnerServerId
local pendingPlacement
local suppressResetUntil = 0
local lastPose
local lastFreezeAssert = 0

local function toast(msg, ttl, category)
  ui_message(msg, ttl or 4, category or "cnr", "directions_car")
end

local function sendServer(event, payload)
  if TriggerServerEvent then TriggerServerEvent(event, jsonEncode(payload or {})) end
end

local function ownVehicle()
  local veh = getPlayerVehicle(0)
  if veh and MPVehicleGE and MPVehicleGE.isOwn(veh:getID()) then return veh end
  return nil
end

local function setFreeze(on)
  frozen = on
  local veh = ownVehicle()
  if veh then veh:queueLuaCommand("controller.setFreeze(" .. (on and 1 or 0) .. ")") end
end

local function lockInputs(on)
  core_input_actionFilter.setGroup("cnr_locked", LOCKED_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_locked", on)
end

local function setResetKey(allowed)
  core_input_actionFilter.setGroup("cnr_resetKey", RESET_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_resetKey", not allowed)
end

local function setPartsMenu(allowed)
  core_input_actionFilter.setGroup("cnr_parts", PARTS_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_parts", not allowed)
end

local function unlockAll()
  lockInputs(false)
  setResetKey(true)
  setPartsMenu(true)
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

local function resetIsBound()
  for _, device in ipairs(core_input_bindings and core_input_bindings.bindings or {}) do
    for _, b in ipairs(device.contents and device.contents.bindings or {}) do
      if b.action == "reset_physics" and not b.unused then return true end
    end
  end
  return false
end

local function vehicleType(config)
  if config.Type then return config.Type end
  local model = core_vehicles.getModel(config.model_key)
  return model and model.model and model.model.Type
end

local function pickVehicle(includeMods, excludedModels)
  local excluded = { unicycle = true }
  for _, m in ipairs(excludedModels or {}) do excluded[m] = true end
  local list = core_vehicles.getConfigList(true).configs or {}
  local candidates = {}
  for _, c in ipairs(list) do
    local official = c.Source == "BeamNG - Official"
    if (official or includeMods) and ALLOWED_TYPES[vehicleType(c)] and not excluded[c.model_key] then
      candidates[#candidates + 1] = c
    end
  end
  if #candidates == 0 then return nil end
  local c = candidates[math.random(#candidates)]
  local path = c.pcFilename or ("vehicles/" .. c.model_key .. "/" .. c.key .. ".pc")
  return c.model_key, (path:gsub("^/", ""))
end

local LINK_STEP = 15
local MAX_SPAWN_RING = 2000

local function roadSpots(center, minD, maxD)
  local nodes = map.getMap().nodes or {}
  local candidates = {}
  local function consider(pos, dir)
    local d = pos:distance(center)
    if d >= minD and d <= maxD then candidates[#candidates + 1] = { pos = pos, d = d, dir = dir } end
  end
  for id, n in pairs(nodes) do
    for linkId in pairs(n.links or {}) do
      local other = nodes[linkId]
      if other and tostring(id) < tostring(linkId) then
        local delta = other.pos - n.pos
        local len = delta:length()
        if len > 1e-3 then
          local dir = delta / len
          local steps = math.max(1, math.floor(len / LINK_STEP))
          for i = 0, steps do consider(n.pos + dir * (len * i / steps), dir) end
        end
      end
    end
  end
  table.sort(candidates, function(a, b) return a.d < b.d end)
  return candidates
end

local function pickSpot(candidates, index)
  local chosen = {}
  for _, c in ipairs(candidates) do
    local free = true
    for _, prev in ipairs(chosen) do
      if prev.pos:distance(c.pos) < COP_SPACING then free = false break end
    end
    if free then
      chosen[#chosen + 1] = c
      if #chosen == index then return c end
    end
  end
  return nil
end

local function findCopSpot(center, minD, maxD, index)
  local lo, hi = minD, maxD
  while true do
    local spot = pickSpot(roadSpots(center, lo, hi), index)
    if spot then return spot.pos, quatFromDir(spot.dir, vec3(0, 0, 1)) end
    if hi >= MAX_SPAWN_RING then return nil end
    lo, hi = 0, hi * 2
  end
end

local function uprightRotation(veh)
  local dir = veh:getDirectionVector()
  dir = vec3(dir.x, dir.y, 0)
  if dir:length() < 1e-3 then dir = vec3(0, 1, 0) end
  return quatFromDir(dir:normalized(), vec3(0, 0, 1))
end

local function serverVid(veh)
  local v = MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(veh:getID())
  local s = v and v.serverVehicleString
  return s and tonumber(s:match("%-(%d+)$"))
end

local function nearestRoad(pos)
  local n1, n2 = map.findClosestRoad(pos)
  if not n1 then return nil end
  local nodes = map.getMap().nodes
  local a, b = nodes[n1], nodes[n2]
  if not a or not b then return nil end
  return a.pos, quatFromDir((b.pos - a.pos):normalized(), vec3(0, 0, 1))
end

local function teleport(veh, pos, rot)
  suppressResetUntil = clock + 2
  lastPose = { pos = pos, rot = rot }
  spawn.safeTeleport(veh, pos, rot)
end

local function vehicleOptions(config, color)
  local opt = { config = config }
  if color and color.r then
    opt.paint = createVehiclePaint({ x = color.r, y = color.g, z = color.b, w = 1 })
  end
  return opt
end

local function placeVehicle(model, config, pos, rot, color)
  local veh = ownVehicle()
  if veh then
    core_vehicles.replaceVehicle(model, vehicleOptions(config, color))
  else
    core_vehicles.spawnNewVehicle(model, vehicleOptions(config, color))
  end
  pendingPlacement = { at = clock + SETUP_DELAY, deadline = clock + PLACEMENT_TIMEOUT, pos = pos, rot = rot }
end

local function aiCommand(car, cmd)
  local obj = car.gameId and getObjectByID(car.gameId)
  if obj then obj:queueLuaCommand(cmd) end
end

local function setAIFreeze(car, on)
  car.frozen = on
  aiCommand(car, "controller.setFreeze(" .. (on and 1 or 0) .. ")")
end

local function runnerGameId()
  for _, car in pairs(aiCars) do
    if car.role == "runner" then return car.gameId end
  end
  local veh = getPlayerVehicle(0)
  return veh and veh:getID()
end

local function startChase(car)
  local target = runnerGameId()
  if not target then return end
  aiCommand(car, "ai.setTargetObjectID(" .. target .. ")")
  aiCommand(car, 'ai.setMode("chase")')
end

local function startFlee(car)
  local veh = getPlayerVehicle(0)
  if veh then aiCommand(car, "ai.setTargetObjectID(" .. veh:getID() .. ")") end
  aiCommand(car, 'ai.setMode("flee")')
end

local function removeAICars()
  for _, car in pairs(aiCars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      obj:queueLuaCommand('ai.setMode("disabled")')
      obj:delete()
    end
  end
  aiCars = {}
end

local function onSetupAI(data)
  local d = jsonDecode(data) or {}
  removeAICars()
  runnerServerId = d.runnerId
  local own = ownVehicle()
  local center = own and own:getPosition()
  for _, a in ipairs(d.ai or {}) do
    local pos, rot
    if center then pos, rot = findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, a.index or 1) end
    local opt = vehicleOptions(d.config, a.color)
    opt.autoEnterVehicle = false
    opt.pos, opt.rot = pos, rot
    local veh = core_vehicles.spawnNewVehicle(d.model, opt)
    if veh then
      aiCars[a.id] = { id = a.id, role = a.role, name = a.name, gameId = veh:getID(), frozen = true, reported = false }
    else
      toast("Could not spawn " .. tostring(a.name) .. ", is MaxCars high enough?", 6, "cnr_reset")
    end
  end
end

local function onPickVehicle(data)
  local d = jsonDecode(data) or {}
  local model, config = pickVehicle(d.includeMods, d.excludedModels)
  if not model then
    toast("No vehicles available to pick", 6)
    return
  end
  sendServer("cnr_vehiclePicked", { model = model, config = config })
end

local function onRoundSetup(data)
  local d = jsonDecode(data) or {}
  active = true
  role = d.role
  runnerId = d.runnerId
  roundModel, roundConfig, roundColor = d.model, d.config, d.color
  resetAllowed = false
  lastHint = nil
  lastPose = nil
  lockInputs(true)
  setResetKey(false)
  setPartsMenu(d.phase == "prep")
  if not resetIsBound() then
    toast("Bind 'Reset vehicle' to a wheel button to reset during rounds", 10, "cnr_binding")
  end

  local pos, rot
  if d.resumePos then
    local back = vec3(d.resumePos.x, d.resumePos.y, d.resumePos.z)
    pos, rot = nearestRoad(back)
    if not pos then pos, rot = back, nil end
  elseif role == "cop" and not d.inPlace then
    local own = ownVehicle()
    local center = d.runnerPos and vec3(d.runnerPos.x, d.runnerPos.y, d.runnerPos.z) or (own and own:getPosition())
    if center then
      pos, rot = findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, math.max(d.copIndex or 1, 1))
    end
  end
  placeVehicle(d.model, d.config, pos, rot, d.color)

  local phase = d.phase or "running"
  frozen = phase == "prep" or phase == "countdown" or (phase == "headstart" and role == "cop")
  if phase == "prep" then
    toast(role == "runner" and "You are the runner! Change your paint if you like, waiting for /cnr go" or "You are a cop! Change your paint if you like, waiting for /cnr go", 8, "cnr_go")
    timerEnd = nil
  elseif phase == "countdown" then
    startTimer(tonumber(d.countdownRemaining), "Runner starts in")
  elseif phase == "headstart" then
    startTimer(tonumber(d.headStartRemaining), "Cops released in")
  else
    timerEnd = nil
  end
end

local function onCountdown(data)
  local d = jsonDecode(data) or {}
  setPartsMenu(false)
  startTimer(tonumber(d.seconds), "Runner starts in")
end

local function onRunnerGo(data)
  local d = jsonDecode(data) or {}
  for _, car in pairs(aiCars) do
    if car.role == "runner" then
      setAIFreeze(car, false)
      startFlee(car)
    end
  end
  if role == "runner" then
    timerEnd = nil
    setFreeze(false)
    toast("GO! Run!", 4, "cnr_go")
  else
    startTimer(tonumber(d.headStartSeconds), "Cops released in")
  end
end

local function repaintInPlace(color)
  local veh = ownVehicle()
  if not veh or not roundModel then return end
  roundColor = color
  placeVehicle(roundModel, roundConfig, veh:getPosition(), uprightRotation(veh), color)
end

local function onPaint(data)
  local d = jsonDecode(data) or {}
  repaintInPlace(d.color)
end

local function onRestoreConfig(data)
  local d = jsonDecode(data) or {}
  roundModel, roundConfig = d.model or roundModel, d.config or roundConfig
  toast("Only paint can be changed, car reset to the round setup", 5, "cnr_reset")
  repaintInPlace(d.color or roundColor)
end

local function onPenalty(data)
  local d = jsonDecode(data) or {}
  if d.aiId then
    local car = aiCars[d.aiId]
    if car then
      setAIFreeze(car, true)
      aiCommand(car, 'ai.setMode("disabled")')
      toast(tostring(car.name) .. " crashed: penalty", 3, "cnr_reset")
    end
    return
  end
  penaltyActive = true
  setFreeze(true)
  startTimer(tonumber(d.seconds), "Crash penalty")
end

local function onPenaltyEnd(data)
  local d = jsonDecode(data or "{}") or {}
  if d.aiId then
    local car = aiCars[d.aiId]
    if car then
      setAIFreeze(car, false)
      startChase(car)
    end
    return
  end
  penaltyActive = false
  lastHint = nil
  timerEnd = nil
  setFreeze(false)
  toast("Penalty over, go!", 3, "cnr_go")
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function compass(from, to)
  local angle = math.deg(math.atan2(to.x - from.x, to.y - from.y)) % 360
  return COMPASS[math.floor((angle + 22.5) / 45) % 8 + 1]
end

local function clearRoute()
  if core_groundMarkers then pcall(core_groundMarkers.setPath, nil) end
end

local function onLastSeen(data)
  local d = jsonDecode(data) or {}
  if not d.pos then return end
  local target = vec3(d.pos.x, d.pos.y, d.pos.z)
  if core_groundMarkers then pcall(core_groundMarkers.setPath, target) end
  local veh = ownVehicle()
  if veh then
    local here = veh:getPosition()
    infoText = string.format("Runner seen %d m %s", math.floor(here:distance(target) + 0.5), compass(here, target))
    toast(infoText, 4, "cnr_seen")
  end
end

local function onNearestCop(data)
  local d = jsonDecode(data) or {}
  if d.dist then infoText = string.format("Nearest cop %d m", math.floor(d.dist + 0.5)) end
end

local function onNotice(data)
  local d = jsonDecode(data) or {}
  if d.about ~= nil and MPConfig and d.about == MPConfig.getPlayerServerID() then return end
  if d.msg then toast(d.msg, 4, "cnr_notice") end
end

local function startStatus()
  statusActive = true
  chaseStart = clock
  lastStatusAt = 0
  infoText = nil
end

local function onRelease()
  for _, car in pairs(aiCars) do
    if car.role == "cop" then
      setAIFreeze(car, false)
      startChase(car)
    end
  end
  timerEnd = nil
  if frozen then setFreeze(false) end
  if role == "cop" then toast("GO!", 3, "cnr_go") end
  startStatus()
end
local function onState(data)
  local d = jsonDecode(data) or {}
  if d.resetAllowed ~= resetAllowed then
    resetAllowed = d.resetAllowed and true or false
    setResetKey(resetAllowed)
  end
  if d.resetHint and d.resetHint ~= lastHint then
    lastHint = d.resetHint
    if not penaltyActive and not statusActive then toast(d.resetHint, 3, "cnr_reset") end
  end
  local p = tonumber(d.catchProgress) or 0
  if p > 0 then
    local pct = math.floor(p * 100 + 0.5)
    if role == "runner" then
      toast(string.format("BEING CAUGHT %d%%", pct), 1, "cnr_catch")
    else
      toast(string.format("HOLDING RUNNER %d%%", pct), 1, "cnr_catch")
    end
  end
end

local function formatTime(seconds)
  local total = math.floor(seconds or 0)
  return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

local function endRound()
  active = false
  role = nil
  statusActive = false
  infoText = nil
  clearRoute()
  removeAICars()
  penaltyActive = false
  timerEnd = nil
  roundModel, roundConfig, roundColor = nil, nil, nil
  pendingPlacement = nil
  resetAllowed = false
  lastPose = nil
  if frozen then setFreeze(false) end
  unlockAll()
end

local function onRoundEnd(data)
  local d = jsonDecode(data) or {}
  local wasRunner = MPConfig and MPConfig.getPlayerServerID() == d.runnerId
  endRound()
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
  if d.explode and wasRunner then
    local veh = ownVehicle()
    if veh then veh:queueLuaCommand("fire.explodeVehicle()") end
  end
end

local function onRequestStations(data)
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

local function onUpdate(dtReal)
  clock = clock + (dtReal or 0)
  if pendingPlacement and clock >= pendingPlacement.at then
    local p = pendingPlacement
    local veh = ownVehicle()
    local vid = veh and serverVid(veh)
    if veh and vid then
      pendingPlacement = nil
      if p.pos then teleport(veh, p.pos, p.rot) end
      if frozen then setFreeze(true) end
      sendServer("cnr_myVehicle", { vid = vid })
    elseif clock >= p.deadline then
      pendingPlacement = nil
    end
  end
  if active and not pendingPlacement then
    local veh = ownVehicle()
    if veh then
      local pos = veh:getPosition()
      if not lastPose or pos:distance(lastPose.pos) <= POSE_JUMP then
        lastPose = { pos = pos, rot = uprightRotation(veh) }
      end
      if frozen and clock - lastFreezeAssert >= FREEZE_REASSERT then
        lastFreezeAssert = clock
        veh:queueLuaCommand("controller.setFreeze(1)")
      end
    end
  end
  local report = {}
  for _, car in pairs(aiCars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      if not car.reported then
        local vid = serverVid(obj)
        if vid then
          car.reported = true
          report[#report + 1] = { id = car.id, vid = vid }
        end
      end
      if car.frozen and clock - (car.lastFreeze or 0) >= FREEZE_REASSERT then
        car.lastFreeze = clock
        obj:queueLuaCommand("controller.setFreeze(1)")
      end
    end
  end
  if #report > 0 then sendServer("cnr_aiVehicles", { ai = report }) end
  if statusActive and clock - lastStatusAt >= 1 then
    lastStatusAt = clock
    local parts = { formatTime(clock - chaseStart) }
    if penaltyActive then
      parts[#parts + 1] = "Penalty"
    elseif resetAllowed then
      parts[#parts + 1] = "Reset OK"
    elseif lastHint then
      parts[#parts + 1] = lastHint
    end
    if infoText then parts[#parts + 1] = infoText end
    toast(table.concat(parts, "  |  "), 1.5, "cnr_status")
  end
  if timerEnd then
    local left = math.ceil(timerEnd - clock)
    if left > 0 and left ~= lastCountdown then
      lastCountdown = left
      toast(string.format("%s %d", timerLabel, left), 1.2, "cnr_go")
    elseif left <= 0 then
      timerEnd = nil
    end
  end
end

local function onVehicleResetted(gameVid)
  if not active or clock < suppressResetUntil or not lastPose then return end
  local veh = ownVehicle()
  if not veh or veh:getID() ~= gameVid then return end
  local pos, rot = lastPose.pos, lastPose.rot
  if role == "cop" then
    local roadPos, roadRot = nearestRoad(pos)
    if roadPos then pos, rot = roadPos, roadRot end
  end
  teleport(veh, pos, rot)
end

local function onExtensionLoaded()
  if AddEventHandler then
    AddEventHandler("cnr_pickVehicle", onPickVehicle)
    AddEventHandler("cnr_roundSetup", onRoundSetup)
    AddEventHandler("cnr_release", onRelease)
    AddEventHandler("cnr_countdown", onCountdown)
    AddEventHandler("cnr_runnerGo", onRunnerGo)
    AddEventHandler("cnr_paint", onPaint)
    AddEventHandler("cnr_penalty", onPenalty)
    AddEventHandler("cnr_setupAI", onSetupAI)
    AddEventHandler("cnr_notice", onNotice)
    AddEventHandler("cnr_lastSeen", onLastSeen)
    AddEventHandler("cnr_nearestCop", onNearestCop)
    AddEventHandler("cnr_penaltyEnd", onPenaltyEnd)
    AddEventHandler("cnr_restoreConfig", onRestoreConfig)
    AddEventHandler("cnr_state", onState)
    AddEventHandler("cnr_roundEnd", onRoundEnd)
    AddEventHandler("cnr_requestStations", onRequestStations)
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = endRound
M.onClientEndMission = endRound
M.onUpdate = onUpdate
M.onVehicleResetted = onVehicleResetted

return M
