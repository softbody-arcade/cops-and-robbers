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
local tables = require("cnr.tables")
local build = require("cnr.build")
local panel = require("cnr.panel")
local panelService = require("arcade.panel").new(messages, roster)
local autoRounds = require("arcade.autoRounds")
local nextRound = autoRounds.new()
local sky = require("cnr.sky")
local traffic = require("arcade.traffic")
local trafficService = traffic.new(roster, messages)
local cars = require("arcade.cars").new(roster, messages, trafficService)
local spectators = require("arcade.spectators").new(roster, messages)
local trafficNote = require("cnr.traffic").note

local VERSION = "2.16.0"
local log, send, notify = messages.log, messages.send, messages.notify
local reply, refuse, broadcast = messages.reply, messages.refuse, messages.broadcast
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
local leaderboardPath = dataDir .. "leaderboard.json"
local buildPath = dataDir .. "build.json"
local settings = require("arcade.settings").new(pluginDir .. "config.json", config.declaration, log)
local playerColors = require("arcade.playerColors").new(dataDir .. "colors.json", roster, messages)

local cfg
local game
local stationsRequested = roster:perPlayer("stationsRequested", "early")
local lastIssuer
local REFUSAL_LOG_SECONDS = 10
local refusalLoggedAt = roster:perPlayer("refusalLoggedAt", "early")
local gridClients = roster:perPlayer("gridClients", "early")
local START_ROAD_SEARCH = 2000
local WATCHING_AI = "You can't spawn a car while watching the AI"
local serverClock = MP.CreateTimer()

math.randomseed(os.time())

local function now() return serverClock:GetCurrent() end

local boardSubs = roster:perPlayer("boardSubs", "early")
local leaderboardLocked = false

local function useConfig(values)
  cfg = values
  game.current.cfg = values
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
  game.board = leaderboard.load(decoded)
end

local function loadBuild()
  local decoded, corrupt = store.decode(buildPath)
  game.currentBuild = not corrupt and build.normalize(decoded) or nil
  if decoded ~= nil and not game.currentBuild or corrupt then
    local aside = buildPath .. ".corrupt-" .. os.time()
    FS.Rename(buildPath, aside)
    log("build.json was unreadable, moved to " .. aside .. "; no build")
  elseif game.currentBuild then
    log("Build: " .. build.label(game.currentBuild))
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
  local currentBuild = game.currentBuild
  if not currentBuild then return nil end
  return {
    model = currentBuild.model, step = currentBuild.step, name = currentBuild.name,
    config = { format = 2, model = currentBuild.model, parts = currentBuild.parts, vars = currentBuild.vars },
  }
end

local function saveLeaderboard(run)
  leaderboard.add(game.board, run)
  if leaderboardLocked then return log("leaderboard not saved: the old file could not be moved aside") end
  if not saveJson(leaderboardPath, game.board) then table.remove(game.board.runs) end
end

local function roundCarActive()
  local current = game.current
  return current.vehicle ~= nil and current.state ~= "idle" and current.state ~= "picking"
end

local function stationsPath() return stationsDir .. game.mapName .. ".json" end

local function loadStations()
  local decoded = store.decode(stationsPath())
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

local function saveStations(updated)
  local ok, err = saveJson(stationsPath(), { stations = updated })
  if not ok then return nil, err end
  game.stations = updated
  return true
end

local function requestStations(pid)
  if #game.stations > 0 or stationsRequested[pid] then return end
  stationsRequested[pid] = true
  send(pid, "cnr_requestStations", { map = game.mapName })
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

local function aiSlotForVid(vid)
  for id, car in pairs(game.aiCars) do
    if car.vid == vid then return id end
  end
end

local function removeAICar(id)
  if id and game.aiCars[id] then
    game.aiCars[id] = nil
    game.current:forgetVehicleSight(id)
  end
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
  local cops = leaderboard.cops(game.board, f, BOARD_TOP, cfg.assistMinSightPercent)
  for _, c in ipairs(cops) do
    if c.key == viewerKey then c.me = true end
    c.key = nil
  end
  local players = leaderboard.players(game.board, f, cfg.assistMinSightPercent)
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

local lastRulesSignature
local function pushRules(pid, onlyChanged)
  local payload = rules.payload(cfg, traffic.perPlayer(cfg.trafficPerPlayer, traffic.maxCars(), 1))
  local signature = panel.signature(payload)
  if onlyChanged and signature == lastRulesSignature then return end
  send(pid or -1, "cnr_rules", payload)
  lastRulesSignature = signature
end

game = require("cnr.game").new({
  messages = messages, roster = roster, cars = cars, spectators = spectators,
  traffic = trafficService, playerColors = playerColors, settings = settings, nextRound = nextRound,
  now = now, useConfig = useConfig, pushRules = pushRules, saveLeaderboard = saveLeaderboard, pushBoard = pushBoard,
})

local function plannedRunner(players)
  local countsByName = {}
  for p, name in pairs(players) do countsByName[name] = game.runCounts[roster:key(p)] or 0 end
  local lastPid = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
  local lastName = lastPid and MP.GetPlayerName(lastPid) or nil
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

local function startRound(runnerId, issuerId, players, opts)
  local current = game.current
  local effects = current:start(now(), runnerId, issuerId, players, opts)
  if current:isActive() then cars:setPublishing(true) end
  game:applyEffects(effects)
end

panelService:command("start", function(pid, cmd)
  local current = game.current
  if current:isActive() and current.test then
    game:applyEffects(current:stop(now(), current.issuerId))
  end
  if current:isActive() then return refuse(pid, "A round is already running") end
  if cfg.carMode == "evolving" and not game.currentBuild then return refuse(pid, "Start a new build first") end
  nextRound:cancel()
  lastIssuer = pid
  local players = MP.GetPlayers() or {}
  local candidates, count = roster:playing(players)
  if count == 0 then return refuse(pid, "Everyone is sitting out") end
  local query = cmd.rest
  local runnerId, err
  if query and query:lower() == "again" then
    runnerId = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
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
  cars:clearRound()
  roster:clear("trafficOpen")
  roster:clear("trafficVids")
  game.partsBaseline = {}
  game.missingCount = {}
  game.lastResult = nil
  useConfig(settings:snapshot())
  local sittingOut = roster:sitOutSnapshot()
  startRound(runnerId, pid, players, { gridPlanner = gridClients[runnerId] and runnerId, build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random), traffic = traffic.perPlayer(cfg.trafficPerPlayer, traffic.maxCars(), 1), trafficRunnerOnly = cfg.trafficRunnerOnly == true, sittingOut = sittingOut })
end)

panelService:command("test", function(pid, cmd)
  if game.current:isActive() then return refuse(pid, "A round is already running") end
  cars:clearRound()
  roster:clear("trafficOpen")
  roster:clear("trafficVids")
  game.partsBaseline = {}
  game.missingCount = {}
  game.previousRoundSerial = game.connectionSerial[pid] or 0
  local role = cmd.args[1] and cmd.args[1]:lower()
  if cfg.carMode == "evolving" and not game.currentBuild then return refuse(pid, "Start a new build first") end
  useConfig(settings:snapshot())
  local opts = { gridPlanner = gridClients[pid] and pid, test = true, role = role, aiOnly = roster:sittingOut(pid), build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random) }
  startRound(nil, pid, roster:players(), opts)
end)

local function lobbyState()
  local current = game.current
  local players = MP.GetPlayers() or {}
  local online = 0
  for _ in pairs(players) do online = online + 1 end
  local practice
  if current:isActive() and current.test then practice = current.players[current.issuerId] or MP.GetPlayerName(current.issuerId) or "someone" end
  return { online = online, practice = practice, active = current:isActive() and not current.test or false }
end

panelService:command("go", function(pid)
  game:applyEffects(game.current:go(now(), pid))
end)

panelService:command("stop", function(pid)
  local current = game.current
  local wasActive = current:isActive()
  game:applyEffects(current:stop(now(), pid))
  if not wasActive then send(-1, "cnr_roundEnd", { reason = "cancelled" }) end
end)

panelService:command("end", function(pid)
  game:applyEffects(game.current:endCalled(now(), pid))
end)

panelService:command("reroll", function(pid)
  game:applyEffects(game.current:reroll(now(), pid))
end)

panelService:command("sky", function(pid)
  local current = game.current
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
  local car = game:carFor(pid)
  if not car then return refuse(pid, "You need to be in a vehicle") end
  local updated = table.move(game.stations, 1, #game.stations, 1, {})
  updated[#updated + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
  local ok, err = saveStations(updated)
  if not ok then return refuse(pid, err) end
  reply(pid, string.format("Gas station added (%d on %s)", #game.stations, game.mapName))
end)

panelService:command("removestation", function(pid)
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
  local ok, err = saveStations(updated)
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

local function panelState()
  local current = game.current
  local running = current.state == "running"
  local players = MP.GetPlayers() or {}
  local candidates, count = roster:playing(players)
  local realRound = current:isActive() and not current.test
  local entries, loading = playerEntries(players, realRound)
  local nextName = not realRound and nextRunnerName(candidates) or nil
  local lastPid = game.lastRunnerKey and roster:pidForKey(game.lastRunnerKey)
  local autoNext
  local autoNextAt = nextRound:pending()
  if autoNextAt and not realRound then
    autoNext = { seconds = math.max(0, math.ceil(autoNextAt - now())), runner = nextName }
  end
  local buildInfo
  local currentBuild = game.currentBuild
  if currentBuild then
    buildInfo = { label = build.label(currentBuild), step = currentBuild.step, name = currentBuild.name, lastChange = build.lastChange(currentBuild) }
  end
  return panel.snapshot({
    version = VERSION, map = game.mapName, phase = current.state,
    runner = current.runnerId and current:runnerName() or nil,
    car = roundCarActive() and current.vehicle.model or nil,
    test = current.test == true,
    elapsed = running and current.releasedAt and math.max(0, now() - current.releasedAt) or nil,
    players = entries, cfg = cfg, defaults = config.DEFAULTS,
    autoNextRound = settings:get("autoNextRound"),
    evolving = current.evolving == true,
    build = buildInfo,
    nextRunner = nextName, lastRunner = lastPid and players[lastPid] or nil,
    loading = loading, autoNext = autoNext, lastResult = game.lastResult,
    stationCount = #game.stations,
    skyRandom = sky.hasRandom(cfg),
    trafficNote = trafficNote(cfg.trafficPerPlayer, traffic.maxCars(), count, cfg.trafficRunnerOnly == true),
  })
end

local function panelBuild(pid, msg)
  local function answer(text, tone) send(pid, "cnr_panelReply", { text = text, tone = tone }) end
  if game.current:isActive() then return answer("Stop the round first", "warn") end
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
  game.currentBuild = replacement
  panelService:push(panelState)
  answer(replacement and "New build: " .. build.label(replacement) or "Build reset")
end

local function reloadRound()
  cfg = settings:load()
  game.current = round.new(cfg)
end

local function panelSettings(pid, values, id)
  if type(id) ~= "number" and type(id) ~= "string" then id = nil end
  local function answer(ok, text, keys) send(pid, "cnr_panelReply", { ok = ok, text = text, keys = keys, id = id }) end
  if game.current:isActive() then return answer(false, "Stop the round first") end
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
    for _, st in ipairs(game.stations) do
      list[#list + 1] = { x = st.x, y = st.y, z = st.z }
    end
    send(pid, "cnr_stationList", { map = game.mapName, stations = list })
  elseif msg.action == "settings" then
    panelSettings(pid, msg.values, msg.id)
  elseif msg.action == "build" then
    panelBuild(pid, msg)
  elseif msg.action == "apply" then
    local current = game.current
    if pid ~= current.runnerId then return send(pid, "cnr_panelReply", { text = "Only the runner can apply the change", tone = "warn" }) end
    local ran, err = messages.mirrored(pid, function() game:applyEffects(current:apply(now(), pid)) end)
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
  local current = game.current
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" then return end
  if not current.evolving or current.state ~= "applying" or pid ~= current.runnerId then return end
  if d.model ~= nil and d.model ~= current.vehicle.model then return log("ignored a setup for another car model from " .. tostring(pid)) end
  local valid = build.normalize({ model = current.vehicle.model, parts = d.parts, vars = d.vars })
  if not valid then return log("ignored a malformed setup from " .. tostring(pid)) end
  local setup = { parts = valid.parts, vars = valid.vars }
  local changes = cleanChanges(d.changes)
  if not current.test and game.currentBuild then
    local name = MP.GetPlayerName(pid) or tostring(pid)
    local nb, changed = build.apply(game.currentBuild, setup, changes, name, os.time())
    if nb ~= game.currentBuild then
      local saved, err = saveJson(buildPath, nb)
      if not saved then return refuse(pid, err) end
      game.currentBuild = nb
      current.buildStep = nb.step
    end
    if changed then broadcast(build.changeLine(nb.step, name, changes)) end
  end
  local cfgTable = { format = 2, model = current.vehicle.model, parts = setup.parts, vars = setup.vars }
  game:applyEffects(current:setupReceived(now(), pid, cfgTable))
  panelService:push(panelState)
end

function cnrOnChange(pid, data)
  local current = game.current
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  if not current.evolving or current.state ~= "prep" or pid ~= current.runnerId then return end
  current.queued = { runner = MP.GetPlayerName(pid) or tostring(pid), changes = cleanChanges(d.changes) }
  for p in pairs(current.players) do
    if not round.isAI(p) then send(p, "cnr_queued", current.queued) end
  end
end

function cnrOnMissing(pid, data)
  local current = game.current
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" or #d.parts == 0 then return end
  if not current:isActive() or current.players[pid] == nil then return end
  game.missingCount[pid] = #d.parts
  local names = {}
  for i, part in ipairs(d.parts) do
    if i > 6 then names[#names + 1] = string.format("+%d more", #d.parts - 6) break end
    names[#names + 1] = tostring(part)
  end
  send(current.test and current.issuerId or -1, "cnr_notice", { msg = string.format("⚠ %s is missing: %s", MP.GetPlayerName(pid) or tostring(pid), table.concat(names, ", ")), tone = "warn" })
end

local function matchesRoundVehicle(decoded)
  local current = game.current
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  return not pcFile or current.evolving or normalizeConfig(pcFile) == normalizeConfig(current.vehicle.config)
end

local function vehicleAllowed(pid, vid, data, isSpawn)
  local current = game.current
  if current:isActive() and current.aiOnly and pid == current.issuerId then
    local decoded = parseVehicleData(data)
    if current.state == "picking" then return not isSpawn, decoded, isSpawn and WATCHING_AI or nil end
    local model = current.vehicle and current.vehicle.model
    local roundModel = model ~= nil and decoded ~= nil and decoded.jbm == model
    if not roundModel or (isSpawn and game.aiSpawnsLeft <= 0) then return false, decoded, isSpawn and WATCHING_AI or nil end
    if isSpawn then game.aiSpawnsLeft = game.aiSpawnsLeft - 1 end
    return true, decoded
  end
  local own = cars:activeVid(pid)
  local trafficCount = trafficService:openCount(pid)
  local roundPlayer = roundCarActive() and current.players[pid] ~= nil
  if isSpawn and roundPlayer and not current.test and (cars:permitted(pid) or cars:replacementAllowed(pid)) then
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
  if isSpawn and not current.test and cars:firstVid(pid) then return false, decoded end
  return true, decoded
end

local function checkParts(pid, decoded)
  local current = game.current
  if not decoded or type(decoded.vcf) ~= "table" or decoded.vcf.parts == nil then return end
  local parts = decoded.vcf.parts
  local entry = game.partsBaseline[pid]
  local mayChange = current.evolving and (current.state == "prep" or current.state == "applying") and pid == current.runnerId
  if entry == nil then
    game.partsBaseline[pid] = { parts = parts, announced = false }
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
  local current = game.current
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
  local current = game.current
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
  cars:forgetPreRound(pid, vid)
  if roundSpawn then
    local _, replaced = cars:claim(pid, vid)
    if replaced then current:forgetVehicleSight(pid) end
  elseif tracksActive(pid) and not cars:confirmed(pid) and not trafficService:openCount(pid) then
    cars:setActive(pid, vid)
  end
  return 0
end

function cnrOnVehicleEdited(pid, vid, data)
  local current = game.current
  if cars:isPreRound(pid, vid) then return 0 end
  if cars:confirmed(pid) and cars:activeVid(pid) ~= vid then
    if pid ~= current.issuerId or not aiSlotForVid(vid) then return 0 end
  end
  local allowed, decoded, why = vehicleAllowed(pid, vid, data, false)
  if not allowed then
    logVehicleRefusal(pid, "edited", vid, decoded)
    refuse(pid, why or "Only the round car is allowed")
    return 1
  end
  local notOwn = vid ~= cars:activeVid(pid) and (current.test or trafficService:openCount(pid))
  if roundCarActive() and current.players[pid] and not notOwn then checkParts(pid, decoded) end
  if tracksActive(pid) and not trafficService:openCount(pid) then
    if cars:setActive(pid, vid) then current:forgetVehicleSight(pid) end
  end
  return 0
end

function cnrOnVehicleDeleted(pid, vid)
  local current = game.current
  if pid == current.issuerId then removeAICar(aiSlotForVid(vid)) end
  cars:forgetPreRound(pid, vid)
  if cars:activeVid(pid) == vid and cars:setActive(pid, nil) then
    current:forgetVehicleSight(pid)
    cars:publish()
  end
end

function cnrOnVehicleReset(pid, vid)
  local own = cars:activeVid(pid)
  if (own or cars:confirmed(pid) or trafficService:openCount(pid)) and own ~= vid then return end
  game:applyEffects(game.current:vehicleReset(now(), pid))
end

function cnrOnColor(pid, data)
  local current = game.current
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
    game:placing(pid)
    send(pid, "cnr_paint", { color = playerColors:get(pid) })
  end
end

function cnrOnSitOut(pid, data)
  local current = game.current
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.on) ~= "boolean" then return end
  roster:setSitOut(pid, d.on)
  send(pid, "cnr_sitOut", { on = d.on })
  if current:isActive() and not current.test then
    notify(pid, d.on and "You sit out from the next round" or "You play again from the next round")
  end
end

function cnrOnPlayerJoin(pid)
  local current = game.current
  send(pid, "cnr_mode", { version = VERSION, startGrid = true })
  playerColors:sendMine(pid)
  pushRules(pid)
  panelService:pushLobby(lobbyState, pid)
  requestStations(pid)
  game:applyEffects(current:playerJoined(now(), pid, MP.GetPlayerName(pid)))
  if current.test and current.vehicle then game:parkBystander(pid) end
  if current.evolving and current.state == "prep" and current.queued and current.players[pid] then
    send(pid, "cnr_queued", current.queued)
  end
  cars:publish(pid)
end

function cnrOnPlayerDisconnect(pid)
  roster:leaveEarly(pid)
  game:applyEffects(game.current:playerLeft(now(), pid))
  roster:leaveLate(pid)
  cars:publish()
end

function cnrOnStartGridReady(pid)
  gridClients[pid] = true
end

local function finite(n)
  return type(n) == "number" and math.abs(n) < math.huge
end

function cnrOnLightningClock(pid, data)
  local current = game.current
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
  if game.current.aiOnly then return nil end
  local vehicles = cars:vehicles(pid)
  local vid, data = next(vehicles)
  if not vid or next(vehicles, vid) then return nil end
  local vehicle = parseVehicleData(data)
  if vehicle and vehicle.jbm == "unicycle" then return nil end
  local raw = cars:rawPosition(pid, vid)
  if raw then return vec.toVec(raw.pos) end
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
  local current = game.current
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
  game:applyEffects(current:gridReceived(now(), slots, MP.GetPlayers() or {}))
end

function cnrOnVehiclePicked(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.model) ~= "string" then return end
  game:applyEffects(game.current:vehiclePicked(now(), pid, decoded.model, decoded.config, MP.GetPlayers() or {}))
end

local function integer(n)
  return finite(n) and n % 1 == 0
end

function cnrOnMyVehicle(pid, data)
  local current = game.current
  local ok, decoded = pcall(Util.JsonDecode, data)
  local vid = ok and type(decoded) == "table" and tonumber(decoded.vid)
  if not integer(vid) or vid < 0 or not roundCarActive() or current.players[pid] == nil then return end
  local owned = cars:vehicles(pid)
  if not owned[vid] or (pid == current.issuerId and aiSlotForVid(vid)) then return end
  if cars:confirm(pid, vid) then current:forgetVehicleSight(pid) end
  game:placed(pid)
  log(string.format("%s placed the round car (vid %s)", MP.GetPlayerName(pid) or tostring(pid), tostring(vid)))
  local rebuildId = tonumber(decoded.rebuild)
  cars:acknowledgeRebuild(pid, rebuildId)
  game:applyEffects(current:vehicleReady(now(), pid, rebuildId))
  if game.pendingAISetup then game:dispatchAISetup() else game:openTraffic(pid) end
  cars:publish()
end

function cnrOnTrafficCars(pid, data)
  local current = game.current
  if not trafficService:openCount(pid) then return end
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.vids) ~= "table" then return end
  trafficService:report(pid, d.vids, cars:activeVid(pid), function(vid)
    return current.test and pid == current.issuerId and aiSlotForVid(vid)
  end)
end

local function registerAICar(pid, a, owned)
  if type(a) ~= "table" then return end
  local id, vid, serial = a.id, a.vid, a.instance
  if not round.isAI(id) or not game.current.players[id] then return end
  if not integer(vid) or vid < 0 or not owned[vid] or cars:confirmedVid(pid) == vid then return end
  if serial ~= nil then
    local latest = math.max(game.previousRoundSerial, game.aiSlotSerial[id] or 0, game.aiVidSerial[vid] or 0)
    if not integer(serial) or serial <= latest then return end
    game.aiSlotSerial[id], game.aiVidSerial[vid] = serial, serial
    game.connectionSerial[pid] = math.max(game.connectionSerial[pid] or 0, serial)
  elseif game.aiSlotSerial[id] or game.aiVidSerial[vid] or (game.aiCars[id] and game.aiCars[id].vid == vid) then
    return
  end
  removeAICar(id)
  removeAICar(aiSlotForVid(vid))
  game.aiCars[id] = {vid=vid, instance=serial}
  cars:forgetPreRound(pid, vid)
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
  local current = game.current
  if not current.test or pid ~= current.issuerId then return end
  local decoded = decodeObservationPacket(data)
  if not decoded or type(decoded.ai) ~= "table" then return end
  local owned = cars:vehicles(pid)
  for _, a in ipairs(decoded.ai) do registerAICar(pid, a, owned) end
end

function cnrOnBoard(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" then return end
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

function cnrOnSight(pid, data)
  local current = game.current
  local d = decodeObservationPacket(data)
  if not d or type(d.seen) ~= "boolean" then return end
  if not cars:confirmedVid(current.runnerId) and not game.aiCars[current.runnerId] then return end
  if d.aiId ~= nil or d.instance ~= nil then
    if not current.test or pid ~= current.issuerId or not round.isAI(d.aiId) or not integer(d.instance) then return end
    local car = game.aiCars[d.aiId]
    if not car or car.instance ~= d.instance then return end
    local owned = cars:vehicles(pid)
    if owned[car.vid] then current:aiSightReport(now(), pid, d.aiId, d.seen) end
  elseif cars:confirmedVid(pid) then
    current:sightReport(now(), pid, d.seen)
  end
end

function cnrOnCover(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  game.current:coverReport(now(), pid, d.covered == true)
end

function cnrOnStations(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or decoded.map ~= game.mapName or #game.stations > 0 then return end
  for _, s in ipairs(decoded.stations or {}) do
    local v = vec.toVec(s)
    if v then
      v.r = tonumber(s.r) or 0
      game.stations[#game.stations + 1] = v
    end
  end
  if #game.stations > 0 then
    saveStations(game.stations)
    log(string.format("%d gas stations detected for %s", #game.stations, game.mapName))
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
    if not game.current:isActive() then useConfig(settings:effective()) end
    pushRules()
  end,
  startNext = startNext,
  reloadRound = reloadRound,
  isActive = function() return game.current:isActive() end,
  send = send,
})

function cnrTick()
  panelService:tick(panelState, lobbyState)
  if nextRound:due(now()) then startScheduled() end
  local current = game.current
  if not current:isActive() then return end
  game:dispatchAISetup()
  if game.pendingAISetup and now() >= game.pendingAISetup.deadline then
    local pid = game.pendingAISetup.pid
    local waitingForCar = not game.pendingAISetup.payload.aiOnly and cars:placementPending(pid)
    game:applyEffects(current:stop(now(), pid))
    notify(pid, waitingForCar and "Practice cancelled: your round car did not register in time."
      or "Practice cancelled: too few free vehicle slots for the AI. Free a slot or increase MaxCars.", "warn")
    return
  end
  local positions = {}
  for pid in pairs(current.players) do positions[pid] = game:carFor(pid) end
  game:announceLightning(positions[current.runnerId])
  game:applyEffects(current:tick(now(), positions, game.stations, trafficService:cars()))
end

FS.CreateDirectory(stationsDir)
reloadRound()
loadLeaderboard()
loadBuild()
playerColors:load()
game.mapName = (tostring(MP.Get(MP.Settings.Map) or ""):match("levels/([^/]+)/")) or "unknown"
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
log("Cops and Robbers " .. VERSION .. " loaded on " .. game.mapName .. " (" .. pluginDir .. ")")
