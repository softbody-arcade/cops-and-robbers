local game = require("copsAndRobbers/game")

local M = {}

local HOLD_REASSERT = 0.5
local REPORT_INTERVAL = 1
local LIGHTS_INTERVAL = 1
local SPAWN_CHECK_SECONDS = 15
local LATE_CLEANUP_SECONDS = 15
local FREEZE_ON = "controller.setFreeze(1)"
local FREEZE_OFF = "controller.setFreeze(0)"
local HEADLIGHTS_ON = "electrics.setLightsState(1)"
local OFFICIAL = "BeamNG - Official"
local BAD_WEATHER = { rain = true, storm = true, fog = true, snow = true }
local SPECIAL_WORDS = { "police", "sheriff", "interceptor", "ambulance", "fire", "rescue", "emergency", "taxi" }

local notify = function() end
local running, held = false, false
local count, startedAt, checked = 0, 0, false
local lastHold, lastReport, lastLights = -math.huge, -math.huge, -math.huge
local reportKey
local cleanupUntil = -math.huge
local weather
local roundCars, ownerCar = {}, {}
local hidden = {}

function M.setNotify(fn)
  notify = fn
end

local function contains(text, words)
  local lower = string.lower(tostring(text or ""))
  for _, w in ipairs(words) do
    if lower:find(w, 1, true) then return true end
  end
  return false
end

function M.civilian(info)
  if type(info) ~= "table" then return false end
  if info.Source ~= OFFICIAL then return false end
  if string.lower(tostring(info["Config Type"] or "")) == "police" then return false end
  if contains(info.key, SPECIAL_WORDS) or contains(info.Name, SPECIAL_WORDS) then return false end
  return true
end

local function configIndex()
  local index = {}
  local ok, list = pcall(core_vehicles.getConfigList, true)
  local configs = ok and type(list) == "table" and list.configs or {}
  for _, info in pairs(configs) do
    if type(info) == "table" and info.model_key and info.key then
      index[info.model_key .. "/" .. info.key] = info
    end
  end
  return index
end

local function civilianGroup(n)
  local utils = gameplay_traffic_trafficUtils
  if not utils or not utils.createTrafficGroup then return {} end
  local ok, candidates = pcall(utils.createTrafficGroup, n * 2)
  if not ok or type(candidates) ~= "table" then return {} end
  local index = configIndex()
  local group = {}
  for _, entry in ipairs(candidates) do
    if #group >= n then break end
    if type(entry) == "table" and M.civilian(index[tostring(entry.model) .. "/" .. tostring(entry.config)]) then
      group[#group + 1] = entry
    end
  end
  return group
end

local function trafficCars()
  local list = {}
  local gt = gameplay_traffic
  local data = gt and gt.getTrafficData and gt.getTrafficData() or {}
  for id, entry in pairs(data) do
    if type(entry) == "table" and entry.isAi == true then
      local obj = getObjectByID(id)
      if obj and MPVehicleGE and MPVehicleGE.isOwn(id) then list[#list + 1] = obj end
    end
  end
  return list
end

local function deleteTraffic()
  local gt = gameplay_traffic
  if gt and gt.deleteVehicles then pcall(gt.deleteVehicles) end
end

local function sendAll(cars, cmd)
  for _, obj in ipairs(cars) do obj:queueLuaCommand(cmd) end
end

local function clearTags()
  local vehicles = MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles() or {}
  for key in pairs(hidden) do
    local v = vehicles[key]
    if type(v) == "table" then v.hideNametag = nil end
  end
  hidden = {}
end

local function hideTags()
  if not next(ownerCar) then return end
  local vehicles = MPVehicleGE and MPVehicleGE.getVehicles and MPVehicleGE.getVehicles() or {}
  for key in pairs(hidden) do
    if not M.isTraffic(key) then
      if type(vehicles[key]) == "table" then vehicles[key].hideNametag = nil end
      hidden[key] = nil
    end
  end
  for key, v in pairs(vehicles) do
    if type(v) == "table" and M.isTraffic(key) and not v.hideNametag then
      v.hideNametag = true
      hidden[key] = true
    end
  end
end

function M.setRoundCars(keys)
  roundCars, ownerCar = {}, {}
  for _, key in ipairs(type(keys) == "table" and keys or {}) do
    local owner = type(key) == "string" and key:match("^(%d+)%-")
    if owner then
      roundCars[key] = true
      ownerCar[owner] = key
    end
  end
  if not next(ownerCar) then clearTags() end
end

function M.roundCar(pid)
  if pid == nil then return nil end
  return ownerCar[tostring(pid)]
end

function M.isTraffic(key)
  local owner = type(key) == "string" and key:match("^(%d+)%-")
  return owner ~= nil and ownerCar[owner] ~= nil and not roundCars[key]
end

function M.setWeather(key)
  weather = type(key) == "string" and key or nil
end

function M.start(n, hold, clock)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return end
  local gt = gameplay_traffic
  if not gt or not gt.spawnTraffic then
    notify("Traffic could not spawn", "warn")
    return
  end
  deleteTraffic()
  if gt.setTrafficVars then pcall(gt.setTrafficVars, { aiMode = "traffic", activeAmount = n, enableRandomEvents = false }) end
  local group = civilianGroup(n)
  if #group == 0 then
    notify("Traffic could not spawn", "warn")
    return
  end
  local ok = pcall(gt.spawnTraffic, #group, group)
  if not ok then
    notify("Traffic could not spawn", "warn")
    return
  end
  running, held = true, hold == true
  count, startedAt, checked = n, clock or 0, false
  lastHold, lastReport, lastLights, reportKey = -math.huge, -math.huge, -math.huge, nil
end

function M.release()
  held = false
  if running then sendAll(trafficCars(), FREEZE_OFF) end
end

function M.stop(clock)
  if running then
    deleteTraffic()
    running, held = false, false
    cleanupUntil = (clock or 0) + LATE_CLEANUP_SECONDS
  end
  clearTags()
  roundCars, ownerCar = {}, {}
  weather = nil
end

function M.tick(clock)
  hideTags()
  if not running then
    if clock < cleanupUntil and #trafficCars() > 0 then deleteTraffic() end
    return nil
  end
  local cars
  local function list()
    cars = cars or trafficCars()
    return cars
  end
  if held and clock - lastHold >= HOLD_REASSERT then
    lastHold = clock
    sendAll(list(), FREEZE_ON)
  end
  if BAD_WEATHER[weather] and clock - lastLights >= LIGHTS_INTERVAL then
    lastLights = clock
    sendAll(list(), HEADLIGHTS_ON)
  end
  if not checked and clock >= startedAt + SPAWN_CHECK_SECONDS then
    checked = true
    local n = #list()
    if n == 0 then
      notify("Traffic could not spawn", "warn")
    elseif n < count then
      notify(string.format("Only %d of %d traffic cars spawned", n, count), "warn")
    end
  end
  if clock - lastReport < REPORT_INTERVAL then return nil end
  lastReport = clock
  local vids = {}
  for _, obj in ipairs(list()) do
    local vid = game.serverVid(obj)
    if vid then vids[#vids + 1] = vid end
  end
  table.sort(vids)
  local key = table.concat(vids, ",")
  if key == reportKey then return nil end
  reportKey = key
  return vids
end

return M
