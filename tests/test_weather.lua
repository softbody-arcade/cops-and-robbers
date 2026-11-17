local weather = require("cnr.weather")
local config = require("cnr.config")

local function cfg(o) return (config.merge(o)) end
local function script(list, rest)
  local i = 0
  return function()
    i = i + 1
    if list[i] ~= nil then return list[i] end
    return rest
  end
end

test("the game time starts at the time key minus the lead", function()
  local s = { time = "sunrise" }
  assertNear(weather.gameStart(s, cfg({ dayLength = "fast" })), 0.775 - 1 / 24, 1e-9)
  assertNear(weather.gameStart(s, cfg({ dayLength = "moderate" })), 0.775 - 1 / 24, 1e-9)
  assertNear(weather.gameStart(s, cfg({ dayLength = "slow" })), 0.775 - 75 / 7200, 1e-9)
  assertNear(weather.gameStart(s, cfg({ dayLength = "off" })), 0.775, 1e-9)
end)

test("the release and end of a round", function()
  local c = cfg({ runnerCountdownSeconds = 3, headStartSeconds = 7, roundTimeLimitSeconds = 0 })
  assertEq(weather.releaseAt(c), 10)
  assertEq(weather.endAt(c), 10 + weather.HORIZON_SECONDS)
  c = cfg({ runnerCountdownSeconds = 3, headStartSeconds = 7, roundTimeLimitSeconds = 600 })
  assertEq(weather.endAt(c), 610)
end)

test("turning points fall at 06:00 and 14:00 from the start on", function()
  local c = weather.climate({ time = "sunrise", weather = "clear", month = 1 }, cfg({ dayLength = "moderate" }), script({}, 0.5))
  local p = c.points
  assertEq(p[1].hour, 14); assertNear(p[1].t, -0.65, 1e-9)
  assertEq(p[2].hour, 6); assertNear(p[2].t, 1 / 60, 1e-9)
  assertNear(p[3].t - p[2].t, 1 / 3, 1e-9)
  assertNear(p[4].t - p[3].t, 2 / 3, 1e-9)
  local days = { 0, 0, 0, 1, 1, 2 }
  for i, d in ipairs(days) do assertEq(p[i].day, d, "day " .. i) end
  assertEq(p[#p].t >= weather.endAt(cfg({ dayLength = "moderate" })) / 1800 + 0.25, true)
  assertEq(p[#p - 1].t < weather.endAt(cfg({ dayLength = "moderate" })) / 1800 + 0.25, true)
  c = weather.climate({ time = "noon", weather = "clear", month = 1 }, cfg({ dayLength = "moderate" }), script({}, 0.5))
  assertEq(c.points[1].hour, 6)
  assertEq(c.points[1].day, 0); assertEq(c.points[2].day, 0); assertEq(c.points[3].day, 1)
  c = weather.climate({ time = "noon", weather = "clear", month = 1 }, cfg({ dayLength = "off" }), script({}, 0.5))
  assertEq(#c.points, 2)
  assertEq(weather.climate({ weather = "clear", month = 1 }, cfg(nil), script({}, 0.5)), nil)
  assertEq(weather.climate({ time = "noon", month = 1 }, cfg(nil), script({}, 0.5)), nil)
  assertEq(weather.climate({ time = "noon", weather = "clear" }, cfg(nil), script({}, 0.5)), nil)
end)

test("day shifts walk within their limits", function()
  local s = { time = "noon", weather = "clear", month = 1 }
  local c = weather.climate(s, cfg({ dayLength = "fast" }), script({}, 1))
  assertEq(c.shifts[0], 4); assertEq(c.shifts[1], 6); assertEq(c.shifts[2], 6)
  c = weather.climate(s, cfg({ dayLength = "fast" }), script({}, 0))
  assertEq(c.shifts[0], -4); assertEq(c.shifts[1], -6); assertEq(c.shifts[2], -6)
  for seed = 1, 100 do
    c = weather.climate(s, cfg({ dayLength = "fast" }), weather.seeded(seed))
    assertEq(math.abs(c.shifts[0]) <= 4, true)
    local d = 1
    while c.shifts[d] do
      assertEq(math.abs(c.shifts[d] - c.shifts[d - 1]) <= 3 + 1e-9, true)
      assertEq(math.abs(c.shifts[d]) <= 6, true)
      d = d + 1
    end
    assertEq(d > 2, true)
  end
end)

test("the points around the start use the start range plus day 0's shift", function()
  local c = weather.climate({ time = "noon", weather = "cloudy", month = 1 }, cfg({ dayLength = "moderate" }), script({ 0.75 }, 0.5))
  assertEq(c.points[1].hour, 6); assertEq(c.points[1].c, 4)
  assertEq(c.points[2].hour, 14); assertEq(c.points[2].c, 7)
end)

test("a snow start stays at or below 0 C at its high", function()
  local c = weather.climate({ time = "noon", weather = "snow", month = 1 }, cfg({ dayLength = "moderate" }), script({ 1 }, 0.5))
  assertEq(c.shifts[0], 0)
  assertEq(c.points[2].c, -1)
end)

test("a later point takes the normal, the day's shift and the weather before it", function()
  local c = weather.climate({ time = "noon", weather = "clear", month = 1 }, cfg({ dayLength = "moderate" }), script({}, 0.5))
  assertEq(c.shifts[1], 0)
  assertEq(c.points[3].hour, 6); assertEq(c.points[4].hour, 14)
  assertEq(weather.fill(c, 3, "clear"), 0)
  assertEq(weather.fill(c, 3, "cloudy"), 2)
  assertEq(weather.fill(c, 3, "snow"), 2)
  c.points[3].c = 0
  assertEq(weather.fill(c, 4, "clear"), 8)
  c.points[3].c = 10
  assertEq(weather.fill(c, 4, "storm"), 12)
  c.shifts[1] = 3
  assertEq(weather.fill(c, 3, "clear"), 3)
end)

test("the temperature is linear between points, like the game's curve", function()
  local points = { { t = -0.5, c = 2 }, { t = 0.5, c = 10 }, { t = 1.5 } }
  assertNear(weather.temperature(points, 1000, 0), 6, 1e-9)
  assertNear(weather.temperature(points, 1000, 500), 10, 1e-9)
  assertNear(weather.temperature(points, 1000, 250), 8, 1e-9)
  assertNear(weather.temperature(points, 1000, 900), 10, 1e-9)
  assertNear(weather.temperature(points, 1000, -900), 2, 1e-9)
  assertNear(weather.temperature(points, nil, 0), 6, 1e-9)
  assertNear(weather.temperature(points, nil, 99), 6, 1e-9)
end)
