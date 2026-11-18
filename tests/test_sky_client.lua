dofile("tests/env_stubs.lua")
local function load(opts)
  local fake = fakeEnvironment(opts)
  for _, n in ipairs({ "copsAndRobbers/sky", "copsAndRobbers/rain", "copsAndRobbers/surfaces", "copsAndRobbers/wind", "copsAndRobbers/shelter" }) do package.loaded[n] = nil end
  return require("copsAndRobbers/sky"), fake
end
local RAIN_NIGHT = { time = "night", weather = "rain", driving = true, windDir = 90, windSeed = 7 }

test("labels join the time and the weather", function()
  local sky = load()
  assertEq(sky.label(RAIN_NIGHT), "Night · Rain")
  assertEq(sky.label({ weather = "snow" }), "Snow")
  assertEq(sky.label({ weather = "thunderstorm" }), "Thunderstorm")
  assertEq(sky.label({ daySeconds = 1800 }), nil)
end)

local WINTER = { time = "sunrise", weather = "snow", year = 2026, month = 12, day = 14, windDir = 0, windSeed = 1 }

local function withTemps(p, low, high)
  local q = {}
  for k, v in pairs(p) do q[k] = v end
  q.temps = { { t = -0.1, hour = 6, c = low }, { t = 0.2, hour = 14, c = high } }
  return q
end

test("labels end with the date only when asked", function()
  local sky = load()
  assertEq(sky.label(withTemps(WINTER, -4, 0), true), "Sunrise · Snow · 14 Dec · -4 to 0 °C")
  assertEq(sky.label(withTemps(WINTER, -4, 0)), "Sunrise · Snow")
  assertEq(sky.label(withTemps({ time = "noon", weather = "clear", month = 1, day = 3 }, 0, 8), true), "Noon · Clear · 3 Jan · 0 to 8 °C")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 13, day = 3 }, true), "Noon · Clear")
end)

test("the label shows the range in Fahrenheit when the game does", function()
  local sky = load()
  local saved = _G.settings
  _G.settings = { getValue = function(k) return k == "uiUnitTemperature" and "f" or nil end }
  local label = sky.label(withTemps(WINTER, -4, 0), true)
  _G.settings = saved
  assertEq(label, "Sunrise · Snow · 14 Dec · 25 to 32 °F")
end)

test("a label without turning points has no temperature", function()
  local sky = load()
  assertEq(sky.label({ time = "noon", weather = "clear", day = 3 }, true), "Noon · Clear")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 3 }, true), "Noon · Clear · 3 Jan")
  assertEq(sky.label({ time = "noon", weather = "hail", month = 1, day = 3 }, true), "Noon · Hail · 3 Jan")
end)

test("old runs without a date still get a label", function()
  local sky = load()
  assertEq(sky.label({ time = "night", weather = "rain", clockSpeed = 60 }), "Night · Rain")
end)

test("the round's date is set with the time", function()
  local sky, fake = load()
  sky.apply(WINTER)
  local s = fake.setStates[1]
  assertEq(s.year, 2026); assertEq(s.month, 12); assertEq(s.day, 14); assertEq(s.time, 0.775)
end)

test("with a moving clock the round starts an hour before the named time", function()
  local sky, fake = load()
  local p = {}
  for k, v in pairs(WINTER) do p[k] = v end
  p.daySeconds = 1800
  sky.apply(p)
  assertEq(math.abs(fake.setStates[1].time - (0.775 - 1 / 24)) < 1e-9, true, tostring(fake.setStates[1].time))
  local sky2, fake2 = load()
  sky2.apply({ time = "noon", weather = "clear", year = 2026, month = 6, day = 14, windDir = 0, windSeed = 1, daySeconds = 900 })
  assertEq(math.abs(fake2.setStates[1].time - (1 - 1 / 24)) < 1e-9, true, tostring(fake2.setStates[1].time))
end)

test("on a slow clock the lead is at most 75 s of real time", function()
  for _, daySeconds in ipairs({ 7200, 86400 }) do
    local sky, fake = load()
    local p = {}
    for k, v in pairs(WINTER) do p[k] = v end
    p.daySeconds = daySeconds
    sky.apply(p)
    local want = 0.775 - 75 / daySeconds
    assertEq(math.abs(fake.setStates[1].time - want) < 1e-9, true, daySeconds .. ": " .. tostring(fake.setStates[1].time))
  end
end)

test("with the clock stopped the round starts at the named time", function()
  local sky, fake = load()
  local p = {}
  for k, v in pairs(WINTER) do p[k] = v end
  p.daySeconds = 0
  sky.apply(p)
  assertEq(fake.setStates[1].time, 0.775)
end)

test("the named time is worked out against the round's date", function()
  local sky, fake = load()
  sky.apply(WINTER)
  assertEq(fake.solarState.month, 12); assertEq(fake.solarState.day, 14); assertEq(fake.solarState.year, 2026)
  assertEq(fake.solarState.latitude, 37.77)
end)

test("a sky without a year keeps the player's year for the sunrise lookup", function()
  local sky, fake = load()
  sky.apply({ time = "sunrise", weather = "snow", month = 12, day = 14, windDir = 0, windSeed = 1 })
  assertEq(fake.solarState.year, 2025); assertEq(fake.solarState.month, 12); assertEq(fake.solarState.day, 14)
  assertEq(fake.state.year, 2025); assertEq(fake.state.month, 12)
end)

test("a map south of the equator gets the same season six months on", function()
  local sky, fake = load()
  fake.state.latitude = -44.57
  sky.apply(WINTER)
  local s = fake.setStates[1]
  assertEq(s.year, 2026); assertEq(s.month, 6); assertEq(s.day, 14)
  assertEq(fake.solarState.month, 6); assertEq(fake.solarState.day, 14)
  assertEq(sky.label(withTemps(WINTER, -4, 0), true), "Sunrise · Snow · 14 Jun · -4 to 0 °C")
end)

test("the shifted date stays a real day", function()
  local sky, fake = load()
  fake.state.latitude = -44.57
  sky.apply({ time = "noon", weather = "clear", year = 2026, month = 12, day = 31, windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].month, 6); assertEq(fake.setStates[1].day, 30)
  assertEq(sky.label({ time = "noon", weather = "clear", month = 8, day = 31 }, true), "Noon · Clear · 28 Feb")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 31 }, true), "Noon · Clear · 31 Jul")
end)

test("restore gives the player's own date back", function()
  local sky, fake = load()
  sky.apply(WINTER)
  assertEq(fake.state.month, 12)
  sky.restore()
  assertEq(fake.state.year, 2025); assertEq(fake.state.month, 6); assertEq(fake.state.day, 20)
end)

test("a sky that sets nothing touches nothing", function()
  local sky, fake = load()
  sky.apply(nil); sky.apply({ windDir = 1, windSeed = 1 })
  assertEq(#fake.setStates, 0); assertEq(fake.locked, false)
end)

test("a round sky is applied and locked", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.time, 0.5); assertEq(s.play, false); assertEq(s.cloudCover, 2.2); assertEq(s.numOfDrops, nil)
  assertNear(s.groundWind.x, 5, 1e-6)
  assertEq(s.temperatureCurveOverrideC, false); assertEq(#fake.profiles, 0)
  sky.update(0.1)
  assertEq(fake.objects.cnr_precipitation:getField("dataBlock"), "rain_medium")
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.92)
  sky.update(4)
  assertEq(fake.locked, true)
end)

test("a thunderstorm has the same sky and rain as a gale", function()
  local sky, fake = load()
  assertEq(sky.isBadWeather("thunderstorm"), true)
  local gale = sky.WEATHER.storm
  local thunderstorm = sky.WEATHER.thunderstorm
  assertEq(thunderstorm ~= nil, true)
  for _, field in ipairs({ "cloudCover", "fogDensity", "windSpeed" }) do
    assertEq(thunderstorm[field], gale[field], field)
  end
  for field, value in pairs(gale.precipitation) do
    assertEq(thunderstorm.precipitation[field], value, field)
  end
  sky.apply({ weather = "thunderstorm" })
  sky.update(0.1)
  assertEq(fake.objects.cnr_precipitation:getField("dataBlock"), "rain_medium")
end)

test("a part on the map's own comes from the map's start values", function()
  local sky, fake = load()
  fake.state.time = 0.3
  sky.apply({ weather = "fog", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].time, 0.1); assertEq(fake.setStates[1].play, false)
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
  assertEq(#fake.profiles, 0)
end)

local TEMPS = {
  { t = -0.20833, hour = 6, c = 8 },
  { t = 0.125, hour = 14, c = 18 },
  { t = 0.79167, hour = 6, c = 9 },
  { t = 1.125, hour = 14, c = 20 },
}

local function changing(extra)
  local p = {
    time = "noon", weather = "cloudy", year = 2026, month = 12, day = 14, daySeconds = 1800, gameStart = 23 / 24,
    windDir = 90, windSeed = 7, changes = { { at = 20, to = "rain", forecastFrom = 0 } }, temps = TEMPS,
  }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

test("the temperature curve is the server's turning points around the start", function()
  local sky, fake = load()
  sky.apply(changing())
  local c = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  assertEq(#c, 2)
  assertNear(c[1][1], 2 / 24, 1e-12); assertEq(c[1][2], 18)
  assertEq(c[2][1], 0.75); assertEq(c[2][2], 8)
  assertEq(#fake.profiles, 0)
  sky, fake = load()
  fake.state.latitude = -44.57
  sky.apply(changing())
  c = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  assertNear(c[1][1], 2 / 24, 1e-12); assertEq(c[1][2], 18)
  assertEq(c[2][1], 0.75); assertEq(c[2][2], 8)
  sky, fake = load()
  sky.apply(changing({ clockSeconds = 300 }))
  c = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  assertNear(c[1][1], 2 / 24, 1e-12); assertEq(c[1][2], 18)
  assertEq(c[2][1], 0.75); assertEq(c[2][2], 9)
  sky, fake = load()
  sky.apply(changing({ temps = false }))
  assertEq(fake.setStates[#fake.setStates].temperatureCurveOverrideC, false)
  sky, fake = load()
  sky.apply(WINTER)
  assertEq(fake.setStates[#fake.setStates].temperatureCurveOverrideC, false)
end)

test("restore gives the player's own wind back", function()
  local sky, fake = load()
  fake.state.groundWind.x = 1
  sky.apply({ weather = "storm", driving = true, windDir = 0, windSeed = 7 })
  assertEq(fake.state.groundWind.y > 1, true)
  sky.restore()
  assertEq(fake.state.groundWind.x, 1); assertEq(fake.state.groundWind.y, 0)
end)

test("a round without a windy weather has no ground wind", function()
  local sky, fake = load()
  fake.state.groundWind.x = 3
  sky.apply({ time = "night", windDir = 0, windSeed = 1 })
  assertEq(fake.state.groundWind.x, 0)
end)

test("weathers without a temperature hand the map's curve back", function()
  local sky, fake = load()
  sky.apply({ time = "noon", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
end)

test("saves the player's sky only once", function()
  local sky, fake = load()
  fake.state.cloudCover = 0.05
  sky.apply(RAIN_NIGHT); sky.apply(RAIN_NIGHT)
  sky.apply({ time = "noon", weather = "snow", driving = true, windDir = 0, windSeed = 3 })
  sky.restore()
  assertEq(fake.state.cloudCover, 0.05); assertEq(fake.state.time, 0.1)
end)

test("a calm sky removes our precipitation object", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  sky.update(0.1)
  assertEq(fake.objects.cnr_precipitation ~= nil, true)
  sky.apply({ time = "night", weather = "clear", windDir = 0, windSeed = 1 })
  sky.update(3.1)
  assertEq(fake.objects.cnr_precipitation, nil)
end)

local function withLog(fn)
  local old, lines = _G.log, {}
  _G.log = function(level, tag, msg) lines[#lines + 1] = level .. " " .. tag .. " " .. tostring(msg) end
  local ok, err = pcall(fn, lines)
  _G.log = old
  if not ok then error(err, 0) end
end

test("a throw from the rain engine calls is contained and leaves no rain", function()
  local sky, fake = load()
  withLog(function(lines)
    local make = _G.createObject
    _G.createObject = function() error("engine boom") end
    sky.apply(RAIN_NIGHT)
    local ok = pcall(sky.update, 0.5)
    _G.createObject = make
    assertEq(ok, true)
    assertEq(fake.objects.cnr_precipitation, nil)
    assertEq(fake.objects.cnr_rain_sound, nil)
    assertEq(#lines >= 1, true)
    assertEq(pcall(sky.update, 0.1), true)
    assertEq(fake.objects.cnr_precipitation, nil)
  end)
end)

test("a failed registration logs once over two seconds of updates", function()
  local sky, fake = load()
  withLog(function(lines)
    local make = _G.createObject
    _G.createObject = function(kind)
      local obj = make(kind)
      if kind == "Precipitation" then function obj:registerObject() end end
      return obj
    end
    sky.apply(RAIN_NIGHT)
    for _ = 1, 20 do sky.update(0.1) end
    _G.createObject = make
    assertEq(#lines, 1)
    assertEq(fake.objects.cnr_precipitation, nil)
  end)
end)

test("restore puts the earlier lock back", function()
  local sky, fake = load({ locked = true })
  sky.apply(RAIN_NIGHT)
  assertEq(#fake.setStates > 0, true)
  sky.update(4)
  sky.restore(); sky.update(4)
  assertEq(fake.locked, true)
  local sky2, fake2 = load()
  sky2.apply(RAIN_NIGHT); sky2.update(4); sky2.restore(); sky2.update(4)
  assertEq(fake2.locked, false)
end)

test("restore stops the wind updates and removes everything", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
  for _ = 1, 4 do sky.update(0.25) end
  local before = #fake.queued
  assertEq(before >= 3, true)
  sky.restore(); sky.update(4)
  assertEq(#fake.queued, before)
  assertEq(fake.objects.cnr_precipitation, nil)
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
end)

test("wind updates don't touch the lock", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
  sky.update(4)
  local states = #fake.setStates
  sky.update(2)
  assertEq(#fake.setStates, states); assertEq(fake.locked, true)
  assertEq(fake.queued[1]:find("obj:setWind(", 1, true) ~= nil, true)
end)

test("driving off leaves surfaces and wind alone", function()
  local sky, fake = load()
  sky.apply({ weather = "storm", windDir = 0, windSeed = 1 }); sky.startClock(0); sky.update(1)
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
  assertEq(#fake.queued, 0)
end)

test("the clock starts at GO with the round's day length", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", daySeconds = 1440, windDir = 0, windSeed = 1 })
  sky.startClock(600)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
  assertNear(s.time, (0.245 - 1 / 24 + 600 / 1440) % 1, 1e-9)
end)

test("drop forgets without applying", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  local n = #fake.setStates
  sky.drop(); sky.restore()
  assertEq(#fake.setStates, n); assertEq(fake.locked, false)
end)

test("isNight follows the game's light state", function()
  local sky, fake = load()
  assertEq(sky.isNight(), false)
  sky.apply(RAIN_NIGHT)
  assertEq(sky.isNight(), true)
end)

test("a failing apply still relocks and restore still works", function()
  local sky, fake = load()
  fake.state.cloudCover = 0.05
  local make = core_environment.setState
  core_environment.setState = function(s, seconds)
    if s and s.cloudCover == 2.2 and s.time and not fake.threw then
      fake.threw = true
      error("boom")
    end
    return make(s, seconds)
  end
  sky.apply(RAIN_NIGHT)
  core_environment.setState = make
  assertEq(fake.objects.cnr_precipitation, nil)
  assertEq(fake.locked, true)
  assertEq(fake.lerps[#fake.setStates], nil); assertEq(fake.state.cloudCover, 2.2)
  sky.restore(); sky.update(4)
  assertEq(fake.locked, false); assertEq(fake.state.cloudCover, 0.05)
end)

test("precipitation is not saved with the level", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.update(0.1)
  assertEq(fake.objects.cnr_precipitation.canSave, false)
end)

test("the map's own rain is put back to its start value during a round", function()
  local sky, fake = load()
  fake.init.numOfDrops = 0; fake.state.numOfDrops = 500
  sky.apply({ time = "noon", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[#fake.setStates].numOfDrops, 0)
  sky.restore()
  assertEq(fake.state.numOfDrops, 500)
end)

local function withRoof(height, fn)
  local oldCast, oldCamera = _G.castRayStatic, _G.core_camera
  local roof = { height = height }
  _G.core_camera = { getPosition = function() return vec3(0, 0, 0) end }
  _G.castRayStatic = function(pos, dir, len)
    if roof.height and roof.height < len then return roof.height end
    return len + 1
  end
  local ok, err = pcall(fn, roof)
  _G.castRayStatic, _G.core_camera = oldCast, oldCamera
  if not ok then error(err, 0) end
end

local function hidden(fake)
  return fake.objects.cnr_precipitation:getField("hidden") == "1"
end

test("rain stops under a close roof and comes back in the open", function()
  withRoof(3, function(roof)
    local sky, fake = load()
    sky.apply(RAIN_NIGHT)
    sky.update(0.25); sky.update(0.25); sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), true)
    roof.height = nil
    sky.update(0.25); sky.update(0.25); sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), false)
  end)
end)

test("rain keeps falling under a high bridge", function()
  withRoof(20, function()
    local sky, fake = load()
    sky.apply(RAIN_NIGHT)
    for _ = 1, 16 do
      sky.update(0.25)
      assertEq(hidden(fake), false)
    end
  end)
end)

test("a new sky in prep keeps the rain hidden under a roof", function()
  withRoof(3, function()
    local sky, fake = load()
    sky.apply(RAIN_NIGHT)
    sky.update(0.25); sky.update(0.25); sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), true)
    sky.apply(RAIN_NIGHT)
    assertEq(hidden(fake), true)
  end)
end)

test("a new round's sky starts its rain without the last round's roof", function()
  withRoof(3, function(roof)
    local sky, fake = load()
    sky.apply(RAIN_NIGHT)
    sky.update(0.25); sky.update(0.25); sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), true)
    sky.restore()
    roof.height = nil
    sky.apply(RAIN_NIGHT)
    assertEq(hidden(fake), false)
  end)
end)

test("the roof check runs before GO and without driving effects", function()
  withRoof(3, function()
    local sky, fake = load()
    sky.apply({ weather = "snow", windDir = 0, windSeed = 1 })
    sky.update(0.25); sky.update(0.25); sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), true)
  end)
end)

test("a round sky blends in over 3 s and locks after the blend", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  assertEq(fake.lerps[#fake.setStates], 3)
  assertEq(fake.locked, false)
  sky.update(3.4); assertEq(fake.locked, false)
  sky.update(0.2); assertEq(fake.locked, true)
end)

test("a second sky during a blend restarts the lock timer", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.update(3)
  sky.apply(RAIN_NIGHT); sky.update(1)
  assertEq(fake.locked, false)
  sky.update(2.6); assertEq(fake.locked, true)
end)

test("GO during a blend lands the full sky and locks", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", weather = "rain", daySeconds = 1440, month = 4, day = 2, windDir = 0, windSeed = 1 })
  local n = #fake.setStates
  sky.startClock(0)
  local landed
  for i = n + 1, #fake.setStates do
    local s = fake.setStates[i]
    if s.cloudCover == 2.2 and fake.lerps[i] == nil and landed == nil then landed = i end
    if s.play == true then assertEq(landed ~= nil and landed < i, true) end
  end
  assertEq(landed ~= nil, true)
  assertEq(fake.setStates[#fake.setStates].play, true)
  assertEq(fake.locked, true)
end)

test("GO during a blend with Day length Off lands the sky, locks and never starts the clock", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", weather = "rain", daySeconds = 0, month = 4, day = 2, windDir = 0, windSeed = 1 })
  local n = #fake.setStates
  assertEq(fake.locked, false)
  sky.startClock(0)
  assertEq(#fake.setStates, n + 1)
  local s = fake.setStates[n + 1]
  assertEq(fake.lerps[n + 1], nil)
  assertEq(s.cloudCover, 2.2); assertEq(s.time, 0.245); assertEq(s.play, false)
  for i = 1, #fake.setStates do assertEq(fake.setStates[i].play ~= true, true) end
  assertEq(fake.locked, true)
  sky.update(5)
  assertEq(#fake.setStates, n + 1); assertEq(fake.locked, true)
end)

test("GO after the blend only starts the clock", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", weather = "rain", daySeconds = 1440, month = 4, day = 2, windDir = 0, windSeed = 1 })
  sky.update(4)
  local n = #fake.setStates
  sky.startClock(0)
  assertEq(#fake.setStates, n + 1)
  local s = fake.setStates[n + 1]
  assertEq(s.play, true); assertEq(s.cloudCover, nil)
  assertEq(fake.locked, true)
end)

test("restore blends back over 3 s and then puts the earlier lock back", function()
  local sky, fake = load({ locked = true })
  sky.apply(RAIN_NIGHT); sky.update(4)
  sky.restore()
  assertEq(fake.lerps[#fake.setStates], 3)
  assertEq(fake.locked, false)
  sky.update(4)
  assertEq(fake.locked, true)
  local sky2, fake2 = load()
  sky2.apply(RAIN_NIGHT); sky2.update(4); sky2.restore()
  assertEq(fake2.locked, false)
  sky2.update(4)
  assertEq(fake2.locked, false)
end)

test("every blend clears a running one first", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  sky.apply(RAIN_NIGHT)
  sky.restore()
  assertEq(fake.resets, 3)
  for i = 1, 3 do
    assertEq(fake.resetAt[i], i - 1)
    assertEq(fake.lerps[i], 3)
  end
end)

test("an immediate restore lands at once and locks back", function()
  local sky, fake = load({ locked = true })
  sky.apply(RAIN_NIGHT); sky.update(1)
  sky.restore(true)
  assertEq(fake.lerps[#fake.setStates], nil)
  assertEq(fake.locked, true)
  assertEq(fake.objects.cnr_precipitation, nil)
  local n = #fake.setStates
  sky.update(5)
  assertEq(#fake.setStates, n); assertEq(fake.locked, true)
  local sky2, fake2 = load()
  sky2.apply(RAIN_NIGHT); sky2.update(1); sky2.restore(true)
  assertEq(fake2.locked, false)
  sky2.update(5)
  assertEq(fake2.locked, false)
end)

test("a round starting during the restore blend saves the player's own sky", function()
  local sky, fake = load()
  fake.state.cloudCover = 0.05
  sky.apply(RAIN_NIGHT); sky.update(4); sky.restore()
  fake.state.cloudCover = 1.1
  sky.apply(RAIN_NIGHT); sky.update(4); sky.restore(); sky.update(4)
  assertEq(fake.state.cloudCover, 0.05)
end)

test("a round starting during the restore blend saves the player's own sky and lock", function()
  local sky, fake = load({ locked = true })
  fake.state.cloudCover = 0.05
  sky.apply(RAIN_NIGHT); sky.update(4); sky.restore()
  assertEq(fake.locked, false)
  fake.state.cloudCover = 1.1
  sky.apply(RAIN_NIGHT); sky.update(4)
  assertEq(fake.locked, true)
  sky.restore()
  assertEq(fake.locked, false)
  sky.update(4)
  assertEq(fake.state.cloudCover, 0.05)
  assertEq(fake.locked, true)
end)

test("drop cancels a pending lock timer", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
  sky.drop()
  assertEq(fake.locked, false)
  sky.update(5)
  assertEq(fake.locked, false)
end)

test("an immediate restore during the round-end blend lands the sky and lock", function()
  local sky, fake = load({ locked = true })
  fake.state.cloudCover = 0.05
  sky.apply(RAIN_NIGHT); sky.update(4); sky.restore()
  fake.state.cloudCover = 1.1
  sky.restore(true)
  assertEq(fake.lerps[#fake.setStates], nil)
  assertEq(fake.state.cloudCover, 0.05)
  assertEq(fake.locked, true)
  local n = #fake.setStates
  sky.update(5)
  assertEq(#fake.setStates, n); assertEq(fake.locked, true)
end)

test("drop removes rain and sound at once and cancels the lock timer", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.update(1)
  assertEq(fake.objects.cnr_rain_sound ~= nil, true)
  sky.drop()
  assertEq(fake.objects.cnr_precipitation, nil); assertEq(fake.objects.cnr_rain_sound, nil)
  local n, locked = #fake.setStates, fake.locked
  sky.update(5)
  assertEq(#fake.setStates, n); assertEq(fake.locked, locked)
end)

test("round end fades the rain out", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.update(4)
  sky.restore()
  assertEq(fake.objects.cnr_precipitation ~= nil, true)
  sky.update(3.2)
  assertEq(fake.objects.cnr_precipitation, nil); assertEq(fake.objects.cnr_rain_sound, nil)
end)

local function drops(fake)
  local obj = fake.objects.cnr_precipitation
  return obj and tonumber(obj:getField("numDrops")) or 0
end

local function curveAt(curve, time)
  local t = time % 1
  for i = 2, #curve do
    local a, b = curve[i - 1], curve[i]
    if t >= a[1] and t <= b[1] then return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1]) end
  end
  local first, last = curve[1], curve[#curve]
  if t < first[1] then t = t + 1 end
  return last[2] + (first[2] - last[2]) * (t - last[1]) / (1 + first[1] - last[1])
end

local function started(extra)
  local sky, fake = load()
  local p = changing(extra)
  sky.apply(p)
  sky.startClock(p.clockSeconds or 0)
  return sky, fake, p.clockSeconds or 0
end

local function runFor(sky, t, seconds, dt, each)
  for _ = 1, math.floor(seconds / dt + 0.5) do
    local change = sky.update(dt)
    t = t + dt
    if each then each(t, change) end
  end
  return t
end

test("clouds and fog step twice a second, locked between steps", function()
  local sky, fake = started()
  local count, steps, last = #fake.setStates, 0, nil
  runFor(sky, 0, 90, 0.1, function(t)
    assertEq(fake.locked, true, "locked at " .. t)
    for i = count + 1, #fake.setStates do
      local s = fake.setStates[i]
      assertEq(fake.lerps[i], nil)
      local keys = 0
      for k in pairs(s) do
        keys = keys + 1
        assertEq(k == "cloudCover" or k == "fogDensity" or k == "windSpeed", true, k)
      end
      assertEq(keys, 3)
      if last then assertEq(t - last >= 0.5 - 1e-6, true, string.format("%.2f after %.2f", t, last)) end
      last = t
      assertEq(t >= 20 and t <= 80.6, true, tostring(t))
      steps = steps + 1
    end
    count = #fake.setStates
  end)
  assertEq(steps >= 110, true, tostring(steps))
end)

test("the steps follow a smoothstep", function()
  local sky, fake = started()
  local t = runFor(sky, 0, 35, 0.1)
  assertNear(fake.state.cloudCover, 1.8625, 0.03)
  runFor(sky, t, 15, 0.1)
  assertNear(fake.state.cloudCover, 2.0, 0.02); assertNear(fake.state.fogDensity, 2.5, 0.1); assertNear(fake.state.windSpeed, 0.4, 0.01)
  runFor(sky, 50, 31, 0.1)
  assertEq(fake.state.cloudCover, 2.2); assertEq(fake.state.fogDensity, 4); assertEq(fake.state.windSpeed, 0.5)
end)

test("a step never touches time, play, the day length, the date or the temperature", function()
  local sky, fake = started()
  local count = #fake.setStates
  local before = {}
  for k, v in pairs(fake.state) do before[k] = v end
  runFor(sky, 0, 90, 0.1)
  assertEq(#fake.setStates > count, true)
  for i = count + 1, #fake.setStates do
    local s = fake.setStates[i]
    for _, k in ipairs({ "time", "play", "dayLength", "year", "month", "day", "temperatureCurveOverrideC", "groundWind" }) do
      assertEq(s[k], nil, k)
    end
  end
  for _, k in ipairs({ "time", "play", "dayLength", "year", "month", "day", "temperatureCurveOverrideC" }) do
    assertEq(fake.state[k], before[k], k)
  end
  assertEq(#fake.profiles, 0)
end)

test("rain fades in over the change", function()
  local sky, fake = started()
  local t = runFor(sky, 0, 19.9, 0.1)
  assertEq(fake.objects.cnr_precipitation, nil)
  t = runFor(sky, t, 30.1, 0.1)
  assertNear(drops(fake), 1500, 150)
  runFor(sky, t, 31, 0.1)
  assertEq(drops(fake), 3000)
end)

test("the curve write lands when the client's own clock reaches the turning point", function()
  local sky, fake = load()
  core_environment.getSolarTimeOfDayValue = function() return 0.01 end
  sky.apply(changing())
  sky.startClock(0)
  local clockStart = fake.setStates[#fake.setStates].time
  assertNear(clockStart, 0.01 - 1 / 24 + 1, 1e-9)
  local count, at = #fake.setStates, nil
  runFor(sky, 0, 400, 0.25, function(t)
    for i = count + 1, #fake.setStates do
      if fake.setStates[i].temperatureCurveOverrideC ~= nil and not at then at = t end
    end
    count = #fake.setStates
  end)
  local expected = (2 / 24 - (clockStart - 1)) * 1800
  assertEq(at ~= nil, true)
  assertEq(at >= expected and at <= expected + 0.5, true, tostring(at))
end)

test("the curve moves on only at a turning point, and the two curves agree there", function()
  local sky, fake = load()
  sky.apply(changing())
  local curve = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  sky.startClock(0)
  local clockStart = fake.setStates[#fake.setStates].time
  local count, writes = #fake.setStates, {}
  runFor(sky, 0, 1500, 0.25, function(t)
    for i = count + 1, #fake.setStates do
      local s = fake.setStates[i]
      if s.temperatureCurveOverrideC ~= nil then
        assertEq(s.cloudCover, nil); assertEq(s.time, nil); assertEq(fake.lerps[i], nil)
        writes[#writes + 1] = { t = t, curve = s.temperatureCurveOverrideC }
      end
    end
    count = #fake.setStates
    assertEq(fake.locked, true)
  end)
  assertEq(#writes, 2)
  assertEq(writes[1].t >= 225 and writes[1].t <= 225.5, true, tostring(writes[1].t))
  assertEq(writes[2].t >= 1425 and writes[2].t <= 1425.5, true, tostring(writes[2].t))
  local turns = { 2 / 24, 0.75 }
  for i, w in ipairs(writes) do
    local at = (clockStart + w.t / 1800) % 1
    assertNear(at, turns[i], 0.5 / 1800 + 1e-9)
    assertNear(curveAt(curve, turns[i]), curveAt(w.curve, turns[i]), 1e-9)
    assertNear(curveAt(curve, at), curveAt(w.curve, at), 0.01)
    curve = w.curve
  end
  assertEq(writes[1].curve[2][2], 9); assertEq(writes[2].curve[1][2], 20)
end)

test("the wind cross-fades", function()
  local sky, fake = started({ weather = "rain", driving = true, changes = { { at = 20, to = "cloudy", forecastFrom = 0 } } })
  local wind = require("copsAndRobbers/wind")
  local t = runFor(sky, 0, 50, 0.25)
  local g = fake.groundWinds[#fake.groundWinds]
  local x, y = wind.at("rain", 7, 90, 50)
  assertNear(g.x, x / 2, 1e-6); assertNear(g.y, y / 2, 1e-6)
  assertEq(math.abs(x) > 1, true)
  t = runFor(sky, t, 29.75, 0.25)
  local n = #fake.groundWinds
  local q = #fake.queued
  g = fake.groundWinds[n]
  assertEq(g.x ~= 0 or g.y ~= 0, true)
  runFor(sky, t, 10, 0.25)
  assertEq(#fake.groundWinds, n + 1)
  g = fake.groundWinds[n + 1]
  assertEq(g.x, 0); assertEq(g.y, 0); assertEq(g.z, 0)
  assertEq(#fake.queued, q + 1)
  assertEq(fake.queued[q + 1], "obj:setWind(0.000000,0.000000,0.000000)")
end)

test("the wind picks up over a change into a windy weather", function()
  local sky, fake = started({ driving = true })
  local wind = require("copsAndRobbers/wind")
  local t = runFor(sky, 0, 19.75, 0.25)
  assertEq(#fake.groundWinds, 0)
  runFor(sky, t, 30.25, 0.25)
  local g = fake.groundWinds[#fake.groundWinds]
  local x = wind.at("rain", 7, 90, 50)
  assertNear(g.x, x / 2, 1e-6)
end)

test("a joiner mid-change gets the in-between sky", function()
  local sky, fake = load()
  sky.apply(changing({ clockSeconds = 50 }))
  local s = fake.setStates[#fake.setStates]
  assertNear(s.cloudCover, 2.0, 1e-9); assertNear(s.fogDensity, 2.5, 1e-9); assertNear(s.windSpeed, 0.4, 1e-9)
  assertEq(s.temperatureCurveOverrideC[2][2], 8)
  assertEq(sky.weather(), "rain")
  sky.startClock(50)
  assertEq(fake.locked, true)
  assertEq(fake.state.cloudCover, s.cloudCover)
  local t = runFor(sky, 50, 15, 0.1, function(_, change) assertEq(change, nil) end)
  assertNear(drops(fake), 1500, 150)
  assertNear(fake.state.cloudCover, 1.8 + 0.4 * 0.84375, 0.03)
  runFor(sky, t, 15.1, 0.1)
  assertEq(drops(fake), 3000)
  assertEq(fake.state.cloudCover, 2.2)

  sky, fake = load()
  sky.apply(changing({ clockSeconds = 50, weather = "rain", changes = { { at = 20, to = "storm", forecastFrom = 0 } } }))
  assertEq(drops(fake), 3000)
  assertEq(fake.objects.cnr_precipitation:getField("dropSize"), "1")
  sky.startClock(50)
  runFor(sky, 50, 15, 0.1)
  assertNear(drops(fake), 5000, 200)

  sky, fake = load()
  sky.apply(changing({ clockSeconds = 100 }))
  s = fake.setStates[#fake.setStates]
  assertEq(s.cloudCover, 2.2); assertEq(fake.lerps[#fake.setStates], 3)
  assertEq(fake.objects.cnr_precipitation, nil)
  sky.startClock(100)
  runFor(sky, 100, 3.1, 0.1)
  assertEq(drops(fake), 3000)
end)

test("update reports a change once, with its notice", function()
  local sky = started({ changes = { { at = 20, to = "rain", forecastFrom = 0 }, { at = 70, to = "storm", forecastFrom = 0 } } })
  local seen = {}
  runFor(sky, 0, 150, 0.1, function(t, change)
    if change then seen[#seen + 1] = { t = t, change = change } end
  end)
  assertEq(#seen, 2)
  assertEq(seen[1].t >= 20 - 1e-6 and seen[1].t < 20.15, true, tostring(seen[1].t))
  assertEq(seen[1].change.from, "cloudy"); assertEq(seen[1].change.to, "rain")
  assertEq(seen[1].change.notice, "Weather: rain coming")
  assertEq(seen[2].change.from, "rain"); assertEq(seen[2].change.to, "storm")
  assertEq(seen[2].change.notice, "Weather: the rain is getting heavier")
end)

test("weather() follows the schedule", function()
  local sky = load()
  assertEq(sky.weather(), nil)
  sky.apply(changing())
  assertEq(sky.weather(), "cloudy")
  sky.startClock(0)
  local t = runFor(sky, 0, 19.9, 0.1)
  assertEq(sky.weather(), "cloudy")
  runFor(sky, t, 5, 0.1)
  assertEq(sky.weather(), "rain")
  sky.restore()
  assertEq(sky.weather(), nil)
end)

test("no step while the round sky blends in", function()
  local sky, fake = started()
  local t = runFor(sky, 0, 30, 0.1)
  sky.apply(changing())
  local n = #fake.setStates
  assertEq(fake.lerps[n], 3)
  t = runFor(sky, t, 3.4, 0.1)
  assertEq(#fake.setStates, n)
  runFor(sky, t, 1, 0.1)
  assertEq(#fake.setStates > n, true)
  assertEq(fake.lerps[#fake.setStates], nil)
  assertEq(fake.locked, true)
  t = runFor(sky, t + 1, 30, 0.1)
  assertEq(drops(fake) < 3000, true)
  runFor(sky, t, 17, 0.1)
  assertEq(drops(fake), 3000)
end)

test("a failing step logs once and stays locked", function()
  local sky, fake = started()
  withLog(function(lines)
    local setState = core_environment.setState
    core_environment.setState = function(s, seconds)
      if s and s.cloudCover then error("step boom") end
      return setState(s, seconds)
    end
    for _ = 1, 900 do
      assertEq(pcall(sky.update, 0.1), true)
      assertEq(fake.locked, true)
    end
    core_environment.setState = setState
    assertEq(#lines, 1)
    assertEq(lines[1]:find("E cnr_sky", 1, true), 1)
    assertNear(drops(fake), 3000, 1)
  end)
end)

test("a failing curve write logs once, stays locked and the clouds go on", function()
  local sky, fake = started()
  withLog(function(lines)
    local setState = core_environment.setState
    local tries = 0
    core_environment.setState = function(s, seconds)
      if s and s.temperatureCurveOverrideC ~= nil then
        tries = tries + 1
        error("curve boom")
      end
      return setState(s, seconds)
    end
    runFor(sky, 0, 1500, 0.25, function() assertEq(fake.locked, true) end)
    core_environment.setState = setState
    assertEq(tries, 1)
    assertEq(#lines, 1)
    assertEq(fake.state.cloudCover, 2.2)
  end)
end)

test("restore forgets the step state", function()
  local sky, fake = started()
  withLog(function(lines)
    local setState = core_environment.setState
    core_environment.setState = function(s, seconds)
      if s and s.cloudCover and seconds == nil and s.time == nil then error("step boom") end
      return setState(s, seconds)
    end
    runFor(sky, 0, 25, 0.1)
    core_environment.setState = setState
    assertEq(#lines, 1)
  end)
  sky.restore(); sky.update(4)
  sky.apply(changing()); sky.startClock(0)
  local n = #fake.setStates
  runFor(sky, 0, 25, 0.1)
  assertEq(#fake.setStates > n, true)
end)

test("the label's range comes from the turning points around the start", function()
  local sky = load()
  assertEq(sky.label(changing(), true), "Noon · Cloudy · 14 Dec · 8 to 18 °C")
  local p = changing({ temps = { { t = -0.2, hour = 14, c = 7.6 }, { t = 0.1, hour = 6, c = -2.4 }, { t = 0.5, hour = 14, c = 30 } } })
  assertEq(sky.label(p, true), "Noon · Cloudy · 14 Dec · -2 to 8 °C")
  assertEq(sky.label(changing({ temps = false }), true), "Noon · Cloudy · 14 Dec")
end)

local function asphalt(fake) return fake.models.ASPHALT.cdata.staticFrictionCoefficient end

local function gripRound(extra)
  local p = changing({ driving = true, weather = "cloudy", changes = { { at = 20, to = "rain", forecastFrom = 0 }, { at = 200, to = "cloudy", forecastFrom = 0 } } })
  for k, v in pairs(extra or {}) do p[k] = v end
  local sky, fake = load()
  sky.apply(p); sky.startClock(0); sky.update(4)
  return sky, fake, p
end

test("grip gets wet over the change and dries over 180 s after it", function()
  local sky, fake = gripRound()
  local t = 4
  t = runFor(sky, t, 50 - t, 0.5)
  assertNear(asphalt(fake), (0.98 + 0.92) / 2, 0.06 * 0.06 + 0.001)
  t = runFor(sky, t, 80 - t, 0.5)
  assertNear(asphalt(fake), 0.92, 1e-6)
  t = runFor(sky, t, 200 - t, 0.5)
  assertNear(asphalt(fake), 0.92, 1e-6)
  t = runFor(sky, t, 350 - t, 0.5)
  assertNear(asphalt(fake), (0.98 + 0.92) / 2, 0.003)
  t = runFor(sky, t, 440 - t, 0.5)
  assertNear(asphalt(fake), 0.98, 1e-6)
end)

test("between wet kinds the blend runs over the change", function()
  local sky, fake = gripRound({
    weather = "rain", changes = { { at = 20, to = "snow", forecastFrom = 0 } },
  })
  local t = runFor(sky, 4, 46, 0.5)
  assertNear(asphalt(fake), (0.92 + 0.65) / 2, 0.03)
  t = runFor(sky, t, 40, 0.5)
  assertNear(asphalt(fake), 0.65, 1e-6)
end)

test("driving off never changes grip", function()
  local sky, fake = gripRound({ driving = false })
  runFor(sky, 4, 120, 0.5)
  assertEq(#fake.modelSets, 0)
  assertEq(asphalt(fake), 0.98)
end)

test("a joiner gets the grip in effect", function()
  local sky, fake = load()
  local p = changing({ driving = true, weather = "cloudy", clockSeconds = 50, changes = { { at = 20, to = "rain", forecastFrom = 0 } } })
  sky.apply(p)
  assertNear(asphalt(fake), (0.98 + 0.92) / 2, 0.003)
  local sky2, fake2 = load()
  p.clockSeconds = 100
  sky2.apply(p)
  assertNear(asphalt(fake2), 0.92, 1e-6)
end)

test("a failing grip push logs once and stops grip for the round", function()
  local sky, fake = gripRound()
  withLog(function(lines)
    local make = _G.be.setGroundModel
    _G.be.setGroundModel = function() error("push boom") end
    runFor(sky, 4, 100, 0.5, function() assertEq(fake.locked, true) end)
    _G.be.setGroundModel = make
    assertEq(#lines, 1)
    assertEq(fake.state.cloudCover, 2.2)
    local n = #fake.modelSets
    runFor(sky, 104, 400, 0.5)
    assertEq(#fake.modelSets, n)
  end)
end)

test("a grip push failure at apply keeps the rain, the clouds and the lock", function()
  local sky, fake = load()
  withLog(function(lines)
    local make = _G.be.setGroundModel
    _G.be.setGroundModel = function() error("push boom") end
    sky.apply(RAIN_NIGHT)
    _G.be.setGroundModel = make
    assertEq(#lines, 1)
    assertEq(lines[1]:find("grip", 1, true) ~= nil, true)
    sky.update(0.1)
    assertEq(fake.objects.cnr_precipitation ~= nil, true)
    assertEq(fake.state.cloudCover, 2.2)
    assertEq(fake.locked, false)
    sky.update(4)
    assertEq(fake.locked, true)
    assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
  end)
end)

test("a ground model push that still fails at restore never blocks the sky restore", function()
  local sky, fake = load()
  withLog(function(lines)
    sky.apply(RAIN_NIGHT); sky.startClock(0); sky.update(4)
    local make = _G.be.setGroundModel
    _G.be.setGroundModel = function() error("push boom") end
    assertEq(pcall(sky.restore), true)
    sky.update(4)
    _G.be.setGroundModel = make
    assertEq(fake.locked, false)
    assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
    assertEq(#lines, 1)
  end)
end)

test("the forecast runs on the round clock from the countdown, and none before it or after the round", function()
  local sky = load()
  local p = changing({ weather = "rain", changes = { { at = 500, to = "storm", forecastFrom = 430 } } })
  sky.apply(p)
  assertEq(sky.forecast(true), nil)
  sky.startClock(100)
  local f = sky.forecast(true)
  assertEq(f.text, "Forecast: a storm in 5-8 min"); assertEq(f.heli, "(helicopter grounded)")
  assertEq(sky.forecast(false).heli, nil)
  sky.restore(true)
  assertEq(sky.forecast(true), nil)
end)

test("the prep label adds the first change's forecast to the sky label", function()
  local sky = load()
  local p = { time = "noon", weather = "clear", releaseAt = 10, changes = { { at = 400, to = "cloudy", forecastFrom = 330 } } }
  assertEq(sky.prepLabel(p), "Noon · Clear · Forecast: clouds 5-8 min after release")
  p.changes = {}
  assertEq(sky.prepLabel(p), "Noon · Clear")
  assertEq(sky.prepLabel(nil), nil)
end)
