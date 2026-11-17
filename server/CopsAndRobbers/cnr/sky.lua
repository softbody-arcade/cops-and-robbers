local weather = require("cnr.weather")

local M = {}

M.DAY_SECONDS = weather.DAY_SECONDS

local DAY = { "sunrise", "morning", "noon", "afternoon", "sunset" }
local CALM = { "clear", "cloudy" }
local BAD = { "rain", "storm", "fog", "snow" }
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local SPRING_AUTUMN = { 3, 4, 10, 11 }
local WHOLE_YEAR = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
local WINDOWS = {
  snow = { 12, 1 },
  fog = { 10, 11 },
  rain = SPRING_AUTUMN,
  storm = SPRING_AUTUMN,
  clear = WHOLE_YEAR,
  cloudy = WHOLE_YEAR,
}

local function pickTime(cfg, random)
  if cfg.timeOfDay ~= "random" then return cfg.timeOfDay end
  if random() * 100 < cfg.nightChancePercent then return "night" end
  return DAY[random(#DAY)]
end

local function pickWeather(cfg, random)
  if cfg.weather ~= "random" then return cfg.weather end
  local list = CALM
  if random() * 100 < cfg.badWeatherChancePercent then list = BAD end
  return list[random(#list)]
end

function M.date(weather, random)
  local months = WINDOWS[weather] or WHOLE_YEAR
  local total = 0
  for _, m in ipairs(months) do total = total + DAYS_IN_MONTH[m] end
  local n = random(1, total)
  for _, m in ipairs(months) do
    if n <= DAYS_IN_MONTH[m] then return m, n end
    n = n - DAYS_IN_MONTH[m]
  end
end

function M.pick(cfg, random, geo, year)
  if geo then return {} end
  local time = pickTime(cfg, random)
  local weather = pickWeather(cfg, random)
  local month, day = M.date(weather, random)
  return {
    time = time,
    weather = weather,
    year = year or tonumber(os.date("%Y")),
    month = month,
    day = day,
    windDir = random(0, 359),
    windSeed = random(1, 2147483646),
  }
end

function M.hasRandom(cfg)
  return cfg.timeOfDay == "random" or cfg.weather == "random"
end

function M.payload(s, cfg, clockSeconds)
  if s == nil or next(s) == nil then return nil end
  local p = {
    time = s.time,
    weather = s.weather,
    year = s.year,
    month = s.month,
    day = s.day,
    windDir = s.windDir,
    windSeed = s.windSeed,
    clockSeconds = clockSeconds,
    daySeconds = M.DAY_SECONDS[cfg.dayLength],
  }
  if s.weather and cfg.weatherDriving then p.driving = true end
  return p
end

function M.record(s, cfg)
  local p = M.payload(s, cfg, nil)
  if not p then return nil end
  return { time = p.time, weather = p.weather, year = p.year, month = p.month, day = p.day, dayLength = cfg.dayLength, driving = p.driving }
end

return M
