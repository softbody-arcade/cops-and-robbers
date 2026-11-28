dofile("tests/server_boot.lua")
local boot, encode = serverBoot.boot, serverBoot.encode
dofile("tests/trace.lua")

test("trace lines sort payload keys at every depth and keep array order", function()
  local entry = { kind = "send", t = 1.25, to = 2, ev = "cnr_notice", data = '{"tone":"info","msg":"x"}' }
  assertEq(traceLine(entry), '1.250 2 cnr_notice {"msg":"x","tone":"info"}')
  entry.data = '{"items":[{"z":1,"a":2},0]}'
  assertEq(traceLine(entry), '1.250 2 cnr_notice {"items":[{"a":2,"z":1},0]}')
end)

test("trace lines preserve log text", function()
  assertEq(traceLine({ kind = "log", t = 0, text = "[CnR] hi" }), "0.000 log [CnR] hi")
end)

test("trace runs preserve non-JSON send payloads", function()
  local trace = traceRun({ steps = function(env)
    env.events.probe = "traceProbe"
    function traceProbe() MP.TriggerClientEvent(1, "cnr_probe", "not json") end
    env.call("probe")
  end })
  assert(trace:find("0.000 1 cnr_probe raw:not json\n", 1, true))
end)

test("trace runs replace only standalone version tokens", function()
  local trace = traceRun({ steps = function(env)
    env.events.probe = "traceProbe"
    function traceProbe()
      MP.TriggerClientEvent(1, "cnr_probe", encode({ v = CNR_VERSION, name = "x" .. CNR_VERSION }))
      print("." .. CNR_VERSION, CNR_VERSION .. ".", CNR_VERSION .. "x")
    end
    env.call("probe")
  end })
  local expected = '0.000 1 cnr_probe {"name":"x' .. CNR_VERSION .. '","v":"<version>"}'
  assert(trace:find(expected .. "\n", 1, true), expected)
  for _, token in ipairs({ "." .. CNR_VERSION, CNR_VERSION .. ".", CNR_VERSION .. "x" }) do
    assert(trace:find(token, 1, true), token)
  end
end)

test("trace records vehicle removal, chat, timer operations and file writes", function()
  local env = boot()
  local target = env.dir .. "a"
  local file = assert(io.open(target .. ".tmp", "wb"))
  assert(file:write('{"b":1,"a":2}'))
  assert(file:close())
  local before = #env.stream
  MP.RemoveVehicle(1, 3)
  MP.SendChatMessage(2, "hi")
  MP.CreateEventTimer("x", 100)
  MP.CancelEventTimer("x")
  FS.CreateDirectory(env.dir .. "d")
  FS.Remove(target)
  FS.Rename(target .. ".tmp", target)
  local exists = FS.Exists(target)
  env.cleanup()

  local expected = {
    "0.000 remove 1-3",
    "0.000 chat 2 hi",
    "0.000 timer create x 100",
    "0.000 timer cancel x",
    "0.000 fs mkdir " .. env.dir .. "d",
    "0.000 fs remove " .. target,
    "0.000 fs write " .. target .. ' {"a":2,"b":1}',
  }
  assertEq(#env.stream - before, #expected, "operation count")
  for i, line in ipairs(expected) do
    local entry = env.stream[before + i]
    assertEq(entry.kind, "op")
    assertEq(entry.t, 0)
    assertEq(entry.text, line)
  end
  assertEq(exists, true)
end)

test("trace lines use ten significant digits for numbers", function()
  local entry = { kind = "send", t = 0, to = 1, ev = "cnr_test", data = '{"x":16.653397805827}' }
  local expected = '0.000 1 cnr_test {"x":16.65339781}'
  assertEq(traceLine(entry), expected)
  entry.data = '{"x":16.653397805827389}'
  assertEq(traceLine(entry), expected)
end)

test("trace runs order fan-out by recipient only within each uninterrupted group", function()
  local trace = traceRun({ steps = function(env)
    env.events.probe = "traceProbe"
    function traceProbe()
      local function send(pid, value) MP.TriggerClientEvent(pid, "cnr_probe", encode({ x = value })) end
      send(3, 0)
      send(1, 0)
      send(2, 1)
      print("boundary")
      send(2, 0)
      return 1, nil, false
    end
    env.call("probe")
    env.call("probe")
  end })
  local group = table.concat({
    "call probe", '0.000 1 cnr_probe {"x":0}', '0.000 3 cnr_probe {"x":0}', '0.000 2 cnr_probe {"x":1}',
    "0.000 log boundary", '0.000 2 cnr_probe {"x":0}', "ret 1 nil false", ""
  }, "\n")
  assertEq(trace:sub(-2 * #group), group .. group)
end)

test("reload captures the timer lifecycle and load events twice", function()
  local env = boot()
  local before = #env.sent
  env.reload()
  env.cleanup()
  assertEq(#env.timerOps, 4)
  for i = 1, 3, 2 do
    assertEq(env.timerOps[i].op, "cancel")
    assertEq(env.timerOps[i].name, "cnr_tick")
    assertEq(env.timerOps[i+1].op, "create")
    assertEq(env.timerOps[i+1].name, "cnr_tick")
    assertEq(env.timerOps[i+1].ms, 250)
  end
  assertEq(#env.sent, 2 * before)
end)

test("a failing trace restores the clock, generator and server environment", function()
  local time, date, random, seed = os.time, os.date, math.random, math.randomseed
  local mp, path = MP, package.path
  local retainedEnv, wrappedCall
  local ok, err = pcall(traceRun, { steps = function(env)
    retainedEnv, wrappedCall = env, env.call
    assertEq(os.time(), 1795000000)
    assertEq(os.date("!%Y-%m-%d"), date("!%Y-%m-%d", 1795000000))
    assertEq(math.random(), 1103527590 / 2147483648)
    error("scenario failed")
  end })
  assertEq(ok, false)
  assert(tostring(err):find("scenario failed", 1, true), tostring(err))
  assertEq(os.time, time)
  assertEq(os.date, date)
  assertEq(math.random, random)
  assertEq(math.randomseed, seed)
  assertEq(MP, mp)
  assertEq(package.path, path)
  assert(retainedEnv.call ~= wrappedCall, "env.call still records after cleanup")
  assertEq(io.open(retainedEnv.dir .. "config.json"), nil)
  assertEq(package.loaded["cnr.round"], nil)
end)

test("a failed boot removes the partial server directory", function()
  local tmpname = os.tmpname
  local tmp = tmpname()
  os.tmpname = function() return tmp end
  local ok, err = pcall(traceRun, { boot = { files = { ["missing/test.json"] = "{}" } } })
  os.tmpname = tmpname
  assertEq(ok, false)
  local dir = tmp .. "_cnr/"
  assert(tostring(err):find(dir .. "missing/test.json", 1, true), tostring(err))
  local renamed = os.rename(dir, dir)
  if renamed then os.remove(dir .. "data"); os.remove(dir) end
  assertEq(renamed, nil, "partial server directory still exists")
end)

local pick = '{"model":"pickup","config":"vehicles/pickup/base.pc"}'

local function findAfter(env, after, event, pid)
  for i = after + 1, #env.sent do
    local msg = env.sent[i]
    if msg.ev == event and (pid == nil or msg.pid == pid) then return msg, i end
  end
end

local function expectAfter(env, after, event, pid)
  local msg, index = findAfter(env, after, event, pid)
  assert(msg, "missing " .. event .. " after send " .. after)
  return decodeJson(msg.data), index
end

local function tick(env)
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
end

local function tickUntil(env, after, event)
  for i = 0, 2000 do
    local msg, index = findAfter(env, after, event)
    if msg then return decodeJson(msg.data), index, msg.pid end
    after = #env.sent
    if i < 2000 then tick(env) end
  end
  error("no " .. event .. " within 2000 ticks")
end

local function go(env)
  local after = #env.sent
  env.go()
  return after
end

local function scenario(name, opts, steps)
  test(name, function() traceCheck(name, { boot = opts, steps = steps }) end)
end

scenario("lobby", {}, function(env)
  env.call("onPlayerJoin", 1)
  env.call("onPlayerJoin", 2)
  env.call("cnr_panel", 1, '{"action":"open"}')
  local opened = #env.sent
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9,"explodeOnCatch":true,"excludedModels":["citybus"]}}')
  assertEq(expectAfter(env, opened, "cnr_panelReply", 1).ok, true)
  env.call("cnr_board", 1, '{"action":"open"}')
  local beforeFilter = #env.sent
  env.call("cnr_board", 1, '{"action":"filter","map":"all"}')
  assertEq(expectAfter(env, beforeFilter, "cnr_boardState", 1).filter, "all")
end)

scenario("round_caught", {}, function(env)
  env.call("cnr_board", 1, '{"action":"open"}')
  env.startRound()
  for pid = 1, 2 do env.call("cnr_myVehicle", pid, '{"vid":0}') end
  tickUntil(env, go(env), "cnr_release")
  env.vidPositions["1-0"] = { pos = { 6, 8, 12 }, vel = { 0, 0, 0 } }
  env.vidPositions["2-0"] = { pos = { 6, 8, 42 }, vel = { 0, 0, 0 } }
  local beforeSight = #env.sent
  env.call("cnr_sight", 2, '{"seen":true}')
  tick(env)
  local seen, index = expectAfter(env, beforeSight, "cnr_lastSeen", 2)
  assertEq(seen.live, true)
  env.vidPositions = {}
  local outcome, finished = tickUntil(env, index, "cnr_roundEnd")
  assertEq(outcome.reason, "caught")
  expectAfter(env, finished, "cnr_boardState", 1)
end)

scenario("round_escaped", { config = '{"roundTimeLimitSeconds":30}' }, function(env)
  env.startRound()
  env.positions[1], env.positions[2] = 0, 2000
  assertEq(tickUntil(env, go(env), "cnr_roundEnd").reason, "escaped")
end)

scenario("late_joiner", {}, function(env)
  env.startRound()
  env.positions[1], env.positions[2] = 0, 900
  local started = go(env)
  for _ = 1, 60 do tick(env) end
  expectAfter(env, started, "cnr_release")
  env.names = { "Reinder", "Bob", "Kim" }
  local beforeJoin = #env.sent
  env.call("onPlayerJoin", 3)
  assertEq(expectAfter(env, beforeJoin, "cnr_spectate", 3).chaseElapsed, 5)
  local beforeLeave = #env.sent
  env.call("onPlayerDisconnect", 1)
  assertEq(expectAfter(env, beforeLeave, "cnr_roundEnd").reason, "disconnect")
end)

scenario("disconnect_picking", {}, function(env)
  env.names = { "Reinder", "Bob", "Kim" }
  env.call("onPlayerJoin", 3)
  local function disconnectWhilePicking(pid)
    env.panel(2, "start rein")
    env.names[pid] = nil
    local before = #env.sent
    env.call("onPlayerDisconnect", pid)
    return before
  end

  local runnerLeft = disconnectWhilePicking(1)
  assertEq(expectAfter(env, runnerLeft, "cnr_roundEnd").reason, "cancelled")
  assertEq(expectAfter(env, runnerLeft, "cnr_notice").msg, "Runner left, round cancelled")
  env.names[1] = "Reinder"
  env.call("onPlayerJoin", 1)

  local issuerLeft = disconnectWhilePicking(2)
  assertEq(expectAfter(env, issuerLeft, "cnr_roundEnd").reason, "cancelled")
  assertEq(expectAfter(env, issuerLeft, "cnr_notice").msg, "Round cancelled")
  env.names[2] = "Bob"
  env.call("onPlayerJoin", 2)

  local copLeft = disconnectWhilePicking(3)
  assertEq(findAfter(env, copLeft, "cnr_roundEnd"), nil)
  local beforePick = #env.sent
  env.call("cnr_vehiclePicked", 2, pick)
  expectAfter(env, beforePick, "cnr_roundSetup", 1)
  expectAfter(env, beforePick, "cnr_roundSetup", 2)
end)

local function spawnAI(env, vid)
  local packet = string.format('USER:Reinder:1-%d:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}', vid)
  assertEq(env.call("onVehicleSpawn", 1, vid, packet), 0)
  env.vehicles[1][vid] = "pickup"
end

local function expectAICatch(env)
  local outcome = tickUntil(env, go(env), "cnr_roundEnd")
  assertEq(outcome.reason, "caught")
  assertEq(outcome.catchers[1], "AI cop 1")
  assertEq(io.open(env.dir .. "data/leaderboard.json"), nil)
end

scenario("practice_runner", { vehicles = { [1] = { [0] = "x" } } }, function(env)
  env.panel(1, "test runner")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, pick)
  local beforeCar = #env.sent
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  expectAfter(env, beforeCar, "cnr_setupAI", 1)
  spawnAI(env, 1)
  env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":1}]}')
  env.vidPositions["1-1"] = { pos = { 5, 0, 0 }, vel = { 0, 0, 0 } }
  expectAICatch(env)
end)

scenario("practice_watch_ai", {}, function(env)
  env.call("cnr_sitOut", 1, '{"on":true}')
  env.panel(1, "test runner")
  local beforePick = #env.sent
  env.call("cnr_vehiclePicked", 1, pick)
  assertEq(expectAfter(env, beforePick, "cnr_spectate", 1).runnerName, "AI runner")
  assertEq(expectAfter(env, beforePick, "cnr_setupAI", 1).aiOnly, true)
  for vid = 1, 3 do spawnAI(env, vid) end
  env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":1},{"id":-11,"vid":2},{"id":-12,"vid":3}]}')
  for vid, x in ipairs({ 0, 5, 500 }) do
    env.vidPositions["1-" .. vid] = { pos = { x, 0, 0 }, vel = { 0, 0, 0 } }
  end
  expectAICatch(env)
end)

local function expectPracticeSetupTimeout(env, explanation)
  env.panel(1, "test runner")
  env.call("cnr_vehiclePicked", 1, pick)
  local picked = #env.sent
  local outcome, finished = tickUntil(env, picked, "cnr_roundEnd")
  assertEq(outcome.reason, "cancelled")
  local notice = expectAfter(env, finished, "cnr_notice", 1)
  assert(notice.msg:find(explanation, 1, true), notice.msg)
end

scenario("practice_setup_car_late", { vehicles = { [1] = { [0] = "x" } } }, function(env)
  expectPracticeSetupTimeout(env, "did not register in time")
end)

scenario("practice_setup_no_slots", { maxCars = 3 }, function(env)
  env.call("cnr_sitOut", 1, '{"on":true}')
  expectPracticeSetupTimeout(env, "too few free vehicle slots")
end)

scenario("evolving", {}, function(env)
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"carMode":"evolving"}}')
  env.call("cnr_panel", 1, '{"action":"build","op":"new","model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":{}}')
  env.panel(2, "start rein")
  local beforeChange = #env.sent
  env.call("cnr_change", 1, '{"changes":[{"label":"Engine","from":"a","to":"b"}]}')
  local _, queued = expectAfter(env, beforeChange, "cnr_queued")
  env.call("cnr_panel", 1, '{"action":"apply"}')
  expectAfter(env, queued, "cnr_requestSetup", 1)
  tick(env)
  env.call("cnr_setup", 1, '{"parts":{"pickup_engine":"v8_60"},"vars":{},"changes":[{"label":"Engine","from":"4.5L V8","to":"6.0L V8"}]}')
  local rebuild, requested = expectAfter(env, queued, "cnr_rebuild")
  assertEq(type(rebuild.rebuild), "number")
  tick(env)
  for pid = 1, 2 do env.call("cnr_myVehicle", pid, encode({ vid = 0, rebuild = rebuild.rebuild })) end
  expectAfter(env, requested, "cnr_applied")
  local beforeMissing = #env.sent
  env.call("cnr_missing", 2, '{"parts":["meo_turbo","meo_intake"]}')
  local notice = expectAfter(env, beforeMissing, "cnr_notice")
  assert(notice.msg:find("Bob is missing: meo_turbo, meo_intake", 1, true))
  assertEq(notice.tone, "warn")
  tickUntil(env, go(env), "cnr_release")
end)

scenario("auto_next", { config = '{"autoNextRound":true,"autoNextDelaySeconds":5}' }, function(env)
  env.panel(1, "auto on")
  env.startRound()
  local first, finished = tickUntil(env, go(env), "cnr_roundEnd")
  assertEq(first.reason, "caught")
  assertEq(first.autoNextSeconds, 5)
  local _, picked, pid = tickUntil(env, finished, "cnr_pickVehicle")
  env.call("cnr_vehiclePicked", pid, pick)
  assertEq(expectAfter(env, picked, "cnr_roundSetup").runnerId, 2)
  tickUntil(env, go(env), "cnr_release")
  local beforeOff = #env.sent
  env.panel(1, "auto off")
  local _, off = expectAfter(env, beforeOff, "cnr_autoNext")
  local second = tickUntil(env, off, "cnr_roundEnd")
  assertEq(second.reason, "caught")
  assertEq(second.autoNextSeconds, nil)
end)

scenario("prep_actions", { config = '{"weather":"random"}' }, function(env)
  env.startRound()
  env.panel(1, "reroll")
  local beforePick = #env.sent
  env.call("cnr_vehiclePicked", 1, '{"model":"etk800","config":"vehicles/etk800/base.pc"}')
  assertEq(expectAfter(env, beforePick, "cnr_roundSetup", 1).model, "etk800")
  local picked = #env.sent
  env.panel(1, "sky")
  expectAfter(env, picked, "cnr_sky", 1)
  expectAfter(env, picked, "cnr_sky", 2)
  local beforeStop = #env.sent
  env.panel(1, "stop")
  assertEq(expectAfter(env, beforeStop, "cnr_roundEnd").reason, "cancelled")
end)

scenario("vehicle_rules", { config = '{"trafficPerPlayer":1}', maxCars = 6 }, function(env)
  env.startRound()
  tickUntil(env, go(env), "cnr_release")
  env.names = { "Reinder", "Bob", "Kim" }
  env.call("onPlayerJoin", 3)
  assertEq(env.call("onVehicleSpawn", 3, 4, 'USER:Kim:3-4:{"jbm":"etk800","vcf":{}}'), 1)
  local packet = 'USER:Reinder:1-4:{"jbm":"etk800","vcf":{}}'
  assertEq(env.call("onVehicleSpawn", 1, 4, packet), 1)
  local beforeCar = #env.sent
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(expectAfter(env, beforeCar, "cnr_trafficStart", 1).count, 1)
  env.call("cnr_trafficCars", 1, '{"vids":[4]}')
  assertEq(env.call("onVehicleSpawn", 1, 4, packet), 0)
end)
