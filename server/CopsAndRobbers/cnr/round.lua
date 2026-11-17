local catch = require("cnr.catch")
local resets = require("cnr.resets")
local crash = require("cnr.crash")
local vec = require("cnr.vec")
local sight = require("cnr.sight")
local sky = require("cnr.sky")
local helicopter = require("cnr.helicopter")

local M = {}
local Round = {}
Round.__index = Round

local PICK_TIMEOUT_SECONDS = 10
local APPLY_TIMEOUT_SECONDS = 20
local SETUP_REPLY_TIMEOUT_SECONDS = 5
local MAX_SIGHT_STEP = 1
local SIGHT_RANGE_MARGIN = 50
local NEAREST_COP_SECONDS = 30
local COLOR_RUNNER = "#d83a2c"
local COLOR_COPS = { "#1f6fe0", "#6fb0ff" }

M.AI_FIRST = -10

function M.isAI(id)
  return type(id) == "number" and id <= M.AI_FIRST
end
local SETUP_GRACE_SECONDS = 5
local RELOCATE_GRACE_SECONDS = 3
local MAX_TIMELINE = 50
local TELEPORT_BASE_METERS = 60
local TELEPORT_MAX_SPEED = 100
local TELEPORT_ANNOUNCE_GAP = 5
local lastRebuildId = 0

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

local function nearRunner(car, runnerCar, cfg)
  if not runnerCar or not runnerCar.pos or not car or not car.pos then return true end
  return vec.dist(car.pos, runnerCar.pos) < cfg.copResetMinDistanceMeters
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
  self.evolving = false
  self.buildStep, self.buildName = nil, nil
  self.sky = nil
  self.traffic = nil
  self.trafficRunnerOnly = nil
  self.prevTraffic = nil
  self.applyStartedAt, self.setupDone, self.readyPids, self.rebuildId = nil, false, {}, nil
  self.startedAt = nil
  self.countdownStartedAt = nil
  self.releasedAt = nil
  self.pickStartedAt = nil
  self.players = {}
  self.resetTrackers = {}
  self.crashDetectors = {}
  self.penalties = {}
  self.freeResetUntil = nil
  self.prevCars = {}
  self.leftPlayers = {}
  self.teleportAnnounced = {}
  self.lastTickAt = nil
  self.sight = sight.new()
  self.queued = nil
  self.inSight = false
  self.liveAt = nil
  self.sightTickAt = nil
  self.heli = nil
  self.runnerCovered = true
  self.tracked = false
  self.shown = true
  self.nearestAt = nil
  self.hiddenSeconds = 0
  self.lostCount = 0
  self.timeline = {}
  self.copSight = {}
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
  e.runnerShown = self.shown
  e.heli = self.heli and helicopter.status(self.heli, now) or nil
  if self.state == "countdown" then
    e.countdownRemaining = math.max(0, self.countdownStartedAt + self.cfg.runnerCountdownSeconds - now)
  elseif self.state == "headstart" then
    e.headStartRemaining = math.max(0, self.startedAt + self.cfg.headStartSeconds - now)
  elseif self.state == "running" then
    e.chaseElapsed = math.max(0, now - self.releasedAt)
  end
  return e
end

function Round:note(now, kind, name, seconds, cause)
  if (self.state ~= "headstart" and self.state ~= "running") or #self.timeline >= MAX_TIMELINE then return end
  local t = 0
  if self.releasedAt then t = math.max(0, math.floor((now - self.releasedAt) * 10 + 0.5) / 10) end
  self.timeline[#self.timeline + 1] = { t = t, kind = kind, name = name, seconds = seconds, cause = cause }
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
  if reason ~= "cancelled" and not self.test then
    fx[#fx + 1] = { kind = "record", run = {
      player = self:runnerName(), survivedSeconds = survived,
      model = self.vehicle and self.vehicle.model, config = not self.evolving and self.vehicle and self.vehicle.config or nil,
      releasedAt = self.releasedAt, endedAt = now, endReason = reason, catchers = catchers,
      chaseSeconds = survived, copIds = {}, copSight = {},
      hiddenSeconds = self.cfg.sightMaxMeters > 0 and self.hiddenSeconds or nil,
      lostCount = self.cfg.sightMaxMeters > 0 and self.lostCount or nil,
      timeline = self.timeline,
      mode = self.evolving and "evolving" or "random", buildStep = self.buildStep, buildName = self.buildName,
      sky = sky.record(self.sky, self.cfg),
      traffic = (self.traffic or 0) > 0 and self.traffic or nil,
      trafficRunnerOnly = (self.traffic or 0) > 0 and self.trafficRunnerOnly or nil,
      helicopter = self.heli and helicopter.flew(self.heli) or nil,
    } }
    local run = fx[#fx].run
    for _, pid in ipairs(self:copPids()) do
      if not M.isAI(pid) then
        run.copIds[#run.copIds + 1] = pid
        run.copSight[#run.copSight + 1] = self.copSight[pid] or 0
      end
    end
  end
  self:clear()
  return fx
end

function Round:cancel(now, msg)
  local fx = { { kind = "broadcast", msg = msg } }
  for _, e in ipairs(self:finish(now, "cancelled")) do
    if e.kind == "roundEnd" then e.message = msg end
    fx[#fx + 1] = e
  end
  return fx
end

function Round:start(now, runnerId, issuerId, players, opts)
  if self:isActive() then
    return { { kind = "reply", pid = issuerId, msg = "A round is already running", tone = "warn" } }
  end
  self:clear()
  self.test = opts and opts.test or false
  if self.test then
    local role = opts.role
    if role ~= "runner" and role ~= "cop" then
      self:clear()
      return { { kind = "reply", pid = issuerId, msg = "Pick practice as runner or as cop", tone = "warn" } }
    end
    self.testRole = role
    self.players = { [issuerId] = players[issuerId] or "You" }
    local a1, a2 = M.AI_FIRST, M.AI_FIRST - 1
    if role == "runner" then
      self.runnerId = issuerId
      self.players[a1], self.players[a2] = "AI cop 1", "AI cop 2"
    else
      self.runnerId = a1
      self.players[a1], self.players[a2] = "AI runner", "AI cop"
    end
  else
    self.runnerId = runnerId
    self.players = copy(players)
  end
  self.state = "picking"
  self.issuerId = issuerId
  self.pickStartedAt = now
  self.sky = opts and opts.sky or nil
  self.traffic = opts and opts.traffic or nil
  self.trafficRunnerOnly = opts and opts.trafficRunnerOnly == true or nil
  local b = opts and opts.build
  if b then
    self.evolving = true
    self.buildStep, self.buildName = b.step, b.name
    return self:vehiclePicked(now, issuerId, b.model, b.config, players)
  end
  return { { kind = "pickVehicle", pid = issuerId } }
end

function Round:allReady()
  for pid in pairs(self.players) do
    if not M.isAI(pid) and not self.readyPids[pid] then return false end
  end
  return true
end

function Round:markApplied(timedOut)
  self.state = "ready"
  return { { kind = "applied", timedOut = timedOut or nil } }
end

function Round:rebuild(now, config)
  self.setupDone = true
  self.readyPids = {}
  self.applyStartedAt = now
  lastRebuildId = lastRebuildId + 1
  self.rebuildId = lastRebuildId
  return { { kind = "rebuild", config = config, id = self.rebuildId } }
end

function Round:apply(now, pid)
  if not self.evolving or self.state ~= "prep" then
    return { { kind = "reply", pid = pid, msg = "Apply only works during prep in evolving mode", tone = "warn" } }
  end
  self.state = "applying"
  self.applyStartedAt = now
  self.setupDone = false
  self.readyPids = {}
  if M.isAI(self.runnerId) then return self:markApplied() end
  return { { kind = "requestSetup", pid = self.runnerId } }
end

function Round:setupReceived(now, pid, newConfig)
  if self.state ~= "applying" or pid ~= self.runnerId or self.setupDone then return {} end
  self.vehicle.config = newConfig
  return self:rebuild(now, newConfig)
end

function Round:vehicleReady(now, pid, rebuildId)
  if self.state ~= "applying" or not self.setupDone or self.players[pid] == nil then return {} end
  if rebuildId ~= self.rebuildId then return {} end
  self.readyPids[pid] = true
  if self:allReady() then return self:markApplied() end
  return {}
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
  else
    for _, p in ipairs(sortedPids(self.players)) do fx[#fx + 1] = self:setupFor(now, p) end
  end
  return fx
end

function Round:go(now, pid)
  if self.state == "idle" or self.state == "picking" then
    return { { kind = "reply", pid = pid, msg = "No round set up, start one in the panel", tone = "warn" } }
  end
  if self.evolving and (self.state == "prep" or self.state == "applying") then
    return { { kind = "reply", pid = pid, msg = "Apply the change first", tone = "warn" } }
  end
  if self.state ~= (self.evolving and "ready" or "prep") then
    return { { kind = "reply", pid = pid, msg = "Round already started", tone = "warn" } }
  end
  self.state = "countdown"
  self.countdownStartedAt = now
  return { { kind = "countdown", seconds = self.cfg.runnerCountdownSeconds } }
end

function Round:tick(now, cars, stations, traffic)
  local fx = {}
  local heliNew = false
  if self.state == "picking" then
    if now - self.pickStartedAt >= PICK_TIMEOUT_SECONDS then
      return self:cancel(now, "Vehicle pick timed out")
    end
    return fx
  end
  if self.state == "applying" then
    local waited = now - self.applyStartedAt
    if not self.setupDone and waited >= SETUP_REPLY_TIMEOUT_SECONDS - 1e-9 then return self:rebuild(now, self.vehicle.config) end
    if self.setupDone and waited >= APPLY_TIMEOUT_SECONDS - 1e-9 then return self:markApplied(true) end
  end
  if self.state == "idle" or self.state == "prep" or self.state == "applying" or self.state == "ready" then return fx end

  if self.state == "countdown" then
    if now - self.countdownStartedAt < self.cfg.runnerCountdownSeconds then return fx end
    self.state = "headstart"
    self.startedAt = now
    for _, tracker in pairs(self.resetTrackers) do tracker:grant(now, SETUP_GRACE_SECONDS) end
    fx[#fx + 1] = { kind = "runnerGo", headStartSeconds = self.cfg.headStartSeconds }
  end

  if self.state == "headstart" and now - self.startedAt >= self.cfg.headStartSeconds then
    self.state = "running"
    self.releasedAt = now
    self.nearestAt = now
    fx[#fx + 1] = { kind = "release" }
    if self.cfg.helicopter then
      self.heli = helicopter.new(self.cfg, self.sky and self.sky.weather, now)
      heliNew = true
    end
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
          and nearRunner(cars[pid], runnerCar, self.cfg) then
          local fault, nearest = crash.atFault(self.prevCars[pid], self:otherCars(pid))
          if fault then
            local seconds = self.cfg.crashPenaltySeconds
            local cause = nearest and nearest.traffic and "traffic" or nil
            self.penalties[pid] = now + seconds
            if pid ~= self.runnerId and nearest and nearest == self.prevCars[self.runnerId] then self.freeResetUntil = now + seconds end
            if self.resetTrackers[pid] then self.resetTrackers[pid]:block(now + seconds) end
            fx[#fx + 1] = { kind = "penalty", pid = pid, seconds = seconds, name = self.players[pid], cause = cause }
            self:note(now, "penalty", self.players[pid], seconds, cause)
          end
        end
      end
    end
    local cops = {}
    for pid in pairs(self.players) do
      if pid ~= self.runnerId and cars[pid] and not self.penalties[pid] then cops[#cops + 1] = cars[pid] end
    end
    progress, caught = self.catchTracker:update(now, runnerCar, cops)
    if caught then self.catchers = self:copsNear(runnerCar, cars) end
    if self.heli and not caught and (helicopter.update(self.heli, now, self.runnerCovered, self.inSight) or heliNew) then
      local s = helicopter.status(self.heli, now)
      fx[#fx + 1] = { kind = "heli", phase = s.phase, seconds = s.seconds, reason = s.reason, seed = s.seed, guided = s.guided }
    end
    if not caught and runnerCar then
      local nearest = self:nearestCop(cars, runnerCar)
      local seeing = self:sightTick(now, cars, runnerCar, fx)
      self:trackTick(now, cars, runnerCar, seeing, nearest, fx)
      if nearest and now - self.nearestAt >= NEAREST_COP_SECONDS - 1e-9 then
        self.nearestAt = now
        fx[#fx + 1] = { kind = "nearestCop", dist = nearest }
      end
    end
  end

  local runnerPos = runnerCar and runnerCar.pos
  for _, pid in ipairs(sortedPids(self.players)) do
    local tracker = self.resetTrackers[pid]
    if tracker and (self.state == "running" or pid == self.runnerId) then
      local role = pid == self.runnerId and "runner" or "cop"
      local beingCaught = role == "runner" and progress > 0
      local freeReset = role == "runner" and self.freeResetUntil ~= nil and now < self.freeResetUntil
      local allowed, hint = tracker:update(now, cars[pid], { role = role, runnerPos = runnerPos, stations = stations, beingCaught = beingCaught, freeReset = freeReset })
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
          fx[#fx + 1] = { kind = "broadcast", msg = string.format("%s teleported", self.players[pid]), tone = "warn" }
          self:note(now, "teleport", self.players[pid])
        end
      end
    end
  end
  self.lastTickAt = now
  self.prevCars = cars
  self.prevTraffic = traffic
  local shown = self.cfg.sightMaxMeters <= 0 or (self.state ~= "headstart" and self.state ~= "running") or self.tracked
  if shown ~= self.shown then
    self.shown = shown
    fx[#fx + 1] = { kind = "runnerShown", shown = shown }
  end
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
  for _, car in ipairs(self.prevTraffic or {}) do list[#list + 1] = car end
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
    self.copSight[pid] = left.copSight
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

function Round:nearestCop(cars, runnerCar)
  local nearest
  for _, pid in ipairs(self:copPids()) do
    local car = cars[pid]
    if car and car.pos and not self.penalties[pid] then
      local d = vec.dist(runnerCar.pos, car.pos)
      if not nearest or d < nearest then nearest = d end
    end
  end
  return nearest
end

function Round:sightTick(now, cars, runnerCar, fx)
  local cfg = self.cfg
  local seeing = {}
  if cfg.sightMaxMeters <= 0 then return seeing end
  local dt = self.sightTickAt and math.min(MAX_SIGHT_STEP, math.max(0, now - self.sightTickAt)) or 0
  self.sightTickAt = now
  local inSight = false
  for _, pid in ipairs(self:copPids()) do
    local car = cars[pid]
    local d = car and car.pos and vec.dist(runnerCar.pos, car.pos)
    if d and d <= cfg.sightMaxMeters + SIGHT_RANGE_MARGIN and sight.sees(self.sight, pid, now, cfg.sightGraceSeconds) then
      seeing[pid] = true
      inSight = true
      self.copSight[pid] = (self.copSight[pid] or 0) + dt
    end
  end
  if not inSight then self.hiddenSeconds = self.hiddenSeconds + dt end
  if inSight and not self.inSight then
    self.inSight = true
    fx[#fx + 1] = { kind = "spotted", spotted = true }
  elseif not inSight and self.inSight then
    self.inSight = false
    self.lostCount = self.lostCount + 1
    self:note(now, "lost", self:runnerName())
    fx[#fx + 1] = { kind = "spotted", spotted = false }
  end
  return seeing
end

function Round:trackTick(now, cars, runnerCar, seeing, nearest, fx)
  local cfg = self.cfg
  local tracked = self.inSight or (self.heli ~= nil and helicopter.tracking(self.heli))
  if tracked then
    self.tracked = true
    if self.liveAt and now - self.liveAt < cfg.sightLiveIntervalSeconds - 1e-9 then return end
    self.liveAt = now
    local noRoute = {}
    for _, pid in ipairs(self:copPids()) do
      local car = cars[pid]
      if car and car.pos and car.vel and seeing[pid] then
        local limit = sight.noRouteDistance(vec.speedKmh(car.vel) / 3.6, cfg.sightNoRouteSeconds, cfg.sightNoRouteMinMeters)
        if vec.dist(runnerCar.pos, car.pos) <= limit then noRoute[pid] = true end
      end
    end
    fx[#fx + 1] = { kind = "live", pos = runnerCar.pos, geo = runnerCar.geo, noRoute = noRoute, nearestCop = nearest }
  elseif self.tracked then
    self.tracked = false
    self.liveAt = nil
    fx[#fx + 1] = { kind = "lastSeen", pos = runnerCar.pos, geo = runnerCar.geo, nearestCop = nearest }
  end
end

function Round:coverReport(now, pid, covered)
  if self.state ~= "headstart" and self.state ~= "running" then return end
  local owner = self.runnerId
  if M.isAI(owner) and self.test then owner = self.issuerId end
  if M.isAI(owner) or pid ~= owner then return end
  self.runnerCovered = covered == true
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
    self.leftPlayers[name] = { pos = prev and prev.pos, penaltyUntil = self.penalties[pid], copSight = self.copSight[pid] }
  end
  self.copSight[pid] = nil
  self.players[pid] = nil
  self.resetTrackers[pid] = nil
  self.crashDetectors[pid] = nil
  self.penalties[pid] = nil
  self.lastState[pid] = nil
  if self.state == "applying" and self.setupDone and self:allReady() then return self:markApplied() end
  return {}
end

function Round:vehicleReset(now, pid)
  local tracker = self.resetTrackers[pid]
  if (self.state ~= "headstart" and self.state ~= "running") or not tracker then return {} end
  self.lastState[pid] = nil
  if tracker:consume(now) then
    if pid == self.runnerId then self.freeResetUntil = nil end
    if self.crashDetectors[pid] then self.crashDetectors[pid]:reset() end
    return {}
  end
  self:note(now, "illegalReset", self.players[pid])
  return { { kind = "broadcast", msg = string.format("%s reset illegally", self.players[pid] or tostring(pid)), tone = "warn" } }
end

function Round:relocated(now, pid)
  local tracker = self.resetTrackers[pid]
  if not tracker then return {} end
  self.lastState[pid] = nil
  tracker:grant(now, RELOCATE_GRACE_SECONDS)
  if self.crashDetectors[pid] then self.crashDetectors[pid]:reset() end
  self.prevCars[pid] = nil
  return {}
end

function Round:endCalled(now, pid)
  if self.state ~= "running" then
    if self.state == "idle" then return { { kind = "reply", pid = pid, msg = "No round running", tone = "warn" } } end
    return { { kind = "reply", pid = pid, msg = "The chase has not started, use Cancel", tone = "warn" } }
  end
  return self:finish(now, "called")
end

function Round:reroll(now, pid)
  if self.evolving then
    return { { kind = "reply", pid = pid, msg = "New car isn't available in evolving mode", tone = "warn" } }
  end
  if self.state ~= "prep" then
    return { { kind = "reply", pid = pid, msg = "You can only reroll during prep", tone = "warn" } }
  end
  self.state = "picking"
  self.issuerId = pid
  self.pickStartedAt = now
  return { { kind = "pickVehicle", pid = pid } }
end

function Round:stop(now, issuerId)
  if self.state == "idle" then
    return { { kind = "reply", pid = issuerId, msg = "No round running", tone = "warn" } }
  end
  return self:cancel(now, "Round cancelled")
end

for _, name in ipairs({ "start", "vehiclePicked", "go", "tick", "playerJoined", "playerLeft", "vehicleReset", "stop", "endCalled", "reroll", "relocated", "apply", "setupReceived", "vehicleReady" }) do
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
