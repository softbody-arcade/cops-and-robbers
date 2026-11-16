local M = {}

local DAY = { "sunrise", "morning", "noon", "afternoon", "sunset" }
local CALM = { "clear", "cloudy" }
local BAD = { "rain", "storm", "fog", "snow" }

local function pickTime(cfg, random)
  if cfg.timeOfDay == "map" then return nil end
  if cfg.timeOfDay ~= "random" then return cfg.timeOfDay end
  if random() * 100 < cfg.nightChancePercent then return "night" end
  return DAY[random(#DAY)]
end

local function pickWeather(cfg, random)
  if cfg.weather == "map" then return nil end
  if cfg.weather ~= "random" then return cfg.weather end
  local list = CALM
  if random() * 100 < cfg.badWeatherChancePercent then list = BAD end
  return list[random(#list)]
end

function M.pick(cfg, random, geo)
  if geo then return {} end
  local time = pickTime(cfg, random)
  local weather = pickWeather(cfg, random)
  return {
    time = time,
    weather = weather,
    windDir = random(0, 359),
    windSeed = random(1, 2147483646),
  }
end

function M.hasRandom(cfg)
  return cfg.timeOfDay == "random" or cfg.weather == "random"
end

function M.payload(s, cfg, clockSeconds)
  if s == nil or next(s) == nil then return nil end
  if s.time == nil and s.weather == nil and cfg.clockSpeed <= 0 then return nil end
  local p = {
    time = s.time,
    weather = s.weather,
    windDir = s.windDir,
    windSeed = s.windSeed,
    clockSeconds = clockSeconds,
  }
  if cfg.clockSpeed > 0 then p.clockSpeed = cfg.clockSpeed end
  if s.weather and cfg.weatherDriving then p.driving = true end
  return p
end

return M
