local M = {}

M.DEFAULTS = {
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
  roundTimeLimitSeconds = 0,
  lastSeenIntervalSeconds = 30,
  excludedModels = { "citybus", "us_semi", "md_series", "percheron", "rockbouncer" },
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
  trafficPerPlayer = 5,
}

M.CHOICES = {
  carMode = { random = true, evolving = true },
  timeOfDay = { sunrise = true, morning = true, noon = true, afternoon = true, sunset = true, night = true, random = true },
  weather = { clear = true, cloudy = true, rain = true, storm = true, fog = true, snow = true, random = true },
  dayLength = { off = true, fast = true, moderate = true, slow = true, realtime = true },
}

local strictlyPositive = {
  catchHoldSeconds = true, catchRadiusMeters = true, crashSpeedLossKmh = true,
  catchMaxSpeedKmh = true, stillMaxSpeedKmh = true, sightLiveIntervalSeconds = true,
}

local function copyList(t)
  local c = {}
  for i, v in ipairs(t) do c[i] = v end
  return c
end

local function validList(v)
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n ~= #v then return false end
  for _, item in ipairs(v) do
    if type(item) ~= "string" then return false end
  end
  return true
end

local RETIRED_KEYS = { clockSpeed = true }
local RETIRED_VALUES = { timeOfDay = "map", weather = "map" }
local MAXIMA = { assistMinSightPercent = 100, nightChancePercent = 100, badWeatherChancePercent = 100, trafficPerPlayer = 20 }
local WHOLE = { trafficPerPlayer = true }

local function validNumber(key, v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false end
  if MAXIMA[key] and v > MAXIMA[key] then return false end
  if WHOLE[key] and v % 1 ~= 0 then return false end
  if strictlyPositive[key] then return v > 0 end
  return v >= 0
end

function M.merge(raw)
  local cfg, warnings = {}, {}
  raw = type(raw) == "table" and raw or {}
  for key, default in pairs(M.DEFAULTS) do
    local v = raw[key]
    if v == nil then
      cfg[key] = type(default) == "table" and copyList(default) or default
    elseif type(default) == "table" then
      if validList(v) then
        cfg[key] = copyList(v)
      else
        cfg[key] = copyList(default)
        warnings[#warnings + 1] = string.format("%s must be a list of names, using the default", key)
      end
    elseif type(default) == "string" then
      if type(v) == "string" and (not M.CHOICES[key] or M.CHOICES[key][v]) then
        cfg[key] = v
      else
        cfg[key] = default
        warnings[#warnings + 1] = string.format("%s has invalid value %s, using %s", key, tostring(v), default)
      end
    elseif type(default) == "boolean" then
      if type(v) == "boolean" then
        cfg[key] = v
      else
        cfg[key] = default
        warnings[#warnings + 1] = string.format("%s must be true or false, using %s", key, tostring(default))
      end
    elseif validNumber(key, v) then
      cfg[key] = v
    else
      cfg[key] = default
      warnings[#warnings + 1] = string.format("%s has invalid value %s, using %s", key, tostring(v), tostring(default))
    end
  end
  local unknown = {}
  for key in pairs(raw) do
    if M.DEFAULTS[key] == nil then unknown[#unknown + 1] = tostring(key) end
  end
  table.sort(unknown)
  for _, key in ipairs(unknown) do
    warnings[#warnings + 1] = string.format("unknown setting %s ignored", key)
  end
  if cfg.copSpawnMaxMeters < cfg.copSpawnMinMeters then
    warnings[#warnings + 1] = string.format("copSpawnMaxMeters (%s) is below copSpawnMinMeters, using %s", tostring(cfg.copSpawnMaxMeters), tostring(cfg.copSpawnMinMeters))
    cfg.copSpawnMaxMeters = cfg.copSpawnMinMeters
  end
  return cfg, warnings
end

local function parseValue(default, text)
  if type(default) == "boolean" then
    local t = text:lower()
    if t == "true" or t == "on" or t == "yes" then return true end
    if t == "false" or t == "off" or t == "no" then return false end
    return nil
  elseif type(default) == "string" then
    return text
  elseif type(default) == "table" then
    local list = {}
    for item in text:gmatch("[^,%s]+") do list[#list + 1] = item end
    return list
  end
  return tonumber(text)
end

function M.setValue(raw, key, text)
  local default = M.DEFAULTS[key]
  if default == nil then return nil, "Unknown setting " .. tostring(key) end
  local value = parseValue(default, tostring(text or ""))
  local invalid = "Invalid value for " .. key .. ": " .. tostring(text)
  if value == nil then return nil, invalid end
  local updated = {}
  for k, v in pairs(raw or {}) do
    if not RETIRED_KEYS[k] and RETIRED_VALUES[k] ~= v then updated[k] = v end
  end
  updated[key] = value
  local _, warnings = M.merge(updated)
  for _, w in ipairs(warnings) do
    if w:find(key .. " ", 1, true) == 1 then return nil, invalid end
  end
  return updated
end

return M
