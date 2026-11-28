local colors = require("arcade.colors")
local traffic = require("arcade.traffic")
local leaderboard = require("cnr.leaderboard")
local round = require("cnr.round")
local sky = require("cnr.sky")
local strikeSchedule = require("cnr.strikeSchedule")
local M = {}

local PARTS_PLACING_SECONDS, PARTS_SETTLE_SECONDS = 10, 3
local AI_SETUP_WAIT_SECONDS = 15

function M.new(ctx)
  local game = {
    stations = {}, partsBaseline = {}, missingCount = {}, runCounts = {},
    aiCars = {}, aiSlotSerial = {}, aiVidSerial = {}, previousRoundSerial = 0, aiSpawnsLeft = 0,
    connectionSerial = ctx.roster:perPlayer("connectionSerial", "early"),
  }
  local cars, roster, spectators = ctx.cars, ctx.roster, ctx.spectators
  local send, log = ctx.messages.send, ctx.messages.log
  local now = ctx.now

  function game:placing(pid)
    local entry = self.partsBaseline[pid] or {}
    self.partsBaseline[pid] = { announced = entry.announced, quietUntil = now() + PARTS_PLACING_SECONDS, placing = true }
  end

  function game:placed(pid)
    local entry = self.partsBaseline[pid]
    if entry and entry.placing then
      entry.placing = nil
      entry.quietUntil = now() + PARTS_SETTLE_SECONDS
    end
  end

  function game:openTraffic(pid)
    local current = self.current
    if not current:isActive() or current.players[pid] == nil or ctx.traffic:openCount(pid) then return end
    local eligible = current.test or not current.cfg.trafficRunnerOnly or pid == current.runnerId
    local reserved = current.test and pid == current.issuerId and 3 or 1
    ctx.traffic:open(pid, ctx.traffic:allowance(current.cfg, reserved, eligible))
  end

  function game:carFor(pid)
    local current = self.current
    if pid == nil then return nil end
    local owner, vid = pid, nil
    if round.isAI(pid) then
      owner, vid = current.issuerId, self.aiCars[pid] and self.aiCars[pid].vid
    else
      vid = cars:vidFor(pid)
    end
    return cars:position(owner, vid)
  end

  function game:announceLightning(runner)
    local current = self.current
    local s = current.sky
    if not (s and s.strikeCursor) then return end
    local elapsed = s.lightningTimer:GetCurrent()
    local horizon = elapsed + 1.25
    s.lastRunnerPos = runner and runner.pos or s.lastRunnerPos
    local events = strikeSchedule.between(s.strikeCursor, s, math.max(s.lightningHorizon or 0, elapsed - 2), horizon)
    s.lightningHorizon = horizon
    if #events == 0 then return end
    local positions = {}
    for _, p in ipairs(s.lightningPositions or {}) do
      if p.at >= elapsed - 2 then positions[#positions + 1] = p end
    end
    local start = current.startGrid and current.startGrid[1]
    local ref = s.lastRunnerPos or start and start.pos or {x = 0, y = 0, z = 0}
    for _, event in ipairs(events) do
      local angle = math.rad(event.bearing)
      positions[#positions + 1] = {id = event.id, at = event.at, x = ref.x + event.range * math.sin(angle),
        y = ref.y + event.range * math.cos(angle), z = ref.z}
    end
    s.lightningPositions = positions
    send(current.test and current.issuerId or -1, "cnr_lightningPositions", {lightningSeed = s.lightningSeed, positions = positions})
  end

  function game:parkBystander(pid)
    local current = self.current
    if pid ~= current.issuerId then spectators:park(pid) end
  end

  function game:dispatchAISetup()
    local setup = self.pendingAISetup
    if not setup then return end
    local pid, payload = setup.pid, setup.payload
    if not payload.aiOnly and cars:placementPending(pid) then return end
    if setup.capacity then
      local occupied = 0
      for _ in pairs(cars:vehicles(pid)) do occupied = occupied + 1 end
      if occupied + #payload.ai > setup.capacity then return end
    end
    self.pendingAISetup = nil
    self.aiSpawnsLeft = payload.aiOnly and #payload.ai or 0
    send(pid, "cnr_setupAI", payload)
    if not payload.aiOnly and cars:confirmed(pid) then self:openTraffic(pid) end
  end

  function game:applyEffects(effects)
    local current = self.current
    for _, e in ipairs(effects) do
      if e.kind == "reply" then
        ctx.messages.reply(e.pid, e.msg, e.tone)
      elseif e.kind == "broadcast" then
        if e.meters then log(string.format("%s %.0f m", e.msg, e.meters)) end
        if e.to then ctx.messages.notify(e.to, e.msg, e.tone) else ctx.messages.broadcast(e.msg, e.tone) end
      elseif e.kind == "pickVehicle" then
        self.pendingAISetup = nil
        cars:requestPick(e.pid, { includeMods = current.cfg.includeModVehicles, excludedModels = current.cfg.excludedModels })
      elseif e.kind == "planStart" then
        send(e.pid, "cnr_planStart", { id = e.id, count = e.count, anchor = e.anchor,
          copSpawnMin = current.cfg.copSpawnMinMeters, copSpawnMax = current.cfg.copSpawnMaxMeters })
      elseif e.kind == "setup" then
        local anchor = e.startPose ~= nil and current.startGrid[1]
        local runnerCar = not anchor and self:carFor(current.runnerId)
        local delivered, reason = cars:setup(e.pid, {
          startPose = e.startPose,
          runnerId = current.runnerId, runnerName = current:runnerName(), role = e.role, copIndex = e.copIndex,
          model = current.vehicle.model, config = current.vehicle.config,
          phase = e.phase, countdownRemaining = e.countdownRemaining, chaseElapsed = e.chaseElapsed,
          headStartRemaining = e.headStartRemaining, inPlace = e.inPlace,
          color = e.colorHex and colors.parseHex(e.colorHex) or ctx.playerColors:get(e.pid),
          runnerPos = anchor and anchor.pos or runnerCar and runnerCar.pos or nil,
          copSpawnMin = current.cfg.copSpawnMinMeters, copSpawnMax = current.cfg.copSpawnMaxMeters,
          sightMaxMeters = current.cfg.sightMaxMeters,
          runnerShown = e.runnerShown, heli = e.heli,
          evolving = current.evolving or nil, rebuild = current.rebuildId, practice = current.test or nil,
          sky = sky.payload(current.sky, current.cfg, current:clockSeconds(now())),
        })
        if delivered == false then
          log(string.format("setup failed for %s: %s", MP.GetPlayerName(e.pid) or tostring(e.pid), tostring(reason)))
          local removedVid = cars:confirmedVid(e.pid)
          cars:removeParticipant(e.pid)
          self:applyEffects(current:setupFailed(now(), e.pid))
          if not current:isActive() then return end
          if removedVid then cars:publish() end
        else
          self:placing(e.pid)
          log(string.format("setup sent to %s: %s, %s", MP.GetPlayerName(e.pid) or tostring(e.pid), e.role, tostring(e.phase)))
          if e.role == "runner" and not current.test then
            local key = roster:key(e.pid)
            self.lastRunnerKey = key
            self.plannedRunnerKey = nil
            self.currentRunnerKey = key
          end
        end
      elseif e.kind == "spectate" then
        spectators:spectate(e.pid, {
          runnerId = current.runnerId, runnerName = current:runnerName(), phase = e.phase,
          countdownRemaining = e.countdownRemaining, headStartRemaining = e.headStartRemaining, chaseElapsed = e.chaseElapsed,
          heli = e.heli,
          sky = sky.payload(current.sky, current.cfg, current:clockSeconds(now())),
        }, e.phase)
      elseif e.kind == "setupAI" then
        for pid in pairs(MP.GetPlayers() or {}) do self:parkBystander(pid) end
        local list = {}
        for _, a in ipairs(e.ai) do
          list[#list + 1] = { id = a.id, role = a.role, index = current.startGrid and a.index or #list + 1, startPose = a.startPose, name = a.name, color = colors.parseHex(a.colorHex) }
        end
        if e.aiOnly then cars:rememberPreRound(e.pid) end
        self.aiSpawnsLeft = 0
        local capacity = traffic.maxCars()
        local payload = {
          model = current.vehicle.model, config = current.vehicle.config, ai = list,
          runnerId = current.runnerId, copSpawnMin = current.cfg.copSpawnMinMeters, copSpawnMax = current.cfg.copSpawnMaxMeters,
          aiOnly = e.aiOnly, sightMaxMeters = current.cfg.sightMaxMeters,
        }
        self.pendingAISetup = { pid = e.pid, payload = payload, deadline = now() + AI_SETUP_WAIT_SECONDS,
          capacity = capacity and capacity >= #list + (e.aiOnly and 0 or 1) and capacity or nil }
        self:dispatchAISetup()
      elseif e.kind == "countdown" then
        if sky.hasThunderstorm(current.sky) then
          current.sky.lightningTimer = MP.CreateTimer()
          current.sky.strikeCursor = strikeSchedule.new(current.sky.lightningSeed)
          self:announceLightning(self:carFor(current.runnerId))
        end
        send(e.to or -1, "cnr_countdown", { seconds = e.seconds })
      elseif e.kind == "runnerGo" then
        send(e.to or -1, "cnr_runnerGo", { headStartSeconds = e.headStartSeconds })
      elseif e.kind == "penalty" then
        local msg = string.format("%s: crash penalty %gs%s", tostring(e.name), e.seconds, e.cause == "traffic" and " (traffic)" or "")
        log(msg)
        send(current.test and current.issuerId or -1, "cnr_notice", { msg = msg, tone = "warn", about = e.pid })
        if round.isAI(e.pid) then
          send(current.issuerId, "cnr_penalty", { seconds = e.seconds, aiId = e.pid })
        else
          send(e.pid, "cnr_penalty", { seconds = e.seconds })
        end
      elseif e.kind == "penaltyEnd" then
        if round.isAI(e.pid) then
          send(current.issuerId, "cnr_penaltyEnd", { aiId = e.pid })
        else
          send(e.pid, "cnr_penaltyEnd", {})
        end
      elseif e.kind == "release" then
        send(e.to or -1, "cnr_release", {})
      elseif e.kind == "state" then
        send(e.pid, "cnr_state", { resetAllowed = e.resetAllowed, resetHint = e.resetHint, catchProgress = e.catchProgress })
      elseif e.kind == "roundEnd" then
        spectators:releaseAll()
        local autoNext = ctx.settings:get("autoNextRound") and e.reason ~= "cancelled" and not e.to
        send(e.to or -1, "cnr_roundEnd", {
          runnerId = e.runnerId, runnerName = e.runnerName, survivedSeconds = e.survivedSeconds,
          reason = e.reason, explode = e.explode, catchers = e.catchers, message = e.message,
          autoNextSeconds = autoNext and current.cfg.autoNextDelaySeconds or nil,
        })
        cars:setPublishing(false)
        cars:clearRound()
        roster:clear("trafficOpen")
        roster:clear("trafficVids")
        self.aiSpawnsLeft = 0
        self.pendingAISetup = nil
        cars:clearPublished()
        self.partsBaseline = {}
        self.missingCount = {}
        if not current.test and not e.to and e.reason ~= "cancelled" then
          self.lastResult = { runner = e.runnerName, seconds = e.survivedSeconds, reason = e.reason }
        end
        self.aiCars, self.aiSlotSerial, self.aiVidSerial = {}, {}, {}
        if autoNext then ctx.nextRound:schedule(now() + current.cfg.autoNextDelaySeconds) end
        ctx.useConfig(ctx.settings:effective())
        ctx.pushRules(nil, true)
      elseif e.kind == "live" then
        for pid in pairs(current.players) do
          if pid ~= current.runnerId and not round.isAI(pid) then
            local route = not (e.noRoute and e.noRoute[pid])
            send(pid, "cnr_lastSeen", { pos = e.pos, live = true, route = route })
          end
        end
        if not round.isAI(current.runnerId) and e.nearestCop then
          send(current.runnerId, "cnr_nearestCop", { dist = e.nearestCop })
        end
      elseif e.kind == "requestSetup" then
        send(e.pid, "cnr_requestSetup", {})
      elseif e.kind == "rebuild" then
        if self.pendingAISetup then self.pendingAISetup.payload.config = e.config end
        local targets = {}
        for pid in pairs(current.players) do
          if not round.isAI(pid) then
            self:placing(pid)
            targets[#targets + 1] = pid
          end
        end
        cars:rebuild(targets, { model = current.vehicle.model, config = e.config, rebuild = e.id }, e.id)
      elseif e.kind == "applied" then
        send(e.to or -1, "cnr_applied", {})
      elseif e.kind == "spotted" then
        if not round.isAI(current.runnerId) then send(current.runnerId, "cnr_spotted", { spotted = e.spotted }) end
      elseif e.kind == "lastSeen" then
        for pid in pairs(current.players) do
          if pid ~= current.runnerId and not round.isAI(pid) then
            send(pid, "cnr_lastSeen", { pos = e.pos })
          end
        end
        if not round.isAI(current.runnerId) and e.nearestCop then
          send(current.runnerId, "cnr_nearestCop", { dist = e.nearestCop })
        end
      elseif e.kind == "heli" then
        send(e.to or -1, "cnr_heli", { phase = e.phase, seconds = e.seconds, reason = e.reason, seed = e.seed, guided = e.guided })
      elseif e.kind == "runnerShown" then
        for pid in pairs(current.players) do
          if pid ~= current.runnerId and not round.isAI(pid) then
            send(pid, "cnr_runnerShown", { shown = e.shown })
          end
        end
      elseif e.kind == "nearestCop" then
        if not round.isAI(current.runnerId) then
          send(current.runnerId, "cnr_nearestCop", { dist = e.dist })
        end
      elseif e.kind == "record" then
        local run = e.run
        local endedAt = os.time()
        run.map = self.mapName
        run.releasedAt = endedAt - math.floor(run.survivedSeconds + 0.5)
        run.endedAt = endedAt
        run.key = self.currentRunnerKey
        run.cops, run.copNames, run.copSightSeconds = {}, {}, {}
        for i, pid in ipairs(run.copIds or {}) do
          run.cops[i] = roster:key(pid)
          run.copNames[i] = MP.GetPlayerName(pid) or tostring(pid)
          run.copSightSeconds[i] = math.floor((run.copSight[i] or 0) * 10 + 0.5) / 10
        end
        run.copIds, run.copSight = nil, nil
        if type(run.catchers) == "table" and #run.catchers > 0 then
          local byName = {}
          for pid, name in pairs(MP.GetPlayers() or {}) do byName[name] = pid end
          run.catcherKeys = {}
          for i, name in ipairs(run.catchers) do
            local pid = byName[name]
            run.catcherKeys[i] = pid and roster:key(pid) or ("name:" .. name)
          end
        end
        if self.currentRunnerKey then self.runCounts[self.currentRunnerKey] = (self.runCounts[self.currentRunnerKey] or 0) + 1 end
        self.plannedRunnerKey = nil
        ctx.saveLeaderboard(run)
        ctx.pushBoard()
        local top = leaderboard.runners(self.board, self.mapName, 3)
        for pid in pairs(MP.GetPlayers() or {}) do
          local viewerKey = roster:key(pid)
          local rows = {}
          for i, e in ipairs(top) do
            rows[i] = { rank = i, player = e.player, time = leaderboard.formatTime(e.survivedSeconds), me = e.key == viewerKey or nil }
          end
          send(pid, "cnr_top", { rows = rows })
        end
      end
    end
  end

  return game
end

return M
