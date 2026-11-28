dofile("tests/server_boot.lua")
local boot, encode = serverBoot.boot, serverBoot.encode

test("main registers events and timer", function()
  local env = boot()
  assertEq(env.events.cnr_vehiclePicked ~= nil, true)
  assertEq(env.timers.cnr_tick, 250)
  env.cleanup()
end)

test("plugin dir resolves without @ chunk name, so config.json is read", function()
  local env = boot({ config = '{"headStartSeconds": 3}' })
  env.call("cnr_panel", 1, '{"action":"open"}')
  assertEq(env.lastSent("cnr_panelState").data:find('"headStartSeconds":3', 1, true) ~= nil, true)
  env.cleanup()
end)

test("server startup logs the name of the preserved corrupt config.json", function()
  local date = os.date
  os.date = function(format, ...)
    if format == "%Y%m%d-%H%M%S" then return "20261128-101500" end
    return date(format, ...)
  end
  local ok, env = pcall(boot, { config = '{"headStartSeconds": 3,}' })
  os.date = date
  assert(ok, env)
  local name = "config.json.corrupt-20261128-101500"
  local logged = env.logHas("config.json is not valid JSON, using defaults; kept a copy as " .. name)
  local exists = FS.Exists(env.dir .. name)
  env.cleanup()
  assertEq(logged, true)
  assertEq(exists, true)
end)

test("plugin load unlocks any client left in a round", function()
  local env = boot()
  local e = env.lastSent("cnr_roundEnd")
  assertEq(e ~= nil, true)
  assertEq(e.pid, -1)
  assertEq(e.data:find('"reason":"cancelled"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a vehicle pick that times out tells the host why", function()
  local env = boot()
  env.panel(2, "start rein")
  env.sent = {}
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local notice
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_notice" and m.data:find("Vehicle pick timed out", 1, true) then notice = m end
  end
  assertEq(notice ~= nil and (notice.pid == -1 or notice.pid == 2), true)
  local e = decodeJson(env.lastSent("cnr_roundEnd").data)
  assertEq(e.reason, "cancelled"); assertEq(e.message, "Vehicle pick timed out")
  env.cleanup()
end)

test("the mod leaves chat messages to BeamMP", function()
  local env = boot()
  assertEq(env.events.onChatMessage, nil)
  env.cleanup()
end)

test("full round over main wiring", function()
  local env = boot()
  env.startRound()
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  local setup = env.lastSent("cnr_roundSetup")
  assertEq(setup.data:find('"runnerId":1', 1, true) ~= nil, true)
  assertEq(env.call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}'), 1)
  env.go()
  assertEq(env.lastSent("cnr_countdown") ~= nil, true)
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_runnerGo") ~= nil, true)
  assertEq(env.lastSent("cnr_release") ~= nil, true)
  assertEq(env.caught(), true)
  assertEq(Util.JsonDecode(env.lastSent("cnr_roundEnd").data).catchers[1], "Bob")
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("the mod never writes to chat over a full round", function()
  local env = boot()
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}'), 1)
  env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.caught(), true)
  assertEq(#env.chats, 0)
  env.cleanup()
end)

test("a refused car is a warning notice", function()
  local env = boot()
  env.startRound()
  env.call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}')
  assertEq(env.noticeHas("Only the round car is allowed", "warn"), true)
  env.cleanup()
end)

test("edit in real pid-vid format with the registered round car is allowed", function()
  local env = boot()
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"a":"b"}},"pro":"0"}'), 0)
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"etk800","vcf":{"parts":{}}}'), 1)
  env.cleanup()
end)

local BASE_EDIT = '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"engine":"v8"}}}'
local TUNED_EDIT = '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"engine":"v12"}}}'

local function placed(env, pid)
  env.call("cnr_myVehicle", pid or 1, '{"vid":0}')
  env.clock = env.clock + 4
end

local function partsLines(env)
  local n = 0
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_notice" and decodeJson(m.data).msg:find("changed parts", 1, true) then n = n + 1 end
  end
  return n
end

test("a parts change during a round is announced to everyone once and never replaces the car", function()
  local env = boot()
  env.startRound()
  placed(env)
  env.call("onVehicleEdited", 1, 0, BASE_EDIT)
  env.sent = {}
  for _ = 1, 10 do
    assertEq(env.call("onVehicleEdited", 1, 0, TUNED_EDIT), 0)
    assertEq(env.call("onVehicleEdited", 1, 0, BASE_EDIT), 0)
  end
  assertEq(env.lastSent("cnr_restoreConfig"), nil)
  assertEq(env.noticeHas("⚠ Reinder changed parts during the round: engine", "warn"), true)
  assertEq(partsLines(env), 1)
  env.cleanup()
end)

test("parts reports right after the mod places a car are never announced", function()
  local env = boot()
  env.startRound()
  env.call("onVehicleEdited", 1, 0, BASE_EDIT)
  env.call("onVehicleEdited", 1, 0, TUNED_EDIT)
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  env.clock = env.clock + 2
  env.call("onVehicleEdited", 1, 0, BASE_EDIT)
  assertEq(partsLines(env), 0)
  env.clock = env.clock + 2
  env.call("onVehicleEdited", 1, 0, TUNED_EDIT)
  assertEq(partsLines(env), 1)
  env.cleanup()
end)

test("spawn in real roles:name:pid-vid format is parsed", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 2, 0, 'USER:Bob:2-0:{"jbm":"pickup","vcf":{"partConfigFilename":"/vehicles/pickup/base.pc"}}'), 0)
  env.cleanup()
end)

test("registering a round car leaves owner-classified traffic and parked cars intact", function()
  local env = boot({ vehicles = { [1] = { [0] = "x", [1] = "y", [2] = "z" }, [2] = { [0] = "x" } } })
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":1}')
  assertEq(#env.removed, 0)
  env.cleanup()
end)

test("reset of a non-active vehicle is ignored", function()
  local env = boot({ vehicles = { [1] = { [0] = "x", [1] = "y" }, [2] = { [0] = "x" } } })
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":1}')
  env.go()
  for _ = 1, 34 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("onVehicleReset", 1, 0, "")
  assertEq(env.noticeHas("reset illegally"), false)
  env.call("onVehicleReset", 1, 1, "")
  assertEq(env.noticeHas("Reinder reset illegally", "warn"), true)
  env.cleanup()
end)

test("stop while idle replies and still unlocks clients", function()
  local env = boot()
  env.sent = {}
  env.panel(1, "stop")
  assertEq(env.replyHas("No round running"), true)
  assertEq(env.lastSent("cnr_roundEnd") ~= nil, true)
  env.cleanup()
end)

test("/cnr test runner: AI vehicles are tracked as cops", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 1)
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.lastSent("cnr_roundSetup").data:find('"role":"runner"', 1, true) ~= nil, true)
  assertEq(env.lastSent("cnr_roundSetup").data:find('"hex":"#d83a2c"', 1, true) ~= nil, true)
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(env.lastSent("cnr_setupAI").pid, 1)
  assertEq(env.call("onVehicleSpawn", 1, 1, 'USER:Reinder:1-1:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'), 0)
  env.vehicles[1][1] = "y"
  assertEq(#env.removed, 0)
  env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":1}]}')
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 1 and vid == 1 then return { pos = { 5, 0, 0 }, vel = { 0, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_roundEnd").data:find('"reason":"caught"', 1, true) ~= nil, true)
  for _, m in ipairs(env.sent) do assertEq(m.pid >= -1, true) end
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f, nil)
  env.cleanup()
end)

test("penalty is shown on everyone's screen", function()
  local env = boot()
  env.startRound()
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 then return { pos = { 200, 0, 0 }, vel = { 120 / 3.6, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 then return { pos = { 201, 0, 0 }, vel = { 0, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  local n = env.lastSent("cnr_notice")
  assertEq(n.pid, -1)
  assertEq(n.data:find('"msg":"Bob: crash penalty 10s"', 1, true) ~= nil, true)
  assertEq(n.data:find('"tone":"warn"', 1, true) ~= nil, true)
  assertEq(n.data:find('"about":2', 1, true) ~= nil, true)
  env.cleanup()
end)

local function confirmDrivers(env, count)
  for pid = 1, count do env.call("cnr_myVehicle", pid, '{"vid":0}') end
end

local function runToChase(env, reportUncovered)
  env.startRound()
  confirmDrivers(env, 2)
  env.go()
  for i = 1, 44 do
    env.clock = env.clock + 0.25; env.positions[2] = 900; env.call("cnr_tick")
    if reportUncovered and i == 20 then env.call("cnr_cover", 1, '{"covered":false}') end
  end
end

test("test round events reach only the issuer", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.sent = {}
  env.panel(1, "test cop")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 50 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "stop")
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_parkBystanderCars" then
      assertEq(m.pid, 2)
    elseif m.ev ~= "cnr_lobby" or m.pid ~= -1 then
      assertEq(m.pid, 1, m.ev)
    end
  end
  env.cleanup()
end)

test("/cnr start cancels a running test round", function()
  local env = boot()
  env.panel(1, "test cop")
  env.panel(2, "start bob")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  env.cleanup()
end)

test("/cnr end records the run", function()
  local env = boot()
  runToChase(env)
  env.panel(2, "end")
  assertEq(Util.JsonDecode(env.lastSent("cnr_roundEnd").data).reason, "called")
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("/cnr start next and again", function()
  local env = boot()
  env.panel(1, "start next")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local first = decodeJson(env.lastSent("cnr_roundSetup").data).runnerId
  env.panel(1, "stop")
  env.panel(1, "start next")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).runnerId, 3 - first)
  env.panel(1, "stop")
  env.panel(1, "start again")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).runnerId, 3 - first)
  env.cleanup()
end)

test("losing sight pings the cops once with the runner's XYZ position", function()
  local env = boot({ config = '{"helicopter": false}' })
  runToChase(env)
  env.positions[2] = 50
  for _ = 1, 4 do env.clock = env.clock + 0.25; env.call("cnr_sight", 2, '{"seen":true}'); env.call("cnr_tick") end
  env.sent = {}
  env.vidPositions["1-0"] = { pos = { 6, 8, 12 }, vel = { 0, 0, 0 } }
  env.call("cnr_sight", 2, '{"seen":false}')
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local count = 0
  for _, m in ipairs(env.sent) do if m.ev == "cnr_lastSeen" and m.data:find('"live"', 1, true) == nil then count = count + 1 end end
  assertEq(count, 1)
  local seen = env.lastSent("cnr_lastSeen")
  assertEq(seen.pid, 2)
  local ping = decodeJson(seen.data)
  assertEq(ping.pos.x, 6); assertEq(ping.pos.y, 8); assertEq(ping.pos.z, 12)
  assertEq(ping.live, nil); assertEq(ping.route, nil)
  env.cleanup()
end)

test("the runner gets cnr_nearestCop every 30 s", function()
  local env = boot({ config = '{"helicopter": false}' })
  runToChase(env)
  env.sent = {}
  for _ = 1, 130 do env.clock = env.clock + 0.25; env.positions[2] = 900; env.call("cnr_tick") end
  local count = 0
  for _, m in ipairs(env.sent) do if m.ev == "cnr_nearestCop" then count = count + 1; assertEq(m.pid, 1) end end
  assertEq(count, 1)
  env.cleanup()
end)

test("heli phases reach every player", function()
  local env = boot({ config = '{"helicopterArrivalSeconds": 0, "weather": "clear"}' })
  runToChase(env, true)
  local delivered = { [1] = 0, [2] = 0 }
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_heli" then
      assertEq(decodeJson(m.data).phase, "tracking")
      for pid in pairs(MP.GetPlayers()) do
        if m.pid == -1 or m.pid == pid then delivered[pid] = delivered[pid] + 1 end
      end
    end
  end
  assertEq(delivered[1], 1); assertEq(delivered[2], 1)
  env.cleanup()
end)

test("runnerShown goes to cops only", function()
  local env = boot()
  env.startRound()
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.positions[2] = 900; env.call("cnr_tick") end
  local cop, runner = false, false
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_runnerShown" then
      if m.pid == 2 then cop = decodeJson(m.data).shown == false end
      if m.pid == 1 then runner = true end
    end
  end
  assertEq(cop, true)
  assertEq(runner, false)
  env.cleanup()
end)

test("practice as runner sends the heli to the issuer only and no runnerShown", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } }, config = '{"weather":"clear"}' })
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 50 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_runnerGo").pid, 1)
  assertEq(env.lastSent("cnr_release").pid, 1)
  assertEq(env.lastSent("cnr_runnerShown"), nil)
  local heliCount = 0
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_heli" then
      assertEq(m.pid, 1); assertEq(decodeJson(m.data).phase, "arriving")
      heliCount = heliCount + 1
    end
  end
  assertEq(heliCount, 1)
  env.cleanup()
end)

test("a rejoining cop gets the current helicopter as a spectator", function()
  local env = boot({ config = '{"helicopterArrivalSeconds": 0, "weather": "clear"}' })
  runToChase(env)
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  assertEq(env.lastSent("cnr_roundSetup"), nil)
  local watch = env.lastSent("cnr_spectate")
  assertEq(watch.pid, 2)
  local d = decodeJson(watch.data)
  assertEq(d.heli.phase, "searching")
  env.cleanup()
end)

test("cnr_heli carries the seed while up", function()
  local env = boot({ config = '{"helicopterArrivalSeconds": 0, "weather": "clear"}' })
  runToChase(env)
  local last
  for _, m in ipairs(env.sent) do if m.ev == "cnr_heli" then last = decodeJson(m.data) end end
  assertEq(type(last.seed), "number")
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  local watch = env.lastSent("cnr_spectate")
  assertEq(type(decodeJson(watch.data).heli.seed), "number")
  env.cleanup()
end)

test("cnr_heli carries guided when a cop sees the runner", function()
  local env = boot({ config = '{"helicopterArrivalSeconds": 0, "weather": "clear"}' })
  runToChase(env)
  env.positions[2] = 300
  env.sent = {}
  env.call("cnr_sight", 2, '{"seen":true}')
  for _ = 1, 2 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local last
  for _, m in ipairs(env.sent) do if m.ev == "cnr_heli" then last = decodeJson(m.data) end end
  assertEq(last.guided, true)
  env.sent = {}
  env.call("cnr_sight", 2, '{"seen":false}')
  for _ = 1, 9 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  last = nil
  for _, m in ipairs(env.sent) do if m.ev == "cnr_heli" then last = decodeJson(m.data) end end
  assertEq(last ~= nil, true)
  assertEq(last.guided, nil)
  env.cleanup()
end)

test("cnr_cover from the runner reaches the round", function()
  local env = boot({ config = '{"helicopterArrivalSeconds": 0, "helicopterUpSeconds": 200, "weather": "clear"}' })
  runToChase(env, true)
  local first
  for _, m in ipairs(env.sent) do if m.ev == "cnr_heli" then first = first or decodeJson(m.data).phase end end
  assertEq(first, "tracking")
  env.sent = {}
  env.call("cnr_cover", 1, '{"covered":true}')
  for _ = 1, 12 do env.clock = env.clock + 0.25; env.positions[2] = 900; env.call("cnr_tick") end
  local last
  for _, m in ipairs(env.sent) do if m.ev == "cnr_heli" then last = decodeJson(m.data).phase end end
  assertEq(last, "searching")
  env.cleanup()
end)

test("pick request carries the excluded models", function()
  local env = boot({ config = '{"excludedModels":["citybus"]}' })
  env.panel(2, "start rein")
  assertEq(env.lastSent("cnr_pickVehicle").data:find("citybus", 1, true) ~= nil, true)
  env.cleanup()
end)

test("players are recognised by BeamMP account across name changes", function()
  local env = boot({ files = { ["data/colors.json"] = '{"beammp:7":"#ff0000"}' } })
  env.ids = { [1] = { beammp = "7" }, [2] = { beammp = "9" } }
  env.names = { "guest555", "Bob" }
  env.panel(2, "start guest")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local setup
  for _, m in ipairs(env.sent) do if m.ev == "cnr_roundSetup" and m.pid == 1 then setup = m.data end end
  assertEq(setup:find('"hex":"#ff0000"', 1, true) ~= nil, true)
  env.go()
  env.positions[1], env.positions[2] = 0, 5
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local saved = assert(io.open(env.dir .. "data/leaderboard.json")):read("*a")
  assertEq(saved:find('"key":"beammp:7"', 1, true) ~= nil, true)
  assertEq(saved:find('"catcherKeys"', 1, true) ~= nil, true)
  env.names = { "Reinder", "Bob" }
  env.panel(2, "start again")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.lastSent("cnr_roundSetup").data:find('"runnerId":1', 1, true) ~= nil, true)
  env.cleanup()
end)

test("auto next round prepares a new round but waits for go", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.caught() then break end
  end
  assertEq(env.caught(), true)
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local pick = env.lastSent("cnr_pickVehicle")
  assertEq(pick ~= nil, true)
  env.call("cnr_vehiclePicked", pick.pid, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.lastSent("cnr_roundSetup").data:find('"runnerId":2', 1, true) ~= nil, true)
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_countdown"), nil)
  env.cleanup()
end)

test("a save drops retired sky settings from config.json", function()
  local env = boot({ config = '{"clockSpeed":30,"timeOfDay":"map","weather":"map","lastSeenIntervalSeconds":5}' })
  env.panel(1, "auto on")
  local saved = assert(io.open(env.dir .. "config.json")):read("*a")
  assertEq(saved:find("clockSpeed", 1, true), nil)
  assertEq(saved:find("lastSeenIntervalSeconds", 1, true), nil)
  assertEq(saved:find('"map"', 1, true), nil)
  assertEq(saved:find('"autoNextRound":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("/cnr auto toggles and saves the setting", function()
  local env = boot()
  env.panel(1, "auto on")
  assertEq(env.replyHas("Automatic next round: on"), true)
  local saved = assert(io.open(env.dir .. "config.json")):read("*a")
  assertEq(saved:find('"autoNextRound":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("manual start cancels a pending automatic round", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.caught() then break end
  end
  env.panel(1, "start reinder")
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  env.cleanup()
end)

test("the mode event advertises the version and shared starting grid at load and join", function()
  local env = boot()
  assertEq(env.logHas("Cops and Robbers " .. CNR_VERSION .. " loaded"), true)
  local loaded = env.lastSent("cnr_mode")
  env.call("onPlayerJoin", 2)
  local joined = env.lastSent("cnr_mode")
  assertEq(loaded.pid, -1); assertEq(joined.pid, 2)
  for _, event in ipairs({ loaded, joined }) do
    local payload = decodeJson(event.data)
    assertEq(payload.version, CNR_VERSION)
    assertEq(payload.startGrid, true)
    payload.version, payload.startGrid = nil, nil
    assertEq(next(payload), nil)
  end
  env.cleanup()
end)

test("round setup sends the runner's XYZ when a vehicle sample is available", function()
  for _, available in ipairs({ true, false }) do
    local env = boot()
    if available then env.vidPositions["1-0"] = { pos = { 6, 8, 12 }, vel = { 1, 2, 3 } } end
    env.panel(2, "start rein")
    env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
    local setup = env.lastSent("cnr_roundSetup")
    assertEq(setup.pid, 2)
    local pos = decodeJson(setup.data).runnerPos
    if available then
      assertEq(pos.x, 6); assertEq(pos.y, 8); assertEq(pos.z, 12)
    else
      assertEq(pos, nil)
    end
    env.cleanup()
  end
end)

test("leaderboard with a wrong shape is moved aside", function()
  local tmp = boot()
  local dir = tmp.dir
  tmp.cleanup()
  local env = boot()
  local f = assert(io.open(env.dir .. "data/leaderboard.json", "w")); f:write('{"runs":5}'); f:close()
  env.cleanup()
  env = boot()
  os.execute("mkdir -p '" .. env.dir .. "data'")
  f = assert(io.open(env.dir .. "data/leaderboard.json", "w")); f:write('{"runs":5}'); f:close()
  local src = assert(io.open("server/CopsAndRobbers/main.lua")):read("*a")
  local logs = {}
  local realPrint = print
  print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
  assert(load(src, env.dir .. "main.lua"))()
  print = realPrint
  local moved = false
  for _, l in ipairs(logs) do if l:find("moved to", 1, true) then moved = true end end
  assertEq(moved, true)
  env.cleanup()
end)

test("roundEnd carries autoNextSeconds when an auto round is scheduled", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound(); env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    local e = env.lastSent("cnr_roundEnd")
    if e and e.data:find("caught", 1, true) then break end
  end
  assertEq(env.lastSent("cnr_roundEnd").data:find('"autoNextSeconds":5', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a recorded run sends the top 3 for the map", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local top = env.lastSent("cnr_top")
  assertEq(top.pid, 2)
  assertEq(top.data:find('"player":"Reinder"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a mid-chase rejoin gets chaseElapsed in the spectator event", function()
  local env = boot()
  env.startRound(); env.go()
  env.positions[1], env.positions[2] = 0, 900
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.sent = {}
  env.call("onPlayerDisconnect", 2)
  env.call("onPlayerJoin", 2)
  local watch = env.lastSent("cnr_spectate")
  assertEq(watch.pid, 2)
  assertEq(watch.data:find('"chaseElapsed":5', 1, true) ~= nil, true)
  env.cleanup()
end)

local function countSent(env, ev, pid, offset)
  local n = 0
  for i = (offset or 0) + 1, #env.sent do
    local s = env.sent[i]
    if s.ev == ev and (pid == nil or s.pid == pid) then n = n + 1 end
  end
  return n
end

test("round setup has a random sky with a date by default", function()
  local env = boot()
  env.startRound()
  local s = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(type(s.time), "string"); assertEq(type(s.weather), "string")
  assertEq(type(s.month), "number"); assertEq(type(s.day), "number"); assertEq(s.daySeconds, 1800)
  env.cleanup()
end)

test("round setup carries a fixed sky", function()
  local env = boot({ config = '{"timeOfDay":"night","weather":"rain"}' })
  env.startRound()
  local s = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(s.time, "night"); assertEq(s.weather, "rain"); assertEq(s.driving, true); assertEq(s.clockSeconds, nil)
  env.cleanup()
end)

test("New car keeps the sky", function()
  local env = boot({ config = '{"weather":"random"}' })
  env.startRound()
  local first = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  env.panel(2, "reroll")
  env.call("cnr_vehiclePicked", 2, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  local after = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(after.windSeed, first.windSeed)
  assertEq(after.month, first.month); assertEq(after.day, first.day)
  env.cleanup()
end)

test("New sky goes to the round's players before GO only", function()
  local env = boot({ config = '{"weather":"random"}' })
  env.startRound()
  env.sent = {}
  env.panel(1, "sky")
  assertEq(countSent(env, "cnr_sky", 1), 1); assertEq(countSent(env, "cnr_sky", 2), 1)
  env.go()
  env.panel(1, "sky")
  assertEq(env.replyHas("before GO"), true)
  env.cleanup()
end)

test("New sky gives different conditions when it can", function()
  local env = boot({ config = '{"weather":"random","timeOfDay":"noon"}' })
  env.startRound()
  local previous = decodeJson(env.lastSent("cnr_roundSetup").data).sky.weather
  math.randomseed(1)
  for _ = 1, 5 do
    env.sent = {}
    env.panel(1, "sky")
    local now = decodeJson(env.lastSent("cnr_sky").data).weather
    assertEq(now ~= previous, true)
    previous = now
  end
  env.cleanup()
end)

test("New sky picks a date that fits the new weather", function()
  local env = boot({ config = '{"weather":"random","timeOfDay":"noon","badWeatherChancePercent":100}' })
  env.startRound()
  local fits = { snow = { [12] = true, [1] = true }, fog = { [10] = true, [11] = true },
    rain = { [3] = true, [4] = true, [10] = true, [11] = true }, storm = { [3] = true, [4] = true, [10] = true, [11] = true },
    thunderstorm = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true } }
  math.randomseed(3)
  for _ = 1, 8 do
    env.sent = {}
    env.panel(1, "sky")
    local s = decodeJson(env.lastSent("cnr_sky").data)
    assertEq(fits[s.weather][s.month], true)
    assertEq(type(s.day), "number"); assertEq(type(s.year), "number")
  end
  env.cleanup()
end)

test("the setup and New sky payloads carry the schedule and strike seed", function()
  local env = boot({ config = '{"weather":"random"}' })
  math.randomseed(1)
  env.startRound()
  local function check(s)
    assertEq(type(s.lightningSeed), "number")
    assertEq(s.lightningSeed % 1, 0)
    assertEq(s.lightningSeed >= 1 and s.lightningSeed <= 2147483646, true)
    assertEq(type(s.changes), "table")
    assertEq(#s.changes > 0, true)
    assertEq(#s.temps >= 2, true)
    assertEq(type(s.gameStart), "number"); assertEq(type(s.releaseAt), "number")
  end
  local function key(s)
    local parts = {}
    for _, c in ipairs(s.changes) do parts[#parts + 1] = c.to .. "@" .. tostring(c.at) end
    return table.concat(parts, ",")
  end
  local setup = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  check(setup)
  env.sent = {}
  env.panel(1, "sky")
  local again = decodeJson(env.lastSent("cnr_sky").data)
  check(again)
  assertEq(key(again) ~= key(setup), true)
  env.cleanup()
end)

test("New sky needs a random setting", function()
  local env = boot({ config = '{"timeOfDay":"noon","weather":"clear"}' })
  env.startRound()
  env.panel(1, "sky")
  assertEq(env.replyHas("to random first"), true)
  env.cleanup()
end)

test("a practice round gets a sky too", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } }, config = '{"weather":"snow"}' })
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).sky.weather, "snow")
  env.cleanup()
end)

test("the round setup tells the client a practice round is practice, and a real round is not", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(decodeJson(env.lastSent("cnr_roundSetup").data).practice, true)
  env.cleanup()
  local real = boot()
  real.startRound()
  assertEq(decodeJson(real.lastSent("cnr_roundSetup").data).practice, nil)
  real.cleanup()
end)

test("a joined spectator receives the fractional storm clock at probe time", function()
  local env = boot({config = '{"weather":"thunderstorm"}', floatTimer = true})
  env.startRound()
  local p = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  assertEq(p.lightningClockSync, true)
  local request = encode({seed = p.lightningSeed, id = 4})
  env.call("cnr_lightningClock", 1, request)
  assertEq(env.lastSent("cnr_lightningClock"), nil)
  local uptime = 7 * 24 * 3600
  env.clock = uptime + 9.576
  env.go()
  env.clock = uptime + 21.132
  env.names = {"Reinder", "Bob", "Kim"}
  env.call("onPlayerJoin", 3)
  env.clock = uptime + 21.269
  env.call("cnr_lightningClock", 3, request)
  local message = env.lastSent("cnr_lightningClock")
  assertEq(message and message.pid, 3)
  local reply = decodeJson(message.data)
  assertEq(reply.id, 4)
  assertEq(reply.seed, p.lightningSeed)
  assertNear(reply.elapsed, 11.693, 1e-5)
  env.cleanup()
end)

test("the storm clock is private to the practice issuer", function()
  local env = boot({config = '{"weather":"thunderstorm"}'})
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local p = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  env.go()
  local request = encode({seed = p.lightningSeed, id = 1})
  env.call("cnr_lightningClock", 2, request)
  assertEq(env.lastSent("cnr_lightningClock"), nil)
  env.call("cnr_lightningClock", 1, request)
  assertEq(env.lastSent("cnr_lightningClock").pid, 1)
  env.cleanup()
end)

test("a mid-chase rejoin gets the spectator sky and can sync the storm clock on its new player ID", function()
  local env = boot({config = '{"weather":"thunderstorm"}'})
  env.startRound(); env.go()
  env.positions[1], env.positions[2] = 0, 900
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local before = decodeJson(env.lastSent("cnr_roundSetup").data).sky
  env.call("onPlayerDisconnect", 2)
  env.names = { [1] = "Reinder", [3] = "Bob" }
  env.call("onPlayerJoin", 3)
  local joined = decodeJson(env.lastSent("cnr_spectate").data).sky
  assertNear(joined.clockSeconds, 15, 0.01)
  assertEq(joined.month, before.month); assertEq(joined.day, before.day); assertEq(joined.daySeconds, 1800)
  local request = encode({seed = joined.lightningSeed, id = 5})
  env.call("cnr_lightningClock", 3, request)
  local reply = env.lastSent("cnr_lightningClock")
  assertEq(reply and reply.pid, 3)
  assertNear(decodeJson(reply.data).elapsed, 15, 0.01)
  env.sent = {}
  env.call("cnr_lightningClock", 2, request)
  assertEq(env.lastSent("cnr_lightningClock"), nil)
  env.cleanup()
end)

local function shownSetting(env, key)
  env.call("cnr_panel", 1, '{"action":"open"}')
  local v = decodeJson(env.lastSent("cnr_panelState").data).settings[key]
  if type(v) == "table" then v = table.concat(v, ", ") end
  return tostring(v)
end

test("panel open sends state to the opener", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  local s = env.lastSent("cnr_panelState")
  assertEq(s.pid, 1)
  assertEq(s.data:find('"phase":"idle"', 1, true) ~= nil, true)
  assertEq(s.data:find('"map":"west_coast_usa"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("panel state is pushed on change, not every tick", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  local n = countSent(env, "cnr_panelState", 1)
  env.call("cnr_tick"); env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), n)
  env.startRound()
  env.call("cnr_tick")
  local m = countSent(env, "cnr_panelState", 1)
  assertEq(m > n, true)
  assertEq(env.lastSent("cnr_panelState").data:find('"phase":"prep"', 1, true) ~= nil, true)
  env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), m)
  env.cleanup()
end)

test("changing auto mode in the panel updates subscribers", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.panel(2, "auto on")
  env.call("cnr_tick")
  local s = env.lastSent("cnr_panelState")
  assertEq(s.pid, 1)
  assertEq(s.data:find('"autoNextRound":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("panel command runs handlers and mirrors replies", function()
  local env = boot()
  env.call("cnr_panel", 2, '{"action":"command","text":"go"}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 2)
  assertEq(r.data:find("No round set up", 1, true) ~= nil, true)
  env.call("cnr_panel", 2, '{"action":"command","text":"start Reinder"}')
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  env.cleanup()
end)

test("panel command outside the allowlist does nothing", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"set headStartSeconds 1"}')
  assertEq(shownSetting(env, "headStartSeconds"), "7")
  env.cleanup()
end)

test("panel settings save several values in one write", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9,"explodeOnCatch":true,"excludedModels":["citybus"]}}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 1)
  assertEq(r.data:find('"ok":true', 1, true) ~= nil, true)
  assertEq(shownSetting(env, "headStartSeconds"), "9")
  assertEq(shownSetting(env, "explodeOnCatch"), "true")
  assertEq(shownSetting(env, "excludedModels"), "citybus")
  env.cleanup()
end)

test("empty excluded list saves", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"excludedModels":[]}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"ok":true', 1, true) ~= nil, true)
  assertEq(shownSetting(env, "excludedModels"), "")
  env.cleanup()
end)

test("panel settings with one invalid value save nothing", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9,"catchHoldSeconds":0}}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.data:find('"ok":false', 1, true) ~= nil, true)
  assertEq(r.data:find("catchHoldSeconds", 1, true) ~= nil, true)
  assertEq(shownSetting(env, "headStartSeconds"), "7")
  env.cleanup()
end)

test("panel settings are refused during a round", function()
  local env = boot()
  env.startRound()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9}}')
  assertEq(env.lastSent("cnr_panelReply").data:find("Stop the round first", 1, true) ~= nil, true)
  env.panel(1, "stop")
  assertEq(shownSetting(env, "headStartSeconds"), "7")
  env.cleanup()
end)

test("disconnect drops the panel subscriber", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.call("onPlayerDisconnect", 1)
  local n = countSent(env, "cnr_panelState", 1)
  env.panel(2, "auto on")
  env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), n)
  env.cleanup()
end)

test("malformed panel data is ignored", function()
  local env = boot()
  env.call("cnr_panel", 1, "not json")
  env.call("cnr_panel", 1, '{"nope":1}')
  env.call("cnr_panel", 1, '{"action":"settings","values":"x"}')
  assertEq(env.lastSent("cnr_panelReply").data:find("Nothing to save", 1, true) ~= nil, true)
  env.cleanup()
end)

local function capturingLogs(fn)
  local logs, realPrint = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  print = realPrint
  if not ok then error(err, 0) end
  return function(text)
    for _, l in ipairs(logs) do if l:find(text, 1, true) then return true end end
    return false
  end
end

test("settings replies echo the request id", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","id":7,"values":{"headStartSeconds":9}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"id":7', 1, true) ~= nil, true)
  env.call("cnr_panel", 1, '{"action":"settings","id":8,"values":{"catchHoldSeconds":0}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"id":8', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a command the panel may not send gets a reply", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"set headStartSeconds 1"}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 1)
  assertEq(r.data:find("Not available from the panel", 1, true) ~= nil, true)
  env.cleanup()
end)

local function lastReply(env)
  return decodeJson(env.lastSent("cnr_panelReply").data)
end

test("a command the panel may not send is refused as a warning", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"set headStartSeconds 1"}')
  assertEq(lastReply(env).text, "Not available from the panel")
  assertEq(lastReply(env).tone, "warn")
  env.cleanup()
end)

test("the Car tab during a round is refused as a warning", function()
  local env = boot()
  env.startRound()
  env.call("cnr_panel", 1, '{"action":"build","op":"reset"}')
  assertEq(lastReply(env).text, "Stop the round first")
  assertEq(lastReply(env).tone, "warn")
  env.cleanup()
end)

test("a car that can't start a build is refused as a warning", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"build","op":"new","model":"","parts":{}}')
  assertEq(lastReply(env).text, "That car can't start a build")
  assertEq(lastReply(env).tone, "warn")
  env.cleanup()
end)

test("apply from anyone but the runner is refused as a warning", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"carMode":"evolving"}}')
  env.call("cnr_panel", 1, '{"action":"build","op":"new","model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":{}}')
  env.panel(2, "start rein")
  env.call("cnr_panel", 2, '{"action":"apply"}')
  assertEq(lastReply(env).text, "Only the runner can apply the change")
  assertEq(lastReply(env).tone, "warn")
  env.cleanup()
end)

test("command refusals in the panel are warnings", function()
  local env = boot()
  local function refused(text, msg)
    env.call("cnr_panel", 1, msg)
    assertEq(lastReply(env).text, text, msg)
    assertEq(lastReply(env).tone, "warn", msg)
  end
  local function command(text) return '{"action":"command","text":"' .. text .. '"}' end
  refused("No round set up, start one in the panel", command("go"))
  refused("No round running", command("end"))
  refused("No round running", command("stop"))
  refused("You can only reroll during prep", command("reroll"))
  refused("You can only change the sky before GO", command("sky"))
  refused("No round is scheduled", command("next"))
  refused("No player matching 'Zed'", command("start Zed"))
  refused("You need to be in a vehicle", '{"action":"station","op":"add"}')
  refused("You need to be in a vehicle", '{"action":"station","op":"remove"}')
  env.positions[1] = 500
  refused("No gas station within 50 m", '{"action":"station","op":"remove"}')
  env.startRound()
  refused("A round is already running", command("start rein"))
  refused("A round is already running", command("test cop"))
  refused("Stop the round before reloading", command("reload"))
  refused("The chase has not started, use Cancel", command("end"))
  env.cleanup()
end)

test("command answers in the panel stay plain", function()
  local env = boot()
  env.panel(1, "reload")
  assertEq(lastReply(env).text, "Config reloaded")
  assertEq(lastReply(env).tone, nil)
  env.positions[1] = 0
  env.call("cnr_panel", 1, '{"action":"station","op":"add"}')
  assertEq(lastReply(env).tone, nil)
  env.call("cnr_panel", 1, '{"action":"build","op":"new","model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":{}}')
  assertEq(lastReply(env).tone, nil)
  env.call("cnr_panel", 1, '{"action":"build","op":"reset"}')
  assertEq(lastReply(env).text, "Build reset")
  assertEq(lastReply(env).tone, nil)
  env.cleanup()
end)

test("panel start keeps the name's case in replies", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"start Zed"}')
  assertEq(env.lastSent("cnr_panelReply").data:find("No player matching 'Zed'", 1, true) ~= nil, true)
  env.cleanup()
end)

test("a panel error does not stop the round tick", function()
  local env = boot()
  env.startRound()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.go()
  MP.GetPlayers = function() error("boom") end
  local logged = capturingLogs(function()
    for _ = 1, 20 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  end)
  assertEq(env.lastSent("cnr_runnerGo") ~= nil, true)
  assertEq(logged("panel update failed"), true)
  env.cleanup()
end)

test("auto off tells clients to drop the next round countdown", function()
  local env = boot()
  env.panel(1, "auto off")
  local s = env.lastSent("cnr_autoNext")
  assertEq(s ~= nil and s.pid, -1)
  env.cleanup()
end)

test("parts change log names the differing slots", function()
  local env = boot()
  env.startRound()
  placed(env)
  local logged = capturingLogs(function()
    env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"engine":"v8","tires":"a"}}}')
    env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"engine":"v12","tires":"a","wing":"big"}}}')
  end)
  assertEq(logged("changed parts during the round: engine, wing"), true)
  env.cleanup()
end)

local function runningRound(env)
  env.startRound()
  confirmDrivers(env, 2)
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
end

test("a cop's sight report sends live XYZ to the cop and distance to the runner", function()
  local env = boot()
  runningRound(env)
  env.names = { "Reinder", "Bob", "Kim" }
  env.call("onPlayerJoin", 3)
  assertEq(env.lastSent("cnr_spectate").pid, 3)
  env.sent = {}
  env.vidPositions["1-0"] = { pos = { 6, 8, 12 }, vel = { 0, 0, 0 } }
  env.vidPositions["2-0"] = { pos = { 6, 8, 42 }, vel = { 0, 0, 0 } }
  env.call("cnr_sight", 2, '{"seen":true}')
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  local live = env.lastSent("cnr_lastSeen")
  for _, event in ipairs(env.sent) do
    if event.ev == "cnr_lastSeen" then assertEq(event.pid, 2) end
  end
  local ping = decodeJson(live.data)
  assertEq(ping.live, true)
  assertEq(ping.route, false)
  assertEq(ping.pos.x, 6); assertEq(ping.pos.y, 8); assertEq(ping.pos.z, 12)
  local nearest = env.lastSent("cnr_nearestCop")
  assertEq(nearest.pid, 1)
  assertEq(decodeJson(nearest.data).dist, 30)
  local spotted = env.lastSent("cnr_spotted")
  assertEq(spotted.pid, 1)
  assertEq(decodeJson(spotted.data).spotted, true)
  env.cleanup()
end)

test("a sight report from the runner is ignored", function()
  local env = boot()
  runningRound(env)
  env.sent = {}
  env.call("cnr_sight", 1, '{"seen":true}')
  env.call("cnr_sight", 1, "not json")
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_lastSeen"), nil)
  assertEq(env.lastSent("cnr_spotted"), nil)
  env.cleanup()
end)

test("round setup tells clients the sight range", function()
  local env = boot()
  env.startRound()
  assertEq(env.lastSent("cnr_roundSetup").data:find('"sightMaxMeters":400', 1, true) ~= nil, true)
  env.cleanup()
end)

local function readFileAt(path)
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

test("an old leaderboard is moved aside as unreadable and the board starts empty", function()
  local old = '{"runs":[{"player":"Old","survivedSeconds":999,"map":"west_coast_usa","endedAt":1}]}'
  local env = boot({ leaderboard = old })
  local data = env.dir .. "data/"
  local files = assert(io.popen('ls "' .. data .. '"'))
  local boards = {}
  for name in files:lines() do
    if name:match("^leaderboard") then boards[#boards + 1] = name end
  end
  assert(files:close())
  assertEq(#boards, 1)
  assertEq(boards[1]:match("^leaderboard%.json%.corrupt%-%d+$"), boards[1])
  assertEq(readFileAt(data .. boards[1]), old)
  assertEq(env.logHas("leaderboard.json was unreadable, moved to " .. data .. boards[1]), true)
  env.call("cnr_board", 1, '{"action":"open"}')
  assertEq(#decodeJson(env.lastSent("cnr_boardState").data).rounds, 0)
  env.cleanup()
end)

test("the board app gets state on open, after a run and on a filter change", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  local s = env.lastSent("cnr_boardState")
  assertEq(s.pid, 2)
  assertEq(s.data:find('"filter":"west_coast_usa"', 1, true) ~= nil, true)
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.sent = {}
  env.panel(1, "end")
  s = env.lastSent("cnr_boardState")
  assertEq(s.pid, 2)
  assertEq(s.data:find("Reinder", 1, true) ~= nil, true)
  env.call("cnr_board", 2, '{"action":"filter","map":"all"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"filter":"all"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a board subscriber who leaves gets no more pushes", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  assertEq(env.lastSent("cnr_boardState"), nil)
  env.cleanup()
end)

test("a recorded run stores cops by key with their sight time", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  local text = readFileAt(env.dir .. "data/leaderboard.json")
  assertEq(text:find('"format":2', 1, true) ~= nil, true)
  assertEq(text:find('"cops":["name:Bob"]', 1, true) ~= nil, true)
  assertEq(text:find('"copSightSeconds":%[0') ~= nil, true)
  assertEq(text:find('"copIds"', 1, true), nil)
  env.cleanup()
end)

test("if the old leaderboard can't be moved aside, it is never overwritten", function()
  local env = boot({ leaderboard = '{"runs":[{"player":"Old","survivedSeconds":999,"map":"west_coast_usa","endedAt":1}]}', renameFails = true })
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  assertEq(readFileAt(env.dir .. "data/leaderboard.json"):find("Old", 1, true) ~= nil, true)
  env.call("cnr_board", 1, '{"action":"open"}')
  local rounds = decodeJson(env.lastSent("cnr_boardState").data).rounds
  assertEq(#rounds, 1)
  assertEq(rounds[1].player, "Reinder")
  assertEq(env.logHas("leaderboard not saved: the old file could not be moved aside"), true)
  env.cleanup()
end)

test("changing a setting refreshes open leaderboards", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.sent = {}
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"assistMinSightPercent":40}}')
  assertEq(env.lastSent("cnr_boardState") ~= nil, true)
  env.cleanup()
end)

test("panel replies go to the panel only", function()
  local env = boot()
  env.panel(2, "go")
  assertEq(env.replyHas("No round set up, start one in the panel"), true)
  for _, m in ipairs(env.sent) do assertEq(m.ev == "cnr_notice" and m.pid == 2, false) end
  env.cleanup()
end)

test("a teleport in the chase is a warn notice for everyone", function()
  local env = boot()
  env.startRound()
  env.go()
  for _ = 1, 34 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.noticeHas("teleported"), false)
  env.positions[1] = 5000
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  assertEq(env.noticeHas("Reinder teleported", "warn"), true)
  local to
  for _, m in ipairs(env.sent) do
    if m.ev == "cnr_notice" and m.data:find("Reinder teleported", 1, true) then to = m.pid end
  end
  assertEq(to, -1)
  env.cleanup()
end)

test("key binding commands are gone", function()
  local env = boot()
  assertEq(env.events.cnr_command, nil)
  env.cleanup()
end)

test("the panel can reload config.json, but not during a round", function()
  local env = boot()
  env.panel(1, "reload")
  assertEq(env.lastSent("cnr_panelReply").data:find("Config reloaded", 1, true) ~= nil, true)
  env.startRound()
  env.panel(1, "reload")
  assertEq(env.lastSent("cnr_panelReply").data:find("Stop the round before reloading", 1, true) ~= nil, true)
  env.cleanup()
end)

test("no player-facing text tells people to type a removed command", function()
  local files = { "client/ui/modules/apps/CopsAndRobbersHud/app.vue", "client/mod_info/CopsAndRobbers/info.json" }
  local list = io.popen("find server client/lua -name '*.lua'")
  for f in list:lines() do files[#files + 1] = f end
  list:close()
  local exact = { '"/cnr go"', '"/cnr start', '"/cnr auto', '"/cnr stop"', '"/cnr test', '"/cnr set', '"/cnr top', '"/cnr continue', '"/cnr reload', '"/cnr config' }
  local anywhere = { "/cnr color", "/cnr addstation", "/cnr removestation", "/cnr help", "/cnr version" }
  for _, f in ipairs(files) do
    local text = assert(io.open(f)):read("*a")
    for _, removed in ipairs(exact) do assertEq(text:find(removed, 1, true), nil, f .. " " .. removed) end
    for _, removed in ipairs(anywhere) do assertEq(text:find(removed, 1, true), nil, f .. " " .. removed) end
  end
end)

test("a saved build is loaded at startup", function()
  local env = boot({ files = { ["data/build.json"] = '{"model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":null,"step":3,"history":null}' } })
  assertEq(env.logHas("Build: Gavril D-Series · change 3"), true)
  env.cleanup()
end)

test("a broken build file is moved aside and there is no build", function()
  local env = boot({ files = { ["data/build.json"] = '{"model":' } })
  assertEq(env.logHas("no build"), true)
  assertEq(readFileAt(env.dir .. "data/build.json"), nil)
  env.cleanup()
end)

local function evolving(env)
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"carMode":"evolving"}}')
end

local function newBuild(env)
  env.call("cnr_panel", 1, '{"action":"build","op":"new","model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":{}}')
end

local function rebuildId(env)
  return assert(env.lastSent("cnr_rebuild").data:match('"rebuild":(%d+)'))
end

local function lsData(env, pattern)
  for name in io.popen('ls "' .. env.dir .. 'data"'):lines() do
    if name:match(pattern) then return name end
  end
end

test("a new build is saved and shown in the panel", function()
  local env = boot()
  newBuild(env)
  assertEq(env.lastSent("cnr_panelReply").data:find("New build: Gavril D-Series · change 0", 1, true) ~= nil, true)
  assertEq(readFileAt(env.dir .. "data/build.json"):find('"pickup_engine":"v8"', 1, true) ~= nil, true)
  env.call("cnr_panel", 1, '{"action":"open"}')
  assertEq(env.lastSent("cnr_panelState").data:find("Gavril D-Series · change 0", 1, true) ~= nil, true)
  env.cleanup()
end)

test("resetting the build keeps a backup", function()
  local env = boot()
  newBuild(env)
  env.call("cnr_panel", 1, '{"action":"build","op":"reset"}')
  assertEq(readFileAt(env.dir .. "data/build.json"), nil)
  assertEq(lsData(env, "^build%-%d+%.json$") ~= nil, true)
  env.cleanup()
end)

test("an evolving round needs a build first", function()
  local env = boot()
  evolving(env)
  env.panel(2, "start rein")
  assertEq(env.lastSent("cnr_panelReply").data:find("Start a new build first", 1, true) ~= nil, true)
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  env.cleanup()
end)

test("a full evolving round: prep, apply, rebuild, ready, GO", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  local setup = env.lastSent("cnr_roundSetup")
  assertEq(setup.data:find('"evolving":true', 1, true) ~= nil, true)
  assertEq(setup.data:find('"pickup_engine":"v8"', 1, true) ~= nil, true)
  env.call("cnr_panel", 1, '{"action":"apply"}')
  assertEq(env.lastSent("cnr_requestSetup").pid, 1)
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[{"label":"Engine","from":"4.5L V8","to":"6.0L V8"}]}')
  assertEq(countSent(env, "cnr_rebuild"), 2)
  assertEq(env.noticeHas("Change 1 by Reinder: Engine 4.5L V8 → 6.0L V8", "info"), true)
  assertEq(readFileAt(env.dir .. "data/build.json"):find('"pickup_engine":"v8_60"', 1, true) ~= nil, true)
  local id = rebuildId(env)
  env.call("cnr_myVehicle", 1, '{"vid":0,"rebuild":' .. id .. '}')
  env.call("cnr_myVehicle", 2, '{"vid":0,"rebuild":' .. id .. '}')
  assertEq(env.lastSent("cnr_applied") ~= nil, true)
  assertEq(env.noticeHas("Cars ready"), false)
  env.go()
  assertEq(env.lastSent("cnr_countdown") ~= nil, true)
  env.cleanup()
end)

test("a car report from before the rebuild doesn't make a player ready", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[]}')
  local id = rebuildId(env)
  env.call("cnr_myVehicle", 1, '{"vid":0,"rebuild":' .. id .. '}')
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  assertEq(countSent(env, "cnr_applied"), 0)
  env.call("cnr_myVehicle", 2, '{"vid":0,"rebuild":' .. id .. '}')
  assertEq(countSent(env, "cnr_applied"), 1)
  env.cleanup()
end)

test("a returning spectator does not delay the other players applying a rebuild", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[]}')
  local id = rebuildId(env)
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  assertEq(env.lastSent("cnr_roundSetup"), nil)
  assertEq(decodeJson(env.lastSent("cnr_spectate").data).phase, "applying")
  env.call("cnr_myVehicle", 1, encode({vid=0, rebuild=id}))
  assertEq(countSent(env, "cnr_applied"), 1)
  env.cleanup()
end)

test("an Apply rebuild and the runner's own prep change are not parts changes", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  placed(env, 1); placed(env, 2)
  local v8 = '%d-0:{"jbm":"pickup","vcf":{"parts":{"pickup_engine":"v8"}}}'
  local v8_60 = '%d-0:{"jbm":"pickup","vcf":{"parts":{"pickup_engine":"v8_60"}}}'
  env.call("onVehicleEdited", 1, 0, v8:format(1)); env.call("onVehicleEdited", 2, 0, v8:format(2))
  env.call("onVehicleEdited", 1, 0, v8_60:format(1))
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[]}')
  env.call("onVehicleEdited", 2, 0, v8_60:format(2))
  local id = rebuildId(env)
  env.call("cnr_myVehicle", 2, '{"vid":0,"rebuild":' .. id .. '}')
  env.call("cnr_myVehicle", 1, '{"vid":0,"rebuild":' .. id .. '}')
  assertEq(partsLines(env), 0)
  env.cleanup()
end)

test("a late report of the runner's prep change after Apply is not a parts change", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  placed(env, 1)
  env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"pickup_engine":"v8"}}}')
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"pickup_engine":"v8_60"}}}')
  assertEq(partsLines(env), 0)
  env.cleanup()
end)

test("the runner's queued change goes to everyone, a cop's doesn't", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.sent = {}
  env.call("cnr_change", 2, '{"changes":[{"label":"Engine","from":"a","to":"b"}]}')
  assertEq(env.lastSent("cnr_queued"), nil)
  env.call("cnr_change", 1, '{"changes":[{"label":"Engine","from":"a","to":"b"}]}')
  assertEq(countSent(env, "cnr_queued"), 2)
  assertEq(env.lastSent("cnr_queued").data:find('"runner":"Reinder"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("missing parts are announced to everyone", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_missing", 2, '{"parts":["meo_turbo","meo_intake"]}')
  assertEq(env.lastSent("cnr_notice").data:find("Bob is missing: meo_turbo, meo_intake", 1, true) ~= nil, true)
  assertEq(env.lastSent("cnr_notice").data:find('"tone":"warn"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("missing parts in a practice round reach only whoever practises", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(1, "test runner")
  env.sent = {}
  env.call("cnr_missing", 1, '{"parts":["meo_turbo"]}')
  local m = env.lastSent("cnr_notice")
  assertEq(m.data:find("Reinder is missing: meo_turbo", 1, true) ~= nil, true)
  assertEq(m.pid, 1)
  env.cleanup()
end)

test("a practice round never changes the saved build", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(1, "test runner")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[]}')
  assertEq(readFileAt(env.dir .. "data/build.json"):find('"pickup_engine":"v8"', 1, true) ~= nil, true)
  assertEq(readFileAt(env.dir .. "data/build.json"):find("v8_60", 1, true), nil)
  env.cleanup()
end)

test("an evolving car with another config name is not refused", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/other.pc","parts":{}}}'), 0)
  env.cleanup()
end)

test("the board app can filter by mode", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.call("cnr_board", 2, '{"action":"filter","map":"all","mode":"evolving"}')
  local data = env.lastSent("cnr_boardState").data
  assertEq(data:find('"mode":"evolving"', 1, true) ~= nil, true)
  assertEq(data:find('"filter":"all"', 1, true) ~= nil, true)
  env.call("cnr_board", 2, '{"action":"filter","map":"west_coast_usa"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"mode":"all"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("build backups made in the same second never overwrite each other", function()
  local env = boot()
  newBuild(env); newBuild(env); newBuild(env)
  local n = 0
  for name in io.popen('ls "' .. env.dir .. 'data"'):lines() do
    if name:match("^build%-") then n = n + 1 end
  end
  assertEq(n, 2)
  env.cleanup()
end)

test("a setup for another model or with a broken part list is ignored", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.sent = {}
  env.call("cnr_setup", 1, '{"model":"etk800","parts":{"etk_engine":"x"},"vars":{},"changes":[{"label":"Engine","from":"a","to":"b"}]}')
  assertEq(env.lastSent("cnr_rebuild"), nil)
  env.call("cnr_setup", 1, '{"model":"pickup","parts":{"pickup_engine":5},"vars":{},"changes":[]}')
  assertEq(env.lastSent("cnr_rebuild"), nil)
  assertEq(readFileAt(env.dir .. "data/build.json"):find('"pickup_engine":"v8"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("an apply without changes keeps the build step", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  env.call("cnr_setup", 1, '{"model":"pickup","parts":{"pickup_engine":"v8","pickup_frame":"f"},"vars":{},"changes":[]}')
  assertEq(env.noticeHas("Change 1"), false)
  assertEq(readFileAt(env.dir .. "data/build.json"):find('"step":0', 1, true) ~= nil, true)
  env.cleanup()
end)

test("only the runner can apply the change", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.sent = {}
  env.call("cnr_panel", 2, '{"action":"apply"}')
  assertEq(env.lastSent("cnr_requestSetup"), nil)
  assertEq(env.lastSent("cnr_panelReply").data:find("Only the runner can apply the change", 1, true) ~= nil, true)
  env.call("cnr_panel", 1, '{"action":"apply"}')
  assertEq(env.lastSent("cnr_requestSetup").pid, 1)
  env.cleanup()
end)

test("someone rejoining during prep spectates while the runner changes the car", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  env.call("cnr_change", 1, '{"changes":[{"label":"Engine","from":"a","to":"b"}]}')
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  assertEq(env.lastSent("cnr_spectate").pid, 2)
  assertEq(env.lastSent("cnr_queued"), nil)
  env.cleanup()
end)

test("the queued change keeps the part ids, as text and capped", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  local many = {}
  for i = 1, 40 do many[i] = '"p' .. i .. '"' end
  env.call("cnr_change", 1, '{"changes":[{"label":"Engine","from":"a","to":"b","parts":["v8_60",7,{"x":1},' .. table.concat(many, ",") .. ']}]}')
  local q = env.lastSent("cnr_queued").data
  assertEq(q:find('"parts":["v8_60","p1"', 1, true) ~= nil, true)
  assertEq(q:find('"p30"', 1, true) ~= nil, false)
  env.cleanup()
end)

test("queued change lists are capped", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(2, "start rein")
  local items = {}
  for i = 1, 60 do items[i] = '{"label":"P' .. i .. '","from":"a","to":"b"}' end
  env.call("cnr_change", 1, '{"changes":[' .. table.concat(items, ",") .. ']}')
  local data = env.lastSent("cnr_queued").data
  assertEq(data:find('"P30"', 1, true) ~= nil, true)
  assertEq(data:find('"P31"', 1, true), nil)
  env.cleanup()
end)

test("the leaderboard app never receives account ids", function()
  local env = boot()
  env.ids = { [1] = { beammp = "12345" } }
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("cnr_board", 2, '{"action":"open"}')
  env.panel(1, "end")
  env.call("cnr_board", 2, '{"action":"open"}')
  assertEq(env.lastSent("cnr_boardState").data:find("12345", 1, true), nil)
  env.cleanup()
end)

local function sentTo(env, ev, pid)
  for i = #env.sent, 1, -1 do
    local m = env.sent[i]
    if m.ev == ev and m.pid == pid then return m.data end
  end
end

test("colour from the UI is saved and confirmed", function()
  local env = boot()
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  assertEq(sentTo(env, "cnr_myColor", 1):find('"hex":"#ff0000"', 1, true) ~= nil, true)
  local saved = assert(io.open(env.dir .. "data/colors.json")):read("*a")
  assertEq(saved:find("#ff0000", 1, true) ~= nil, true)
  env.startRound()
  local setup
  for _, m in ipairs(env.sent) do if m.ev == "cnr_roundSetup" and m.pid == 1 then setup = m.data end end
  assertEq(setup:find('"hex":"#ff0000"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a bad colour answers with the error and the old colour", function()
  local env = boot()
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  env.call("cnr_color", 1, '{"hex":"#zz"}')
  local d = sentTo(env, "cnr_myColor", 1)
  assertEq(d:find('"error":"Use a hex color like #ff0000"', 1, true) ~= nil, true)
  assertEq(d:find('"hex":"#ff0000"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("no colour clears it", function()
  local env = boot()
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  env.call("cnr_color", 1, '{}')
  assertEq(sentTo(env, "cnr_myColor", 1):find('"hex"', 1, true), nil)
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  env.call("cnr_color", 1, '{"hex":""}')
  assertEq(sentTo(env, "cnr_myColor", 1):find('"hex"', 1, true), nil)
  env.cleanup()
end)

test("joining with a colour saved only under the bare name sends no colour", function()
  local env = boot({ files = { ["data/colors.json"] = '{"Reinder":"#ff0000"}' } })
  env.call("onPlayerJoin", 1)
  assertEq(decodeJson(sentTo(env, "cnr_myColor", 1)).hex, nil)
  env.cleanup()
end)

test("colour in prep repaints", function()
  local env = boot()
  env.startRound()
  env.sent = {}
  env.call("cnr_color", 2, '{"hex":"#00ff00"}')
  local m = env.lastSent("cnr_paint")
  assertEq(m.pid, 2)
  assertEq(m.data:find('"hex":"#00ff00"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("colour during the chase is saved but does not repaint", function()
  local env = boot()
  runToChase(env)
  env.sent = {}
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  assertEq(env.lastSent("cnr_paint"), nil)
  assertEq(sentTo(env, "cnr_myColor", 1):find('"hex":"#ff0000"', 1, true) ~= nil, true)
  assertEq(assert(io.open(env.dir .. "data/colors.json")):read("*a"):find("#ff0000", 1, true) ~= nil, true)
  env.cleanup()
end)

test("a repaint is not a parts change", function()
  local env = boot()
  env.startRound()
  placed(env, 2)
  local bob = function(text) return (text:gsub("^1%-0", "2-0")) end
  env.call("onVehicleEdited", 2, 0, bob(BASE_EDIT))
  env.call("cnr_color", 2, '{"hex":"#00ff00"}')
  assertEq(env.lastSent("cnr_paint").pid, 2)
  env.call("onVehicleEdited", 2, 0, bob(TUNED_EDIT))
  assertEq(partsLines(env), 0)
  env.cleanup()
end)

test("a guest gets their colour by name key", function()
  local env = boot()
  env.call("cnr_color", 1, '{"hex":"#00ff00"}')
  local saved = assert(io.open(env.dir .. "data/colors.json")):read("*a")
  assertEq(saved:find('"name:Reinder"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("join sends your colour", function()
  local env = boot()
  env.call("cnr_color", 1, '{"hex":"#ff0000"}')
  env.sent = {}
  env.call("onPlayerJoin", 1)
  assertEq(sentTo(env, "cnr_myColor", 1):find('"hex":"#ff0000"', 1, true) ~= nil, true)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  local d = sentTo(env, "cnr_myColor", 2)
  assertEq(d ~= nil and d:find('"hex"', 1, true) == nil, true)
  env.cleanup()
end)

test("Map tab adds and removes a station where you stand", function()
  local env = boot()
  env.positions[1] = 0
  env.call("cnr_panel", 1, '{"action":"station","op":"add"}')
  assertEq(env.replyHas("Gas station added (1 on west_coast_usa)"), true)
  assertEq(io.open(env.dir .. "data/stations/west_coast_usa.json") ~= nil, true)
  env.positions[1] = 500
  env.call("cnr_panel", 1, '{"action":"station","op":"remove"}')
  assertEq(env.replyHas("No gas station within 50 m"), true)
  env.positions[1] = 0
  env.call("cnr_panel", 1, '{"action":"station","op":"remove"}')
  assertEq(env.replyHas("Gas station removed (0 left on west_coast_usa)"), true)
  env.cleanup()
end)

test("station discovery persists the first matching map report with its radius", function()
  local env = boot()
  env.call("onPlayerJoin", 1)
  assertEq(decodeJson(env.lastSent("cnr_requestStations").data).map, "west_coast_usa")
  local function report(map, z)
    env.call("cnr_stations", 1, string.format('{"map":"%s","stations":[{"x":1,"y":2,"z":%d,"r":12}]}', map, z))
  end
  report("italy", 100)
  report("west_coast_usa", 5)
  report("west_coast_usa", 200)
  local f = assert(io.open(env.dir .. "data/stations/west_coast_usa.json"))
  local stations = decodeJson(f:read("*a")).stations
  f:close()
  assertEq(#stations, 1)
  assertEq(stations[1].z, 5)
  assertEq(stations[1].r, 12)
  env.cleanup()
end)

test("stations list", function()
  local env = boot()
  env.positions[1] = 0
  env.call("cnr_panel", 1, '{"action":"station","op":"add"}')
  env.call("cnr_panel", 1, '{"action":"stations"}')
  local d = decodeJson(sentTo(env, "cnr_stationList", 1))
  assertEq(d.map, "west_coast_usa")
  assertEq(#d.stations, 1)
  assertEq(d.stations[1].x, 0)
  assertEq(d.stations[1].y ~= nil and d.stations[1].z ~= nil, true)
  env.cleanup()
end)

test("Start now starts the scheduled round", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 60}' })
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.caught() then break end
  end
  assertEq(env.caught(), true)
  env.sent = {}
  env.panel(1, "next")
  assertEq(env.lastSent("cnr_pickVehicle") ~= nil, true)
  env.cleanup()
end)

test("next without a schedule", function()
  local env = boot()
  env.panel(1, "next")
  assertEq(env.replyHas("No round is scheduled"), true)
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  env.cleanup()
end)

test("a joiner gets rules, lobby and colour", function()
  local env = boot()
  env.call("onPlayerJoin", 2)
  assertEq(sentTo(env, "cnr_rules", 2):find('"headStartSeconds":7', 1, true) ~= nil, true)
  assertEq(sentTo(env, "cnr_lobby", 2):find('"online":2', 1, true) ~= nil, true)
  assertEq(sentTo(env, "cnr_lobby", 2):find('"active":false', 1, true) ~= nil, true)
  assertEq(sentTo(env, "cnr_myColor", 2) ~= nil, true)
  env.cleanup()
end)

test("a player already included in the initial pick stays a cop when the join callback arrives", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Kim" }
  env.startRound()
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 3)).role, "cop")
  env.call("onPlayerJoin", 3)
  assertEq(sentTo(env, "cnr_spectate", 3), nil)
  assertEq(env.call("onVehicleSpawn", 3, 0, 'USER:Kim:3-0:{"jbm":"pickup"}'), 0)
  env.cleanup()
end)

test("a cop still loading at the initial pick joins as a spectator and earns no round credit", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Kim" }
  env.loading = { [3] = true }
  env.startRound()
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  assertEq(env.call("onVehicleSpawn", 3, 0, 'USER:Kim:3-0:{"jbm":"pickup"}'), 1)
  env.loading[3] = nil
  env.call("onPlayerJoin", 3)
  assertEq(decodeJson(sentTo(env, "cnr_spectate", 3)).phase, "prep")
  env.panel(2, "reroll")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  env.go()
  env.positions[2] = 900
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  local run = decodeJson(readFileAt(env.dir .. "data/leaderboard.json")).runs[1]
  assertEq(table.concat(run.copNames, ","), "Bob")
  env.cleanup()
end)

test("an unreachable runner cancels prep before any other player replaces their car", function()
  local env = boot()
  env.names = { "Kim", "Bob", "Reinder" }
  env.loading = { [3] = true }
  env.sent = {}
  env.startRound()
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).reason, "cancelled")
  assertEq(countSent(env, "cnr_roundSetup"), 0)
  env.loading[3] = nil
  env.call("onPlayerJoin", 3)
  assertEq(decodeJson(sentTo(env, "cnr_lobby", 3)).active, false)
  env.cleanup()
end)

test("a prep reroll keeps the playing roster when the online list changes before the join callback", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Kim" }
  env.startRound()
  env.call("onPlayerDisconnect", 3)
  env.names[3], env.names[4] = "Dan", "Kim"
  env.panel(2, "reroll")
  env.sent = {}
  assertEq(env.call("onVehicleSpawn", 4, 0, 'USER:Kim:4-0:{"jbm":"etk800"}'), 1)
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  for _, pid in ipairs({3, 4}) do
    assertEq(sentTo(env, "cnr_roundSetup", pid), nil)
    assertEq(decodeJson(sentTo(env, "cnr_spectate", pid)).phase, "prep")
    env.call("onPlayerJoin", pid)
    env.call("cnr_myVehicle", pid, '{"vid":0}')
    assertEq(env.call("onVehicleSpawn", pid, 0, '{"jbm":"pickup"}'), 1)
  end
  assertEq(countSent(env, "cnr_roundSetup"), 2)
  env.cleanup()
end)

test("a mid-round rejoiner also gets them", function()
  local env = boot()
  env.startRound()
  env.call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}')
  env.go()
  for _ = 1, 40 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("onPlayerDisconnect", 2)
  env.call("onPlayerJoin", 2)
  assertEq(sentTo(env, "cnr_rules", 2) ~= nil, true)
  assertEq(sentTo(env, "cnr_lobby", 2):find('"active":true', 1, true) ~= nil, true)
  assertEq(sentTo(env, "cnr_myColor", 2) ~= nil, true)
  assertEq(sentTo(env, "cnr_spectate", 2):find('"phase":"running"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("saving a setting re-sends the rules", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"headStartSeconds":9}}')
  local last = env.lastSent("cnr_rules")
  assertEq(last.pid, -1)
  assertEq(last.data:find('"headStartSeconds":9', 1, true) ~= nil, true)
  env.cleanup()
end)

test("lobby shows a practice round by someone", function()
  local env = boot()
  env.panel(1, "test runner")
  env.call("cnr_tick")
  local l = env.lastSent("cnr_lobby")
  assertEq(l.pid, -1)
  assertEq(l.data:find('"practice":"Reinder"', 1, true) ~= nil, true)
  assertEq(l.data:find('"active":false', 1, true) ~= nil, true)
  env.cleanup()
end)

test("lobby online count follows players", function()
  local env = boot()
  env.names = { "Reinder" }
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_lobby").data:find('"online":1', 1, true) ~= nil, true)
  env.cleanup()
end)

test("lobby is only re-sent when it changes", function()
  local env = boot()
  env.call("cnr_tick")
  local n = #env.sent
  env.call("cnr_tick")
  for i = n + 1, #env.sent do assertEq(env.sent[i].ev == "cnr_lobby", false) end
  env.names = { "Reinder" }
  n = #env.sent
  env.call("cnr_tick")
  local resent = false
  for i = n + 1, #env.sent do if env.sent[i].ev == "cnr_lobby" then resent = true end end
  assertEq(resent, true)
  env.cleanup()
end)

test("a lobby change still goes out when the panel push errors", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.call("cnr_tick")
  env.names = { "Reinder" }
  env.sent = {}
  local realGet, failed = MP.GetPlayers, 0
  MP.GetPlayers = function()
    MP.GetPlayers = realGet
    failed = failed + 1
    error("boom")
  end
  capturingLogs(function() env.call("cnr_tick") end)
  MP.GetPlayers = realGet
  assertEq(failed, 1)
  assertEq(decodeJson(assert(env.lastSent("cnr_lobby")).data).online, 1)
  env.cleanup()
end)

test("a parts change is noted and saved", function()
  local env = boot()
  env.startRound(); env.go()
  placed(env)
  env.call("onVehicleEdited", 1, 0, BASE_EDIT)
  for _ = 1, 40 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("onVehicleEdited", 1, 0, TUNED_EDIT)
  for _ = 1, 4 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  local text = readFileAt(env.dir .. "data/leaderboard.json")
  assertEq(text:find("partsChanged", 1, true) ~= nil, true)
  env.cleanup()
end)

local function panelOf(env)
  env.call("cnr_panel", 1, '{"action":"open"}')
  return decodeJson(env.lastSent("cnr_panelState").data)
end

local function rowOf(st, name)
  for _, r in ipairs(st.players) do if r.name == name then return r end end
end

test("panel marks next and last runner", function()
  local env = boot()
  local st = panelOf(env)
  assertEq(#st.players, 2)
  assertEq(st.players[1].name, "Bob"); assertEq(st.players[2].name, "Reinder")
  assertEq(st.nextRunner == "Bob" or st.nextRunner == "Reinder", true); assertEq(st.lastRunner, nil)
  assertEq(rowOf(st, st.nextRunner).next, true)
  assertEq(rowOf(st, "Bob").role, nil)
  env.startRound()
  env.panel(1, "stop")
  st = panelOf(env)
  assertEq(st.lastRunner, "Reinder"); assertEq(rowOf(st, "Reinder").last, true)
  assertEq(st.nextRunner, "Bob")
  env.cleanup()
end)

test("only a round that really ends counts as a run, not a cancelled one", function()
  local env = boot()
  env.startRound()
  env.panel(1, "stop")
  assertEq(rowOf(panelOf(env), "Reinder").runs, 0)
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  assertEq(rowOf(panelOf(env), "Reinder").runs, 1)
  env.cleanup()
end)

test("prep rows show loading until the car is placed", function()
  local env = boot()
  env.vehicles[2][3] = "round car"
  env.startRound()
  local st = panelOf(env)
  assertEq(st.nextRunner, nil)
  assertEq(rowOf(st, "Reinder").role, "runner"); assertEq(rowOf(st, "Bob").role, "cop")
  assertEq(rowOf(st, "Bob").state, "loading")
  env.call("cnr_myVehicle", 2, '{"vid":3}')
  st = panelOf(env)
  assertEq(rowOf(st, "Bob").state, "ready")
  env.cleanup()
end)

test("panel state names the round car once it is picked", function()
  local env = boot()
  assertEq(panelOf(env).car, nil)
  env.panel(2, "start rein")
  assertEq(panelOf(env).car, nil)
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(panelOf(env).car, "pickup")
  env.panel(1, "stop")
  assertEq(panelOf(env).car, nil)
  env.cleanup()
end)

test("evolving prep blocks GO with the runner's name", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":0}'); env.call("cnr_myVehicle", 2, '{"vid":0}')
  local st = panelOf(env)
  assertEq(st.phase, "prep")
  assertEq(st.goBlocked, "Waiting for Reinder to apply the change")
  env.call("cnr_change", 1, '{"changes":[{"label":"Engine","from":"A","to":"B"}]}')
  st = panelOf(env)
  assertEq(rowOf(st, "Reinder").state, "changing"); assertEq(rowOf(st, "Reinder").change, "Engine")
  env.call("cnr_missing", 2, '{"parts":["meo_turbo","meo_intake"]}')
  st = panelOf(env)
  assertEq(rowOf(st, "Bob").state, "missing"); assertEq(rowOf(st, "Bob").missing, 2)
  env.cleanup()
end)

test("after a round with auto on the panel shows the next round", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 15}' })
  env.startRound(); env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.caught() then break end
  end
  local st = panelOf(env)
  assertEq(st.autoNext.seconds, 15); assertEq(st.autoNext.runner, "Bob")
  assertEq(st.lastResult.runner, "Reinder"); assertEq(st.lastResult.reason, "caught")
  assertEq(type(st.lastResult.seconds), "number")
  env.cleanup()
end)

local function editConfig(env, json)
  local file = assert(io.open(env.dir .. "config.json", "w"))
  assert(file:write(json))
  assert(file:close())
end

test("a disk edit survives a mid-round auto toggle and applies from the next round", function()
  local env = boot()
  env.startRound()
  editConfig(env, '{"headStartSeconds":9}')
  env.panel(1, "auto on")
  assertEq(decodeJson(readFileAt(env.dir .. "config.json")).headStartSeconds, 9)

  local function runnerGoSeconds()
    env.go()
    env.clock = env.clock + 3
    env.call("cnr_tick")
    return decodeJson(env.lastSent("cnr_runnerGo").data).headStartSeconds
  end
  assertEq(runnerGoSeconds(), 7)
  env.panel(2, "stop")
  env.startRound()
  assertEq(runnerGoSeconds(), 9)
  env.cleanup()
end)

test("a held-back change reaches players once at round end", function()
  local env = boot()
  runToChase(env)
  editConfig(env, '{"headStartSeconds":9}')
  env.panel(1, "auto on")
  assertEq(decodeJson(env.lastSent("cnr_rules").data).headStartSeconds, 7)
  env.call("onPlayerJoin", 2)
  assertEq(env.lastSent("cnr_rules").pid, 2)
  assertEq(decodeJson(env.lastSent("cnr_rules").data).headStartSeconds, 7)
  local offset = #env.sent
  env.panel(2, "end")
  assertEq(countSent(env, "cnr_rules", nil, offset), 1)
  assertEq(env.lastSent("cnr_rules").pid, -1)
  assertEq(decodeJson(env.lastSent("cnr_rules").data).headStartSeconds, 9)
  env.startRound()
  offset = #env.sent
  env.panel(2, "stop")
  assertEq(countSent(env, "cnr_rules", nil, offset), 0)
  env.cleanup()
end)

test("round end synchronizes traffic rules when a joiner received a different slot limit", function()
  for _, limits in ipairs({ { maxCars = 2, traffic = 1 }, { maxCars = 4, traffic = 3 } }) do
    local opts = { config = '{"trafficPerPlayer":5}', maxCars = 4 }
    local env = boot(opts)
    assertEq(decodeJson(env.lastSent("cnr_rules").data).trafficPerPlayer, 3)
    env.startRound()
    opts.maxCars = 2
    env.names = { "Reinder", "Bob", "Kim" }
    env.call("onPlayerJoin", 3)
    assertEq(decodeJson(sentTo(env, "cnr_rules", 3)).trafficPerPlayer, 1)
    opts.maxCars = limits.maxCars
    env.sent = {}
    env.panel(1, "stop")
    local update = env.lastSent("cnr_rules")
    env.cleanup()
    assert(update, "players missed the final traffic limit for MaxCars " .. limits.maxCars)
    assertEq(update.pid, -1)
    assertEq(decodeJson(update.data).trafficPerPlayer, limits.traffic)
  end
end)

test("a subscribed panel shows auto off at once during a chase", function()
  local env = boot({ config = '{"autoNextRound":true}' })
  runToChase(env)
  assertEq(panelOf(env).auto, true)
  editConfig(env, '{"headStartSeconds":9}')
  env.sent = {}
  env.panel(2, "auto off")
  local update = env.lastSent("cnr_panelState")
  assertEq(update.pid, 1)
  local state = decodeJson(update.data)
  assertEq(state.phase, "running")
  assertEq(state.auto, false)
  assertEq(state.settings.autoNextRound, false)
  assertEq(state.settings.headStartSeconds, 7)
  env.panel(2, "end")
  assertEq(decodeJson(env.lastSent("cnr_panelState").data).settings.headStartSeconds, 9)
  env.cleanup()
end)

test("a disk edit to the delay doesn't change the running round's next countdown", function()
  local env = boot({ config = '{"autoNextRound":false,"autoNextDelaySeconds":5}' })
  runToChase(env)
  editConfig(env, '{"autoNextDelaySeconds":15}')
  env.panel(1, "auto on")
  env.panel(2, "end")
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).autoNextSeconds, 5)
  local state = panelOf(env)
  assertEq(state.autoNext.seconds, 5)
  assertEq(state.settings.autoNextDelaySeconds, 15)
  env.cleanup()
end)

test("auto off mid-chase still stops the next countdown", function()
  local env = boot({ config = '{"autoNextRound":true,"autoNextDelaySeconds":5}' })
  runToChase(env)
  env.panel(1, "auto off")
  env.panel(2, "end")
  local ended = decodeJson(env.lastSent("cnr_roundEnd").data)
  assertEq(ended.reason, "called")
  assertEq(ended.autoNextSeconds, nil)
  env.sent = {}
  env.clock = env.clock + 5
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  env.cleanup()
end)

test("auto on with an unreadable config.json changes nothing and says so", function()
  local env = boot({ config = '{"autoNextRound":false}' })
  local path = env.dir .. "config.json"
  assert(os.remove(path))
  FS.CreateDirectory(path)
  local _, readError = require("arcade.store").read(path)
  assert(readError)
  env.sent = {}
  env.panel(1, "auto on")
  assertEq(env.replyHas("Could not save config.json"), true)
  assertEq(env.logHas(readError), true)
  assertEq(env.lastSent("cnr_rules"), nil)
  assertEq(env.lastSent("cnr_autoNext"), nil)
  local state = panelOf(env)
  assertEq(state.auto, false)
  assertEq(state.settings.autoNextRound, false)
  env.cleanup()
end)

test("a failed auto off keeps the scheduled next round", function()
  local env = boot({ config = '{"autoNextRound":true,"autoNextDelaySeconds":5}' })
  runToChase(env)
  env.panel(2, "end")
  editConfig(env, "{broken")
  env.sent = {}
  env.panel(1, "auto off")
  assertEq(env.replyHas("config.json is not valid JSON"), true)
  assertEq(env.lastSent("cnr_autoNext"), nil)
  env.clock = env.clock + 5
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_pickVehicle") ~= nil, true)
  env.cleanup()
end)

test("round setup tells every player the runner's name", function()
  local env = boot()
  env.startRound()
  assertEq(Util.JsonDecode(sentTo(env, "cnr_roundSetup", 2)).runnerName, "Reinder")
  assertEq(Util.JsonDecode(sentTo(env, "cnr_roundSetup", 1)).runnerName, "Reinder")
  env.cleanup()
end)

test("a practice round keeps the last real result on the panel", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.caught() then break end
  end
  assertEq(panelOf(env).lastResult.runner, "Reinder")
  env.panel(1, "test runner")
  assertEq(panelOf(env).lastResult.runner, "Reinder")
  env.panel(1, "stop")
  assertEq(panelOf(env).lastResult.runner, "Reinder")
  env.cleanup()
end)

test("station count", function()
  local env = boot()
  assertEq(panelOf(env).stationCount, 0)
  env.cleanup()
end)

local function runnersSeed(n)
  local runs = {}
  for i = 1, n do
    runs[i] = string.format('{"player":"P%d","key":"beammp:%d","survivedSeconds":%d,"map":"west_coast_usa","endedAt":%d}', i, 100 + i, 1000 - i, i)
  end
  return '{"format":2,"runs":[' .. table.concat(runs, ",") .. ']}'
end

test("the board marks the viewer's own rows and never leaks keys", function()
  local env = boot({ leaderboard = '{"format":2,"runs":[{"player":"Me","key":"beammp:11","survivedSeconds":50,"map":"west_coast_usa","endedAt":1},{"player":"Bob","key":"beammp:22","survivedSeconds":40,"map":"west_coast_usa","endedAt":2}]}' })
  env.ids = { [1] = { beammp = "11" }, [2] = { beammp = "22" } }
  env.call("cnr_board", 1, '{"action":"open"}')
  local d = sentTo(env, "cnr_boardState", 1)
  local runners = Util.JsonDecode(d).runners
  assertEq(runners[1].me, true); assertEq(runners[2].me, nil)
  assertEq(Util.JsonDecode(d).mine, nil)
  assertEq(d:find("beammp:", 1, true), nil)
  env.cleanup()
end)

test("rounds carry the same anonymous keys as players, so a renamed player keeps their rounds", function()
  local env = boot({ leaderboard = '{"format":2,"runs":[{"player":"Old","key":"beammp:11","survivedSeconds":50,"map":"west_coast_usa","endedAt":1,"cops":["beammp:22"],"copNames":["Bob"]},{"player":"New","key":"beammp:11","survivedSeconds":40,"map":"west_coast_usa","endedAt":2}]}' })
  env.call("cnr_board", 1, '{"action":"open"}')
  local d = sentTo(env, "cnr_boardState", 1)
  local s = Util.JsonDecode(d)
  local keyOf = {}
  for _, p in ipairs(s.players) do keyOf[p.name] = p.key end
  assertEq(keyOf["New"] ~= nil, true); assertEq(keyOf["Bob"] ~= nil, true)
  assertEq(s.rounds[1].playerKey, keyOf["New"])
  assertEq(s.rounds[2].playerKey, keyOf["New"])
  assertEq(s.rounds[2].cops[1].key, keyOf["Bob"])
  assertEq(d:find("beammp:", 1, true), nil)
  env.cleanup()
end)

test("a viewer outside the top 20 gets mine pinned", function()
  local env = boot({ leaderboard = runnersSeed(21) })
  env.ids = { [1] = { beammp = "121" }, [2] = { beammp = "101" } }
  env.call("cnr_board", 1, '{"action":"open"}')
  local s = Util.JsonDecode(sentTo(env, "cnr_boardState", 1))
  assertEq(#s.runners, 20)
  assertEq(s.mine.rank, 21); assertEq(s.mine.player, "P21"); assertEq(s.mine.survivedSeconds, 979)
  env.call("cnr_board", 2, '{"action":"open"}')
  assertEq(Util.JsonDecode(sentTo(env, "cnr_boardState", 2)).mine, nil)
  env.cleanup()
end)

test("more raises the rounds count and a filter keeps it", function()
  local env = boot({ leaderboard = runnersSeed(70) })
  env.call("cnr_board", 1, '{"action":"open"}')
  assertEq(#Util.JsonDecode(sentTo(env, "cnr_boardState", 1)).rounds, 30)
  env.call("cnr_board", 1, '{"action":"more"}')
  assertEq(#Util.JsonDecode(sentTo(env, "cnr_boardState", 1)).rounds, 60)
  env.call("cnr_board", 1, '{"action":"filter","map":"all"}')
  assertEq(#Util.JsonDecode(sentTo(env, "cnr_boardState", 1)).rounds, 60)
  env.cleanup()
end)

test("the board says when more rounds can be loaded", function()
  local env = boot({ leaderboard = runnersSeed(31) })
  env.call("cnr_board", 1, '{"action":"open"}')
  local s = Util.JsonDecode(sentTo(env, "cnr_boardState", 1))
  assertEq(#s.rounds, 30); assertEq(s.moreRounds, true)
  env.call("cnr_board", 1, '{"action":"more"}')
  s = Util.JsonDecode(sentTo(env, "cnr_boardState", 1))
  assertEq(#s.rounds, 31); assertEq(s.moreRounds, nil)
  env.cleanup()
  env = boot({ leaderboard = runnersSeed(30) })
  env.call("cnr_board", 1, '{"action":"open"}')
  s = Util.JsonDecode(sentTo(env, "cnr_boardState", 1))
  assertEq(#s.rounds, 30); assertEq(s.moreRounds, nil)
  env.cleanup()
end)

test("more stops at the rounds cap", function()
  local env = boot({ leaderboard = runnersSeed(301) })
  env.call("cnr_board", 1, '{"action":"open"}')
  for _ = 1, 10 do env.call("cnr_board", 1, '{"action":"more"}') end
  local s = Util.JsonDecode(sentTo(env, "cnr_boardState", 1))
  assertEq(#s.rounds, 300); assertEq(s.moreRounds, nil)
  env.cleanup()
end)

test("a saved run with an empty timeline reaches the board as tracked", function()
  local env = boot({ leaderboard = '{"format":2,"runs":[{"player":"Old","survivedSeconds":50,"map":"west_coast_usa","endedAt":1},{"player":"New","survivedSeconds":40,"map":"west_coast_usa","endedAt":2,"timeline":[]}]}' })
  env.call("cnr_board", 1, '{"action":"open"}')
  local rounds = Util.JsonDecode(sentTo(env, "cnr_boardState", 1)).rounds
  assertEq(rounds[1].player, "New"); assertEq(rounds[1].tracked, true); assertEq(rounds[1].timeline, nil)
  assertEq(rounds[2].player, "Old"); assertEq(rounds[2].tracked, nil)
  env.cleanup()
end)

test("cnr_top goes to each player with me on their own row only", function()
  local env = boot({ leaderboard = '{"format":2,"runs":[{"player":"Old","key":"beammp:22","survivedSeconds":999,"map":"west_coast_usa","endedAt":1}]}' })
  env.ids = { [1] = { beammp = "11" }, [2] = { beammp = "22" } }
  env.startRound(); env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local one = Util.JsonDecode(sentTo(env, "cnr_top", 1))
  local two = Util.JsonDecode(sentTo(env, "cnr_top", 2))
  assertEq(one.lines, nil)
  assertEq(one.rows[1].player, "Bob"); assertEq(one.rows[1].time, "16:39")
  assertEq(one.rows[1].me, nil)
  assertEq(two.rows[1].me, true)
  assertEq(one.rows[2].me, true)
  env.cleanup()
end)

local function trafficBoot(opts)
  opts = opts or {}
  if opts.maxCars == nil then opts.maxCars = 6 end
  if opts.config == nil then opts.config = '{"trafficPerPlayer":5}' end
  return boot(opts)
end

local function spawnOf(pid, vid, model, config)
  local vcf = config and ('{"partConfigFilename":"' .. config .. '"}') or "{}"
  return string.format('USER:%s:%d-%d:{"jbm":"%s","vcf":%s}', pid == 1 and "Reinder" or "Bob", pid, vid, model, vcf)
end

local function chase(env)
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
end

test("after the round car is placed, the game is told how much traffic to spawn", function()
  local env = trafficBoot()
  env.startRound()
  assertEq(env.lastSent("cnr_trafficStart"), nil)
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  local m = env.lastSent("cnr_trafficStart")
  assertEq(m.pid, 2)
  assertEq(m.data:find('"count":5', 1, true) ~= nil, true)
  env.cleanup()
  local small = trafficBoot({ maxCars = 4 })
  small.startRound()
  small.call("cnr_myVehicle", 2, '{"vid":0}')
  assertEq(small.lastSent("cnr_trafficStart").data:find('"count":3', 1, true) ~= nil, true)
  small.cleanup()
end)

test("with traffic for the runner only, only the runner's game spawns traffic, with the same count", function()
  local env = trafficBoot({ config = '{"trafficPerPlayer":5,"trafficRunnerOnly":true}' })
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  assertEq(env.lastSent("cnr_trafficStart"), nil)
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  local m = env.lastSent("cnr_trafficStart")
  assertEq(m.pid, 1)
  assertEq(m.data:find('"count":5', 1, true) ~= nil, true)
  env.cleanup()
end)

test("no traffic go-ahead by default, when disabled, or without room", function()
  local cases = {
    { maxCars = 6 },
    { maxCars = 1, config = '{"trafficPerPlayer":5}' },
    { maxCars = 6, config = '{"trafficPerPlayer":0}' },
  }
  for i, opts in ipairs(cases) do
    local env = boot(opts)
    env.startRound()
    env.call("cnr_myVehicle", 1, '{"vid":0}')
    env.call("cnr_myVehicle", 2, '{"vid":0}')
    assertEq(env.lastSent("cnr_trafficStart"), nil, "case " .. i)
    env.cleanup()
  end
end)

test("a driver who owns only traffic can spawn one validated round car alongside it", function()
  local env = trafficBoot({ vehicles = { [1] = { [0] = "x", [1] = "y", [2] = "z" }, [2] = { [0] = "x" } } })
  env.startRound()
  env.call("cnr_color", 1, '{"hex":"#00ff00"}')
  assertEq(env.call("onVehicleSpawn", 1, 3, spawnOf(1, 3, "etk800")), 1)
  assertEq(env.call("onVehicleSpawn", 1, 3, spawnOf(1, 3, "pickup", "vehicles/pickup/base.pc")), 0)
  env.vehicles[1][3] = "round car"
  assertEq(env.call("onVehicleSpawn", 1, 4, spawnOf(1, 4, "pickup", "vehicles/pickup/base.pc")), 1)
  env.call("cnr_myVehicle", 1, '{"vid":3}')
  assertEq(#env.removed, 0)
  assertEq(env.lastSent("cnr_trafficStart").pid, 1)
  env.cleanup()
end)

test("a traffic spawn before the go-ahead is refused", function()
  local env = trafficBoot()
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "etk800")), 1)
  env.cleanup()
end)

test("traffic spawns pass up to the count, the next is refused", function()
  local env = trafficBoot()
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  for vid = 1, 5 do
    assertEq(env.call("onVehicleSpawn", 2, vid, spawnOf(2, vid, "etk800")), 0, "spawn " .. vid)
    env.vehicles[2][vid] = "t"
  end
  assertEq(env.call("onVehicleSpawn", 2, 6, spawnOf(2, 6, "etk800")), 1)
  env.cleanup()
end)

test("owners can edit their pre-existing traffic before round registration without losing it", function()
  for _, mode in ipairs({ "normal", "practice", "watch" }) do
    local env = trafficBoot({ vehicles = { [1] = { [0] = "traffic", [2] = "personal" } } })
    if mode == "normal" then
      env.startRound()
    else
      if mode == "watch" then env.call("cnr_sitOut", 1, '{"on":true}') end
      env.panel(1, "test runner")
      env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
    end
    assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"etk800","vcf":{}}'), 0, mode)
    if mode ~= "watch" then
      env.call("cnr_myVehicle", 1, '{"vid":2}')
      assertEq(env.call("onVehicleEdited", 1, 2, '1-2:{"jbm":"etk800","vcf":{}}'), 1, mode)
    end
    env.cleanup()
  end
end)

test("with round traffic off, retained traffic can be edited and never takes over round-car tracking", function()
  local env = trafficBoot({ config = '{"trafficPerPlayer":0}' })
  env.startRound()
  placed(env, 2)
  env.vehicles[2][1] = "parked traffic"
  local edit = '2-1:{"jbm":"etk800","vcf":{}}'
  assertEq(env.call("onVehicleEdited", 2, 1, edit), 0)
  assertEq(env.call("onVehicleEdited", 2, 0, edit), 1)
  env.call("onVehicleDeleted", 2, 0)
  env.vehicles[2][0] = nil
  local queried = {}
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    queried[pid .. "-" .. tostring(vid)] = true
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  assertEq(queried["2-1"], nil)
  assertEq(env.call("onVehicleSpawn", 2, 9, spawnOf(2, 9, "pickup", "vehicles/pickup/base.pc")), 0)
  env.vehicles[2][9] = "round car"
  assertEq(env.call("onVehicleSpawn", 2, 10, spawnOf(2, 10, "pickup", "vehicles/pickup/base.pc")), 1)
  env.cleanup()
end)

test("a traffic edit is never deleted, never a parts change, and never becomes the player's car", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1)
  env.vehicles[1][3] = "t"
  assertEq(env.call("onVehicleEdited", 1, 3, '1-3:{"jbm":"etk800","vcf":{"parts":{"a":"1"}}}'), 0)
  assertEq(env.call("onVehicleEdited", 1, 3, '1-3:{"jbm":"etk800","vcf":{"parts":{"a":"2"}}}'), 0)
  assertEq(partsLines(env), 0)
  env.go()
  for _ = 1, 34 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("onVehicleReset", 1, 3, "")
  assertEq(env.noticeHas("reset illegally"), false)
  env.call("onVehicleReset", 1, 0, "")
  assertEq(env.noticeHas("Reinder reset illegally", "warn"), true)
  env.cleanup()
end)

test("a repaint after the go-ahead removes no traffic", function()
  local env = trafficBoot()
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  env.vehicles[2] = { [0] = "x", [3] = "t", [4] = "t" }
  env.call("cnr_color", 2, '{"hex":"#00ff00"}')
  assertEq(env.lastSent("cnr_paint").pid, 2)
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  assertEq(#env.removed, 0)
  env.cleanup()
end)

test("in practice the issuer may spawn traffic of any model, but its own car stays checked", function()
  local env = trafficBoot({ vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(env.lastSent("cnr_trafficStart").data:find('"count":3', 1, true) ~= nil, true)
  assertEq(env.call("onVehicleSpawn", 1, 5, spawnOf(1, 5, "etk800")), 0)
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"etk800","vcf":{"parts":{}}}'), 1)
  env.clock = env.clock + 4
  env.call("onVehicleEdited", 1, 0, BASE_EDIT)
  env.call("onVehicleEdited", 1, 0, TUNED_EDIT)
  assertEq(partsLines(env), 1)
  env.cleanup()
end)

test("round-car announcements wait for each driver's confirmed vehicle", function()
  local env = trafficBoot({vehicles={[1]={[0]="spare", [4]="round"}, [2]={[0]="round"}}})
  env.panel(2, "start rein")
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(sentTo(env, "cnr_roundCars", -1), nil)
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", -1)).keys, ","), "2-0")
  env.call("onPlayerJoin", 3)
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", 3)).keys, ","), "2-0")
  env.sent = {}
  env.call("cnr_myVehicle", 2, '{"vid":4}')
  assertEq(sentTo(env, "cnr_roundCars", -1), nil)
  env.call("cnr_myVehicle", 1, '{"vid":4}')
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", -1)).keys, ","), "1-4,2-0")
  env.cleanup()
end)

test("a failed reroll setup removes the cop's old car for current and joining clients", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1)
  placed(env, 2)
  env.panel(1, "reroll")
  env.loading = { [2] = true }
  env.call("cnr_vehiclePicked", 1, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", -1)).keys, ","), "1-0")
  env.call("onPlayerJoin", 3)
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", 3)).keys, ","), "1-0")
  env.cleanup()
end)

test("everyone learns the round cars, and they're cleared at round end", function()
  local env = trafficBoot()
  env.vehicles[2][3] = "round car"
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  env.call("cnr_myVehicle", 2, '{"vid":3}')
  local m = env.lastSent("cnr_roundCars")
  assertEq(m.pid, -1)
  assertEq(m.data:find('"1-0"', 1, true) ~= nil, true)
  assertEq(m.data:find('"2-3"', 1, true) ~= nil, true)
  env.panel(1, "stop")
  m = env.lastSent("cnr_roundCars")
  assertEq(m.pid, -1)
  assertEq(m.data:find('"keys":{}', 1, true) ~= nil or m.data:find('"keys":[]', 1, true) ~= nil, true)
  env.cleanup()
  local p = trafficBoot({ vehicles = { [1] = { [0] = "x" } } })
  p.panel(1, "test runner")
  p.positions[1] = 0
  p.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  p.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(p.lastSent("cnr_roundCars").pid, -1)
  p.cleanup()
end)

test("a deleted round car never hands the player's checks to a traffic car", function()
  local env = trafficBoot()
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  env.vehicles[2] = { [0] = "x", [3] = "t" }
  env.call("onVehicleDeleted", 2, 0)
  env.vehicles[2] = { [3] = "t" }
  local asked = {}
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    asked[pid .. "-" .. tostring(vid)] = true
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  MP.GetPositionRaw = raw
  assertEq(asked["2-3"], nil)
  env.cleanup()
end)

test("with the round car gone, traffic resets are ignored and a round car can be put back", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1)
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  env.vehicles[2] = { [0] = "x", [1] = "t", [2] = "t", [3] = "t", [4] = "t", [5] = "t" }
  chase(env)
  env.call("onVehicleDeleted", 2, 0)
  env.vehicles[2][0] = nil
  env.call("onVehicleReset", 2, 3, "")
  assertEq(env.noticeHas("reset illegally"), false)
  assertEq(env.call("onVehicleEdited", 2, 3, '2-3:{"jbm":"etk800","vcf":{}}'), 0)
  assertEq(env.call("onVehicleSpawn", 2, 9, spawnOf(2, 9, "pickup", "vehicles/pickup/base.pc")), 0)
  assertEq(env.call("onVehicleSpawn", 2, 10, spawnOf(2, 10, "etk800")), 1)
  env.vehicles[2][9] = "x"
  assertEq(env.call("onVehicleSpawn", 2, 11, spawnOf(2, 11, "pickup", "vehicles/pickup/base.pc")), 1)
  env.cleanup()
end)

test("above the configured traffic allowance one validated replacement is broadcast after deletion or a new car setup", function()
  for _, reroll in ipairs({ false, true }) do
    local env = trafficBoot({ config = '{"trafficPerPlayer":1}', maxCars = 10 })
    env.startRound()
    env.call("cnr_myVehicle", 2, '{"vid":0}')
    env.vehicles[2] = { [0] = "round car", [1] = "traffic", [2] = "parked traffic" }
    if reroll then
      env.panel(1, "reroll")
      assertEq(env.call("onVehicleSpawn", 2, 3, spawnOf(2, 3, "etk800")), 1)
      env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
    else
      env.call("onVehicleDeleted", 2, 0)
      env.vehicles[2][0] = nil
      assertEq(env.lastSent("cnr_roundCars").data:find('"2-0"', 1, true), nil)
    end
    assertEq(env.call("onVehicleSpawn", 2, 3, spawnOf(2, 3, "etk800")), 1)
    assertEq(env.call("onVehicleSpawn", 2, 3, spawnOf(2, 3, "pickup", "vehicles/pickup/sport.pc")), 1)
    assertEq(env.call("onVehicleSpawn", 2, 3, spawnOf(2, 3, "pickup", "vehicles/pickup/base.pc")), 0)
    env.vehicles[2][3] = "replacement"
    assertEq(env.lastSent("cnr_roundCars").data:find('"2-3"', 1, true) ~= nil, true)
    assertEq(env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "pickup", "vehicles/pickup/base.pc")), 1)
    assertEq(env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "etk800")), 1)
    env.cleanup()
  end
end)

test("a New car re-pick lets no extra car past the cap", function()
  local env = trafficBoot()
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  env.vehicles[2] = { [0] = "x", [1] = "t", [2] = "t", [3] = "t", [4] = "t", [5] = "t" }
  env.panel(1, "reroll")
  assertEq(env.lastSent("cnr_pickVehicle") ~= nil, true)
  assertEq(env.call("onVehicleSpawn", 2, 9, spawnOf(2, 9, "etk800")), 1)
  env.cleanup()
end)

test("a returning spectator sees the round cars and cannot register or spawn their old car", function()
  local env = trafficBoot()
  env.names = { "Reinder", "Bob", "Kim" }
  env.startRound()
  placed(env, 1); placed(env, 2); placed(env, 3)
  chase(env)
  env.call("onPlayerDisconnect", 3)
  assertEq(env.call("onVehicleSpawn", 3, 0, spawnOf(3, 0, "etk800")), 1)
  env.sent = {}
  env.call("onPlayerJoin", 3)
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  assertEq(decodeJson(sentTo(env, "cnr_spectate", 3)).phase, "running")
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", 3)).keys, ","), "1-0,2-0")
  env.vehicles[3] = { [0] = "x", [1] = "y" }
  env.call("cnr_myVehicle", 3, '{"vid":0}')
  assertEq(sentTo(env, "cnr_trafficStart", 3), nil)
  assertEq(sentTo(env, "cnr_roundCars", -1), nil)
  assertEq(#env.removed, 0)
  assertEq(env.call("onVehicleSpawn", 3, 0, spawnOf(3, 0, "pickup", "vehicles/pickup/base.pc")), 1)
  assertEq(env.noticeHas("You can't spawn a car while spectating"), true)
  env.cleanup()
end)

local function trafficCrash(env)
  env.startRound()
  placed(env, 1); placed(env, 2)
  env.call("cnr_trafficCars", 1, '{"vids":[5]}')
  env.vidPositions["1-5"] = { pos = { 208, 0, 0 }, vel = { 0, 0, 0 } }
  chase(env)
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 and vid == 0 then return { pos = { 200, 0, 0 }, vel = { 120 / 3.6, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 and vid == 0 then return { pos = { 201, 0, 0 }, vel = { 0, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  MP.GetPositionRaw = raw
end

test("a cop who drives into reported traffic gets (traffic) in the notice", function()
  local env = trafficBoot()
  trafficCrash(env)
  assertEq(env.noticeHas("Bob: crash penalty 10s (traffic)", "warn"), true)
  env.cleanup()
end)

test("How to play gets the effective traffic", function()
  local env = trafficBoot({ maxCars = 4 })
  assertEq(env.lastSent("cnr_rules").data:find('"trafficPerPlayer":3', 1, true) ~= nil, true)
  env.cleanup()
end)

test("in driven practice a spawn before cnr_myVehicle doesn't release AI setup", function()
  local env = trafficBoot({ maxCars = 4, vehicles = { [1] = {} } })
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assert(env.lastSent("cnr_roundSetup"))
  assertEq(env.call("onVehicleSpawn", 1, 4, spawnOf(1, 4, "pickup", "vehicles/pickup/base.pc")), 0)
  env.vehicles[1][4] = "pickup"
  env.clock = 0.25
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_setupAI"), nil)
  env.call("cnr_myVehicle", 1, '{"vid":4}')
  env.clock = 0.5
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_setupAI").pid, 1)
  env.cleanup()
end)

test("practice reserves AI slots until the server sees the owner's late spare removed", function()
  for _, watch in ipairs({ false, true }) do
    local env = trafficBoot({ maxCars = 4, vehicles = { [1] = { [0] = "car", [1] = "spare", [2] = "late spare" } } })
    if watch then env.call("cnr_sitOut", 1, '{"on":true}') end
    env.panel(1, "test runner")
    env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
    assertEq(env.lastSent("cnr_setupAI"), nil)
    if not watch then env.call("cnr_myVehicle", 1, '{"vid":0}') end
    env.clock = 0.25
    env.call("cnr_tick")
    assertEq(env.lastSent("cnr_setupAI"), nil)
    assertEq(env.lastSent("cnr_trafficStart"), nil)
    env.vehicles[1][2] = nil
    if watch then env.vehicles[1][0] = nil else env.vehicles[1][1] = nil end
    env.clock = 0.5
    env.call("cnr_tick")
    assertEq(#decodeJson(env.lastSent("cnr_setupAI").data).ai, watch and 3 or 2)
    if not watch then assertEq(env.lastSent("cnr_trafficStart").pid, 1) end
    env.sent = {}
    env.call("cnr_tick")
    assertEq(env.lastSent("cnr_setupAI"), nil)
    env.cleanup()
  end
end)

test("a practice reroll supersedes pending AI and waits for the new human car even when space opens", function()
  local env = trafficBoot({ maxCars = 3, vehicles = { [1] = { [0] = "car", [1] = "late spare" } } })
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  env.panel(1, "reroll")
  env.vehicles[1][1] = nil
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_setupAI"), nil)
  env.call("cnr_vehiclePicked", 1, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  assertEq(env.lastSent("cnr_setupAI"), nil)
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(decodeJson(env.lastSent("cnr_setupAI").data).model, "etk800")
  env.cleanup()
end)

test("practice releases bystanders if the round car never registers and a later practice can start", function()
  for _, maxCars in ipairs({1, 4}) do
    local env = trafficBoot({maxCars = maxCars})
    local pick = '{"model":"pickup","config":"vehicles/pickup/base.pc"}'
    env.panel(1, "test runner")
    env.call("cnr_vehiclePicked", 1, pick)
    env.clock = 16
    env.call("cnr_tick")
    local ended = env.lastSent("cnr_roundEnd")
    assert(ended and ended.pid == 1, "practice did not end after the placement timeout")
    assertEq(env.noticeHas("round car", "warn"), true)
    assertEq(decodeJson(sentTo(env, "cnr_parkBystanderCars", 2)).on, false)
    env.call("cnr_myVehicle", 1, '{"vid":0}')
    assertEq(env.lastSent("cnr_setupAI"), nil)
    env.panel(1, "test runner")
    env.call("cnr_vehiclePicked", 1, pick)
    env.clock = env.clock + 14
    env.call("cnr_tick")
    env.call("cnr_myVehicle", 1, '{"vid":0}')
    assertEq(#decodeJson(env.lastSent("cnr_setupAI").data).ai, 2)
    env.cleanup()
  end
end)

test("practice with no room for all AI ends and releases bystanders without deleting retained traffic", function()
  local env = trafficBoot({ maxCars = 3, vehicles = { [1] = { [0] = "round car", [1] = "parked traffic" } } })
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  env.clock = 16
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_setupAI"), nil)
  assertEq(env.lastSent("cnr_roundEnd").pid, 1)
  assertEq(env.noticeHas("vehicle slots", "warn"), true)
  assertEq(decodeJson(env.lastSent("cnr_parkBystanderCars").data).on, false)
  assertEq(#env.removed, 0)
  env.cleanup()
end)

test("the panel shows the traffic note", function()
  local env = trafficBoot({ maxCars = 4 })
  env.call("cnr_panel", 1, '{"action":"open"}')
  assertEq(env.lastSent("cnr_panelState").data:find('"trafficNote":"MaxCars is 4 on this server: 3 per player"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("with traffic for the runner only, the panel's traffic note says so", function()
  local env = trafficBoot({ maxCars = 4, config = '{"trafficPerPlayer":5,"trafficRunnerOnly":true}' })
  env.call("cnr_panel", 1, '{"action":"open"}')
  assertEq(env.lastSent("cnr_panelState").data:find('"trafficNote":"MaxCars is 4 on this server: 3 for the runner"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a recorded run keeps its traffic, and a traffic crash's cause survives the save", function()
  local env = trafficBoot()
  trafficCrash(env)
  env.panel(2, "end")
  local saved = assert(io.open(env.dir .. "data/leaderboard.json")):read("*a")
  assertEq(saved:find('"traffic":5', 1, true) ~= nil, true)
  assertEq(saved:find('"cause":"traffic"', 1, true) ~= nil, true)
  env.cleanup()
  local plain = boot({ maxCars = 1 })
  plain.startRound()
  chase(plain)
  plain.panel(2, "end")
  local text = assert(io.open(plain.dir .. "data/leaderboard.json")):read("*a")
  assertEq(text:find('"traffic"', 1, true), nil)
  plain.cleanup()
end)

test("reported traffic keeps out the player's own car and stops at the count", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1); placed(env, 2)
  env.call("cnr_trafficCars", 2, '{"vids":[0,1,2,3,4,5,6,7]}')
  chase(env)
  local asked = {}
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 then asked[vid] = true end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  MP.GetPositionRaw = raw
  local others = 0
  for vid in pairs(asked) do if vid ~= 0 then others = others + 1 end end
  assertEq(asked[0], true)
  assertEq(others, 5)
  env.cleanup()
end)

test("the board app can filter by traffic", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.call("cnr_board", 2, '{"action":"filter","map":"all","traffic":"with"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"traffic":"with"', 1, true) ~= nil, true)
  env.call("cnr_board", 2, '{"action":"filter","map":"all","traffic":"runner"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"traffic":"runner"', 1, true) ~= nil, true)
  env.call("cnr_board", 2, '{"action":"filter","map":"all"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"traffic":"all"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a recorded run keeps traffic for the runner only", function()
  local env = trafficBoot({ config = '{"trafficPerPlayer":5,"trafficRunnerOnly":true}' })
  env.startRound()
  chase(env)
  env.panel(2, "end")
  local saved = assert(io.open(env.dir .. "data/leaderboard.json")):read("*a")
  assertEq(saved:find('"traffic":5', 1, true) ~= nil, true)
  assertEq(saved:find('"trafficRunnerOnly":true', 1, true) ~= nil, true)
  env.cleanup()
  local everyone = trafficBoot()
  everyone.startRound()
  chase(everyone)
  everyone.panel(2, "end")
  local text = assert(io.open(everyone.dir .. "data/leaderboard.json")):read("*a")
  assertEq(text:find('"traffic":5', 1, true) ~= nil, true)
  assertEq(text:find('"trafficRunnerOnly"', 1, true), nil)
  everyone.cleanup()
end)

local function step(env)
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
end

local function logCount(env, text)
  local n = 0
  for _, l in ipairs(env.logs) do if l:find(text, 1, true) then n = n + 1 end end
  return n
end

test("a refused car is logged at most once per 10 s per player", function()
  local env = boot()
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  for _ = 1, 3 do assertEq(env.call("onVehicleSpawn", 2, 7, spawnOf(2, 7, "etk800")), 1) end
  assertEq(logCount(env, "Bob spawned etk800 (vid 7): refused"), 1)
  for _ = 1, 39 do step(env) end
  assertEq(env.call("onVehicleEdited", 2, 0, '2-0:{"jbm":"etk800","vcf":{}}'), 1)
  assertEq(env.logHas("Bob edited etk800 (vid 0): refused"), false)
  step(env)
  assertEq(env.call("onVehicleSpawn", 2, 7, spawnOf(2, 7, "etk800")), 1)
  assertEq(logCount(env, "Bob spawned etk800 (vid 7): refused"), 2)
  env.cleanup()
end)

local PICK = '{"model":"pickup","config":"vehicles/pickup/base.pc"}'

local function sitOut(env, pid, on)
  env.call("cnr_sitOut", pid, on and '{"on":true}' or '{"on":false}')
end

local function threePlayers(opts)
  local env = boot(opts)
  env.names = { "Reinder", "Bob", "Kim" }
  return env
end

test("practice parks only bystanders, including late joiners, and releases them when the issuer leaves", function()
  local env = boot()
  env.panel(1, "test cop")
  assertEq(env.lastSent("cnr_parkBystanderCars"), nil)
  env.call("cnr_vehiclePicked", 1, PICK)
  assertEq(sentTo(env, "cnr_parkBystanderCars", 1), nil)
  assertEq(decodeJson(sentTo(env, "cnr_parkBystanderCars", 2)).on, true)
  env.names = { "Reinder", "Bob", "Kim" }
  env.call("onPlayerJoin", 3)
  assertEq(decodeJson(sentTo(env, "cnr_parkBystanderCars", 3)).on, true)
  assertEq(sentTo(env, "cnr_spectate", 3), nil)
  assertEq(env.call("onVehicleSpawn", 3, 0, spawnOf(3, 0, "etk800")), 0)
  env.sent = {}
  env.panel(2, "reroll")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 1)
  env.call("cnr_vehiclePicked", 1, PICK)
  assertEq(env.lastSent("cnr_parkBystanderCars"), nil)
  env.call("onPlayerDisconnect", 2)
  env.call("onPlayerDisconnect", 1)
  assertEq(decodeJson(sentTo(env, "cnr_parkBystanderCars", 3)).on, false)
  assertEq(sentTo(env, "cnr_parkBystanderCars", 1), nil)
  assertEq(sentTo(env, "cnr_parkBystanderCars", 2), nil)
  env.cleanup()
end)

test("a practice end unparks bystanders before the issuer's roundEnd", function()
  local env = boot()
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, PICK)
  env.sent = {}
  env.panel(1, "stop")
  local unpark, ended
  for i, event in ipairs(env.sent) do
    if event.ev == "cnr_parkBystanderCars" and event.pid == 2 and decodeJson(event.data).on == false then
      unpark = i
    elseif event.ev == "cnr_roundEnd" and event.pid == 1 then
      ended = i
    end
  end
  assert(unpark and ended and unpark < ended, "expected Bob to be unparked before the issuer's roundEnd")
  env.cleanup()
end)

test("a practice bystander still loading gets the parking request on join", function()
  local env = boot()
  env.loading = { [2] = true }
  env.panel(1, "test cop")
  env.call("cnr_vehiclePicked", 1, PICK)
  assertEq(sentTo(env, "cnr_parkBystanderCars", 2), nil)
  env.loading[2] = nil
  env.call("onPlayerJoin", 2)
  local parking = sentTo(env, "cnr_parkBystanderCars", 2)
  assert(parking and decodeJson(parking).on, "joined with personal cars still on the map")
  env.cleanup()
end)

test("Sit out is answered, stored per player and cleared on disconnect", function()
  local env = threePlayers()
  env.sent = {}
  sitOut(env, 3, true)
  assertEq(decodeJson(sentTo(env, "cnr_sitOut", 3)).on, true)
  for _, bad in ipairs({ "{}", '{"on":"yes"}', "nope" }) do
    env.sent = {}
    env.call("cnr_sitOut", 3, bad)
    assertEq(#env.sent, 0)
  end
  env.panel(2, "start rein")
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  assertEq(sentTo(env, "cnr_spectate", 3) ~= nil, true)
  env.panel(1, "stop")
  env.call("onPlayerDisconnect", 3)
  env.sent = {}
  env.panel(2, "start rein")
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(sentTo(env, "cnr_roundSetup", 3) ~= nil, true)
  assertEq(sentTo(env, "cnr_spectate", 3), nil)
  env.cleanup()
end)

test("Start is refused only when everyone sits out", function()
  local env = boot()
  sitOut(env, 1, true)
  sitOut(env, 2, true)
  env.panel(2, "start next")
  assertEq(env.replyHas("Everyone is sitting out"), true)
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  sitOut(env, 2, false)
  env.panel(2, "start next")
  assertEq(env.lastSent("cnr_pickVehicle") ~= nil, true)
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 2)).role, "runner")
  assertEq(sentTo(env, "cnr_spectate", 1) ~= nil, true)
  env.cleanup()
  local alone = boot()
  alone.names = { "Reinder" }
  alone.panel(1, "start next")
  alone.call("cnr_vehiclePicked", 1, PICK)
  assertEq(decodeJson(sentTo(alone, "cnr_roundSetup", 1)).role, "runner")
  alone.cleanup()
end)

test("auto next round keeps going with one player who isn't sitting out", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  sitOut(env, 1, true)
  env.panel(2, "start next")
  env.call("cnr_vehiclePicked", 2, PICK)
  env.go()
  for _ = 1, 50 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(2, "end")
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_pickVehicle") ~= nil, true)
  env.call("cnr_vehiclePicked", env.lastSent("cnr_pickVehicle").pid, PICK)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 2)).role, "runner")
  env.cleanup()
end)

test("a sitting-out player is never the runner", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Ann" }
  env.panel(2, "start =Ann")
  env.call("cnr_vehiclePicked", 2, PICK)
  env.panel(1, "stop")
  sitOut(env, 3, true)
  env.panel(2, "start ann")
  assertEq(env.replyHas("Ann is sitting out"), true)
  env.panel(2, "start =Ann")
  assertEq(env.replyHas("Ann is sitting out"), true)
  env.panel(2, "start again")
  assertEq(env.replyHas("Ann is sitting out"), true)
  env.panel(2, "start next")
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 2)).runnerName ~= "Ann", true)
  env.panel(1, "stop")
  math.randomseed(7)
  for _ = 1, 12 do
    env.sent = {}
    env.panel(2, "start random")
    env.call("cnr_vehiclePicked", 2, PICK)
    assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 2)).runnerId ~= 3, true)
    env.panel(1, "stop")
  end
  env.cleanup()
end)

test("Sit out during a round applies to the next round and says so", function()
  local env = threePlayers()
  env.panel(2, "start rein")
  env.sent = {}
  sitOut(env, 3, true)
  assertEq(env.noticeHas("You sit out from the next round"), true)
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(sentTo(env, "cnr_roundSetup", 3) ~= nil, true)
  assertEq(sentTo(env, "cnr_spectate", 3), nil)
  env.panel(1, "stop")
  for _ = 1, 2 do
    env.sent = {}
    env.panel(2, "start rein")
    env.call("cnr_vehiclePicked", 2, PICK)
    assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
    assertEq(sentTo(env, "cnr_spectate", 3) ~= nil, true)
    if _ == 1 then env.panel(1, "stop") end
  end
  sitOut(env, 3, false)
  assertEq(env.noticeHas("You play again from the next round"), true)
  env.panel(1, "stop")
  env.sent = {}
  env.panel(2, "start rein")
  env.call("cnr_vehiclePicked", 2, PICK)
  assertEq(sentTo(env, "cnr_roundSetup", 3) ~= nil, true)
  env.panel(1, "stop")
  env.sent = {}
  sitOut(env, 3, true)
  assertEq(env.noticeHas("next round"), false)
  env.cleanup()
end)

test("a sitting-out player gets cnr_spectate at the pick, with the round's sky", function()
  local env = threePlayers({ config = '{"timeOfDay":"night","weather":"rain"}' })
  sitOut(env, 3, true)
  env.panel(2, "start rein")
  env.call("cnr_vehiclePicked", 2, PICK)
  local d = decodeJson(sentTo(env, "cnr_spectate", 3))
  assertEq(d.phase, "prep"); assertEq(d.runnerId, 1); assertEq(d.runnerName, "Reinder")
  assertEq(d.sky.time, "night"); assertEq(d.sky.weather, "rain")
  assertEq(env.logHas("Kim spectates (prep)"), true)
  env.cleanup()
end)

test("a player sitting out before the pick receives the storm clock after GO", function()
  local env = threePlayers({config = '{"weather":"thunderstorm"}'})
  sitOut(env, 3, true)
  env.startRound()
  local d = decodeJson(sentTo(env, "cnr_spectate", 3))
  env.go()
  env.call("cnr_lightningClock", 3, encode({seed = d.sky.lightningSeed, id = 2}))
  local reply = env.lastSent("cnr_lightningClock")
  assertEq(reply and reply.pid, 3)
  env.cleanup()
end)

test("a mid-chase joiner gets cnr_spectate with the chase time, the sky clock and the round cars, and no setup or traffic", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1); placed(env, 2)
  chase(env)
  env.names = { "Reinder", "Bob", "Kim" }
  env.sent = {}
  env.call("onPlayerJoin", 3)
  local d = decodeJson(sentTo(env, "cnr_spectate", 3))
  assertEq(d.phase, "running"); assertNear(d.chaseElapsed, 1, 0.01); assertNear(d.sky.clockSeconds, 11, 0.01)
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  assertEq(sentTo(env, "cnr_roundCars", 3) ~= nil, true)
  assertEq(sentTo(env, "cnr_lobby", 3):find('"active":true', 1, true) ~= nil, true)
  env.vehicles[3] = { [0] = "x", [1] = "y" }
  env.call("cnr_myVehicle", 3, '{"vid":0}')
  assertEq(sentTo(env, "cnr_trafficStart", 3), nil)
  assertEq(#env.removed, 0)
  env.cleanup()
end)

test("a spectator can't spawn a car until the round ends", function()
  local env = threePlayers()
  sitOut(env, 3, true)
  env.panel(2, "start rein")
  assertEq(env.call("onVehicleSpawn", 3, 5, '3:Kim:3-5:{"jbm":"etk800","vcf":{}}'), 0)
  env.call("cnr_vehiclePicked", 2, PICK)
  env.sent = {}
  assertEq(env.call("onVehicleSpawn", 3, 6, '3:Kim:3-6:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'), 1)
  assertEq(env.noticeHas("You can't spawn a car while spectating"), true)
  env.panel(1, "stop")
  assertEq(env.call("onVehicleSpawn", 3, 7, '3:Kim:3-7:{"jbm":"etk800","vcf":{}}'), 0)
  env.cleanup()
  local joined = boot()
  joined.startRound(); joined.go()
  joined.names = { "Reinder", "Bob", "Kim" }
  joined.call("onPlayerJoin", 3)
  assertEq(joined.call("onVehicleSpawn", 3, 0, '3:Kim:3-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'), 1)
  joined.call("onPlayerDisconnect", 3)
  joined.call("onPlayerJoin", 3)
  assertEq(joined.call("onVehicleSpawn", 3, 0, '3:Kim:3-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'), 1)
  joined.panel(1, "stop")
  assertEq(joined.call("onVehicleSpawn", 3, 1, '3:Kim:3-1:{"jbm":"etk800","vcf":{}}'), 0)
  joined.cleanup()
  local practice = boot()
  practice.panel(1, "test runner")
  practice.call("cnr_vehiclePicked", 1, PICK)
  assertEq(practice.call("onVehicleSpawn", 2, 3, '2:Bob:2-3:{"jbm":"etk800","vcf":{}}'), 0)
  practice.cleanup()
end)

test("New sky reaches spectators", function()
  local env = threePlayers({ config = '{"weather":"random"}' })
  sitOut(env, 3, true)
  env.startRound()
  env.sent = {}
  env.panel(1, "sky")
  assertEq(countSent(env, "cnr_sky", 1), 1); assertEq(countSent(env, "cnr_sky", 3), 1)
  env.cleanup()
end)

test("the panel marks sitting-out players, Next skips them and the traffic note counts only players", function()
  local env = trafficBoot()
  env.names = { "Reinder", "Bob", "Ann" }
  sitOut(env, 3, true)
  env.call("cnr_panel", 1, '{"action":"open"}')
  local st = decodeJson(env.lastSent("cnr_panelState").data)
  local rows = {}
  for _, row in ipairs(st.players) do rows[row.name] = row end
  assertEq(rows.Ann.sitOut, true); assertEq(rows.Bob.sitOut, nil)
  assertEq(st.nextRunner ~= "Ann" and st.nextRunner ~= nil, true)
  assertEq(st.trafficNote, "5 each · 10 cars with 2 players")
  env.cleanup()
end)

test("a name that fits several players still says so when one of them sits out", function()
  local env = boot()
  env.names = { "Reinder", "Ann", "Anna", "Andy" }
  sitOut(env, 4, true)
  env.panel(1, "start an")
  assertEq(env.replyHas("matches several players: Ann, Anna"), true)
  env.panel(1, "start and")
  assertEq(env.replyHas("Andy is sitting out"), true)
  env.cleanup()
end)

test("a player who joins in prep keeps spectating through New car, with spawns still refused", function()
  local env = boot()
  env.startRound()
  env.names = { "Reinder", "Bob", "Kim" }
  env.call("onPlayerJoin", 3)
  env.panel(2, "reroll")
  env.sent = {}
  env.call("cnr_vehiclePicked", 2, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  assertEq(sentTo(env, "cnr_roundSetup", 3), nil)
  assertEq(sentTo(env, "cnr_spectate", 3) ~= nil, true)
  assertEq(sentTo(env, "cnr_roundSetup", 1) ~= nil, true)
  assertEq(env.call("onVehicleSpawn", 3, 0, '3:Kim:3-0:{"jbm":"etk800","vcf":{"partConfigFilename":"vehicles/etk800/base.pc"}}'), 1)
  env.cleanup()
end)

local function runnerNamed(env)
  local d = decodeJson(env.lastSent("cnr_roundSetup").data)
  return env.names[d.runnerId]
end

test("the panel's next runner is the runner a Start next round gets, across rounds", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Kim", "Ann" }
  math.randomseed(5)
  for _ = 1, 6 do
    local planned = panelOf(env).nextRunner
    env.panel(1, "start next")
    env.call("cnr_vehiclePicked", 1, PICK)
    local setup
    for i = #env.sent, 1, -1 do
      local m = env.sent[i]
      if m.ev == "cnr_roundSetup" and decodeJson(m.data).role == "runner" then setup = decodeJson(m.data) break end
    end
    assertEq(env.names[setup.runnerId], planned)
    env.go()
    for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
    env.panel(1, "end")
  end
  env.cleanup()
end)

test("the planned next runner holds when someone joins and changes when it leaves or sits out", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Kim", "Ann" }
  math.randomseed(9)
  local planned = panelOf(env).nextRunner
  for _ = 1, 20 do assertEq(panelOf(env).nextRunner, planned) end
  env.names[5] = "Zed"
  env.call("onPlayerJoin", 5)
  assertEq(panelOf(env).nextRunner, planned)
  local pidOf
  for pid, n in pairs(env.names) do if n == planned then pidOf = pid end end
  sitOut(env, pidOf, true)
  local after = panelOf(env).nextRunner
  assertEq(after ~= planned, true)
  for _ = 1, 20 do assertEq(panelOf(env).nextRunner, after) end
  local pid2
  for pid, n in pairs(env.names) do if n == after then pid2 = pid end end
  env.names[pid2] = nil
  env.call("onPlayerDisconnect", pid2)
  local third = panelOf(env).nextRunner
  assertEq(third ~= after and third ~= planned, true)
  env.cleanup()
end)

test("two cycles of four players never repeat a runner back to back and the second order is drawn", function()
  local orders = {}
  for seed = 1, 12 do
    local env = boot()
    env.names = { "Reinder", "Bob", "Kim", "Ann" }
    math.randomseed(seed)
    local order, prev = {}, nil
    for i = 1, 8 do
      env.panel(1, "start next")
      env.call("cnr_vehiclePicked", 1, PICK)
      local name = runnerNamed(env)
      assertEq(name ~= prev, true)
      if i <= 4 then
        for j = 1, i - 1 do assertEq(order[j] ~= name, true) end
      end
      order[#order + 1] = name
      prev = name
      env.go()
      for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
      env.panel(1, "end")
    end
    orders[table.concat(order, ",", 1, 4) == table.concat(order, ",", 5, 8) and "same" or "diff"] = true
    orders[table.concat(order, ",", 1, 4)] = true
    env.cleanup()
  end
  assertEq(orders.diff, true)
  local alpha = 0
  for k in pairs(orders) do if k == "Ann,Bob,Kim,Reinder" then alpha = alpha + 1 end end
  assertEq(alpha <= 1, true)
end)

local AI_SPAWN = 'USER:Reinder:1-%d:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'

test("practice while sitting out runs the AI alone, the issuer spectates and nothing is recorded", function()
  for _, cmd in ipairs({ "test runner", "test cop" }) do
    local env = boot()
    sitOut(env, 1, true)
    env.sent = {}
    env.panel(1, cmd)
    assertEq(env.lastSent("cnr_pickVehicle").pid, 1)
    env.call("cnr_vehiclePicked", 1, PICK)
    assertEq(env.lastSent("cnr_roundSetup"), nil, cmd)
    local d = decodeJson(sentTo(env, "cnr_spectate", 1))
    assertEq(d.phase, "prep"); assertEq(d.practice, nil); assertEq(d.runnerName, "AI runner")
    assertEq(sentTo(env, "cnr_spectate", 2), nil)
    local s = decodeJson(sentTo(env, "cnr_setupAI", 1))
    assertEq(s.aiOnly, true); assertEq(#s.ai, 3)
    assertEq(s.ai[1].role, "runner"); assertEq(s.ai[2].name, "AI cop 1"); assertEq(s.ai[3].name, "AI cop 2")
    for vid = 1, 3 do
      assertEq(env.call("onVehicleSpawn", 1, vid, string.format(AI_SPAWN, vid)), 0, cmd)
      env.vehicles[1][vid] = "pickup"
    end
    env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":1},{"id":-11,"vid":2},{"id":-12,"vid":3}]}')
    env.vidPositions["1-1"] = { pos = { 0, 0, 0 }, vel = { 0, 0, 0 } }
    env.vidPositions["1-2"] = { pos = { 5, 0, 0 }, vel = { 0, 0, 0 } }
    env.vidPositions["1-3"] = { pos = { 500, 0, 0 }, vel = { 0, 0, 0 } }
    env.go()
    for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
    assertEq(env.caught(), true, cmd)
    for _, m in ipairs(env.sent) do
      if m.ev == "cnr_parkBystanderCars" then
        assertEq(m.pid, 2)
      elseif m.ev ~= "cnr_lobby" or m.pid ~= -1 then
        assertEq(m.pid, 1, m.ev)
      end
    end
    assertEq(io.open(env.dir .. "data/leaderboard.json"), nil)
    assertEq(env.call("onVehicleSpawn", 1, 4, string.format(AI_SPAWN, 4)), 0)
    env.cleanup()
  end
end)

test("an evolving practice with an AI runner has no change to apply: prep is ready and GO starts it", function()
  for _, sitting in ipairs({ false, true }) do
    local env = boot()
    evolving(env); newBuild(env)
    if sitting then sitOut(env, 1, true) end
    env.sent = {}
    env.panel(1, "test cop")
    local setup = sitting and sentTo(env, "cnr_spectate", 1) or sentTo(env, "cnr_roundSetup", 1)
    assertEq(decodeJson(setup).phase, "ready", tostring(sitting))
    local st = panelOf(env)
    assertEq(st.can.go, true); assertEq(st.can.apply, false); assertEq(st.goBlocked, nil)
    env.call("cnr_panel", 1, '{"action":"apply"}')
    assertEq(env.lastSent("cnr_requestSetup"), nil)
    assertEq(env.lastSent("cnr_applied"), nil)
    env.go()
    assertEq(env.lastSent("cnr_countdown") ~= nil, true, tostring(sitting))
    env.cleanup()
  end
end)

test("an evolving practice as runner still waits for the runner's change", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.panel(1, "test runner")
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 1)).phase, "prep")
  env.go()
  assertEq(env.lastSent("cnr_countdown"), nil)
  env.call("cnr_panel", 1, '{"action":"apply"}')
  assertEq(env.lastSent("cnr_requestSetup").pid, 1)
  env.cleanup()
end)

test("someone else sitting out leaves practice as it was", function()
  local env = boot()
  sitOut(env, 2, true)
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, PICK)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 1)).role, "runner")
  assertEq(sentTo(env, "cnr_spectate", 1), nil); assertEq(sentTo(env, "cnr_spectate", 2), nil)
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(decodeJson(sentTo(env, "cnr_setupAI", 1)).aiOnly, nil)
  env.cleanup()
end)

test("New sky reaches whoever watches an AI-only practice", function()
  local env = boot({ config = '{"weather":"random"}' })
  sitOut(env, 1, true)
  env.panel(1, "test cop")
  env.call("cnr_vehiclePicked", 1, PICK)
  env.sent = {}
  env.panel(1, "sky")
  assertEq(countSent(env, "cnr_sky", 1), 1); assertEq(countSent(env, "cnr_sky", 2), 0)
  env.cleanup()
end)

test("the lobby names whoever watches the AI practise, and their leaving ends it", function()
  local env = boot()
  sitOut(env, 1, true)
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, PICK)
  env.call("cnr_tick")
  local l = env.lastSent("cnr_lobby")
  assertEq(l.data:find('"practice":"Reinder"', 1, true) ~= nil, true)
  env.call("onPlayerDisconnect", 1)
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).reason, "cancelled")
  env.names = { [2] = "Bob" }
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_lobby").data:find('"practice"', 1, true), nil)
  env.cleanup()
end)

test("a watched practice refuses the issuer's own spawns and model changes, but not the AI cars or the restore after", function()
  local env = boot()
  sitOut(env, 1, true)
  env.panel(1, "test cop")
  assertEq(env.call("onVehicleEdited", 1, 2, string.format(AI_SPAWN, 2)), 0)
  assertEq(env.call("onVehicleSpawn", 1, 3, string.format(AI_SPAWN, 3)), 1)
  env.call("cnr_vehiclePicked", 1, PICK)
  env.sent = {}
  for vid = 1, 3 do assertEq(env.call("onVehicleSpawn", 1, vid, string.format(AI_SPAWN, vid)), 0, vid) end
  assertEq(env.call("onVehicleSpawn", 1, 4, string.format(AI_SPAWN, 4)), 1)
  assertEq(env.noticeHas("You can't spawn a car while watching the AI", "warn"), true)
  assertEq(env.call("onVehicleSpawn", 1, 5, 'USER:Reinder:1-5:{"jbm":"etk800","vcf":{}}'), 1)
  assertEq(env.call("onVehicleEdited", 1, 2, 'USER:Reinder:1-2:{"jbm":"etk800","vcf":{}}'), 1)
  assertEq(env.noticeHas("Only the round car is allowed", "warn"), true)
  assertEq(env.call("onVehicleEdited", 1, 2, string.format(AI_SPAWN, 2)), 0)
  assertEq(env.call("onVehicleSpawn", 2, 7, '2:Bob:2-7:{"jbm":"etk800","vcf":{}}'), 0)
  env.panel(1, "reroll")
  env.call("cnr_vehiclePicked", 1, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  env.sent = {}
  assertEq(env.call("onVehicleEdited", 1, 2, string.format(AI_SPAWN, 2)), 1)
  assertEq(#env.sent, 1)
  local warning = env.sent[1]
  assertEq(warning.ev, "cnr_notice"); assertEq(warning.pid, 1)
  local notice = decodeJson(warning.data)
  assertEq(notice.msg, "Only the round car is allowed"); assertEq(notice.tone, "warn")
  for vid = 8, 10 do assertEq(env.call("onVehicleSpawn", 1, vid, spawnOf(1, vid, "etk800")), 0, vid) end
  assertEq(env.call("onVehicleSpawn", 1, 11, spawnOf(1, 11, "etk800")), 1)
  env.panel(1, "stop")
  assertEq(env.call("onVehicleSpawn", 1, 12, 'USER:Reinder:1-12:{"jbm":"etk800","vcf":{}}'), 0)
  env.cleanup()
end)

local function westCoastStart(client)
  client.veh.pos = vec3(-360.06, 619.75, 75.05)
  client.veh.getDirectionVector = function() return vec3(-1, 0, 0) end
  local points = {
    { "wp25", -432.85, 681.35 }, { "wp19", -395.25, 643.95 }, { "wp31", -380.15, 636.80 },
    { "wp30", -364.93, 621.97 }, { "wp29", -355.37, 621.09 },
  }
  local nodes, graph = {}, {}
  for i, p in ipairs(points) do
    nodes[p[1]], graph[p[1]] = { pos = vec3(p[2], p[3], 74.9) }, {}
    if i > 1 then
      local u = points[i - 1][1]
      local link = { inNode = u, oneWay = true }
      graph[u][p[1]], graph[p[1]][u] = link, link
    end
  end
  map.getMap = function() return { nodes = nodes } end
  map.getGraphpath = function() return { graph = graph } end
  map.findClosestRoad = function() return "wp30", "wp29" end
end

test("the runner and both cop slots use identical West Coast poses across normal and all three practice modes", function()
  dofile("tests/client_stubs.lua")
  local reference
  for _, mode in ipairs({ "normal", "runner", "cop", "watch" }) do
    local env = boot()
    env.names = { "Reinder", "Bob", "Alice" }
    env.vidPositions["1-0"] = { pos = { -360.06, 619.75, 75.05 }, vel = { 0, 0, 0 } }
    local planner = bootClient()
    westCoastStart(planner)
    planner.fire("cnr_mode", { startGrid = true })
    assertEq(planner.lastSent("cnr_startGridReady") ~= nil, true, "planner announces support")
    env.call("cnr_startGridReady", 1, "{}")
    if mode == "watch" then sitOut(env, 1, true) end
    local picker = mode == "normal" and 2 or 1
    env.panel(picker, mode == "normal" and "start rein" or "test " .. (mode == "watch" and "cop" or mode))
    env.call("cnr_vehiclePicked", picker, PICK)
    local request = env.lastSent("cnr_planStart")
    assertEq(request and request.pid, 1)
    planner.fire("cnr_planStart", decodeJson(request.data))
    local reply = planner.lastSent("cnr_startGrid")
    env.call("cnr_startGrid", 1, encode(reply))

    local function drive(client, pid, poses)
      local function store(slot, pos, rot)
        assertEq(pos ~= nil and rot ~= nil, true, mode .. " has a pose for slot " .. slot)
        poses[slot] = { pos.x, pos.y, pos.z, rot.dir.x, rot.dir.y, rot.dir.z }
      end
      for _, ev in ipairs(env.sent) do
        if ev.pid == pid then
          local d = decodeJson(ev.data)
          if ev.ev == "cnr_roundSetup" then
            local slot = d.role == "runner" and 1 or d.copIndex + 1
            spawn.safeTeleport = function(veh, pos, rot) veh.pos = pos; store(slot, pos, rot) end
            client.fire(ev.ev, d)
            client.tick(1)
            local registration = client.lastSent("cnr_myVehicle")
            env.vehicles[pid] = {[registration.vid]="round car"}
            env.call("cnr_myVehicle", pid, encode(registration))
          elseif ev.ev == "cnr_spectate" or ev.ev == "cnr_setupAI" then
            client.fire(ev.ev, d)
            if ev.ev == "cnr_setupAI" then
              client.tick(1)
              for i, a in ipairs(d.ai) do
                local spawned = client.spawned[#client.spawned - #d.ai + i].opt
                store(a.role == "runner" and 1 or a.index + 1, spawned.pos, spawned.rot)
              end
            end
          end
        end
      end
      client.tick(1)
    end
    for pick = 1, 2 do
      if pick == 2 then
        env.sent = {}
        env.panel(picker, "reroll")
        env.call("cnr_vehiclePicked", picker, PICK)
        assertEq(env.lastSent("cnr_planStart"), nil, "New car retains its original grid")
      end
      local poses = {}
      drive(mode == "normal" and bootClient() or planner, 1, poses)
      if mode == "normal" then
        for pid = 2, 3 do
          local cop = bootClient()
          cop.veh.pos = vec3(999, -800, 500)
          drive(cop, pid, poses)
        end
      end
      assertEq(#poses, 3, mode)
      assertNear(poses[1][1], -364.93, 0.001)
      assertEq(poses[1][4] > 0.99, true, "runner faces the legal exit")
      assertEq(poses[2][1] < poses[1][1] and poses[3][1] < poses[1][1], true, "both cops start behind")
      assertEq(poses[2][1] ~= poses[3][1], true)
      reference = reference or poses
      for i = 1, 3 do
        for j = 1, 6 do assertNear(poses[i][j], reference[i][j], 1e-8, mode .. " slot " .. i) end
      end
    end
    env.cleanup()
  end
end)

test("starting grid replies must match the outstanding pick, planner, slot count and valid poses", function()
  local env = boot()
  env.names = { "Reinder", "Bob", "Chloe" }
  env.call("cnr_startGridReady", 1, "{}")
  local function pick()
    env.panel(2, "start rein")
    env.call("cnr_vehiclePicked", 2, PICK)
    return decodeJson(env.lastSent("cnr_planStart").data)
  end
  local first = pick()
  env.go()
  assertEq(env.lastSent("cnr_countdown"), nil)
  env.panel(2, "stop")
  local nextPick = pick()
  local pose = { pos = { x = 5, y = 10, z = 15 }, dir = { x = 1, y = 0, z = 0 } }
  local function reply(pid, id, slots)
    env.call("cnr_startGrid", pid, encode({ id = id, slots = slots }))
  end
  local slots = { pose, pose, false }
  reply(1, first.id, slots)
  reply(2, nextPick.id, slots)
  reply(1, nextPick.id, { pose, pose })
  reply(1, nextPick.id, { pose, { pos = { x = 1 }, dir = pose.dir }, false })
  reply(1, nextPick.id, { pose, { pos = pose.pos, dir = { x = 0, y = 0, z = 0 } }, false })
  assertEq(env.lastSent("cnr_roundSetup"), nil)
  env.clock = 2
  env.call("cnr_tick")
  assertEq(countSent(env, "cnr_planStart", 1), 3, "retry the current pick")
  reply(1, nextPick.id, slots)
  reply(1, nextPick.id, slots)
  assertEq(countSent(env, "cnr_roundSetup", 1), 1)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 3)).startPose, false, "a cop with no road keeps the safe fallback")
  env.panel(2, "stop")
  pick()
  env.clock = 30
  env.call("cnr_tick")
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).reason, "cancelled")
  pick()
  env.call("onPlayerDisconnect", 1)
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).reason, "cancelled")
  env.cleanup()
end)

test("a cop joining during the initial pick extends the starting grid around its first anchor", function()
  local env = boot()
  env.names = { "Reinder", "Bob" }
  env.call("cnr_startGridReady", 1, "{}")
  env.startRound()
  local plan = decodeJson(env.lastSent("cnr_planStart").data)
  local dir = { x = -1, y = 0, z = 0 }
  local runner = { pos = { x = 12, y = 24, z = 2 }, dir = dir }
  local cop = { pos = { x = 100, y = 0, z = 0 }, dir = dir }
  env.names[3] = "Chloe"
  env.call("onPlayerJoin", 3)
  env.call("cnr_startGrid", 1, encode({ id = plan.id, slots = { runner, cop } }))
  local extended = decodeJson(env.lastSent("cnr_planStart").data)
  assertEq(extended.count, 3)
  assertEq(extended.anchor.pos.x, 12)
  local moved = { pos = { x = 15, y = 24, z = 2 }, dir = dir }
  env.call("cnr_startGrid", 1, encode({ id = extended.id, slots = { moved, cop, false } }))
  assertEq(env.lastSent("cnr_roundSetup"), nil, "the extension keeps the accepted anchor")
  env.positions[1] = 10000
  env.call("cnr_startGrid", 1, encode({ id = extended.id, slots = { runner, cop, false } }))
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 3)).startPose, false)
  env.cleanup()
end)

test("an evolving practice places the human cop on the grid and dispatches AI on its acknowledgement", function()
  local env = boot()
  evolving(env); newBuild(env)
  env.call("cnr_startGridReady", 1, "{}")
  env.panel(1, "test cop")
  local request = env.lastSent("cnr_planStart")
  assertEq(request.pid, 1)
  local places = {}
  for i = 1, 3 do places[i] = { pos = { x = 10 * i, y = 0, z = 0 }, dir = { x = 1, y = 0, z = 0 } } end
  env.call("cnr_startGrid", 1, encode({ id = decodeJson(request.data).id, slots = places }))
  local human = decodeJson(sentTo(env, "cnr_roundSetup", 1))
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  local ai = decodeJson(sentTo(env, "cnr_setupAI", 1)).ai
  assertEq(human.phase, "ready"); assertEq(human.startPose.pos.x, 20)
  assertEq(ai[1].role, "runner"); assertEq(ai[1].startPose.pos.x, 10)
  assertEq(ai[2].role, "cop"); assertEq(ai[2].startPose.pos.x, 30)
  env.cleanup()
end)

test("the initial grid stays near a known runner and within the search range of its anchor", function()
  local env = boot()
  env.call("cnr_startGridReady", 1, "{}")
  env.startRound()
  local id = decodeJson(env.lastSent("cnr_planStart").data).id
  local function pose(x)
    return { pos = { x = x, y = 0, z = 0 }, dir = { x = 1, y = 0, z = 0 } }
  end
  local function submit(runnerX, copX)
    env.call("cnr_startGrid", 1, encode({ id = id, slots = { pose(runnerX), pose(copX) } }))
  end
  env.positions[1] = 9000
  submit(0, 120)
  assertEq(env.lastSent("cnr_roundSetup"), nil, "known runner is outside the road search area")
  submit(9000, 15000)
  assertEq(env.lastSent("cnr_roundSetup"), nil, "cop is outside the largest search ring")
  submit(9000, 11300)
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 2)).startPose.pos.x, 11300, "widened ring")
  env.cleanup()
end)

test("an ambiguous personal vehicle sample still permits a bounded initial grid", function()
  local env = boot({ vehicles = { [1] = { [0] = "parked", [2] = "personal" }, [2] = { [0] = "cop" } } })
  env.call("cnr_startGridReady", 1, "{}")
  env.startRound()
  local request = decodeJson(env.lastSent("cnr_planStart").data)
  local pose = { pos = { x = 12000, y = 0, z = 0 }, dir = { x = 1, y = 0, z = 0 } }
  env.call("cnr_startGrid", 1, encode({ id = request.id, slots = { pose, false } }))
  assertEq(decodeJson(sentTo(env, "cnr_roundSetup", 1)).startPose.pos.x, 12000)
  env.cleanup()
end)

test("normal and practice strikes are announced ahead around the moving server runner", function()
  for _, mode in ipairs({"round", "practice"}) do
    local env = boot({config = '{"weather":"thunderstorm","lightningMinSeconds":1,"lightningMaxSeconds":1}'})
    if mode == "round" then
      env.names = {"Reinder", "Bob", "Kim"}
      sitOut(env, 3, true)
      env.startRound()
      assert(sentTo(env, "cnr_spectate", 3))
    else
      env.panel(1, "test cop")
      env.call("cnr_vehiclePicked", 1, PICK)
      env.vehicles[1][8] = "pickup"
      env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":8,"instance":1}]}')
    end
    local key = mode == "round" and "1-0" or "1-8"
    env.vidPositions[key] = {pos = {92000, -33000, 125}, vel = {0, 0, 0}}
    env.go()
    local first = env.lastSent("cnr_lightningPositions")
    assert(first, mode .. " must announce the first strike before it is due")
    assertEq(first.pid, mode == "round" and -1 or 1)
    local packet = decodeJson(first.data)
    local landing = packet.positions[1]
    assertEq(landing.at, 1)
    assertEq(landing.z, 125)
    local range = math.sqrt((landing.x - 92000)^2 + (landing.y + 33000)^2)
    assert(range >= 300 and range <= 6000)
    env.vidPositions[key].pos = {-72000, 53000, 13}
    env.clock = 1
    env.call("cnr_tick")
    local follow = decodeJson(env.lastSent("cnr_lightningPositions").data).positions
    local nextLanding = follow[#follow]
    assertEq(follow[1].id, landing.id)
    assertEq(follow[1].x, landing.x)
    assertEq(follow[1].y, landing.y)
    assert(nextLanding.id ~= landing.id and nextLanding.at > landing.at)
    assertEq(nextLanding.z, 13)
    range = math.sqrt((nextLanding.x + 72000)^2 + (nextLanding.y - 53000)^2)
    assert(range >= 300 and range <= 6000)
    if mode == "round" then
      env.names[4] = "Ann"
      env.call("onPlayerJoin", 4)
      local pending = decodeJson(env.lastSent("cnr_spectate").data).sky.lightningPositions
      local joined = pending[#pending]
      assertEq(joined.id, nextLanding.id)
      assertEq(joined.x, nextLanding.x)
      assertEq(joined.y, nextLanding.y)
    end
    env.cleanup()
  end
end)

test("clear-only rounds do not announce strike positions", function()
  local env = boot({config = '{"weather":"clear","weatherChanges":false,"lightningMinSeconds":1,"lightningMaxSeconds":1}'})
  env.startRound()
  env.go()
  env.clock = 5
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_lightningPositions"), nil)
  env.cleanup()
end)

local function placeAI(env, vid, x)
  env.vehicles[1][vid] = "pickup"
  env.vidPositions["1-" .. vid] = {pos={x,0,0}, vel={0,0,0}}
end

local function registerAI(env, id, vid, instance, pid)
  env.call("cnr_aiVehicles", pid or 1, encode({ai={{id=id, vid=vid, instance=instance}}}))
end

local function reportAI(env, id, instance, seen, pid)
  env.call("cnr_sight", pid or 1, encode({aiId=id, instance=instance, seen=seen}))
end

local function advanceSight(env, ticks)
  for _ = 1, ticks or 1 do
    env.clock = env.clock + 0.25
    env.call("cnr_tick")
  end
end

local function setupPracticeSight(env, role)
  if role == "watch" then sitOut(env, 1, true) end
  env.panel(1, role == "runner" and "test runner" or "test cop")
  env.call("cnr_vehiclePicked", 1, PICK)
  if role ~= "watch" then env.call("cnr_myVehicle", 1, '{"vid":0}') end
  env.positions[1] = role == "runner" and 0 or 300
  placeAI(env, 2, role == "runner" and 300 or 0)
  placeAI(env, 3, 300)
  env.go()
end

local function runnerSpotted(env)
  local data = sentTo(env, "cnr_spotted", 1)
  if data then return decodeJson(data).spotted end
end

test("public sight starts with confirmed cars for both the observer and the target", function()
  for _, first in ipairs({1, 2}) do
    local env = boot({config='{"helicopter":false}'})
    env.startRound()
    env.positions[2] = 300
    env.call("cnr_myVehicle", first, '{"vid":0}')
    chase(env)
    env.sent = {}
    env.call("cnr_sight", 2, '{"seen":true}')
    advanceSight(env)
    assertEq(sentTo(env, "cnr_lastSeen", 2), nil)
    env.call("cnr_myVehicle", 3 - first, '{"vid":0}')
    advanceSight(env)
    assertEq(runnerSpotted(env), nil)
    env.call("cnr_sight", 2, '{"seen":true}')
    advanceSight(env)
    assertEq(runnerSpotted(env), true)
    env.cleanup()
  end
end)

test("replacing a human runner leaves all cops with the old target's last position", function()
  for _, change in ipairs({"spawn after deletion", "missing for one tick", "placement acknowledgement"}) do
    local env = boot({config='{"helicopter":false}'})
    env.names = {"Reinder", "Bob", "Kim"}
    env.vehicles[3] = {[0]="cop"}
    env.startRound()
    env.positions[2], env.positions[3] = 300, 320
    confirmDrivers(env, 3)
    chase(env)
    env.call("cnr_sight", 2, '{"seen":true}')
    env.call("cnr_sight", 3, '{"seen":true}')
    advanceSight(env)
    assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 2)).pos.x, 0)
    env.sent = {}
    if change ~= "placement acknowledgement" then
      env.call("onVehicleDeleted", 1, 0)
      env.vehicles[1][0] = nil
      env.call("cnr_sight", 3, '{"seen":true}')
      if change == "missing for one tick" then
        advanceSight(env)
        assertEq(runnerSpotted(env), false)
        assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 2)).pos.x, 0)
      end
      assertEq(env.call("onVehicleSpawn", 1, 1, spawnOf(1, 1, "pickup", "vehicles/pickup/base.pc")), 0)
    end
    env.vehicles[1][1] = "replacement"
    env.vidPositions["1-1"] = {pos={200,0,0}, vel={0,0,0}}
    if change == "placement acknowledgement" then env.call("cnr_myVehicle", 1, '{"vid":1}') end
    env.call("cnr_sight", 2, '{"seen":false}')
    advanceSight(env, 4)
    for pid = 2, 3 do
      local last = decodeJson(sentTo(env, "cnr_lastSeen", pid))
      assertEq(last.live, nil, change)
      assertEq(last.pos.x, 0, change)
    end
    assertEq(runnerSpotted(env), false, change)
    env.call("cnr_sight", 2, '{"seen":true}')
    advanceSight(env)
    assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 2)).pos.x, 200)
    env.cleanup()
  end
end)

test("a cop replacement forgets only its own sight and duplicate acknowledgements preserve grace", function()
  local env = boot({config='{"helicopter":false}'})
  env.names = {"Reinder", "Bob", "Kim"}
  env.vehicles[3] = {[0]="cop"}
  env.startRound()
  env.positions[2], env.positions[3] = 300, 320
  confirmDrivers(env, 3)
  chase(env)
  for pid = 2, 3 do env.call("cnr_sight", pid, '{"seen":true}') end
  advanceSight(env)
  env.call("cnr_sight", 3, '{"seen":false}')
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  env.call("cnr_myVehicle", 3, '{"vid":0}')
  env.vehicles[2][1] = "replacement"
  env.call("cnr_myVehicle", 2, '{"vid":1}')
  env.call("onVehicleDeleted", 2, 0)
  advanceSight(env, 4)
  assertEq(runnerSpotted(env), true)
  advanceSight(env, 2)
  assertEq(runnerSpotted(env), false)
  env.call("cnr_sight", 2, '{"seen":true}')
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  env.cleanup()
end)

test("targeted Practice AI setup enables registered observers in each issuer role", function()
  for _, role in ipairs({"runner", "cop", "watch"}) do
    local env = boot({config='{"helicopter":false}'})
    setupPracticeSight(env, role)
    assertEq(decodeJson(sentTo(env, "cnr_setupAI", 1)).sightMaxMeters, 400, role)
    assertEq(sentTo(env, "cnr_setupAI", 2), nil)
    registerAI(env, -11, 3, 8)
    registerAI(env, -10, 2, 7)
    advanceSight(env, 41)
    env.sent = {}
    reportAI(env, role == "runner" and -10 or -11, role == "runner" and 7 or 8, true)
    advanceSight(env)
    assertEq(runnerSpotted(env), role == "runner" and true or nil)
    local live = sentTo(env, "cnr_lastSeen", 1)
    if role == "cop" then assertEq(decodeJson(live).live, true)
    else assertEq(live, nil) end
    assertEq(sentTo(env, "cnr_lastSeen", 2), nil)
    assertEq(sentTo(env, "cnr_spotted", 2), nil)
    env.panel(1, "end")
    assertEq(decodeJson(sentTo(env, "cnr_roundEnd", 1)).reason, "called")
    assertEq(io.open(env.dir .. "data/leaderboard.json"), nil)
    env.cleanup()
  end
end)

test("an invalid AI report cannot set or clear a human cop's own sight", function()
  local env = boot({config='{"helicopter":false}'})
  env.names = {"Reinder", "Bob", "Watcher"}
  sitOut(env, 3, true)
  env.startRound()
  confirmDrivers(env, 2)
  env.positions[2] = 290
  env.go()
  advanceSight(env, 41)
  local invalid = {
    {aiId=-10, instance=7}, {aiId=2, instance=7}, {aiId="-11", instance=7},
    {aiId=-11.5, instance=7}, {aiId=-11}, {instance=7},
    {aiId=-11, instance=0.5}, {aiId=-11, instance="7"}, {aiId=false},
  }
  for _, d in ipairs(invalid) do
    d.seen = true
    env.call("cnr_sight", 2, encode(d))
  end
  env.call("cnr_sight", 3, '{"seen":true}')
  env.call("cnr_sight", 2, '{"aiId":null,"seen":true}')
  env.call("cnr_sight", 2, '{"instance":null,"seen":true}')
  advanceSight(env)
  assertEq(runnerSpotted(env), nil)
  env.call("cnr_sight", 2, '{"seen":true}')
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  for _, d in ipairs(invalid) do
    d.seen = false
    env.call("cnr_sight", 2, encode(d))
    advanceSight(env, 7)
    assertEq(runnerSpotted(env), true)
    env.call("cnr_sight", 2, '{"seen":true}')
  end
  for _, msg in ipairs({'{"seen":"false"}', '{}', '{"seen":1}', '{"aiId":null,"seen":false}', 'invalid'}) do
    env.call("cnr_sight", 2, msg)
    advanceSight(env, 7)
    assertEq(runnerSpotted(env), true)
    env.call("cnr_sight", 2, '{"seen":true}')
  end
  env.cleanup()
end)

test("AI sight requires matching live issuer-owned registration and strict numeric fields", function()
  local env = boot({config='{"helicopter":false}'})
  setupPracticeSight(env, "runner")
  advanceSight(env, 41)
  registerAI(env, -10, 2, 7, 2)
  registerAI(env, -10, "2", 7)
  registerAI(env, "-10", 2, 7)
  registerAI(env, -10, 2, "7")
  registerAI(env, -10, 2, 0.5)
  registerAI(env, -10, 2.5, 7)
  registerAI(env, -10.5, 2, 7)
  registerAI(env, -10, 2)
  reportAI(env, -10, 7, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), nil)
  env.vehicles[2][5] = "pickup"
  registerAI(env, -10, 5, 8)
  placeAI(env, 5, 300)
  reportAI(env, -10, 8, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), nil)
  registerAI(env, -10, 2, 9)
  env.call("cnr_myVehicle", 1, '{"vid":2}')
  assertEq(table.concat(decodeJson(sentTo(env, "cnr_roundCars", -1)).keys, ","), "1-0")
  local invalid = {
    {-11,9}, {-20,9}, {1,9}, {-10.5,9}, {"-10",9}, {-10,"9"}, {-10,8},
    {-10,9.5}, {-10,nil}, {nil,9}, {-10,9,2}
  }
  for _, d in ipairs(invalid) do reportAI(env, d[1], d[2], true, d[3]) end
  env.vehicles[1][2] = nil
  reportAI(env, -10, 9, true)
  env.vehicles[1][2] = "pickup"
  advanceSight(env)
  assertEq(runnerSpotted(env), nil)
  reportAI(env, -10, 9, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  for _, d in ipairs(invalid) do
    reportAI(env, d[1], d[2], false, d[3])
    advanceSight(env, 7)
    assertEq(runnerSpotted(env), true)
    reportAI(env, -10, 9, true)
  end
  env.cleanup()
end)

test("deletion, slot remap and VID transfer invalidate Practice AI sight immediately", function()
  for _, change in ipairs({"delete", "remap", "transfer"}) do
    local env = boot({config='{"helicopter":false}'})
    setupPracticeSight(env, "runner")
    registerAI(env, -11, 3, 8)
    registerAI(env, -10, 2, 7)
    advanceSight(env, 41)
    reportAI(env, -10, 7, true)
    advanceSight(env)
    assertEq(runnerSpotted(env), true, change)
    registerAI(env, -10, 2, 7)
    env.vehicles[2][2] = "personal"
    env.call("onVehicleDeleted", 2, 2)
    advanceSight(env, 7)
    assertEq(runnerSpotted(env), true, change)
    reportAI(env, -10, 7, false)
    local id, vid = -10, 2
    if change == "delete" then
      env.call("onVehicleDeleted", 1, 2)
      registerAI(env, -10, 2, 7)
      reportAI(env, -10, 7, true)
      advanceSight(env)
      assertEq(runnerSpotted(env), false)
    elseif change == "remap" then
      vid = 4
      placeAI(env, vid, 310)
    else
      id = -11
    end
    registerAI(env, id, vid, 9)
    registerAI(env, -10, 2, 7)
    reportAI(env, -10, 7, true)
    advanceSight(env)
    assertEq(runnerSpotted(env), false, change)
    reportAI(env, id, 9, true)
    advanceSight(env)
    assertEq(runnerSpotted(env), true, change)
    env.cleanup()
  end
end)

test("an AI runner replacement clears both AI and human sight of the old target", function()
  local env = boot({config='{"helicopter":false}'})
  setupPracticeSight(env, "cop")
  registerAI(env, -10, 2, 7)
  registerAI(env, -11, 3, 8)
  advanceSight(env, 41)
  reportAI(env, -11, 8, true)
  env.call("cnr_sight", 1, '{"seen":true}')
  advanceSight(env)
  assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 1)).live, true)
  env.call("cnr_sight", 1, '{"seen":false}')
  placeAI(env, 4, 40)
  registerAI(env, -10, 4, 9)
  advanceSight(env)
  local lost = decodeJson(sentTo(env, "cnr_lastSeen", 1))
  assertEq(lost.live, nil)
  assertEq(lost.pos.x, 0)
  reportAI(env, -11, 8, true)
  advanceSight(env)
  assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 1)).live, true)
  env.call("onVehicleDeleted", 1, 4)
  advanceSight(env)
  local removed = decodeJson(sentTo(env, "cnr_lastSeen", 1))
  assertEq(removed.live, nil)
  assertEq(removed.pos.x, 40)
  reportAI(env, -11, 8, true)
  env.call("cnr_sight", 1, '{"seen":true}')
  placeAI(env, 4, 100)
  registerAI(env, -10, 4, 10)
  advanceSight(env, 5)
  assertEq(decodeJson(sentTo(env, "cnr_lastSeen", 1)).live, nil)
  env.cleanup()
end)

test("Practice rejects old registrations across rounds and starts a new serial sequence on reconnect", function()
  local env = boot({config='{"helicopter":false}'})
  setupPracticeSight(env, "runner")
  registerAI(env, -10, 2, 7)
  advanceSight(env, 41)
  reportAI(env, -10, 7, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  env.panel(1, "end")
  setupPracticeSight(env, "runner")
  env.sent = {}
  advanceSight(env, 41)
  registerAI(env, -10, 2, 7)
  reportAI(env, -10, 7, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), nil)
  registerAI(env, -10, 2, 9)
  reportAI(env, -10, 9, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  env.call("onPlayerDisconnect", 1)
  env.call("onPlayerJoin", 1)
  setupPracticeSight(env, "runner")
  env.sent = {}
  registerAI(env, -10, 2, 1)
  advanceSight(env, 41)
  reportAI(env, -10, 1, true)
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  env.cleanup()
end)

test("malformed AI registrations cannot move a legacy cop onto the runner", function()
  local env = boot({config='{"helicopter":false}'})
  setupPracticeSight(env, "runner")
  registerAI(env, -10, 2)
  placeAI(env, 4, 0)
  env.call("cnr_aiVehicles", 1, '{"ai":[false,{"id":-10,"vid":4,"instance":null}]}')
  advanceSight(env, 90)
  assertEq(env.caught(), false)
  registerAI(env, -10, 4)
  advanceSight(env, 40)
  assertEq(env.caught(), true)
  env.cleanup()
end)

test("Practice rejects a head-start sighting and honors the targeted host range", function()
  for _, maximum in ipairs({0, 400}) do
    local env = boot({config=encode({sightMaxMeters=maximum, helicopter=false})})
    setupPracticeSight(env, "runner")
    assertEq(decodeJson(sentTo(env, "cnr_setupAI", 1)).sightMaxMeters, maximum)
    registerAI(env, -10, 2, 7)
    advanceSight(env, 16)
    reportAI(env, -10, 7, true)
    advanceSight(env, 25)
    assertEq(runnerSpotted(env), nil)
    reportAI(env, -10, 7, true)
    advanceSight(env)
    assertEq(runnerSpotted(env), maximum > 0 and true or nil)
    env.cleanup()
  end
end)

test("a malformed registration leaves valid siblings usable and quoted null text leaves sight usable", function()
  local env = boot({config='{"helicopter":false}'})
  setupPracticeSight(env, "runner")
  env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-11,"vid":3,"instance":null},null,{"id":-10,"vid":2,"instance":7}]}')
  advanceSight(env, 41)
  env.call("cnr_sight", 1, encode({aiId=-10, instance=7, seen=true, details='ignored ":null'}))
  advanceSight(env)
  assertEq(runnerSpotted(env), true)
  env.cleanup()
end)

local function denyRenameFrom(path, reason)
  local rename = FS.Rename
  FS.Rename = function(from, to)
    if from == path then return false, reason or "rename denied" end
    return rename(from, to)
  end
end

for _, action in ipairs({ "settings", "auto on" }) do
  test("a failed " .. action .. " save shows the filename and logs the full error", function()
    local bytes = '{"headStartSeconds":3,"autoNextRound":false}'
    local env = boot({ config = bytes })
    local path = env.dir .. "config.json"
    FS.CreateDirectory(path .. ".tmp")
    local file, openError = io.open(path .. ".tmp", "wb")
    assertEq(file, nil)
    assert(openError:find(path, 1, true))
    if action == "settings" then
      env.call("cnr_panel", 1, '{"action":"settings","id":7,"values":{"headStartSeconds":9}}')
    else
      env.panel(1, action)
    end
    local reply = decodeJson(env.lastSent("cnr_panelReply").data)
    if action == "settings" then
      assertEq(reply.ok, false)
      assertEq(reply.id, 7)
    else
      assertEq(reply.tone, "warn")
    end
    assertEq(reply.text, "Could not save config.json")
    assertEq(env.logHas("could not save config.json: " .. openError), true)
    assertEq(readFileAt(path), bytes)
    local settings = panelOf(env).settings
    assertEq(settings.headStartSeconds, 3)
    assertEq(settings.autoNextRound, false)
    env.cleanup()
  end)
end

for _, hex in ipairs({ "#00ff00", "" }) do
  test("a colour that can't be saved isn't applied (" .. hex .. ")", function()
    local env = boot()
    env.call("cnr_color", 1, '{"hex":"#ff0000"}')
    denyRenameFrom(env.dir .. "data/colors.json.tmp")
    env.call("cnr_color", 1, encode({ hex = hex }))
    local mine = decodeJson(env.lastSent("cnr_myColor").data)
    assertEq(mine.error, "rename denied")
    assertEq(mine.hex, "#ff0000")
    env.cleanup()
  end)
end

local oldBuildBytes = '{"model":"pigeon","name":"Old build","parts":{},"step":3}'

test("a new build that can't be saved keeps the old build", function()
  local env = boot({ files = { ["data/build.json"] = oldBuildBytes } })
  local path = env.dir .. "data/build.json"
  denyRenameFrom(path .. ".tmp", path .. ".tmp: rename denied")
  newBuild(env)
  assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Could not save build.json")
  assertEq(env.logHas("could not save build.json: " .. path .. ".tmp: rename denied"), true)
  assertEq(readFileAt(path), oldBuildBytes)
  assertEq(panelOf(env).build.label, "Old build · change 3")
  env.cleanup()
end)

for _, op in ipairs({ "new", "reset" }) do
  test("a failed build backup stops " .. op, function()
    local env = boot({ files = { ["data/build.json"] = oldBuildBytes } })
    local path = env.dir .. "data/build.json"
    denyRenameFrom(path, path .. ": rename denied")
    if op == "new" then newBuild(env) else env.call("cnr_panel", 1, '{"action":"build","op":"reset"}') end
    assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Could not save build.json")
    assertEq(env.logHas("could not save build.json: " .. path .. ": rename denied"), true)
    assertEq(readFileAt(path), oldBuildBytes)
    assertEq(panelOf(env).build.label, "Old build · change 3")
    env.cleanup()
  end)
end

test("an unsaved evolving setup keeps the build and its step", function()
  local env = boot({ files = { ["data/build.json"] = oldBuildBytes } })
  evolving(env)
  env.panel(2, "start rein")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  local path = env.dir .. "data/build.json"
  denyRenameFrom(path .. ".tmp", path .. ".tmp: rename denied")
  env.call("cnr_setup", 1, '{"parts":{"engine":"v8"},"changes":[{"label":"Engine"}]}')
  assertEq(env.logHas("could not save build.json: " .. path .. ".tmp: rename denied"), true)
  assertEq(decodeJson(env.lastSent("cnr_notice").data).msg, "Could not save build.json")
  assertEq(panelOf(env).build.step, 3)
  assertEq(readFileAt(path), oldBuildBytes)
  assertEq(env.lastSent("cnr_rebuild"), nil)
  env.cleanup()
end)

for _, op in ipairs({ "add", "remove" }) do
  test("a failed station " .. op .. " keeps the station list", function()
    local env = boot()
    local path = env.dir .. "data/stations/west_coast_usa.json"
    env.positions[1] = 0
    if op == "remove" then env.call("cnr_panel", 1, '{"action":"station","op":"add"}') end
    local count, bytes = panelOf(env).stationCount, readFileAt(path)
    denyRenameFrom(path .. ".tmp", path .. ".tmp: rename denied")
    env.call("cnr_panel", 1, encode({ action = "station", op = op }))
    assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Could not save west_coast_usa.json")
    assertEq(env.logHas("could not save west_coast_usa.json: " .. path .. ".tmp: rename denied"), true)
    assertEq(panelOf(env).stationCount, count)
    assertEq(readFileAt(path), bytes)
    env.cleanup()
  end)
end

test("discovered stations stay usable for the session when their save fails", function()
  local env = boot()
  local path = env.dir .. "data/stations/west_coast_usa.json"
  denyRenameFrom(path .. ".tmp")
  env.call("cnr_stations", 1, '{"map":"west_coast_usa","stations":[{"x":1,"y":2,"z":3,"r":12}]}')
  env.call("cnr_panel", 1, '{"action":"stations"}')
  local stations = decodeJson(sentTo(env, "cnr_stationList", 1)).stations
  assertEq(#stations, 1)
  assertEq(stations[1].x, 1)
  assertEq(stations[1].y, 2)
  assertEq(stations[1].z, 3)
  assertEq(readFileAt(path), nil)
  assertEq(env.logHas("could not save west_coast_usa.json: rename denied"), true)
  env.cleanup()
end)

test("a failed leaderboard save leaves the old standings on disk and in the app", function()
  local bytes = '{"format":2,"runs":[]}'
  local env = boot({ leaderboard = bytes })
  local path = env.dir .. "data/leaderboard.json"
  denyRenameFrom(path .. ".tmp")
  env.startRound()
  env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  env.call("cnr_board", 1, '{"action":"open"}')
  assertEq(env.logHas("could not save leaderboard.json: rename denied"), true)
  assertEq(#decodeJson(env.lastSent("cnr_boardState").data).rounds, 0)
  assertEq(rowOf(panelOf(env), "Reinder").runs, 1)
  assertEq(readFileAt(path), bytes)
  env.cleanup()
end)

test("an encoding error while replacing a build restores its file", function()
  local env = boot({ files = { ["data/build.json"] = oldBuildBytes } })
  local encodeJson = Util.JsonEncode
  Util.JsonEncode = function(value)
    if value.model == "pickup" and value.startedFrom then error("encoding failed", 0) end
    return encodeJson(value)
  end
  local called, err = pcall(newBuild, env)
  Util.JsonEncode = encodeJson
  assert(called, err)
  assertEq(env.replyHas("Could not save build.json"), true)
  assertEq(env.logHas("could not save build.json: encoding failed"), true)
  assertEq(readFileAt(env.dir .. "data/build.json"), oldBuildBytes)
  assertEq(panelOf(env).build.label, "Old build · change 3")
  env.cleanup()
end)

test("watch-only practice by a sitting-out player still starts", function()
  local env = boot()
  env.names = { [7] = "Ann" }
  sitOut(env, 7, true)
  env.panel(7, "test runner")
  env.call("cnr_vehiclePicked", 7, PICK)
  assertEq(decodeJson(sentTo(env, "cnr_setupAI", 7)).aiOnly, true)
  env.cleanup()
end)

test("an automatic start after the issuer left is issued by the lowest player id", function()
  local env = boot({ config = '{"autoNextRound":true,"autoNextDelaySeconds":5}' })
  runToChase(env)
  env.panel(2, "end")
  env.names = { [19] = "Bob", [7] = "Ann", [11] = "Kim" }
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.clock = env.clock + 5
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 7)
  env.cleanup()
end)

test("a real round starts when the only connected player is player 7", function()
  local env = boot()
  env.names = { [7] = "Ann" }
  env.panel(7, "start Ann")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 7)
  env.cleanup()
end)

test("a driver whose confirmed round car vanished without a delete can spawn the round car again", function()
  local env = boot({ vehicles = { [1] = {}, [2] = {} } })
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "pickup")), 0)
  env.vehicles[2][4] = "round car"
  env.call("cnr_myVehicle", 2, '{"vid":4}')
  env.vehicles[2][4] = nil
  local again = env.call("onVehicleSpawn", 2, 5, spawnOf(2, 5, "pickup"))
  env.cleanup()
  assertEq(again, 0)
end)

test("a driver who still owns a vehicle cannot spawn a second round car", function()
  local env = boot({ vehicles = { [1] = {}, [2] = {} } })
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "pickup")), 0)
  env.vehicles[2][4] = "round car"
  local second = env.call("onVehicleSpawn", 2, 5, spawnOf(2, 5, "pickup"))
  env.cleanup()
  assertEq(second, 1)
end)

test("a traffic capacity refusal keeps its model-independent log entry", function()
  local env = trafficBoot({ config = '{"trafficPerPlayer":1}', maxCars = 3 })
  env.startRound()
  env.call("cnr_myVehicle", 2, '{"vid":0}')
  env.vehicles[2][1] = "traffic"
  assertEq(env.call("onVehicleSpawn", 2, 2, spawnOf(2, 2, "etk800")), 1)
  assertEq(env.logHas("Bob spawned ? (vid 2): refused"), true)
  env.cleanup()
end)

test("a driver can retry placement after their provisional car is deleted before confirmation", function()
  local env = boot({ vehicles = { [1] = {}, [2] = {} } })
  env.startRound()
  local first = env.call("onVehicleSpawn", 2, 4, spawnOf(2, 4, "pickup"))
  env.call("onVehicleDeleted", 2, 4)
  local retry = env.call("onVehicleSpawn", 2, 5, spawnOf(2, 5, "pickup"))
  env.vehicles[2][5] = "round car"
  env.call("cnr_myVehicle", 2, '{"vid":5}')
  local keys = decodeJson(env.lastSent("cnr_roundCars").data).keys
  env.cleanup()
  assertEq(first, 0)
  assertEq(retry, 0)
  assertEq(table.concat(keys, ","), "2-5")
end)

test("a runner leaving mid-chase sends exactly one empty cnr_roundCars", function()
  local env = trafficBoot()
  env.startRound()
  placed(env, 1)
  placed(env, 2)
  chase(env)
  env.call("cnr_panel", 2, '{"action":"open"}')
  assertEq(decodeJson(env.lastSent("cnr_panelState").data).phase, "running")
  assertEq(table.concat(decodeJson(env.lastSent("cnr_roundCars").data).keys, ","), "1-0,2-0")
  env.sent = {}
  env.call("onPlayerDisconnect", 1)
  local count = 0
  for _, msg in ipairs(env.sent) do
    if msg.ev == "cnr_roundCars" then
      count = count + 1
      assertEq(msg.pid, -1)
      assertEq(#decodeJson(msg.data).keys, 0)
    end
  end
  env.cleanup()
  assertEq(count, 1)
end)

test("a station report without a list leaves discovery open for the next report", function()
  local env = boot()
  env.call("cnr_stations", 1, '{"map":"west_coast_usa","stations":true}')
  env.call("cnr_stations", 1, '{"map":"west_coast_usa","stations":[{"x":1,"y":2,"z":3}]}')
  env.call("cnr_panel", 1, '{"action":"stations"}')
  local stations = decodeJson(env.lastSent("cnr_stationList").data).stations
  env.cleanup()
  assertEq(#stations, 1)
  assertEq(stations[1].x, 1)
end)

test("a temporary leaderboard read error at startup cannot replace earlier runs", function()
  local bytes = '{"format":2,"runs":[{"player":"Old","survivedSeconds":999,"endedAt":1}]}'
  local env = boot({ leaderboard = bytes })
  local path = env.dir .. "data/leaderboard.json"
  local store = require("arcade.store")
  local read = store.read
  store.read = function(name)
    if name == path then return nil, "permission denied", 13 end
    return read(name)
  end
  local ok, err = pcall(env.reload)
  store.read = read
  assert(ok, err)
  runningRound(env)
  env.panel(1, "end")
  env.call("cnr_board", 1, '{"action":"open"}')
  local rounds = decodeJson(env.lastSent("cnr_boardState").data).rounds
  local saved = readFileAt(path)
  env.cleanup()
  assertEq(#rounds, 1)
  assertEq(rounds[1].player, "Reinder")
  assertEq(saved, bytes)
end)

test("a failed build restore keeps the backup path in the server log", function()
  local env = boot({ files = { ["data/build.json"] = oldBuildBytes } })
  local path = env.dir .. "data/build.json"
  denyRenameFrom(path .. ".tmp", path .. ".tmp: rename denied")
  local rename, backup = os.rename
  os.rename = function(from, to)
    if to == path then
      backup = from
      return nil, from .. ": restore denied"
    end
    return rename(from, to)
  end
  local ok, err = pcall(newBuild, env)
  os.rename = rename
  assert(ok, err)
  assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Could not save build.json")
  assertEq(env.logHas(path .. ".tmp: rename denied"), true)
  assertEq(env.logHas(backup .. ": restore denied"), true)
  assertEq(readFileAt(backup), oldBuildBytes)
  env.cleanup()
end)
