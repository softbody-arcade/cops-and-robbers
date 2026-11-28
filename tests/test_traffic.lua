local traffic = require("cnr.traffic")
local rules = require("cnr.rules")
local config = require("cnr.config")

test("the panel note names the cost or the cap", function()
  assertEq(traffic.note(5, 32, 6), "5 each · 30 cars with 6 players")
  assertEq(traffic.note(5, 32, 1), "5 each · 5 cars with 1 player")
  assertEq(traffic.note(5, 4, 6), "MaxCars is 4 on this server: 3 per player")
  assertEq(traffic.note(5, 1, 2), "MaxCars is 1 on this server: no room for traffic")
  assertEq(traffic.note(0, 32, 6), nil)
end)

test("with traffic for the runner only, the panel note counts one game's traffic", function()
  assertEq(traffic.note(5, 32, 6, true), "5 cars in all with 6 players")
  assertEq(traffic.note(5, 32, 1, true), "5 cars in all with 1 player")
  assertEq(traffic.note(5, 4, 6, true), "MaxCars is 4 on this server: 3 for the runner")
  assertEq(traffic.note(5, 1, 2, true), "MaxCars is 1 on this server: no room for traffic")
end)

test("the rules payload carries the effective traffic", function()
  local cfg = config.merge(nil)
  assertEq(rules.payload(cfg).trafficPerPlayer, 0)
  assertEq(rules.payload(cfg, 3).trafficPerPlayer, 3)
end)

dofile("tests/client_stubs.lua")

local function clearingRound(time)
  local env = bootClient()
  env.fire("cnr_roundSetup", {
    role = "cop", runnerId = 2, model = "pickup", config = "vehicles/pickup/base.pc", phase = "running", chaseElapsed = 0,
    runnerPos = { x = 0, y = 0, z = 0 },
    sky = { time = time, weather = "rain", windDir = 0, windSeed = 1, clockSeconds = 0, changes = { { at = 10, to = "cloudy", forecastFrom = 0 } } },
  })
  env.fire("cnr_trafficStart", { count = 3 })
  return env
end

local function trafficCars(env)
  local list = {}
  for id in pairs(env.gameTraffic) do list[#list + 1] = env.objects[id] end
  return list
end

local function sent(obj, cmd)
  local n = 0
  for _, c in ipairs(obj.commands) do if c == cmd then n = n + 1 end end
  return n
end

local OFF = "electrics.setLightsState(0)"

test("traffic headlights go off once when it clears by day, and not at night", function()
  local day = clearingRound("noon")
  day.tick(9)
  local cars = trafficCars(day)
  assertEq(#cars, 3)
  for _, obj in ipairs(cars) do
    assertEq(sent(obj, "electrics.setLightsState(1)") > 0, true)
    assertEq(sent(obj, OFF), 0)
  end
  day.tick(60)
  for _, obj in ipairs(cars) do assertEq(sent(obj, OFF), 0) end
  day.tick(3)
  for _, obj in ipairs(cars) do assertEq(sent(obj, OFF), 1) end
  day.tick(10)
  for _, obj in ipairs(cars) do assertEq(sent(obj, OFF), 1) end
  local night = clearingRound("night")
  night.tick(75)
  local dark = trafficCars(night)
  assertEq(#dark, 3)
  for _, obj in ipairs(dark) do assertEq(sent(obj, OFF), 0) end
  night.sky.state.time = 0
  night.tick(3)
  for _, obj in ipairs(dark) do assertEq(sent(obj, OFF), 1) end
end)
