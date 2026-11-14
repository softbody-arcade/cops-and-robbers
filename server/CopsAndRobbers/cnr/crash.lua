local vec = require("cnr.vec")

local M = {}
local Detector = {}
Detector.__index = Detector

local WINDOW_SECONDS = 0.5
local CONTACT_RADIUS = 15

function M.atFault(selfCar, others)
  if not selfCar or not selfCar.pos or not selfCar.vel then return true end
  local nearest, nearestDist
  for _, o in ipairs(others or {}) do
    if o and o.pos and o.vel then
      local d = vec.dist(selfCar.pos, o.pos)
      if d <= CONTACT_RADIUS and (not nearestDist or d < nearestDist) then nearest, nearestDist = o, d end
    end
  end
  if not nearest or nearestDist < 1e-6 then return true end
  local dx = (nearest.pos.x - selfCar.pos.x) / nearestDist
  local dy = (nearest.pos.y - selfCar.pos.y) / nearestDist
  local dz = (nearest.pos.z - selfCar.pos.z) / nearestDist
  local selfToward = selfCar.vel.x * dx + selfCar.vel.y * dy + selfCar.vel.z * dz
  local otherToward = -(nearest.vel.x * dx + nearest.vel.y * dy + nearest.vel.z * dz)
  return selfToward >= otherToward
end

function M.new(cfg)
  return setmetatable({ cfg = cfg, history = {} }, Detector)
end

function Detector:reset()
  self.history = {}
end

function Detector:update(now, car)
  if not car or not car.vel then
    self:reset()
    return false
  end
  local speed = vec.speedKmh(car.vel)
  local kept, maxSpeed = {}, speed
  for _, h in ipairs(self.history) do
    if h.t >= now - WINDOW_SECONDS - 1e-9 then
      kept[#kept + 1] = h
      if h.speed > maxSpeed then maxSpeed = h.speed end
    end
  end
  kept[#kept + 1] = { t = now, speed = speed }
  self.history = kept
  if maxSpeed - speed >= self.cfg.crashSpeedLossKmh then
    self:reset()
    return true
  end
  return false
end

return M
