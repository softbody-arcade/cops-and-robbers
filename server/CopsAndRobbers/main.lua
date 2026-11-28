local pluginDir = (debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./")
package.path = pluginDir .. "?.lua;" .. package.path

local store = require("arcade.store")
local messages = require("arcade.messages").new({ prefix = "[CnR] " })
local roster = require("arcade.roster").new()

local VERSION = "2.16.0"
local serverClock = MP.CreateTimer()
local function now() return serverClock:GetCurrent() end
local clock = { now = now, timer = MP.CreateTimer, unixTime = os.time }
local gameModule = require("cnr.game")
local manifest = gameModule.manifest(VERSION)
local settingsModule = require("arcade.settings")
local log, send, notify = messages.log, messages.send, messages.notify
local refuse, broadcast = messages.refuse, messages.broadcast
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
local buildPath = dataDir .. "build.json"
local declaration = settingsModule.combine(settingsModule.GLOBAL, gameModule.settingsDeclaration())
local settings = settingsModule.new(pluginDir .. "config.json", declaration, log)
local trafficService = require("arcade.traffic").new(roster, messages)
local cars = require("arcade.cars").new(roster, messages, trafficService)
local spectators = require("arcade.spectators").new(roster, messages)
local playerColors = require("arcade.playerColors").new(dataDir .. "colors.json", roster, messages)
local panelService = require("arcade.panel").new(messages, roster)
local nextRound = require("arcade.autoRounds").new()
local cycleModule = require("arcade.cycle")
local cycle = cycleModule.new({
  messages = messages, roster = roster, store = store, clock = clock,
  settings = settings, traffic = trafficService, cars = cars, spectators = spectators,
  playerColors = playerColors, panel = panelService, autoRounds = nextRound,
  dataDir = dataDir, map = tostring(MP.Get(MP.Settings.Map) or ""):match("levels/([^/]+)/") or "unknown",
}, manifest)
local ctx = cycle:context()
FS.CreateDirectory(stationsDir)
settings:load()
local game = gameModule.new(ctx)
cycle:attach(game)

local vec = require("cnr.vec")
local round = require("cnr.round")
local leaderboard = require("cnr.leaderboard")
local tables = require("cnr.tables")
local build = require("cnr.build")
local START_ROAD_SEARCH = 2000

math.randomseed(os.time())

local function loadLeaderboard()
  local leaderboardPath = game.leaderboardPath
  local decoded, corrupt = store.decode(leaderboardPath)
  if corrupt or not leaderboard.validShape(decoded) then
    local aside = leaderboardPath .. ".corrupt-" .. os.time()
    local moved, err = FS.Rename(leaderboardPath, aside)
    if moved == false then
      game.leaderboardLocked = true
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
  ctx.panel:push()
  answer(replacement and "New build: " .. build.label(replacement) or "Build reset")
end

local function panelSettings(pid, values, id)
  if type(id) ~= "number" and type(id) ~= "string" then id = nil end
  local function answer(ok, text, keys) send(pid, "cnr_panelReply", { ok = ok, text = text, keys = keys, id = id }) end
  if cycle:state() == "round" then return answer(false, "Stop the round first") end
  local keys, err = settings:apply(values)
  if not keys then return answer(false, err) end
  settings:load()
  answer(true, "Saved", keys)
  cycle:dispatch("settingsChanged", keys)
end

function cnrOnPanel(pid, data)
  local ok, msg = pcall(Util.JsonDecode, data)
  if not ok or type(msg) ~= "table" or type(msg.action) ~= "string" then return end
  if msg.action == "open" then
    ctx.panel:push(pid)
  elseif msg.action == "close" then
    panelService:close(pid)
  elseif msg.action == "command" then
    local text = cycle:allowCommand(msg.text)
    if not text then return send(pid, "cnr_panelReply", { text = "Not available from the panel", tone = "warn" }) end
    local ran, err = messages.mirrored(pid, panelService.run, panelService, pid, text)
    ctx.panel:push()
    if not ran then error(err, 0) end
  elseif msg.action == "station" then
    if msg.op ~= "add" and msg.op ~= "remove" then return end
    local ran, err = messages.mirrored(pid, panelService.run, panelService, pid, msg.op .. "station")
    ctx.panel:push()
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
    ctx.panel:push()
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
  ctx.panel:push()
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

function cnrOnVehicleSpawn(pid, vid, data) return cycle:onVehicleSpawn(pid, vid, data) end
function cnrOnVehicleEdited(pid, vid, data) return cycle:onVehicleEdited(pid, vid, data) end
function cnrOnVehicleDeleted(pid, vid) return cycle:onVehicleDeleted(pid, vid) end
function cnrOnVehicleReset(pid, vid) return cycle:onVehicleReset(pid, vid) end

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
  game:pushRules(pid)
  ctx.panel:pushLobby(pid)
  game:requestStations(pid)
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
  game:gridReady(pid)
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
  local vehicle = cycleModule.parseVehicleData(data)
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
  local limit = math.max(current.cfg.copSpawnMaxMeters, 1)
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
  if not integer(vid) or vid < 0 or not game:roundCarActive() or current.players[pid] == nil then return end
  local owned = cars:vehicles(pid)
  if not owned[vid] or (pid == current.issuerId and game:aiSlotForVid(vid)) then return end
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
    return current.test and pid == current.issuerId and game:aiSlotForVid(vid)
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
  game:removeAICar(id)
  game:removeAICar(game:aiSlotForVid(vid))
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
  game:updateBoard(pid, msg)
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
    game:saveStations(game.stations)
    log(string.format("%d gas stations detected for %s", #game.stations, game.mapName))
  end
end

function cnrTick() cycle:tick() end

loadLeaderboard()
loadBuild()
playerColors:load()
game:loadStations()

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
cycle:dispatch("rulesChanged")
ctx.panel:pushLobby()
log("Cops and Robbers " .. VERSION .. " loaded on " .. game.mapName .. " (" .. pluginDir .. ")")
