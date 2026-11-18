local game = require("copsAndRobbers/game")

local M = {}

local parked, restoring
local hitchWait = 0
local HITCH_SETTLE_SECONDS, HITCH_TIMEOUT_SECONDS = 0.2, 10

local function isTraffic(id)
  local gt = gameplay_traffic
  local data = gt and gt.getTrafficData and gt.getTrafficData() or {}
  local entry = data[id]
  return type(entry) == "table" and entry.isAi == true
end

local function ownCars()
  local list, seen = {}, {}
  local parking = gameplay_parking
  local parkedCars = parking and parking.getParkedCarsData and parking.getParkedCarsData() or {}
  local function add(veh)
    local id = veh and veh:getID()
    if id and not parkedCars[id] and not seen[id] and not isTraffic(id) then
      seen[id] = true
      list[#list + 1] = veh
    end
  end
  add(game.ownVehicle())
  local own = MPVehicleGE and MPVehicleGE.getOwnMap and MPVehicleGE.getOwnMap() or {}
  local ids = {}
  for id in pairs(own) do
    local n = tonumber(id)
    if n then ids[#ids + 1] = n end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do add(getObjectByID(id)) end
  return list
end

function M.personalCar()
  for _, car in ipairs(ownCars()) do
    if car:getJBeamFilename() ~= "unicycle" then return car end
  end
end

local function snapshot(veh)
  local data = core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(veh:getID())
  local config = type(data) == "table" and type(data.config) == "table" and deepcopy(data.config) or nil
  if config and type(config.partsTree) == "table" and core_vehicle_partmgmt and core_vehicle_partmgmt.partsTreeToPartsMap then
    config.parts = core_vehicle_partmgmt.partsTreeToPartsMap(config.partsTree)
    config.partsTree = nil
  end
  local helpers = rawget(_G, "MPHelpers")
  if config and helpers and helpers.getColorsFromVehObj then
    local ok, paints = pcall(helpers.getColorsFromVehObj, veh)
    if ok and type(paints) == "table" then config.paints = paints end
  end
  local p, d = veh:getPosition(), veh:getDirectionVector()
  return { model = veh:getJBeamFilename(), config = config, pos = vec3(p.x, p.y, p.z), dir = vec3(d.x, d.y, 0), rot = game.uprightRotation(veh) }
end

local function saveHitches(byId)
  local vehicles = core_vehicles
  for _, pair in ipairs(vehicles and vehicles.attachedCouplers or {}) do
    local a, b, nodeA, nodeB = pair[1], pair[2], pair[3], pair[4]
    if a ~= b and byId[a] and byId[b] then
      local tags, offsets = vehicles.vehsCouplerTags, vehicles.vehsCouplerOffset
      local tag = tags[a] and tags[a][nodeA]
      if not tag then
        a, b, nodeA, nodeB = b, a, nodeB, nodeA
        tag = tags[a] and tags[a][nodeA]
      end
      if vehicles.couplerTagsOptions[tag] and offsets[a] and offsets[a][nodeA] and offsets[b] and offsets[b][nodeB] then
        byId[b].hitch = { tow = byId[a], ball = offsets[a][nodeA], socket = offsets[b][nodeB], tag = tag }
      end
    end
  end
end

function M.park()
  if parked then return end
  restoring = nil
  parked = {}
  local cars = ownCars()
  if #cars == 0 then return end
  local cmds = rawget(_G, "commands")
  if game.ownVehicle() and cmds and cmds.setFreeCamera then cmds.setFreeCamera() end
  local byId = {}
  for _, veh in ipairs(cars) do
    if veh:getJBeamFilename() ~= "unicycle" then
      local car = snapshot(veh)
      parked[#parked + 1] = car
      byId[veh:getID()] = car
    end
  end
  saveHitches(byId)
  for _, veh in ipairs(cars) do veh:delete() end
end

function M.restore()
  local list = parked
  parked = nil
  if not list or #list == 0 or not core_vehicles then return true end
  local allBack = true
  for i, car in ipairs(list) do
    local ok, veh = pcall(core_vehicles.spawnNewVehicle, car.model, { config = car.config, pos = car.pos, rot = car.rot, autoEnterVehicle = i == 1 })
    if ok and veh then
      car.id = veh:getID()
      if car.hitch then restoring, hitchWait = list, 0 end
    else
      allBack = false
    end
  end
  if not allBack and log then log("W", "cnr_spectate", "a parked car could not be put back") end
  local cmds = rawget(_G, "commands")
  if cmds and cmds.isFreeCamera and cmds.isFreeCamera() and cmds.setGameCamera then cmds.setGameCamera() end
  return allBack
end

function M.updateHitches(dt)
  if not restoring then return end
  hitchWait = hitchWait + dt
  if hitchWait < HITCH_SETTLE_SECONDS then return end
  local coupled = core_vehicles.vehsCouplings or {}
  local pending = false
  for _, car in ipairs(restoring) do
    local hitch = car.hitch
    if hitch then
      local tow = hitch.tow
      if not (car.id and tow.id and getObjectByID(car.id) and getObjectByID(tow.id)) then
        car.hitch = nil
      elseif not tow.hitch and MPVehicleGE.isOwn(tow.id) and MPVehicleGE.isOwn(car.id) then
        if not (coupled[tow.id] and coupled[tow.id][car.id]) then
          spawn.placeTrailer(tow.id, hitch.ball, car.id, hitch.socket, hitch.tag)
        end
        car.hitch = nil
      else
        pending = true
      end
    end
  end
  if not pending then
    restoring = nil
  elseif hitchWait >= HITCH_TIMEOUT_SECONDS then
    log("W", "cnr_spectate", "timed out restoring a parked trailer hitch")
    restoring = nil
  end
end

function M.drop()
  parked, restoring = nil, nil
end

function M.parked()
  return parked ~= nil
end

function M.spot()
  local first = parked and parked[1]
  if not first then return nil end
  return first.pos, first.dir
end

function M.carIds(owners, vehicles, exists)
  local ids = {}
  for _, key in pairs(owners or {}) do
    local v = vehicles and vehicles[key]
    local id = type(v) == "table" and not v.isDeleted and v.isSpawned ~= false and tonumber(v.gameVehicleID)
    if id and exists(id) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

function M.cycleTarget(ids, fromId, toId, dir)
  local n = #ids
  if n == 0 then return nil end
  for _, id in ipairs(ids) do
    if id == toId then return nil end
  end
  local step = (tonumber(dir) or 1) < 0 and -1 or 1
  for i, id in ipairs(ids) do
    if id == fromId then return ids[(i - 1 + step) % n + 1] end
  end
  return step > 0 and ids[1] or ids[n]
end

function M.watchedName(localName)
  local cmds = rawget(_G, "commands")
  if cmds and cmds.isFreeCamera and cmds.isFreeCamera() then return nil end
  local veh = getPlayerVehicle(0)
  local own = veh and localName and localName(veh:getID())
  if own then return own end
  if not veh or not MPVehicleGE or not MPVehicleGE.getVehicleByGameID then return nil end
  local v = MPVehicleGE.getVehicleByGameID(veh:getID())
  if type(v) ~= "table" then return nil end
  if type(v.ownerName) == "string" and v.ownerName ~= "" then return v.ownerName end
  local owner = type(v.serverVehicleString) == "string" and tonumber(v.serverVehicleString:match("^(%d+)%-"))
  local players = MPVehicleGE.getPlayers and MPVehicleGE.getPlayers() or {}
  local p = owner and (players[owner] or players[tostring(owner)])
  return type(p) == "table" and type(p.name) == "string" and p.name or nil
end

return M
