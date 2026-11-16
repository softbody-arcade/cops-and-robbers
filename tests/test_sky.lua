local sky = require("cnr.sky")
local config = require("cnr.config")

local function rng(roll, index)
  return function(m, n)
    if m == nil then return roll end
    if n == nil then return math.min(index, m) end
    return m
  end
end
local function cfg(o) return (config.merge(o)) end

test("map choices pick no time or weather but still pick wind", function()
  local s = sky.pick(cfg(nil), rng(0.5, 1))
  assertEq(s.time, nil); assertEq(s.weather, nil); assertEq(s.windDir, 0); assertEq(s.windSeed, 1)
end)

test("fixed choices are kept", function()
  local s = sky.pick(cfg({ timeOfDay = "sunset", weather = "fog" }), rng(0.5, 1))
  assertEq(s.time, "sunset"); assertEq(s.weather, "fog")
end)

test("random time follows the night chance", function()
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 100 }), rng(0.99, 1)).time, "night")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 0 }), rng(0, 3)).time, "noon")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 25 }), rng(0.2499, 1)).time, "night")
  assertEq(sky.pick(cfg({ timeOfDay = "random", nightChancePercent = 25 }), rng(0.25, 1)).time, "sunrise")
end)

test("random weather follows the bad weather chance", function()
  assertEq(sky.pick(cfg({ weather = "random", badWeatherChancePercent = 100 }), rng(0.5, 4)).weather, "snow")
  assertEq(sky.pick(cfg({ weather = "random", badWeatherChancePercent = 0 }), rng(0.5, 2)).weather, "cloudy")
end)

test("nothing is picked on BeamNG.Earth", function()
  assertEq(next(sky.pick(cfg({ weather = "rain", timeOfDay = "night" }), rng(0, 1), true)), nil)
end)

test("hasRandom sees a random time or weather", function()
  assertEq(sky.hasRandom(cfg(nil)), false)
  assertEq(sky.hasRandom(cfg({ timeOfDay = "random" })), true)
  assertEq(sky.hasRandom(cfg({ weather = "random" })), true)
end)

test("payload is nil when the round sets nothing", function()
  assertEq(sky.payload({ windDir = 10, windSeed = 5 }, cfg(nil), nil), nil)
end)

test("payload carries a clock speed even with the map's own sky", function()
  local p = sky.payload({ windDir = 10, windSeed = 5 }, cfg({ clockSpeed = 30 }), nil)
  assertEq(p.clockSpeed, 30); assertEq(p.time, nil); assertEq(p.driving, nil); assertEq(p.windSeed, 5)
end)

test("payload sends driving only with a weather and the switch on", function()
  local s = { weather = "rain", windDir = 10, windSeed = 5 }
  assertEq(sky.payload(s, cfg({ weather = "rain" }), nil).driving, true)
  assertEq(sky.payload(s, cfg({ weather = "rain", weatherDriving = false }), nil).driving, nil)
  assertEq(sky.payload({ time = "night", windDir = 1, windSeed = 1 }, cfg(nil), nil).driving, nil)
  assertEq(sky.payload(s, cfg(nil), nil).clockSpeed, nil)
end)

test("nothing is sent on BeamNG.Earth, also with a clock speed", function()
  local c = cfg({ clockSpeed = 30, weather = "rain" })
  assertEq(sky.payload(sky.pick(c, rng(0, 1), true), c, nil), nil)
  assertEq(sky.payload(nil, c, nil), nil)
end)

test("payload passes clockSeconds", function()
  assertEq(sky.payload({ time = "noon", windDir = 1, windSeed = 1 }, cfg(nil), 12.5).clockSeconds, 12.5)
end)

test("record keeps the conditions without the wind", function()
  local r = sky.record({ time = "night", weather = "rain", windDir = 3, windSeed = 9 }, cfg({ weather = "rain", clockSpeed = 60 }))
  assertEq(r.time, "night"); assertEq(r.weather, "rain"); assertEq(r.clockSpeed, 60); assertEq(r.driving, true)
  assertEq(r.windSeed, nil); assertEq(r.windDir, nil)
  assertEq(sky.record({ windDir = 1, windSeed = 1 }, cfg(nil)), nil)
  assertEq(sky.record({}, cfg({ clockSpeed = 30 })), nil)
end)
