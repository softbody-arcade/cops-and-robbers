local settings = require("arcade.settings")
local config = require("cnr.config")
local store = require("arcade.store")
dofile("tests/server_boot.lua")

local decl = settings.combine(settings.GLOBAL, config.GAME)
local defaults = {
  headStartSeconds = 7,
  runnerCountdownSeconds = 3,
  resetWaitSeconds = 7,
  catchHoldSeconds = 7,
  catchRadiusMeters = 10,
  catchMaxSpeedKmh = 3,
  stillMaxSpeedKmh = 1,
  copResetMinDistanceMeters = 1000,
  gasStationRadiusMeters = 25,
  copSpawnMinMeters = 50,
  copSpawnMaxMeters = 150,
  explodeOnCatch = false,
  includeModVehicles = false,
  crashSpeedLossKmh = 50,
  crashPenaltySeconds = 10,
  roundTimeLimitSeconds = 1800,
  helicopter = true,
  helicopterArrivalSeconds = 60,
  helicopterUpSeconds = 120,
  helicopterRefuelSeconds = 90,
  excludedModels = {},
  autoNextRound = false,
  autoNextDelaySeconds = 15,
  sightMaxMeters = 400,
  sightGraceSeconds = 1.5,
  sightLiveIntervalSeconds = 1,
  sightNoRouteSeconds = 5,
  sightNoRouteMinMeters = 50,
  assistMinSightPercent = 20,
  sirensAllowed = true,
  carMode = "random",
  timeOfDay = "random",
  nightChancePercent = 25,
  dayLength = "moderate",
  weather = "random",
  badWeatherChancePercent = 25,
  weatherDriving = true,
  weatherChanges = true,
  weatherChangeMinMinutes = 3,
  weatherChangeMaxMinutes = 8,
  lightningMinSeconds = 5,
  lightningMaxSeconds = 20,
  trafficPerPlayer = 0,
  trafficRunnerOnly = false,
}
local raw = {
  lightningMinSeconds = 30, lightningMaxSeconds = 20, copSpawnMinMeters = 200, copSpawnMaxMeters = 100,
  clockSpeed = 2, weather = "map", zzz = 1, aaa = 1,
}

local function sameValues(actual, expected)
  assertEq(serverBoot.encode(actual, true), serverBoot.encode(expected, true))
end

test("global and game declarations preserve the server defaults", function()
  sameValues(decl.DEFAULTS, defaults)
  local globalKeys = {
    "timeOfDay", "nightChancePercent", "dayLength", "weather", "badWeatherChancePercent", "weatherDriving",
    "weatherChanges", "weatherChangeMinMinutes", "weatherChangeMaxMinutes", "lightningMinSeconds",
    "lightningMaxSeconds", "trafficPerPlayer", "autoNextRound", "autoNextDelaySeconds", "includeModVehicles", "excludedModels",
  }
  local expected = {}
  for _, key in ipairs(globalKeys) do expected[key] = defaults[key] end
  sameValues(settings.GLOBAL.DEFAULTS, expected)
end)

test("duplicate declarations fail even when the shared default is false", function()
  local ok = pcall(settings.combine, settings.GLOBAL, { DEFAULTS = { autoNextRound = true } })
  assertEq(ok, false)
end)

test("game timing ranges require positive whole seconds at both ends", function()
  local combined = settings.combine(settings.GLOBAL, {
    DEFAULTS = { fooMinSeconds = 2, fooMaxSeconds = 4 },
    TIMING_RANGES = { fooMinSeconds = "fooMaxSeconds" },
  })
  for _, key in ipairs({ "fooMinSeconds", "fooMaxSeconds" }) do
    assertEq(combined.WHOLE[key], true, key)
    assertEq(combined.POSITIVE[key], true, key)
  end
  local cfg, warnings = settings.merge({ fooMinSeconds = 1.5 }, combined)
  assertEq(cfg.fooMinSeconds, 2)
  sameValues(warnings, { "fooMinSeconds has invalid value 1.5, using 2" })
end)

test("an override with the wrong type fails with the setting name", function()
  local ok, err = pcall(settings.combine, settings.GLOBAL, { OVERRIDES = { autoNextRound = "yes" } })
  assertEq(ok, false)
  assert(err:find("autoNextRound", 1, true), err)
end)

test("an override outside the global choices fails with the setting name", function()
  local ok, err = pcall(settings.combine, settings.GLOBAL, { OVERRIDES = { weather = "hail" } })
  assertEq(ok, false)
  assert(err:find("weather", 1, true), err)
end)

test("overrides change only the chosen global default for this game", function()
  local combined = settings.combine(settings.GLOBAL, { DEFAULTS = {}, OVERRIDES = { weather = "rain" } })
  local expected = {}
  for key, value in pairs(settings.GLOBAL.DEFAULTS) do expected[key] = value end
  expected.weather = "rain"
  sameValues(combined.DEFAULTS, expected)
  assertEq(settings.GLOBAL.DEFAULTS.weather, "random")
  local cfg, warnings = settings.merge({ weather = "map" }, combined)
  assertEq(cfg.weather, "rain")
  assertEq(warnings[1], "weather has invalid value map, using rain")
end)

test("merge preserves the corrected config, warnings and their defined order", function()
  local cfg, warnings = settings.merge(raw, decl)
  local expected = {}
  for key, value in pairs(defaults) do expected[key] = value end
  expected.copSpawnMinMeters, expected.copSpawnMaxMeters = 200, 200
  expected.lightningMinSeconds, expected.lightningMaxSeconds = 30, 30
  sameValues(cfg, expected)

  local cop = "copSpawnMaxMeters (100) is below copSpawnMinMeters, using 200"
  local timing = "lightningMaxSeconds (20) is below lightningMinSeconds, using 30"
  local expectedWarnings = {
    "weather has invalid value map, using random", "unknown setting aaa ignored",
    "unknown setting clockSpeed ignored", "unknown setting zzz ignored", cop, timing,
  }
  local index = {}
  for i, warning in ipairs(warnings) do index[warning] = i end
  table.sort(warnings)
  table.sort(expectedWarnings)
  sameValues(warnings, expectedWarnings)
  assert(index["unknown setting aaa ignored"] < index["unknown setting clockSpeed ignored"])
  assert(index["unknown setting clockSpeed ignored"] < index["unknown setting zzz ignored"])
  assert(index[cop] < index[timing])
end)

test("an invalid value keeps the original error text", function()
  local updated, err = settings.setValue(raw, "lightningMinSeconds", "0", decl)
  assertEq(updated, nil)
  assertEq(err, "Invalid value for lightningMinSeconds: 0")
end)

local copyName = "game.json.corrupt-20261128-101500"
local warning = "game.json is not valid JSON, using defaults; "
local kept = warning .. "kept a copy as " .. copyName

local function withSettings(bytes, check)
  local env = serverBoot.boot({ files = { ["game.json"] = bytes } })
  local path = env.dir .. "game.json"
  local logs = {}
  local service = settings.new(path, decl, function(line) logs[#logs + 1] = line end)
  local date, copy = os.date, store.copy
  os.date = function(format)
    assertEq(format, "%Y%m%d-%H%M%S")
    return "20261128-101500"
  end
  local ok, err = pcall(check, service, path, env.dir .. copyName, logs)
  os.date, store.copy = date, copy
  env.cleanup()
  assert(ok, err)
end

test("broken settings keep their exact bytes and reuse the copy on reload", function()
  local bytes = "{broken\r\n"
  withSettings(bytes, function(service, path, backup, logs)
    sameValues(service:load(), defaults)
    assertEq(store.read(backup), bytes)
    assertEq(store.read(path), bytes)
    store.copy = function() error("identical settings were copied twice") end
    sameValues(service:load(), defaults)
    sameValues(logs, { kept, kept })
    assertEq(FS.Exists(backup .. "-2"), false)
  end)
end)

test("distinct broken settings in the same second keep separate copies", function()
  withSettings("{first", function(service, path, backup, logs)
    service:load()
    store.write(path, "{second")
    service:load()
    service:load()
    assertEq(store.read(backup), "{first")
    assertEq(store.read(backup .. "-2"), "{second")
    assertEq(store.read(path), "{second")
    assertEq(FS.Exists(backup .. "-3"), false)
    sameValues(logs, { kept, kept .. "-2", kept .. "-2" })
  end)
end)

test("copy failure logs the error and loads defaults", function()
  withSettings("{broken", function(service, path, backup, logs)
    local called = false
    store.copy = function(src, dst)
      assertEq(src, path)
      assertEq(dst, backup)
      assertEq(FS.Exists(dst), false)
      called = true
      return nil, "denied"
    end
    sameValues(service:load(), defaults)
    assertEq(called, true)
    sameValues(logs, { warning .. "could not keep a copy: denied" })
    assertEq(store.read(path), "{broken")
  end)
end)

test("an empty settings file keeps an empty copy", function()
  withSettings("", function(service, path, backup, logs)
    sameValues(service:load(), defaults)
    assertEq(store.read(backup), "")
    assertEq(store.read(path), "")
    sameValues(logs, { kept })
  end)
end)

test("missing and valid settings load without making a copy", function()
  withSettings(nil, function(service, path, backup, logs)
    sameValues(service:load(), defaults)
    assertEq(FS.Exists(backup), false)
    store.write(path, '{"headStartSeconds":3}')
    assertEq(service:load().headStartSeconds, 3)
    assertEq(FS.Exists(backup), false)
    sameValues(logs, {})
  end)
end)

test("saving a raw edit preserves unknowns and drops retired entries", function()
  local env = serverBoot.boot({ config = serverBoot.encode(raw) })
  local path = env.dir .. "config.json"
  local logs = {}
  local service = settings.new(path, decl, function(line) logs[#logs + 1] = line end)
  local cfg, warnings, loaded = service:load()
  sameValues(loaded, raw)
  assertEq(cfg.lightningMaxSeconds, 30)
  assertEq(#warnings, 6)
  assertEq(#logs, #warnings)
  for i, warning in ipairs(warnings) do assertEq(logs[i], "config: " .. warning) end
  service:save(assert(settings.setValue(loaded, "headStartSeconds", "9", decl)))
  local saved = store.decode(path)
  env.cleanup()
  sameValues(saved, {
    headStartSeconds = 9, lightningMinSeconds = 30, lightningMaxSeconds = 20,
    copSpawnMinMeters = 200, copSpawnMaxMeters = 100, zzz = 1, aaa = 1,
  })
end)
