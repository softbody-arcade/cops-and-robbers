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

test("invalid settings log the basename of the file", function()
  local env = serverBoot.boot({ files = { ["game.json"] = "{broken" } })
  local logs = {}
  settings.new(env.dir .. "game.json", decl, function(line) logs[#logs + 1] = line end):load()
  env.cleanup()
  local prefix = "game.json is not valid JSON, using defaults"
  assertEq(logs[1]:sub(1, #prefix), prefix)
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
