local vec = require("cnr.vec")

local M = {}
local Detector = {}
Detector.__index = Detector

local WINDOW_SECONDS = 0.5

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
