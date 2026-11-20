local sky = require("copsAndRobbers/sky")
local visibility = require("copsAndRobbers/visibility")

local M = {}
local solarKeys = {"latitude", "longitude", "year", "month", "day", "utcOffset", "dstRule"}
local precipitationFactors = {clear = 1, cloudy = 1, fog = 1, rain = 0.85, snow = 0.75, storm = 0.70, thunderstorm = 0.70}
local lightsKey = "lights_state"
local solarCache

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function read(getter, ...)
  if type(getter) ~= "function" then return nil end
  local ok, value, extra = pcall(getter, ...)
  if ok then return value, extra end
end

local function matchesSolarCache(tod, level)
  if not solarCache or solarCache.level ~= level then return false end
  for _, key in ipairs(solarKeys) do
    if solarCache[key] ~= tod[key] then return false end
  end
  return true
end

local function solarMeasurement(tod)
  local level = read(getCurrentLevelIdentifier)
  if matchesSolarCache(tod, level) then return solarCache end

  solarCache = nil
  local solar = core_solarTimeOfDay
  if not solar then return nil end
  local values = read(solar.getSolarTimeOfDayValues, tod)
  local measurement
  if type(values) == "table" and finite(values.sunrise) and finite(values.sunset)
      and values.sunrise % 1 ~= values.sunset % 1 then
    measurement = {sunrise = values.sunrise, sunset = values.sunset}
  else
    local events = read(solar.getSolarTimeOfDayEvents, tod)
    local polar = type(events) == "table" and events.polar
    if polar == "day" or polar == "night" then
      measurement = {polar = polar}
    end
  end
  if not measurement then return nil end

  measurement.level = level
  for _, key in ipairs(solarKeys) do
    measurement[key] = tod[key]
  end
  solarCache = measurement
  return measurement
end

local function sampleDaylight(env)
  local tod = read(env and env.getTimeOfDay)
  local measurement = type(tod) == "table" and solarMeasurement(tod)
  if measurement then
    if measurement.polar then return measurement.polar == "day" and 1 or 0 end
    local daylight = visibility.daylight(tod.time, measurement.sunrise, measurement.sunset)
    if daylight then return daylight end
  end

  local lightState = read(env and env.getLightState)
  return type(lightState) == "table" and lightState.isNight == false and 1 or 0
end

local function sampleWeather(env)
  local from, to, progress = sky.weatherBlend()
  local fromPreset, toPreset = sky.WEATHER[from], sky.WEATHER[to]
  local fromFog = fromPreset and fromPreset.fogDensity or 15
  local toFog = toPreset and toPreset.fogDensity or 15
  local fromPrecipitation = precipitationFactors[from] or 0.70
  local toPrecipitation = precipitationFactors[to] or 0.70

  local fog, precipitation
  if finite(progress) then
    local blend = math.max(0, math.min(1, progress))
    fog = fromFog + (toFog - fromFog) * blend
    precipitation = fromPrecipitation + (toPrecipitation - fromPrecipitation) * blend
  else
    fog = math.max(fromFog, toFog)
    precipitation = math.min(fromPrecipitation, toPrecipitation)
  end

  local density, levelInfo = read(env and env.getFogDensity)
  return levelInfo and finite(density) and density or fog / 1000, precipitation
end

local function runnerLamps(runner)
  local bridge = core_vehicleBridge
  if not runner or not bridge or type(bridge.registerValueChangeNotification) ~= "function" then return false end
  local id = read(runner.getID, runner)
  if not finite(id) then return false end
  if not pcall(bridge.registerValueChangeNotification, runner, lightsKey) then return false end
  local value = read(bridge.getCachedVehicleData, id, lightsKey)
  return value == 1 or value == 2
end

function M.sample(runner)
  local env = core_environment
  local fog, precipitation = sampleWeather(env)
  return sampleDaylight(env), runnerLamps(runner), fog, precipitation
end

function M.reset()
  solarCache = nil
end

return M
