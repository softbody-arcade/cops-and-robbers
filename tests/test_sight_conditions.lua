local sightConditions = require("copsAndRobbers/sightConditions")
local sky = require("copsAndRobbers/sky")

local function fixture(run)
  local env, solar, bridge, levelIdentifier, weatherBlend = core_environment, core_solarTimeOfDay,
    core_vehicleBridge, getCurrentLevelIdentifier, sky.weatherBlend
  core_environment, core_solarTimeOfDay, core_vehicleBridge, getCurrentLevelIdentifier = {}, {}, {}, nil
  sky.weatherBlend = function() return "clear", "clear", 1 end
  sightConditions.reset()
  local ok, err = pcall(run)
  sightConditions.reset()
  core_environment, core_solarTimeOfDay, core_vehicleBridge, getCurrentLevelIdentifier = env, solar, bridge, levelIdentifier
  sky.weatherBlend = weatherBlend
  if not ok then error(err, 0) end
end

test("daylight reads the current clock and refreshes anchors on each map and solar key change", function()
  fixture(function()
    local tod = {
      time = 0, latitude = 37, longitude = -122, year = 2026, month = 11,
      day = 18, utcOffset = -8, dstRule = "us",
    }
    local map, lookups = "west_coast_usa", 0
    getCurrentLevelIdentifier = function() return map end
    core_environment.getTimeOfDay = function() return tod end
    core_environment.getLightState = function() return {isNight = true} end
    core_solarTimeOfDay.getSolarTimeOfDayValues = function(state)
      assertEq(state, tod)
      lookups = lookups + 1
      return {sunrise = 0.75, sunset = 0.25}
    end
    assertEq((sightConditions.sample()), 1)
    assertEq(lookups, 1)
    tod.time = 1.75
    assertEq((sightConditions.sample()), 0.5)
    assertEq(lookups, 1)

    local changes = {{"latitude", 42}, {"longitude", -110}, {"year", 2027}, {"month", 9},
      {"day", 21}, {"utcOffset", -7}, {"dstRule", "none"}}
    for index, change in ipairs(changes) do
      tod[change[1]] = change[2]
      assertEq((sightConditions.sample()), 0.5, change[1])
      assertEq(lookups, index + 1, change[1])
    end
    map = "utah"
    assertEq((sightConditions.sample()), 0.5)
    assertEq(lookups, 9)
    sightConditions.reset()
    assertEq((sightConditions.sample()), 0.5)
    assertEq(lookups, 10)
  end)
end)

test("daylight uses cached polar events ahead of the engine night flag", function()
  fixture(function()
    local tod = {time = 0, month = 6}
    local night, events = true, 0
    core_environment.getTimeOfDay = function() return tod end
    core_environment.getLightState = function() return {isNight = night} end
    core_solarTimeOfDay.getSolarTimeOfDayValues = function() return {noon = 0, night = 0.5} end
    core_solarTimeOfDay.getSolarTimeOfDayEvents = function(state)
      assertEq(state, tod)
      events = events + 1
      return {polar = state.month == 6 and "day" or "night"}
    end
    assertEq((sightConditions.sample()), 1)
    tod.time = 0.5
    assertEq((sightConditions.sample()), 1)
    assertEq(events, 1)
    night, tod.month = false, 12
    assertEq((sightConditions.sample()), 0)
    assertEq(events, 2)
  end)
end)

test("daylight falls back to a definite engine night flag when the solar sample is unusable", function()
  fixture(function()
    local tod = {time = 0 / 0, day = 18}
    core_environment.getTimeOfDay = function() return tod end
    core_environment.getLightState = function() return {isNight = false} end
    core_solarTimeOfDay.getSolarTimeOfDayValues = function() return {sunrise = 0.75, sunset = 0.25} end
    assertEq((sightConditions.sample()), 1)

    core_environment.getTimeOfDay = function() error("unavailable") end
    assertEq((sightConditions.sample()), 1)
    core_environment.getTimeOfDay = function() return {time = 0.5, day = 19} end
    core_solarTimeOfDay.getSolarTimeOfDayValues = function() return {sunrise = 0.5, sunset = 0.5} end
    assertEq((sightConditions.sample()), 1)

    core_solarTimeOfDay.getSolarTimeOfDayValues = nil
    core_environment.getLightState = function() return {isNight = true} end
    assertEq((sightConditions.sample()), 0)
    core_environment.getLightState = function() return {isNight = "false"} end
    assertEq((sightConditions.sample()), 0)
    core_environment.getLightState = nil
    assertEq((sightConditions.sample()), 0)
  end)
end)

local function assertWeather(expectedFog, expectedPrecipitation)
  local _, _, fog, precipitation = sightConditions.sample()
  assert(fog == fog and precipitation == precipitation)
  assertNear(fog, expectedFog, 1e-9, "raw fog")
  assertNear(precipitation, expectedPrecipitation, 1e-9, "precipitation")
end

test("live fog wins when LevelInfo supplies a finite density", function()
  fixture(function()
    local density, levelInfo = 0, nil
    core_environment.getFogDensity = function() return density, levelInfo end
    sky.weatherBlend = function() return "clear", "rain", 0.5 end
    assertWeather(0.0012, 0.925)
    levelInfo = {}
    assertWeather(0, 0.925)
    density = 0.0035
    assertWeather(0.0035, 0.925)
    density = 0 / 0
    assertWeather(0.0012, 0.925)
    density = math.huge
    assertWeather(0.0012, 0.925)
    core_environment.getFogDensity = function() error("unavailable") end
    assertWeather(0.0012, 0.925)
  end)
end)

test("weather presets supply fallback fog and precipitation for each stable weather", function()
  fixture(function()
    for _, row in ipairs({
      {"clear", 0.0004, 1}, {"cloudy", 0.001, 1}, {"fog", 0.015, 1},
      {"rain", 0.002, 0.85}, {"snow", 0.005, 0.75}, {"storm", 0.004, 0.70},
      {"thunderstorm", 0.004, 0.70}, {"unknown", 0.015, 0.70},
    }) do
      sky.weatherBlend = function() return row[1], row[1], 1 end
      assertWeather(row[2], row[3])
    end
  end)
end)

test("weather blends use current progress and restrictive values for missing progress", function()
  fixture(function()
    local from, to, progress = "fog", "storm", nil
    sky.weatherBlend = function() return from, to, progress end
    assertWeather(0.015, 0.70)
    progress = math.huge
    assertWeather(0.015, 0.70)
    progress = -1
    assertWeather(0.015, 1)
    progress = 2
    assertWeather(0.004, 0.70)
    from, to, progress = "unknown", "rain", 0.25
    assertWeather(0.01175, 0.7375)
    from, to = nil, nil
    assertWeather(0.015, 0.70)
  end)
end)

test("runner lamps follow bridge values through vehicle changes and reused IDs", function()
  fixture(function()
    local function vehicle(id)
      return {getID = function() return id end}
    end
    local a, b, replacement = vehicle(41), vehicle(42), vehicle(42)
    local cache = {[41] = {data = {lights_state = 2}, registered = {lights_state = true}}}
    local registrations, reads, notifications, unregistrations = 0, 0, 0, 0
    local registeredVehicle
    core_vehicleBridge.registerValueChangeNotification = function(veh, key)
      assertEq(key, "lights_state")
      registeredVehicle = veh
      registrations = registrations + 1
      local id = veh:getID()
      cache[id] = cache[id] or {data = {}, registered = {}}
      if not cache[id].registered[key] then
        notifications = notifications + 1
        cache[id].registered[key] = true
      end
    end
    core_vehicleBridge.getCachedVehicleData = function(id, key)
      assertEq(key, "lights_state")
      reads = reads + 1
      assertEq(reads, registrations)
      assertEq(id, registeredVehicle:getID())
      return cache[id].data[key]
    end
    core_vehicleBridge.unregisterValueChangeNotification = function()
      unregistrations = unregistrations + 1
      cache[41].registered.lights_state = nil
    end
    local function assertLamps(runner, expected, queued)
      local _, lamps = sightConditions.sample(runner)
      assertEq(lamps, expected)
      assertEq(notifications, queued)
      if runner then assertEq(registeredVehicle, runner) end
    end
    assertLamps(a, true, 0)
    assertLamps(b, false, 1)
    for _, row in ipairs({{1, true}, {0, false}, {3, false}, {"1", false}, {true, false}}) do
      cache[42].data.lights_state = row[1]
      assertLamps(b, row[2], 1)
    end
    cache[42] = nil
    assertLamps(replacement, false, 2)
    cache[42].data.lights_state = 2
    assertLamps(replacement, true, 2)
    assertLamps(nil, false, 2)
    sightConditions.reset()
    assertLamps(nil, false, 2)
    assertEq(registrations, 9)
    assertEq(reads, 9)
    assertEq(unregistrations, 0)
    assertEq(cache[41].registered.lights_state, true)
  end)
end)

test("runner lamps default off when the bridge cannot read the assigned car", function()
  fixture(function()
    local car = {getID = function() return 42 end}
    local _, lamps = sightConditions.sample(car)
    assertEq(lamps, false)
    core_vehicleBridge.registerValueChangeNotification = function() error("vehicle removed") end
    core_vehicleBridge.getCachedVehicleData = function() return 2 end
    _, lamps = sightConditions.sample(car)
    assertEq(lamps, false)
  end)
end)
