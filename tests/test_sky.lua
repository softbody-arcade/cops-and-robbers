local sky = require("cnr.sky")
local weather = require("cnr.weather")
local config = require("cnr.config")

local function rng(roll, index)
  return function(m, n)
    if m == nil then return roll end
    if n == nil then return math.min(index, m) end
    return m
  end
end
local function cfg(o) return (config.merge(o)) end

test("pick rolls a weather seed and a schedule", function()
  local s = sky.pick(cfg(nil), rng(0.5, 1), 2026)
  assertEq(s.weatherSeed, 1)
  assertEq(type(s.changes), "table"); assertEq(type(s.temps), "table")
  assertEq(#s.temps >= 2, true)
  assertEq(s.releaseAt, 10)
  assertEq(type(s.gameStart), "number")
  local again = weather.build({ time = s.time, weather = s.weather, month = s.month, weatherSeed = 1 }, cfg(nil))
  assertEq(#s.changes, #again.changes)
  assertEq(s.changes[1].at, again.changes[1].at)
end)

test("payload carries the schedule", function()
  local changes = { { at = 100, to = "cloudy", forecastFrom = 50 } }
  local temps = { { t = -0.2, hour = 6, c = 3 }, { t = 0.1, hour = 14, c = 9 } }
  local s = { time = "noon", weather = "rain", windDir = 1, windSeed = 1, weatherSeed = 5, changes = changes, temps = temps, gameStart = 0.95, releaseAt = 10 }
  local p = sky.payload(s, cfg(nil), nil)
  assertEq(p.changes, changes); assertEq(p.temps, temps)
  assertEq(p.gameStart, 0.95); assertEq(p.releaseAt, 10)
  assertEq(p.weatherSeed, nil)
  p = sky.payload({ time = "noon", windDir = 1, windSeed = 1 }, cfg(nil), nil)
  assertEq(p.changes, nil); assertEq(p.temps, nil); assertEq(p.gameStart, nil); assertEq(p.releaseAt, nil)
end)

test("random choices are the default and still pick wind", function()
  local s = sky.pick(cfg(nil), rng(0.5, 1), 2026)
  assertEq(s.time, "sunrise"); assertEq(s.weather, "clear"); assertEq(s.windDir, 0); assertEq(s.windSeed, 1)
  assertEq(s.year, 2026); assertEq(s.month, 1); assertEq(s.day, 1)
end)

test("the date follows the weather", function()
  local s = sky.pick(cfg({ weather = "snow" }), rng(0.5, 1), 2026)
  assertEq(s.month, 12); assertEq(s.day, 1)
  assertEq(sky.pick(cfg({ weather = "fog" }), rng(0.5, 1), 2026).month, 10)
  assertEq(sky.pick(cfg({ weather = "rain" }), rng(0.5, 1), 2026).month, 3)
end)

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local WINDOWS = {
  snow = { 62, { [12] = true, [1] = true }, { 12, 1 }, { 1, 31 } },
  fog = { 61, { [10] = true, [11] = true }, { 10, 1 }, { 11, 30 } },
  rain = { 122, { [3] = true, [4] = true, [10] = true, [11] = true }, { 3, 1 }, { 11, 30 } },
  storm = { 122, { [3] = true, [4] = true, [10] = true, [11] = true }, { 3, 1 }, { 11, 30 } },
  clear = { 365, nil, { 1, 1 }, { 12, 31 } },
  cloudy = { 365, nil, { 1, 1 }, { 12, 31 } },
}

test("every date in a window exists and each day comes up once", function()
  for weather, w in pairs(WINDOWS) do
    local total, months, first, last = w[1], w[2], w[3], w[4]
    local seen, count = {}, 0
    for n = 1, total do
      local month, day = sky.date(weather, function(a, b) assertEq(a, 1); assertEq(b, total); return n end)
      assertEq(months == nil or months[month] == true, true)
      assertEq(day >= 1 and day <= DAYS[month], true)
      local key = month * 100 + day
      if not seen[key] then seen[key], count = true, count + 1 end
    end
    assertEq(count, total)
    local m1, d1 = sky.date(weather, function() return 1 end)
    assertEq(m1, first[1]); assertEq(d1, first[2])
    local m2, d2 = sky.date(weather, function() return total end)
    assertEq(m2, last[1]); assertEq(d2, last[2])
  end
  local m, d = sky.date("clear", function() return 60 end)
  assertEq(m, 3); assertEq(d, 1)
end)

test("the year defaults to the server's current year", function()
  assertEq(sky.pick(cfg(nil), rng(0.5, 1)).year, tonumber(os.date("%Y")))
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

test("hasRandom sees a random time or weather", function()
  assertEq(sky.hasRandom(cfg({ timeOfDay = "noon", weather = "clear" })), false)
  assertEq(sky.hasRandom(cfg(nil)), true)
  assertEq(sky.hasRandom(cfg({ timeOfDay = "noon" })), true)
  assertEq(sky.hasRandom(cfg({ weather = "clear" })), true)
end)

test("payload carries the date and the day length in seconds", function()
  local s = { time = "noon", weather = "snow", year = 2026, month = 12, day = 14, windDir = 1, windSeed = 2 }
  local p = sky.payload(s, cfg(nil), nil)
  assertEq(p.year, 2026); assertEq(p.month, 12); assertEq(p.day, 14); assertEq(p.daySeconds, 1800)
  assertEq(sky.payload(s, cfg({ dayLength = "fast" }), nil).daySeconds, 900)
  assertEq(sky.payload(s, cfg({ dayLength = "slow" }), nil).daySeconds, 7200)
  assertEq(sky.payload(s, cfg({ dayLength = "realtime" }), nil).daySeconds, 86400)
  assertEq(sky.payload(s, cfg({ dayLength = "off" }), nil).daySeconds, nil)
end)

test("payload sends driving only with a weather and the switch on", function()
  local s = { weather = "rain", windDir = 10, windSeed = 5 }
  assertEq(sky.payload(s, cfg({ weather = "rain" }), nil).driving, true)
  assertEq(sky.payload(s, cfg({ weather = "rain", weatherDriving = false }), nil).driving, nil)
  assertEq(sky.payload({ time = "night", windDir = 1, windSeed = 1 }, cfg(nil), nil).driving, nil)
  assertEq(sky.payload(s, cfg({ dayLength = "off" }), nil).daySeconds, nil)
end)

test("a missing sky has no payload", function()
  local c = cfg({ dayLength = "fast", weather = "rain" })
  assertEq(sky.payload(nil, c, nil), nil)
end)

test("payload passes clockSeconds", function()
  assertEq(sky.payload({ time = "noon", windDir = 1, windSeed = 1 }, cfg(nil), 12.5).clockSeconds, 12.5)
end)

test("record keeps the conditions without the wind", function()
  local s = { time = "night", weather = "rain", year = 2026, month = 3, day = 9, windDir = 3, windSeed = 9 }
  local r = sky.record(s, cfg({ weather = "rain", dayLength = "fast" }))
  assertEq(r.time, "night"); assertEq(r.weather, "rain"); assertEq(r.dayLength, "fast"); assertEq(r.driving, true)
  assertEq(r.year, 2026); assertEq(r.month, 3); assertEq(r.day, 9)
  assertEq(r.windSeed, nil); assertEq(r.windDir, nil); assertEq(r.daySeconds, nil)
  assertEq(sky.record({}, cfg(nil)), nil)
end)

test("record gives the worst weather and the start weather", function()
  local s = { weather = "cloudy", changes = { { at = 10, to = "rain" }, { at = 20, to = "storm" }, { at = 30, to = "cloudy" } } }
  local r = sky.record(s, cfg(nil), 35)
  assertEq(r.weather, "storm"); assertEq(r.weatherStart, "cloudy")
  assertEq(sky.record(s, cfg(nil), 15).weather, "rain")
  assertEq(sky.record(s, cfg(nil), 5).weather, "cloudy")
  assertEq(sky.record({ weather = "snow", changes = { { at = 1, to = "fog" } } }, cfg(nil), 5).weather, "snow")
  assertEq(sky.record({ weather = "fog", changes = { { at = 1, to = "snow" } } }, cfg(nil), 5).weather, "fog")
  assertEq(sky.record({ weather = "storm", changes = { { at = 1, to = "clear" } } }, cfg(nil), 5).weather, "storm")
end)
