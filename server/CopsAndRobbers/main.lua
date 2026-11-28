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
local log, send = messages.log, messages.send
local dataDir = pluginDir .. "data/"
local stationsDir = dataDir .. "stations/"
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

math.randomseed(os.time())

function cnrOnPanel(pid, data) return cycle:onPanel(pid, data) end
function cnrOnVehicleSpawn(pid, vid, data) return cycle:onVehicleSpawn(pid, vid, data) end
function cnrOnVehicleEdited(pid, vid, data) return cycle:onVehicleEdited(pid, vid, data) end
function cnrOnVehicleDeleted(pid, vid) return cycle:onVehicleDeleted(pid, vid) end
function cnrOnVehicleReset(pid, vid) return cycle:onVehicleReset(pid, vid) end

function cnrOnPlayerJoin(pid) return cycle:onPlayerJoin(pid) end
function cnrOnPlayerDisconnect(pid) return cycle:onPlayerDisconnect(pid) end

function cnrTick() cycle:tick() end

game:loadLeaderboard()
game:loadBuild()
playerColors:load()
game:loadStations()

MP.RegisterEvent("onVehicleSpawn", "cnrOnVehicleSpawn")
MP.RegisterEvent("onVehicleEdited", "cnrOnVehicleEdited")
MP.RegisterEvent("onVehicleDeleted", "cnrOnVehicleDeleted")
MP.RegisterEvent("onVehicleReset", "cnrOnVehicleReset")
MP.RegisterEvent("onPlayerJoin", "cnrOnPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "cnrOnPlayerDisconnect")
MP.RegisterEvent("cnr_panel", "cnrOnPanel")
for _, event in ipairs(manifest.clientEvents) do
  local suffix = event:gsub("^cnr_", "")
  local handler = "cnrOn" .. suffix:gsub("^%l", string.upper)
  _G[handler] = function(pid, data) return cycle:onClientEvent(event, pid, data) end
  MP.RegisterEvent(event, handler)
end
MP.RegisterEvent("cnr_tick", "cnrTick")
MP.CancelEventTimer("cnr_tick")
MP.CreateEventTimer("cnr_tick", 250)

send(-1, "cnr_roundEnd", { reason = "cancelled" })
send(-1, "cnr_mode", { version = VERSION, startGrid = true })
cycle:dispatch("rulesChanged")
ctx.panel:pushLobby()
log("Cops and Robbers " .. VERSION .. " loaded on " .. ctx.map .. " (" .. pluginDir .. ")")
