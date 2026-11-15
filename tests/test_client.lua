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
  assertEq(h.visible, true)
  assertEq(h.prep.role, "COP"); assertEq(h.prep.car, "Gavril Pickup")
end)

test("countdown, runner go and release drive the banner and status", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_countdown", { seconds = 3 })
  env.tick(0.2)
  assertEq(env.hud().banner.label, "RUNNER STARTS IN")
  assertEq(env.hud().prep, nil)
  env.fire("cnr_runnerGo", { headStartSeconds = 7 })
  env.tick(0.2)
  assertEq(env.hud().banner.label, "COPS RELEASED IN")
  env.fire("cnr_release", {})
  env.tick(0.2)
  assertEq(env.hud().banner.label, "GO!")
  env.tick(3)
  assertEq(env.hud().status.role, "COP")
  assertEq(env.hud().status.time, "0:03")
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
  env.fire("cnr_setupAI", { model = "pickup", config = "vehicles/pickup/base.pc", runnerId = 1, ai = { { id = -10, role = "cop", name = "AI green", index = 1 } } })
  env.tick(1)
  assertEq(#env.spawned, 1)
  env.fire("cnr_release", {})
  env.fire("cnr_notice", { msg = "AI green: crash penalty 10s", about = -10 })
  env.fire("cnr_penalty", { aiId = -10, seconds = 10 })
  env.tick(0.2)
  assertEq(#env.hud().events, 1)
end)

test("the result card shows the top 3, and leaving the server clears it", function()
  local env = bootClient()
  startCop(env)
  env.fire("cnr_roundEnd", { reason = "caught", runnerName = "Bob", survivedSeconds = 75, catchers = { "Reinder" }, runnerId = 2 })
  env.fire("cnr_top", { lines = { "1. Bob 1:15" } })
  env.tick(0.2)
  assertEq(env.hud().result.title, "RUNNER CAUGHT")
  assertEq(env.hud().result.top[1], "1. Bob 1:15")
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

test("the HUD is placed centred in em units and checked less often once placed", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  env.tick(4, 0.5)
  assertEq(#L.added, 1)
  assertEq(L.added[1].left, "50%")
  assertEq(L.added[1].margin, nil)
  assertEq(L.added[1].width, "32.5em")
  local before = env.reads[L.name]
  env.tick(20, 0.5)
  assertEq(env.reads[L.name] - before <= 3, true)
end)

test("a layout switch is picked up right away, not after the slow check", function()
  local L = fakeLayouts()
  local env = bootClient({ layouts = L })
  env.tick(4, 0.5)
  assertEq(#L.added, 1)
  L.current = L.other
  env.M.onGameStateUpdate({})
  env.tick(1, 0.25)
  assertEq(#L.added, 2)
  assertEq(#L.disk[L.other].apps, 1)
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
  assertEq(env.hud().status.info, "IN SIGHT")
  env.fire("cnr_lastSeen", { live = true, route = true, pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.info, "Runner 640 m N · live")
  env.fire("cnr_lastSeen", { pos = { x = 0, y = 640, z = 0 } })
  env.tick(0.2)
  assertEq(env.hud().status.info, "Runner seen 640 m N")
end)

test("the runner sees SPOTTED or HIDDEN with the nearest cop", function()
  local env = bootClient()
  env.fire("cnr_roundSetup", { role = "runner", runnerId = 1, model = "pickup", config = "vehicles/pickup/base.pc", phase = "prep" })
  env.tick(1)
  env.fire("cnr_release", {})
  env.fire("cnr_nearestCop", { dist = 1200 })
  env.fire("cnr_spotted", { spotted = true })
  env.tick(0.2)
  assertEq(env.hud().status.info, "SPOTTED · Nearest cop 1.2 km")
  env.fire("cnr_spotted", { spotted = false })
  env.tick(0.2)
  assertEq(env.hud().status.info, "HIDDEN · Nearest cop 1.2 km")
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

test("sight follows the car the runner is driving, not a parked one", function()
  local env = bootClient()
  copInChase(env)
  env.addObject(301, vec3(0, 900, 0))
  env.mpVehicles["2-1"] = { gameVehicleID = 301, isSpawned = true }
  env.mpPlayers[2] = { activeVehicleID = "2-1" }
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
  env.mpPlayers[2] = { activeVehicleID = "2-0" }
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, true)
end)

test("sight needs a clear ray in both directions", function()
  local env = bootClient()
  copInChase(env)
  env.blockFrom = vec3(0, 101, 0)
  env.tick(0.3)
  assertEq(env.lastSent("cnr_sight").seen, false)
end)
