local pluginDir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./")
package.path = pluginDir .. "?.lua;" .. package.path

local vec = require("cnr.vec")
local config = require("cnr.config")
local round = require("cnr.round")
local leaderboard = require("cnr.leaderboard")
local commands = require("cnr.commands")
local colors = require("cnr.colors")
local tables = require("cnr.tables")
local geo = require("cnr.geo")
local build = require("cnr.build")
local panel = require("cnr.panel")

local VERSION = "2.0.2"
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
local stationsRequested = {}
local partsBaseline = {}
local aiVid = {}
local runCounts = {}
local lastRunnerKey
local currentRunnerKey
local autoNextAt
local lastIssuer
local rawConfig = {}
local geoMode = false
local geoRef
local geoReports = {}
local geoStations = {}
local localStationsCache
local lastGeoByName = {}
local GEO_STALE_SECONDS = 2
local GEO_STATION_MERGE_METERS = 50
local GEO_STATION_RADIUS = 20
local GEO_RESET_VERDICT_DELAY = 1
local GEO_LIVE_MIN_SECONDS = 3
local lastLiveSentAt = -math.huge
local pendingResetVerdicts = {}
local colorStore = {}
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

local boardSubs = {}
local leaderboardLocked = false
local panelSubs = {}
local panelMirror
local lastPanelSig
local lastPanelError

local function send(pid, event, payload)
  if type(pid) ~= "number" or (pid < 0 and pid ~= -1) then return end
  MP.TriggerClientEvent(pid, event, Util.JsonEncode(payload or {}))
end
local function reply(pid, msg)
  MP.SendChatMessage(pid, PREFIX .. msg)
  if panelMirror and pid == panelMirror then send(pid, "cnr_panelReply", { text = msg }) end
end
local function broadcast(msg) MP.SendChatMessage(-1, PREFIX .. msg) end

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
  vid = firstVid(pid)
  activeVid[pid] = vid
  return vid
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
    return { pos = pos, vel = { x = r.ve, y = r.vn, z = r.vu } }
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

local function normalizeConfig(path)
  if type(path) ~= "string" then return nil end
  return (path:gsub("\\", "/"):gsub("^/", ""):lower())
end

local function boardState(sub)
  sub = type(sub) == "table" and sub or { map = mapName }
  local f = {
    map = sub.map ~= "all" and sub.map or nil,
    mode = (sub.mode == "random" or sub.mode == "evolving") and sub.mode or nil,
  }
  return {
    map = mapName, maps = leaderboard.maps(board), filter = sub.map or mapName, mode = f.mode or "all",
    runners = leaderboard.runners(board, f, 20),
    cops = leaderboard.cops(board, f, 20),
    players = leaderboard.players(board, f, cfg.assistMinSightPercent),
  }
end

local function sendBoard(pid)
  local ok, state = pcall(boardState, boardSubs[pid])
  if ok then send(pid, "cnr_boardState", state) else log("board update failed: " .. tostring(state)) end
end

local function pushBoard()
  for pid in pairs(boardSubs) do sendBoard(pid) end
end

local function applyEffects(effects)
  for _, e in ipairs(effects) do
    if e.kind == "reply" then
      reply(e.pid, e.msg)
    elseif e.kind == "broadcast" then
      if e.to then reply(e.to, e.msg) else broadcast(e.msg) end
    elseif e.kind == "pickVehicle" then
      send(e.pid, "cnr_pickVehicle", { includeMods = cfg.includeModVehicles, excludedModels = cfg.excludedModels })
    elseif e.kind == "setup" then
      if e.role == "runner" and not current.test then
        local key = playerKey(e.pid)
        runCounts[key] = (runCounts[key] or 0) + 1
        lastRunnerKey = key
        currentRunnerKey = key
      end
      local runnerCar = carFor(current.runnerId)
      local resumeGeo
      if geoMode and e.resumePos then resumeGeo = lastGeoByName[MP.GetPlayerName(e.pid) or ""] end
      send(e.pid, "cnr_roundSetup", {
        geo = geoMode, runnerGeo = geoMode and geoPoint(geoOf(current.runnerId)) or nil,
        resumeGeo = resumeGeo,
        runnerId = current.runnerId, role = e.role, copIndex = e.copIndex,
        model = current.vehicle.model, config = current.vehicle.config,
        phase = e.phase, countdownRemaining = e.countdownRemaining, chaseElapsed = e.chaseElapsed,
        headStartRemaining = e.headStartRemaining, inPlace = e.inPlace,
        resumePos = not geoMode and e.resumePos or nil,
        color = e.colorHex and colorTable((colors.parseHex(e.colorHex))) or colorFor(e.pid),
        runnerPos = not geoMode and runnerCar and runnerCar.pos or nil,
        copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
        sightMaxMeters = cfg.sightMaxMeters,
        evolving = current.evolving or nil,
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
      send(current.test and current.issuerId or -1, "cnr_notice", { msg = string.format("%s: crash penalty %gs", tostring(e.name), e.seconds), about = e.pid })
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
        reason = e.reason, explode = e.explode, catchers = e.catchers,
        autoNextSeconds = autoNext and cfg.autoNextDelaySeconds or nil,
      })
      activeVid = {}
      partsBaseline = {}
      aiVid = {}
      if autoNext then
        autoNextAt = now() + cfg.autoNextDelaySeconds
        broadcast(string.format("Next round in %gs (turn off Automatic rounds in the panel to stop)", cfg.autoNextDelaySeconds))
      end
    elseif e.kind == "live" then
      if not geoMode or now() - lastLiveSentAt >= GEO_LIVE_MIN_SECONDS then
        lastLiveSentAt = now()
        local g = geoMode and geoPoint(geoOf(current.runnerId)) or nil
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
        if not round.isAI(pid) then send(pid, "cnr_rebuild", { model = current.vehicle.model, config = e.config }) end
      end
    elseif e.kind == "applied" then
      send(e.to or -1, "cnr_applied", {})
      send(e.to or -1, "cnr_notice", { msg = e.timedOut and "Cars ready (not everyone loaded in time), press GO" or "Cars ready, press GO" })
    elseif e.kind == "spotted" then
      if not round.isAI(current.runnerId) then send(current.runnerId, "cnr_spotted", { spotted = e.spotted }) end
    elseif e.kind == "lastSeen" then
      for pid in pairs(current.players) do
        if pid ~= current.runnerId and not round.isAI(pid) then
          if geoMode then
            local g = geoPoint(geoOf(current.runnerId))
            if g then send(pid, "cnr_lastSeen", { geo = g }) end
          else
            send(pid, "cnr_lastSeen", { pos = e.pos })
          end
        end
      end
      if not round.isAI(current.runnerId) and e.nearestCop then
        send(current.runnerId, "cnr_nearestCop", { dist = e.nearestCop })
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
      local t = leaderboard.formatTime(run.survivedSeconds)
      if run.endReason == "caught" then
        local by = (run.catchers and #run.catchers > 0) and (" by " .. table.concat(run.catchers, ", ")) or ""
        broadcast(string.format("Runner caught%s! %s survived %s", by, run.player, t))
      elseif run.endReason == "called" then
        broadcast(string.format("Round ended: %s survived %s", run.player, t))
      elseif run.endReason == "escaped" then
        broadcast(string.format("%s escaped! Survived %s", run.player, t))
      else
        broadcast(string.format("%s disconnected after %s", run.player, t))
      end
      for _, line in ipairs(leaderboard.formatTop(board, 5, mapName)) do broadcast(line) end
      send(-1, "cnr_top", { lines = leaderboard.formatTop(board, 3, mapName) })
    end
  end
end

local HELP = {
  "Run rounds and settings with the Cops and Robbers Panel, see times and stats with the Cops and Robbers Leaderboard (Esc > UI Apps)",
  '"/cnr color <#hex|off>" - your car color for every round',
  '"/cnr addstation" / "/cnr removestation" - edit this map\'s gas stations',
  '"/cnr help" / "/cnr version"',
}

local handlers = {}

function handlers.help(pid)
  reply(pid, "Cops and Robbers " .. VERSION)
  for _, line in ipairs(HELP) do reply(pid, line) end
end

function handlers.version(pid)
  reply(pid, "Cops and Robbers " .. VERSION)
end

function handlers.start(pid, cmd)
  if current:isActive() and current.test then
    applyEffects(current:stop(now(), current.issuerId))
  end
  if current:isActive() then return reply(pid, "A round is already running") end
  if cfg.carMode == "evolving" and not currentBuild then return reply(pid, "Start a new build first") end
  autoNextAt = nil
  lastIssuer = pid
  local players = MP.GetPlayers() or {}
  local query = cmd.rest
  local runnerId, err
  if query and query:lower() == "again" then
    runnerId = lastRunnerKey and pidForKey(lastRunnerKey)
    if not runnerId then return reply(pid, "No previous runner online") end
  else
    local countsByName = {}
    for p, name in pairs(players) do countsByName[name] = runCounts[playerKey(p)] or 0 end
    runnerId, err = commands.matchPlayer(query, players, nil, countsByName)
  end
  if not runnerId then return reply(pid, err) end
  requestStations(pid)
  activeVid = {}
  partsBaseline = {}
  applyEffects(current:start(now(), runnerId, pid, players, cfg.carMode == "evolving" and { build = buildOpts() } or nil))
end

function handlers.test(pid, cmd)
  if current:isActive() then return reply(pid, "A round is already running") end
  activeVid = {}
  partsBaseline = {}
  aiVid = {}
  local role = cmd.args[1] and cmd.args[1]:lower()
  if cfg.carMode == "evolving" and not currentBuild then return reply(pid, "Start a new build first") end
  local opts = { test = true, role = role, build = cfg.carMode == "evolving" and buildOpts() or nil }
  applyEffects(current:start(now(), nil, pid, MP.GetPlayers() or {}, opts))
end

function handlers.auto(pid, cmd)
  local arg = cmd.args[1] and cmd.args[1]:lower()
  if arg ~= "on" and arg ~= "off" then arg = cfg.autoNextRound and "off" or "on" end
  local updated = config.setValue(rawConfig, "autoNextRound", arg)
  writeFile(pluginDir .. "config.json", Util.JsonPrettify(Util.JsonEncode(updated)))
  loadConfig()
  current.cfg = cfg
  if arg == "off" then
    autoNextAt = nil
    send(-1, "cnr_autoNext", {})
  end
  reply(pid, "Automatic next round: " .. arg)
end

function handlers.go(pid)
  applyEffects(current:go(now(), pid))
end

function handlers.color(pid, cmd)
  local name = playerKey(pid)
  local arg = cmd.args[1]
  if not arg then
    local c = colors.get(colorStore, name) or colors.get(colorStore, MP.GetPlayerName(pid) or "")
    return reply(pid, c and ("Your car color is " .. c.hex) or 'No car color set, use "/cnr color #ff0000"')
  end
  if arg:lower() == "off" then
    colors.clear(colorStore, name)
    saveColors()
    return reply(pid, "Car color cleared")
  end
  local c, err = colors.parseHex(arg)
  if not c then return reply(pid, err) end
  colors.set(colorStore, name, c.hex)
  saveColors()
  if current.state == "prep" and current.players[pid] then
    reply(pid, "Your car color is now " .. c.hex)
    send(pid, "cnr_paint", { color = colorFor(pid) })
  elseif roundCarActive() then
    reply(pid, "Your car color is now " .. c.hex .. " (applies from the next round)")
  else
    reply(pid, "Your car color is now " .. c.hex)
  end
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


function handlers.addstation(pid)
  if geoMode then
    local r = geoOf(pid)
    if not r then return reply(pid, "You need to be in a vehicle") end
    geoStations[#geoStations + 1] = { lat = r.lat, lon = r.lon, r = GEO_STATION_RADIUS }
    saveStations()
    return reply(pid, string.format("Gas station added (%d on %s)", #geoStations, mapName))
  end
  local car = carFor(pid)
  if not car then return reply(pid, "You need to be in a vehicle") end
  stations[#stations + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
  saveStations()
  reply(pid, string.format("Gas station added (%d on %s)", #stations, mapName))
end

function handlers.removestation(pid)
  if geoMode then
    local r = geoOf(pid)
    if not r then return reply(pid, "You need to be in a vehicle") end
    local ref = geo.newRef(r.lat, r.lon)
    local bestIndex, bestDist
    for i, st in ipairs(geoStations) do
      local p = geo.toLocal(ref, st.lat, st.lon, 0)
      local d = math.sqrt(p.x * p.x + p.y * p.y)
      if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
    end
    if not bestIndex then return reply(pid, "No gas station within 50 m") end
    table.remove(geoStations, bestIndex)
    saveStations()
    return reply(pid, string.format("Gas station removed (%d left on %s)", #geoStations, mapName))
  end
  local car = carFor(pid)
  if not car then return reply(pid, "You need to be in a vehicle") end
  local bestIndex, bestDist
  for i, s in ipairs(stations) do
    local d = vec.dist(car.pos, s)
    if d <= 50 and (not bestDist or d < bestDist) then bestIndex, bestDist = i, d end
  end
  if not bestIndex then return reply(pid, "No gas station within 50 m") end
  table.remove(stations, bestIndex)
  saveStations()
  reply(pid, string.format("Gas station removed (%d left on %s)", #stations, mapName))
end


function handlers.reload(pid)
  if current:isActive() then return reply(pid, "Stop the round before reloading") end
  loadConfig()
  current = round.new(cfg)
  reply(pid, "Config reloaded")
end


local function runCommand(pid, text)
  local cmd = commands.parse("/cnr " .. text)
  local handler = cmd and handlers[cmd.name]
  if handler then handler(pid, cmd) end
end


local function panelState()
  local running = current.state == "running"
  return panel.snapshot({
    version = VERSION, map = mapName, phase = current.state,
    runner = current.runnerId and current:runnerName() or nil,
    test = current.test == true,
    elapsed = running and current.releasedAt and math.max(0, now() - current.releasedAt) or nil,
    players = MP.GetPlayers() or {}, cfg = cfg, defaults = config.DEFAULTS,
    evolving = current.evolving == true,
    build = currentBuild and { label = build.label(currentBuild), step = currentBuild.step } or nil,
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
  local function answer(text) send(pid, "cnr_panelReply", { text = text }) end
  if current:isActive() then return answer("Stop the round first") end
  if msg.op == "reset" then
    backupBuild()
    currentBuild = nil
    pushPanel()
    return answer("Build reset")
  end
  if msg.op ~= "new" then return end
  local nb = build.normalize({ model = msg.model, name = msg.name, parts = msg.parts, vars = msg.vars })
  if not nb then return answer("That car can't start a build") end
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
    if not text then return send(pid, "cnr_panelReply", { text = "Not available from the panel" }) end
    panelMirror = pid
    local ran, err = pcall(runCommand, pid, text)
    panelMirror = nil
    pushPanel()
    if not ran then error(err, 0) end
  elseif msg.action == "settings" then
    panelSettings(pid, msg.values, msg.id)
  elseif msg.action == "build" then
    panelBuild(pid, msg)
  elseif msg.action == "apply" then
    panelMirror = pid
    local ran, err = pcall(function() applyEffects(current:apply(now(), pid)) end)
    panelMirror = nil
    pushPanel()
    if not ran then error(err, 0) end
  end
end

function cnrOnSetup(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" then return end
  if not current.evolving or current.state ~= "applying" or pid ~= current.runnerId then return end
  if d.model ~= nil and d.model ~= current.vehicle.model then return log("ignored a setup for another car model from " .. tostring(pid)) end
  local valid = build.normalize({ model = current.vehicle.model, parts = d.parts, vars = d.vars })
  if not valid then return log("ignored a malformed setup from " .. tostring(pid)) end
  local setup = { parts = valid.parts, vars = valid.vars }
  local changes = type(d.changes) == "table" and d.changes or {}
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
  local runnerName = MP.GetPlayerName(pid) or tostring(pid)
  local changes = type(d.changes) == "table" and d.changes or {}
  for p in pairs(current.players) do
    if not round.isAI(p) then send(p, "cnr_queued", { runner = runnerName, changes = changes }) end
  end
end

function cnrOnMissing(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" or type(d.parts) ~= "table" or #d.parts == 0 then return end
  if not current:isActive() or current.players[pid] == nil then return end
  local names = {}
  for i, part in ipairs(d.parts) do
    if i > 6 then names[#names + 1] = string.format("+%d more", #d.parts - 6) break end
    names[#names + 1] = tostring(part)
  end
  send(-1, "cnr_notice", { msg = string.format("⚠ %s is missing: %s", MP.GetPlayerName(pid) or tostring(pid), table.concat(names, ", ")) })
end

local CHAT_COMMANDS = { color = true, addstation = true, removestation = true, help = true, version = true }

function cnrOnChatMessage(pid, name, msg)
  local cmd = commands.parse(msg)
  if not cmd then return 0 end
  local handler = CHAT_COMMANDS[cmd.name] and handlers[cmd.name]
  if handler then
    handler(pid, cmd)
  else
    reply(pid, "Use the Cops and Robbers Panel (Esc > UI Apps)")
  end
  return 1
end

local function vehicleAllowed(pid, data, isSpawn)
  if not roundCarActive() or not current.players[pid] then return true end
  local decoded = parseVehicleData(data)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  if pcFile and not current.evolving and normalizeConfig(pcFile) ~= normalizeConfig(current.vehicle.config) then return false end
  if isSpawn and firstVid(pid) and not (current.test and pid == current.issuerId) then return false end
  return true, decoded
end

local function checkParts(pid, decoded)
  if not decoded or type(decoded.vcf) ~= "table" or decoded.vcf.parts == nil then return end
  local parts = decoded.vcf.parts
  local entry = partsBaseline[pid]
  if entry == nil then
    partsBaseline[pid] = { parts = parts, announced = false }
  elseif not tables.deepEqual(parts, entry.parts) then
    if not entry.announced then
      entry.announced = true
      log(string.format("%s changed parts during the round (not enforced), slots: %s",
        MP.GetPlayerName(pid) or tostring(pid), tables.diffKeys(entry.parts, parts, 5)))
    end
    entry.parts = parts
  end
end

local function tracksActive(pid)
  return current:isActive() and not (current.test and pid == current.issuerId)
end

function cnrOnVehicleSpawn(pid, vid, data)
  if not vehicleAllowed(pid, data, true) then
    reply(pid, "Only the round car is allowed")
    return 1
  end
  if tracksActive(pid) then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleEdited(pid, vid, data)
  local allowed, decoded = vehicleAllowed(pid, data, false)
  if not allowed then
    reply(pid, "Only the round car is allowed")
    return 1
  end
  if roundCarActive() and current.players[pid] and not (current.test and vid ~= activeVid[pid]) then checkParts(pid, decoded) end
  if tracksActive(pid) then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleDeleted(pid, vid)
  if activeVid[pid] == vid then activeVid[pid] = nil end
end

function cnrOnVehicleReset(pid, vid)
  if activeVid[pid] and activeVid[pid] ~= vid then return end
  if geoMode then
    local fx = current:vehicleReset(now(), pid)
    if #fx > 0 then pendingResetVerdicts[#pendingResetVerdicts + 1] = { pid = pid, at = now(), fx = fx } end
    return
  end
  applyEffects(current:vehicleReset(now(), pid))
end

function cnrOnPlayerJoin(pid)
  send(pid, "cnr_mode", { geo = geoMode, version = VERSION })
  requestStations(pid)
  applyEffects(current:playerJoined(now(), pid, MP.GetPlayerName(pid)))
end

function cnrOnPlayerDisconnect(pid)
  stationsRequested[pid] = nil
  panelSubs[pid] = nil
  boardSubs[pid] = nil
  local name = MP.GetPlayerName(pid)
  if name and geoReports[pid] then lastGeoByName[name] = geoPoint(geoReports[pid]) end
  geoReports[pid] = nil
  applyEffects(current:playerLeft(now(), pid))
  activeVid[pid] = nil
end

function cnrOnVehiclePicked(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  if not ok or type(decoded) ~= "table" or type(decoded.model) ~= "string" then return end
  applyEffects(current:vehiclePicked(now(), pid, decoded.model, decoded.config, MP.GetPlayers() or {}))
end

function cnrOnMyVehicle(pid, data)
  local ok, decoded = pcall(Util.JsonDecode, data)
  local vid = ok and type(decoded) == "table" and tonumber(decoded.vid)
  if not vid or not current:isActive() then return end
  activeVid[pid] = vid
  applyEffects(current:vehicleReady(now(), pid))
  if current.test then return end
  local vehicles = MP.GetPlayerVehicles(pid)
  if type(vehicles) ~= "table" then return end
  for other in pairs(vehicles) do
    if other ~= vid then MP.RemoveVehicle(pid, other) end
  end
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
      sub = { map = type(msg.map) == "string" and msg.map or sub.map, mode = type(msg.mode) == "string" and msg.mode or nil }
    end
    boardSubs[pid] = sub
    sendBoard(pid)
  end
end

function cnrOnSight(pid, data)
  local ok, d = pcall(Util.JsonDecode, data)
  if not ok or type(d) ~= "table" then return end
  current:sightReport(now(), pid, d.seen == true)
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

local function startAutoRound()
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
  applyEffects(current:tick(now(), cars, roundStations()))
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
MP.RegisterEvent("cnr_geo", "cnrOnGeo")
MP.RegisterEvent("cnr_relocated", "cnrOnRelocated")
MP.RegisterEvent("cnr_panel", "cnrOnPanel")
MP.RegisterEvent("cnr_sight", "cnrOnSight")
MP.RegisterEvent("cnr_board", "cnrOnBoard")
MP.RegisterEvent("cnr_setup", "cnrOnSetup")
MP.RegisterEvent("cnr_change", "cnrOnChange")
MP.RegisterEvent("cnr_missing", "cnrOnMissing")
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
send(-1, "cnr_mode", { geo = geoMode, version = VERSION })
log("Cops and Robbers " .. VERSION .. " loaded on " .. mapName .. " (" .. pluginDir .. ")")
