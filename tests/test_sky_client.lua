dofile("tests/env_stubs.lua")
local function load(opts)
  local fake = fakeEnvironment(opts)
  for _, n in ipairs({ "copsAndRobbers/sky", "copsAndRobbers/surfaces", "copsAndRobbers/wind", "copsAndRobbers/shelter" }) do package.loaded[n] = nil end
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
  assertEq(sky.label(WINTER, true), "Sunrise · Snow · 14 Dec")
  assertEq(sky.label(WINTER), "Sunrise · Snow")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 1, day = 3 }, true), "Noon · Clear · 3 Jan")
  assertEq(sky.label({ time = "noon", weather = "clear", month = 13, day = 3 }, true), "Noon · Clear")
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
  assertEq(fake.profiles[1].averageC, 8)
  assertEq(fake.objects.cnr_precipitation:getField("dataBlock"), "rain_medium")
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.92)
  assertEq(fake.locked, true)
end)

test("a part on the map's own comes from the map's start values", function()
  local sky, fake = load()
  fake.state.time = 0.3
  sky.apply({ weather = "fog", windDir = 0, windSeed = 1 })
  assertEq(fake.setStates[1].time, 0.1); assertEq(fake.setStates[1].play, false)
  assertEq(fake.setStates[1].temperatureCurveOverrideC, false)
  assertEq(fake.profiles[1].averageC, 5)
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
  sky.restore()
  assertEq(fake.locked, true)
  local sky2, fake2 = load()
  sky2.apply(RAIN_NIGHT); sky2.restore()
  assertEq(fake2.locked, false)
end)

test("restore stops the wind updates and removes everything", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
  for _ = 1, 4 do sky.update(0.25) end
  local before = #fake.queued
  assertEq(before >= 3, true)
  sky.restore(); sky.update(1)
  assertEq(#fake.queued, before)
  assertEq(fake.objects.cnr_precipitation, nil)
  assertEq(fake.models.ASPHALT.cdata.staticFrictionCoefficient, 0.98)
end)

test("wind updates don't touch the lock", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT); sky.startClock(0)
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
  local make = _G.createObject
  _G.createObject = function() error("boom") end
  sky.apply(RAIN_NIGHT)
  _G.createObject = make
  assertEq(fake.locked, true)
  sky.restore()
  assertEq(fake.locked, false); assertEq(fake.state.cloudCover, 0.05)
end)

test("precipitation is not saved with the level", function()
  local sky, fake = load()
  sky.apply(RAIN_NIGHT)
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
