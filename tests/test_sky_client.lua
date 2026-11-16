dofile("tests/env_stubs.lua")
local function load(opts)
  local fake = fakeEnvironment(opts)
  for _, n in ipairs({ "copsAndRobbers/sky", "copsAndRobbers/surfaces", "copsAndRobbers/wind" }) do package.loaded[n] = nil end
  return require("copsAndRobbers/sky"), fake
end
local RAIN_NIGHT = { time = "night", weather = "rain", driving = true, windDir = 90, windSeed = 7 }

test("labels join the time and the weather", function()
  local sky = load()
  assertEq(sky.label(RAIN_NIGHT), "Night · Rain")
  assertEq(sky.label({ weather = "snow" }), "Snow")
  assertEq(sky.label({ clockSpeed = 30 }), nil)
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
  assertEq(s.time, 0.5); assertEq(s.play, false); assertEq(s.cloudCover, 1.0); assertEq(s.numOfDrops, nil)
  assertNear(s.groundWind.x, 4, 1e-6)
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
  sky.apply(RAIN_NIGHT); sky.restore()
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

test("the clock starts at GO at the configured speed", function()
  local sky, fake = load()
  sky.apply({ time = "sunset", clockSpeed = 60, windDir = 0, windSeed = 1 })
  sky.startClock(600)
  local s = fake.setStates[#fake.setStates]
  assertEq(s.play, true); assertEq(s.dayLength, 1440)
  assertNear(s.time, (0.245 + 600 * 60 / 86400) % 1, 1e-9)
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
