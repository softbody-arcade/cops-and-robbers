local vec = require("cnr.vec")

local M = {}
local Tracker = {}
Tracker.__index = Tracker

local DRAIN_FACTOR = 2
local STUCK_WINDOW_SECONDS = 4
local STUCK_METERS = 3
local ROCK_FACTOR = 1.5

function M.new(cfg)
  return setmetatable({ cfg = cfg, hold = 0, lastNow = nil, history = {} }, Tracker)
end

function Tracker:reset()
  self.hold = 0
  self.lastNow = nil
  self.history = {}
end

function Tracker:stuck(now, runner)
  local history = self.history
  if not runner or not runner.pos then return false end
  history[#history + 1] = { t = now, pos = runner.pos }
  while #history >= 2 and now - history[2].t >= STUCK_WINDOW_SECONDS - 1e-9 do table.remove(history, 1) end
  local oldest = history[1]
  if now - oldest.t < STUCK_WINDOW_SECONDS - 1e-9 then return false end
  local net = vec.dist(runner.pos, oldest.pos)
  if net >= STUCK_METERS then return false end
  local path = 0
  for i = 2, #history do path = path + vec.dist(history[i].pos, history[i - 1].pos) end
  return path >= ROCK_FACTOR * net
end

function Tracker:isHeld(runner, cops, stuck)
  if not runner or not runner.pos or not runner.vel then return false end
  if vec.speedKmh(runner.vel) >= self.cfg.catchMaxSpeedKmh and not stuck then return false end
  for _, cop in ipairs(cops) do
    if cop.pos and vec.dist(runner.pos, cop.pos) <= self.cfg.catchRadiusMeters then return true end
  end
  return false
end

function Tracker:update(now, runner, cops)
  local dt = self.lastNow and (now - self.lastNow) or 0
  self.lastNow = now
  local stuck = self:stuck(now, runner)
  if self:isHeld(runner, cops or {}, stuck) then
    self.hold = self.hold + dt
  else
    self.hold = math.max(0, self.hold - DRAIN_FACTOR * dt)
  end
  local need = self.cfg.catchHoldSeconds
  local caught = self.hold >= need - 1e-9
  return math.min(self.hold / need, 1), caught
end

return M
