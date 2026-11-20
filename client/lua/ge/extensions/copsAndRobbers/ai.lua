local startGrid = require("copsAndRobbers/startGrid")
local game = require("copsAndRobbers/game")
local roads = require("copsAndRobbers/roads")
local vehicles = require("copsAndRobbers/vehicles")

local M = {}

local FREEZE_REASSERT = 0.5
local LIGHTS_ON = "electrics.set_lightbar_signal(1)"
local HEADLIGHTS_ON = "electrics.setLightsState(1)"
local HEADLIGHTS_OFF = "electrics.setLightsState(0)"
local FLEE_CHECK = 1
local HOLD_INPUTS = "if input and input.setAllowedInputSource then for _, t in ipairs({ 'steering', 'throttle', 'brake', 'parkingbrake', 'clutch' }) do input.setAllowedInputSource(t, 'ai', true) input.setAllowedInputSource(t, 'local', false) end end"

local cars = {}
local lastInstance = 0
local aiOnly = false
local notify = function() end

function M.setNotify(fn)
  notify = fn
end

local function command(car, cmd)
  local obj = car.gameId and getObjectByID(car.gameId)
  if obj then obj:queueLuaCommand(cmd) end
end

local function setFreeze(car, on)
  car.frozen = on
  command(car, "controller.setFreeze(" .. (on and 1 or 0) .. ")")
end

local function runnerGameId(humanRunnerId)
  for _, car in pairs(cars) do
    if car.role == "runner" then return car.gameId end
  end
  return humanRunnerId
end

local function startChase(car, humanRunnerId)
  local target = runnerGameId(humanRunnerId)
  if not target then return end
  command(car, "ai.setTargetObjectID(" .. target .. ")")
  command(car, 'ai.setMode("chase")')
end

local function positionOf(car)
  local obj = car.gameId and getObjectByID(car.gameId)
  return obj and obj:getPosition()
end

local function nearestCop(runner)
  local here = positionOf(runner)
  if not here then return nil end
  local best, bestDist, held, heldDist
  for _, car in pairs(cars) do
    local at = car.role == "cop" and positionOf(car)
    local d = at and at:distance(here)
    if d and (not heldDist or d < heldDist) then held, heldDist = car.gameId, d end
    if d and not car.frozen and (not bestDist or d < bestDist) then best, bestDist = car.gameId, d end
  end
  return best or held
end

local function fleeFrom(car, target)
  if not target or target == car.fleeFrom then return end
  car.fleeFrom = target
  command(car, "ai.setTargetObjectID(" .. target .. ")")
end

local function startFlee(car)
  if aiOnly then
    car.fleeing = true
    fleeFrom(car, nearestCop(car))
  else
    local veh = getPlayerVehicle(0)
    if veh then command(car, "ai.setTargetObjectID(" .. veh:getID() .. ")") end
  end
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
  aiOnly = false
end

local function spawnCar(model, config, a, pos, rot)
  local opt = vehicles.options(a.role == "cop" and vehicles.copConfig(model, config) or config, a.color)
  opt.autoEnterVehicle = false
  opt.pos, opt.rot = pos, rot
  local veh = core_vehicles.spawnNewVehicle(model, opt)
  if not veh then
    notify("Could not spawn " .. tostring(a.name) .. ", is MaxCars high enough?", "warn")
    return nil
  end
  if aiOnly then veh:queueLuaCommand(HOLD_INPUTS) end
  lastInstance = lastInstance + 1
  return veh, lastInstance
end

function M.setup(d, center, heading)
  M.remove()
  aiOnly = d.aiOnly == true
  if not center then
    local own = game.ownVehicle()
    center = own and own:getPosition()
    heading = own and own:getDirectionVector()
  end
  local copCenter, copIndex = center, 0
  for _, a in ipairs(d.ai or {}) do
    local pos, rot
    if a.startPose ~= nil then
      pos, rot = startGrid.pose(a.startPose)
    elseif center and aiOnly and a.role == "runner" then
      local runnerHeading
      pos, rot, runnerHeading = roads.nearestRoad(center, heading, true)
      heading = runnerHeading or heading
      copCenter = pos or center
    elseif center then
      copIndex = copIndex + 1
      pos, rot = roads.findCopSpot(copCenter, d.copSpawnMin or 50, d.copSpawnMax or 150, aiOnly and copIndex or a.index or 1, heading)
    end
    local veh, instance = spawnCar(d.model, d.config, a, pos, rot)
    if veh then
      cars[a.id] = { id = a.id, role = a.role, name = a.name, color = a.color,
        gameId = veh:getID(), instance = instance, frozen = true, reported = false }
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
      local veh, instance = spawnCar(model, config, car, pos, rot)
      car.gameId, car.instance = veh and veh:getID(), instance
      car.reported, car.lastFreeze = false, nil
    end
  end
end

function M.holdInputs()
  if not aiOnly then return end
  for _, car in pairs(cars) do command(car, HOLD_INPUTS) end
end

function M.releaseRunner()
  for _, car in pairs(cars) do
    if car.role == "runner" then
      setFreeze(car, false)
      startFlee(car)
    end
  end
end

function M.releaseCops(humanRunnerId)
  for _, car in pairs(cars) do
    if car.role == "cop" then
      setFreeze(car, false)
      startChase(car, humanRunnerId)
    end
  end
end

function M.penalty(id)
  local car = cars[id]
  if not car then return end
  setFreeze(car, true)
  command(car, 'ai.setMode("disabled")')
end

function M.penaltyEnd(id, humanRunnerId)
  local car = cars[id]
  if not car then return end
  setFreeze(car, false)
  startChase(car, humanRunnerId)
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
          report[#report + 1] = { id = car.id, vid = vid, instance = car.instance }
        end
      end
      if car.frozen and clock - (car.lastFreeze or 0) >= FREEZE_REASSERT then
        car.lastFreeze = clock
        obj:queueLuaCommand("controller.setFreeze(1)")
      end
      if car.fleeing and clock - (car.fleeCheckedAt or -math.huge) >= FLEE_CHECK then
        car.fleeCheckedAt = clock
        fleeFrom(car, nearestCop(car))
      end
    end
  end
  return report
end

function M.lightsOn(headlights)
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then
      if car.role == "cop" then obj:queueLuaCommand(LIGHTS_ON) end
      if headlights then
        obj:queueLuaCommand(HEADLIGHTS_ON)
        car.headlights = true
      elseif car.headlights then
        obj:queueLuaCommand(HEADLIGHTS_OFF)
        car.headlights = nil
      end
    end
  end
end

function M.runnerObject()
  for _, car in pairs(cars) do
    if car.role == "runner" then return car.gameId and getObjectByID(car.gameId) end
  end
  return nil
end

function M.destroyed(gameId)
  for _, car in pairs(cars) do
    if car.gameId == gameId then car.gameId = nil end
  end
end

function M.nameOf(gameId)
  for _, car in pairs(cars) do
    if gameId ~= nil and car.gameId == gameId then return car.name end
  end
  return nil
end

function M.objects()
  local list = {}
  for _, car in pairs(cars) do
    local obj = car.gameId and getObjectByID(car.gameId)
    if obj then list[#list + 1] = { id = car.id, obj = obj, role = car.role, instance = car.instance, reported = car.reported } end
  end
  return list
end

return M
