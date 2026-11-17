local pluginDir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./")
package.path = pluginDir .. "?.lua;" .. package.path

local vec = require("cnr.vec")
local config = require("cnr.config")
local rules = require("cnr.rules")
local round = require("cnr.round")
local leaderboard = require("cnr.leaderboard")
local commands = require("cnr.commands")
local colors = require("cnr.colors")
local tables = require("cnr.tables")
local geo = require("cnr.geo")
local build = require("cnr.build")
local panel = require("cnr.panel")
local sky = require("cnr.sky")
local traffic = require("cnr.traffic")

local VERSION = "2.9.5"
local PREFIX = "[CnR] "
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
local leaderboardPath = dataDir .. "leaderboard.json"
local buildPath = dataDir .. "build.json"
local currentBuild
local colorsPath = dataDir .. "colors.json"

local cfg
local current
local board
local mapName
local stations = {}
local activeVid = {}
local trafficOpen = {}
local trafficVids = {}
local lastRoundCars
local stationsRequested = {}
local partsBaseline = {}
local aiVid = {}
local runCounts = {}
local lastRunnerKey
local missingCount = {}
local lastResult
local currentRunnerKey
local autoNextAt
local startAutoRound
local lastIssuer
local rawConfig = {}
local geoMode = false
local geoRef
local geoReports = {}
local geoStations = {}
local localStationsCache
local lastGeoByName = {}
local GEO_STALE_SECONDS = 2
local PARTS_PLACING_SECONDS, PARTS_SETTLE_SECONDS = 10, 3
local GEO_STATION_MERGE_METERS = 50
local GEO_STATION_RADIUS = 20
local GEO_RESET_VERDICT_DELAY = 1
local GEO_LIVE_MIN_SECONDS = 3
local lastLiveSentAt = -math.huge
local pendingResetVerdicts = {}
local REFUSAL_LOG_SECONDS = 10
local refusalLoggedAt = {}
local colorStore = {}
local sitOut = {}
local spectators = {}
local serverClock = MP.CreateTimer()

math.randomseed(os.time())

local function log(msg) print(PREFIX .. msg) end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, content)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  f:write(content)
  f:close()
  FS.Remove(path)
  FS.Rename(tmp, path)
end

local function decodeFile(path)
  local s = readFile(path)
  if not s or s == "" then return nil, false end
  local ok, value = pcall(Util.JsonDecode, s)
  if not ok or type(value) ~= "table" then return nil, true end
  return value, false
end

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

local boardSubs = {}
local leaderboardLocked = false
local panelSubs = {}
local panelMirror
local lastPanelSig
local lastLobbySig
local lastPanelError
local lastLobbyError

local function send(pid, event, payload)
  if type(pid) ~= "number" or (pid < 0 and pid ~= -1) then return end
  MP.TriggerClientEvent(pid, event, Util.JsonEncode(payload or {}))
end
local function notify(pid, msg, tone)
  send(pid, "cnr_notice", { msg = msg, tone = tone or "info" })
end
local function reply(pid, msg, tone)
  if panelMirror and pid == panelMirror then
    send(pid, "cnr_panelReply", { text = msg, tone = tone })
  else
    notify(pid, msg, tone)
  end
end
local function refuse(pid, msg) reply(pid, msg, "warn") end
local function broadcast(msg, tone) notify(-1, msg, tone) end

local function loadConfig()
  local raw, corrupt = decodeFile(pluginDir .. "config.json")
  if corrupt then log("config.json is not valid JSON, using defaults") end
  rawConfig = type(raw) == "table" and raw or {}
  local warnings
  cfg, warnings = config.merge(raw)
  for _, w in ipairs(warnings) do log("config: " .. w) end
end

local function loadLeaderboard()
  local decoded, corrupt = decodeFile(leaderboardPath)
  if not corrupt and not leaderboard.validShape(decoded) then
    corrupt = true
    decoded = nil
  end
  local aside, why
  if corrupt then
    aside, why = leaderboardPath .. ".corrupt-" .. os.time(), "was unreadable"
  elseif not leaderboard.isCurrent(decoded) then
    aside, why = dataDir .. "leaderboard-1.6.json", "is the old format"
    if FS.Exists(aside) then aside = dataDir .. "leaderboard-1.6-" .. os.time() .. ".json" end
  end
  if aside then
    local moved, err = FS.Rename(leaderboardPath, aside)
    if moved == false then
      leaderboardLocked = true
      log(string.format("leaderboard.json %s but could not be moved to %s (%s): runs are not saved until this is fixed", why, aside, tostring(err)))
    else
      log(string.format("leaderboard.json %s, moved to %s; starting a fresh one", why, aside))
    end
    decoded = nil
  end
  board = leaderboard.load(decoded)
end

local function loadBuild()
  local decoded, corrupt = decodeFile(buildPath)
  currentBuild = not corrupt and build.normalize(decoded) or nil
  if decoded ~= nil and not currentBuild or corrupt then
    local aside = buildPath .. ".corrupt-" .. os.time()
    FS.Rename(buildPath, aside)
    log("build.json was unreadable, moved to " .. aside .. "; no build")
  elseif currentBuild then
    log("Build: " .. build.label(currentBuild))
  end
end

local function saveBuild()
  if currentBuild then writeFile(buildPath, Util.JsonPrettify(Util.JsonEncode(currentBuild))) end
end

local function backupBuild()
  if not FS.Exists(buildPath) then return end
  local base = dataDir .. "build-" .. os.time()
  local aside, n = base .. ".json", 1
  while FS.Exists(aside) do
    n = n + 1
    aside = string.format("%s-%d.json", base, n)
  end
  FS.Rename(buildPath, aside)
end

local function buildOpts()
  if not currentBuild then return nil end
  return {
    model = currentBuild.model, step = currentBuild.step, name = currentBuild.name,
    config = { format = 2, model = currentBuild.model, parts = currentBuild.parts, vars = currentBuild.vars },
  }
end

local function saveLeaderboard()
  if leaderboardLocked then return log("leaderboard not saved: the old file could not be moved aside") end
  writeFile(leaderboardPath, Util.JsonPrettify(Util.JsonEncode(board)))
end

local function loadColors()
  colorStore = colors.load((decodeFile(colorsPath)))
end

local function saveColors()
  writeFile(colorsPath, Util.JsonPrettify(Util.JsonEncode(colorStore)))
end

local function colorTable(c)
  return c and { hex = c.hex, r = c.r, g = c.g, b = c.b } or nil
end

local function playerKey(pid)
  local ids = MP.GetPlayerIdentifiers and MP.GetPlayerIdentifiers(pid)
  if type(ids) == "table" and ids.beammp and tostring(ids.beammp) ~= "" then
    return "beammp:" .. tostring(ids.beammp)
  end
  return "name:" .. tostring(MP.GetPlayerName(pid) or pid)
end

local function pidForKey(key)
  for pid in pairs(MP.GetPlayers() or {}) do
    if playerKey(pid) == key then return pid end
  end
  return nil
end

local function colorFor(pid)
  local c = colors.get(colorStore, playerKey(pid)) or colors.get(colorStore, MP.GetPlayerName(pid) or "")
  return colorTable(c)
end

local function roundCarActive()
  return current.vehicle ~= nil and current.state ~= "idle" and current.state ~= "picking"
end

local function playing(players)
  local list, count = {}, 0
  for pid, name in pairs(players) do
    if not sitOut[pid] then
      list[pid] = name
      count = count + 1
    end
  end
  return list, count
end

local function stationsPath() return stationsDir .. mapName .. ".json" end

local function loadStations()
  local decoded = decodeFile(stationsPath())
  stations = {}
  geoStations = {}
  localStationsCache = nil
  if geoMode then
    for _, s in ipairs(decoded and decoded.stations or {}) do
      local lat, lon = tonumber(s.lat), tonumber(s.lon)
      if geo.valid(lat, lon) then
        geoStations[#geoStations + 1] = { lat = lat, lon = lon, r = tonumber(s.r) or GEO_STATION_RADIUS, name = s.name }
      end
    end
    log(string.format("%d gas stations loaded for %s", #geoStations, mapName))
    return
  end
  for _, s in ipairs(decoded and decoded.stations or {}) do
    local v = vec.toVec(s)
    if v then
      v.r = tonumber(s.r) or 0
      stations[#stations + 1] = v
    end
  end
  log(string.format("%d gas stations loaded for %s", #stations, mapName))
end

local function saveStations()
  localStationsCache = nil
  local list = geoMode and geoStations or stations
  writeFile(stationsPath(), Util.JsonPrettify(Util.JsonEncode({ stations = list })))
end

local function requestStations(pid)
  if geoMode then return end
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
  if trafficOpen[pid] then return nil end
  vid = firstVid(pid)
  activeVid[pid] = vid
  return vid
end

local function maxCars()
  if not MP.Settings or MP.Settings.MaxCars == nil then return nil end
  local ok, value = pcall(MP.Get, MP.Settings.MaxCars)
  return ok and tonumber(value) or nil
end

local function trafficFor(pid)
  if cfg.trafficRunnerOnly and not current.test and pid ~= current.runnerId then return 0 end
  return traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, current.test and pid == current.issuerId)
end

local function openTraffic(pid)
  if trafficOpen[pid] or not current:isActive() or current.players[pid] == nil then return end
  local n = trafficFor(pid)
  if n <= 0 then return end
  trafficOpen[pid] = n
  send(pid, "cnr_trafficStart", { count = n })
end

local function extraCars(pid)
  local vehicles = MP.GetPlayerVehicles(pid)
  local n = 0
  if type(vehicles) ~= "table" then return n end
  for vid in pairs(vehicles) do
    if vid ~= activeVid[pid] then n = n + 1 end
  end
  return n
end

local function roundCarKeys()
  local keys = {}
  for p in pairs(current.players) do
    if not round.isAI(p) and activeVid[p] then keys[#keys + 1] = p .. "-" .. activeVid[p] end
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

local function ensureRef(lat, lon)
  if not geoRef then geoRef = geo.newRef(lat, lon) end
  return geoRef
end

local function geoOf(pid)
  local r = pid ~= nil and geoReports[pid]
  if not r or now() - r.t > GEO_STALE_SECONDS then return nil end
  return r
end

local function geoPoint(r)
  return r and { lat = r.lat, lon = r.lon, h = r.h } or nil
end

local function roundStations()
  if not geoMode then return stations end
  if not geoRef then return {} end
  if not localStationsCache then
    localStationsCache = {}
    for _, s in ipairs(geoStations) do
      local p = geo.toLocal(geoRef, s.lat, s.lon, 0)
      p.z = nil
      local here = { x = p.x, y = p.y, z = 0, r = s.r }
      localStationsCache[#localStationsCache + 1] = here
    end
  end
  return localStationsCache
end

local function carFor(pid)
  if pid == nil then return nil end
  if geoMode then
    local r = geoOf(pid)
    if not r then return nil end
    local pos = geo.toLocal(ensureRef(r.lat, r.lon), r.lat, r.lon, r.h)
    pos.z = 0
    return { pos = pos, vel = { x = r.ve, y = r.vn, z = r.vu }, geo = geoPoint(r) }
  end
  local owner, vid = pid, nil
  if round.isAI(pid) then
    owner, vid = current.issuerId, aiVid[pid]
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

local function trafficCars()
  if geoMode then return nil end
  local list = {}
  for pid, set in pairs(trafficVids) do
    for vid in pairs(set) do
      local raw, err = MP.GetPositionRaw(pid, vid)
      if not (err and err ~= "") and type(raw) == "table" then
        local pos, vel = vec.toVec(raw.pos), vec.toVec(raw.vel)
        if pos and vel then list[#list + 1] = { pos = pos, vel = vel, traffic = true } end
      end
    end
  end
  return list
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
  local ok, state = pcall(boardState, boardSubs[pid], playerKey(pid))
  if ok then send(pid, "cnr_boardState", state) else log("board update failed: " .. tostring(state)) end
end

local function pushBoard()
  for pid in pairs(boardSubs) do sendBoard(pid) end
end

local function applyEffects(effects)
  for _, e in ipairs(effects) do
    if e.kind == "reply" then
      reply(e.pid, e.msg, e.tone)
    elseif e.kind == "broadcast" then
      if e.meters then log(string.format("%s %.0f m", e.msg, e.meters)) end
      if e.to then notify(e.to, e.msg, e.tone) else broadcast(e.msg, e.tone) end
    elseif e.kind == "pickVehicle" then
      send(e.pid, "cnr_pickVehicle", { includeMods = cfg.includeModVehicles, excludedModels = cfg.excludedModels })
    elseif e.kind == "setup" then
      if e.role == "runner" and not current.test then
        local key = playerKey(e.pid)
        lastRunnerKey = key
        currentRunnerKey = key
      end
      local runnerCar = carFor(current.runnerId)
      local resumeGeo
      if geoMode and e.resumePos then resumeGeo = lastGeoByName[MP.GetPlayerName(e.pid) or ""] end
      placing(e.pid)
      log(string.format("setup sent to %s: %s, %s%s", MP.GetPlayerName(e.pid) or tostring(e.pid), e.role, tostring(e.phase), e.resumePos and ", resuming" or ""))
      send(e.pid, "cnr_roundSetup", {
        geo = geoMode, runnerGeo = geoMode and geoPoint(geoOf(current.runnerId)) or nil,
        resumeGeo = resumeGeo,
        runnerId = current.runnerId, runnerName = current:runnerName(), role = e.role, copIndex = e.copIndex,
        model = current.vehicle.model, config = current.vehicle.config,
        phase = e.phase, countdownRemaining = e.countdownRemaining, chaseElapsed = e.chaseElapsed,
        headStartRemaining = e.headStartRemaining, inPlace = e.inPlace,
        resumePos = not geoMode and e.resumePos or nil,
        color = e.colorHex and colorTable((colors.parseHex(e.colorHex))) or colorFor(e.pid),
        runnerPos = not geoMode and runnerCar and runnerCar.pos or nil,
        copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
        sightMaxMeters = cfg.sightMaxMeters,
        runnerShown = e.runnerShown, heli = e.heli,
        evolving = current.evolving or nil, rebuild = current.rebuildId, practice = current.test or nil,
        sky = sky.payload(current.sky, cfg, current.countdownStartedAt and math.max(0, now() - current.countdownStartedAt) or nil),
      })
    elseif e.kind == "spectate" then
      spectators[e.pid] = true
      log(string.format("%s spectates (%s)", MP.GetPlayerName(e.pid) or tostring(e.pid), tostring(e.phase)))
      send(e.pid, "cnr_spectate", {
        runnerId = current.runnerId, runnerName = current:runnerName(), phase = e.phase,
        countdownRemaining = e.countdownRemaining, headStartRemaining = e.headStartRemaining, chaseElapsed = e.chaseElapsed,
        heli = e.heli,
        sky = sky.payload(current.sky, cfg, current.countdownStartedAt and math.max(0, now() - current.countdownStartedAt) or nil),
      })
    elseif e.kind == "setupAI" then
      local list = {}
      for _, a in ipairs(e.ai) do
        list[#list + 1] = { id = a.id, role = a.role, index = a.index, name = a.name, color = colorTable((colors.parseHex(a.colorHex))) }
      end
      send(e.pid, "cnr_setupAI", {
        model = current.vehicle.model, config = current.vehicle.config, ai = list,
        runnerId = current.runnerId, copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
      })
    elseif e.kind == "countdown" then
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
      local autoNext = cfg.autoNextRound and e.reason ~= "cancelled" and not e.to
      send(e.to or -1, "cnr_roundEnd", {
        runnerId = e.runnerId, runnerName = e.runnerName, survivedSeconds = e.survivedSeconds,
        reason = e.reason, explode = e.explode, catchers = e.catchers, message = e.message,
        autoNextSeconds = autoNext and cfg.autoNextDelaySeconds or nil,
      })
      activeVid = {}
      trafficOpen = {}
      trafficVids = {}
      spectators = {}
      clearRoundCars()
      partsBaseline = {}
      missingCount = {}
      if not current.test and not e.to and e.reason ~= "cancelled" then
        lastResult = { runner = e.runnerName, seconds = e.survivedSeconds, reason = e.reason }
      end
      aiVid = {}
      if autoNext then autoNextAt = now() + cfg.autoNextDelaySeconds end
    elseif e.kind == "live" then
      if not geoMode or now() - lastLiveSentAt >= GEO_LIVE_MIN_SECONDS - 0.05 then
        lastLiveSentAt = now()
        local g = geoMode and e.geo or nil
        for pid in pairs(current.players) do
          if pid ~= current.runnerId and not round.isAI(pid) then
            local route = not (e.noRoute and e.noRoute[pid])
            if not geoMode then
              send(pid, "cnr_lastSeen", { pos = e.pos, live = true, route = route })
            elseif g then
              send(pid, "cnr_lastSeen", { geo = g, live = true, route = route })
            end
          end
        end
        if not round.isAI(current.runnerId) and e.nearestCop then
          send(current.runnerId, "cnr_nearestCop", { dist = e.nearestCop })
        end
      end
    elseif e.kind == "requestSetup" then
      send(e.pid, "cnr_requestSetup", {})
    elseif e.kind == "rebuild" then
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
          if geoMode then
            if e.geo then send(pid, "cnr_lastSeen", { geo = e.geo }) end
          else
            send(pid, "cnr_lastSeen", { pos = e.pos })
          end
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
      if currentRunnerKey then runCounts[currentRunnerKey] = (runCounts[currentRunnerKey] or 0) + 1 end
      run.cops, run.copNames, run.copSightSeconds = {}, {}, {}
      for i, pid in ipairs(run.copIds or {}) do
        run.cops[i] = playerKey(pid)
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
          run.catcherKeys[i] = pid and playerKey(pid) or ("name:" .. name)
        end
      end
      leaderboard.add(board, run)
      local ok, err = pcall(saveLeaderboard)
      if not ok then log("failed to save leaderboard: " .. tostring(err)) end
      pushBoard()
      local top = leaderboard.runners(board, mapName, 3)
      for pid in pairs(MP.GetPlayers() or {}) do
        local viewerKey = playerKey(pid)
        local rows = {}
        for i, e in ipairs(top) do
          rows[i] = { rank = i, player = e.player, time = leaderboard.formatTime(e.survivedSeconds), me = e.key == viewerKey or nil }
        end
        send(pid, "cnr_top", { rows = rows })
      end
    end
  end
end

local handlers = {}

function handlers.start(pid, cmd)
  if current:isActive() and current.test then
    applyEffects(current:stop(now(), current.issuerId))
  end
  if current:isActive() then return refuse(pid, "A round is already running") end
  if cfg.carMode == "evolving" and not currentBuild then return refuse(pid, "Start a new build first") end
  autoNextAt = nil
  lastIssuer = pid
  local players = MP.GetPlayers() or {}
  local candidates, count = playing(players)
  if count < 2 then return refuse(pid, "Need two players who aren't sitting out") end
  local query = cmd.rest
  local runnerId, err
  if query and query:lower() == "again" then
    runnerId = lastRunnerKey and pidForKey(lastRunnerKey)
    if not runnerId then return refuse(pid, "No previous runner online") end
  else
    local countsByName = {}
    for p, name in pairs(candidates) do countsByName[name] = runCounts[playerKey(p)] or 0 end
    runnerId, err = commands.matchPlayer(query, candidates, nil, countsByName)
    if not runnerId then
      local anyone = commands.matchPlayer(query, players)
      if anyone and sitOut[anyone] then runnerId = anyone end
    end
  end
  if not runnerId then return refuse(pid, err) end
  if sitOut[runnerId] then return refuse(pid, string.format("%s is sitting out", players[runnerId] or tostring(runnerId))) end
  requestStations(pid)
  activeVid = {}
  trafficOpen = {}
  trafficVids = {}
  partsBaseline = {}
  missingCount = {}
  lastResult = nil
  local sittingOut = {}
  for p in pairs(sitOut) do sittingOut[p] = true end
  applyEffects(current:start(now(), runnerId, pid, players, { build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random, geoMode), traffic = traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, false), trafficRunnerOnly = cfg.trafficRunnerOnly == true, sittingOut = sittingOut }))
end

function handlers.test(pid, cmd)
  if current:isActive() then return refuse(pid, "A round is already running") end
  activeVid = {}
  trafficOpen = {}
  trafficVids = {}
  partsBaseline = {}
  missingCount = {}
  aiVid = {}
  local role = cmd.args[1] and cmd.args[1]:lower()
  if cfg.carMode == "evolving" and not currentBuild then return refuse(pid, "Start a new build first") end
  local opts = { test = true, role = role, build = cfg.carMode == "evolving" and buildOpts() or nil, sky = sky.pick(cfg, math.random, geoMode) }
  applyEffects(current:start(now(), nil, pid, MP.GetPlayers() or {}, opts))
end

local function pushRules(pid)
  send(pid or -1, "cnr_rules", rules.payload(cfg, traffic.perPlayer(cfg.trafficPerPlayer, maxCars(), geoMode, false)))
end

local function lobbyState()
  local players = MP.GetPlayers() or {}
  local online = 0
  for _ in pairs(players) do online = online + 1 end
  local practice
  if current:isActive() and current.test then practice = current.players[current.issuerId] or "someone" end
  return { online = online, practice = practice, active = current:isActive() and not current.test or false }
end

local function pushLobby(pid)
  local state = lobbyState()
  if pid then return send(pid, "cnr_lobby", state) end
  local sig = panel.signature(state)
  if sig ~= lastLobbySig then
    lastLobbySig = sig
    send(-1, "cnr_lobby", state)
  end
end

function handlers.auto(pid, cmd)
  local arg = cmd.args[1] and cmd.args[1]:lower()
  if arg ~= "on" and arg ~= "off" then arg = cfg.autoNextRound and "off" or "on" end
  local updated = config.setValue(rawConfig, "autoNextRound", arg)
  writeFile(pluginDir .. "config.json", Util.JsonPrettify(Util.JsonEncode(updated)))
  loadConfig()
  current.cfg = cfg
  pushRules()
  if arg == "off" then
    autoNextAt = nil
    send(-1, "cnr_autoNext", {})
  end
  reply(pid, "Automatic next round: " .. arg)
end

function handlers.go(pid)
  applyEffects(current:go(now(), pid))
end

function handlers.next(pid)
  if not autoNextAt then return refuse(pid, "No round is scheduled") end
  startAutoRound()
end

function handlers.stop(pid)
  local wasActive = current:isActive()
  applyEffects(current:stop(now(), pid))
  if not wasActive then send(-1, "cnr_roundEnd", { reason = "cancelled" }) end
end


handlers["end"] = function(pid)
  applyEffects(current:endCalled(now(), pid))
end

function handlers.reroll(pid)
  applyEffects(current:reroll(now(), pid))
end

function handlers.sky(pid)
  if geoMode then return refuse(pid, "Not available on BeamNG.Earth yet") end
  if current.state ~= "prep" and current.state ~= "ready" then return refuse(pid, "You can only change the sky before GO") end
  if not sky.hasRandom(cfg) then return refuse(pid, "Set time of day or weather to random first") end
  local before = current.sky or {}
  local picked = sky.pick(cfg, math.random, geoMode)
  for _ = 1, 10 do
    if picked.time ~= before.time or picked.weather ~= before.weather then break end
    picked = sky.pick(cfg, math.random, geoMode)
  end
  current.sky = picked
  local data = sky.payload(current.sky, cfg, nil)
  for p in pairs(current.test and current.players or MP.GetPlayers() or {}) do
    if not round.isAI(p) then send(p, "cnr_sky", data) end
  end
end


function handlers.addstation(pid)
  if geoMode then
    local r = geoOf(pid)
    if not r then return refuse(pid, "You need to be in a vehicle") end
    geoStations[#geoStations + 1] = { lat = r.lat, lon = r.lon, r = GEO_STATION_RADIUS }
    saveStations()
    return reply(pid, string.format("Gas station added (%d on %s)", #geoStations, mapName))
  end
  local car = carFor(pid)
  if not car then return refuse(pid, "You need to be in a vehicle") end
  stations[#stations + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
  saveStations()
  reply(pid, string.format("Gas station added (%d on %s)", #stations, mapName))
end

function handlers.removestation(pid)
  if geoMode then
    local r = geoOf(pid)
    if not r then return refuse(pid, "You need to be in a vehicle") end
    local ref = geo.newRef(r.lat, r.lon)
    local bestIndex, bestDist
    for i, st in ipairs(geoStations) do
      local p = geo.toLocal(ref, st.lat, st.lon, 0)
      local d = math.sqrt(p.x * p.x + p.y * p.y)
      if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
    end
    if not bestIndex then return refuse(pid, "No gas station within 50 m") end
    table.remove(geoStations, bestIndex)
    saveStations()
    return reply(pid, string.format("Gas station removed (%d left on %s)", #geoStations, mapName))
  end
  local car = carFor(pid)
  if not car then return refuse(pid, "You need to be in a vehicle") end
  local bestIndex, bestDist
  for i, s in ipairs(stations) do
    local d = vec.dist(car.pos, s)
    if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
  end
  if not bestIndex then return refuse(pid, "No gas station within 50 m") end
  table.remove(stations, bestIndex)
  saveStations()
  reply(pid, string.format("Gas station removed (%d left on %s)", #stations, mapName))
end


function handlers.reload(pid)
  if current:isActive() then return refuse(pid, "Stop the round before reloading") end
  loadConfig()
  current = round.new(cfg)
  pushRules()
  reply(pid, "Config reloaded")
end


local function runCommand(pid, text)
  local cmd = commands.parse("/cnr " .. text)
  local handler = cmd and handlers[cmd.name]
  if handler then handler(pid, cmd) end
end


local function nextRunnerName(players)
  local countsByName = {}
  for p, name in pairs(players) do countsByName[name] = runCounts[playerKey(p)] or 0 end
  local pid = commands.matchPlayer("next", players, nil, countsByName)
  return pid and players[pid] or nil
end

local function playerEntries(players, realRound)
  local entries, loading = {}, 0
  for pid, name in pairs(players) do
    local entry = { name = name, runs = runCounts[playerKey(pid)] or 0, sitOut = sitOut[pid] or nil }
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
  local candidates, count = playing(players)
  local realRound = current:isActive() and not current.test
  local entries, loading = playerEntries(players, realRound)
  local nextName = not realRound and nextRunnerName(candidates) or nil
  local lastPid = lastRunnerKey and pidForKey(lastRunnerKey)
  local autoNext
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
    evolving = current.evolving == true,
    build = buildInfo,
    nextRunner = nextName, lastRunner = lastPid and players[lastPid] or nil,
    loading = loading, autoNext = autoNext, lastResult = lastResult,
    stationCount = #(geoMode and geoStations or stations), geo = geoMode,
    skyRandom = not geoMode and sky.hasRandom(cfg),
    trafficNote = traffic.note(cfg.trafficPerPlayer, maxCars(), geoMode, count, cfg.trafficRunnerOnly == true),
  })
end

local function pushPanel(opener)
  if opener then panelSubs[opener] = nil end
  if not next(panelSubs) and not opener then return end
  local state = panelState()
  local sig = panel.signature(state)
  if sig ~= lastPanelSig then
    for p in pairs(panelSubs) do send(p, "cnr_panelState", state) end
    lastPanelSig = sig
  end
  if opener then
    panelSubs[opener] = true
    send(opener, "cnr_panelState", state)
  end
end

local function panelBuild(pid, msg)
  local function answer(text, tone) send(pid, "cnr_panelReply", { text = text, tone = tone }) end
  if current:isActive() then return answer("Stop the round first", "warn") end
  if msg.op == "reset" then
    backupBuild()
    currentBuild = nil
    pushPanel()
    return answer("Build reset")
  end
  if msg.op ~= "new" then return end
  local nb = build.normalize({ model = msg.model, name = msg.name, parts = msg.parts, vars = msg.vars })
  if not nb then return answer("That car can't start a build", "warn") end
  backupBuild()
  currentBuild = build.new(nb.model, nb.name, nb.parts, nb.vars, type(msg.from) == "string" and msg.from or "random", os.time())
  saveBuild()
  pushPanel()
  answer("New build: " .. build.label(currentBuild))
end

local function panelSettings(pid, values, id)
  if type(id) ~= "number" and type(id) ~= "string" then id = nil end
  local function answer(ok, text, keys) send(pid, "cnr_panelReply", { ok = ok, text = text, keys = keys, id = id }) end
  if current:isActive() then return answer(false, "Stop the round first") end
  local updated, keys = panel.applyValues(rawConfig, values)
  if not updated then return answer(false, keys) end
  writeFile(pluginDir .. "config.json", Util.JsonPrettify(Util.JsonEncode(updated)))
  loadConfig()
  current = round.new(cfg)
  answer(true, "Saved", keys)
  pushRules()
  pushPanel()
  pushBoard()
end

function cnrOnPanel(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" or type(msg.action) ~= "string" then return end
  if msg.action == "open" then
    pushPanel(pid)
  elseif msg.action == "close" then
    panelSubs[pid] = nil
  elseif msg.action == "command" then
    local text = panel.allow(msg.text)
    if not text then return send(pid, "cnr_panelReply", { text = "Not available from the panel", tone = "warn" }) end
    panelMirror = pid
    local ran, err = pcall(runCommand, pid, text)
    panelMirror = nil
    pushPanel()
    if not ran then error(err, 0) end
  elseif msg.action == "station" then
    if msg.op ~= "add" and msg.op ~= "remove" then return end
    panelMirror = pid
    local handler = handlers.removestation
    if msg.op == "add" then handler = handlers.addstation end
    local ran, err = pcall(handler, pid)
    panelMirror = nil
    pushPanel()
    if not ran then error(err, 0) end
  elseif msg.action == "stations" then
    local list = {}
    for _, st in ipairs(geoMode and geoStations or stations) do
      list[#list + 1] = geoMode and { lat = st.lat, lon = st.lon, name = st.name } or { x = st.x, y = st.y, z = st.z }
    end
    send(pid, "cnr_stationList", { geo = geoMode, stations = list })
  elseif msg.action == "settings" then
    panelSettings(pid, msg.values, msg.id)
  elseif msg.action == "build" then
    panelBuild(pid, msg)
  elseif msg.action == "apply" then
    local mayApply = pid == current.runnerId or (round.isAI(current.runnerId) and pid == current.issuerId)
    if not mayApply then return send(pid, "cnr_panelReply", { text = "Only the runner can apply the change", tone = "warn" }) end
    panelMirror = pid
    local ran, err = pcall(function() applyEffects(current:apply(now(), pid)) end)
    panelMirror = nil
    pushPanel()
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
      currentBuild = nb
      current.buildStep = nb.step
      saveBuild()
    end
    if changed then broadcast(build.changeLine(nb.step, name, changes)) end
  end
  local cfgTable = { format = 2, model = current.vehicle.model, parts = setup.parts, vars = setup.vars }
  applyEffects(current:setupReceived(now(), pid, cfgTable))
  pushPanel()
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

function cnrOnChatMessage(pid, name, msg)
  if not commands.parse(msg) then return 0 end
  notify(pid, "Chat commands are gone: use the Cops and Robbers card at the bottom of your screen.")
  return 1
end

local function vehicleAllowed(pid, vid, data, isSpawn)
  local own = activeVid[pid]
  if current:isActive() and trafficOpen[pid] and current.players[pid] ~= nil and vid ~= own then
    if current.test and pid == current.issuerId then return true end
    if not isSpawn then return true end
    if extraCars(pid) >= trafficOpen[pid] + (own and 0 or 1) then return false end
    if own then return true end
  end
  if not roundCarActive() or not current.players[pid] then return true end
  local decoded = parseVehicleData(data)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false, decoded end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  if pcFile and not current.evolving and normalizeConfig(pcFile) ~= normalizeConfig(current.vehicle.config) then return false, decoded end
  if isSpawn and not trafficOpen[pid] and firstVid(pid) and not (current.test and pid == current.issuerId) then return false, decoded end
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

local function logVehicle(pid, action, vid, allowed, decoded)
  if allowed then
    if not decoded or not current:isPlacing(now(), pid) then return end
  else
    local last = refusalLoggedAt[pid]
    if last and now() - last < REFUSAL_LOG_SECONDS then return end
    refusalLoggedAt[pid] = now()
  end
  log(string.format("%s %s %s (vid %s): %s", MP.GetPlayerName(pid) or tostring(pid), action,
    tostring(decoded and decoded.jbm or "?"), tostring(vid), allowed and "allowed" or "refused"))
end

function cnrOnVehicleSpawn(pid, vid, data)
  if spectators[pid] then
    logVehicle(pid, "spawned", vid, false, parseVehicleData(data))
    refuse(pid, "You can't spawn a car while spectating")
    return 1
  end
  local allowed, decoded = vehicleAllowed(pid, vid, data, true)
  logVehicle(pid, "spawned", vid, allowed, decoded)
  if not allowed then
    refuse(pid, "Only the round car is allowed")
    return 1
  end
  if tracksActive(pid) and not trafficOpen[pid] then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleEdited(pid, vid, data)
  local allowed, decoded = vehicleAllowed(pid, vid, data, false)
  logVehicle(pid, "edited", vid, allowed, decoded)
  if not allowed then
    refuse(pid, "Only the round car is allowed")
    return 1
  end
  local notOwn = vid ~= activeVid[pid] and (current.test or trafficOpen[pid])
  if roundCarActive() and current.players[pid] and not notOwn then checkParts(pid, decoded) end
  if tracksActive(pid) and not trafficOpen[pid] then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleDeleted(pid, vid)
  if activeVid[pid] == vid then activeVid[pid] = nil end
end

function cnrOnVehicleReset(pid, vid)
  if (activeVid[pid] or trafficOpen[pid]) and activeVid[pid] ~= vid then return end
  if geoMode then
    local fx = current:vehicleReset(now(), pid)
    if #fx > 0 then pendingResetVerdicts[#pendingResetVerdicts + 1] = { pid = pid, at = now(), fx = fx } end
    return
  end
  applyEffects(current:vehicleReset(now(), pid))
end

local function sendMyColor(pid, err)
  local c = colorFor(pid)
  send(pid, "cnr_myColor", { hex = c and c.hex, error = err })
end

function cnrOnColor(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" then return end
  local hex = type(msg.hex) == "string" and msg.hex or ""
  if hex == "" then
    colors.clear(colorStore, playerKey(pid))
    colors.clear(colorStore, MP.GetPlayerName(pid) or "")
    saveColors()
    return sendMyColor(pid)
  end
  local c, err = colors.parseHex(hex)
  if not c then return sendMyColor(pid, err) end
  colors.set(colorStore, playerKey(pid), c.hex)
  saveColors()
  sendMyColor(pid)
  if current.state == "prep" and current.players[pid] then
    placing(pid)
    send(pid, "cnr_paint", { color = colorFor(pid) })
  end
end

function cnrOnSitOut(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.on) ~= "boolean" then return end
  sitOut[pid] = d.on or nil
  send(pid, "cnr_sitOut", { on = d.on })
  if current:isActive() and not current.test then
    notify(pid, d.on and "You sit out from the next round" or "You play again from the next round")
  end
end

function cnrOnPlayerJoin(pid)
  send(pid, "cnr_mode", { geo = geoMode, version = VERSION })
  sendMyColor(pid)
  pushRules(pid)
  pushLobby(pid)
  requestStations(pid)
  applyEffects(current:playerJoined(now(), pid, MP.GetPlayerName(pid)))
  if current.evolving and current.state == "prep" and current.queued and current.players[pid] then
    send(pid, "cnr_queued", current.queued)
  end
  if current:isActive() then pushRoundCars(pid) end
end

function cnrOnPlayerDisconnect(pid)
  stationsRequested[pid] = nil
  refusalLoggedAt[pid] = nil
  sitOut[pid] = nil
  spectators[pid] = nil
  panelSubs[pid] = nil
  boardSubs[pid] = nil
  local name = MP.GetPlayerName(pid)
  if name and geoReports[pid] then lastGeoByName[name] = geoPoint(geoReports[pid]) end
  geoReports[pid] = nil
  applyEffects(current:playerLeft(now(), pid))
  activeVid[pid] = nil
  trafficOpen[pid] = nil
  trafficVids[pid] = nil
  pushRoundCars()
end

function cnrOnVehiclePicked(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.model) ~= "string" then return end
  applyEffects(current:vehiclePicked(now(), pid, decoded.model, decoded.config, MP.GetPlayers() or {}))
end

function cnrOnMyVehicle(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  local vid = ok and type(decoded) == "table" and tonumber(decoded.vid)
  if not vid or not current:isActive() or current.players[pid] == nil then return end
  activeVid[pid] = vid
  placed(pid)
  log(string.format("%s placed the round car (vid %s)", MP.GetPlayerName(pid) or tostring(pid), tostring(vid)))
  applyEffects(current:vehiclePlaced(now(), pid))
  applyEffects(current:vehicleReady(now(), pid, tonumber(decoded.rebuild)))
  if not current.test and not trafficOpen[pid] then
    local vehicles = MP.GetPlayerVehicles(pid)
    if type(vehicles) == "table" then
      for other in pairs(vehicles) do
        if other ~= vid then MP.RemoveVehicle(pid, other) end
      end
    end
  end
  openTraffic(pid)
  pushRoundCars()
end

function cnrOnTrafficCars(pid, data)
  local limit = trafficOpen[pid]
  if not limit then return end
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.vids) ~= "table" then return end
  local ai = {}
  if current.test and pid == current.issuerId then
    for _, v in pairs(aiVid) do ai[v] = true end
  end
  local set, n = {}, 0
  for _, raw in ipairs(d.vids) do
    local vid = tonumber(raw)
    if vid and n < limit and vid ~= activeVid[pid] and not ai[vid] and not set[vid] then
      set[vid] = true
      n = n + 1
    end
  end
  trafficVids[pid] = set
end

function cnrOnAiVehicles(pid, data)
  if not current.test or pid ~= current.issuerId then return end
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.ai) ~= "table" then return end
  for _, a in ipairs(decoded.ai) do
    local id, vid = tonumber(a.id), tonumber(a.vid)
    if id and vid and round.isAI(id) and current.players[id] then aiVid[id] = vid end
  end
end

local function mergeGeoStations(list)
  local added = 0
  for _, s in ipairs(list or {}) do
    local lat, lon = tonumber(s.lat), tonumber(s.lon)
    if geo.valid(lat, lon) then
      local ref = geo.newRef(lat, lon)
      local duplicate = false
      for _, existing in ipairs(geoStations) do
        local p = geo.toLocal(ref, existing.lat, existing.lon, 0)
        if math.sqrt(p.x * p.x + p.y * p.y) <= GEO_STATION_MERGE_METERS then duplicate = true break end
      end
      if not duplicate then
        geoStations[#geoStations + 1] = { lat = lat, lon = lon, r = GEO_STATION_RADIUS, name = type(s.name) == "string" and s.name or nil }
        added = added + 1
      end
    end
  end
  return added
end

function cnrOnGeo(pid, data)
  if not geoMode then return end
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.cars) ~= "table" then return end
  for _, c in ipairs(decoded.cars) do
    local lat, lon = tonumber(c.lat), tonumber(c.lon)
    local id = tonumber(c.id) or pid
    local allowed = id == pid or (round.isAI(id) and current.test and pid == current.issuerId and current.players[id] ~= nil)
    if allowed and geo.valid(lat, lon) then
      geoReports[id] = {
        lat = lat, lon = lon, h = tonumber(c.h) or 0,
        ve = tonumber(c.ve) or 0, vn = tonumber(c.vn) or 0, vu = tonumber(c.vu) or 0, t = now(),
      }
    end
  end
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
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  current:sightReport(now(), pid, d.seen == true)
end

function cnrOnCover(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  current:coverReport(now(), pid, d.covered == true)
end

function cnrOnRelocated(pid, data)
  if not current:isActive() then return end
  local ok, decoded = pcall(Util.JsonDecode, data)
  local ids = ok and type(decoded) == "table" and type(decoded.ids) == "table" and decoded.ids or { pid }
  for _, raw in ipairs(ids) do
    local id = tonumber(raw)
    local allowed = id == pid or (round.isAI(id) and current.test and pid == current.issuerId)
    if allowed then
      applyEffects(current:relocated(now(), id))
      for i = #pendingResetVerdicts, 1, -1 do
        if pendingResetVerdicts[i].pid == id then table.remove(pendingResetVerdicts, i) end
      end
    end
  end
end

function cnrOnStations(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if geoMode then
    if not ok or type(decoded) ~= "table" or decoded.map ~= mapName then return end
    local added = mergeGeoStations(decoded.stations)
    if added > 0 then
      saveStations()
      log(string.format("%d new gas stations on %s (%d known)", added, mapName, #geoStations))
    end
    return
  end
  if not ok or type(decoded) ~= "table" or decoded.map ~= mapName or #stations > 0 then return end
  for _, s in ipairs(decoded.stations or {}) do
    local v = vec.toVec(s)
    if v then
      v.r = tonumber(s.r) or 0
      stations[#stations + 1] = v
    end
  end
  if #stations > 0 then
    saveStations()
    log(string.format("%d gas stations detected for %s", #stations, mapName))
  end
end

function startAutoRound()
  autoNextAt = nil
  if current:isActive() then return end
  local players = MP.GetPlayers() or {}
  local issuer = lastIssuer and players[lastIssuer] and lastIssuer
  if not issuer then
    for p in pairs(players) do
      if not issuer or p < issuer then issuer = p end
    end
  end
  if issuer then handlers.start(issuer, { name = "start", args = { "next" }, rest = "next" }) end
end

function cnrTick()
  local panelOk, panelErr = pcall(pushPanel)
  if not panelOk and panelErr ~= lastPanelError then log("panel update failed: " .. tostring(panelErr)) end
  lastPanelError = not panelOk and panelErr or nil
  local lobbyOk, lobbyErr = pcall(pushLobby)
  if not lobbyOk and lobbyErr ~= lastLobbyError then log("lobby update failed: " .. tostring(lobbyErr)) end
  lastLobbyError = not lobbyOk and lobbyErr or nil
  if autoNextAt and now() >= autoNextAt then startAutoRound() end
  for i = #pendingResetVerdicts, 1, -1 do
    local v = pendingResetVerdicts[i]
    if now() - v.at >= GEO_RESET_VERDICT_DELAY then
      table.remove(pendingResetVerdicts, i)
      if current:isActive() then applyEffects(v.fx) end
    end
  end
  if not current:isActive() then return end
  local cars = {}
  for pid in pairs(current.players) do cars[pid] = carFor(pid) end
  applyEffects(current:tick(now(), cars, roundStations(), trafficCars()))
end

FS.CreateDirectory(stationsDir)
loadConfig()
loadLeaderboard()
loadBuild()
loadColors()
mapName = (tostring(MP.Get(MP.Settings.Map) or ""):match("levels/([^/]+)/")) or "unknown"
geoMode = mapName == "beamng_earth"
loadStations()
current = round.new(cfg)

MP.RegisterEvent("onChatMessage", "cnrOnChatMessage")
MP.RegisterEvent("onVehicleSpawn", "cnrOnVehicleSpawn")
MP.RegisterEvent("onVehicleEdited", "cnrOnVehicleEdited")
MP.RegisterEvent("onVehicleDeleted", "cnrOnVehicleDeleted")
MP.RegisterEvent("onVehicleReset", "cnrOnVehicleReset")
MP.RegisterEvent("onPlayerJoin", "cnrOnPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "cnrOnPlayerDisconnect")
MP.RegisterEvent("cnr_vehiclePicked", "cnrOnVehiclePicked")
MP.RegisterEvent("cnr_stations", "cnrOnStations")
MP.RegisterEvent("cnr_myVehicle", "cnrOnMyVehicle")
MP.RegisterEvent("cnr_aiVehicles", "cnrOnAiVehicles")
MP.RegisterEvent("cnr_trafficCars", "cnrOnTrafficCars")
MP.RegisterEvent("cnr_geo", "cnrOnGeo")
MP.RegisterEvent("cnr_relocated", "cnrOnRelocated")
MP.RegisterEvent("cnr_panel", "cnrOnPanel")
MP.RegisterEvent("cnr_color", "cnrOnColor")
MP.RegisterEvent("cnr_sitOut", "cnrOnSitOut")
MP.RegisterEvent("cnr_sight", "cnrOnSight")
MP.RegisterEvent("cnr_cover", "cnrOnCover")
MP.RegisterEvent("cnr_board", "cnrOnBoard")
MP.RegisterEvent("cnr_setup", "cnrOnSetup")
MP.RegisterEvent("cnr_change", "cnrOnChange")
MP.RegisterEvent("cnr_missing", "cnrOnMissing")
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
send(-1, "cnr_mode", { geo = geoMode, version = VERSION })
pushRules()
pushLobby()
log("Cops and Robbers " .. VERSION .. " loaded on " .. mapName .. " (" .. pluginDir .. ")")
