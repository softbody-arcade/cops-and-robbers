dofile("tests/server_boot.lua")

local function checkReload(env)
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.panel(1, "auto on")
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25
    env.call("cnr_tick")
    if env.caught() then break end
  end
  assertEq(env.caught(), true)
  local delay = decodeJson(env.lastSent("cnr_roundEnd").data).autoNextSeconds
  assertEq(delay, 5)
  local oldDeadline = env.clock + delay
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  local panel = assert(env.lastSent("cnr_panelState"))
  assertEq(panel.pid, 1)
  assertEq(decodeJson(panel.data).autoNext.seconds, 5)
  local reloadTime = env.clock

  env.sent = {}
  env.reload()
  local roundEnd = assert(env.lastSent("cnr_roundEnd"))
  assertEq(roundEnd.pid, -1)
  assertEq(decodeJson(roundEnd.data).reason, "cancelled")
  local mode = assert(env.lastSent("cnr_mode"))
  assertEq(mode.pid, -1)
  assertEq(decodeJson(mode.data).version, CNR_VERSION)
  assertEq(#env.timerOps, 4)
  for i = 1, 3, 2 do
    local cancel, create = env.timerOps[i], env.timerOps[i + 1]
    assertEq(cancel.op, "cancel")
    assertEq(cancel.name, "cnr_tick")
    assertEq(create.op, "create")
    assertEq(create.name, "cnr_tick")
    assertEq(create.ms, 250)
  end

  env.clock = reloadTime + oldDeadline + 0.25
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_panelState"), nil)
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
end

test("hot reload resets panel subscriptions and the pending automatic round", function()
  local env = serverBoot.boot({ config = '{"autoNextDelaySeconds":5}' })
  local ok, err = xpcall(checkReload, debug.traceback, env)
  env.cleanup()
  if not ok then error(err, 0) end
end)

test("rebuild ids from before a reload don't complete the current rebuild", function()
  local env = serverBoot.boot({
    config = '{"carMode":"evolving"}',
    files = { ["data/build.json"] = '{"model":"pickup","parts":{"engine":"v8"}}' },
  })
  local function startRebuild()
    env.panel(2, "start rein")
    env.call("cnr_panel", 1, '{"action":"apply"}')
    env.call("cnr_setup", 1, '{"parts":{"engine":"v8"},"changes":[]}')
    return decodeJson(assert(env.lastSent("cnr_rebuild")).data).rebuild
  end
  local function acknowledge(pid, id)
    env.call("cnr_myVehicle", pid, serverBoot.encode({ vid = 0, rebuild = id }))
  end

  local old = startRebuild()
  local cars
  local game = require("cnr.game")
  local new = game.new
  game.new = function(ctx)
    cars = ctx.cars
    return new(ctx)
  end
  local ok, err = pcall(env.reload)
  game.new = new
  assert(ok, err)
  env.sent = {}
  local current = startRebuild()
  acknowledge(2, current)
  assertEq(cars:pendingRebuild(2), false)
  acknowledge(1, old)
  assertEq(env.lastSent("cnr_applied"), nil)
  assertEq(cars:pendingRebuild(1), true)
  acknowledge(1, current)
  assertEq(cars:pendingRebuild(1), false)
  assert(env.lastSent("cnr_applied"))
  env.cleanup()
end)

test("grid ids from before a reload don't release the current setup", function()
  local env = serverBoot.boot()
  local function requestGrid()
    env.call("cnr_startGridReady", 1, "{}")
    env.startRound()
    local request = assert(env.lastSent("cnr_planStart"))
    assertEq(request.pid, 1)
    return decodeJson(request.data).id
  end
  local old = requestGrid()
  env.reload()
  env.sent = {}
  local current = requestGrid()
  local grid = { id = old, slots = { false, false } }
  env.call("cnr_startGrid", 1, serverBoot.encode(grid))
  assertEq(env.lastSent("cnr_roundSetup"), nil)
  grid.id = current
  env.call("cnr_startGrid", 1, serverBoot.encode(grid))
  assert(env.lastSent("cnr_roundSetup"))
  env.cleanup()
end)

test("a hot reload keeps one module search path for the plugin", function()
  local env = serverBoot.boot()
  local path = package.path
  env.reload()
  assertEq(package.path == path, true)
  env.cleanup()
end)

test("a malformed station list on disk leaves the plugin ready to discover stations", function()
  local env = serverBoot.boot()
  local f = assert(io.open(env.dir .. "data/stations/west_coast_usa.json", "w"))
  assert(f:write('{"stations":true}'))
  assert(f:close())
  env.reload()
  env.call("onPlayerJoin", 1)
  assertEq(env.lastSent("cnr_requestStations").pid, 1)
  env.call("cnr_stations", 1, '{"map":"west_coast_usa","stations":[{"x":1,"y":2,"z":3}]}')
  env.call("cnr_panel", 1, '{"action":"stations"}')
  assertEq(decodeJson(env.lastSent("cnr_stationList").data).stations[1].x, 1)
  env.cleanup()
end)
