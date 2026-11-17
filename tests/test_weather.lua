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

local WEATHERS = { "clear", "cloudy", "rain", "storm", "fog", "snow" }
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
  return T, T <= 12 and tod >= 0.25 and tod < 0.875, high >= 15
end

local function allowed(from, to, T, foggy, warm)
  if from == "clear" then return to == "cloudy" or (to == "fog" and foggy) end
  if from == "cloudy" then return to == "clear" or (to == "rain" and T >= 2) or (to == "snow" and T <= 1) or (to == "fog" and foggy) end
  if from == "rain" then return to == "cloudy" or (to == "storm" and warm) or (to == "snow" and T <= 1) end
  if from == "storm" then return to == "rain" end
  if from == "snow" then return to == "cloudy" or (to == "rain" and T >= 2) end
  if from == "fog" then return to == "cloudy" or to == "clear" end
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
          local s = { time = time, weather = WEATHERS[seed % 6 + 1], month = month }
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
    parts[#parts + 1] = string.format("%s@%.9f/%.9f/%s", ch.to, ch.at, ch.forecastFrom, tostring(ch.cross))
  end
  for _, p in ipairs(r.temps or {}) do
    parts[#parts + 1] = string.format("%d:%.9f:%.9f", p.hour, p.t, p.c)
  end
  return table.concat(parts, ";")
end

test("no changes with Weather changes off, without a weather or on Earth; temps still come with a weather", function()
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

test("each slot change comes min to max after the change before it, the first after the release", function()
  local n = 0
  eachCase(function(s, r)
    local before = r.releaseAt
    for _, ch in ipairs(r.changes) do
      if not ch.cross then
        local gap = ch.at - before
        assertEq(gap >= 180 - 1e-9 and gap <= 480 + 1e-9, true, "gap " .. gap)
        n = n + 1
      end
      before = ch.at
    end
  end)
  assertEq(n > 500, true)
end)

test("changes run up to the time limit, or 180 minutes without one", function()
  for seed = 1, 10 do
    local s = { time = TIMES[seed % 6 + 1], weather = WEATHERS[seed % 6 + 1], month = 4 }
    local r = weather.build(s, cfg({ roundTimeLimitSeconds = 600 }), weather.seeded(seed))
    assertEq(#r.changes > 0, true)
    for _, ch in ipairs(r.changes) do assertEq(ch.at < r.releaseAt + 600, true) end
    r = weather.build(s, cfg(nil), weather.seeded(seed))
    local last = r.changes[#r.changes]
    assertEq(last.at < r.releaseAt + 10800, true)
    assertEq(last.at + 480 > r.releaseAt + 10800, true)
  end
end)

test("no count cap", function()
  local r = weather.build({ time = "noon", weather = "clear", month = 7 }, cfg({ weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 1 }), weather.seeded(9))
  assertEq(#r.changes, 179)
  for i, ch in ipairs(r.changes) do
    assertNear(ch.at, r.releaseAt + 60 * i, 1e-9)
    assertEq(ch.cross, nil)
  end
end)

test("Day length Off: slots still come, crossings never", function()
  local months = { clear = 1, cloudy = 7, rain = 4, storm = 3, fog = 10, snow = 12 }
  local n = 0
  for seed = 1, 30 do
    local w = WEATHERS[seed % 6 + 1]
    local s = { time = TIMES[math.floor(seed / 6) % 6 + 1], weather = w, month = months[w] }
    local r = weather.build(s, cfg({ dayLength = "off", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 2 }), weather.seeded(seed))
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
        local T, foggy, warm = conditions(r, ds, ch.at)
        assertEq(allowed(from, ch.to, T, foggy, warm), true, from .. " -> " .. ch.to .. " at " .. T)
        n = n + 1
      end
    end
  end)
  assertEq(n > 500, true)
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
  local r = weather.build({ time = "night", weather = "rain", month = 3 }, noSlots(), script({}, 0))
  local ch = r.changes
  assertEq(ch[1].to, "snow"); assertEq(ch[1].cross, true)
  assertNear(weather.temperature(r.temps, 900, ch[1].at), 1, 0.05)
  assertEq(ch[2].to, "rain"); assertEq(ch[2].cross, true)
  assertNear(weather.temperature(r.temps, 900, ch[2].at), 2, 0.05)
  assertEq(r.temps[4].c, 0)
  assertEq(r.temps[5].c, 5)
end)

test("a storm that gets that cold becomes rain, then snow when the change ends", function()
  local r = weather.build({ time = "night", weather = "storm", month = 3 }, noSlots(), script({ 0.25 }, 0))
  local ch = r.changes
  assertEq(ch[1].to, "rain"); assertEq(ch[1].cross, true)
  assertNear(weather.temperature(r.temps, 900, ch[1].at), 1, 0.05)
  assertEq(ch[2].to, "snow"); assertEq(ch[2].cross, true)
  assertNear(ch[2].at, ch[1].at + 60, 1e-9)
end)

test("fog lifts at 09:00", function()
  local r = weather.build({ time = "sunrise", weather = "fog", month = 10 }, noSlots(), script({}, 0.5))
  local ch = r.changes[1]
  assertNear(ch.at, (0.875 - (0.775 - 1 / 24)) * 900, 1e-6)
  assertEq(ch.to, "clear"); assertEq(ch.cross, true)
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

test("a crossing during a change waits for its end", function()
  local kinds = { "rain", "snow", "storm", "fog", "cloudy" }
  local months = { 1, 3, 12, 10 }
  local crossings, waited = 0, 0
  for seed = 1, 50 do
    local s = { time = TIMES[seed % 6 + 1], weather = kinds[seed % 5 + 1], month = months[seed % 4 + 1] }
    local r = weather.build(s, cfg({ dayLength = "fast", weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 2 }), weather.seeded(seed))
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
