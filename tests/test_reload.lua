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
