local pluginDir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./")
package.path = pluginDir .. "?.lua;" .. package.path

local vec = require("cnr.vec")
local config = require("cnr.config")
local round = require("cnr.round")
local leaderboard = require("cnr.leaderboard")
local commands = require("cnr.commands")
local colors = require("cnr.colors")
local tables = require("cnr.tables")

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

local function reply(pid, msg) MP.SendChatMessage(pid, PREFIX .. msg) end
local function broadcast(msg) MP.SendChatMessage(-1, PREFIX .. msg) end
local function send(pid, event, payload) MP.TriggerClientEvent(pid, event, Util.JsonEncode(payload or {})) end

local function loadConfig()
  local raw, corrupt = decodeFile(pluginDir .. "config.json")
  if corrupt then log("config.json is not valid JSON, using defaults") end
  local warnings
  cfg, warnings = config.merge(raw)
  for _, w in ipairs(warnings) do log("config: " .. w) end
end

local function loadLeaderboard()
  local decoded, corrupt = decodeFile(leaderboardPath)
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

local function colorFor(pid)
  local c = colors.get(colorStore, MP.GetPlayerName(pid) or "")
  return c and { hex = c.hex, r = c.r, g = c.g, b = c.b } or nil
end

local function roundCarActive()
  return current.vehicle ~= nil and current.state ~= "idle" and current.state ~= "picking"
end

local function stationsPath() return stationsDir .. mapName .. ".json" end

local function loadStations()
  local decoded = decodeFile(stationsPath())
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

local function saveStations()
  writeFile(stationsPath(), Util.JsonPrettify(Util.JsonEncode({ stations = stations })))
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
  vid = firstVid(pid)
  activeVid[pid] = vid
  return vid
end

local function carFor(pid)
  local vid = vidFor(pid)
  if not vid then return nil end
  local raw, err = MP.GetPositionRaw(pid, vid)
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
      broadcast(e.msg)
    elseif e.kind == "pickVehicle" then
      send(e.pid, "cnr_pickVehicle", { includeMods = cfg.includeModVehicles })
    elseif e.kind == "setup" then
      local runnerCar = carFor(current.runnerId)
      send(e.pid, "cnr_roundSetup", {
        runnerId = current.runnerId, role = e.role, copIndex = e.copIndex,
        model = current.vehicle.model, config = current.vehicle.config,
        phase = e.phase, countdownRemaining = e.countdownRemaining,
        headStartRemaining = e.headStartRemaining, color = colorFor(e.pid),
        runnerPos = runnerCar and runnerCar.pos or nil,
        copSpawnMin = cfg.copSpawnMinMeters, copSpawnMax = cfg.copSpawnMaxMeters,
      })
    elseif e.kind == "countdown" then
      send(-1, "cnr_countdown", { seconds = e.seconds })
    elseif e.kind == "runnerGo" then
      send(-1, "cnr_runnerGo", { headStartSeconds = e.headStartSeconds })
    elseif e.kind == "penalty" then
      send(e.pid, "cnr_penalty", { seconds = e.seconds })
    elseif e.kind == "penaltyEnd" then
      send(e.pid, "cnr_penaltyEnd", {})
    elseif e.kind == "release" then
      send(-1, "cnr_release", {})
    elseif e.kind == "state" then
      send(e.pid, "cnr_state", { resetAllowed = e.resetAllowed, resetHint = e.resetHint, catchProgress = e.catchProgress })
    elseif e.kind == "roundEnd" then
      send(-1, "cnr_roundEnd", {
        runnerId = e.runnerId, runnerName = e.runnerName, survivedSeconds = e.survivedSeconds,
        reason = e.reason, explode = e.explode,
      })
      activeVid = {}
      partsBaseline = {}
    elseif e.kind == "record" then
      local run = e.run
      local endedAt = os.time()
      run.map = mapName
      run.releasedAt = endedAt - math.floor(run.survivedSeconds + 0.5)
      run.endedAt = endedAt
      leaderboard.add(board, run)
      local ok, err = pcall(saveLeaderboard)
      if not ok then log("failed to save leaderboard: " .. tostring(err)) end
      if run.endReason == "caught" then
        broadcast(string.format("Runner caught! %s survived %s", run.player, leaderboard.formatTime(run.survivedSeconds)))
      else
        broadcast(string.format("%s disconnected after %s", run.player, leaderboard.formatTime(run.survivedSeconds)))
      end
      for _, line in ipairs(leaderboard.formatTop(board, 5)) do broadcast(line) end
    end
  end
end

local HELP = {
  "/cnr start <name|random> - set up a round with that runner",
  "/cnr go - start the countdown",
  "/cnr color <#hex|off> - your car color for every round",
  "/cnr stop - cancel the current round",
  "/cnr top - leaderboard",
  "/cnr addstation / removestation - edit this map's gas stations",
  "/cnr config - show settings",
  "/cnr reload - reload config.json",
}

local handlers = {}

function handlers.help(pid)
  for _, line in ipairs(HELP) do reply(pid, line) end
end

function handlers.start(pid, cmd)
  if current:isActive() then return reply(pid, "A round is already running") end
  local players = MP.GetPlayers() or {}
  local runnerId, err = commands.matchPlayer(cmd.rest, players)
  if not runnerId then return reply(pid, err) end
  requestStations(pid)
  activeVid = {}
  partsBaseline = {}
  applyEffects(current:start(now(), runnerId, pid, players))
end

function handlers.go(pid)
  applyEffects(current:go(now(), pid))
end

function handlers.color(pid, cmd)
  local name = MP.GetPlayerName(pid) or ""
  local arg = cmd.args[1]
  if not arg then
    local c = colors.get(colorStore, name)
    return reply(pid, c and ("Your car color is " .. c.hex) or "No car color set, use /cnr color #ff0000")
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
  reply(pid, "Your car color is now " .. c.hex)
  if roundCarActive() and current.players[pid] then
    send(pid, "cnr_paint", { color = colorFor(pid) })
  end
end

function handlers.stop(pid)
  local wasActive = current:isActive()
  applyEffects(current:stop(now(), pid))
  if not wasActive then send(-1, "cnr_roundEnd", { reason = "cancelled" }) end
end

function handlers.top(pid)
  for _, line in ipairs(leaderboard.formatTop(board, 10)) do reply(pid, line) end
end

function handlers.addstation(pid)
  local car = carFor(pid)
  if not car then return reply(pid, "You need to be in a vehicle") end
  stations[#stations + 1] = { x = car.pos.x, y = car.pos.y, z = car.pos.z, r = 0 }
  saveStations()
  reply(pid, string.format("Gas station added (%d on %s)", #stations, mapName))
end

function handlers.removestation(pid)
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
  for _, k in ipairs(keys) do reply(pid, k .. " = " .. tostring(cfg[k])) end
end

function handlers.reload(pid)
  if current:isActive() then return reply(pid, "Stop the round before reloading") end
  loadConfig()
  current = round.new(cfg)
  reply(pid, "Config reloaded")
end

function cnrOnChatMessage(pid, name, msg)
  local cmd = commands.parse(msg)
  if not cmd then return 0 end
  local handler = handlers[cmd.name]
  if handler then
    handler(pid, cmd)
  else
    reply(pid, "Unknown command, try /cnr help")
  end
  return 1
end

local function vehicleAllowed(pid, data, isSpawn)
  if not roundCarActive() or not current.players[pid] then return true end
  local decoded = parseVehicleData(data)
  if not decoded or decoded.jbm ~= current.vehicle.model then return false end
  local pcFile = type(decoded.vcf) == "table" and decoded.vcf.partConfigFilename
  if pcFile and normalizeConfig(pcFile) ~= normalizeConfig(current.vehicle.config) then return false end
  if isSpawn and firstVid(pid) then return false end
  return true, decoded
end

local function checkParts(pid, decoded)
  if not decoded or type(decoded.vcf) ~= "table" or decoded.vcf.parts == nil then return end
  local parts = decoded.vcf.parts
  if partsBaseline[pid] == nil then
    partsBaseline[pid] = parts
  elseif not tables.deepEqual(parts, partsBaseline[pid]) then
    send(pid, "cnr_restoreConfig", { model = current.vehicle.model, config = current.vehicle.config, color = colorFor(pid) })
    reply(pid, "Only paint can be changed, your car was reset to the round setup")
  end
end

function cnrOnVehicleSpawn(pid, vid, data)
  if not vehicleAllowed(pid, data, true) then
    reply(pid, "Only the round car is allowed")
    return 1
  end
  if current:isActive() then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleEdited(pid, vid, data)
  local allowed, decoded = vehicleAllowed(pid, data, false)
  if not allowed then
    reply(pid, "Only the round car is allowed")
    return 1
  end
  if roundCarActive() and current.players[pid] then checkParts(pid, decoded) end
  if current:isActive() then activeVid[pid] = vid end
  return 0
end

function cnrOnVehicleDeleted(pid, vid)
  if activeVid[pid] == vid then activeVid[pid] = nil end
end

function cnrOnVehicleReset(pid, vid)
  if activeVid[pid] and activeVid[pid] ~= vid then return end
  applyEffects(current:vehicleReset(now(), pid))
end

function cnrOnPlayerJoin(pid)
  requestStations(pid)
  applyEffects(current:playerJoined(now(), pid, MP.GetPlayerName(pid)))
end

function cnrOnPlayerDisconnect(pid)
  stationsRequested[pid] = nil
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
  local vehicles = MP.GetPlayerVehicles(pid)
  if type(vehicles) ~= "table" then return end
  for other in pairs(vehicles) do
    if other ~= vid then MP.RemoveVehicle(pid, other) end
  end
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
    saveStations()
    log(string.format("%d gas stations detected for %s", #stations, mapName))
  end
end

function cnrTick()
  if not current:isActive() then return end
  local cars = {}
  for pid in pairs(current.players) do cars[pid] = carFor(pid) end
  applyEffects(current:tick(now(), cars, stations))
end

FS.CreateDirectory(stationsDir)
loadConfig()
loadLeaderboard()
loadColors()
mapName = (tostring(MP.Get(MP.Settings.Map) or ""):match("levels/([^/]+)/")) or "unknown"
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
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
log("Cops and Robbers loaded on " .. mapName .. " (" .. pluginDir .. ")")
