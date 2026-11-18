local game = require("copsAndRobbers/game")

local M = {}

local parked, restoring
local hitchWait = 0
local HITCH_SETTLE_SECONDS, HITCH_TIMEOUT_SECONDS = 0.2, 10
local HITCH_RETRY_SECONDS = 0.5
local ATTACH_HITCH = [[
local c = beamstate.couplerCache[%d]
if c and c.couplerTag == %q and obj:getNodeLatch(c.cid) <= 0 and obj:getNodeCoupler(c.cid) <= 0 then
  obj:attachExternalCoupler(c.cid, %d, %d, c.couplerStrength or 1000000, c.couplerRadius or 0.2,
    c.couplerLockRadius or 0.025, c.couplerLatchSpeed or 0.3, c.couplerTargets or 0)
end
]]

local function isTraffic(id)
  local gt = gameplay_traffic
  local data = gt and gt.getTrafficData and gt.getTrafficData() or {}
  local entry = data[id]
  return type(entry) == "table" and entry.isAi == true
end

local function ownCars(aiCars)
  local list, seen = {}, {}
  for _, car in ipairs(aiCars or {}) do seen[car.obj:getID()] = true end
  local parking = gameplay_parking
  local parkedCars = parking and parking.getParkedCarsData and parking.getParkedCarsData() or {}
  local function add(veh)
    local id = veh and veh:getID()
    if id and not seen[id] and not parkedCars[id] and not isTraffic(id)
      and veh.vehicleGroup ~= "autoParking" and veh.vehicleGroup ~= "autoTraffic" then
      seen[id] = true
      list[#list + 1] = veh
    end
  end
  local seated = game.ownVehicle()
  if seated then add(getObjectByID(seated:getID())) end
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

function M.removeExtras(roundId, aiCars)
  for _, car in ipairs(ownCars(aiCars)) do
    if car:getID() ~= roundId then car:delete() end
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
        byId[b].hitch = {
          tow = byId[a], towNode = nodeA, trailerNode = nodeB, tag = tag
        }
        for _, id in ipairs({a, b}) do
          local veh = getObjectByID(id)
          byId[id].safeSpawn = false
          byId[id].rot = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())
        end
      end
    end
  end
end

local function rigRegistered(id, visited)
  if visited[id] then return true end
  visited[id] = true
  if not MPVehicleGE.getVehicleByGameID(id) then return false end
  for _, pair in ipairs(core_vehicles.attachedCouplers or {}) do
    local peer = pair[1] == id and pair[2] or pair[2] == id and pair[1]
    if peer and not rigRegistered(peer, visited) then return false end
  end
  return true
end

function M.park(aiCars)
  if not parked then
    restoring = nil
    parked = {}
  end
  local cars = ownCars(aiCars)
  for i = #cars, 1, -1 do
    if not rigRegistered(cars[i]:getID(), {}) then table.remove(cars, i) end
  end
  if #cars == 0 then return end
  local cmds = rawget(_G, "commands")
  if cars[1] == game.ownVehicle() and cmds and cmds.setFreeCamera then cmds.setFreeCamera() end
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
    local ok, veh = pcall(core_vehicles.spawnNewVehicle, car.model, {
      config = car.config, pos = car.pos, rot = car.rot, safeSpawn = car.safeSpawn, autoEnterVehicle = i == 1
    })
    if ok and veh then
      car.id = veh:getID()
      car.couplerCache = core_vehicles.vehsCouplerCache and core_vehicles.vehsCouplerCache[car.id]
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

local function hitchStatus(tow, towNode, trailer, trailerNode)
  local occupied = false
  for _, pair in ipairs(core_vehicles.attachedCouplers or {}) do
    local a, b, nodeA, nodeB = pair[1], pair[2], pair[3], pair[4]
    if a == trailer or b == tow then a, b, nodeA, nodeB = b, a, nodeB, nodeA end
    if a == tow and b == trailer and nodeA == towNode and nodeB == trailerNode then return "attached" end
    if (a == tow and b == trailer) or (a == tow and nodeA == towNode) or (b == trailer and nodeB == trailerNode) then
      occupied = true
    end
  end
  if occupied then return "occupied" end
end

local function alignHitch(tow, trailer, hitch, lockRadius)
  local ball = tow:getPosition() + tow:getNodePosition(hitch.towNode)
  local pos = ball - trailer:getNodePosition(hitch.trailerNode)
  if pos:distance(trailer:getPosition()) > lockRadius then
    trailer:setClusterPosRelRot(-1, pos.x, pos.y, pos.z, 0, 0, 0, 1)
  end
end

local function updateHitch(car, expired)
  local hitch, tow = car.hitch, car.hitch.tow
  local vehicle = tow.id and getObjectByID(tow.id)
  local trailer = car.id and getObjectByID(car.id)
  if not (vehicle and trailer) then return true end
  local caches = core_vehicles.vehsCouplerCache
  if caches[tow.id] ~= tow.couplerCache or caches[car.id] ~= car.couplerCache then return true end
  local status = hitchStatus(tow.id, hitch.towNode, car.id, hitch.trailerNode)
  if status == "attached" then return true end
  if expired then
    log("W", "cnr_spectate", "timed out restoring trailer hitch between " .. tow.id .. " and " .. car.id)
    return true
  end
  if not (tow.couplerCache and car.couplerCache) or status == "occupied" or tow.hitch then return false end
  if not (MPVehicleGE.isOwn(tow.id) and MPVehicleGE.isOwn(car.id)) then return false end
  if not hitch.placed then
    local ball = tow.couplerCache[hitch.towNode]
    local socket = car.couplerCache[hitch.trailerNode]
    if not (ball and ball.couplerTag == hitch.tag and socket and socket.tag == hitch.tag) then
      log("W", "cnr_spectate", "missing saved coupler node on restored rig " .. tow.id .. " and " .. car.id)
      return true
    end
    local ok, err = pcall(alignHitch, vehicle, trailer, hitch, ball.couplerLockRadius or 0.025)
    if not ok then
      log("W", "cnr_spectate", "could not place parked trailer " .. car.id .. ": " .. tostring(err))
      return true
    end
    hitch.placed = true
    if core_vehicles.couplerTagsOptions[hitch.tag] == "autoCouple" then
      hitch.nextAttach = hitchWait + HITCH_RETRY_SECONDS
    end
  elseif hitch.nextAttach and hitchWait >= hitch.nextAttach then
    local cmd = string.format(ATTACH_HITCH, hitch.towNode, hitch.tag, car.id, hitch.trailerNode)
    local ok, err = pcall(vehicle.queueLuaCommand, vehicle, cmd)
    if not ok then
      log("W", "cnr_spectate", "could not couple parked trailer " .. car.id .. ": " .. tostring(err))
      return true
    end
    hitch.nextAttach = hitchWait + HITCH_RETRY_SECONDS
  end
  return false
end

function M.updateHitches(dt)
  if not restoring then return end
  hitchWait = hitchWait + dt
  if hitchWait < HITCH_SETTLE_SECONDS then return end
  local pending = false
  for _, car in ipairs(restoring) do
    if car.hitch then
      if updateHitch(car, hitchWait >= HITCH_TIMEOUT_SECONDS) then
        car.hitch = nil
      else
        pending = true
      end
    end
  end
  if not pending then restoring = nil end
end

local function restoringCar(id)
  if not restoring then return end
  for _, car in ipairs(restoring) do
    if car.id == id then return car end
  end
end

function M.vehicleSpawned(id)
  local car = restoringCar(id)
  if car and not car.couplerCache then car.couplerCache = core_vehicles.vehsCouplerCache[id] end
end

function M.forgetVehicle(id)
  local car = restoringCar(id)
  if car then car.id = nil end
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
