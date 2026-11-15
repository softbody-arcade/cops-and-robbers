local M = {}

local hud = require("copsAndRobbers/hud")
local lightbar = require("copsAndRobbers/lightbar")
local placement = require("copsAndRobbers/placement")

local CLIENT_VERSION = "1.3.1"
local LIGHTS_ON = "electrics.set_lightbar_signal(1)"
local LIGHTS_OFF = "electrics.set_lightbar_signal(0)"

local LOCKED_ACTIONS = {
  "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road", "loadHome", "saveHome",
  "reload_vehicle", "reload_all_vehicles", "reset_all_physics", "vehicle_selector",
  "dropPlayerAtCamera", "dropPlayerAtCameraNoReset", "nodegrabberGrab", "switch_next_vehicle",
  "switch_previous_vehicle", "toggleWalkingMode",
}
local EXTRA_LOCKED_ACTIONS = {
  "toggleWalkingMode", "photomode", "toggleTrackBuilder", "toggleConsoleNG", "cefdev_console_toggle", "lua_reload",
  "toggleTraffic", "toggleAITraffic", "debugmode_reset",
}
local RESET_BUTTONS = { reset_physics = true, recover_vehicle = true, recover_vehicle_alt = true, recover_to_last_road = true, loadHome = true }
local GATED_ACTIONS = { reset_physics = true, parts_selector = true, recover_vehicle = true, recover_vehicle_alt = true, recover_to_last_road = true, loadHome = true }
local VEHICLE_PATCH_INTERVAL = 2
local VEHICLE_PATCH = table.concat({
  "if not cnrOrig then cnrOrig = { s = recovery.startRecovering, t = recovery.stopRecovering, h = recovery.loadHome } end",
  "recovery.startRecovering = function() obj:queueGameEngineLua('if copsAndRobbers then copsAndRobbers.requestReset(\"place\") end') end",
  "recovery.stopRecovering = function() end",
  "recovery.loadHome = function() obj:queueGameEngineLua('if copsAndRobbers then copsAndRobbers.requestReset(\"road\") end') end",
}, " ")
local VEHICLE_UNPATCH = "if cnrOrig then recovery.startRecovering, recovery.stopRecovering, recovery.loadHome = cnrOrig.s, cnrOrig.t, cnrOrig.h; cnrOrig = nil end"
local RESET_ACTIONS = { "reset_physics" }
local PARTS_ACTIONS = { "parts_selector" }
local ALLOWED_TYPES = { Car = true, Truck = true }
local COP_SPACING = 8
local SETUP_DELAY = 0.5
local PLACEMENT_TIMEOUT = 5
local FREEZE_REASSERT = 0.5
local POSE_JUMP = 30

local clock = 0
local HUD_APP = "copsAndRobbersHud"
local HUD_PLACEMENT = { left = "0", right = "0", margin = "auto", bottom = "70px", width = "520px", height = "90px" }
local HUD_FILES = { "/ui/modules/apps/CopsAndRobbersHud/app.json", "/ui/modules/apps/CopsAndRobbersHud/app.vue" }
local HUD_PUSH_INTERVAL = 0.1
local PLACEMENT_INTERVAL = 2
local PLACEMENT_DELAY = 3
local hudState = hud.new()
local hudPlaced = false
local hudVisibleSent = false
local lastHudPush = 0
local lastPlacementCheck = 0
local loadedAt
local placementState = placement.new(HUD_APP, HUD_PLACEMENT)
local BANNER_LABELS = { ["Runner starts in"] = "RUNNER STARTS IN", ["Cops released in"] = "COPS RELEASED IN", ["Crash penalty"] = "CRASH PENALTY" }
local RESULT_TITLES = { caught = "RUNNER CAUGHT", called = "ROUND ENDED", escaped = "ESCAPED", disconnect = "RUNNER LEFT", cancelled = "ROUND CANCELLED" }
local FLASH_SECONDS, EVENT_SECONDS, RESET_FLASH_SECONDS, RESULT_SECONDS = 2, 4, 1.5, 10
local hudFlash, hudPrep, hudResetFlashUntil, hudResult
local hudEvents = {}
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
local geoMode = false
local lastGeoSent = 0
local lastPlacesAt = -math.huge
local lastPlacesGeo
local GEO_SEND_INTERVAL = 0.25
local PLACES_INTERVAL = 60
local PLACES_MOVE_METERS = 1000
local PLACES_RADIUS = 3000
local chaseStart
local lastStatusAt = 0
local infoText
local runnerServerId
local pendingPlacement
local suppressResetUntil = 0
local lastPose
local lastFreezeAssert = 0

local function earthApi()
  local api = rawget(_G, "beamngEarth_api")
  if api and api.version and api.version() == 1 then return api end
  return nil
end

local function geoToGame(g)
  local api = earthApi()
  if not api or type(g) ~= "table" or not g.lat or not g.lon then return nil end
  local x, y, z = api.toGame(g.lat, g.lon, g.h or 0)
  if not x then return nil end
  return vec3(x, y, z)
end

local function gameToGeo(pos)
  local api = earthApi()
  if not api or not pos then return nil end
  local lat, lon, h = api.toGeo(pos.x, pos.y, pos.z)
  if not lat then return nil end
  return lat, lon, h
end

local function setFlash(text)
  hudFlash = { text = text, untilT = clock + FLASH_SECONDS }
end

local function addEvent(text)
  hudEvents[#hudEvents + 1] = { text = text, untilT = clock + EVENT_SECONDS }
  while #hudEvents > 5 do table.remove(hudEvents, 1) end
end

local function carName(model)
  local ok, m = pcall(core_vehicles.getModel, model)
  local info = ok and type(m) == "table" and m.model
  if type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
    local brand = type(info.Brand) == "string" and info.Brand ~= "" and (info.Brand .. " ") or ""
    return brand .. info.Name
  end
  return tostring(model)
end

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

local function lockedActions()
  local seen, list = {}, {}
  local function add(name)
    if type(name) == "string" and not seen[name] and not GATED_ACTIONS[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  local templates = core_input_actionFilter.getActionTemplates and core_input_actionFilter.getActionTemplates()
  for _, name in ipairs(templates and templates.competitive or {}) do add(name) end
  for _, name in ipairs(LOCKED_ACTIONS) do add(name) end
  for _, name in ipairs(EXTRA_LOCKED_ACTIONS) do add(name) end
  return list
end

local originalBigMapTeleport

local function guardBigMapTeleport(on)
  local bigMap = rawget(_G, "freeroam_bigMapMode")
  if not bigMap then return end
  if on and not originalBigMapTeleport then
    originalBigMapTeleport = bigMap.teleportToPoi
    bigMap.teleportToPoi = function()
      ui_message("Teleporting is disabled during a Cops and Robbers round", 4, "cnr_reset", "directions_car")
    end
  elseif not on and originalBigMapTeleport then
    bigMap.teleportToPoi = originalBigMapTeleport
    originalBigMapTeleport = nil
  end
end

local originalResetGameplay, originalLastRoad
local lastVehiclePatch = -math.huge

local function hookResetButtons(on)
  if on then
    if not originalResetGameplay then
      originalResetGameplay = rawget(_G, "resetGameplay")
      rawset(_G, "resetGameplay", function() M.requestReset("place") end)
    end
    if spawn and not originalLastRoad then
      originalLastRoad = spawn.teleportToLastRoad
      spawn.teleportToLastRoad = function() M.requestReset("road") end
    end
    lastVehiclePatch = -math.huge
  else
    if originalResetGameplay then
      rawset(_G, "resetGameplay", originalResetGameplay)
      originalResetGameplay = nil
    end
    if originalLastRoad then
      spawn.teleportToLastRoad = originalLastRoad
      originalLastRoad = nil
    end
    local veh = getPlayerVehicle(0)
    if veh then veh:queueLuaCommand(VEHICLE_UNPATCH) end
  end
end

local function lockInputs(on)
  core_input_actionFilter.setGroup("cnr_locked", lockedActions())
  core_input_actionFilter.addAction(0, "cnr_locked", on)
  guardBigMapTeleport(on)
  hookResetButtons(on)
end

local function setResetKey()
  core_input_actionFilter.setGroup("cnr_resetKey", RESET_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_resetKey", false)
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
      if RESET_BUTTONS[b.action] and not b.unused then return true end
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

local ROAD_SEARCH_MAX = 2000

local function closestNodeFallback(pos)
  local nodes = map.getMap().nodes or {}
  local best, bestDist, bestLink
  for id, n in pairs(nodes) do
    local d = n.pos:distance(pos)
    if d <= ROAD_SEARCH_MAX and (not bestDist or d < bestDist) then
      for linkId in pairs(n.links or {}) do
        if nodes[linkId] then best, bestDist, bestLink = id, d, linkId break end
      end
    end
  end
  return best, bestLink
end

local function nearestRoad(pos)
  local n1, n2 = map.findClosestRoad(pos)
  if not n1 then n1, n2 = closestNodeFallback(pos) end
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

local function hasLightbar(parts)
  for _, part in pairs(parts or {}) do
    if type(part) == "string" and part ~= "" and part:lower():find("lightbar", 1, true) then return true end
  end
  return false
end

local function lightbarParts(model)
  local m = core_vehicles.getModel(model)
  local best
  for _, c in pairs(m and m.configs or {}) do
    local data = c.pcFilename and jsonReadFile(c.pcFilename)
    if type(data) == "table" and data.format ~= 4 and type(data.parts) == "table" and hasLightbar(data.parts) then
      local parts = {}
      for slot, part in pairs(data.parts) do
        if type(part) == "string" and part ~= "" and (slot:lower():find("lightbar", 1, true) or part:lower():find("lightbar", 1, true)) then
          parts[slot] = part
        end
      end
      local score = tostring(c.key or ""):lower():find("police", 1, true) and 2 or 1
      if not best or score > best.score then best = { score = score, parts = parts } end
    end
  end
  return best and best.parts
end

local function jbeamLightbarParts(model)
  local okIo, jbeamIO = pcall(require, "jbeam/io")
  if not okIo or type(jbeamIO) ~= "table" then return nil end
  local okCtx, ioCtx = pcall(jbeamIO.startLoading, { "/vehicles/" .. model .. "/" })
  if not okCtx or type(ioCtx) ~= "table" then return nil end
  local okParts, available = pcall(jbeamIO.getAvailableParts, ioCtx)
  if not okParts or type(available) ~= "table" then return nil end
  local candidates = {}
  for name in pairs(available) do
    if name:lower():find("lightbar", 1, true) then
      local okPart, part = pcall(jbeamIO.getPart, ioCtx, name)
      if okPart and type(part) == "table" then
        candidates[#candidates + 1] = { name = name, slots = part.slotType or part.slotTypes }
      end
    end
  end
  return lightbar.choose(candidates)
end

local function copConfig(model, configPath)
  if type(configPath) ~= "string" then return configPath end
  local ok, base = pcall(jsonReadFile, "/" .. configPath:gsub("^/", ""))
  if not ok or type(base) ~= "table" or type(base.parts) ~= "table" or base.format == 4 or hasLightbar(base.parts) then return configPath end
  local cfg = deepcopy(base)
  local extra = lightbarParts(model)
  if extra then
    for slot, part in pairs(extra) do cfg.parts[slot] = part end
    return cfg
  end
  local chosen = jbeamLightbarParts(model)
  if chosen and lightbar.apply(cfg.parts, chosen) then return cfg end
  return configPath
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
    local opt = vehicleOptions(a.role == "cop" and copConfig(d.model, d.config) or d.config, a.color)
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
  hudState = hud.new()
  hudResult, hudFlash, hudPrep, hudResetFlashUntil = nil, nil, nil, nil
  hudEvents = {}
  active = true
  role = d.role
  runnerId = d.runnerId
  roundModel, roundColor = d.model, d.color
  roundConfig = d.role == "cop" and copConfig(d.model, d.config) or d.config
  resetAllowed = false
  lastHint = nil
  lastPose = nil
  lockInputs(true)
  setResetKey(false)
  setPartsMenu(d.phase == "prep")
  if not resetIsBound() then
    toast("Bind a reset or recover button to reset during rounds", 10, "cnr_binding")
  end

  local pos, rot
  local resume = d.resumeGeo and geoToGame(d.resumeGeo) or (d.resumePos and vec3(d.resumePos.x, d.resumePos.y, d.resumePos.z))
  if resume then
    pos, rot = nearestRoad(resume)
    if not pos then pos, rot = resume, nil end
  elseif role == "cop" and not d.inPlace then
    local own = ownVehicle()
    local runner = d.runnerGeo and geoToGame(d.runnerGeo) or (d.runnerPos and vec3(d.runnerPos.x, d.runnerPos.y, d.runnerPos.z))
    local center = runner or (own and own:getPosition())
    if center then
      pos, rot = findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, math.max(d.copIndex or 1, 1))
    end
  end
  if role == "cop" and not d.inPlace and not resume and not pos then
    toast("No road found near the runner, you start where you are", 6, "cnr_reset")
  end
  placeVehicle(d.model, roundConfig, pos, rot, d.color)

  local phase = d.phase or "running"
  frozen = phase == "prep" or phase == "countdown" or (phase == "headstart" and role == "cop")
  if phase == "prep" then
    hudPrep = { role = role, car = carName(d.model) }
    if not hudPlaced then
      toast(role == "runner" and 'You are the runner! Change your paint if you like, waiting for "/cnr go"' or 'You are a cop! Change your paint if you like, waiting for "/cnr go"', 8, "cnr_go")
    end
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
  hudPrep = nil
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
    setFlash("GO! RUN!")
    if not hudPlaced then toast("GO! Run!", 4, "cnr_go") end
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

local function onPenalty(data)
  local d = jsonDecode(data) or {}
  if d.aiId then
    local car = aiCars[d.aiId]
    if car then
      setAIFreeze(car, true)
      aiCommand(car, 'ai.setMode("disabled")')
      addEvent(tostring(car.name) .. " crashed: penalty")
      if not hudPlaced then toast(tostring(car.name) .. " crashed: penalty", 3, "cnr_reset") end
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
  setFlash("PENALTY OVER")
  if not hudPlaced then toast("Penalty over, go!", 3, "cnr_go") end
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function compass(from, to)
  local angle = math.deg(math.atan2(to.x - from.x, to.y - from.y)) % 360
  return COMPASS[math.floor((angle + 22.5) / 45) % 8 + 1]
end

local gpsTarget

local function formatDistance(m)
  if m >= 1000 then return string.format("%.1f km", m / 1000) end
  return string.format("%d m", math.floor(m + 0.5))
end

local function clearRoute()
  if core_groundMarkers then pcall(core_groundMarkers.setPath, nil) end
  if gpsTarget then
    local api = earthApi()
    if api and api.gpsClear then pcall(api.gpsClear) end
    gpsTarget = nil
  end
end

local function gpsInfo()
  if not gpsTarget then return nil end
  local api = earthApi()
  local veh = ownVehicle()
  local here = veh and veh:getPosition()
  local target = geoToGame(gpsTarget)
  local dir = (here and target) and (" " .. compass(here, target)) or ""
  local ok, g = pcall(function() return api and api.gps and api.gps() end)
  if ok and type(g) == "table" and type(g.remaining) == "number" and not g.planning then
    return string.format("Runner %s by road%s", formatDistance(g.remaining), dir)
  end
  if here and target then return string.format("Runner %s%s", formatDistance(here:distance(target)), dir) end
  return nil
end

local function onLastSeen(data)
  local d = jsonDecode(data) or {}
  local target = d.geo and geoToGame(d.geo) or (d.pos and vec3(d.pos.x, d.pos.y, d.pos.z))
  if not target then return end
  local api = geoMode and earthApi()
  if api and api.has and api.has("gps") and d.geo then
    local ok = pcall(api.gpsSet, d.geo.lat, d.geo.lon, "Runner last seen")
    if ok then
      gpsTarget = { lat = d.geo.lat, lon = d.geo.lon, h = d.geo.h }
      infoText = gpsInfo()
      if infoText and not hudPlaced then toast(infoText, 4, "cnr_seen") end
      return
    end
  end
  if core_groundMarkers then pcall(core_groundMarkers.setPath, target) end
  local veh = ownVehicle()
  if veh then
    local here = veh:getPosition()
    infoText = string.format("Runner seen %d m %s", math.floor(here:distance(target) + 0.5), compass(here, target))
    if not hudPlaced then toast(infoText, 4, "cnr_seen") end
  end
end

local function onNearestCop(data)
  local d = jsonDecode(data) or {}
  if d.dist then infoText = "Nearest cop " .. formatDistance(d.dist) end
end

local function onMode(data)
  local d = jsonDecode(data) or {}
  geoMode = d.geo == true
  lastPlacesAt, lastPlacesGeo = -math.huge, nil
  if geoMode and not earthApi() then
    toast("Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map", 10, "cnr_mode")
  end
  if d.version and d.version ~= CLIENT_VERSION then
    toast(string.format("Cops and Robbers: your copy is %s, the server runs %s. Rejoin to update.", CLIENT_VERSION, d.version), 10, "cnr_version")
  end
end

local function sendGeo()
  local api = earthApi()
  if not api or (api.rebasing and api.rebasing()) then return end
  local cars = {}
  local function add(obj, id)
    local pos = obj:getPosition()
    local lat, lon, h = gameToGeo(pos)
    if not lat then return end
    local v = obj:getVelocity()
    cars[#cars + 1] = { id = id, lat = lat, lon = lon, h = h, ve = v.x, vn = v.y, vu = v.z }
  end
  local veh = ownVehicle()
  if veh then add(veh, nil) end
  for _, car in pairs(aiCars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then add(obj, car.id) end
  end
  if #cars > 0 then sendServer("cnr_geo", { cars = cars }) end
end

local function geoDistance(a, b)
  local dLat = (a.lat - b.lat) * 111320
  local dLon = (a.lon - b.lon) * 111320 * math.cos(math.rad(a.lat))
  return math.sqrt(dLat * dLat + dLon * dLon)
end

local function lookupStations()
  local api = earthApi()
  if not api or not api.has or not api.has("places") then return end
  local veh = ownVehicle()
  local lat, lon = gameToGeo(veh and veh:getPosition())
  if not lat then return end
  local here = { lat = lat, lon = lon }
  if lastPlacesGeo and clock - lastPlacesAt < PLACES_INTERVAL and geoDistance(here, lastPlacesGeo) < PLACES_MOVE_METERS then return end
  lastPlacesAt, lastPlacesGeo = clock, here
  local level = getCurrentLevelIdentifier()
  api.places(lat, lon, { radius = PLACES_RADIUS, categories = { "gas_station" } }, function(r)
    if type(r) ~= "table" or type(r.places) ~= "table" then return end
    local list = {}
    for _, p in ipairs(r.places) do
      if p.lat and p.lon and p.open ~= "permanently_closed" then
        list[#list + 1] = { lat = p.lat, lon = p.lon, name = p.name }
      end
    end
    if #list > 0 then sendServer("cnr_stations", { map = level, geo = true, stations = list }) end
  end)
end

local function onNotice(data)
  local d = jsonDecode(data) or {}
  if d.about ~= nil and MPConfig and d.about == MPConfig.getPlayerServerID() then return end
  if d.msg then
    addEvent(d.msg)
    if not hudPlaced then toast(d.msg, 4, "cnr_notice") end
  end
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
  if role == "cop" then
    setFlash("GO!")
    if not hudPlaced then toast("GO!", 3, "cnr_go") end
  end
  startStatus()
end
local function layoutsApi()
  return rawget(_G, "ui_appLayouts") or (extensions and extensions.ui_appLayouts)
end

local function refreshUiApps()
  local files = {}
  for _, f in ipairs(HUD_FILES) do files[#files + 1] = { filename = f, type = "added" } end
  pcall(extensions.hook, "onFilesChanged", files)
end

local function placementEnv()
  local api = layoutsApi()
  if not api or not api.getCurrentLayout or not api.addApp or not api.removeApp
    or not api.setCurrentLayout or not api.getAvailableLayouts then
    return nil
  end
  return {
    api = api,
    appExists = FS:fileExists(HUD_FILES[1]),
    readLayout = function(filename)
      local ok, data = pcall(jsonReadFile, filename)
      if ok and type(data) == "table" then
        data.filename = filename
        return data
      end
      return nil
    end,
  }
end

local function placementTick()
  local env = placementEnv()
  if not env then hudPlaced = false return end
  local ok, placed = pcall(placement.tick, placementState, env)
  hudPlaced = ok and placed == true
end

local function placementStart()
  loadedAt = clock
  placement.activate(placementState)
end

local function placementLeave()
  loadedAt = nil
  hudPlaced = false
  local env = placementEnv()
  if env then pcall(placement.leave, placementState, env) end
  placementState.active = false
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
  hud.catchSample(hudState, clock, p)
  if p > 0 and not hudPlaced then
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
  hudState = hud.new()
  hudFlash, hudPrep, hudResetFlashUntil = nil, nil, nil
  hudEvents = {}
  local own = ownVehicle()
  if active and role == "cop" and own then own:queueLuaCommand(LIGHTS_OFF) end
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
  endRound()
  local catchers = (type(d.catchers) == "table" and #d.catchers > 0) and table.concat(d.catchers, ", ") or nil
  hudResult = {
    title = RESULT_TITLES[d.reason] or RESULT_TITLES.cancelled,
    runner = tostring(d.runnerName or ""), time = formatTime(d.survivedSeconds), catchers = catchers,
    untilT = clock + RESULT_SECONDS,
    nextAt = tonumber(d.autoNextSeconds) and (clock + tonumber(d.autoNextSeconds)) or nil,
  }
  if not hudPlaced then showEndToast(d) end
  if d.explode and wasRunner then
    local veh = ownVehicle()
    if veh then veh:queueLuaCommand("fire.explodeVehicle()") end
  end
end

local function onTop(data)
  local d = jsonDecode(data) or {}
  if hudResult and type(d.lines) == "table" then hudResult.top = d.lines end
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
  if active and clock - lastVehiclePatch >= VEHICLE_PATCH_INTERVAL then
    lastVehiclePatch = clock
    local veh = ownVehicle()
    if veh then
      veh:queueLuaCommand(VEHICLE_PATCH)
      if role == "cop" then veh:queueLuaCommand(LIGHTS_ON) end
    end
    for _, car in pairs(aiCars) do
      local obj = car.role == "cop" and car.gameId and getObjectByID(car.gameId)
      if obj then obj:queueLuaCommand(LIGHTS_ON) end
    end
  end
  if geoMode then
    if clock - lastGeoSent >= GEO_SEND_INTERVAL then
      lastGeoSent = clock
      sendGeo()
    end
    lookupStations()
  end
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
    if gpsTarget then infoText = gpsInfo() or infoText end
    if infoText then parts[#parts + 1] = infoText end
    if not hudPlaced then toast(table.concat(parts, "  |  "), 1.5, "cnr_status") end
  end
  local resultShowing = hudResult and clock < hudResult.untilT
  if (active or resultShowing) and clock - lastHudPush >= HUD_PUSH_INTERVAL then
    lastHudPush = clock
    hudVisibleSent = true
    guihooks.trigger("CnRHud", hud.payload(hudState, clock, {
      active = active, role = role, chaseStart = statusActive and chaseStart or nil,
      resetAllowed = resetAllowed, resetHint = lastHint, penalty = penaltyActive, infoText = infoText,
      timer = timerEnd and { label = BANNER_LABELS[timerLabel] or timerLabel, endsAt = timerEnd } or nil,
      flash = hudFlash, prep = hudPrep, events = hudEvents, resetFlashUntil = hudResetFlashUntil,
      result = hudResult,
    }))
  elseif not active and not resultShowing and hudVisibleSent then
    hudVisibleSent = false
    guihooks.trigger("CnRHud", { visible = false })
  end
  if loadedAt and clock - loadedAt >= PLACEMENT_DELAY and clock - lastPlacementCheck >= PLACEMENT_INTERVAL then
    lastPlacementCheck = clock
    placementTick()
  end
  if timerEnd then
    local left = math.ceil(timerEnd - clock)
    if left > 0 and left ~= lastCountdown then
      lastCountdown = left
      if not hudPlaced then toast(string.format("%s %d", timerLabel, left), 1.2, "cnr_go") end
    elseif left <= 0 then
      timerEnd = nil
    end
  end
end

local function onVehicleResetted(gameVid)
  if not active or clock < suppressResetUntil then return end
  if geoMode then
    local veh = ownVehicle()
    if veh and veh:getID() == gameVid then sendServer("cnr_relocated", {}) end
    return
  end
  if not lastPose then return end
  local veh = ownVehicle()
  if not veh or veh:getID() ~= gameVid then return end
  teleport(veh, lastPose.pos, lastPose.rot)
end

local function requestReset(kind)
  if not active then return end
  local veh = ownVehicle()
  if not veh then return end
  if not resetAllowed then
    hudResetFlashUntil = clock + RESET_FLASH_SECONDS
    if not hudPlaced then
      toast(penaltyActive and "No reset during a crash penalty" or (lastHint or "Reset not available"), 3, "cnr_reset")
    end
    return
  end
  resetAllowed = false
  local pos, rot = veh:getPosition(), uprightRotation(veh)
  if kind == "road" and role == "cop" then
    local roadPos, roadRot = nearestRoad(pos)
    if roadPos then
      pos, rot = roadPos, roadRot
    else
      toast("No road found nearby, repaired in place", 4, "cnr_reset")
    end
  end
  teleport(veh, pos, rot)
end

M.requestReset = requestReset

local AI_REPLACE_MIN, AI_REPLACE_MAX = 80, 200

local function onBeamNGEarthRebased(info)
  if not active then return end
  suppressResetUntil = clock + 3
  lastPose = nil
  local purpose = type(info) == "table" and info.purpose or "rebase"
  local own = ownVehicle()
  if purpose ~= "teleport" then
    sendServer("cnr_relocated", {})
    return
  end
  local ids = {}
  local center = own and own:getPosition()
  local index = 0
  for id, car in pairs(aiCars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj and center then
      index = index + 1
      local pos, rot = findCopSpot(center, AI_REPLACE_MIN, AI_REPLACE_MAX, index)
      if pos then
        spawn.safeTeleport(obj, pos, rot)
        if car.frozen then obj:queueLuaCommand("controller.setFreeze(1)") end
        ids[#ids + 1] = id
      end
    end
  end
  if #ids > 0 then sendServer("cnr_relocated", { ids = ids }) end
end

M.onBeamNGEarthRebased = onBeamNGEarthRebased

local ACTIONS_FILE = "/lua/ge/extensions/core/input/actions/copsAndRobbers.json"

local function refreshActions()
  extensions.hook("onFileChanged", ACTIONS_FILE, "modified")
end

function M.command(text)
  if TriggerServerEvent then TriggerServerEvent("cnr_command", tostring(text)) end
end

local function onExtensionLoaded()
  refreshActions()
  refreshUiApps()
  placementStart()
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
    AddEventHandler("cnr_top", onTop)
    AddEventHandler("cnr_mode", onMode)
    AddEventHandler("cnr_lastSeen", onLastSeen)
    AddEventHandler("cnr_nearestCop", onNearestCop)
    AddEventHandler("cnr_penaltyEnd", onPenaltyEnd)
    AddEventHandler("cnr_state", onState)
    AddEventHandler("cnr_roundEnd", onRoundEnd)
    AddEventHandler("cnr_requestStations", onRequestStations)
  end
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = function()
  endRound()
  placementLeave()
  refreshActions()
end
M.onClientEndMission = function()
  endRound()
  placementLeave()
end
M.onBeamMPServerLeave = function()
  endRound()
  placementLeave()
end
M.onWorldReadyState = function(st)
  if st == 2 then placementStart() end
end
M.onUpdate = onUpdate
M.onVehicleResetted = onVehicleResetted

return M
