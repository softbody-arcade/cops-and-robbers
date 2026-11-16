dofile("tests/client_stubs.lua")

local SETUP = { role = "cop", runnerId = 2, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep", runnerPos = { x = 0, y = 0, z = 0 } }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function startCop(env)
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
end

test("joining registers the server events", function()
  local env = bootClient()
  for _, ev in ipairs({ "cnr_roundSetup", "cnr_countdown", "cnr_runnerGo", "cnr_release", "cnr_state", "cnr_roundEnd", "cnr_panelState", "cnr_panelReply" }) do
    assertEq(type(env.handlers[ev]), "function", ev)
  end
end)

test("a cop round places the car, reports it and shows the prep line", function()
  local env = bootClient()
  startCop(env)
  assertEq(env.replaced[1].model, "pickup")
  assertEq(env.lastSent("cnr_myVehicle").vid, 100)
  assertEq(env.teleported, 1)
  local h = env.hud()
  assertEq(h.visible, true); assertEq(h.mode, "round"); assertEq(h.driving, false)
  assertEq(h.center.kind, "role"); assertEq(h.center.role, "cop"); assertEq(h.center.car, "Gavril Pickup")
  assertEq(h.center.title, "YOU'RE A COP")
  assertEq(h.prep.waiting, "Waiting for the host to press GO")
end)

test("helicopter events drive the status item", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_release", {})
  env.tick(0.2)
  env.fire("cnr_heli", { phase = "arriving", seconds = 61 })
  env.tick(0.1)
  assertEq(env.hud().status.heli.text, "HELICOPTER IN")
  assertEq(env.hud().status.heli.time, "1:00")
  env.tick(10)
  assertEq(env.hud().status.heli.time, "0:50")
end)

test("a mid-round setup carries the helicopter and a new round clears it", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.phase = "running"; setup.heli = { phase = "searching" }
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  assertEq(env.hud().status.heli.text, "HELICOPTER SEARCHING")
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 3, runnerId = 2 })
  env.tick(0.2)
  startCop(env)
  env.fire("cnr_release", {})
  env.tick(1)
  assertEq(env.hud().status.heli, nil)
end)

test("countdown, runner go and release drive the centre and status", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_countdown", { seconds = 3 })
  env.tick(0.2)
  assertEq(env.hud().center.kind, "countdown")
  assertEq(env.hud().center.label, "RUNNER STARTS IN"); assertEq(env.hud().center.tone, "runner")
  assertEq(env.hud().prep, nil)
  assertEq(env.hud().driving, true)
  env.fire("cnr_runnerGo", { headStartSeconds = 7 })
  env.tick(0.2)
  assertEq(env.hud().center.label, "COPS RELEASED IN"); assertEq(env.hud().center.tone, "cop")
  assertEq(env.hud().status, nil)
  env.fire("cnr_release", {})
  env.tick(0.2)
  assertEq(env.hud().center.kind, "flash"); assertEq(env.hud().center.text, "GO!")
  env.tick(3)
  assertEq(env.hud().status.role, "cop")
  assertEq(env.hud().status.time, "0:03")
  assertEq(env.hud().driving, true)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 3, runnerId = 2 })
  env.tick(0.2)
  assertEq(env.hud().mode, "result"); assertEq(env.hud().driving, false)
end)

test("cops turn their emergency lights on and off", function()
  local env = bootClient()
  startCop(env)
  env.tick(2.5)
  local on = false
  for _, c in ipairs(env.veh.commands) do if c == "electrics.set_lightbar_signal(1)" then on = true end end
  assertEq(on, true)
  local before = #env.veh.commands
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  local off = false
  for i = before + 1, #env.veh.commands do
    if env.veh.commands[i] == "electrics.set_lightbar_signal(0)" then off = true end
  end
  assertEq(off, true)
end)

test("catch progress fills the bar", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_release", {})
  env.fire("cnr_state", { catchProgress = 0.5, resetAllowed = false })
  env.tick(0.2)
  assertEq(env.hud().catch.visible, true)
  assertEq(env.hud().catch.label, "HOLDING RUNNER")
end)

test("a refused reset highlights the reset part of the status line", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_release", {})
  env.tick(0.2)
  env.M.requestReset("place")
  env.tick(0.2)
  assertEq(env.hud().status.resetFlash, true)
end)

test("an allowed road reset puts a cop on the road", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_release", {})
  env.fire("cnr_state", { resetAllowed = true })
  local before = env.teleported
  env.veh.pos = vec3(500, 500, 0)
  env.M.requestReset("road")
  assertEq(env.teleported, before + 1)
  assertEq(env.veh.pos.y, 60)
end)

test("an AI crash shows once in the event line", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -10, role = "cop", name = "AI cop 1", index = 1 } } })
  env.tick(1)
  assertEq(#env.spawned, 1)
  env.fire("cnr_release", {})
  env.fire("cnr_notice", { msg = "AI cop 1: crash penalty 10s", about = -10 })
  env.fire("cnr_penalty", { aiId = -10, seconds = 10 })
  env.tick(0.2)
  assertEq(#env.hud().notices, 1)
end)

test("the result card shows the top 3, and leaving the server clears it", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_roundEnd", { reason = "caught", runnerName = "Bob", survivedSeconds = 75, catchers = { "Reinder" }, runnerId = 2 })
  env.fire("cnr_top", { rows = { { rank = 1, player = "Bob", time = "1:15" }, { rank = 2, player = "Reinder", time = "0:40", me = true } } })
  env.tick(0.2)
  assertEq(env.hud().mode, "result")
  assertEq(env.hud().result.title, "RUNNER CAUGHT")
  assertEq(env.hud().result.rows[1].player, "Bob"); assertEq(env.hud().result.rows[1].me, false)
  assertEq(env.hud().result.rows[2].me, true)
  assertEq(env.hud().result.top, nil)
  env.M.onBeamMPServerLeave()
  env.tick(0.5)
  assertEq(env.hud().visible, false)
  assertEq(env.lastTrigger("CnRPanel").phase, nil)
end)

test("auto off drops Next round in from the result card", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2, autoNextSeconds = 15 })
  env.tick(0.2)
  assertEq(env.hud().result.nextIn ~= nil, true)
  env.fire("cnr_autoNext", {})
  env.tick(0.2)
  assertEq(env.hud().result.nextIn, nil)
end)

test("a server mode message resets the panel so it resubscribes", function()
  local env = bootClient()
  env.triggers = {}
  env.fire("cnr_mode", { geo = false, version = "1.6.0" })
  local p = env.lastTrigger("CnRPanel")
  assertEq(p ~= nil and p.phase, nil)
  assertEq(p ~= nil, true)
end)

test("the panel bridge forwards requests and state", function()
  local env = bootClient()
  env.M.panel({ action = "open" })
  assertEq(env.lastSent("cnr_panel").action, "open")
  env.fire("cnr_panelState", { phase = "idle" })
  assertEq(env.lastTrigger("CnRPanel").phase, "idle")
  env.fire("cnr_panelReply", { ok = true, text = "Saved" })
  assertEq(env.lastTrigger("CnRPanelReply").text, "Saved")
end)

test("picking a vehicle sends an official car config", function()
  local env = bootClient({ configs = {
    { model_key = "pickup", key = "base", Source = "BeamNG - Official", Type = "Car", pcFilename = "/vehicles/pickup/base.pc" },
    { model_key = "modcar", key = "x", Source = "Some Mod", Type = "Car" },
  } })
  env.fire("cnr_pickVehicle", { includeMods = false, excludedModels = {} })
  local s = env.lastSent("cnr_vehiclePicked")
  assertEq(s.model, "pickup"); assertEq(s.config, "vehicles/pickup/base.pc")
end)

local function fakeLayouts()
  local name = "/settings/ui_apps/layouts/beammp.uilayout.json"
  local other = "/settings/ui_apps/layouts/earth.uilayout.json"
  local L = { disk = { [name] = { apps = {} }, [other] = { apps = {} } }, added = {}, current = name }
  L.api = {
    getCurrentLayout = function() return { filename = L.current, apps = L.disk[L.current].apps, userFileExists = true } end,
    setCurrentLayout = function() end,
    getAvailableLayouts = function()
      return { { filename = name, apps = L.disk[name].apps }, { filename = other, apps = L.disk[other].apps } }
    end,
    addApp = function(file, app, placement)
      table.insert(L.disk[file].apps, { appName = app, placement = placement })
      L.added[#L.added + 1] = placement
      return true
    end,
    removeApp = function(file, idx0) table.remove(L.disk[file].apps, idx0 + 1); return true end,
  }
  L.name, L.other = name, other
  return L
end

local function names(L)
  local list = {}
  for _, a in ipairs(L.disk[L.name].apps) do list[#list + 1] = a.appName end
  return list
end

local function has(L, app)
  for _, n in ipairs(names(L)) do if n == app then return true end end
  return false
end

local function countApp(L, app)
  local n = 0
  for _, name in ipairs(names(L)) do if name == app then n = n + 1 end end
  return n
end

local function assertPlacement(L, app, expected)
  local placement
  for _, a in ipairs(L.disk[L.name].apps) do
    if a.appName == app then placement = a.placement end
  end
  assertEq(type(placement), "table", app)
  for k, v in pairs(expected) do assertEq(placement[k], v, app .. "." .. k) end
  for k in pairs(placement) do assertEq(expected[k] ~= nil, true, app .. "." .. k) end
end

local ANNOUNCE_PLACEMENT = { left = "50%", right = "", top = "10em", bottom = "", width = "40em", height = "12em" }
local HUD_PLACEMENT = { left = "50%", right = "", top = "", bottom = "2em", width = "40em", height = "22em" }
local HOWTO_PLACEMENT = { left = "50%", right = "", top = "50%", bottom = "", width = "40em", height = "26em" }

test("joining places Announcements and the HUD, then checks less often", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  env.tick(4, 0.5)
  assertEq(#L.added, 2)
  assertPlacement(L, "copsAndRobbersAnnouncements", ANNOUNCE_PLACEMENT)
  assertPlacement(L, "copsAndRobbersHud", HUD_PLACEMENT)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  local before = env.reads[L.name]
  env.tick(20, 0.5)
  assertEq(env.reads[L.name] - before <= 4, true)
end)

test("the player can't remove Announcements or the HUD: both come back", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  env.tick(4, 0.5)
  L.disk[L.name].apps = {}
  env.tick(10, 0.5)
  assertEq(countApp(L, "copsAndRobbersAnnouncements"), 1)
  assertEq(countApp(L, "copsAndRobbersHud"), 1)
end)

test("toggle opens and closes the leaderboard", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  local apps = require("copsAndRobbers/apps")
  env.tick(4, 0.5)
  apps.toggle("board")
  env.tick(0.5, 0.5)
  assertEq(has(L, "copsAndRobbersLeaderboard"), true)
  assertEq(apps.isOpen("board"), true)
  apps.toggle("board")
  env.tick(0.5, 0.5)
  assertEq(has(L, "copsAndRobbersLeaderboard"), false)
  assertEq(apps.isOpen("board"), false)
  assertEq(has(L, "copsAndRobbersHud"), true)
end)

test("isOpen sees an app the player added", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  local apps = require("copsAndRobbers/apps")
  assertEq(apps.isOpen("panel"), false)
  table.insert(L.disk[L.name].apps, { appName = "copsAndRobbersPanel" })
  assertEq(apps.isOpen("panel"), true)
  apps.toggle("panel")
  assertEq(has(L, "copsAndRobbersPanel"), false)
end)

test("leaving the server removes the HUD apps, How to play and the apps it opened, not ones the player added", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  local apps = require("copsAndRobbers/apps")
  env.tick(4, 0.5)
  apps.toggle("board")
  env.M.ui({ action = "help", open = true })
  assertEq(has(L, "copsAndRobbersHowToPlay"), true)
  table.insert(L.disk[L.name].apps, { appName = "copsAndRobbersPanel" })
  env.M.onBeamMPServerLeave()
  assertEq(has(L, "copsAndRobbersHud"), false)
  assertEq(has(L, "copsAndRobbersAnnouncements"), false)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  assertEq(has(L, "copsAndRobbersLeaderboard"), false)
  assertEq(has(L, "copsAndRobbersPanel"), true)
end)

test("a layout switch is picked up right away, not after the slow check", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  env.tick(4, 0.5)
  assertEq(#L.added, 2)
  L.current = L.other
  env.M.onGameStateUpdate({})
  env.tick(1, 0.25)
  assertEq(#L.added, 4)
  assertEq(#L.disk[L.other].apps, 2)
end)

test("leaving deletes the HUD apps' copy of BeamMP's own layout, which comes from the BeamMP zip", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L, origins = { [L.name] = "/mods/multiplayer/beammp.zip" } })
  env.tick(4, 0.5)
  assertEq(#L.added, 2)
  env.M.onBeamMPServerLeave()
  assertEq(#env.removedFiles, 1); assertEq(env.removedFiles[1], L.name)
end)

test("leaving keeps a layout file that is the player's own", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L, origins = { [L.name] = "" } })
  env.tick(4, 0.5)
  env.M.onBeamMPServerLeave()
  assertEq(#env.removedFiles, 0)
end)

test("unloading drops the cached helper modules so a rejoin loads fresh code", function()
  local env = bootClient()
  assertEq(package.loaded["copsAndRobbers/hudfeed"] ~= nil, true)
  env.M.onExtensionUnloaded()
  for name in pairs(package.loaded) do
    assertEq(name:find("^copsAndRobbers/") == nil, true, name)
  end
end)

local function copInChase(env)
  local setup = copy(SETUP)
  setup.sightMaxMeters = 400
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  env.addObject(300, vec3(0, 100, 0))
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "2-0" } })
  env.fire("cnr_release", {})
end

local function countSentEv(env, ev)
  local n = 0
  for _, s in ipairs(env.sent) do if s.ev == ev then n = n + 1 end end
  return n
end

test("a cop who can see the runner reports it once, then as a keep-alive", function()
  local env = bootClient()
  copInChase(env)
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, true)
  local n = countSentEv(env, "cnr_sight")
  env.tick(2)
  assertEq(countSentEv(env, "cnr_sight"), n)
  env.tick(4)
  assertEq(countSentEv(env, "cnr_sight"), n + 1)
end)

test("a blocked view or a runner out of range reports out of sight", function()
  local env = bootClient()
  copInChase(env)
  env.blockAt = 5
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
  env.blockAt = nil
  env.objects[300].pos = vec3(0, 900, 0)
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
  env.objects[300].pos = vec3(0, 100, 0)
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, true)
end)

test("a live update without route shows IN SIGHT, with route the live distance", function()
  local env = bootClient()
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { live = true, route = false, pos = { x = 0, y = 100, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "IN SIGHT"); assertEq(env.hud().status.info, nil)
  env.fire("cnr_lastSeen", { live = true, route = true, pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "LIVE"); local i = env.hud().status.info
  assertEq(i.before, "Runner"); assertEq(i.dist, "640 m"); assertEq(i.after, "N")
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.tag, nil); local i2 = env.hud().status.info
  assertEq(i2.before, "Runner seen"); assertEq(i2.dist, "640 m"); assertEq(i2.after, "N")
end)

local function trackPaths(env)
  env.paths = {}
  _G.core_groundMarkers = { setPath = function(t) env.paths[#env.paths + 1] = t or false end }
end

local function targetPaths(env)
  local n = 0
  for _, t in ipairs(env.paths) do if t then n = n + 1 end end
  return n
end

local function earthStub(env)
  env.gpsSet = 0
  _G.beamngEarth_api = {
    version = function() return 1 end,
    has = function() return true end,
    gpsSet = function() env.gpsSet = env.gpsSet + 1 return true end,
    gpsClear = function() end,
    toGame = function(lat, lon, h) return lon, lat, h end,
    toGeo = function(x, y, z) return y, x, z end,
    places = function() return {} end,
    gps = function() return {} end,
  }
end

test("out of sight clears the route when you see the runner, as today", function()
  local env = bootClient()
  trackPaths(env)
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { live = true, route = true, pos = { x = 0, y = 640, z = 0 } })
  assertEq(targetPaths(env), 1)
  env.fire("cnr_lastSeen", { live = true, route = false, pos = { x = 0, y = 100, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "IN SIGHT"); assertEq(env.hud().status.info, nil)
  assertEq(env.paths[#env.paths], false)
end)

test("always keeps the route while you see the runner", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "always" } } })
  trackPaths(env)
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { live = true, route = false, pos = { x = 0, y = 100, z = 0 } })
  env.tick(0.2)
  local last = env.paths[#env.paths]
  assertEq(last ~= false and last.y, 100)
  assertEq(env.hud().status.tag, "IN SIGHT")
  assertEq(env.hud().status.info.before, "Runner"); assertEq(env.hud().status.info.dist, "100 m")
  assertEq(env.hud().status.info.after, "N")
end)

test("never draws no route and still shows distance and direction", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "never" } } })
  trackPaths(env)
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(targetPaths(env), 0)
  local i = env.hud().status.info
  assertEq(i.before, "Runner seen"); assertEq(i.dist, "640 m"); assertEq(i.after, "N")
  env.fire("cnr_lastSeen", { live = true, route = true, pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(targetPaths(env), 0)
  assertEq(env.hud().status.info.before, "Runner")
end)

test("Never clears a route left from before", function()
  local env = bootClient()
  trackPaths(env)
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  assertEq(targetPaths(env), 1)
  env.M.ui({ action = "setting", key = "route", value = "never" })
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  assertEq(env.paths[#env.paths], false)
  assertEq(targetPaths(env), 1)
end)

test("Never leaves a waypoint the mod did not draw alone", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "never" } } })
  trackPaths(env)
  copInChase(env)
  local before = #env.paths
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  env.fire("cnr_lastSeen", { live = true, route = false, pos = { x = 0, y = 100, z = 0 } })
  assertEq(#env.paths, before)
end)

test("Never shows IN SIGHT on a live update in sight and draws nothing", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "never" } } })
  trackPaths(env)
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { live = true, route = false, pos = { x = 0, y = 100, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "IN SIGHT"); assertEq(env.hud().status.info, nil)
  assertEq(targetPaths(env), 0)
end)

test("Never on BeamNG.Earth sets no GPS destination and shows the straight distance", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "never" } } })
  earthStub(env)
  env.fire("cnr_mode", { geo = true })
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { geo = { lat = 640, lon = 0, h = 0 } })
  env.tick(0.2)
  local gpsSet = env.gpsSet
  local i = env.hud().status.info
  _G.beamngEarth_api = nil
  assertEq(gpsSet, 0)
  assertEq(i.dist, "640 m")
end)

test("Always keeps the Earth GPS destination while in sight", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { route = "always" } } })
  earthStub(env)
  env.fire("cnr_mode", { geo = true })
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { live = true, route = true, geo = { lat = 640, lon = 0, h = 0 } })
  local before = env.gpsSet
  env.fire("cnr_lastSeen", { live = true, route = false, geo = { lat = 100, lon = 0, h = 0 } })
  local after = env.gpsSet
  env.tick(0.2)
  local tag = env.hud().status.tag
  _G.beamngEarth_api = nil
  assertEq(after, before + 1)
  assertEq(tag, "IN SIGHT")
end)

test("a last-seen ping past 1 km shows in km", function()
  local env = bootClient()
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 1500, z = 0 } })
  env.tick(0.2)
  local i = env.hud().status.info
  assertEq(i.before, "Runner seen"); assertEq(i.dist, "1.5 km")
end)

test("the chase distance follows the game's unit", function()
  local env = bootClient()
  copInChase(env)
  env.veh.pos = vec3(0, 0, 0)
  env.gameSettings.uiUnitLength = "imperial"
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.info.dist, "0.4 mi")
  env.gameSettings.uiUnitLength = "metric"
  env.tick(0.2)
  assertEq(env.hud().status.info.dist, "640 m")
end)

test("the runner sees SPOTTED or HIDDEN with the nearest cop", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  env.tick(1)
  env.fire("cnr_release", {})
  env.fire("cnr_nearestCop", { dist = 1200 })
  env.fire("cnr_spotted", { spotted = true })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "SPOTTED"); local i = env.hud().status.info
  assertEq(i.before, "Nearest cop"); assertEq(i.dist, "1.2 km")
  env.fire("cnr_spotted", { spotted = false })
  env.tick(0.2)
  assertEq(env.hud().status.tag, "HIDDEN"); local i = env.hud().status.info
  assertEq(i.before, "Nearest cop"); assertEq(i.dist, "1.2 km")
end)

test("the leaderboard bridge forwards requests and state with car names", function()
  local env = bootClient()
  env.M.board({ action = "open" })
  assertEq(env.lastSent("cnr_board").action, "open")
  env.fire("cnr_boardState", { filter = "west_coast_usa", runners = { { player = "Bob", survivedSeconds = 90, model = "pickup" } }, cops = {}, players = {} })
  local b = env.lastTrigger("CnRBoard")
  assertEq(b.runners[1].car, "Gavril Pickup")
  env.M.onBeamMPServerLeave()
  assertEq(env.lastTrigger("CnRBoard").filter, nil)
end)

test("sight follows the runner's round car, never one of his traffic cars", function()
  local env = bootClient()
  copInChase(env)
  env.addObject(301, vec3(0, 900, 0))
  env.mpVehicles["2-1"] = { gameVehicleID = 301, isSpawned = true }
  env.mpPlayers[2] = { activeVehicleID = "2-1" }
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, true)
  env.fire("cnr_roundCars", { keys = {} })
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
end)

test("sight needs a clear ray in both directions", function()
  local env = bootClient()
  copInChase(env)
  env.blockFrom = vec3(0, 101, 0)
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
end)

test("prep keeps the parts menu closed for everyone in random mode", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  assertEq(env.actionFilter.cnr_parts, true)
  local cop = bootClient()
  cop.fire("cnr_roundSetup", copy(SETUP))
  assertEq(cop.actionFilter.cnr_parts, true)
end)

test("in evolving prep only the runner gets the parts menu", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep", evolving = true })
  assertEq(env.actionFilter.cnr_parts, false)
  env.fire("cnr_countdown", { seconds = 3 })
  assertEq(env.actionFilter.cnr_parts, true)
  local cop = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  cop.fire("cnr_roundSetup", setup)
  assertEq(cop.actionFilter.cnr_parts, true)
end)

test("no pop-ups during a full round", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  env.fire("cnr_countdown", { seconds = 3 })
  env.tick(1)
  env.fire("cnr_runnerGo", { headStartSeconds = 5 })
  env.tick(1)
  env.fire("cnr_release", {})
  env.fire("cnr_state", { resetAllowed = false, resetHint = "Reset in 5s", catchProgress = 0.4 })
  env.tick(1.2)
  env.fire("cnr_penalty", { seconds = 5 })
  env.tick(1)
  env.fire("cnr_penaltyEnd", {})
  env.fire("cnr_lastSeen", { pos = { x = 10, y = 0, z = 0 } })
  env.fire("cnr_roundEnd", { reason = "caught", runnerName = "Bob", survivedSeconds = 30, runnerId = 2, catchers = { "Ann" } })
  env.tick(1)
  assertEq(#env.toasts, 0)
end)

test("notices become HUD events with their tone", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_notice", { msg = "Ann reset illegally", tone = "warn" })
  env.fire("cnr_notice", { msg = "Change 7 by Bob", tone = "info" })
  env.tick(0.2)
  local events = env.hud().notices
  assertEq(#events, 2)
  assertEq(events[1].text, "Change 7 by Bob"); assertEq(events[1].tone, "info")
  assertEq(events[2].text, "Ann reset illegally"); assertEq(events[2].tone, "warn")
  assertEq(#env.toasts, 0)
end)

test("a cancelled round says why on the result card and keeps the notice", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_notice", { msg = "Runner left, round cancelled" })
  env.fire("cnr_roundEnd", { reason = "cancelled", message = "Runner left, round cancelled" })
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.mode, "result"); assertEq(h.result.title, "ROUND CANCELLED")
  assertEq(h.result.message, "Runner left, round cancelled")
  assertEq(h.notices[1] and h.notices[1].text, "Runner left, round cancelled")
end)

test("a plain cancel does not repeat the title on the result card", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_roundEnd", { reason = "cancelled", message = "Round cancelled" })
  env.tick(0.2)
  assertEq(env.hud().mode, "result"); assertEq(env.hud().result.message, nil)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 3, runnerId = 2, message = "x" })
  env.tick(0.2)
  assertEq(env.hud().result.message, nil)
end)

test("the host sees why a vehicle pick timed out", function()
  local env = bootClient()
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  env.fire("cnr_notice", { msg = "Vehicle pick timed out" })
  env.fire("cnr_roundEnd", { reason = "cancelled", message = "Vehicle pick timed out" })
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.mode, "lobby")
  assertEq(h.notices[1] and h.notices[1].text, "Vehicle pick timed out")
end)

test("a missing reset binding is a standing warning until bound", function()
  local env = bootClient()
  local hudfeed = package.loaded["copsAndRobbers/hudfeed"]
  local text = "Bind a reset or recover button to reset during rounds"
  core_input_bindings.bindings = {}
  env.fire("cnr_roundSetup", copy(SETUP))
  assertEq(hudfeed.warnings()[1], text)
  env.fire("cnr_roundEnd", { reason = "cancelled" })
  core_input_bindings.bindings = { { contents = { bindings = { { action = "reset_physics" } } } } }
  env.fire("cnr_roundSetup", copy(SETUP))
  assertEq(#hudfeed.warnings(), 0)
end)

test("a missing reset binding also shows a warn notice at round setup", function()
  local env = bootClient()
  local text = "Bind a reset or recover button to reset during rounds"
  core_input_bindings.bindings = {}
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(0.2)
  local n = env.hud().notices[1]
  assertEq(n and n.text, text); assertEq(n and n.tone, "warn")
end)

test("binding a reset key clears the lobby line when the lobby refreshes", function()
  local env = bootClient()
  local hudfeed = package.loaded["copsAndRobbers/hudfeed"]
  local text = "Bind a reset or recover button to reset during rounds"
  core_input_bindings.bindings = {}
  env.fire("cnr_roundSetup", copy(SETUP))
  env.fire("cnr_roundEnd", { reason = "cancelled" })
  assertEq(hudfeed.warnings()[1], text)
  core_input_bindings.bindings = { { contents = { bindings = { { action = "reset_physics" } } } } }
  env.fire("cnr_lobby", { online = 2 })
  assertEq(#hudfeed.warnings(), 0)
end)

test("binding a reset key clears the lobby line within a few seconds", function()
  local env = bootClient()
  local hudfeed = package.loaded["copsAndRobbers/hudfeed"]
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  core_input_bindings.bindings = {}
  env.fire("cnr_roundSetup", copy(SETUP))
  env.fire("cnr_roundEnd", { reason = "cancelled" })
  env.tick(0.5)
  assertEq(#hudfeed.warnings(), 1)
  core_input_bindings.bindings = { { contents = { bindings = { { action = "reset_physics" } } } } }
  env.tick(2.5)
  assertEq(#hudfeed.warnings(), 0)
  env.tick(8)
  assertEq(env.hud().mode, "lobby"); assertEq(#env.hud().lobby.warnings, 0)
end)

test("version mismatch and a missing BeamNG.Earth are standing warnings", function()
  local env = bootClient()
  local hudfeed = package.loaded["copsAndRobbers/hudfeed"]
  env.fire("cnr_mode", { geo = false, version = "9.9.9" })
  assertEq(hudfeed.warnings()[1], "Your copy is " .. CNR_VERSION .. ", the server runs 9.9.9: rejoin to update")
  env.fire("cnr_mode", { geo = true, version = CNR_VERSION })
  local w = hudfeed.warnings()
  assertEq(#w, 1)
  assertEq(w[1], "Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map")
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  assertEq(#hudfeed.warnings(), 0)
  assertEq(#env.toasts, 0)
end)

test("reset refused in prep is a HUD event", function()
  local env = bootClient()
  startCop(env)
  env.M.requestReset("place")
  env.tick(0.2)
  local events = env.hud().notices
  assertEq(#events, 1)
  assertEq(events[1].text, "Reset not available"); assertEq(events[1].tone, "warn")
  assertEq(#env.toasts, 0)
end)

local EVOLVING_RUNNER = { role = "runner", runnerId = 1, model = "pickup", phase = "prep", evolving = true,
  config = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = { gear1 = 3.1 } } }

test("the evolving runner's change is diffed against his own build and sent once per change", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  local first = env.lastSent("cnr_change")
  assertEq(first ~= nil and #first.changes, 0)
  env.liveParts.pickup_engine = "v8_60"
  env.liveParts.pickup_paint_design = "flames"
  env.tick(1.2)
  local sent = env.lastSent("cnr_change")
  assertEq(#sent.changes, 1)
  assertEq(sent.changes[1].label, "Engine"); assertEq(sent.changes[1].from, "4.5L V8"); assertEq(sent.changes[1].to, "6.0L V8")
  assertEq(sent.changes[1].parts[1], "v8_60")
  local n = 0
  for _, s in ipairs(env.sent) do if s.ev == "cnr_change" then n = n + 1 end end
  env.tick(3)
  local m = 0
  for _, s in ipairs(env.sent) do if s.ev == "cnr_change" then m = m + 1 end end
  assertEq(m, n)
end)

test("on apply the runner sends his exact setup without the livery", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.liveParts.pickup_engine = "v8_60"
  env.tick(1.2)
  env.fire("cnr_requestSetup", {})
  local s = env.lastSent("cnr_setup")
  assertEq(s.parts.pickup_engine, "v8_60"); assertEq(s.parts.pickup_paint_design, nil); assertEq(s.vars.gear1, 3.1)
  assertEq(s.changes[1].label, "Engine")
end)

test("a rebuild replaces the car in place, closes the parts menu and reports missing parts", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  local before = #env.replaced
  env.fire("cnr_rebuild", { model = "pickup", config = { format = 2, model = "pickup", parts = { pickup_engine = "v8_60", pickup_turbo = "meo_turbo" }, vars = {} } })
  assertEq(#env.replaced, before + 1)
  assertEq(env.replaced[#env.replaced].opt.config.parts.pickup_engine, "v8_60")
  assertEq(env.actionFilter.cnr_parts, true)
  local missing = env.lastSent("cnr_missing")
  assertEq(#missing.parts, 1); assertEq(missing.parts[1], "meo_turbo")
  env.tick(0.2)
  assertEq(env.hud().center.kind, "applying"); assertEq(env.hud().center.text, "APPLYING CHANGES")
  assertEq(env.hud().prep.waiting, "Waiting for the host to press GO")
  env.fire("cnr_applied", {})
  env.tick(0.2)
  assertEq(env.hud().center.kind, "role")
  assertEq(env.hud().prep.waiting, "Waiting for the host to press GO")
end)

test("the car report after a rebuild carries the rebuild id", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  assertEq(env.lastSent("cnr_myVehicle").rebuild, nil)
  env.fire("cnr_rebuild", { model = "pickup", rebuild = 7, config = { format = 2, model = "pickup", parts = { pickup_engine = "v8_60" }, vars = {} } })
  env.tick(1)
  assertEq(env.lastSent("cnr_myVehicle").rebuild, 7)
end)

test("a player who joins while applying reports with the rebuild id from his setup", function()
  local env = bootClient()
  local setup = copy(EVOLVING_RUNNER)
  setup.role, setup.runnerId, setup.phase, setup.rebuild = "cop", 2, "applying", 5
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  assertEq(env.lastSent("cnr_myVehicle").rebuild, 5)
end)

test("practice as runner: a rebuild respawns the AI cops in place with the new build and reports them again", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.fire("cnr_setupAI", { model = "pickup", config = EVOLVING_RUNNER.config, runnerId = 1,
    ai = { { id = -10, role = "cop", name = "AI cop 1", index = 1, color = { r = 0, g = 1, b = 0 } } } })
  env.tick(1)
  assertEq(#env.spawned, 1)
  local old = env.spawned[1].veh
  old.pos = vec3(30, 40, 0)
  env.fire("cnr_rebuild", { model = "pickup", rebuild = 3, config = { format = 2, model = "pickup", parts = { pickup_engine = "v8_60" }, vars = {} } })
  assertEq(#env.spawned, 2)
  assertEq(env.objects[old.id], nil)
  local new = env.spawned[2]
  assertEq(new.opt.config.parts.pickup_engine, "v8_60")
  assertEq(new.opt.pos.x, 30); assertEq(new.opt.pos.y, 40)
  assertEq(new.opt.paint.y, 1)
  assertEq(new.opt.autoEnterVehicle, false)
  env.sent = {}
  env.tick(0.2)
  local report = env.lastSent("cnr_aiVehicles")
  assertEq(report.ai[1].id, -10); assertEq(report.ai[1].vid, new.veh.id)
end)

test("everyone sees the queued change in the HUD", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  env.fire("cnr_roundSetup", setup)
  env.fire("cnr_queued", { runner = "Bob", changes = { { label = "Engine", from = "4.5L V8", to = "6.0L V8" } } })
  env.tick(0.2)
  assertEq(env.hud().change.title, "Bob's change"); assertEq(env.hud().change.count, 1)
end)

test("a player who lacks a part of the queued change sees it marked missing", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  env.fire("cnr_roundSetup", setup)
  env.fire("cnr_queued", { runner = "Bob", changes = {
    { label = "Engine", from = "4.5L V8", to = "6.0L V8", parts = { "v8_60" } },
    { label = "Turbo", from = "(none)", to = "Meo Turbo", parts = { "meo_turbo" } },
  } })
  env.tick(0.2)
  local lines = env.hud().change.lines
  assertEq(lines[1].missing, nil); assertEq(lines[1].parts, nil)
  assertEq(lines[2].missing, true)
end)

test("a repaint during evolving prep keeps the runner's queued change", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.liveParts.pickup_engine = "v8_60"
  env.fire("cnr_paint", { color = { r = 1, g = 0, b = 0 } })
  assertEq(env.replaced[#env.replaced].opt.config.parts.pickup_engine, "v8_60")
end)

test("a cop's evolving car gets the build with emergency lights checked", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  setup.config = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = {} }
  env.fire("cnr_roundSetup", setup)
  assertEq(type(env.replaced[#env.replaced].opt.config), "table")
  assertEq(env.replaced[#env.replaced].opt.config.parts.pickup_engine, "v8")
end)

local CONFIGS = {
  { model_key = "pickup", key = "base", Configuration = "Base", Source = "BeamNG - Official", Type = "Car", pcFilename = "/vehicles/pickup/base.pc" },
  { model_key = "meocar", key = "drag", Configuration = "Drag", Source = "Meo's Drag", Type = "Car", pcFilename = "/vehicles/meocar/drag.pc" },
  { model_key = "localcar", key = "x", Configuration = "X", Source = "My Mod", Type = "Car", pcFilename = "/vehicles/localcar/x.pc" },
  { model_key = "citybus", key = "city", Configuration = "City", Source = "BeamNG - Official", Type = "Car", pcFilename = "/vehicles/citybus/city.pc" },
  { model_key = "pickup", key = "mine", Configuration = "Mine", Source = "Custom", Type = "Car", pcFilename = "/vehicles/pickup/mine.pc" },
}
local ORIGINS = { ["/vehicles/meocar/drag.pc"] = "/mods/multiplayer/meosdrag.zip", ["/vehicles/localcar/x.pc"] = "/mods/repo/mymod.zip" }

test("the build car list has only server-provided configs", function()
  local env = bootClient({ configs = CONFIGS, origins = ORIGINS })
  env.M.configs({ includeMods = true, excludedModels = { "citybus" } })
  local list = env.lastTrigger("CnRConfigs")
  local byConfig = {}
  for _, c in ipairs(list) do byConfig[c.config] = c end
  assertEq(#list, 2)
  assertEq(byConfig["vehicles/pickup/base.pc"] ~= nil, true); assertEq(byConfig["vehicles/meocar/drag.pc"] ~= nil, true)
  assertEq(byConfig["vehicles/pickup/base.pc"].label, "Gavril Pickup – Base")
  env.M.configs({ includeMods = false, excludedModels = {} })
  assertEq(#env.lastTrigger("CnRConfigs"), 2)
end)

test("starting a build reads the chosen config and sends its parts", function()
  local env = bootClient({ configs = CONFIGS, origins = ORIGINS,
    files = { ["/vehicles/pickup/base.pc"] = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = { gear1 = 3.1 } } } })
  env.M.newBuild({ config = "vehicles/pickup/base.pc" })
  local msg = env.lastSent("cnr_panel")
  assertEq(msg.action, "build"); assertEq(msg.op, "new"); assertEq(msg.model, "pickup")
  assertEq(msg.parts.pickup_engine, "v8"); assertEq(msg.vars.gear1, 3.1); assertEq(msg.name, "Gavril Pickup")
  env.M.newBuild({ config = "vehicles/pickup/missing.pc" })
  assertEq(env.lastTrigger("CnRPanelReply").text, "That car can't start a build")
end)

test("an engine swap is sent as one change with the parts that came with it", function()
  local env = bootClient({ jbeamParts = {
    pickup = { slots2 = { { name = "pickup_engine", description = "Engine" } } },
    v8 = { information = { name = "4.5L V8" }, slots2 = { { name = "pickup_intake", description = "Intake" } } },
    v8_60 = { information = { name = "6.0L V8" }, slots2 = { { name = "pickup_intake", description = "Intake" } } },
    intake_big = { information = { name = "Big Intake" } },
  } })
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.liveParts.pickup_engine = "v8_60"
  env.liveParts.pickup_intake = "intake_big"
  env.tick(1.2)
  local sent = env.lastSent("cnr_change")
  assertEq(#sent.changes, 1)
  assertEq(sent.changes[1].label, "Engine"); assertEq(sent.changes[1].to, "6.0L V8"); assertEq(sent.changes[1].extra, 1)
end)

test("during a round no menu can change a cop's parts or paint", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  core_vehicle_partmgmt.setNewParts({})
  core_vehicle_partmgmt.setConfigVars({})
  core_vehicle_colors.setVehiclePaint({})
  assertEq(#env.edits, 0)
  env.tick(0.2)
  assertEq(env.hud().notices[1].text, "Parts and paint are locked during a round. Use Settings for your car colour")
  assertEq(#env.toasts, 0)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  core_vehicle_partmgmt.setNewParts({})
  assertEq(#env.edits, 1)
end)

test("the evolving runner may change parts and tuning in prep, but not paint, and nothing after apply", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  core_vehicle_partmgmt.setNewParts({})
  core_vehicle_partmgmt.setConfigVars({})
  assertEq(#env.edits, 2)
  core_vehicle_partmgmt.setConfigPaints({})
  core_vehicle_colors.setVehicleColor({})
  assertEq(#env.edits, 2)
  env.fire("cnr_rebuild", { model = "pickup", config = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = {} } })
  core_vehicle_partmgmt.setNewParts({})
  assertEq(#env.edits, 2)
end)

test("changing one tuning value shows only that value, with rounded numbers", function()
  local env = bootClient()
  env.liveVars = { ["$gear_1"] = { val = 3.1, step = 0.01 }, ["$arb_F"] = { val = 40000, step = 100 } }
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.liveVars["$arb_F"].val = 40000.0000001
  env.liveVars["$gear_1"].val = 3.4500000001
  env.tick(1.2)
  local sent = env.lastSent("cnr_change")
  assertEq(#sent.changes, 1)
  assertEq(sent.changes[1].label, "Gear 1"); assertEq(sent.changes[1].from, "3.1"); assertEq(sent.changes[1].to, "3.45")
end)

test("a player who joins while applying or ready is frozen and sees the prep line", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.phase = "ready"
  setup.evolving = true
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  local frozen = false
  for _, c in ipairs(env.veh.commands) do if c == "controller.setFreeze(1)" then frozen = true end end
  assertEq(frozen, true)
  assertEq(env.hud().center.role, "cop"); assertEq(env.hud().mode, "round")
end)

test("cars ready clears the queued change and closes the parts menu", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.fire("cnr_queued", { runner = "Reinder", changes = { { label = "Engine", from = "a", to = "b" } } })
  env.fire("cnr_applied", {})
  env.tick(0.2)
  assertEq(env.hud().change, nil)
  assertEq(env.actionFilter.cnr_parts, true)
end)

test("only the tuning value that really changed shows, with the game's title", function()
  local env = bootClient()
  env.liveVars = {
    ["$brakestrength"] = { val = 1, step = 0.01, title = "Brake Force" },
    ["$camber_FR"] = { val = 1.002, step = 0.001, title = "Camber Front" },
    ["$caster_FR"] = { val = 1, step = 0.01 },
  }
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.liveVars["$brakestrength"].val = 0.6
  env.liveVars["$camber_FR"].val = 1.0020000004
  env.tick(1.2)
  local sent = env.lastSent("cnr_change")
  assertEq(#sent.changes, 1)
  assertEq(sent.changes[1].label, "Brake Force"); assertEq(sent.changes[1].from, "1"); assertEq(sent.changes[1].to, "0.6")
end)

local MODES_FILE = "/settings/cnr_vehicle_modes.json"

local function hasCommand(env, text, from)
  for i = from or 1, #env.veh.commands do
    if env.veh.commands[i]:find(text, 1, true) then return true end
  end
  return false
end

test("your traction control and drive mode are noted during a round, not right after a new car", function()
  local env = bootClient()
  startCop(env)
  local mark = #env.veh.commands + 1
  env.tick(1)
  assertEq(hasCommand(env, "copsAndRobbers.vehicleModes", mark), false)
  env.tick(4)
  assertEq(hasCommand(env, "copsAndRobbers.vehicleModes", mark), true)
end)

test("noted modes are saved and put back on the next car", function()
  local env = bootClient()
  startCop(env)
  env.M.vehicleModes({ controller = { escConfigKey = "off", driveModesActiveMode = "sport" }, powertrain = { rearDiffMode = "locked" } })
  assertEq(env.written[MODES_FILE].byModel.pickup.controller.escConfigKey, "off")
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  local mark = #env.veh.commands + 1
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  assertEq(hasCommand(env, "setState", mark), true)
  assertEq(hasCommand(env, '"off"', mark), true)
  assertEq(hasCommand(env, '"sport"', mark), true)
  assertEq(hasCommand(env, '"locked"', mark), true)
end)

test("doors, bonnet and boot are never carried over to the next car", function()
  local env = bootClient()
  startCop(env)
  env.M.vehicleModes({ controller = { escMode = "off", doorFL_coupler_groupState = "detached", hood_latch_groupState = "broken" } })
  local saved = env.written[MODES_FILE].byModel.pickup.controller
  assertEq(saved.escMode, "off"); assertEq(saved.doorFL_coupler_groupState, nil); assertEq(saved.hood_latch_groupState, nil)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  local mark = #env.veh.commands + 1
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  assertEq(hasCommand(env, '"off"', mark), true)
  assertEq(hasCommand(env, "groupState", mark), false)
end)

test("only driver settings are carried over, never physical state", function()
  local env = bootClient()
  startCop(env)
  env.M.vehicleModes({
    controller = {
      escConfigKey = "off", driveModesActiveMode = "sport", controlModes_modeIndex = 2, grb_bhv = "arcade", grb_mde = "S",
      axleLiftMode = "up", liftAxleControl_mode = "auto", compressionBrakeCoef = 0.5, compressionBrakeLevelIndex = 2,
      retarder_settingIndex = 1, pumpBrake_hillAssistCoef = 0.3, twoStep_enabled = true, twoStep_rpm = 4000,
      antilag_mode = "on", autoLevel_front_targetLength = 0.2, lightbar_modeIndex = 1,
      frzn = true, grb_idx = 4, postCrashBrake_state = "braking", postCrashBrake_crashCounter = 3, transbrakeActive = true,
      jato_fuel = 10, jato_fuelCoef = 1, nitrousPurgeTimeRemaining = 2, hydraulicSuspension_FL_currentPosition = 0.4,
      tirePressureControlActivePressureChange = -1, tirePressureControlFLPressure = 20, doorFL_coupler_groupState = "detached",
    },
    powertrain = { rearDiffMode = "locked", rangeboxMode = "low", pump_accumulatorOilVolume = 3 },
  })
  local saved = env.written[MODES_FILE].byModel.pickup
  for _, k in ipairs({ "escConfigKey", "driveModesActiveMode", "controlModes_modeIndex", "grb_bhv", "grb_mde", "axleLiftMode",
    "liftAxleControl_mode", "compressionBrakeCoef", "compressionBrakeLevelIndex", "retarder_settingIndex", "pumpBrake_hillAssistCoef",
    "twoStep_enabled", "twoStep_rpm", "antilag_mode", "autoLevel_front_targetLength", "lightbar_modeIndex" }) do
    assertEq(saved.controller[k] ~= nil, true, k)
  end
  for _, k in ipairs({ "frzn", "grb_idx", "postCrashBrake_state", "postCrashBrake_crashCounter", "transbrakeActive", "jato_fuel",
    "jato_fuelCoef", "nitrousPurgeTimeRemaining", "hydraulicSuspension_FL_currentPosition", "tirePressureControlActivePressureChange",
    "tirePressureControlFLPressure", "doorFL_coupler_groupState" }) do
    assertEq(saved.controller[k], nil, k)
  end
  assertEq(saved.powertrain.rearDiffMode, "locked"); assertEq(saved.powertrain.rangeboxMode, "low")
  assertEq(saved.powertrain.pump_accumulatorOilVolume, nil)
end)

test("a frozen state in the saved file never freezes the next car", function()
  local env = bootClient({ files = { [MODES_FILE] = { byModel = { pickup = { controller = { escConfigKey = "off", frzn = true } } } } } })
  local mark = #env.veh.commands + 1
  startCop(env)
  assertEq(hasCommand(env, '"off"', mark), true)
  assertEq(hasCommand(env, "frzn", mark), false)
end)

test("door states already in the saved file are not put back", function()
  local env = bootClient({ files = { [MODES_FILE] = { byModel = { pickup = { controller = { escMode = "off", doorRL_coupler_groupState = "detached" } } } } } })
  local mark = #env.veh.commands + 1
  startCop(env)
  assertEq(hasCommand(env, '"off"', mark), true)
  assertEq(hasCommand(env, "groupState", mark), false)
end)

test("saved modes from an earlier session are used", function()
  local env = bootClient({ files = { [MODES_FILE] = { byModel = { pickup = { controller = { escMode = "off" } } } } } })
  local mark = #env.veh.commands + 1
  startCop(env)
  assertEq(hasCommand(env, '"off"', mark), true)
end)

test("the runner gets an Apply button on his own change line, cops don't", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(2)
  env.fire("cnr_queued", { runner = "Reinder", changes = {} })
  env.tick(0.2)
  assertEq(env.hud().change.canApply, true)
  assertEq(env.hud().change.title, "Your change"); assertEq(env.hud().change.count, 0)
  env.M.applyChange()
  assertEq(env.lastSent("cnr_panel").action, "apply")
  local cop = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  cop.fire("cnr_roundSetup", setup)
  cop.fire("cnr_queued", { runner = "Bob", changes = {} })
  cop.tick(0.2)
  assertEq(cop.hud().change.canApply, nil)
end)

test("in evolving prep the prep line says what's next, then waiting for GO", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(EVOLVING_RUNNER))
  env.tick(0.2)
  assertEq(env.hud().prep.waiting, "Make your change, then press Apply")
  env.fire("cnr_applied", {})
  env.tick(0.2)
  assertEq(env.hud().prep.waiting, "Waiting for the host to press GO")
  local cop = bootClient()
  cop.mpPlayers[2] = { name = "Bob" }
  local setup = copy(SETUP)
  setup.evolving = true
  cop.fire("cnr_roundSetup", setup)
  cop.tick(0.2)
  assertEq(cop.hud().prep.waiting, "Waiting for Bob's change")
  local plain = bootClient()
  plain.fire("cnr_roundSetup", copy(SETUP))
  plain.tick(0.2)
  assertEq(plain.hud().prep.waiting, "Waiting for the host to press GO")
end)

test("the runner reads HIDDEN from the start of the chase when sight is on", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep", sightMaxMeters = 400 })
  env.tick(1)
  env.fire("cnr_release", {})
  env.tick(0.2)
  assertEq(env.hud().status.tag, "HIDDEN")
end)

test("the queued change shows on the change card, not as an event", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.evolving = true
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  env.fire("cnr_queued", { runner = "Bob", changes = { { label = "Engine", from = "2.0L I4", to = "3.0L I6", extra = 12 } } })
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.change.title, "Bob's change"); assertEq(h.change.count, 1)
  assertEq(#h.notices, 0)
  assertEq(#env.toasts, 0)
end)

test("a repeated identical HUD event is refreshed, not stacked", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  core_vehicle_partmgmt.setNewParts({})
  core_vehicle_partmgmt.setNewParts({})
  env.tick(0.2)
  assertEq(#env.hud().notices, 1)
end)

test("a repeated notice keeps one line and turns yellow when the repeat is a warning", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(1)
  local hudfeed = require("copsAndRobbers/hudfeed")
  hudfeed.event("Bob is close", 1, "info")
  hudfeed.event("Bob is close", 1.1, "warn")
  env.tick(0.2)
  assertEq(#env.hud().notices, 1)
  assertEq(env.hud().notices[1].tone, "warn")
end)

test("a random new build skips cars that can't start a build", function()
  local env = bootClient({ configs = {
    { model_key = "pickup", key = "old", Configuration = "Old", Source = "BeamNG - Official", Type = "Car", pcFilename = "/vehicles/pickup/old.pc" },
    { model_key = "pickup", key = "base", Configuration = "Base", Source = "BeamNG - Official", Type = "Car", pcFilename = "/vehicles/pickup/base.pc" },
  }, files = {
    ["/vehicles/pickup/old.pc"] = { format = 4, partsTree = {} },
    ["/vehicles/pickup/base.pc"] = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = {} },
  } })
  for _ = 1, 5 do
    env.sent = {}
    env.M.newBuild({ random = true })
    assertEq(env.lastSent("cnr_panel").parts.pickup_engine, "v8")
  end
end)

local HELP_FILE = "settings/cnr_help_seen.json"
local RULES = {
  runnerCountdownSeconds = 3, headStartSeconds = 7, catchHoldSeconds = 7, catchRadiusMeters = 10, catchMaxSpeedKmh = 3,
  resetWaitSeconds = 7, copResetMinDistanceMeters = 1000, crashSpeedLossKmh = 50, crashPenaltySeconds = 10,
  sightMaxMeters = 400, helicopter = true, helicopterArrivalSeconds = 60, helicopterUpSeconds = 120, helicopterRefuelSeconds = 90, roundTimeLimitSeconds = 0, carMode = "random",
}

local function join(env)
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  env.fire("cnr_myColor", { hex = "#ff8800" })
  env.fire("cnr_rules", copy(RULES))
  env.fire("cnr_lobby", { online = 3, active = false })
end

local function countHidden(env)
  local n = 0
  for _, t in ipairs(env.triggers) do
    if t.name == "CnRHud" and t.data.visible == false then n = n + 1 end
  end
  return n
end

test("connected, the HUD shows the lobby card between rounds", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.visible, true); assertEq(h.mode, "lobby"); assertEq(h.driving, false)
  assertEq(h.lobby.online, 3); assertEq(h.lobby.status, "Waiting for the host to start a round")
  assertEq(h.lobby.color, "#ff8800")
  assertEq(h.lobby.apps.panel, false); assertEq(h.lobby.apps.board, false)
  env.fire("cnr_lobby", { online = 4, practice = "Bob", active = false })
  env.tick(0.2)
  assertEq(env.hud().lobby.status, "Practice round: Bob"); assertEq(env.hud().lobby.online, 4)
end)

test("not connected, nothing is pushed", function()
  local env = bootClient()
  env.tick(1)
  assertEq(env.hud(), nil)
end)

test("cnr_rules reach How to play while it is open", function()
  local env = bootClient()
  join(env)
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.help.open, true)
  assertEq(h.help.rules.headStartSeconds, 7); assertEq(h.help.rules.catchMaxSpeedKmh, 3)
  assertEq(h.help.rules.noLimit, true); assertEq(h.help.rules.sightOff, false)
  local changed = copy(RULES)
  changed.roundTimeLimitSeconds = 600
  env.fire("cnr_rules", changed)
  env.tick(0.2)
  assertEq(env.hud().help.rules.roundTimeLimitSeconds, 600); assertEq(env.hud().help.rules.noLimit, false)
  env.M.ui({ action = "help", open = false })
  assertEq(env.hud().help.open, false); assertEq(env.hud().help.rules, nil)
end)

test("first join opens How to play and Got it remembers", function()
  local env = bootClient()
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  env.tick(0.2)
  assertEq(env.hud().help.open, true)
  env.M.ui({ action = "help", open = false })
  assertEq(env.written[HELP_FILE].seen, true)
  assertEq(env.hud().help.open, false)
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  env.tick(0.2)
  assertEq(env.hud().help.open, false)
  local again = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  again.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  again.tick(0.2)
  assertEq(again.hud().help.open, false)
  again.M.ui({ action = "help", open = true })
  assertEq(again.hud().help.open, true)
end)

test("How to play opens and closes as its own app", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L, files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(4, 0.5)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  env.M.ui({ action = "help", open = true })
  assertPlacement(L, "copsAndRobbersHowToPlay", HOWTO_PLACEMENT)
  assertEq(env.hud().help.open, true)
  env.M.ui({ action = "help", open = true })
  env.tick(11, 0.5)
  assertEq(countApp(L, "copsAndRobbersHowToPlay"), 1)
  env.M.ui({ action = "help", open = false })
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  assertEq(env.hud().help.open, false)
  assertEq(env.written[HELP_FILE].seen, true)
  env.M.ui({ action = "help", open = false })
  env.tick(11, 0.5)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  assertEq(has(L, "copsAndRobbersHud"), true); assertEq(has(L, "copsAndRobbersAnnouncements"), true)
end)

test("a first join adds How to play to the layout along with the HUD", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  join(env)
  env.tick(4, 0.5)
  assertEq(env.hud().help.open, true)
  assertPlacement(L, "copsAndRobbersHowToPlay", HOWTO_PLACEMENT)
end)

local function withLeftoverHowTo()
  local L = fakeLayouts()
  table.insert(L.disk[L.name].apps, { appName = "copsAndRobbersHowToPlay" })
  local env = bootClient({ layouts = L, files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(4, 0.5)
  env.M.ui({ action = "help", open = true })
  assertEq(countApp(L, "copsAndRobbersHowToPlay"), 1)
  return L, env
end

test("a How to play left in the layout by an unclean exit is removed on leaving once opened", function()
  local L, env = withLeftoverHowTo()
  env.M.onBeamMPServerLeave()
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
end)

test("a How to play left in the layout by an unclean exit counts as closed when the player removes it", function()
  local L, env = withLeftoverHowTo()
  local kept = {}
  for _, a in ipairs(L.disk[L.name].apps) do
    if a.appName ~= "copsAndRobbersHowToPlay" then kept[#kept + 1] = a end
  end
  L.disk[L.name].apps = kept
  env.tick(11, 0.5)
  assertEq(env.hud().help.open, false)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
end)

test("How to play removed by the player counts as closed, without marking it seen", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  join(env)
  env.tick(4, 0.5)
  assertEq(has(L, "copsAndRobbersHowToPlay"), true)
  local kept = {}
  for _, a in ipairs(L.disk[L.name].apps) do
    if a.appName ~= "copsAndRobbersHowToPlay" then kept[#kept + 1] = a end
  end
  L.disk[L.name].apps = kept
  env.tick(11, 0.5)
  assertEq(env.hud().help.open, false)
  assertEq(has(L, "copsAndRobbersHowToPlay"), false)
  assertEq(env.written[HELP_FILE], nil)
  L.current = L.other
  env.M.onGameStateUpdate({})
  env.tick(1, 0.25)
  assertEq(#L.disk[L.other].apps, 2)
  L.current = L.name
  env.M.ui({ action = "help", open = true })
  assertEq(has(L, "copsAndRobbersHowToPlay"), true)
  assertEq(env.hud().help.open, true)
end)

test("the colour picker sends cnr_color and the server's answer sets your colour", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.M.ui({ action = "color", hex = "#00ff00" })
  assertEq(env.lastSent("cnr_color").hex, "#00ff00")
  env.M.ui({ action = "color" })
  assertEq(env.lastSent("cnr_color").hex, nil)
  env.fire("cnr_myColor", { hex = "#00ff00" })
  env.tick(0.2)
  assertEq(env.hud().lobby.color, "#00ff00")
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(0.2)
  assertEq(env.hud().prep.color, "#00ff00")
  env.fire("cnr_myColor", {})
  env.tick(0.2)
  assertEq(env.hud().prep.color, nil)
end)

test("a refused colour shows as a notice", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.fire("cnr_myColor", { hex = "#ff8800", error = "Use a colour like #ff8800" })
  env.tick(0.2)
  assertEq(env.hud().notices[1].text, "Use a colour like #ff8800"); assertEq(env.hud().notices[1].tone, "warn")
  assertEq(env.hud().lobby.color, "#ff8800")
end)

test("a mid-round joiner sees the round, not the lobby", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  env.fire("cnr_mode", { geo = false, version = CNR_VERSION })
  env.fire("cnr_myColor", { hex = "#ff8800" })
  env.fire("cnr_rules", copy(RULES))
  env.fire("cnr_lobby", { online = 4, active = true })
  env.tick(0.2)
  assertEq(env.hud().mode, "lobby"); assertEq(env.hud().lobby.status, "A round is running")
  local setup = copy(SETUP)
  setup.phase, setup.chaseElapsed = "running", 30
  env.fire("cnr_roundSetup", setup)
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.mode, "round"); assertEq(h.lobby, nil); assertEq(h.driving, true)
  assertEq(h.status.role, "cop"); assertEq(h.status.time, "0:30")
  assertEq(h.center, nil)
end)

test("a cop's prep names the runner and leaves the rules to How to play", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  env.mpPlayers[2] = { name = "Bob" }
  join(env)
  startCop(env)
  assertEq(env.hud().center.title, "YOU'RE A COP")
  assertEq(env.hud().center.runner, "Bob"); assertEq(env.hud().center.rule, nil)
end)

test("a cop's prep uses the runner name the server sends", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  env.mpPlayers[2] = { name = "Bobby" }
  join(env)
  local setup = copy(SETUP)
  setup.runnerName = "Bob"
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  assertEq(env.hud().center.runner, "Bob")
end)

test("the chase line shows the time limit when one is set", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  local limited = copy(RULES)
  limited.roundTimeLimitSeconds = 600
  env.fire("cnr_rules", limited)
  startCop(env)
  env.fire("cnr_release", {})
  env.tick(0.2)
  assertEq(env.hud().status.limit, "10:00")
end)

test("the runner's chase line counts down to the cops' release", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  env.tick(1)
  assertEq(env.hud().center.title, "YOU'RE THE RUNNER")
  env.fire("cnr_countdown", { seconds = 3 })
  env.tick(3)
  env.fire("cnr_runnerGo", { headStartSeconds = 7 })
  env.tick(0.2)
  local h = env.hud()
  assertEq(h.center.kind, "flash"); assertEq(h.center.text, "GO! RUN!")
  assertEq(h.status.role, "runner"); assertEq(h.status.time, "0:00"); assertEq(h.status.releaseIn, 7)
  env.tick(2.5)
  assertEq(env.hud().status.releaseIn, 5)
  env.fire("cnr_release", {})
  env.tick(1.2)
  assertEq(env.hud().status.releaseIn, nil); assertEq(env.hud().status.time, "0:01")
end)

test("a runner who rejoins in the head start sees the release countdown on the chase line", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "headstart", headStartRemaining = 4 })
  env.tick(0.2)
  assertEq(env.hud().center, nil)
  assertEq(env.hud().status.releaseIn, 4)
end)

test("hello pushes right away", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(0.2)
  env.triggers = {}
  env.M.ui({ action = "hello" })
  assertEq(env.hud().mode, "lobby")
end)

test("the lobby card's buttons open and close the leaderboard and host panel", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L, files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(4, 0.5)
  assertEq(env.hud().lobby.apps.board, false)
  env.M.ui({ action = "toggleApp", name = "board" })
  assertEq(has(L, "copsAndRobbersLeaderboard"), true)
  assertEq(env.hud().lobby.apps.board, true)
  env.M.ui({ action = "toggleApp", name = "panel" })
  assertEq(env.hud().lobby.apps.panel, true)
  env.M.ui({ action = "toggleApp", name = "board" })
  assertEq(env.hud().lobby.apps.board, false)
end)

test("Apply from the HUD sends the apply action", function()
  local env = bootClient()
  env.M.ui({ action = "apply" })
  assertEq(env.lastSent("cnr_panel").action, "apply")
end)

test("leaving the server hides the HUD with one push", function()
  local env = bootClient({ files = { [HELP_FILE] = { seen = true } } })
  join(env)
  env.tick(0.5)
  env.M.onBeamMPServerLeave()
  assertEq(env.hud().visible, false)
  env.tick(1)
  assertEq(countHidden(env), 1)
  env.M.ui({ action = "hello" })
  assertEq(countHidden(env), 1); assertEq(env.hud().visible, false)
end)

test("board gives cars to your best run and every round", function()
  local env = bootClient()
  env.fire("cnr_boardState", { filter = "all", runners = {}, cops = {}, players = {}, mine = { rank = 2, model = "pickup" }, rounds = { { id = 1, model = "pickup" }, { id = 2 } } })
  local b = env.lastTrigger("CnRBoard")
  assertEq(b.mine.car, "Gavril Pickup")
  assertEq(b.rounds[1].car, "Gavril Pickup")
  assertEq(b.rounds[2].car, nil)
end)

test("board names maps", function()
  local env = bootClient()
  env.fire("cnr_boardState", { map = "west_coast_usa", maps = { "beamng_earth", "gridmap_v2" }, filter = "east_coast_usa", runners = {}, rounds = { { id = 1, map = "utah" } } })
  local n = env.lastTrigger("CnRBoard").mapNames
  assertEq(n.west_coast_usa.pretty, "West Coast USA")
  assertEq(n.west_coast_usa.title, nil)
  assertEq(n.beamng_earth.pretty, "BeamNG.Earth")
  assertEq(n.gridmap_v2.pretty, "Gridmap V2")
  assertEq(n.east_coast_usa.pretty, "East Coast USA")
  assertEq(n.utah.pretty, "Utah")
  env.fire("cnr_boardState", { filter = "all", runners = {} })
  assertEq(next(env.lastTrigger("CnRBoard").mapNames), nil)
end)

test("board uses the level title when the game has one", function()
  local env = bootClient()
  _G.core_levels = { getLevelTitle = function(id) return "levels." .. id .. ".info.title" end }
  env.fire("cnr_boardState", { map = "west_coast_usa", runners = {} })
  _G.core_levels = nil
  local n = env.lastTrigger("CnRBoard").mapNames.west_coast_usa
  assertEq(n.title, "levels.west_coast_usa.info.title")
  assertEq(n.pretty, "West Coast USA")
end)

test("the panel gets the map name", function()
  local env = bootClient()
  env.fire("cnr_panelState", { map = "uk_motorway" })
  assertEq(env.lastTrigger("CnRPanel").mapName.pretty, "UK Motorway")
  env.fire("cnr_panelState", {})
  assertEq(env.lastTrigger("CnRPanel").mapName, nil)
end)

test("the panel gets names for the excluded cars", function()
  local env = bootClient()
  local getModel = core_vehicles.getModel
  core_vehicles.getModel = function(model)
    if model == "citybus" then return { model = { Name = "City Bus", Brand = "Wentward" } } end
    error("no such model")
  end
  env.fire("cnr_panelState", { settings = { excludedModels = { "citybus", "gone_mod" } } })
  core_vehicles.getModel = getModel
  local names = env.lastTrigger("CnRPanel").excludedNames
  assertEq(names.citybus, "Wentward City Bus")
  assertEq(names.gone_mod, "gone_mod")
  env.fire("cnr_panelState", { settings = { excludedModels = {} } })
  assertEq(next(env.lastTrigger("CnRPanel").excludedNames), nil)
  env.fire("cnr_panelState", { settings = { excludedModels = "citybus" } })
  assertEq(env.lastTrigger("CnRPanel").excludedNames, nil)
  env.fire("cnr_panelState", {})
  assertEq(env.lastTrigger("CnRPanel").excludedNames, nil)
end)

test("panel state gets the round car's name", function()
  local env = bootClient()
  env.fire("cnr_panelState", { phase = "prep", car = "pickup" })
  assertEq(env.lastTrigger("CnRPanel").carName, "Gavril Pickup")
  env.fire("cnr_panelState", { phase = "idle" })
  assertEq(env.lastTrigger("CnRPanel").carName, nil)
end)

test("station list gives the nearest three and whether one can be removed", function()
  local env = bootClient()
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_stationList", { geo = false, stations = { { x = 400, y = 0, z = 0 }, { x = 30, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }, { x = 200, y = 0, z = 0 } } })
  local s = env.lastTrigger("CnRStations")
  assertEq(s.count, 4); assertEq(#s.nearest, 3)
  assertEq(s.nearest[1].meters, 30); assertEq(s.nearest[3].meters, 200)
  assertEq(s.canRemove, true)
  env.fire("cnr_stationList", { stations = { { x = 51, y = 0, z = 0 } } })
  assertEq(env.lastTrigger("CnRStations").canRemove, false)
  env.fire("cnr_stationList", { stations = {} })
  s = env.lastTrigger("CnRStations")
  assertEq(s.count, 0); assertEq(#s.nearest, 0); assertEq(s.canRemove, false)
  env.fire("cnr_stationList", {})
  assertEq(env.lastTrigger("CnRStations").count, 0)
end)

test("station list with geo points converts them to game space", function()
  local env = bootClient()
  _G.beamngEarth_api = { version = function() return 1 end, toGame = function(lat, lon, h) return lon, lat, h end }
  env.veh.pos = vec3(0, 0, 0)
  env.fire("cnr_stationList", { geo = true, stations = { { lat = 20, lon = 0, name = "A" }, { lat = 0, lon = 40 }, { lat = "x" } } })
  _G.beamngEarth_api = nil
  local s = env.lastTrigger("CnRStations")
  assertEq(s.count, 3); assertEq(#s.nearest, 2)
  assertEq(s.nearest[1].meters, 20); assertEq(s.nearest[2].meters, 40)
  assertEq(s.canRemove, true)
end)

test("geo station distances ignore height and skip points that don't convert", function()
  local env = bootClient()
  _G.beamngEarth_api = {
    version = function() return 1 end,
    toGame = function(lat, lon, h) if lat == 99 then return nil end return lon, lat, h end,
  }
  env.veh.pos = vec3(0, 0, 300)
  env.fire("cnr_stationList", { geo = true, stations = { { lat = 0, lon = 10 }, { lat = 99, lon = 0 } } })
  _G.beamngEarth_api = nil
  local s = env.lastTrigger("CnRStations")
  assertEq(s.count, 2); assertEq(#s.nearest, 1)
  assertEq(s.nearest[1].meters, 10)
  assertEq(s.canRemove, true)
end)

test("station list without a car of your own has nothing nearby", function()
  local env = bootClient()
  _G.MPVehicleGE.isOwn = function() return false end
  env.fire("cnr_stationList", { stations = { { x = 1, y = 0, z = 0 } } })
  local s = env.lastTrigger("CnRStations")
  assertEq(s.count, 1); assertEq(#s.nearest, 0); assertEq(s.canRemove, false)
end)

test("a round sky is applied at setup and shown on the role card", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { time = "night", weather = "rain", driving = true, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(5)
  assertEq(env.sky.locked, true)
  assertEq(env.hud().center.car, "Gavril Pickup · Night · Rain")
end)

test("the role card shows the round's date", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { time = "night", weather = "rain", year = 2026, month = 12, day = 14, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  assertEq(env.hud().center.car, "Gavril Pickup · Night · Rain · 14 Dec · 3 to 5 °C")
end)

test("New sky updates the card and says so", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { weather = "rain", windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  env.fire("cnr_sky", { time = "noon", weather = "snow", year = 2026, month = 1, day = 3, windDir = 0, windSeed = 9 })
  env.tick(0.2)
  assertEq(env.hud().center.car, "Gavril Pickup · Noon · Snow · 3 Jan · -5 to -1 °C")
  env.tick(3.5)
  assertEq(env.sky.objects.cnr_precipitation:getField("dataBlock"), "Snow_menu")
  local found = false
  for _, n in ipairs(env.hud().notices) do if n.text == "New sky: Noon · Snow · 3 Jan · -5 to -1 °C" then found = true end end
  assertEq(found, true)
end)

test("a sky event with no round does nothing", function()
  local env = bootClient()
  env.fire("cnr_sky", { time = "noon", weather = "snow", windDir = 0, windSeed = 9 })
  env.tick(0.2)
  assertEq(env.sky.locked, false); assertEq(#env.sky.setStates, 0)
end)

test("the countdown starts the round clock", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { time = "sunset", daySeconds = 1440, windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  env.fire("cnr_countdown", { seconds = 3 })
  local s = env.sky.setStates[#env.sky.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
end)

test("a mid-chase setup starts the clock at clockSeconds", function()
  local env = bootClient()
  local d = copy(SETUP); d.phase = "running"; d.chaseElapsed = 100
  d.sky = { time = "sunset", daySeconds = 1440, clockSeconds = 110, windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d); env.tick(0.1)
  assertNear(env.sky.state.time, (0.245 + 110 / 1440) % 1, 1e-6)
end)

test("the round end gives the player's sky back, a map change only forgets it", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { weather = "storm", driving = true, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(5)
  assertEq(env.sky.locked, true)
  env.fire("cnr_roundEnd", { reason = "cancelled" })
  assertEq(env.sky.locked, false); assertEq(env.sky.state.cloudCover, 0.3)
  env.tick(5)
  env.fire("cnr_roundSetup", d); env.tick(5)
  local n = #env.sky.setStates
  assertEq(env.sky.locked, true)
  env.M.onClientEndMission()
  assertEq(#env.sky.setStates, n)
  assertEq(env.sky.locked, false)
end)

test("leaving the server mid-rain removes the rain at once", function()
  local env = bootClient()
  local d = copy(SETUP); d.sky = { weather = "rain", driving = true, windDir = 0, windSeed = 7 }
  env.fire("cnr_roundSetup", d); env.tick(1)
  assertEq(env.sky.objects.cnr_precipitation ~= nil, true)
  assertEq(env.sky.objects.cnr_rain_sound ~= nil, true)
  env.M.onBeamMPServerLeave()
  assertEq(env.sky.objects.cnr_precipitation, nil)
  assertEq(env.sky.objects.cnr_rain_sound, nil)
end)

test("practice AI cars turn their headlights on at night", function()
  local env = bootClient()
  local d = copy(SETUP); d.role = "runner"; d.runnerId = 1; d.inPlace = true
  d.sky = { time = "night", windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d)
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -1, role = "cop", index = 1, name = "AI cop 1" } } })
  env.tick(3)
  local cmds = table.concat(env.spawned[1].veh.commands, "\n")
  assertEq(cmds:find("electrics.setLightsState(1)", 1, true) ~= nil, true)
end)

test("practice AI headlights go off after sunrise and a day practice never turns them on", function()
  local env = bootClient()
  local d = copy(SETUP); d.role = "runner"; d.runnerId = 1; d.inPlace = true
  d.sky = { time = "night", windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d)
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -1, role = "cop", index = 1, name = "AI cop 1" } } })
  env.tick(3)
  local cmds = table.concat(env.spawned[1].veh.commands, "\n")
  assertEq(cmds:find("electrics.setLightsState(0)", 1, true), nil)
  env.sky.state.time = 0
  env.tick(3)
  cmds = table.concat(env.spawned[1].veh.commands, "\n")
  assertEq(cmds:find("electrics.setLightsState(0)", 1, true) ~= nil, true)
end)

test("a day practice never sends headlights", function()
  local env = bootClient()
  local d = copy(SETUP); d.role = "runner"; d.runnerId = 1; d.inPlace = true
  d.sky = { time = "noon", windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", d)
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -1, role = "cop", index = 1, name = "AI cop 1" } } })
  env.tick(3)
  local cmds = table.concat(env.spawned[1].veh.commands, "\n")
  assertEq(cmds:find("electrics.setLightsState(1)", 1, true), nil)
end)

test("leaderboard round rows get a sky label", function()
  local env = bootClient()
  env.fire("cnr_boardState", { rounds = { { id = 1, model = "pickup", sky = { time = "night", weather = "rain", month = 12, day = 14 } }, { id = 2, model = "pickup" } } })
  local d = env.lastTrigger("CnRBoard")
  assertEq(d.rounds[1].skyLabel, "Night · Rain"); assertEq(d.rounds[2].skyLabel, nil)
end)

local function trafficObjects(env)
  local list = {}
  for id in pairs(env.gameTraffic) do
    if env.objects[id] then list[#list + 1] = env.objects[id] end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function hasCommand(obj, cmd)
  for _, c in ipairs(obj.commands) do if c == cmd then return true end end
  return false
end

local function countEvents(env, text)
  local hf = package.loaded["copsAndRobbers/hudfeed"]
  local seen = { n = 0 }
  local real = hf.event
  hf.event = function(msg, ...)
    if msg == text then seen.n = seen.n + 1 end
    return real(msg, ...)
  end
  return seen
end

test("traffic spawns only on the server's go-ahead, without police", function()
  local env = bootClient()
  startCop(env)
  assertEq(#env.trafficSpawns, 0)
  env.fire("cnr_trafficStart", { count = 3 })
  assertEq(env.trafficSpawns[1].amount, 3)
  for _, entry in ipairs(env.trafficSpawns[1].group) do assertEq(entry.model, "pickup") end
  assertEq(env.trafficVars.enableRandomEvents, false)
  assertEq(env.trafficVars.aiMode, "traffic")
end)

test("traffic stands still until the runner's GO", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(1)
  local cars = trafficObjects(env)
  assertEq(#cars, 3)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "controller.setFreeze(1)"), true) end
  env.fire("cnr_runnerGo", { headStartSeconds = 7 })
  for _, obj in ipairs(cars) do
    assertEq(hasCommand(obj, "controller.setFreeze(0)"), true)
    obj.commands = {}
  end
  env.tick(2)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "controller.setFreeze(1)"), false) end
end)

test("traffic for a player who joins during the chase drives at once", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.phase = "running"
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(1)
  assertEq(env.trafficSpawns[1].amount, 3)
  local cars = trafficObjects(env)
  assertEq(#cars, 3)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "controller.setFreeze(1)"), false) end
end)

test("traffic is deleted at round end and on leaving, never when none was started", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_trafficStart", { count = 3 })
  local before = env.trafficDeletes
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  assertEq(env.trafficDeletes > before, true)
  assertEq(#trafficObjects(env), 0)
  local quiet = bootClient()
  startCop(quiet)
  quiet.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  quiet.tick(1)
  assertEq(quiet.trafficDeletes, 0)
  local leaving = bootClient()
  startCop(leaving)
  leaving.fire("cnr_trafficStart", { count = 3 })
  leaving.M.onBeamMPServerLeave()
  assertEq(#trafficObjects(leaving), 0)
end)

test("traffic that finishes spawning after the round is deleted too", function()
  local env = bootClient()
  startCop(env)
  env.deferTraffic = true
  env.fire("cnr_trafficStart", { count = 3 })
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  env.finishTraffic()
  assertEq(#trafficObjects(env), 3)
  env.tick(1)
  assertEq(#trafficObjects(env), 0)
end)

test("the game reports its traffic cars once per change", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(1.2)
  local cars = trafficObjects(env)
  local vids = env.lastSent("cnr_trafficCars").vids
  assertEq(#vids, 3)
  for i, obj in ipairs(cars) do assertEq(vids[i], obj.id) end
  local reports = 0
  for _, m in ipairs(env.sent) do if m.ev == "cnr_trafficCars" then reports = reports + 1 end end
  env.tick(2)
  local after = 0
  for _, m in ipairs(env.sent) do if m.ev == "cnr_trafficCars" then after = after + 1 end end
  assertEq(after, reports)
  cars[1]:delete()
  env.tick(1.2)
  assertEq(#env.lastSent("cnr_trafficCars").vids, 2)
end)

test("traffic cars have no name tags, players keep theirs", function()
  local env = bootClient()
  startCop(env)
  env.mpVehicles["1-100"] = { gameVehicleID = 100, isSpawned = true }
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.mpVehicles["2-5"] = { gameVehicleID = 305, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "1-100", "2-0" } })
  env.tick(0.2)
  assertEq(env.mpVehicles["2-5"].hideNametag, true)
  assertEq(env.mpVehicles["2-0"].hideNametag, nil)
  assertEq(env.mpVehicles["1-100"].hideNametag, nil)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  assertEq(env.mpVehicles["2-5"].hideNametag, nil)
end)

test("a cop loses the runner's name tag while the runner is not shown", function()
  local env = bootClient()
  startCop(env)
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "2-0" } })
  env.fire("cnr_runnerShown", { shown = false })
  env.tick(1.2)
  assertEq(env.mpVehicles["2-0"].hideNametag, true)
  env.fire("cnr_runnerShown", { shown = true })
  env.tick(1.2)
  assertEq(env.mpVehicles["2-0"].hideNametag, nil)
  env.fire("cnr_runnerShown", { shown = false })
  env.tick(1.2)
  assertEq(env.mpVehicles["2-0"].hideNametag, true)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  assertEq(env.mpVehicles["2-0"].hideNametag, nil)
end)

test("leaving the server shows the runner's name tag again", function()
  local env = bootClient()
  startCop(env)
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "2-0" } })
  env.fire("cnr_runnerShown", { shown = false })
  env.tick(1.2)
  assertEq(env.mpVehicles["2-0"].hideNametag, true)
  env.M.onBeamMPServerLeave()
  assertEq(env.mpVehicles["2-0"].hideNametag, nil)
end)

test("a runner never hides anything", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep", runnerShown = false })
  env.mpVehicles["1-0"] = { gameVehicleID = 100, isSpawned = true }
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "1-0", "2-0" } })
  env.fire("cnr_runnerShown", { shown = false })
  env.tick(1.2)
  assertEq(env.mpVehicles["1-0"].hideNametag, nil)
  assertEq(env.mpVehicles["2-0"].hideNametag, nil)
end)

test("a lobby player hides the tags on someone's practice traffic until it ends", function()
  local env = bootClient()
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.mpVehicles["2-5"] = { gameVehicleID = 305, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "2-0" } })
  env.tick(0.2)
  assertEq(env.mpVehicles["2-5"].hideNametag, true)
  env.fire("cnr_roundCars", { keys = {} })
  env.tick(0.2)
  assertEq(env.mpVehicles["2-5"].hideNametag, nil)
end)

local function noticeShown(env, text)
  for _, n in ipairs(env.hud().notices or {}) do
    if n.text:find(text, 1, true) then return true end
  end
  return false
end

test("an AI car that can't spawn gets a notice", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  core_vehicles.spawnNewVehicle = function() return nil end
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -10, role = "cop", name = "AI cop 1", index = 1 } } })
  env.tick(0.2)
  assertEq(noticeShown(env, "Could not spawn AI cop 1, is MaxCars high enough?"), true)
end)

test("a cop with no road near the runner is told they start where they are", function()
  local env = bootClient()
  _G.map = {
    getMap = function() return { nodes = {} } end,
    getGraphpath = function() return { graph = {} } end,
    findClosestRoad = function() return nil end,
  }
  startCop(env)
  assertEq(noticeShown(env, "No road found near the runner, you start where you are"), true)
end)

test("a car pick with no vehicles available gets a notice", function()
  local env = bootClient({ configs = {} })
  env.fire("cnr_roundSetup", copy(SETUP))
  env.fire("cnr_pickVehicle", { includeMods = false, excludedModels = {} })
  env.tick(0.2)
  assertEq(noticeShown(env, "No vehicles available to pick"), true)
  assertEq(env.lastSent("cnr_vehiclePicked"), nil)
end)

test("warnings keep their order: a new one goes last, an update keeps its place", function()
  bootClient()
  local hudfeed = require("copsAndRobbers/hudfeed")
  hudfeed.warning("binding", "bind reset")
  hudfeed.warning("version", "old copy")
  assertEq(hudfeed.warnings()[1], "bind reset"); assertEq(hudfeed.warnings()[2], "old copy")
  hudfeed.warning("binding", "bind reset now")
  assertEq(hudfeed.warnings()[1], "bind reset now")
  hudfeed.warning("binding", nil)
  hudfeed.warning("binding", "bind reset")
  assertEq(hudfeed.warnings()[1], "old copy"); assertEq(hudfeed.warnings()[2], "bind reset")
end)

test("traffic name tags are checked a few times a second, not every frame", function()
  local env = bootClient()
  env.mpVehicles["2-0"] = { gameVehicleID = 300, isSpawned = true }
  env.fire("cnr_roundCars", { keys = { "2-0" } })
  env.tick(0.02, 0.02)
  local calls = 0
  local original = MPVehicleGE.getVehicles
  MPVehicleGE.getVehicles = function() calls = calls + 1 return original() end
  env.tick(0.4, 0.02)
  MPVehicleGE.getVehicles = original
  assertEq(calls <= 2, true, "calls " .. calls)
  env.mpVehicles["2-6"] = { gameVehicleID = 306, isSpawned = true }
  env.tick(0.3, 0.02)
  assertEq(env.mpVehicles["2-6"].hideNametag, true)
end)

test("in bad weather traffic gets headlights and keeps them, in a clear round none from us", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.sky = { weather = "fog" }
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(1.2)
  local cars = trafficObjects(env)
  assertEq(#cars, 3)
  for _, obj in ipairs(cars) do
    assertEq(hasCommand(obj, "electrics.setLightsState(1)"), true)
    obj.commands = {}
  end
  env.tick(1.1)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "electrics.setLightsState(1)"), true) end
  local clear = bootClient()
  local calm = copy(SETUP)
  calm.sky = { weather = "clear" }
  clear.fire("cnr_roundSetup", calm)
  clear.tick(1)
  clear.fire("cnr_trafficStart", { count = 3 })
  clear.tick(2)
  local calmCars = trafficObjects(clear)
  assertEq(#calmCars, 3)
  for _, obj in ipairs(calmCars) do assertEq(hasCommand(obj, "electrics.setLightsState(1)"), false) end
  clear.fire("cnr_sky", { weather = "rain" })
  clear.tick(1.2)
  for _, obj in ipairs(calmCars) do assertEq(hasCommand(obj, "electrics.setLightsState(1)"), true) end
end)

test("a failed traffic spawn tells the player once", function()
  local env = bootClient()
  startCop(env)
  local failed = countEvents(env, "Traffic could not spawn")
  env.deferTraffic = true
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(16)
  assertEq(failed.n, 1)
  local some = bootClient()
  startCop(some)
  local partial = countEvents(some, "Only 2 of 3 traffic cars spawned")
  local spawn = gameplay_traffic.spawnTraffic
  gameplay_traffic.spawnTraffic = function(amount, group) return spawn(2, group) end
  some.fire("cnr_trafficStart", { count = 3 })
  some.tick(16)
  assertEq(partial.n, 1)
end)

test("held traffic is lit at night by the mod, and only while held", function()
  local env = bootClient()
  local setup = copy(SETUP)
  setup.sky = { time = "night", windDir = 0, windSeed = 1 }
  env.fire("cnr_roundSetup", setup)
  env.tick(1)
  env.fire("cnr_trafficStart", { count = 3 })
  env.tick(1.2)
  local cars = trafficObjects(env)
  assertEq(#cars, 3)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "electrics.setLightsState(1)"), true) end
  env.fire("cnr_runnerGo", { headStartSeconds = 7 })
  for _, obj in ipairs(cars) do obj.commands = {} end
  env.tick(2)
  for _, obj in ipairs(cars) do assertEq(hasCommand(obj, "electrics.setLightsState(1)"), false) end
end)

test("service vehicles never become traffic", function()
  bootClient()
  local traffic = require("copsAndRobbers/traffic")
  assertEq(traffic.civilian({ Source = "BeamNG - Official", ["Config Type"] = "Service", key = "22_security_late_A", Name = "Security (A)" }), false)
  assertEq(traffic.civilian({ Source = "BeamNG - Official", ["Config Type"] = "Service", key = "md_70_prisonbus", Name = "Prison Bus" }), false)
  assertEq(traffic.civilian({ Source = "BeamNG - Official", ["Config Type"] = "Factory", key = "d15_4wd_A", Name = "D15 4WD" }), true)
end)

test("starting or stopping traffic never deletes the player's own car", function()
  local env = bootClient()
  startCop(env)
  env.gameTraffic[env.veh.id] = { isAi = false }
  env.fire("cnr_trafficStart", { count = 3 })
  assertEq(env.objects[env.veh.id] ~= nil, true)
  env.gameTraffic[env.veh.id] = { isAi = false }
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  assertEq(env.objects[env.veh.id] ~= nil, true)
end)

test("a distance that rounds to 1000 m shows in km", function()
  bootClient()
  local units = require("copsAndRobbers/units")
  assertEq(units.distance(999.5), "1.0 km")
  assertEq(units.distance(999.4), "999 m")
  assertEq(units.distance(1000), "1.0 km")
end)

test("a setting from the card is saved and shown", function()
  local env = bootClient()
  env.fire("cnr_mode", {})
  env.M.ui({ action = "setting", key = "siren", value = true })
  env.tick(0.2)
  local saved = env.written["settings/cnr_settings.json"]
  assertEq(saved.siren, true); assertEq(saved.headlights, true)
  assertEq(env.hud().settings.siren, true); assertEq(env.hud().settings.sirensAllowed, true)
  env.written = {}
  env.M.ui({ action = "setting", key = "nope", value = true })
  assertEq(next(env.written), nil)
end)

test("saved settings load on start", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { headlights = true } } })
  env.fire("cnr_mode", {})
  env.tick(0.2)
  assertEq(env.hud().settings.headlights, true)
  assertEq(env.hud().settings.siren, false)
end)

test("the host's siren rule reaches the card", function()
  local env = bootClient()
  env.fire("cnr_mode", {})
  env.fire("cnr_rules", { sirensAllowed = false })
  env.tick(0.2)
  assertEq(env.hud().settings.sirensAllowed, false)
end)

local ownLights = require("copsAndRobbers/ownLights")
local SIREN2, SIREN1, SIREN0 = ownLights.SIREN_ON, ownLights.LIGHTS_ONLY, "electrics.set_lightbar_signal(0)"

test("the siren command falls back to lights only without a siren sound", function()
  assertEq(ownLights.SIREN_ON, "electrics.set_lightbar_signal((v.data.soundscape and v.data.soundscape.siren) and 2 or 1)")
  assertEq(ownLights.LIGHTS_ONLY, "electrics.set_lightbar_signal(1)")
end)

local function count(veh, cmd)
  local n = 0
  for _, c in ipairs(veh.commands) do if c == cmd then n = n + 1 end end
  return n
end

local function lightbarCommands(veh)
  local out = {}
  for _, c in ipairs(veh.commands) do if c:find("set_lightbar_signal", 1, true) then out[#out + 1] = c end end
  return out
end

local function skyRound(env, sky, role)
  local d = copy(SETUP)
  d.sky = sky
  if role then d.role = role end
  env.fire("cnr_roundSetup", d)
  env.tick(1)
end

local NIGHT = { time = "night", windDir = 0, windSeed = 1 }
local HEAD_ON = { files = { ["settings/cnr_settings.json"] = { headlights = true } } }
local SIREN_ON = { files = { ["settings/cnr_settings.json"] = { siren = true } } }

test("own headlights come on when the car is placed at night", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, NIGHT)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
end)

test("own headlights are not re-sent while nothing changes", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, NIGHT)
  env.tick(10)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_OFF), 0)
end)

test("a day round in rain lights the car, a clear day does not", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, { time = "noon", weather = "rain", windDir = 0, windSeed = 1 })
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  env = bootClient(HEAD_ON)
  skyRound(env, { time = "noon", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 0)
end)

test("sunrise turns own headlights off once", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, NIGHT)
  env.sky.state.time = 0
  env.tick(3)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_OFF), 1)
end)

test("New sky to rain by day turns own headlights on", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, { time = "noon", windDir = 0, windSeed = 1 })
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 0)
  env.fire("cnr_sky", { time = "noon", weather = "rain", windDir = 0, windSeed = 1 })
  env.tick(2)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
end)

test("a repaint at night lights the new car again", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, NIGHT)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  env.fire("cnr_paint", { color = { r = 1, g = 0, b = 0 } })
  env.tick(1)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 2)
end)

test("a player with no settings file gets auto headlights", function()
  local env = bootClient()
  skyRound(env, NIGHT)
  env.tick(5)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
end)

test("the headlights switch off never touches the lights", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { headlights = false } } })
  skyRound(env, NIGHT)
  env.tick(5)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 0)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_OFF), 0)
end)

test("a day change while the car is away lights it once the car is back", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, { time = "noon", windDir = 0, windSeed = 1 })
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 0)
  local veh = env.veh
  _G.getPlayerVehicle = function() return nil end
  env.sky.state.time = 0.5
  env.tick(3)
  _G.getPlayerVehicle = function() return veh end
  env.tick(2)
  assertEq(count(veh, ownLights.HEADLIGHTS_ON), 1)
end)

test("an evolving rebuild at night lights the new car again", function()
  local env = bootClient(HEAD_ON)
  local d = copy(EVOLVING_RUNNER)
  d.sky = NIGHT
  env.fire("cnr_roundSetup", d)
  env.tick(2)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  env.fire("cnr_rebuild", { model = "pickup", config = { format = 2, model = "pickup", parts = { pickup_engine = "v8_60" }, vars = {} } })
  env.tick(2)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 2)
end)

test("rain turning clear by day switches own headlights off once", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, { time = "noon", weather = "rain", windDir = 0, windSeed = 1 })
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  env.fire("cnr_sky", { time = "noon", weather = "clear", windDir = 0, windSeed = 1 })
  env.tick(2)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_OFF), 1)
end)

test("a non-boolean setting value is ignored", function()
  local env = bootClient()
  env.fire("cnr_mode", {})
  env.M.ui({ action = "setting", key = "siren", value = "yes" })
  env.tick(0.2)
  assertEq(env.written["settings/cnr_settings.json"], nil)
  assertEq(env.hud().settings.siren, false)
end)

test("switching Auto headlights on in prep at night lights the car once", function()
  local env = bootClient({ files = { ["settings/cnr_settings.json"] = { headlights = false } } })
  skyRound(env, NIGHT, "cop")
  env.tick(1)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 0)
  env.M.ui({ action = "setting", key = "headlights", value = true })
  env.tick(2)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
end)

test("switching headlights off in prep and round end send nothing", function()
  local env = bootClient(HEAD_ON)
  skyRound(env, NIGHT)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_ON), 1)
  env.M.ui({ action = "setting", key = "headlights", value = false })
  env.tick(2)
  env.fire("cnr_roundEnd", { reason = "cancelled", message = "Round cancelled" })
  env.tick(1)
  assertEq(count(env.veh, ownLights.HEADLIGHTS_OFF), 0)
end)

test("a cop's siren runs only after release", function()
  local env = bootClient(SIREN_ON)
  skyRound(env, nil)
  env.tick(3)
  assertEq(count(env.veh, SIREN2), 0)
  env.fire("cnr_release", {})
  env.tick(3)
  assertEq(count(env.veh, SIREN2) > 0, true)
  env.fire("cnr_roundEnd", { reason = "cancelled", message = "Round cancelled" })
  local bars = lightbarCommands(env.veh)
  assertEq(bars[#bars], SIREN0)
end)

test("the host's switch silences a cop and never touches the saved switch", function()
  local env = bootClient(SIREN_ON)
  env.fire("cnr_rules", { sirensAllowed = false })
  skyRound(env, nil)
  env.fire("cnr_release", {})
  env.tick(3)
  assertEq(count(env.veh, SIREN2), 0)
  assertEq(count(env.veh, SIREN1) > 0, true)
  assertEq(env.written["settings/cnr_settings.json"], nil)
  env.fire("cnr_rules", { sirensAllowed = true })
  env.tick(3)
  assertEq(count(env.veh, SIREN2) > 0, true)
end)

test("leaving a server forgets its siren ban", function()
  local env = bootClient(SIREN_ON)
  env.fire("cnr_rules", { sirensAllowed = false })
  env.M.onBeamMPServerLeave()
  skyRound(env, nil)
  env.fire("cnr_release", {})
  env.tick(3)
  assertEq(count(env.veh, SIREN2) > 0, true)
end)

test("a runner never gets light bar commands", function()
  local env = bootClient(SIREN_ON)
  skyRound(env, nil, "runner")
  env.fire("cnr_release", {})
  env.tick(3)
  assertEq(#lightbarCommands(env.veh), 0)
end)

test("geo.gpsInfo reports the road distance with a compass direction", function()
  local env = bootClient()
  local geo = require("copsAndRobbers/geo")
  _G.beamngEarth_api = {
    version = function() return 1 end,
    has = function() return true end,
    gpsSet = function() return true end,
    gpsClear = function() end,
    toGame = function(lat, lon, h) return lon, lat, h end,
    gps = function() return { remaining = 750 } end,
  }
  env.veh.pos = vec3(0, 0, 0)
  assertEq(geo.setGpsTarget({ lat = 100, lon = 0, h = 0 }), true)
  local info = geo.gpsInfo()
  geo.clearRoute()
  _G.beamngEarth_api = nil
  assertEq(info.before, "Runner"); assertEq(info.meters, 750); assertEq(info.after, "by road N")
end)

test("geo.gpsInfo falls back to the straight line while the route is planning", function()
  local env = bootClient()
  local geo = require("copsAndRobbers/geo")
  local planning = true
  _G.beamngEarth_api = {
    version = function() return 1 end,
    has = function() return true end,
    gpsSet = function() return true end,
    gpsClear = function() end,
    toGame = function(lat, lon, h) return lon, lat, h end,
    gps = function() return planning and { planning = true, remaining = 5 } or {} end,
  }
  env.veh.pos = vec3(0, 0, 0)
  assertEq(geo.setGpsTarget({ lat = 0, lon = 100, h = 0 }), true)
  local planned = geo.gpsInfo()
  planning = false
  local noRemaining = geo.gpsInfo()
  geo.clearRoute()
  _G.beamngEarth_api = nil
  assertEq(planned.meters, 100); assertEq(planned.after, "E")
  assertEq(noRemaining.meters, 100); assertEq(noRemaining.after, "E")
end)

local function syncCommands(veh)
  local out = {}
  for _, c in ipairs(veh.commands) do if c:find("MPElectricsGE.sendElectrics", 1, true) then out[#out + 1] = c end end
  return out
end

test("during a round the car's lights are sent to the other players again every 5 s", function()
  local env = bootClient()
  skyRound(env, NIGHT)
  local first = #syncCommands(env.veh)
  env.tick(10)
  local list = syncCommands(env.veh)
  assertEq(#list >= first + 2, true)
  assertEq(list[#list] ~= list[#list - 1], true)
  assertEq(load(list[#list]) ~= nil, true)
  env.fire("cnr_roundEnd", { reason = "called", runnerName = "Bob", survivedSeconds = 30, runnerId = 2 })
  local after = #syncCommands(env.veh)
  env.tick(10)
  assertEq(#syncCommands(env.veh), after)
end)

test("practice AI cars get their lights sent to the other players too", function()
  local env = bootClient()
  local d = copy(SETUP); d.role = "runner"; d.runnerId = 1; d.inPlace = true
  d.sky = NIGHT
  env.fire("cnr_roundSetup", d)
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -1, role = "cop", index = 1, name = "AI cop 1" } } })
  env.tick(12)
  assertEq(#syncCommands(env.spawned[1].veh) >= 1, true)
end)

test("a car that never appears doesn't break the client's update", function()
  local env = bootClient()
  local car = env.veh
  env.veh = nil
  env.fire("cnr_roundSetup", copy(SETUP))
  env.tick(6)
  env.veh = car
  local ok, err = pcall(env.tick, 3)
  assertEq(ok, true, tostring(err))
end)

test("the runner reports cover after release, a cop does not", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  env.tick(1)
  env.fire("cnr_release", {})
  env.tick(0.5)
  assertEq(env.lastSent("cnr_cover").covered, false)
  local cop = bootClient()
  startCop(cop)
  cop.fire("cnr_release", {})
  cop.tick(1)
  assertEq(cop.lastSent("cnr_cover"), nil)
end)
