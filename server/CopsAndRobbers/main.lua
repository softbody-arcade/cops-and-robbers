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
local panel = require("cnr.panel")

local VERSION = "1.5.0"
local PREFIX = "[CnR] "
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
local leaderboardPath = dataDir .. "leaderboard.json"
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
  if corrupt then
    local aside = leaderboardPath .. ".corrupt-" .. os.time()
    FS.Rename(leaderboardPath, aside)
    log("leaderboard.json was unreadable, moved to " .. aside)
  end
  board = leaderboard.load(decoded)
end

local function saveLeaderboard()
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
        broadcast(string.format('Next round in %gs ("/cnr auto off" to stop)', cfg.autoNextDelaySeconds))
      end
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
  '"/cnr start <name|random|next|again>" - set up a round with that runner',
  '"/cnr go" - start the countdown',
  '"/cnr auto [on|off]" - prepare the next round automatically after each round',
  '"/cnr continue" - next step: set up a round, or start it (handy on a button)',
  '"/cnr reroll" - new car during prep',
  '"/cnr end" - end the chase and record the time',
  '"/cnr stop" - cancel the current round',
  '"/cnr color <#hex|off>" - your car color for every round',
  '"/cnr test <runner|cop>" - practice round against AI',
  '"/cnr top [cops|all|<map>]" - leaderboards',
  '"/cnr set <setting> <value>" - change a setting',
  '"/cnr config" - show settings',
  '"/cnr reload" - reload config.json',
  '"/cnr addstation" / "/cnr removestation" - edit this map\'s gas stations',
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
  applyEffects(current:start(now(), runnerId, pid, players))
end

function handlers.test(pid, cmd)
  if current:isActive() then return reply(pid, "A round is already running") end
  activeVid = {}
  partsBaseline = {}
  aiVid = {}
  local role = cmd.args[1] and cmd.args[1]:lower()
  applyEffects(current:start(now(), nil, pid, MP.GetPlayers() or {}, { test = true, role = role }))
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

function handlers.top(pid, cmd)
  local arg = cmd.args[1] and cmd.args[1]:lower()
  local lines
  if arg == "cops" then
    lines = leaderboard.formatTopCops(board, 10)
  elseif arg == "all" then
    lines = leaderboard.formatTop(board, 10)
  else
    lines = leaderboard.formatTop(board, 10, arg or mapName)
  end
  for _, line in ipairs(lines) do reply(pid, line) end
end

handlers["end"] = function(pid)
  applyEffects(current:endCalled(now(), pid))
end

function handlers.reroll(pid)
  applyEffects(current:reroll(now(), pid))
end

function handlers.set(pid, cmd)
  local key, value = cmd.args[1], cmd.rest and cmd.rest:match("^%S+%s+(.+)$")
  if not key or not value then return reply(pid, 'Usage: "/cnr set <setting> <value>"') end
  if current:isActive() then return reply(pid, "Stop the round before changing settings") end
  local updated, err = config.setValue(rawConfig, key, value)
  if not updated then return reply(pid, err) end
  writeFile(pluginDir .. "config.json", Util.JsonPrettify(Util.JsonEncode(updated)))
  loadConfig()
  current = round.new(cfg)
  local shown = cfg[key]
  if type(shown) == "table" then shown = table.concat(shown, ", ") end
  reply(pid, key .. " = " .. tostring(shown))
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

function handlers.config(pid)
  local keys = {}
  for k in pairs(cfg) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = cfg[k]
    if type(v) == "table" then v = table.concat(v, ", ") end
    reply(pid, k .. " = " .. tostring(v))
  end
end

function handlers.reload(pid)
  if current:isActive() then return reply(pid, "Stop the round before reloading") end
  loadConfig()
  current = round.new(cfg)
  reply(pid, "Config reloaded")
end

function handlers.continue(pid)
  if current.state == "idle" then
    return handlers.start(pid, { name = "start", args = { "next" }, rest = "next" })
  end
  applyEffects(current:go(now(), pid))
end

local function runCommand(pid, text)
  local cmd = commands.parse("/cnr " .. text)
  local handler = cmd and handlers[cmd.name]
  if handler then handler(pid, cmd) end
end

function cnrOnCommand(pid, data)
  local text = type(data) == "string" and data:lower():match("^%s*(.-)%s*$") or ""
  if not panel.BINDABLE[text] then return end
  runCommand(pid, text)
end

local function panelState()
  local running = current.state == "running"
  return panel.snapshot({
    version = VERSION, map = mapName, phase = current.state,
    runner = current.runnerId and current:runnerName() or nil,
    test = current.test == true,
    elapsed = running and current.releasedAt and math.max(0, now() - current.releasedAt) or nil,
    players = MP.GetPlayers() or {}, cfg = cfg, defaults = config.DEFAULTS,
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
  end
end

function cnrOnChatMessage(pid, name, msg)
  local cmd = commands.parse(msg)
  if not cmd then return 0 end
  local handler = handlers[cmd.name]
  if handler then
    handler(pid, cmd)
  else
    reply(pid, 'Unknown command, try "/cnr help"')
  end
  return 1
end

local function vehicleAllowed(pid, data, isSpawn)
  if not roundCarActive() or not current.players[pid] then return true end
  local decoded = parseVehicleData(data)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  if pcFile and normalizeConfig(pcFile) ~= normalizeConfig(current.vehicle.config) then return false end
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
MP.RegisterEvent("cnr_command", "cnrOnCommand")
MP.RegisterEvent("cnr_panel", "cnrOnPanel")
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
send(-1, "cnr_mode", { geo = geoMode, version = VERSION })
log("Cops and Robbers " .. VERSION .. " loaded on " .. mapName .. " (" .. pluginDir .. ")")
