local ai = require("copsAndRobbers/ai")
local conditions = require("copsAndRobbers/sightConditions")
local game = require("copsAndRobbers/game")
local sight = require("copsAndRobbers/sight")
local streetLights = require("copsAndRobbers/streetLights")
local visibility = require("copsAndRobbers/visibility")

local M = {}
local INTERVAL = 0.25
local HUMAN = "human"

local maximum, human, aiCops, aiRunner
local observers = {}
local lastSample = -math.huge
local lastTarget

function M.configure(meters, humanCop, roster)
  human, aiCops, aiRunner = humanCop, false, false
  for _, slot in ipairs(roster or {}) do
    if slot.role == "cop" then aiCops = true end
    if slot.role == "runner" then aiRunner = true end
  end
  maximum = meters and meters > 0 and meters < math.huge and (human or aiCops) and meters or nil
  observers, lastTarget, lastSample = {}, nil, -math.huge
  if maximum then streetLights.beginMissionIndex() end
end

function M.replaced(role)
  if role == "runner" then
    for _, state in pairs(observers) do state.seen = nil end
  elseif role == "cop" then
    observers[HUMAN] = nil
  end
end

function M.leaveMission()
  streetLights.clear()
  conditions.reset()
end

local function observe(id, instance, clock, seen, distance)
  local state = observers[id]
  if not state or state.instance ~= instance then
    state = sight.new()
    state.instance = instance
    observers[id] = state
  end
  local changed = state.seen ~= seen
  if sight.step(state, clock, seen) then
    local report = { seen = seen }
    if id ~= HUMAN then report.aiId, report.instance = id, instance end
    game.sendServer("cnr_sight", report)
    if changed and log then
      log("I", "cnr_sight", string.format("cop %s: runner %s (%s m)", tostring(id),
        seen and "in sight" or "out of sight", distance and string.format("%.0f", distance) or "?"))
    end
  end
end

function M.update(clock, running, roundVehicle, humanRunner)
  if not maximum then return end
  streetLights.advance()
  if not running or clock - lastSample < INTERVAL then return end
  lastSample = clock

  local cars, runner, targetId = {}
  if human then cars[HUMAN] = { obj = roundVehicle() } end
  if aiCops or aiRunner then
    for _, car in ipairs(ai.objects()) do
      if car.reported then
        if car.role == "cop" then
          cars[car.id] = car
        elseif car.role == "runner" then
          runner, targetId = car.obj, car.instance
        end
      end
    end
  end
  if not aiRunner then
    runner = humanRunner()
    targetId = runner and runner:getID()
  end
  if targetId ~= lastTarget then
    for _, state in pairs(observers) do state.seen = nil end
    lastTarget = targetId
  end

  local target = sight.position(runner)
  local center = target and sight.targetCenter(target)
  local day, lamps, fog, precipitation, street, runnerHeading
  for id, car in pairs(cars) do
    local seen, distance = false, nil
    local origin = center and sight.position(car.obj)
    if origin then distance = sight.distance(origin, center) end
    if distance and distance <= maximum then
      if day == nil then
        day, lamps, fog, precipitation = conditions.sample(runner)
        street = day < 1 and streetLights.strength(center, castRayStatic) or 0
        runnerHeading = sight.heading(runner)
      end
      local gaze, forward = sight.lookDirection(car.obj, id == HUMAN)
      local delta = target - origin
      local range = visibility.range(maximum, visibility.bearing(gaze, delta), visibility.bearing(forward, delta),
        day, lamps, street, fog, precipitation)
      seen = sight.visible(origin, target, runnerHeading, range, castRayStatic)
    end
    observe(id, car.instance, clock, seen, distance)
  end
  for id, state in pairs(observers) do
    if not cars[id] then
      observe(id, state.instance, clock, false)
      observers[id] = nil
    end
  end
end

return M
