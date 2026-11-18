local weather = require("cnr.weather")
local config = require("cnr.config")
local sky = require("cnr.sky")

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

test("a time limit beyond the horizon schedules no further than no limit", function()
  local s = { time = "noon", weather = "clear", month = 4, weatherSeed = 5 }
  local week = cfg({ roundTimeLimitSeconds = 7 * 86400 })
  local none = cfg({ roundTimeLimitSeconds = 0 })
  assertEq(weather.endAt(week), weather.endAt(none))
  assertEq(#weather.build(s, week).changes, #weather.build(s, none).changes)
end)

test("turning points fall at 06:00 and 14:00 from the start on", function()
  local multiDay = cfg({ dayLength = "moderate", roundTimeLimitSeconds = 0 })
  local c = weather.climate({ time = "sunrise", weather = "clear", month = 1 }, multiDay, script({}, 0.5))
  local p = c.points
  assertEq(p[1].hour, 14); assertNear(p[1].t, -0.65, 1e-9)
  assertEq(p[2].hour, 6); assertNear(p[2].t, 1 / 60, 1e-9)
  assertNear(p[3].t - p[2].t, 1 / 3, 1e-9)
  assertNear(p[4].t - p[3].t, 2 / 3, 1e-9)
  local days = { 0, 0, 0, 1, 1, 2 }
  for i, d in ipairs(days) do assertEq(p[i].day, d, "day " .. i) end
  assertEq(p[#p].t >= weather.endAt(multiDay) / 1800 + 0.25, true)
  assertEq(p[#p - 1].t < weather.endAt(multiDay) / 1800 + 0.25, true)
  c = weather.climate({ time = "noon", weather = "clear", month = 1 }, multiDay, script({}, 0.5))
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

local WEATHERS = { "clear", "cloudy", "rain", "storm", "fog", "snow", "thunderstorm" }
local TIMES = { "sunrise", "morning", "noon", "afternoon", "sunset", "night" }

local function around(temps, d)
  local prev
  for _, p in ipairs(temps) do
    if d <= p.t then return prev, p end
    prev = p
  end
  return prev, nil
end

local function conditions(r, ds, at)
  local T = weather.temperature(r.temps, ds, at)
  local d = ds and at / ds or 0
  local tod = (r.gameStart + d) % 1
  local a, b = around(r.temps, d)
  local high = math.max(a and a.c or -math.huge, b and b.c or -math.huge)
  return T, T <= 12 and tod >= 0.25 and tod < 0.875, high >= 15, high >= 20
end

local function allowed(from, to, T, foggy, warm, hot)
  if from == "clear" then return to == "cloudy" or (to == "fog" and foggy) end
  if from == "cloudy" then
    return to == "clear" or (to == "rain" and T >= 2) or (to == "snow" and T <= 1) or (to == "fog" and foggy) or (to == "thunderstorm" and hot)
  end
  if from == "rain" then
    return to == "cloudy" or (to == "storm" and warm) or (to == "snow" and T <= 1) or (to == "thunderstorm" and hot)
  end
  if from == "storm" then return to == "rain" end
  if from == "snow" then return to == "cloudy" or (to == "rain" and T >= 2) end
  if from == "fog" then return to == "cloudy" or to == "clear" end
  if from == "thunderstorm" then return to == "rain" or to == "cloudy" end
  return false
end

local cases
local function eachCase(fn)
  if not cases then
    local list = {}
    for seed = 1, 30 do
      local dayLength = (math.floor(seed / 6) % 2 == 0) and "moderate" or "fast"
      local c = cfg({ roundTimeLimitSeconds = 1800, dayLength = dayLength })
      for _, month in ipairs({ 1, 4, 7, 10 }) do
        for _, time in ipairs(TIMES) do
          local s = { time = time, weather = WEATHERS[seed % #WEATHERS + 1], month = month }
          list[#list + 1] = { s = s, ds = weather.DAY_SECONDS[dayLength], r = weather.build(s, c, weather.seeded(seed)) }
        end
      end
    end
    cases = list
  end
  for _, k in ipairs(cases) do fn(k.s, k.r, k.ds) end
end

local function fingerprint(r)
  local parts = {}
  for _, ch in ipairs(r.changes) do
    parts[#parts + 1] = string.format("%s@%.9f/%.9f/%s/%s", ch.to, ch.at, ch.forecastFrom, tostring(ch.cross), tostring(ch.afterStay))
  end
  for _, p in ipairs(r.temps or {}) do
    parts[#parts + 1] = string.format("%d:%.9f:%.9f", p.hour, p.t, p.c)
  end
  return table.concat(parts, ";")
end

test("no changes with Weather changes off or without a weather; temps still come with a weather", function()
  local s = { time = "noon", weather = "rain", month = 3, weatherSeed = 7 }
  local r = weather.build(s, cfg({ weatherChanges = false }))
  assertEq(#r.changes, 0)
  assertEq(#r.temps >= 2, true)
  for _, p in ipairs(r.temps) do
    assertEq(type(p.t), "number"); assertEq(type(p.c), "number")
    assertEq(p.hour == 6 or p.hour == 14, true)
  end
  assertEq(r.releaseAt, 10)
  assertNear(r.gameStart, weather.gameStart(s, cfg(nil)), 1e-12)
  assertEq(#weather.build(s, cfg(nil)).changes > 0, true)
  r = weather.build({ time = "noon", month = 3, weatherSeed = 7 }, cfg(nil))
  assertEq(#r.changes, 0); assertEq(r.temps, nil); assertEq(r.releaseAt, 10)
  r = weather.build({}, cfg(nil))
  assertEq(#r.changes, 0); assertEq(r.temps, nil)
end)

test("Weather changes off fills every point with the start weather", function()
  local s = { time = "noon", weather = "storm", month = 4, weatherSeed = 3 }
  local c = cfg({ weatherChanges = false, dayLength = "fast" })
  local r = weather.build(s, c)
  local expect = weather.climate(s, c, weather.seeded(3))
  for j = 3, #expect.points do expect.points[j].c = weather.fill(expect, j, "storm") end
  assertEq(#r.temps, #expect.points)
  for j, p in ipairs(expect.points) do
    assertNear(r.temps[j].c, p.c, 1e-9); assertNear(r.temps[j].t, p.t, 1e-12); assertEq(r.temps[j].hour, p.hour)
  end
end)

test("each planned change is at least the minimum slot interval after release or the previous change", function()
  local n = 0
  eachCase(function(s, r)
    local before = r.releaseAt
    for _, ch in ipairs(r.changes) do
      if not ch.cross then
        local gap = ch.at - before
        assertEq(gap >= 180 - 1e-9, true, "gap " .. gap)
        n = n + 1
      end
      before = ch.at
    end
  end)
  assertEq(n > 500, true)
end)

test("changes end before the time limit or the three-hour horizon", function()
  for seed = 1, 10 do
    local s = { time = TIMES[seed % #TIMES + 1], weather = WEATHERS[seed % #WEATHERS + 1], month = 4 }
    local r = weather.build(s, cfg({ roundTimeLimitSeconds = 600 }), weather.seeded(seed))
    for _, ch in ipairs(r.changes) do assertEq(ch.at < r.releaseAt + 600, true) end
    r = weather.build(s, cfg(nil), weather.seeded(seed))
    for _, ch in ipairs(r.changes) do assertEq(ch.at < r.releaseAt + 10800, true) end
  end
end)

test("fixed slots align with release even when some slots stay", function()
  local s = { time = "noon", weather = "cloudy", month = 7, weatherSeed = 9 }
  local r = weather.build(s, cfg({ dayLength = "off", weatherChangeMinMinutes = 3, weatherChangeMaxMinutes = 3 }))
  local hasStay = false
  for _, ch in ipairs(r.changes) do
    assertEq((ch.at - r.releaseAt) % 180, 0)
    if ch.afterStay then hasStay = true end
  end
  assertEq(hasStay, true)
end)

test("one-minute slots without a stay reach slot 179 before the horizon", function()
  local s = { time = "noon", weather = "clear", month = 7 }
  local r = weather.build(s, cfg({ roundTimeLimitSeconds = 0, dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1 }), script({}, 0.75))
  for i, ch in ipairs(r.changes) do
    assertEq(ch.at, r.releaseAt + 60 * i)
    assertEq(ch.at < r.releaseAt + 10800, true)
    assertEq(ch.cross, nil)
    assertEq(ch.afterStay, nil)
  end
  assertEq(r.changes[#r.changes].at, r.releaseAt + 179 * 60)
end)

test("Day length Off: slots still come, crossings never", function()
  local months = { clear = 1, cloudy = 7, rain = 4, storm = 3, fog = 10, snow = 12, thunderstorm = 7 }
  local n = 0
  for seed = 1, 30 do
    local w = WEATHERS[seed % #WEATHERS + 1]
    local s = { time = TIMES[math.floor(seed / #WEATHERS) % #TIMES + 1], weather = w, month = months[w] }
    local r = weather.build(s, cfg({ roundTimeLimitSeconds = 0, dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 2 }), weather.seeded(seed))
    assertEq(#r.temps, 2)
    for _, ch in ipairs(r.changes) do
      assertEq(ch.cross, nil)
      n = n + 1
    end
  end
  assertEq(n > 1000, true)
end)

test("each slot change goes to an allowed neighbour", function()
  local n = 0
  eachCase(function(s, r, ds)
    for i, ch in ipairs(r.changes) do
      if not ch.cross then
        local from = i > 1 and r.changes[i - 1].to or s.weather
        local T, foggy, warm, hot = conditions(r, ds, ch.at)
        assertEq(allowed(from, ch.to, T, foggy, warm, hot), true, from .. " -> " .. ch.to .. " at " .. T)
        n = n + 1
      end
    end
  end)
  assertEq(n > 500, true)
end)

test("planned picks roll group then weight", function()
  local cases = {
    { "cloudy", 25, { 0.24999, 2 / 3 - 1e-9 }, "rain" },
    { "cloudy", 25, { 0.24999, 2 / 3 }, "thunderstorm" },
    { "cloudy", 25, { 0.25, 0.75 }, "clear" },
    { "cloudy", 0, { 0, 0.75 }, "clear" },
    { "cloudy", 100, { 0.99999, 0 }, "rain" },
    { "rain", 25, { 0, 1 / 3 - 1e-9 } },
    { "rain", 25, { 0, 1 / 3 }, "storm" },
    { "rain", 25, { 0, 2 / 3 - 1e-9 }, "storm" },
    { "rain", 25, { 0, 2 / 3 }, "thunderstorm" },
    { "clear", 100, { 0.75 }, "cloudy" },
    { "storm", 0, { 1 }, "rain" },
    { "thunderstorm", 100, { 0, 1 }, "rain" },
  }
  for i, k in ipairs(cases) do
    local s = { time = "noon", weather = k[1], month = 7 }
    local c = cfg({ dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1,
      roundTimeLimitSeconds = 120, badWeatherChancePercent = k[2] })
    local draws = { 0.5, 0 }
    for _, value in ipairs(k[3]) do draws[#draws + 1] = value end
    local r = weather.build(s, c, script(draws, 0))
    assertEq(#r.changes, k[4] and 1 or 0, "case " .. i)
    assertEq(r.changes[1] and r.changes[1].to, k[4], "case " .. i)
  end
end)

test("stay consumes a slot, not a change", function()
  local s = { time = "noon", weather = "cloudy", month = 7 }
  local c = cfg({ dayLength = "off", weatherChangeMinMinutes = 3, weatherChangeMaxMinutes = 3,
    roundTimeLimitSeconds = 400, badWeatherChancePercent = 25 })
  local r = weather.build(s, c, script({ 0.5, 0, 0.9, 0, 0, 0.9, 0.75, 0.5, 0 }, 0))
  local p = sky.payload({ weather = s.weather, changes = r.changes, releaseAt = r.releaseAt }, c)
  assertEq(#r.changes, 1)
  assertEq(p.changes, r.changes)
  local ch = p.changes[1]
  assertEq(ch.to, "clear")
  assertEq(ch.at, r.releaseAt + 360)
  assertEq(ch.afterStay, true)
  assertEq(ch.forecastFrom, r.releaseAt + 300)
  assertEq(#weather.build(s, c, script({ 0.5, 0, 0.9, 0, 0, 0.9, 0, 0 }, 0)).changes, 0)
end)

test("only the first forecast after a stay is clamped to its slot", function()
  local s = { time = "noon", weather = "cloudy", month = 7 }
  local c = cfg({ dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1,
    roundTimeLimitSeconds = 200, badWeatherChancePercent = 25 })
  local r = weather.build(s, c, script({ 0.5, 0, 0.9, 0, 0, 0.9, 0.75, 1, 0, 0.75, 1, 0 }, 0))
  assertEq(#r.changes, 2)
  assertEq(r.changes[1].at, r.releaseAt + 120)
  assertEq(r.changes[1].forecastFrom, r.releaseAt + 60)
  assertEq(r.changes[1].afterStay, true)
  assertEq(r.changes[2].at, r.releaseAt + 180)
  assertEq(r.changes[2].forecastFrom, r.releaseAt + 60)
  assertEq(r.changes[2].afterStay, nil)
end)

test("cloudy and rain can turn to a thunderstorm when the higher point reaches 20 C", function()
  local c = cfg({ dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1,
    roundTimeLimitSeconds = 120, badWeatherChancePercent = 100 })
  for _, k in ipairs({ { "cloudy", 5, 0.5, "rain" }, { "rain", 6, 0.125, "storm" } }) do
    local s = { time = "sunrise", weather = k[1], month = k[2] }
    local hot = weather.build(s, c, script({ k[3] }, 0.999))
    local cool = weather.build(s, c, script({ k[3] - 0.015625 }, 0.999))
    assertEq(hot.temps[2].c, 20)
    assertEq(cool.temps[2].c, 19.875)
    assertEq(weather.temperature(hot.temps, nil, hot.changes[1].at) < 20, true)
    assertEq(hot.changes[1].to, "thunderstorm", s.weather)
    assertEq(cool.changes[1].to, k[4], s.weather)
  end
end)

test("a summer round never sees snow", function()
  local n = 0
  for seed = 1, 50 do
    for month = 6, 8 do
      local s = { time = TIMES[seed % 6 + 1], weather = (seed % 2 == 0) and "clear" or "cloudy", month = month }
      local r = weather.build(s, cfg({ dayLength = "fast", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 3, roundTimeLimitSeconds = 3600 }), weather.seeded(seed))
      for _, ch in ipairs(r.changes) do
        assertEq(ch.to ~= "snow", true)
        n = n + 1
      end
    end
  end
  assertEq(n > 1000, true)
end)

test("every forecast window is 120 s and contains its change", function()
  local n = 0
  eachCase(function(s, r)
    for _, ch in ipairs(r.changes) do
      assertEq(ch.forecastFrom >= ch.at - 120 and ch.forecastFrom <= ch.at, true)
      n = n + 1
    end
  end)
  assertEq(n > 500, true)
end)

test("the same seed gives the same schedule, another seed another one", function()
  local c = cfg({ dayLength = "fast" })
  local s = { time = "night", weather = "cloudy", month = 1, weatherSeed = 42 }
  local a = weather.build(s, c)
  local b = weather.build(s, c)
  assertEq(#a.changes > 0, true)
  assertEq(fingerprint(a), fingerprint(b))
  assertEq(fingerprint(a), fingerprint(weather.build(s, c, weather.seeded(42))))
  s.weatherSeed = 43
  assertEq(fingerprint(weather.build(s, c)) ~= fingerprint(a), true)
end)

local function noSlots(o)
  local t = { dayLength = "fast", weatherChangeMinMinutes = 1000, weatherChangeMaxMinutes = 1000 }
  for k, v in pairs(o or {}) do t[k] = v end
  return cfg(t)
end

test("rain turns to snow at 1 C and back to rain at 2 C", function()
  for _, chance in ipairs({ 0, 100 }) do
    local r = weather.build({ time = "night", weather = "rain", month = 3 }, noSlots({ badWeatherChancePercent = chance }), script({}, 0))
    local ch = r.changes
    assertEq(ch[1].to, "snow"); assertEq(ch[1].cross, true)
    assertNear(weather.temperature(r.temps, 900, ch[1].at), 1, 0.05)
    assertEq(ch[2].to, "rain"); assertEq(ch[2].cross, true)
    assertNear(weather.temperature(r.temps, 900, ch[2].at), 2, 0.05)
    assertEq(r.temps[4].c, 0)
    assertEq(r.temps[5].c, 5)
  end
end)

test("a storm that gets that cold becomes rain, then snow when the change ends", function()
  local r = weather.build({ time = "night", weather = "storm", month = 3 }, noSlots(), script({ 0.25 }, 0))
  local ch = r.changes
  assertEq(ch[1].to, "rain"); assertEq(ch[1].cross, true)
  assertNear(weather.temperature(r.temps, 900, ch[1].at), 1, 0.05)
  assertEq(ch[2].to, "snow"); assertEq(ch[2].cross, true)
  assertNear(ch[2].at, ch[1].at + 60, 1e-9)
end)

test("a thunderstorm cools through 1 C to rain, then to snow after 60 seconds", function()
  local r = weather.build({ time = "afternoon", weather = "thunderstorm", month = 1 }, noSlots(), script({ 0.25 }, 0))
  local ch = r.changes
  assertEq(#ch >= 2, true)
  assertEq(weather.temperature(r.temps, 900, r.releaseAt) > 1, true)
  assertEq(ch[1].to, "rain"); assertEq(ch[1].cross, true)
  assertNear(weather.temperature(r.temps, 900, ch[1].at), 1, 1e-9)
  assertEq(ch[2].to, "snow"); assertEq(ch[2].cross, true)
  assertNear(ch[2].at, ch[1].at + 60, 1e-9)
  assertEq(weather.temperature(r.temps, 900, ch[2].at) <= 1, true)
end)

test("fog lifts at 09:00", function()
  local r = weather.build({ time = "sunrise", weather = "fog", month = 10 }, noSlots(), script({}, 0.5))
  local ch = r.changes[1]
  assertNear(ch.at, (0.875 - (0.775 - 1 / 24)) * 900, 1e-6)
  assertEq(ch.to, "clear"); assertEq(ch.cross, true)
end)

test("a stay does not postpone a forced fog lift", function()
  local s = { time = "sunrise", weather = "fog", month = 10 }
  local c = cfg({ dayLength = "fast", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1,
    roundTimeLimitSeconds = 150, badWeatherChancePercent = 100 })
  local r = weather.build(s, c, script({}, 0.5))
  assertEq(#r.changes, 1)
  local ch = r.changes[1]
  assertNear(ch.at, 127.5, 1e-6)
  assertEq(ch.to, "clear")
  assertEq(ch.cross, true)
  assertEq(ch.afterStay, true)
  assertEq(ch.forecastFrom, r.releaseAt + 60)
end)

test("fog lifts when it warms above 12 C", function()
  local r = weather.build({ time = "night", weather = "fog", month = 10 }, noSlots(), script({}, 0.6875))
  assertEq(weather.temperature(r.temps, 900, r.releaseAt) > 12, true)
  local ch = r.changes[1]
  assertEq(ch.cross, true); assertEq(ch.to, "clear")
  assertNear(weather.temperature(r.temps, 900, ch.at), 12, 0.05)
  local tod = (r.gameStart + ch.at / 900) % 1
  assertEq(tod > 0.75 and tod < 0.875, true)
end)

test("a fog crossing at the turning point just filled refills it with the new weather", function()
  local r = weather.build({ time = "night", weather = "fog", month = 10 }, noSlots(), script({ 0.75 }, 0.5))
  assertEq(r.temps[2].c, 12)
  local ch = r.changes[1]
  assertEq(ch.cross, true); assertEq(ch.to, "clear")
  assertNear(ch.at, r.temps[2].t * 900, 1e-6)
  assertEq(r.temps[3].c, 22)
end)

test("a crossing during a change waits for its end", function()
  local kinds = { "rain", "snow", "storm", "fog", "cloudy", "thunderstorm" }
  local months = { 1, 3, 12, 10 }
  local crossings, waited = 0, 0
  for seed = 1, 50 do
    local s = { time = TIMES[seed % #TIMES + 1], weather = kinds[seed % #kinds + 1], month = months[seed % #months + 1] }
    local r = weather.build(s, cfg({ roundTimeLimitSeconds = 0, dayLength = "fast", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 2 }), weather.seeded(seed))
    for i, ch in ipairs(r.changes) do
      if ch.cross then
        crossings = crossings + 1
        if i > 1 then
          local gap = ch.at - r.changes[i - 1].at
          assertEq(gap >= 60 - 1e-9, true, "gap " .. gap)
          if gap < 60 + 1e-9 then waited = waited + 1 end
        end
      end
    end
  end
  assertEq(crossings > 50, true)
  assertEq(waited > 0, true)
end)

test("in effect is the last change started", function()
  local s = { weather = "rain", changes = { { at = 40, to = "storm" }, { at = 200, to = "rain" }, { at = 500, to = "snow" } } }
  assertEq(weather.at(s, 0), "rain")
  assertEq(weather.at(s, 40), "storm")
  assertEq(weather.at(s, 199), "storm")
  assertEq(weather.at(s, 200), "rain")
  assertEq(weather.at(s, 900), "snow")
  assertEq(weather.at({ weather = "fog" }, 10), "fog")
  assertEq(weather.at(nil, 10), nil)
end)

test("grounded while a grounding weather is in effect or still clearing", function()
  local s = { weather = "rain", changes = { { at = 40, to = "storm" }, { at = 200, to = "rain" }, { at = 500, to = "cloudy" }, { at = 700, to = "fog" }, { at = 800, to = "snow" } } }
  assertEq(weather.groundedAt(s, 39), nil)
  assertEq(weather.groundedAt(s, 40), "storm")
  assertEq(weather.groundedAt(s, 200), "storm")
  assertEq(weather.groundedAt(s, 259.9), "storm")
  assertEq(weather.groundedAt(s, 260), nil)
  assertEq(weather.groundedAt(s, 520), nil)
  assertEq(weather.groundedAt(s, 700), "fog")
  assertEq(weather.groundedAt(s, 830), "snow")
  assertEq(weather.groundedAt({ weather = "fog" }, 0), "fog")
  assertEq(weather.groundedAt({ weather = "clear" }, 0), nil)
  assertEq(weather.groundedAt({}, 0), nil)
  assertEq(weather.groundedAt(nil, 0), nil)
end)

test("a thunderstorm grounds the helicopter from entry through the end of its exit blend", function()
  local s = { weather = "cloudy", changes = { { at = 40, to = "thunderstorm" }, { at = 200, to = "rain" } } }
  assertEq(weather.groundedAt(s, 39.9), nil)
  assertEq(weather.groundedAt(s, 40), "thunderstorm")
  assertEq(weather.groundedAt(s, 200), "thunderstorm")
  assertEq(weather.groundedAt(s, 259.9), "thunderstorm")
  assertEq(weather.groundedAt(s, 260), nil)
  assertEq(weather.groundedAt({ weather = "thunderstorm" }, 0), "thunderstorm")
end)

test("no missed crossing: a fitted weather fits until the next change, and a crossing comes when it stops fitting", function()
  local list = {}
  for seed, w in ipairs(WEATHERS) do
    for _, month in ipairs({ 1, 4, 7, 10 }) do
      local dayLength = (seed % 2 == 0) and "fast" or "moderate"
      local lo = (seed % 7) + 1
      local c = cfg({ roundTimeLimitSeconds = 1800, dayLength = dayLength, weatherChangeMinMinutes = lo, weatherChangeMaxMinutes = lo })
      local s = { time = TIMES[(seed - 1) % #TIMES + 1], weather = w, month = month }
      list[#list + 1] = { r = weather.build(s, c, weather.seeded(seed)), ds = weather.DAY_SECONDS[dayLength], c = c, s = s }
    end
  end
  for seed = 1, 4 do
    for _, month in ipairs({ 3, 11 }) do
      local c = cfg({ roundTimeLimitSeconds = 1800, dayLength = "fast", weatherChangeMinMinutes = 25, weatherChangeMaxMinutes = 25 })
      for _, w in ipairs({ "storm", "thunderstorm" }) do
        local s = { time = TIMES[seed], weather = w, month = month }
        list[#list + 1] = { r = weather.build(s, c, weather.seeded(seed)), ds = weather.DAY_SECONDS.fast, c = c, s = s }
      end
    end
  end
  local storms, delayed = { storm = 0, thunderstorm = 0 }, 0
  for _, k in ipairs(list) do
    local r, ds = k.r, k.ds
    assertEq(r.temps ~= nil, true, k.s.weather)
    local from, to = r.releaseAt, weather.endAt(k.c)
    local ci, cur, fitted, runUntil = 1, k.s.weather, false, nil
    local function fit(w, t)
      local T = weather.temperature(r.temps, ds, t)
      local tod = (r.gameStart + t / ds) % 1
      if w == "fog" then return T <= 12 and (tod >= 0.25 and tod < 0.875) end
      if w == "snow" then return T < 2 end
      if w == "rain" or w == "storm" or w == "thunderstorm" then return T > 1 end
      return true
    end
    for t = from, to - 1 do
      while r.changes[ci] and r.changes[ci].at <= t + 1e-9 do
        local ch = r.changes[ci]
        if ch.cross then
          if storms[cur] then storms[cur] = storms[cur] + 1 end
          if ci > 1 and ch.at - r.changes[ci - 1].at < weather.CHANGE_SECONDS + 1e-9 then delayed = delayed + 1 end
          local context = string.format("%s at %s in month %d: %s -> %s at %.3f s", k.s.weather, k.s.time, k.s.month, cur, ch.to, ch.at)
          assertEq(fit(cur, ch.at - 1e-3) and fit(cur, ch.at) and fit(cur, ch.at + 1e-3), false, context)
        end
        cur, fitted, runUntil = ch.to, false, ch.at + weather.CHANGE_SECONDS
        ci = ci + 1
      end
      if runUntil and t >= runUntil then runUntil, fitted = nil, fit(cur, t) end
      if not runUntil then
        if fitted then
          local nxt = r.changes[ci]
          if not (nxt and nxt.at <= t + 1) then assertEq(fit(cur, t), true) end
        elseif fit(cur, t) then fitted = true end
      end
    end
  end
  assertEq(storms.storm > 0, true)
  assertEq(storms.thunderstorm > 0, true)
  assertEq(delayed > 0, true)
end)
