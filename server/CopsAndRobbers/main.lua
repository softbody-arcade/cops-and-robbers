local pluginDir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./")
package.path = pluginDir .. "?.lua;" .. package.path

local store = require("arcade.store")
local messages = require("arcade.messages").new({ prefix = "[CnR] " })
local roster = require("arcade.roster").new()
local vec = require("cnr.vec")
local config = require("cnr.config")
local rules = require("cnr.rules")
local round = require("cnr.round")
local leaderboard = require("cnr.leaderboard")
local commands = require("cnr.commands")
local colors = require("arcade.colors")
local tables = require("cnr.tables")
local build = require("cnr.build")
local panel = require("cnr.panel")
local panelService = require("arcade.panel").new(messages, roster)
local autoRounds = require("arcade.autoRounds")
local nextRound = autoRounds.new()
local sky = require("cnr.sky")
local strikeSchedule = require("cnr.strikeSchedule")
local traffic = require("arcade.traffic")
local trafficService = traffic.new(roster, messages)
local trafficNote = require("cnr.traffic").note

local VERSION = "2.16.0"
local log, send, notify = messages.log, messages.send, messages.notify
local reply, refuse, broadcast = messages.reply, messages.refuse, messages.broadcast
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
local leaderboardPath = dataDir .. "leaderboard.json"
local buildPath = dataDir .. "build.json"
local currentBuild
local settings = require("arcade.settings").new(pluginDir .. "config.json", config.declaration, log)
local playerColors = require("arcade.playerColors").new(dataDir .. "colors.json", roster, messages)

local cfg
local current
local board
local mapName
local stations = {}
local activeVid = roster:perPlayer("activeVid", "late")
local registeredRoundCar = roster:perPlayer("registeredRoundCar", "late")
local allowRoundSpawn = roster:perPlayer("allowRoundSpawn", "late")
local preRoundVehicles = roster:perPlayer("preRoundVehicles", "late")
local lastRoundCars
local stationsRequested = roster:perPlayer("stationsRequested", "early")
local partsBaseline = {}
local aiCars = {}
local aiSlotSerial, aiVidSerial = {}, {}
local connectionSerial = roster:perPlayer("connectionSerial", "early")
local previousRoundSerial = 0
local runCounts = {}
local lastRunnerKey
local plannedRunnerKey
local missingCount = {}
local lastResult
local currentRunnerKey
local lastIssuer
local PARTS_PLACING_SECONDS, PARTS_SETTLE_SECONDS = 10, 3
local REFUSAL_LOG_SECONDS = 10
local refusalLoggedAt = roster:perPlayer("refusalLoggedAt", "early")
local parkedBystanders = roster:perPlayer("parkedBystanders", "early")
local aiSpawnsLeft = 0
local pendingAISetup
local AI_SETUP_WAIT_SECONDS = 15
local gridClients = roster:perPlayer("gridClients", "early")
local START_ROAD_SEARCH = 2000
local WATCHING_AI = "You can't spawn a car while watching the AI"
local serverClock = MP.CreateTimer()

math.randomseed(os.time())

local function now() return serverClock:GetCurrent() end

local function placing(pid)
  local entry = partsBaseline[pid] or {}
  partsBaseline[pid] = { announced = entry.announced, quietUntil = now() + PARTS_PLACING_SECONDS, placing = true }
end

local function placed(pid)
  local entry = partsBaseline[pid]
  if entry and entry.placing then
    entry.placing = nil
    entry.quietUntil = now() + PARTS_SETTLE_SECONDS
  end
end

local boardSubs = roster:perPlayer("boardSubs", "early")
local leaderboardLocked = false

local function useConfig(values)
  cfg = values
  current.cfg = values
end

local function loadLeaderboard()
  local decoded, corrupt = store.decode(leaderboardPath)
  if corrupt or not leaderboard.validShape(decoded) then
    local aside = leaderboardPath .. ".corrupt-" .. os.time()
    local moved, err = FS.Rename(leaderboardPath, aside)
    if moved == false then
      leaderboardLocked = true
      log(string.format("leaderboard.json was unreadable but could not be moved to %s (%s): runs are not saved until this is fixed", aside, tostring(err)))
    else
      log(string.format("leaderboard.json was unreadable, moved to %s; starting a fresh one", aside))
    end
    decoded = nil
  end
  board = leaderboard.load(decoded)
end

local function loadBuild()
  local decoded, corrupt = store.decode(buildPath)
  currentBuild = not corrupt and build.normalize(decoded) or nil
  if decoded ~= nil and not currentBuild or corrupt then
    local aside = buildPath .. ".corrupt-" .. os.time()
    FS.Rename(buildPath, aside)
    log("build.json was unreadable, moved to " .. aside .. "; no build")
  elseif currentBuild then
    log("Build: " .. build.label(currentBuild))
  end
end

local function saveError(path, err)
  log("could not save " .. path:match("[^/\\]+$") .. ": " .. err)
  return nil, err
end

local function saveJson(path, value)
  local ok, err = store.writeJson(path, value)
  if not ok then return saveError(path, err) end
  return true
end

local function backupBuild()
  if not FS.Exists(buildPath) then return true end
  local base = dataDir .. "build-" .. os.time()
  local aside, n = base .. ".json", 1
  while FS.Exists(aside) do
    n = n + 1
    aside = string.format("%s-%d.json", base, n)
  end
  local moved, err = FS.Rename(buildPath, aside)
  if not moved then return saveError(buildPath, err or "rename failed") end
  return true, aside
end

local function buildOpts()
  if not currentBuild then return nil end
  return {
    model = currentBuild.model, step = currentBuild.step, name = currentBuild.name,
    config = { format = 2, model = currentBuild.model, parts = currentBuild.parts, vars = currentBuild.vars },
  }
end

local function saveLeaderboard(run)
  leaderboard.add(board, run)
  if leaderboardLocked then return log("leaderboard not saved: the old file could not be moved aside") end
  if not saveJson(leaderboardPath, board) then table.remove(board.runs) end
end

local function roundCarActive()
  return current.vehicle ~= nil and current.state ~= "idle" and current.state ~= "picking"
end

local function stationsPath() return stationsDir .. mapName .. ".json" end

local function loadStations()
  local decoded = store.decode(stationsPath())
  stations = {}
  for _, s in ipairs(decoded and decoded.stations or {}) do
    local v = vec.toVec(s)
    if v then
      v.r = tonumber(s.r) or 0
      stations[#stations + 1] = v
    end
  end
  log(string.format("%d gas stations loaded for %s", #stations, mapName))
end

local function saveStations(updated)
  local ok, err = saveJson(stationsPath(), { stations = updated })
  if not ok then return nil, err end
  stations = updated
  return true
end

local function requestStations(pid)
  if #stations > 0 or stationsRequested[pid] then return end
  stationsRequested[pid] = true
  send(pid, "cnr_requestStations", { map = mapName })
end

local function parseVehicleData(data)
  if type(data) ~= "string" then return nil end
  local start = data:find("{", 1, true)
  if not start then return nil end
  local json = data:sub(start)
  local ok, decoded = pcall(Util.JsonDecode, json)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

local function firstVid(pid)
  local vehicles = MP.GetPlayerVehicles(pid)
  if type(vehicles) ~= "table" then return nil end
  local best
  for vid in pairs(vehicles) do
    if not best or vid < best then best = vid end
  end
  return best
end

local function vidFor(pid)
  local vid = activeVid[pid]
  if vid then return vid end
  if registeredRoundCar[pid] or trafficService:openCount(pid) then return nil end
  vid = firstVid(pid)
  activeVid[pid] = vid
  return vid
end

local function openTraffic(pid)
  if not current:isActive() or current.players[pid] == nil or trafficService:openCount(pid) then return end
  local eligible = current.test or not cfg.trafficRunnerOnly or pid == current.runnerId
  local reserved = current.test and pid == current.issuerId and 3 or 1
  trafficService:open(pid, trafficService:allowance(cfg, reserved, eligible))
end

local function confirmedVid(pid)
  return registeredRoundCar[pid] and activeVid[pid]
end

local function setRoundVid(pid, vid)
  if registeredRoundCar[pid] and activeVid[pid] ~= vid then current:forgetVehicleSight(pid) end
  activeVid[pid] = vid
end

local function roundCarKeys()
  local keys = {}
  for p in pairs(current.players) do
    local vid = confirmedVid(p)
    if vid then keys[#keys + 1] = p .. "-" .. vid end
  end
  table.sort(keys)
  return keys
end

local function pushRoundCars(pid)
  if not current:isActive() then return end
  local keys = roundCarKeys()
  if pid then return send(pid, "cnr_roundCars", { keys = keys }) end
  local sig = table.concat(keys, ",")
  if sig == lastRoundCars then return end
  lastRoundCars = sig
  send(-1, "cnr_roundCars", { keys = keys })
end

local function clearRoundCars()
  if lastRoundCars and lastRoundCars ~= "" then send(-1, "cnr_roundCars", { keys = {} }) end
  lastRoundCars = nil
end

local function aiSlotForVid(vid)
  for id, car in pairs(aiCars) do
    if car.vid == vid then return id end
  end
end

local function removeAICar(id)
  if id and aiCars[id] then
    aiCars[id] = nil
    current:forgetVehicleSight(id)
  end
end

local function carFor(pid)
  if pid == nil then return nil end
  local owner, vid = pid, nil
  if round.isAI(pid) then
    owner, vid = current.issuerId, aiCars[pid] and aiCars[pid].vid
  else
    vid = vidFor(pid)
  end
  if not owner or not vid then return nil end
  local raw, err = MP.GetPositionRaw(owner, vid)
  if err and err ~= "" or type(raw) ~= "table" then return nil end
  local pos, vel = vec.toVec(raw.pos), vec.toVec(raw.vel)
  if not pos or not vel then return nil end
  return { pos = pos, vel = vel }
end

local function announceLightning(runner)
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

local function normalizeConfig(path)
  if type(path) ~= "string" then return nil end
  return (path:gsub("\\", "/"):gsub("^/", ""):lower())
end

local function anonymous(key)
  local h = 5381
  for i = 1, #key do h = (h * 33 + key:byte(i)) % 4294967296 end
  return string.format("p%08x", h)
end

local BOARD_TOP = 20
local ROUNDS_DEFAULT, ROUNDS_STEP, ROUNDS_MAX = 30, 30, 300

local function boardState(sub, viewerKey)
  sub = type(sub) == "table" and sub or { map = mapName }
  local f = {
    map = sub.map ~= "all" and sub.map or nil,
    mode = (sub.mode == "random" or sub.mode == "evolving") and sub.mode or nil,
    traffic = (sub.traffic == "with" or sub.traffic == "runner" or sub.traffic == "without") and sub.traffic or nil,
  }
  local runners, mine = {}, nil
  for rank, entry in ipairs(leaderboard.runners(board, f, math.huge)) do
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
  local cops = leaderboard.cops(board, f, BOARD_TOP, cfg.assistMinSightPercent)
  for _, c in ipairs(cops) do
    if c.key == viewerKey then c.me = true end
    c.key = nil
  end
  local players = leaderboard.players(board, f, cfg.assistMinSightPercent)
  for _, p in ipairs(players) do
    if p.key == viewerKey then p.me = true end
    p.key = anonymous(tostring(p.key))
  end
  local limit = sub.rounds or ROUNDS_DEFAULT
  local rounds, total = leaderboard.rounds(board, f, limit)
  for _, r in ipairs(rounds) do
    r.playerKey = anonymous(tostring(r.playerKey))
    for _, c in ipairs(r.cops) do c.key = anonymous(tostring(c.key)) end
  end
  return {
    map = mapName, maps = leaderboard.maps(board), filter = sub.map or mapName, mode = f.mode or "all", traffic = f.traffic or "all",
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

local function parkBystander(pid)
  if pid == current.issuerId or parkedBystanders[pid] then return end
  if send(pid, "cnr_parkBystanderCars", { on = true }) ~= false then parkedBystanders[pid] = true end
end

local function rememberPreRoundVehicles(pid)
  if registeredRoundCar[pid] or preRoundVehicles[pid] then return end
  local existing = {}
  local vehicles = MP.GetPlayerVehicles(pid)
  if type(vehicles) == "table" then
    for vid in pairs(vehicles) do existing[vid] = true end
  end
  preRoundVehicles[pid] = existing
end

local function dispatchAISetup()
  local setup = pendingAISetup
  if not setup then return end
  local pid, payload = setup.pid, setup.payload
  if not payload.aiOnly and allowRoundSpawn[pid] then return end
  if setup.capacity then
    local vehicles = MP.GetPlayerVehicles(pid)
    local occupied = 0
    if type(vehicles) == "table" then
      for _ in pairs(vehicles) do occupied = occupied + 1 end
      if occupied + #payload.ai > setup.capacity then return end
    end
  end
  pendingAISetup = nil
  aiSpawnsLeft = payload.aiOnly and #payload.ai or 0
  send(pid, "cnr_setupAI", payload)
  if not payload.aiOnly and registeredRoundCar[pid] then openTraffic(pid) end
end

local lastRulesSignature
local function pushRules(pid, onlyChanged)
  local payload = rules.payload(cfg, traffic.perPlayer(cfg.trafficPerPlayer, traffic.maxCars(), 1))
  local signature = panel.signature(payload)
  if onlyChanged and signature == lastRulesSignature then return end
  send(pid or -1, "cnr_rules", payload)
  lastRulesSignature = signature
end

local function applyEffects(effects)
  for _, e in ipairs(effects) do
    if e.kind == "reply" then
      reply(e.pid, e.msg, e.tone)
    elseif e.kind == "broadcast" then
      if e.meters then log(string.format("%s %.0f m", e.msg, e.meters)) end
      if e.to then notify(e.to, e.msg, e.tone) else broadcast(e.msg, e.tone) end
    elseif e.kind == "pickVehicle" then
      pendingAISetup = nil
      send(e.pid, "cnr_pickVehicle", { includeMods = cfg.includeModVehicles, excludedModels = cfg.excludedModels })
    elseif e.kind == "planStart" then
      send(e.pid, "cnr_planStart", { id = e.id, count = e.count, anchor = e.anchor,
        copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters })
    elseif e.kind == "setup" then
      local anchor = e.startPose ~= nil and current.startGrid[1]
      local runnerCar = not anchor and carFor(current.runnerId)
      local delivered, reason = send(e.pid, "cnr_roundSetup", {
        startPose = e.startPose,
        runnerId = current.runnerId, runnerName = current:runnerName(), role = e.role, copIndex = e.copIndex,
        model = current.vehicle.model, config = current.vehicle.config,
        phase = e.phase, countdownRemaining = e.countdownRemaining, chaseElapsed = e.chaseElapsed,
        headStartRemaining = e.headStartRemaining, inPlace = e.inPlace,
        color = e.colorHex and colors.parseHex(e.colorHex) or playerColors:get(e.pid),
        runnerPos = anchor and anchor.pos or runnerCar and runnerCar.pos or nil,
        copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
        sightMaxMeters = cfg.sightMaxMeters,
        runnerShown = e.runnerShown, heli = e.heli,
        evolving = current.evolving or nil, rebuild = current.rebuildId, practice = current.test or nil,
        sky = sky.payload(current.sky, cfg, current:clockSeconds(now())),
      })
      if delivered == false then
        log(string.format("setup failed for %s: %s", MP.GetPlayerName(e.pid) or tostring(e.pid), tostring(reason)))
        applyEffects(current:setupFailed(now(), e.pid))
        if not current:isActive() then return end
      else
        placing(e.pid)
        rememberPreRoundVehicles(e.pid)
        allowRoundSpawn[e.pid] = true
        log(string.format("setup sent to %s: %s, %s", MP.GetPlayerName(e.pid) or tostring(e.pid), e.role, tostring(e.phase)))
        if e.role == "runner" and not current.test then
          local key = roster:key(e.pid)
          lastRunnerKey = key
          plannedRunnerKey = nil
          currentRunnerKey = key
        end
      end
    elseif e.kind == "spectate" then
      log(string.format("%s spectates (%s)", MP.GetPlayerName(e.pid) or tostring(e.pid), tostring(e.phase)))
      send(e.pid, "cnr_spectate", {
        runnerId = current.runnerId, runnerName = current:runnerName(), phase = e.phase,
        countdownRemaining = e.countdownRemaining, headStartRemaining = e.headStartRemaining, chaseElapsed = e.chaseElapsed,
        heli = e.heli,
        sky = sky.payload(current.sky, cfg, current:clockSeconds(now())),
      })
    elseif e.kind == "setupAI" then
      for pid in pairs(MP.GetPlayers() or {}) do parkBystander(pid) end
      local list = {}
      for _, a in ipairs(e.ai) do
        list[#list + 1] = { id = a.id, role = a.role, index = current.startGrid and a.index or #list + 1, startPose = a.startPose, name = a.name, color = colors.parseHex(a.colorHex) }
      end
      if e.aiOnly then rememberPreRoundVehicles(e.pid) end
      aiSpawnsLeft = 0
      local capacity = traffic.maxCars()
      local payload = {
        model = current.vehicle.model, config = current.vehicle.config, ai = list,
        runnerId = current.runnerId, copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
        aiOnly = e.aiOnly, sightMaxMeters = cfg.sightMaxMeters,
      }
      pendingAISetup = { pid = e.pid, payload = payload, deadline = now() + AI_SETUP_WAIT_SECONDS,
        capacity = capacity and capacity >= #list + (e.aiOnly and 0 or 1) and capacity or nil }
      dispatchAISetup()
    elseif e.kind == "countdown" then
      if sky.hasThunderstorm(current.sky) then
        current.sky.lightningTimer = MP.CreateTimer()
        current.sky.strikeCursor = strikeSchedule.new(current.sky.lightningSeed)
        announceLightning(carFor(current.runnerId))
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
      for pid in pairs(parkedBystanders) do send(pid, "cnr_parkBystanderCars", { on = false }) end
      roster:clear("parkedBystanders")
      local autoNext = settings:get("autoNextRound") and e.reason ~= "cancelled" and not e.to
      send(e.to or -1, "cnr_roundEnd", {
        runnerId = e.runnerId, runnerName = e.runnerName, survivedSeconds = e.survivedSeconds,
        reason = e.reason, explode = e.explode, catchers = e.catchers, message = e.message,
        autoNextSeconds = autoNext and cfg.autoNextDelaySeconds or nil,
      })
      roster:clear("activeVid")
      roster:clear("registeredRoundCar")
      roster:clear("allowRoundSpawn")
      roster:clear("preRoundVehicles")
      roster:clear("trafficOpen")
      roster:clear("trafficVids")
      aiSpawnsLeft = 0
      pendingAISetup = nil
      clearRoundCars()
      partsBaseline = {}
      missingCount = {}
      if not current.test and not e.to and e.reason ~= "cancelled" then
        lastResult = { runner = e.runnerName, seconds = e.survivedSeconds, reason = e.reason }
      end
      aiCars, aiSlotSerial, aiVidSerial = {}, {}, {}
      if autoNext then nextRound:schedule(now() + cfg.autoNextDelaySeconds) end
      useConfig(settings:effective())
      pushRules(nil, true)
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
      if pendingAISetup then pendingAISetup.payload.config = e.config end
      for pid in pairs(current.players) do
        if not round.isAI(pid) then
          placing(pid)
          send(pid, "cnr_rebuild", { model = current.vehicle.model, config = e.config, rebuild = e.id })
        end
      end
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
      run.map = mapName
      run.releasedAt = endedAt - math.floor(run.survivedSeconds + 0.5)
      run.endedAt = endedAt
      run.key = currentRunnerKey
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
      if currentRunnerKey then runCounts[currentRunnerKey] = (runCounts[currentRunnerKey] or 0) + 1 end
      plannedRunnerKey = nil
      saveLeaderboard(run)
      pushBoard()
      local top = leaderboard.runners(board, mapName, 3)
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

local function plannedRunner(players)
  local countsByName = {}
  for p, name in pairs(players) do countsByName[name] = runCounts[roster:key(p)] or 0 end
  local lastPid = lastRunnerKey and roster:pidForKey(lastRunnerKey)
  local lastName = lastPid and MP.GetPlayerName(lastPid) or nil
  local eligible = commands.eligibleNext(players, countsByName, lastName)
  if plannedRunnerKey then
    for _, p in ipairs(eligible) do
      if roster:key(p) == plannedRunnerKey then return p end
    end
  end
  local pid = commands.matchPlayer("next", players, nil, countsByName, lastName)
  plannedRunnerKey = pid and roster:key(pid) or nil
  return pid
end

panelService:command("start", function(pid, cmd)
  if current:isActive() and current.test then
    applyEffects(current:stop(now(), current.issuerId))
  end
  if current:isActive() then return refuse(pid, "A round is already running") end
  if cfg.carMode == "evolving" and not currentBuild then return refuse(pid, "Start a new build first") end
  nextRound:cancel()
  lastIssuer = pid
  local players = MP.GetPlayers() or {}
  local candidates, count = roster:playing(players)
  if count == 0 then return refuse(pid, "Everyone is sitting out") end
  local query = cmd.rest
  local runnerId, err
  if query and query:lower() == "again" then
    runnerId = lastRunnerKey and roster:pidForKey(lastRunnerKey)
    if not runnerId then return refuse(pid, "No previous runner online") end
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
  if not runnerId then return refuse(pid, err) end
  if roster:sittingOut(runnerId) then return refuse(pid, string.format("%s is sitting out", players[runnerId] or tostring(runnerId))) end
  requestStations(pid)
  roster:clear("activeVid")
  roster:clear("trafficOpen")
  roster:clear("trafficVids")
  partsBaseline = {}
  missingCount = {}
  lastResult = nil
  useConfig(settings:snapshot())
  local sittingOut = roster:sitOutSnapshot()
  applyEffects(current:start(now(), runnerId, pid, players, { gridPlanner = gridClients[runnerId] and runnerId, build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random), traffic = traffic.perPlayer(cfg.trafficPerPlayer, traffic.maxCars(), 1), trafficRunnerOnly = cfg.trafficRunnerOnly == true, sittingOut = sittingOut }))
end)

panelService:command("test", function(pid, cmd)
  if current:isActive() then return refuse(pid, "A round is already running") end
  roster:clear("activeVid")
  roster:clear("trafficOpen")
  roster:clear("trafficVids")
  partsBaseline = {}
  missingCount = {}
  previousRoundSerial = connectionSerial[pid] or 0
  local role = cmd.args[1] and cmd.args[1]:lower()
  if cfg.carMode == "evolving" and not currentBuild then return refuse(pid, "Start a new build first") end
  useConfig(settings:snapshot())
  local opts = { gridPlanner = gridClients[pid] and pid, test = true, role = role, aiOnly = roster:sittingOut(pid), build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random) }
  applyEffects(current:start(now(), nil, pid, MP.GetPlayers() or {}, opts))
end)

local function lobbyState()
  local players = MP.GetPlayers() or {}
  local online = 0
  for _ in pairs(players) do online = online + 1 end
  local practice
  if current:isActive() and current.test then practice = current.players[current.issuerId] or MP.GetPlayerName(current.issuerId) or "someone" end
  return { online = online, practice = practice, active = current:isActive() and not current.test or false }
end

panelService:command("go", function(pid)
  applyEffects(current:go(now(), pid))
end)

panelService:command("stop", function(pid)
  local wasActive = current:isActive()
  applyEffects(current:stop(now(), pid))
  if not wasActive then send(-1, "cnr_roundEnd", { reason = "cancelled" }) end
end)

panelService:command("end", function(pid)
  applyEffects(current:endCalled(now(), pid))
end)

panelService:command("reroll", function(pid)
  applyEffects(current:reroll(now(), pid))
end)

panelService:command("sky", function(pid)
  if current.state ~= "prep" and current.state ~= "ready" then return refuse(pid, "You can only change the sky before GO") end
  if not sky.hasRandom(cfg) then return refuse(pid, "Set time of day or weather to random first") end
  local before = current.sky or {}
  local picked = sky.pick(cfg, math.random)
  for _ = 1, 10 do
    if picked.time ~= before.time or picked.weather ~= before.weather then break end
    picked = sky.pick(cfg, math.random)
  end
  current.sky = picked
  local data = sky.payload(current.sky, cfg, nil)
  local targets = current.test and { [current.issuerId] = true } or MP.GetPlayers() or {}
  for p in pairs(targets) do send(p, "cnr_sky", data) end
end)

panelService:command("addstation", function(pid)
  local car = carFor(pid)
  if not car then return refuse(pid, "You need to be in a vehicle") end
  local updated = table.move(stations, 1, #stations, 1, {})
  updated[#updated + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
  local ok, err = saveStations(updated)
  if not ok then return refuse(pid, err) end
  reply(pid, string.format("Gas station added (%d on %s)", #stations, mapName))
end)

panelService:command("removestation", function(pid)
  local car = carFor(pid)
  if not car then return refuse(pid, "You need to be in a vehicle") end
  local bestIndex, bestDist
  for i, s in ipairs(stations) do
    local d = vec.dist(car.pos, s)
    if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
  end
  if not bestIndex then return refuse(pid, "No gas station within 50 m") end
  local updated = table.move(stations, 1, #stations, 1, {})
  table.remove(updated, bestIndex)
  local ok, err = saveStations(updated)
  if not ok then return refuse(pid, err) end
  reply(pid, string.format("Gas station removed (%d left on %s)", #stations, mapName))
end)

local function nextRunnerName(players)
  local pid = plannedRunner(players)
  return pid and players[pid] or nil
end

local function playerEntries(players, realRound)
  local entries, loading = {}, 0
  for pid, name in pairs(players) do
    local entry = { name = name, runs = runCounts[roster:key(pid)] or 0, sitOut = roster:sittingOut(pid) or nil }
    if realRound and current.players[pid] ~= nil then
      local isRunner = pid == current.runnerId
      entry.role = isRunner and "runner" or "cop"
      local placingNow = partsBaseline[pid] and partsBaseline[pid].placing
      if placingNow then loading = loading + 1 end
      local changes = current.queued and current.queued.changes
      if placingNow then
        entry.state = "loading"
      elseif missingCount[pid] then
        entry.state, entry.missing = "missing", missingCount[pid]
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

local function panelState()
  local running = current.state == "running"
  local players = MP.GetPlayers() or {}
  local candidates, count = roster:playing(players)
  local realRound = current:isActive() and not current.test
  local entries, loading = playerEntries(players, realRound)
  local nextName = not realRound and nextRunnerName(candidates) or nil
  local lastPid = lastRunnerKey and roster:pidForKey(lastRunnerKey)
  local autoNext
  local autoNextAt = nextRound:pending()
  if autoNextAt and not realRound then
    autoNext = { seconds = math.max(0, math.ceil(autoNextAt - now())), runner = nextName }
  end
  local buildInfo
  if currentBuild then
    buildInfo = { label = build.label(currentBuild), step = currentBuild.step, name = currentBuild.name, lastChange = build.lastChange(currentBuild) }
  end
  return panel.snapshot({
    version = VERSION, map = mapName, phase = current.state,
    runner = current.runnerId and current:runnerName() or nil,
    car = roundCarActive() and current.vehicle.model or nil,
    test = current.test == true,
    elapsed = running and current.releasedAt and math.max(0, now() - current.releasedAt) or nil,
    players = entries, cfg = cfg, defaults = config.DEFAULTS,
    autoNextRound = settings:get("autoNextRound"),
    evolving = current.evolving == true,
    build = buildInfo,
    nextRunner = nextName, lastRunner = lastPid and players[lastPid] or nil,
    loading = loading, autoNext = autoNext, lastResult = lastResult,
    stationCount = #stations,
    skyRandom = sky.hasRandom(cfg),
    trafficNote = trafficNote(cfg.trafficPerPlayer, traffic.maxCars(), count, cfg.trafficRunnerOnly == true),
  })
end

local function panelBuild(pid, msg)
  local function answer(text, tone) send(pid, "cnr_panelReply", { text = text, tone = tone }) end
  if current:isActive() then return answer("Stop the round first", "warn") end
  local replacement
  if msg.op == "new" then
    local nb = build.normalize({ model = msg.model, name = msg.name, parts = msg.parts, vars = msg.vars })
    if not nb then return answer("That car can't start a build", "warn") end
    replacement = build.new(nb.model, nb.name, nb.parts, nb.vars, type(msg.from) == "string" and msg.from or "random", os.time())
  elseif msg.op ~= "reset" then
    return
  end
  local moved, aside = backupBuild()
  if not moved then return answer(aside, "warn") end
  if replacement then
    local saved, err = saveJson(buildPath, replacement)
    if not saved then
      if aside then
        local restored, restoreErr = os.rename(aside, buildPath)
        if not restored then
          err = string.format("%s; restore failed (%s), original kept at %s", err, tostring(restoreErr), aside)
          saveError(buildPath, err)
        end
      end
      return answer(err, "warn")
    end
  end
  currentBuild = replacement
  panelService:push(panelState)
  answer(replacement and "New build: " .. build.label(replacement) or "Build reset")
end

local function reloadRound()
  cfg = settings:load()
  current = round.new(cfg)
end

local function panelSettings(pid, values, id)
  if type(id) ~= "number" and type(id) ~= "string" then id = nil end
  local function answer(ok, text, keys) send(pid, "cnr_panelReply", { ok = ok, text = text, keys = keys, id = id }) end
  if current:isActive() then return answer(false, "Stop the round first") end
  local keys, err = settings:apply(values)
  if not keys then return answer(false, err) end
  reloadRound()
  answer(true, "Saved", keys)
  pushRules()
  panelService:push(panelState)
  pushBoard()
end

function cnrOnPanel(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" or type(msg.action) ~= "string" then return end
  if msg.action == "open" then
    panelService:push(panelState, pid)
  elseif msg.action == "close" then
    panelService:close(pid)
  elseif msg.action == "command" then
    local text = panel.allow(msg.text)
    if not text then return send(pid, "cnr_panelReply", { text = "Not available from the panel", tone = "warn" }) end
    local ran, err = messages.mirrored(pid, panelService.run, panelService, pid, text)
    panelService:push(panelState)
    if not ran then error(err, 0) end
  elseif msg.action == "station" then
    if msg.op ~= "add" and msg.op ~= "remove" then return end
    local ran, err = messages.mirrored(pid, panelService.run, panelService, pid, msg.op .. "station")
    panelService:push(panelState)
    if not ran then error(err, 0) end
  elseif msg.action == "stations" then
    local list = {}
    for _, st in ipairs(stations) do
      list[#list + 1] = { x = st.x, y = st.y, z = st.z }
    end
    send(pid, "cnr_stationList", { map = mapName, stations = list })
  elseif msg.action == "settings" then
    panelSettings(pid, msg.values, msg.id)
  elseif msg.action == "build" then
    panelBuild(pid, msg)
  elseif msg.action == "apply" then
    if pid ~= current.runnerId then return send(pid, "cnr_panelReply", { text = "Only the runner can apply the change", tone = "warn" }) end
    local ran, err = messages.mirrored(pid, function() applyEffects(current:apply(now(), pid)) end)
    panelService:push(panelState)
    if not ran then error(err, 0) end
  end
end

local MAX_CHANGES, MAX_TEXT, MAX_PARTS, MAX_PART_ID = 30, 80, 20, 120

local function cleanParts(list)
  local out = {}
  for _, id in ipairs(type(list) == "table" and list or {}) do
    if #out >= MAX_PARTS then break end
    if type(id) == "string" and id ~= "" then out[#out + 1] = id:sub(1, MAX_PART_ID) end
  end
  return #out > 0 and out or nil
end

local function cleanChanges(list)
  local out = {}
  for _, c in ipairs(type(list) == "table" and list or {}) do
    if #out >= MAX_CHANGES then break end
    if type(c) == "table" then
      out[#out + 1] = {
        label = tostring(c.label or ""):sub(1, MAX_TEXT), from = tostring(c.from or ""):sub(1, MAX_TEXT),
        to = tostring(c.to or ""):sub(1, MAX_TEXT), extra = tonumber(c.extra), parts = cleanParts(c.parts),
      }
    end
  end
  return out
end

function cnrOnSetup(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" then return end
  if not current.evolving or current.state ~= "applying" or pid ~= current.runnerId then return end
  if d.model ~= nil and d.model ~= current.vehicle.model then return log("ignored a setup for another car model from " .. tostring(pid)) end
  local valid = build.normalize({ model = current.vehicle.model, parts = d.parts, vars = d.vars })
  if not valid then return log("ignored a malformed setup from " .. tostring(pid)) end
  local setup = { parts = valid.parts, vars = valid.vars }
  local changes = cleanChanges(d.changes)
  if not current.test and currentBuild then
    local name = MP.GetPlayerName(pid) or tostring(pid)
    local nb, changed = build.apply(currentBuild, setup, changes, name, os.time())
    if nb ~= currentBuild then
      local saved, err = saveJson(buildPath, nb)
      if not saved then return refuse(pid, err) end
      currentBuild = nb
      current.buildStep = nb.step
    end
    if changed then broadcast(build.changeLine(nb.step, name, changes)) end
  end
  local cfgTable = { format = 2, model = current.vehicle.model, parts = setup.parts, vars = setup.vars }
  applyEffects(current:setupReceived(now(), pid, cfgTable))
  panelService:push(panelState)
end

function cnrOnChange(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  if not current.evolving or current.state ~= "prep" or pid ~= current.runnerId then return end
  current.queued = { runner = MP.GetPlayerName(pid) or tostring(pid), changes = cleanChanges(d.changes) }
  for p in pairs(current.players) do
    if not round.isAI(p) then send(p, "cnr_queued", current.queued) end
  end
end

function cnrOnMissing(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" or #d.parts == 0 then return end
  if not current:isActive() or current.players[pid] == nil then return end
  missingCount[pid] = #d.parts
  local names = {}
  for i, part in ipairs(d.parts) do
    if i > 6 then names[#names + 1] = string.format("+%d more", #d.parts - 6) break end
    names[#names + 1] = tostring(part)
  end
  send(current.test and current.issuerId or -1, "cnr_notice", { msg = string.format("⚠ %s is missing: %s", MP.GetPlayerName(pid) or tostring(pid), table.concat(names, ", ")), tone = "warn" })
end

local function matchesRoundVehicle(decoded)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  return not pcFile or current.evolving or normalizeConfig(pcFile) == normalizeConfig(current.vehicle.config)
end

local function vehicleAllowed(pid, vid, data, isSpawn)
  if current:isActive() and current.aiOnly and pid == current.issuerId then
    local decoded = parseVehicleData(data)
    if current.state == "picking" then return not isSpawn, decoded, isSpawn and WATCHING_AI or nil end
    local model = current.vehicle and current.vehicle.model
    local roundModel = model ~= nil and decoded ~= nil and decoded.jbm == model
    if not roundModel or (isSpawn and aiSpawnsLeft <= 0) then return false, decoded, isSpawn and WATCHING_AI or nil end
    if isSpawn then aiSpawnsLeft = aiSpawnsLeft - 1 end
    return true, decoded
  end
  local own = activeVid[pid]
  local trafficCount = trafficService:openCount(pid)
  local roundPlayer = roundCarActive() and current.players[pid] ~= nil
  if isSpawn and roundPlayer and not current.test and (allowRoundSpawn[pid] or (registeredRoundCar[pid] and not own)) then
    local decoded = parseVehicleData(data)
    if matchesRoundVehicle(decoded) then return true, decoded, nil, true end
    if not own or not trafficCount then return false, decoded end
  end
  if current:isActive() and trafficCount and current.players[pid] ~= nil and vid ~= own then
    if current.test and pid == current.issuerId then return true end
    if not isSpawn then return true end
    return own ~= nil and trafficService:extraCars(pid, own) < trafficCount
  end
  if not roundPlayer then return true end
  local decoded = parseVehicleData(data)
  if not matchesRoundVehicle(decoded) then return false, decoded end
  if isSpawn and not current.test and firstVid(pid) then return false, decoded end
  return true, decoded
end

local function checkParts(pid, decoded)
  if not decoded or type(decoded.vcf) ~= "table" or decoded.vcf.parts == nil then return end
  local parts = decoded.vcf.parts
  local entry = partsBaseline[pid]
  local mayChange = current.evolving and (current.state == "prep" or current.state == "applying") and pid == current.runnerId
  if entry == nil then
    partsBaseline[pid] = { parts = parts, announced = false }
  elseif entry.parts == nil or mayChange or (entry.quietUntil and now() < entry.quietUntil) then
    entry.parts = parts
  elseif not tables.deepEqual(parts, entry.parts) then
    if not entry.announced then
      entry.announced = true
      local msg = string.format("⚠ %s changed parts during the round: %s", MP.GetPlayerName(pid) or tostring(pid), tables.diffKeys(entry.parts, parts, 5))
      log(msg)
      current:note(now(), "partsChanged", MP.GetPlayerName(pid) or tostring(pid))
      if current.test then notify(current.issuerId, msg, "warn") else broadcast(msg, "warn") end
    end
    entry.parts = parts
  end
end

local function tracksActive(pid)
  return current:isActive() and not (current.test and pid == current.issuerId)
end

local function logVehicleRefusal(pid, action, vid, decoded)
  local last = refusalLoggedAt[pid]
  if last and now() - last < REFUSAL_LOG_SECONDS then return end
  refusalLoggedAt[pid] = now()
  log(string.format("%s %s %s (vid %s): refused", MP.GetPlayerName(pid) or tostring(pid), action,
    tostring(decoded and decoded.jbm or "?"), tostring(vid)))
end

function cnrOnVehicleSpawn(pid, vid, data)
  if current.vehicle and not current.test and current.players[pid] == nil then
    logVehicleRefusal(pid, "spawned", vid, parseVehicleData(data))
    refuse(pid, "You can't spawn a car while spectating")
    return 1
  end
  local allowed, decoded, why, roundSpawn = vehicleAllowed(pid, vid, data, true)
  if not allowed then
    logVehicleRefusal(pid, "spawned", vid, decoded)
    refuse(pid, why or "Only the round car is allowed")
    return 1
  end
  if preRoundVehicles[pid] then preRoundVehicles[pid][vid] = nil end
  if roundSpawn then
    setRoundVid(pid, vid)
    allowRoundSpawn[pid] = nil
    if registeredRoundCar[pid] then pushRoundCars() end
  elseif tracksActive(pid) and not registeredRoundCar[pid] and not trafficService:openCount(pid) then
    activeVid[pid] = vid
  end
  return 0
end

function cnrOnVehicleEdited(pid, vid, data)
  if preRoundVehicles[pid] and preRoundVehicles[pid][vid] then return 0 end
  if registeredRoundCar[pid] and activeVid[pid] ~= vid then
    if pid ~= current.issuerId or not aiSlotForVid(vid) then return 0 end
  end
  local allowed, decoded, why = vehicleAllowed(pid, vid, data, false)
  if not allowed then
    logVehicleRefusal(pid, "edited", vid, decoded)
    refuse(pid, why or "Only the round car is allowed")
    return 1
  end
  local notOwn = vid ~= activeVid[pid] and (current.test or trafficService:openCount(pid))
  if roundCarActive() and current.players[pid] and not notOwn then checkParts(pid, decoded) end
  if tracksActive(pid) and not trafficService:openCount(pid) then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleDeleted(pid, vid)
  if pid == current.issuerId then removeAICar(aiSlotForVid(vid)) end
  if preRoundVehicles[pid] then preRoundVehicles[pid][vid] = nil end
  if activeVid[pid] == vid then
    setRoundVid(pid, nil)
    if registeredRoundCar[pid] then pushRoundCars() end
  end
end

function cnrOnVehicleReset(pid, vid)
  if (activeVid[pid] or registeredRoundCar[pid] or trafficService:openCount(pid)) and activeVid[pid] ~= vid then return end
  applyEffects(current:vehicleReset(now(), pid))
end

function cnrOnColor(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" then return end
  local hex = type(msg.hex) == "string" and msg.hex or ""
  if hex == "" then
    local _, err = playerColors:clear(pid)
    return playerColors:sendMine(pid, err)
  end
  local saved, err = playerColors:set(pid, hex)
  playerColors:sendMine(pid, err)
  if not saved then return end
  if current.state == "prep" and current.players[pid] then
    placing(pid)
    send(pid, "cnr_paint", { color = playerColors:get(pid) })
  end
end

function cnrOnSitOut(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.on) ~= "boolean" then return end
  roster:setSitOut(pid, d.on)
  send(pid, "cnr_sitOut", { on = d.on })
  if current:isActive() and not current.test then
    notify(pid, d.on and "You sit out from the next round" or "You play again from the next round")
  end
end

function cnrOnPlayerJoin(pid)
  send(pid, "cnr_mode", { version = VERSION, startGrid = true })
  playerColors:sendMine(pid)
  pushRules(pid)
  panelService:pushLobby(lobbyState, pid)
  requestStations(pid)
  applyEffects(current:playerJoined(now(), pid, MP.GetPlayerName(pid)))
  if current.test and current.vehicle then parkBystander(pid) end
  if current.evolving and current.state == "prep" and current.queued and current.players[pid] then
    send(pid, "cnr_queued", current.queued)
  end
  if current:isActive() then pushRoundCars(pid) end
end

function cnrOnPlayerDisconnect(pid)
  roster:leaveEarly(pid)
  applyEffects(current:playerLeft(now(), pid))
  roster:leaveLate(pid)
  pushRoundCars()
end

function cnrOnStartGridReady(pid)
  gridClients[pid] = true
end

local function finite(n)
  return type(n) == "number" and math.abs(n) < math.huge
end

function cnrOnLightningClock(pid, data)
  local timer = current.sky and current.sky.lightningTimer
  if not timer or not current:isActive() then return end
  local players = MP.GetPlayers() or {}
  if not players[pid] or (current.test and pid ~= current.issuerId) then return end
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or d.seed ~= current.sky.lightningSeed or not finite(d.id) then return end
  send(pid, "cnr_lightningClock", {seed = d.seed, id = d.id, elapsed = timer:GetCurrent()})
end

local function gamePoint(p)
  if type(p) == "table" and finite(p.x) and finite(p.y) and finite(p.z) then
    return { x = p.x, y = p.y, z = p.z }
  end
end

local function plannerPosition(pid)
  if current.aiOnly then return nil end
  local vehicles = MP.GetPlayerVehicles(pid)
  if type(vehicles) ~= "table" then return nil end
  local vid, data = next(vehicles)
  if not vid or next(vehicles, vid) then return nil end
  local vehicle = parseVehicleData(data)
  if vehicle and vehicle.jbm == "unicycle" then return nil end
  local raw, err = MP.GetPositionRaw(pid, vid)
  if (not err or err == "") and type(raw) == "table" then return vec.toVec(raw.pos) end
end

local function startPose(p)
  if p == false then return false end
  if type(p) ~= "table" then return nil end
  local at, dir = gamePoint(p.pos), gamePoint(p.dir)
  if at and dir then
    local norm = dir.x * dir.x + dir.y * dir.y + dir.z * dir.z
    if norm > 0.99 and norm < 1.01 then return { pos = at, dir = dir, offRoad = p.offRoad == true or nil } end
  end
end

function cnrOnStartGrid(pid, data)
  local pending = current.pendingGrid
  if not pending or pid ~= pending.request.pid then return end
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or d.id ~= pending.request.id or type(d.slots) ~= "table" then return end
  if #d.slots ~= pending.request.count then return end
  local slots = {}
  for i = 1, pending.request.count do
    slots[i] = startPose(d.slots[i])
    if slots[i] == nil or (not slots[1] and slots[i]) then return end
  end
  local runner = slots[1]
  local anchor = runner and runner.pos
  if pending.request.anchor ~= nil then
    if not tables.deepEqual(pending.request.anchor, runner) then return end
  elseif anchor then
    local known = plannerPosition(pid)
    if known and not (vec.dist(known, anchor) <= START_ROAD_SEARCH + 1) then return end
  end
  local limit = math.max(cfg.copSpawnMaxMeters, 1)
  while limit < START_ROAD_SEARCH do limit = limit * 2 end
  for i = 2, #slots do
    local cop = slots[i]
    if cop and not (vec.dist(anchor, cop.pos) <= limit + 1) then return end
  end
  applyEffects(current:gridReceived(now(), slots, MP.GetPlayers() or {}))
end

function cnrOnVehiclePicked(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.model) ~= "string" then return end
  applyEffects(current:vehiclePicked(now(), pid, decoded.model, decoded.config, MP.GetPlayers() or {}))
end

local function integer(n)
  return finite(n) and n % 1 == 0
end

function cnrOnMyVehicle(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  local vid = ok and type(decoded) == "table" and tonumber(decoded.vid)
  if not integer(vid) or vid < 0 or not roundCarActive() or current.players[pid] == nil then return end
  local owned = MP.GetPlayerVehicles(pid)
  if type(owned) ~= "table" or not owned[vid] or (pid == current.issuerId and aiSlotForVid(vid)) then return end
  setRoundVid(pid, vid)
  registeredRoundCar[pid] = true
  preRoundVehicles[pid] = nil
  allowRoundSpawn[pid] = nil
  placed(pid)
  log(string.format("%s placed the round car (vid %s)", MP.GetPlayerName(pid) or tostring(pid), tostring(vid)))
  applyEffects(current:vehicleReady(now(), pid, tonumber(decoded.rebuild)))
  if pendingAISetup then dispatchAISetup() else openTraffic(pid) end
  pushRoundCars()
end

function cnrOnTrafficCars(pid, data)
  if not trafficService:openCount(pid) then return end
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.vids) ~= "table" then return end
  trafficService:report(pid, d.vids, activeVid[pid], function(vid)
    return current.test and pid == current.issuerId and aiSlotForVid(vid)
  end)
end

local function registerAICar(pid, a, owned)
  if type(a) ~= "table" then return end
  local id, vid, serial = a.id, a.vid, a.instance
  if not round.isAI(id) or not current.players[id] then return end
  if not integer(vid) or vid < 0 or not owned[vid] or (registeredRoundCar[pid] and activeVid[pid] == vid) then return end
  if serial ~= nil then
    local latest = math.max(previousRoundSerial, aiSlotSerial[id] or 0, aiVidSerial[vid] or 0)
    if not integer(serial) or serial <= latest then return end
    aiSlotSerial[id], aiVidSerial[vid] = serial, serial
    connectionSerial[pid] = math.max(connectionSerial[pid] or 0, serial)
  elseif aiSlotSerial[id] or aiVidSerial[vid] or (aiCars[id] and aiCars[id].vid == vid) then
    return
  end
  removeAICar(id)
  removeAICar(aiSlotForVid(vid))
  aiCars[id] = {vid=vid, instance=serial}
  if preRoundVehicles[pid] then preRoundVehicles[pid][vid] = nil end
end

local function decodeObservationPacket(data)
  if type(data) ~= "string" then return end
  if data:find("null", 1, true) then
    local quoted = false
    data = data:gsub('([^"]*)("?)', function(chunk, quote)
      local value = quoted and chunk or chunk:gsub("null", "[]")
      if quote ~= "" and #chunk:match("\\*$") % 2 == 0 then quoted = not quoted end
      return value .. quote
    end)
  end
  local ok, packet = pcall(Util.JsonDecode, data)
  if ok and type(packet) == "table" then return packet end
end

function cnrOnAiVehicles(pid, data)
  if not current.test or pid ~= current.issuerId then return end
  local decoded = decodeObservationPacket(data)
  if not decoded or type(decoded.ai) ~= "table" then return end
  local owned = MP.GetPlayerVehicles(pid)
  if type(owned) ~= "table" then return end
  for _, a in ipairs(decoded.ai) do registerAICar(pid, a, owned) end
end

function cnrOnBoard(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" then return end
  if msg.action == "close" then
    boardSubs[pid] = nil
  elseif msg.action == "open" or msg.action == "filter" then
    local sub = boardSubs[pid] or { map = mapName }
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

function cnrOnSight(pid, data)
  local d = decodeObservationPacket(data)
  if not d or type(d.seen) ~= "boolean" then return end
  if not confirmedVid(current.runnerId) and not aiCars[current.runnerId] then return end
  if d.aiId ~= nil or d.instance ~= nil then
    if not current.test or pid ~= current.issuerId or not round.isAI(d.aiId) or not integer(d.instance) then return end
    local car = aiCars[d.aiId]
    if not car or car.instance ~= d.instance then return end
    local owned = MP.GetPlayerVehicles(pid)
    if type(owned) == "table" and owned[car.vid] then current:aiSightReport(now(), pid, d.aiId, d.seen) end
  elseif confirmedVid(pid) then
    current:sightReport(now(), pid, d.seen)
  end
end

function cnrOnCover(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  current:coverReport(now(), pid, d.covered == true)
end

function cnrOnStations(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or decoded.map ~= mapName or #stations > 0 then return end
  for _, s in ipairs(decoded.stations or {}) do
    local v = vec.toVec(s)
    if v then
      v.r = tonumber(s.r) or 0
      stations[#stations + 1] = v
    end
  end
  if #stations > 0 then
    saveStations(stations)
    log(string.format("%d gas stations detected for %s", #stations, mapName))
  end
end

local function startNext()
  local players = MP.GetPlayers() or {}
  local issuer = lastIssuer and players[lastIssuer] and lastIssuer
  if not issuer then
    for p in pairs(players) do
      if not issuer or p < issuer then issuer = p end
    end
  end
  if issuer then panelService:run(issuer, "start next") end
end

local startScheduled = autoRounds.register(panelService, {
  settings = settings,
  a = nextRound,
  pushRules = function()
    if not current:isActive() then useConfig(settings:effective()) end
    pushRules()
  end,
  startNext = startNext,
  reloadRound = reloadRound,
  isActive = function() return current:isActive() end,
  send = send,
})

function cnrTick()
  panelService:tick(panelState, lobbyState)
  if nextRound:due(now()) then startScheduled() end
  if not current:isActive() then return end
  dispatchAISetup()
  if pendingAISetup and now() >= pendingAISetup.deadline then
    local pid = pendingAISetup.pid
    local waitingForCar = not pendingAISetup.payload.aiOnly and allowRoundSpawn[pid]
    applyEffects(current:stop(now(), pid))
    notify(pid, waitingForCar and "Practice cancelled: your round car did not register in time."
      or "Practice cancelled: too few free vehicle slots for the AI. Free a slot or increase MaxCars.", "warn")
    return
  end
  local cars = {}
  for pid in pairs(current.players) do cars[pid] = carFor(pid) end
  announceLightning(cars[current.runnerId])
  applyEffects(current:tick(now(), cars, stations, trafficService:cars()))
end

FS.CreateDirectory(stationsDir)
reloadRound()
loadLeaderboard()
loadBuild()
playerColors:load()
mapName = (tostring(MP.Get(MP.Settings.Map) or ""):match("levels/([^/]+)/")) or "unknown"
loadStations()

MP.RegisterEvent("onVehicleSpawn", "cnrOnVehicleSpawn")
MP.RegisterEvent("onVehicleEdited", "cnrOnVehicleEdited")
MP.RegisterEvent("onVehicleDeleted", "cnrOnVehicleDeleted")
MP.RegisterEvent("onVehicleReset", "cnrOnVehicleReset")
MP.RegisterEvent("onPlayerJoin", "cnrOnPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "cnrOnPlayerDisconnect")
MP.RegisterEvent("cnr_startGridReady", "cnrOnStartGridReady")
MP.RegisterEvent("cnr_startGrid", "cnrOnStartGrid")
MP.RegisterEvent("cnr_vehiclePicked", "cnrOnVehiclePicked")
MP.RegisterEvent("cnr_stations", "cnrOnStations")
MP.RegisterEvent("cnr_myVehicle", "cnrOnMyVehicle")
MP.RegisterEvent("cnr_aiVehicles", "cnrOnAiVehicles")
MP.RegisterEvent("cnr_trafficCars", "cnrOnTrafficCars")
MP.RegisterEvent("cnr_panel", "cnrOnPanel")
MP.RegisterEvent("cnr_color", "cnrOnColor")
MP.RegisterEvent("cnr_sitOut", "cnrOnSitOut")
MP.RegisterEvent("cnr_sight", "cnrOnSight")
MP.RegisterEvent("cnr_cover", "cnrOnCover")
MP.RegisterEvent("cnr_lightningClock", "cnrOnLightningClock")
MP.RegisterEvent("cnr_board", "cnrOnBoard")
MP.RegisterEvent("cnr_setup", "cnrOnSetup")
MP.RegisterEvent("cnr_change", "cnrOnChange")
MP.RegisterEvent("cnr_missing", "cnrOnMissing")
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
send(-1, "cnr_mode", { version = VERSION, startGrid = true })
pushRules()
panelService:pushLobby(lobbyState)
log("Cops and Robbers " .. VERSION .. " loaded on " .. mapName .. " (" .. pluginDir .. ")")
