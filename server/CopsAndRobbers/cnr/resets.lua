local vec = require("cnr.vec")

local M = {}
local Tracker = {}
Tracker.__index = Tracker

local GRACE_SECONDS = 1.5

function M.atStation(pos, stations, cfg)
  for _, s in ipairs(stations or {}) do
    local radius = math.max(cfg.gasStationRadiusMeters, (s.r or 0) + 10)
    if vec.dist(pos, s) <= radius then return true end
  end
  return false
end

function M.new(cfg)
  return setmetatable({ cfg = cfg, stillSince = nil, lastAllowedAt = nil }, Tracker)
end

function Tracker:evaluate(now, car, ctx)
  local cfg = self.cfg
  if not car or not car.pos or not car.vel then
    self.stillSince = nil
    return false, "Stop to reset"
  end
  if ctx.role == "cop" and ctx.runnerPos and vec.dist(car.pos, ctx.runnerPos) >= cfg.copResetMinDistanceMeters then
    return true, "Reset available (far from runner)"
  end
  if vec.speedKmh(car.vel) >= cfg.stillMaxSpeedKmh then
    self.stillSince = nil
    return false, "Stop to reset"
  end
  self.stillSince = self.stillSince or now
  if M.atStation(car.pos, ctx.stations, cfg) then
    return true, "Reset available (gas station)"
  end
  local remaining = cfg.resetWaitSeconds - (now - self.stillSince)
  if remaining <= 1e-9 then
    return true, "Reset available"
  end
  return false, string.format("Stay still %ds to reset", math.ceil(remaining - 1e-9))
end

function Tracker:update(now, car, ctx)
  local allowed, hint = self:evaluate(now, car, ctx)
  if allowed then self.lastAllowedAt = now end
  return allowed, hint
end

function Tracker:consume(now)
  local legal = self.lastAllowedAt ~= nil and now - self.lastAllowedAt <= GRACE_SECONDS
  self.lastAllowedAt = nil
  self.stillSince = nil
  return legal
end

return M
