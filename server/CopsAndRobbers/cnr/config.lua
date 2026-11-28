local settings = require("arcade.settings")

local GAME = {
  DEFAULTS = {
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
    crashSpeedLossKmh = 50,
    crashPenaltySeconds = 10,
    roundTimeLimitSeconds = 1800,
    helicopter = true,
    helicopterArrivalSeconds = 60,
    helicopterUpSeconds = 120,
    helicopterRefuelSeconds = 90,
    sightMaxMeters = 400,
    sightGraceSeconds = 1.5,
    sightLiveIntervalSeconds = 1,
    sightNoRouteSeconds = 5,
    sightNoRouteMinMeters = 50,
    assistMinSightPercent = 20,
    sirensAllowed = true,
    carMode = "random",
    trafficRunnerOnly = false,
  },
  CHOICES = {
    carMode = { random = true, evolving = true },
  },
  RANGES = { copSpawnMinMeters = "copSpawnMaxMeters" },
  POSITIVE = {
    catchHoldSeconds = true, catchRadiusMeters = true, crashSpeedLossKmh = true,
    catchMaxSpeedKmh = true, stillMaxSpeedKmh = true, sightLiveIntervalSeconds = true, helicopterUpSeconds = true,
  },
  MAXIMA = { assistMinSightPercent = 100 },
  RETIRED_KEYS = { lastSeenIntervalSeconds = true },
  OVERRIDES = {},
}

local declaration = settings.combine(settings.GLOBAL, GAME)
local M = {
  GAME = GAME,
  declaration = declaration,
  DEFAULTS = declaration.DEFAULTS,
  CHOICES = declaration.CHOICES,
  TIMING_RANGES = declaration.TIMING_RANGES,
}

function M.merge(raw)
  return settings.merge(raw, declaration)
end

function M.setValue(raw, key, text)
  return settings.setValue(raw, key, text, declaration)
end

return M
