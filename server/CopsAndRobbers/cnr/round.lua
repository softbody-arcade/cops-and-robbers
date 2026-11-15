local catch = require("cnr.catch")
local resets = require("cnr.resets")
local crash = require("cnr.crash")
local leaderboard = require("cnr.leaderboard")
local vec = require("cnr.vec")
local sight = require("cnr.sight")

local M = {}
local Round = {}
Round.__index = Round

local PICK_TIMEOUT_SECONDS = 10
local COLOR_RUNNER = "#1f5fff"
local COLOR_COPS = { "#20c020", "#e02020" }

M.AI_FIRST = -10

function M.isAI(id)
  return type(id) == "number" and id <= M.AI_FIRST
end
local SETUP_GRACE_SECONDS = 5
local RELOCATE_GRACE_SECONDS = 3
local TELEPORT_BASE_METERS = 60
local TELEPORT_MAX_SPEED = 100
local TELEPORT_ANNOUNCE_GAP = 5

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

local function sortedPids(players)
  local pids = {}
  for pid in pairs(players) do pids[#pids + 1] = pid end
  table.sort(pids)
  return pids
end

function M.new(cfg)
  local r = setmetatable({ cfg = cfg }, Round)
  r:clear()
  return r
end

function Round:clear()
  self.state = "idle"
  self.runnerId = nil
  self.issuerId = nil
  self.vehicle = nil
  self.startedAt = nil
  self.countdownStartedAt = nil
  self.releasedAt = nil
  self.pickStartedAt = nil
  self.players = {}
  self.resetTrackers = {}
  self.crashDetectors = {}
  self.penalties = {}
  self.prevCars = {}
  self.leftPlayers = {}
  self.teleportAnnounced = {}
  self.lastTickAt = nil
  self.lastSeenAt = nil
  self.sight = sight.new()
  self.inSight = false
  self.liveAt = nil
  self.test = false
  self.lastState = {}
  self.nextCopIndex = 1
  self.catchTracker = catch.new(self.cfg)
end

function Round:isActive()
  return self.state ~= "idle"
end

function Round:runnerName()
  return self.players[self.runnerId] or tostring(self.runnerId)
end

function Round:setupFor(now, pid)
  local role, copIndex = "cop", 0
  if pid == self.runnerId then
    role = "runner"
  else
    copIndex = self.nextCopIndex
    self.nextCopIndex = self.nextCopIndex + 1
  end
  self.resetTrackers[pid] = resets.new(self.cfg)
  self.resetTrackers[pid]:grant(now, SETUP_GRACE_SECONDS)
  self.crashDetectors[pid] = crash.new(self.cfg)
  local e = { kind = "setup", pid = pid, role = role, copIndex = copIndex, phase = self.state }
  if self.state == "countdown" then
    e.countdownRemaining = math.max(0, self.countdownStartedAt + self.cfg.runnerCountdownSeconds - now)
  elseif self.state == "headstart" then
    e.headStartRemaining = math.max(0, self.startedAt + self.cfg.headStartSeconds - now)
  elseif self.state == "running" then
    e.chaseElapsed = math.max(0, now - self.releasedAt)
  end
  return e
end

function Round:finish(now, reason)
  local fx = {}
  local survived = self.releasedAt and (now - self.releasedAt) or 0
  local catchers = reason == "caught" and self.catchers or {}
  fx[#fx + 1] = {
    kind = "roundEnd", runnerId = self.runnerId, runnerName = self:runnerName(),
    survivedSeconds = survived, reason = reason, catchers = catchers,
    explode = self.cfg.explodeOnCatch and reason == "caught",
  }
  if self.test and reason == "caught" then
    fx[#fx + 1] = { kind = "broadcast", msg = string.format("Test round: %s caught after %s", self:runnerName(), leaderboard.formatTime(survived)) }
  end
  if reason ~= "cancelled" and not self.test then
    fx[#fx + 1] = { kind = "record", run = {
      player = self:runnerName(), survivedSeconds = survived,
      model = self.vehicle and self.vehicle.model, config = self.vehicle and self.vehicle.config,
      releasedAt = self.releasedAt, endedAt = now, endReason = reason, catchers = catchers,
    } }
  end
  self:clear()
  return fx
end

function Round:cancel(now, msg)
  local fx = { { kind = "broadcast", msg = msg } }
  for _, e in ipairs(self:finish(now, "cancelled")) do fx[#fx + 1] = e end
  return fx
end

function Round:start(now, runnerId, issuerId, players, opts)
  if self:isActive() then
    return { { kind = "reply", pid = issuerId, msg = "A round is already running" } }
  end
  self:clear()
  self.test = opts and opts.test or false
  if self.test then
    local role = opts.role
    if role ~= "runner" and role ~= "cop" then
      self:clear()
      return { { kind = "reply", pid = issuerId, msg = 'Usage: "/cnr test <runner|cop>"' } }
    end
    self.testRole = role
    self.players = { [issuerId] = players[issuerId] or "You" }
    local a1, a2 = M.AI_FIRST, M.AI_FIRST - 1
    if role == "runner" then
      self.runnerId = issuerId
      self.players[a1], self.players[a2] = "AI green", "AI red"
    else
      self.runnerId = a1
      self.players[a1], self.players[a2] = "AI blue", "AI red"
    end
  else
    self.runnerId = runnerId
    self.players = copy(players)
  end
  self.state = "picking"
  self.issuerId = issuerId
  self.pickStartedAt = now
  return { { kind = "pickVehicle", pid = issuerId } }
end

function Round:vehiclePicked(now, pid, model, config, players)
  if self.state ~= "picking" or pid ~= self.issuerId then return {} end
  if not self.test then self.players = copy(players) end
  if not self.test and not self.players[self.runnerId] then
    return self:cancel(now, "Runner left, round cancelled")
  end
  self.state = "prep"
  self.vehicle = { model = model, config = config }
  self.nextCopIndex = 1
  local fx = {}
  if self.test then
    local copColor = 1
    local function colorFor(id)
      if id == self.runnerId then return COLOR_RUNNER end
      local c = COLOR_COPS[copColor]
      copColor = copColor + 1
      return c
    end
    local own = self:setupFor(now, pid)
    own.colorHex = colorFor(pid)
    own.inPlace = true
    fx[#fx + 1] = own
    local ai = {}
    for _, id in ipairs({ M.AI_FIRST, M.AI_FIRST - 1 }) do
      local e = self:setupFor(now, id)
      ai[#ai + 1] = { id = id, role = e.role, index = #ai + 1, colorHex = colorFor(id), name = self.players[id] }
    end
    fx[#fx + 1] = { kind = "setupAI", pid = pid, ai = ai }
    if self.testRole == "runner" then
      fx[#fx + 1] = { kind = "broadcast", msg = 'Test round: you are the runner, two AI cops will chase you. Type "/cnr go" to start' }
    else
      fx[#fx + 1] = { kind = "broadcast", msg = 'Test round: you are a cop with an AI runner and an AI partner. Type "/cnr go" to start' }
    end
  else
    for _, p in ipairs(sortedPids(self.players)) do fx[#fx + 1] = self:setupFor(now, p) end
    fx[#fx + 1] = { kind = "broadcast", msg = string.format('%s is the runner! Car: %s. Change your paint if you like, then type "/cnr go"', self:runnerName(), model) }
  end
  return fx
end

function Round:go(now, pid)
  if self.state == "idle" or self.state == "picking" then
    return { { kind = "reply", pid = pid, msg = 'No round set up, use "/cnr start <name>"' } }
  end
  if self.state ~= "prep" then
    return { { kind = "reply", pid = pid, msg = "Round already started" } }
  end
  self.state = "countdown"
  self.countdownStartedAt = now
  return {
    { kind = "countdown", seconds = self.cfg.runnerCountdownSeconds },
    { kind = "broadcast", msg = string.format("Runner starts in %gs", self.cfg.runnerCountdownSeconds) },
  }
end

function Round:tick(now, cars, stations)
  local fx = {}
  if self.state == "picking" then
    if now - self.pickStartedAt >= PICK_TIMEOUT_SECONDS then
      return self:cancel(now, "Vehicle pick timed out")
    end
    return fx
  end
  if self.state == "idle" or self.state == "prep" then return fx end

  if self.state == "countdown" then
    if now - self.countdownStartedAt < self.cfg.runnerCountdownSeconds then return fx end
    self.state = "headstart"
    self.startedAt = now
    for _, tracker in pairs(self.resetTrackers) do tracker:grant(now, SETUP_GRACE_SECONDS) end
    fx[#fx + 1] = { kind = "runnerGo", headStartSeconds = self.cfg.headStartSeconds }
    fx[#fx + 1] = { kind = "broadcast", msg = string.format("%s is off! Cops released in %gs", self:runnerName(), self.cfg.headStartSeconds) }
  end

  if self.state == "headstart" and now - self.startedAt >= self.cfg.headStartSeconds then
    self.state = "running"
    self.releasedAt = now
    self.lastSeenAt = now
    fx[#fx + 1] = { kind = "release" }
    fx[#fx + 1] = { kind = "broadcast", msg = "Cops released!" }
  end

  local runnerCar = cars[self.runnerId]
  local progress, caught = 0, false
  if self.state == "running" then
    for _, pid in ipairs(sortedPids(self.players)) do
      if pid ~= self.runnerId then
        local untilTime = self.penalties[pid]
        if untilTime and now >= untilTime then
          self.penalties[pid] = nil
          fx[#fx + 1] = { kind = "penaltyEnd", pid = pid }
        elseif not untilTime and self.crashDetectors[pid] and self.crashDetectors[pid]:update(now, cars[pid])
          and crash.atFault(self.prevCars[pid], self:otherCars(pid)) then
          local seconds = self.cfg.crashPenaltySeconds
          self.penalties[pid] = now + seconds
          if self.resetTrackers[pid] then self.resetTrackers[pid]:block(now + seconds) end
          fx[#fx + 1] = { kind = "penalty", pid = pid, seconds = seconds, name = self.players[pid] }
        end
      end
    end
    local cops = {}
    for pid in pairs(self.players) do
      if pid ~= self.runnerId and cars[pid] and not self.penalties[pid] then cops[#cops + 1] = cars[pid] end
    end
    progress, caught = self.catchTracker:update(now, runnerCar, cops)
    if caught then self.catchers = self:copsNear(runnerCar, cars) end
    if not caught and runnerCar then self:sightTick(now, cars, runnerCar, fx) end
    local interval = self.cfg.lastSeenIntervalSeconds
    if not caught and interval > 0 and runnerCar and now - self.lastSeenAt >= interval - 1e-9 then
      self.lastSeenAt = now
      local nearest
      for _, car in ipairs(cops) do
        local d = vec.dist(runnerCar.pos, car.pos)
        if not nearest or d < nearest then nearest = d end
      end
      fx[#fx + 1] = { kind = "lastSeen", pos = runnerCar.pos, nearestCop = nearest }
    end
  end

  local runnerPos = runnerCar and runnerCar.pos
  for _, pid in ipairs(sortedPids(self.players)) do
    local tracker = self.resetTrackers[pid]
    if tracker and (self.state == "running" or pid == self.runnerId) then
      local role = pid == self.runnerId and "runner" or "cop"
      local beingCaught = role == "runner" and progress > 0
      local allowed, hint = tracker:update(now, cars[pid], { role = role, runnerPos = runnerPos, stations = stations, beingCaught = beingCaught })
      local p = math.floor(progress * 100 + 1e-9) / 100
      local last = self.lastState[pid]
      if not last or last.resetAllowed ~= allowed or last.resetHint ~= hint or last.catchProgress ~= p then
        local e = { kind = "state", pid = pid, resetAllowed = allowed, resetHint = hint, catchProgress = p }
        self.lastState[pid] = e
        fx[#fx + 1] = e
      end
    end
  end

  if self.lastTickAt then
    local allowedMove = TELEPORT_BASE_METERS + TELEPORT_MAX_SPEED * (now - self.lastTickAt)
    for _, pid in ipairs(sortedPids(self.players)) do
      local before, after, tracker = self.prevCars[pid], cars[pid], self.resetTrackers[pid]
      if before and after and before.pos and after.pos and vec.dist(before.pos, after.pos) > allowedMove
        and not (tracker and tracker:inGrace(now)) then
        if not self.teleportAnnounced[pid] or now - self.teleportAnnounced[pid] >= TELEPORT_ANNOUNCE_GAP then
          self.teleportAnnounced[pid] = now
          fx[#fx + 1] = { kind = "broadcast", msg = string.format("%s teleported", self.players[pid]) }
        end
      end
    end
  end
  self.lastTickAt = now
  self.prevCars = cars
  local limit = self.cfg.roundTimeLimitSeconds
  if caught then
    for _, e in ipairs(self:finish(now, "caught")) do fx[#fx + 1] = e end
  elseif self.state == "running" and limit > 0 and now - self.releasedAt >= limit - 1e-9 then
    for _, e in ipairs(self:finish(now, "escaped")) do fx[#fx + 1] = e end
  end
  return fx
end

function Round:copsNear(runnerCar, cars)
  local names = {}
  if not runnerCar or not runnerCar.pos then return names end
  for pid, name in pairs(self.players) do
    local car = cars[pid]
    if pid ~= self.runnerId and car and car.pos and not self.penalties[pid]
      and vec.dist(runnerCar.pos, car.pos) <= self.cfg.catchRadiusMeters then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function Round:otherCars(pid)
  local list = {}
  for other, car in pairs(self.prevCars) do
    if other ~= pid then list[#list + 1] = car end
  end
  return list
end

function Round:playerJoined(now, pid, name)
  if self.state == "idle" or self.test then return {} end
  self.players[pid] = name
  if self.state == "picking" then return {} end
  local setup = self:setupFor(now, pid)
  local fx = { setup }
  local left = self.leftPlayers[name]
  if left then
    self.leftPlayers[name] = nil
    setup.resumePos = left.pos
    if left.penaltyUntil and left.penaltyUntil > now then
      self.penalties[pid] = left.penaltyUntil
      self.resetTrackers[pid]:block(left.penaltyUntil)
      fx[#fx + 1] = { kind = "penalty", pid = pid, seconds = left.penaltyUntil - now, name = name }
    end
  end
  return fx
end

function Round:sightReport(now, pid, seen)
  if self.state ~= "running" or self.players[pid] == nil or pid == self.runnerId or M.isAI(pid) then return end
  sight.report(self.sight, pid, seen == true, now)
end

function Round:copPids()
  local pids = {}
  for pid in pairs(self.players) do
    if pid ~= self.runnerId then pids[#pids + 1] = pid end
  end
  table.sort(pids)
  return pids
end

function Round:sightTick(now, cars, runnerCar, fx)
  local cfg = self.cfg
  if cfg.sightMaxMeters <= 0 then return end
  local cops = self:copPids()
  local nearest
  for _, pid in ipairs(cops) do
    local car = cars[pid]
    if car and car.pos then
      local d = vec.dist(runnerCar.pos, car.pos)
      if not nearest or d < nearest then nearest = d end
    end
  end
  if sight.any(self.sight, cops, now, cfg.sightGraceSeconds) then
    if not self.inSight then
      self.inSight = true
      fx[#fx + 1] = { kind = "spotted", spotted = true }
    end
    self.lastSeenAt = now
    if self.liveAt and now - self.liveAt < cfg.sightLiveIntervalSeconds - 1e-9 then return end
    self.liveAt = now
    local noRoute = {}
    for _, pid in ipairs(cops) do
      local car = cars[pid]
      if car and car.pos and car.vel and sight.sees(self.sight, pid, now, cfg.sightGraceSeconds) then
        local limit = sight.noRouteDistance(vec.speedKmh(car.vel) / 3.6, cfg.sightNoRouteSeconds, cfg.sightNoRouteMinMeters)
        if vec.dist(runnerCar.pos, car.pos) <= limit then noRoute[pid] = true end
      end
    end
    fx[#fx + 1] = { kind = "live", pos = runnerCar.pos, noRoute = noRoute, nearestCop = nearest }
  elseif self.inSight then
    self.inSight = false
    self.liveAt = nil
    self.lastSeenAt = now
    fx[#fx + 1] = { kind = "spotted", spotted = false }
    fx[#fx + 1] = { kind = "lastSeen", pos = runnerCar.pos, nearestCop = nearest }
  end
end

function Round:playerLeft(now, pid)
  if self.state == "idle" or self.players[pid] == nil then return {} end
  sight.forget(self.sight, pid)
  if pid == self.runnerId then
    if self.state == "running" then return self:finish(now, "disconnect") end
    return self:cancel(now, "Runner left, round cancelled")
  end
  if (self.state == "picking" or self.test) and pid == self.issuerId then
    return self:cancel(now, "Round cancelled")
  end
  local name = self.players[pid]
  local prev = self.prevCars[pid]
  if self.state == "running" or self.state == "headstart" then
    self.leftPlayers[name] = { pos = prev and prev.pos, penaltyUntil = self.penalties[pid] }
  end
  self.players[pid] = nil
  self.resetTrackers[pid] = nil
  self.crashDetectors[pid] = nil
  self.penalties[pid] = nil
  self.lastState[pid] = nil
  return {}
end

function Round:vehicleReset(now, pid)
  local tracker = self.resetTrackers[pid]
  if (self.state ~= "headstart" and self.state ~= "running") or not tracker then return {} end
  if tracker:consume(now) then
    if self.crashDetectors[pid] then self.crashDetectors[pid]:reset() end
    return {}
  end
  return { { kind = "broadcast", msg = string.format("%s reset illegally", self.players[pid] or tostring(pid)) } }
end

function Round:relocated(now, pid)
  local tracker = self.resetTrackers[pid]
  if not tracker then return {} end
  tracker:grant(now, RELOCATE_GRACE_SECONDS)
  if self.crashDetectors[pid] then self.crashDetectors[pid]:reset() end
  self.prevCars[pid] = nil
  return {}
end

function Round:endCalled(now, pid)
  if self.state ~= "running" then
    if self.state == "idle" then return { { kind = "reply", pid = pid, msg = "No round running" } } end
    return { { kind = "reply", pid = pid, msg = 'The chase has not started, use "/cnr stop"' } }
  end
  return self:finish(now, "called")
end

function Round:reroll(now, pid)
  if self.state ~= "prep" then
    return { { kind = "reply", pid = pid, msg = "You can only reroll during prep" } }
  end
  self.state = "picking"
  self.issuerId = pid
  self.pickStartedAt = now
  return {
    { kind = "pickVehicle", pid = pid },
    { kind = "broadcast", msg = "Picking a new car..." },
  }
end

function Round:stop(now, issuerId)
  if self.state == "idle" then
    return { { kind = "reply", pid = issuerId, msg = "No round running" } }
  end
  return self:cancel(now, "Round cancelled")
end

for _, name in ipairs({ "start", "vehiclePicked", "go", "tick", "playerJoined", "playerLeft", "vehicleReset", "stop", "endCalled", "reroll", "relocated" }) do
  local method = Round[name]
  Round[name] = function(self, ...)
    local issuer = self.test and self.issuerId
    local fx = method(self, ...)
    issuer = issuer or (self.test and self.issuerId)
    if issuer then
      for _, e in ipairs(fx) do
        if e.pid == nil and e.to == nil then e.to = issuer end
      end
    end
    return fx
  end
end

return M
