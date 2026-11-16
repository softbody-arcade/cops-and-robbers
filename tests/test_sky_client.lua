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
  assertEq(sky.label({ daySeconds = 1800 }), nil)
end)

local WINTER = { time = "sunrise", weather = "snow", year = 2026, month = 12, day = 14, windDir = 0, windSeed = 1 }

test("labels end with the date only when asked", function()
  local sky = load()
  assertEq(sky.label(WINTER, true), "Sunrise · Snow · 14 Dec · -4 to 0 °C")
  assertEq(sky.label(WINTER), "Sunrise · Snow")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 3 }, true), "Noon · Clear · 3 Jan · 0 to 8 °C")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 13, day = 3 }, true), "Noon · Clear")
end)

test("the label shows the range in Fahrenheit when the game does", function()
  local sky = load()
  local saved = _G.settings
  _G.settings = { getValue = function(k) return k == "uiUnitTemperature" and "f" or nil end }
  local label = sky.label(WINTER, true)
  _G.settings = saved
  assertEq(label, "Sunrise · Snow · 14 Dec · 25 to 32 °F")
end)

test("a label without a month or with an unknown weather has no temperature", function()
  local sky = load()
  assertEq(sky.label({ time = "noon", weather = "clear", day = 3 }, true), "Noon · Clear")
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
  assertEq(sky.label(WINTER, true), "Sunrise · Snow · 14 Jun · -4 to 0 °C")
end)

test("the shifted date stays a real day", function()
  local sky, fake = load()
  fake.state.latitude = -44.57
  sky.apply({ time = "noon", weather = "clear", year = 2026, month = 12, day = 31, windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].month, 6); assertEq(fake.setStates[1].day, 30)
  assertEq(sky.label({ time = "noon", weather = "clear", month = 8, day = 31 }, true), "Noon · Clear · 28 Feb · 19 to 30 °C")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 31 }, true), "Noon · Clear · 31 Jul · 0 to 8 °C")
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

test("a part on the map's own comes from the map's start values", function()
  local sky, fake = load()
  fake.state.time = 0.3
  sky.apply({ weather = "fog", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].time, 0.1); assertEq(fake.setStates[1].play, false)
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
  assertEq(#fake.profiles, 0)
end)

test("the temperature follows the weather and the server's month", function()
  local sky, fake = load()
  sky.apply(WINTER)
  local c = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  assertEq(#c, 2)
  assertNear(c[1][1], 2 / 24, 1e-9); assertEq(c[1][2], 0)
  assertNear(c[2][1], 0.775, 1e-9); assertEq(c[2][2], -4)
  assertEq(#fake.profiles, 0)
  sky, fake = load()
  fake.state.latitude = -44.57
  sky.apply(WINTER)
  c = fake.setStates[#fake.setStates].temperatureCurveOverrideC
  assertEq(#c, 2)
  assertNear(c[1][1], 2 / 24, 1e-9); assertEq(c[1][2], 0)
  assertNear(c[2][1], 0.775, 1e-9); assertEq(c[2][2], -4)
  assertEq(#fake.profiles, 0)
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
  sky.apply({ time = "night", weather = "clear", windDir = 0, windSeed = 1 })
  assertEq(fake.objects.cnr_precipitation, nil)
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
  assertNear(s.time, (0.245 + 600 / 1440) % 1, 1e-9)
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
  local make = _G.be.setGroundModel
  _G.be.setGroundModel = function() error("boom") end
  sky.apply(RAIN_NIGHT)
  _G.be.setGroundModel = make
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
    sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), true)
    roof.height = nil
    sky.update(0.25); sky.update(0.25)
    assertEq(hidden(fake), false)
  end)
end)

test("rain keeps falling under a high bridge", function()
  withRoof(20, function()
    local sky, fake = load()
    sky.apply(RAIN_NIGHT)
    for _ = 1, 4 do sky.update(0.25) end
    assertEq(hidden(fake), false)
  end)
end)

test("the roof check runs before GO and without driving effects", function()
  withRoof(3, function()
    local sky, fake = load()
    sky.apply({ weather = "snow", windDir = 0, windSeed = 1 })
    sky.update(0.25); sky.update(0.25)
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
