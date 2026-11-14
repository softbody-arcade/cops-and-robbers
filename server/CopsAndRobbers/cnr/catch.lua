local vec = require("cnr.vec")

local M = {}
local Tracker = {}
Tracker.__index = Tracker

function M.new(cfg)
  return setmetatable({ cfg = cfg, hold = 0, lastNow = nil }, Tracker)
end

function Tracker:reset()
  self.hold = 0
  self.lastNow = nil
end

function Tracker:isHeld(runner, cops)
  if not runner or not runner.pos or not runner.vel then return false end
  if vec.speedKmh(runner.vel) >= self.cfg.catchMaxSpeedKmh then return false end
  for _, cop in ipairs(cops) do
    if cop.pos and vec.dist(runner.pos, cop.pos) <= self.cfg.catchRadiusMeters then return true end
  end
  return false
end

function Tracker:update(now, runner, cops)
  if self:isHeld(runner, cops or {}) then
    if self.lastNow then self.hold = self.hold + (now - self.lastNow) end
    self.lastNow = now
  else
    self:reset()
  end
  local need = self.cfg.catchHoldSeconds
  local caught = self.hold >= need - 1e-9
  return math.min(self.hold / need, 1), caught
end

return M
