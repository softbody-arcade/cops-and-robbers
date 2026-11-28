local colors = require("arcade.colors")
local leaderboard = require("cnr.leaderboard")
local panel = require("cnr.panel")
local round = require("cnr.round")
local rules = require("cnr.rules")
local sky = require("cnr.sky")
local strikeSchedule = require("cnr.strikeSchedule")
local commands = require("cnr.commands")
local config = require("cnr.config")
local tables = require("cnr.tables")
local build = require("cnr.build")
local vec = require("cnr.vec")
local trafficNote = require("cnr.traffic").note
local M = {}

function M.manifest(version)
  return {
    id = "cnr", name = "Cops and Robbers", version = version, minPlayers = 1,
    commands = panel.commands(), actions = { "build", "apply", "station", "stations" },
    clientEvents = {
      "cnr_startGridReady", "cnr_startGrid", "cnr_vehiclePicked", "cnr_stations", "cnr_myVehicle",
      "cnr_aiVehicles", "cnr_trafficCars", "cnr_color", "cnr_sitOut", "cnr_sight", "cnr_cover",
      "cnr_lightningClock", "cnr_board", "cnr_setup", "cnr_change", "cnr_missing",
    },
  }
end

function M.settingsDeclaration() return config.GAME end

local PARTS_PLACING_SECONDS, PARTS_SETTLE_SECONDS = 10, 3
local AI_SETUP_WAIT_SECONDS = 15

local function anonymous(key)
  local h = 5381
  for i = 1, #key do h = (h * 33 + key:byte(i)) % 4294967296 end
  return string.format("p%08x", h)
end

local BOARD_TOP = 20
local ROUNDS_DEFAULT, ROUNDS_STEP, ROUNDS_MAX = 30, 30, 300

local function normalizeConfig(path)
  if type(path) ~= "string" then return nil end
  return (path:gsub("\\", "/"):gsub("^/", ""):lower())
end

local function matchesRoundVehicle(current, decoded)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  return not pcFile or current.evolving or normalizeConfig(pcFile) == normalizeConfig(current.vehicle.config)
end

local function vehicleVerdict(allow, reason, roundCar)
  return { allow = allow, reason = reason, roundCar = roundCar, notify = allow }
end

function M.new(ctx)
  local game = {
    current = round.new(ctx.settings:effective()), mapName = ctx.map,
    leaderboardPath = ctx.dataDir .. "leaderboard.json",
    stations = {}, partsBaseline = {}, missingCount = {}, runCounts = {},
    aiCars = {}, aiSlotSerial = {}, aiVidSerial = {}, previousRoundSerial = 0, aiSpawnsLeft = 0,
    connectionSerial = ctx.roster:perPlayer("connectionSerial", "early"),
  }
  local cars, roster, spectators = ctx.cars, ctx.roster, ctx.spectators
  local send, log = ctx.messages.send, ctx.messages.log
  local now = ctx.clock.now
  local gridClients = roster:perPlayer("gridClients", "early")
  local stationsRequested = roster:perPlayer("stationsRequested", "early")
  local refuse, reply = ctx.messages.refuse, ctx.messages.reply
  local sharedRulesSignature
  local boardSubs = roster:perPlayer("boardSubs", "early")

  local function saveLeaderboard(run)
    leaderboard.add(game.board, run)
    if game.leaderboardLocked then return log("leaderboard not saved: the old file could not be moved aside") end
    local ok, err = ctx.store.writeJson(game.leaderboardPath, game.board)
    if not ok then
      log("could not save leaderboard.json: " .. err)
      table.remove(game.board.runs)
    end
  end

  local function boardState(sub, viewerKey)
    sub = type(sub) == "table" and sub or { map = game.mapName }
    local f = {
      map = sub.map ~= "all" and sub.map or nil,
      mode = (sub.mode == "random" or sub.mode == "evolving") and sub.mode or nil,
      traffic = (sub.traffic == "with" or sub.traffic == "runner" or sub.traffic == "without") and sub.traffic or nil,
    }
    local runners, mine = {}, nil
    for rank, entry in ipairs(leaderboard.runners(game.board, f, math.huge)) do
      if rank <= BOARD_TOP then
        runners[rank] = entry
      elseif entry.key == viewerKey then
        mine = { rank = rank, player = entry.player, survivedSeconds = entry.survivedSeconds, model = entry.model, map = entry.map }
        break
      end
    end
    for _, e in ipairs(runners) do
      if e.key == viewerKey then e.me = true end
      e.key = nil
    end
    local cops = leaderboard.cops(game.board, f, BOARD_TOP, game.current.cfg.assistMinSightPercent)
    for _, c in ipairs(cops) do
      if c.key == viewerKey then c.me = true end
      c.key = nil
    end
    local players = leaderboard.players(game.board, f, game.current.cfg.assistMinSightPercent)
    for _, p in ipairs(players) do
      if p.key == viewerKey then p.me = true end
      p.key = anonymous(tostring(p.key))
    end
    local limit = sub.rounds or ROUNDS_DEFAULT
    local rounds, total = leaderboard.rounds(game.board, f, limit)
    for _, r in ipairs(rounds) do
      r.playerKey = anonymous(tostring(r.playerKey))
      for _, c in ipairs(r.cops) do c.key = anonymous(tostring(c.key)) end
    end
    return {
      map = game.mapName, maps = leaderboard.maps(game.board), filter = sub.map or game.mapName, mode = f.mode or "all", traffic = f.traffic or "all",
      runners = runners, cops = cops, players = players, mine = mine,
      rounds = rounds, moreRounds = (total > #rounds and limit < ROUNDS_MAX) or nil,
    }
  end

  local function sendBoard(pid)
    local ok, state = pcall(boardState, boardSubs[pid], roster:key(pid))
    if ok then send(pid, "cnr_boardState", state) else log("board update failed: " .. tostring(state)) end
  end

  local function pushBoard()
    for pid in pairs(boardSubs) do sendBoard(pid) end
  end

  function game:updateBoard(pid, msg)
    if msg.action == "close" then
      boardSubs[pid] = nil
    elseif msg.action == "open" or msg.action == "filter" then
      local sub = boardSubs[pid] or { map = game.mapName }
      if msg.action == "filter" then
        sub = {
          map = type(msg.map) == "string" and msg.map or sub.map, mode = type(msg.mode) == "string" and msg.mode or nil,
          traffic = type(msg.traffic) == "string" and msg.traffic or nil, rounds = sub.rounds,
        }
      end
      boardSubs[pid] = sub
      sendBoard(pid)
    elseif msg.action == "more" and boardSubs[pid] then
      local sub = boardSubs[pid]
      sub.rounds = math.min((sub.rounds or ROUNDS_DEFAULT) + ROUNDS_STEP, ROUNDS_MAX)
      sendBoard(pid)
    end
  end

  function game:pushRules(pid, onlyChanged)
    local cfg = self.current.cfg
    local payload = rules.payload(cfg, ctx.traffic:allowance(cfg, 1, true))
    local signature = panel.signature(payload)
    if onlyChanged and signature == sharedRulesSignature then return end
    send(pid or -1, "cnr_rules", payload)
    if not pid then
      sharedRulesSignature = signature
    elseif signature ~= sharedRulesSignature then
      sharedRulesSignature = nil
    end
  end

  function game:roundFinished()
    self.current.cfg = ctx.settings:effective()
    self:pushRules(nil, true)
  end

  function game:rulesChanged()
    if not self.current:isActive() then self.current.cfg = ctx.settings:effective() end
    self:pushRules()
  end

  function game:settingsChanged(keys)
    self:rulesChanged()
    ctx.panel:push()
    pushBoard()
  end

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
          log(string.format("setup failed for %s: %s", roster:name(e.pid) or tostring(e.pid), tostring(reason)))
          local removedVid = cars:confirmedVid(e.pid)
          cars:removeParticipant(e.pid)
          self:applyEffects(current:setupFailed(now(), e.pid))
          if not current:isActive() then return end
          if removedVid then cars:publish() end
        else
          self:placing(e.pid)
          log(string.format("setup sent to %s: %s, %s", roster:name(e.pid) or tostring(e.pid), e.role, tostring(e.phase)))
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
        for pid in pairs(roster:players()) do self:parkBystander(pid) end
        local list = {}
        for _, a in ipairs(e.ai) do
          list[#list + 1] = { id = a.id, role = a.role, index = current.startGrid and a.index or #list + 1, startPose = a.startPose, name = a.name, color = colors.parseHex(a.colorHex) }
        end
        if e.aiOnly then cars:rememberPreRound(e.pid) end
        self.aiSpawnsLeft = 0
        local capacity = ctx.traffic:maxCars()
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
          current.sky.lightningTimer = ctx.clock.timer()
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
        local hasResult = not current.test and not e.to and e.reason ~= "cancelled"
        ctx.round:finish({
          runnerId = e.runnerId, runnerName = e.runnerName, survivedSeconds = e.survivedSeconds,
          reason = e.reason, explode = e.explode, catchers = e.catchers, message = e.message,
        }, e.to or -1, hasResult)
        self.aiSpawnsLeft = 0
        self.pendingAISetup = nil
        self.partsBaseline = {}
        self.missingCount = {}
        if hasResult then
          self.lastResult = { runner = e.runnerName, seconds = e.survivedSeconds, reason = e.reason }
        end
        self.aiCars, self.aiSlotSerial, self.aiVidSerial = {}, {}, {}
        self.previousRoundSerial = 0
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
        local endedAt = ctx.clock.unixTime()
        run.map = self.mapName
        run.releasedAt = endedAt - math.floor(run.survivedSeconds + 0.5)
        run.endedAt = endedAt
        run.key = self.currentRunnerKey
        run.cops, run.copNames, run.copSightSeconds = {}, {}, {}
        for i, pid in ipairs(run.copIds or {}) do
          run.cops[i] = roster:key(pid)
          run.copNames[i] = roster:name(pid) or tostring(pid)
          run.copSightSeconds[i] = math.floor((run.copSight[i] or 0) * 10 + 0.5) / 10
        end
        run.copIds, run.copSight = nil, nil
        if type(run.catchers) == "table" and #run.catchers > 0 then
          local byName = {}
          for pid, name in pairs(roster:players()) do byName[name] = pid end
          run.catcherKeys = {}
          for i, name in ipairs(run.catchers) do
            local pid = byName[name]
            run.catcherKeys[i] = pid and roster:key(pid) or ("name:" .. name)
          end
        end
        if self.currentRunnerKey then self.runCounts[self.currentRunnerKey] = (self.runCounts[self.currentRunnerKey] or 0) + 1 end
        self.plannedRunnerKey = nil
        saveLeaderboard(run)
        pushBoard()
        local top = leaderboard.runners(self.board, self.mapName, 3)
        for pid in pairs(roster:players()) do
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

  local function buildOpts()
    local currentBuild = game.currentBuild
    if not currentBuild then return nil end
    return {
      model = currentBuild.model, step = currentBuild.step, name = currentBuild.name,
      config = { format = 2, model = currentBuild.model, parts = currentBuild.parts, vars = currentBuild.vars },
    }
  end

  function game:roundCarActive()
    local current = game.current
    return current.vehicle ~= nil and current.state ~= "idle" and current.state ~= "picking"
  end

  function game:aiSlotForVid(vid)
    for id, car in pairs(self.aiCars) do
      if car.vid == vid then return id end
    end
  end

  function game:removeAICar(id)
    if id and self.aiCars[id] then
      self.aiCars[id] = nil
      self.current:forgetVehicleSight(id)
    end
  end

  local function checkParts(pid, decoded, at)
    local current = game.current
    if not decoded or type(decoded.vcf) ~= "table" or decoded.vcf.parts == nil then return end
    local parts = decoded.vcf.parts
    local entry = game.partsBaseline[pid]
    local mayChange = current.evolving and (current.state == "prep" or current.state == "applying") and pid == current.runnerId
    if entry == nil then
      game.partsBaseline[pid] = { parts = parts, announced = false }
    elseif entry.parts == nil or mayChange or (entry.quietUntil and at < entry.quietUntil) then
      entry.parts = parts
    elseif not tables.deepEqual(parts, entry.parts) then
      if not entry.announced then
        entry.announced = true
        local msg = string.format("⚠ %s changed parts during the round: %s", MP.GetPlayerName(pid) or tostring(pid), tables.diffKeys(entry.parts, parts, 5))
        log(msg)
        current:note(at, "partsChanged", MP.GetPlayerName(pid) or tostring(pid))
        if current.test then ctx.messages.notify(current.issuerId, msg, "warn") else ctx.messages.broadcast(msg, "warn") end
      end
      entry.parts = parts
    end
  end

  function game:checkVehicle(kind, pid, vid, decoded, facts)
    local current = self.current
    local spawn = kind == "spawn"
    if spawn and current.vehicle and not current.test and current.players[pid] == nil then
      return vehicleVerdict(false, "You can't spawn a car while spectating")
    end
    if not spawn and (facts.preRound or (facts.confirmed and vid ~= facts.activeVid
        and (pid ~= current.issuerId or not self:aiSlotForVid(vid)))) then
      return { allow = true, notify = false }
    end
    if current:isActive() and current.aiOnly and pid == current.issuerId then
      local watching = spawn and "You can't spawn a car while watching the AI" or nil
      if current.state == "picking" then return vehicleVerdict(not spawn, watching) end
      local model = current.vehicle and current.vehicle.model
      if not model or not decoded or decoded.jbm ~= model or (spawn and self.aiSpawnsLeft <= 0) then
        return vehicleVerdict(false, watching)
      end
      return vehicleVerdict(true)
    end
    local roundPlayer = self:roundCarActive() and current.players[pid] ~= nil
    local roundSpawn = spawn and roundPlayer and not current.test
    if roundSpawn and (facts.permitted or facts.replacementAllowed) then
      if matchesRoundVehicle(current, decoded) then return vehicleVerdict(true, nil, true) end
      if not facts.activeVid or not facts.trafficOpen then return vehicleVerdict(false) end
    end
    if current:isActive() and facts.trafficOpen and current.players[pid] ~= nil and vid ~= facts.activeVid then
      if not spawn or (current.test and pid == current.issuerId) then return vehicleVerdict(true) end
      local room = facts.activeVid ~= nil and ctx.traffic:extraCars(pid, facts.activeVid) < facts.trafficOpen
      return vehicleVerdict(room, nil, false)
    end
    if not roundPlayer then return vehicleVerdict(true) end
    if not matchesRoundVehicle(current, decoded) then return vehicleVerdict(false) end
    if roundSpawn and cars:firstVid(pid) then return vehicleVerdict(false) end
    return vehicleVerdict(true)
  end

  function game:onVehicle(kind, pid, vid, decoded, facts, at)
    local current = self.current
    if kind == "replaced" then
      current:forgetVehicleSight(pid)
    elseif kind == "delete" then
      if pid == current.issuerId then self:removeAICar(self:aiSlotForVid(vid)) end
    elseif kind == "reset" then
      if (facts.activeVid or facts.confirmed or facts.trafficOpen) and facts.activeVid ~= vid then return end
      self:applyEffects(current:vehicleReset(at, pid))
    else
      if kind == "edit" then
        local notOwn = vid ~= facts.activeVid and (current.test or facts.trafficOpen)
        if self:roundCarActive() and current.players[pid] and not notOwn then checkParts(pid, decoded, at) end
      elseif current:isActive() and current.aiOnly and pid == current.issuerId then
        self.aiSpawnsLeft = self.aiSpawnsLeft - 1
      end
      if current:isActive() and not (current.test and pid == current.issuerId)
          and not facts.confirmed and not facts.trafficOpen and cars:activeVid(pid) ~= vid then
        cars:setActive(pid, vid)
      end
    end
  end

  local function stationsPath() return ctx.dataDir .. "stations/" .. game.mapName .. ".json" end

  function game:loadStations()
    local decoded = ctx.store.decode(stationsPath())
    game.stations = {}
    for _, s in ipairs(decoded and decoded.stations or {}) do
      local v = vec.toVec(s)
      if v then
        v.r = tonumber(s.r) or 0
        game.stations[#game.stations + 1] = v
      end
    end
    log(string.format("%d gas stations loaded for %s", #game.stations, game.mapName))
  end

  function game:saveStations(updated)
    local ok, err = ctx.store.writeJson(stationsPath(), { stations = updated })
    if not ok then
      log("could not save " .. game.mapName .. ".json: " .. err)
      return nil, err
    end
    game.stations = updated
    return true
  end

  function game:requestStations(pid)
    if #game.stations > 0 or stationsRequested[pid] then return end
    stationsRequested[pid] = true
    send(pid, "cnr_requestStations", { map = game.mapName })
  end

  local function plannedRunner(players)
    local countsByName = {}
    for p, name in pairs(players) do countsByName[name] = game.runCounts[roster:key(p)] or 0 end
    local lastPid = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
    local lastName = lastPid and roster:name(lastPid) or nil
    local eligible = commands.eligibleNext(players, countsByName, lastName)
    if game.plannedRunnerKey then
      for _, p in ipairs(eligible) do
        if roster:key(p) == game.plannedRunnerKey then return p end
      end
    end
    local pid = commands.matchPlayer("next", players, nil, countsByName, lastName)
    game.plannedRunnerKey = pid and roster:key(pid) or nil
    return pid
  end

  function game:gridReady(pid)
    gridClients[pid] = true
  end

  local function reject(pid, reason)
    refuse(pid, reason)
    return nil, reason
  end

  function game:canStart(request)
    local pid, command = request.issuer, request.command
    local current = self.current
    local practice = command == "test"
    if not practice and current:isActive() and current.test then
      self:applyEffects(current:stop(now(), current.issuerId))
    end
    if current:isActive() then return reject(pid, "A round is already running") end
    if current.cfg.carMode == "evolving" and not self.currentBuild then return reject(pid, "Start a new build first") end
    local players = roster:players()
    if practice then
      local aiOnly = roster:sittingOut(pid)
      local role = request.text
      if not aiOnly and role ~= "runner" and role ~= "cop" then return reject(pid, "Pick practice as runner or as cop") end
      return { participants = aiOnly and {} or { pid }, solo = true, role = role, aiOnly = aiOnly, issuer = pid, players = players }
    end
    ctx.autoRounds:cancel()
    local participants = roster:playingList(players)
    if #participants == 0 then return reject(pid, "Everyone is sitting out") end
    local candidates = roster:playing(players)
    local query = command == "next" and "next" or request.text
    local runnerId, err
    if query and query:lower() == "again" then
      runnerId = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
      if not runnerId then return reject(pid, "No previous runner online") end
    else
      if query and query:lower() == "next" then
        runnerId = plannedRunner(candidates)
      else
        runnerId, err = commands.matchPlayer(query, candidates)
      end
      if not runnerId then
        local anyone = commands.matchPlayer(query, players)
        if anyone and roster:sittingOut(anyone) then runnerId = anyone end
      end
    end
    if not runnerId then return reject(pid, err) end
    if roster:sittingOut(runnerId) then return reject(pid, string.format("%s is sitting out", players[runnerId] or tostring(runnerId))) end
    return { participants = participants, issuer = pid, runnerId = runnerId, players = players }
  end

  function game:start(prepared, snapshot, startedAt)
    local pid, runnerId = prepared.issuer, prepared.runnerId
    if not prepared.solo then self:requestStations(pid) end
    cars:clearRound()
    ctx.traffic:clearRound()
    self.partsBaseline, self.missingCount = {}, {}
    self.current = round.new(snapshot)
    local planner = prepared.solo and pid or runnerId
    local opts = {
      gridPlanner = gridClients[planner] and planner,
      build = snapshot.carMode == "evolving" and buildOpts() or nil,
      sky = sky.pick(snapshot, math.random),
    }
    if prepared.solo then
      self.previousRoundSerial = self.connectionSerial[pid] or 0
      opts.test, opts.role, opts.aiOnly = true, prepared.role, prepared.aiOnly
    else
      self.lastResult = nil
      opts.traffic = ctx.traffic:allowance(snapshot, 1, true)
      opts.trafficRunnerOnly = snapshot.trafficRunnerOnly == true
      opts.sittingOut = roster:sitOutSnapshot()
    end
    self:applyEffects(self.current:start(startedAt, runnerId, pid, prepared.players, opts))
  end

  local function startCommand(pid, cmd)
    ctx.round:start({ issuer = pid, command = cmd.name, text = cmd.rest })
  end

  ctx.panel:command("start", startCommand)
  ctx.panel:command("test", startCommand)

  function game:lobbyFields()
    local current = game.current
    local players = roster:players()
    local online = 0
    for _ in pairs(players) do online = online + 1 end
    local practice
    if current:isActive() and current.test then practice = current.players[current.issuerId] or roster:name(current.issuerId) or "someone" end
    return { online = online, practice = practice, active = current:isActive() and not current.test or false }
  end

  ctx.panel:command("go", function(pid)
    game:applyEffects(game.current:go(now(), pid))
  end)

  ctx.panel:command("stop", function(pid)
    local current = game.current
    local wasActive = current:isActive()
    game:applyEffects(current:stop(now(), pid))
    if not wasActive then send(-1, "cnr_roundEnd", { reason = "cancelled" }) end
  end)

  ctx.panel:command("end", function(pid)
    game:applyEffects(game.current:endCalled(now(), pid))
  end)

  ctx.panel:command("reroll", function(pid)
    game:applyEffects(game.current:reroll(now(), pid))
  end)

  ctx.panel:command("sky", function(pid)
    local current = game.current
    if current.state ~= "prep" and current.state ~= "ready" then return refuse(pid, "You can only change the sky before GO") end
    local cfg = current.cfg
    if not sky.hasRandom(cfg) then return refuse(pid, "Set time of day or weather to random first") end
    local before = current.sky or {}
    local picked = sky.pick(cfg, math.random)
    for _ = 1, 10 do
      if picked.time ~= before.time or picked.weather ~= before.weather then break end
      picked = sky.pick(cfg, math.random)
    end
    current.sky = picked
    local data = sky.payload(current.sky, cfg, nil)
    local targets = current.test and { [current.issuerId] = true } or roster:players()
    for p in pairs(targets) do send(p, "cnr_sky", data) end
  end)

  ctx.panel:command("addstation", function(pid)
    local car = game:carFor(pid)
    if not car then return refuse(pid, "You need to be in a vehicle") end
    local updated = table.move(game.stations, 1, #game.stations, 1, {})
    updated[#updated + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
    local ok, err = game:saveStations(updated)
    if not ok then return refuse(pid, err) end
    reply(pid, string.format("Gas station added (%d on %s)", #game.stations, game.mapName))
  end)

  ctx.panel:command("removestation", function(pid)
    local car = game:carFor(pid)
    if not car then return refuse(pid, "You need to be in a vehicle") end
    local bestIndex, bestDist
    for i, s in ipairs(game.stations) do
      local d = vec.dist(car.pos, s)
      if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
    end
    if not bestIndex then return refuse(pid, "No gas station within 50 m") end
    local updated = table.move(game.stations, 1, #game.stations, 1, {})
    table.remove(updated, bestIndex)
    local ok, err = game:saveStations(updated)
    if not ok then return refuse(pid, err) end
    reply(pid, string.format("Gas station removed (%d left on %s)", #game.stations, game.mapName))
  end)

  local function nextRunnerName(players)
    local pid = plannedRunner(players)
    return pid and players[pid] or nil
  end

  local function playerEntries(players, realRound)
    local current = game.current
    local entries, loading = {}, 0
    for pid, name in pairs(players) do
      local entry = { name = name, runs = game.runCounts[roster:key(pid)] or 0, sitOut = roster:sittingOut(pid) or nil }
      if realRound and current.players[pid] ~= nil then
        local isRunner = pid == current.runnerId
        entry.role = isRunner and "runner" or "cop"
        local placingNow = game.partsBaseline[pid] and game.partsBaseline[pid].placing
        if placingNow then loading = loading + 1 end
        local changes = current.queued and current.queued.changes
        if placingNow then
          entry.state = "loading"
        elseif game.missingCount[pid] then
          entry.state, entry.missing = "missing", game.missingCount[pid]
        elseif isRunner and current.evolving and current.state == "prep" and changes and changes[1] then
          entry.state, entry.change = "changing", tostring(changes[1].label)
        else
          entry.state = "ready"
        end
      end
      entries[#entries + 1] = entry
    end
    return entries, loading
  end

  function game:panelState()
    local current = self.current
    local cfg = current.cfg
    local running = current.state == "running"
    local players = roster:players()
    local candidates, count = roster:playing(players)
    local realRound = current:isActive() and not current.test
    local entries, loading = playerEntries(players, realRound)
    local nextName = not realRound and nextRunnerName(candidates) or nil
    local lastPid = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
    local autoNext
    local autoNextAt = ctx.autoRounds:pending()
    if autoNextAt and not realRound then
      autoNext = { seconds = math.max(0, math.ceil(autoNextAt - now())), runner = nextName }
    end
    local buildInfo
    local currentBuild = game.currentBuild
    if currentBuild then
      buildInfo = { label = build.label(currentBuild), step = currentBuild.step, name = currentBuild.name, lastChange = build.lastChange(currentBuild) }
    end
    return panel.snapshot({
      version = ctx.version, map = game.mapName, phase = current.state,
      runner = current.runnerId and current:runnerName() or nil,
      car = self:roundCarActive() and current.vehicle.model or nil,
      test = current.test == true,
      elapsed = running and current.releasedAt and math.max(0, now() - current.releasedAt) or nil,
      players = entries, cfg = cfg, defaults = config.DEFAULTS,
      autoNextRound = ctx.settings:get("autoNextRound"),
      evolving = current.evolving == true,
      build = buildInfo,
      nextRunner = nextName, lastRunner = lastPid and players[lastPid] or nil,
      loading = loading, autoNext = autoNext, lastResult = game.lastResult,
      stationCount = #game.stations,
      skyRandom = sky.hasRandom(cfg),
      trafficNote = trafficNote(cfg.trafficPerPlayer, ctx.traffic:maxCars(), count, cfg.trafficRunnerOnly == true),
    })
  end

  function game:tick(tickAt)
    local current = self.current
    game:dispatchAISetup()
    if game.pendingAISetup and tickAt >= game.pendingAISetup.deadline then
      local pid = game.pendingAISetup.pid
      local waitingForCar = not game.pendingAISetup.payload.aiOnly and cars:placementPending(pid)
      game:applyEffects(current:stop(tickAt, pid))
      ctx.messages.notify(pid, waitingForCar and "Practice cancelled: your round car did not register in time."
        or "Practice cancelled: too few free vehicle slots for the AI. Free a slot or increase MaxCars.", "warn")
      return
    end
    local positions = {}
    for pid in pairs(current.players) do positions[pid] = game:carFor(pid) end
    game:announceLightning(positions[current.runnerId])
    game:applyEffects(current:tick(tickAt, positions, game.stations, ctx.traffic:cars()))
  end

  return game
end

return M
