local game = require("copsAndRobbers/game")
local roads = require("copsAndRobbers/roads")
local vehicles = require("copsAndRobbers/vehicles")

local M = {}

local FREEZE_REASSERT = 0.5
local LIGHTS_ON = "electrics.set_lightbar_signal(1)"
local REPLACE_MIN, REPLACE_MAX = 80, 200

local cars = {}

local function command(car, cmd)
  local obj = car.gameId and getObjectByID(car.gameId)
  if obj then obj:queueLuaCommand(cmd) end
end

local function setFreeze(car, on)
  car.frozen = on
  command(car, "controller.setFreeze(" .. (on and 1 or 0) .. ")")
end

local function runnerGameId()
  for _, car in pairs(cars) do
    if car.role == "runner" then return car.gameId end
  end
  local veh = getPlayerVehicle(0)
  return veh and veh:getID()
end

local function startChase(car)
  local target = runnerGameId()
  if not target then return end
  command(car, "ai.setTargetObjectID(" .. target .. ")")
  command(car, 'ai.setMode("chase")')
end

local function startFlee(car)
  local veh = getPlayerVehicle(0)
  if veh then command(car, "ai.setTargetObjectID(" .. veh:getID() .. ")") end
  command(car, 'ai.setMode("flee")')
end

function M.remove()
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      obj:queueLuaCommand('ai.setMode("disabled")')
      obj:delete()
    end
  end
  cars = {}
end

local function spawnCar(model, config, a, pos, rot)
  local opt = vehicles.options(a.role == "cop" and vehicles.copConfig(model, config) or config, a.color)
  opt.autoEnterVehicle = false
  opt.pos, opt.rot = pos, rot
  local veh = core_vehicles.spawnNewVehicle(model, opt)
  if not veh then game.toast("Could not spawn " .. tostring(a.name) .. ", is MaxCars high enough?", 6, "cnr_reset") end
  return veh
end

function M.setup(d)
  M.remove()
  local own = game.ownVehicle()
  local center = own and own:getPosition()
  for _, a in ipairs(d.ai or {}) do
    local pos, rot
    if center then pos, rot = roads.findCopSpot(center, d.copSpawnMin or 50, d.copSpawnMax or 150, a.index or 1) end
    local veh = spawnCar(d.model, d.config, a, pos, rot)
    if veh then
      cars[a.id] = { id = a.id, role = a.role, name = a.name, color = a.color, gameId = veh:getID(), frozen = true, reported = false }
    end
  end
end

function M.rebuild(model, config)
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      local pos, rot = obj:getPosition(), game.uprightRotation(obj)
      obj:queueLuaCommand('ai.setMode("disabled")')
      obj:delete()
      local veh = spawnCar(model, config, car, pos, rot)
      car.gameId = veh and veh:getID()
      car.reported, car.lastFreeze = false, nil
    end
  end
end

function M.releaseRunner()
  for _, car in pairs(cars) do
    if car.role == "runner" then
      setFreeze(car, false)
      startFlee(car)
    end
  end
end

function M.releaseCops()
  for _, car in pairs(cars) do
    if car.role == "cop" then
      setFreeze(car, false)
      startChase(car)
    end
  end
end

function M.penalty(id)
  local car = cars[id]
  if not car then return end
  setFreeze(car, true)
  command(car, 'ai.setMode("disabled")')
end

function M.penaltyEnd(id)
  local car = cars[id]
  if not car then return end
  setFreeze(car, false)
  startChase(car)
end

function M.tick(clock)
  local report = {}
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      if not car.reported then
        local vid = game.serverVid(obj)
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
  return report
end

function M.lightsOn()
  for _, car in pairs(cars) do
    local obj = car.role == "cop" and car.gameId and getObjectByID(car.gameId)
    if obj then obj:queueLuaCommand(LIGHTS_ON) end
  end
end

function M.runnerObject()
  for _, car in pairs(cars) do
    if car.role == "runner" then return car.gameId and getObjectByID(car.gameId) end
  end
  return nil
end

function M.objects()
  local list = {}
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then list[#list + 1] = { id = car.id, obj = obj } end
  end
  return list
end

function M.relocate(center)
  local ids, index = {}, 0
  if not center then return ids end
  for id, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      index = index + 1
      local pos, rot = roads.findCopSpot(center, REPLACE_MIN, REPLACE_MAX, index)
      if pos then
        spawn.safeTeleport(obj, pos, rot)
        if car.frozen then obj:queueLuaCommand("controller.setFreeze(1)") end
        ids[#ids + 1] = id
      end
    end
  end
  return ids
end

return M
