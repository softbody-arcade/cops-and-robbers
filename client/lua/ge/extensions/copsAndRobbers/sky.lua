local wind = require("copsAndRobbers/wind")
local surfaces = require("copsAndRobbers/surfaces")
local rain = require("copsAndRobbers/rain")
local climate = require("copsAndRobbers/climate")
local units = require("copsAndRobbers/units")

local M = {}

M.WEATHER = {
  clear = { cloudCover = 0.4, fogDensity = 0.4, windSpeed = 0.1 },
  cloudy = { cloudCover = 1.8, fogDensity = 1, windSpeed = 0.3 },
  rain = {
    cloudCover = 2.2, fogDensity = 4, windSpeed = 0.5,
    precipitation = { dataBlock = "rain_medium", numDrops = 3000, dropSize = 1, minSpeed = 0.4, maxSpeed = 0.5, volume = 1.0 },
  },
  storm = {
    cloudCover = 3.0, fogDensity = 8, windSpeed = 1.5,
    precipitation = { dataBlock = "rain_medium", numDrops = 7000, dropSize = 1.3, minSpeed = 0.6, maxSpeed = 0.8, volume = 2.0 },
  },
  fog = { cloudCover = 1.5, fogDensity = 15, windSpeed = 0.1 },
  snow = {
    cloudCover = 2.2, fogDensity = 5, windSpeed = 0.4,
    precipitation = { dataBlock = "Snow_menu", numDrops = 5000, dropSize = 0.2, minSpeed = 0.1, maxSpeed = 0.3 },
  },
}

M.BLEND_SECONDS = 3
local LOCK_DELAY = M.BLEND_SECONDS + 0.5
local WIND_INTERVAL = 0.25
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local saved, wasLocked, round, clockStart, target
local lockTimer, lockAfter, restoring
local roundTime, started, sinceWind = 0, false, 0

local function forget()
  wind.reset()
  saved, wasLocked, round, clockStart, target = nil, false, nil, nil, nil
  roundTime, started, sinceWind = 0, false, 0
end

local function blend(env, state)
  env.setState(nil)
  env.setState(state, M.BLEND_SECONDS)
end

local function capitalise(key)
  return key:sub(1, 1):upper() .. key:sub(2)
end

local function localDate(month, day, latitude)
  if not (latitude and latitude < 0) then return month, day end
  local shifted = (month + 5) % 12 + 1
  return shifted, math.min(day, DAYS_IN_MONTH[shifted])
end

local function mapLatitude()
  local env = core_environment
  local state = env and env.getState and env.getState()
  return state and state.latitude
end

local function setsSomething(p)
  return p ~= nil and (p.time ~= nil or p.weather ~= nil or (p.daySeconds or 0) > 0)
end

local function windy(p)
  return p.driving and wind.WEATHER[p.weather] ~= nil
end

local function roundState(env, p)
  local init = env.getInitState() or {}
  local state = { play = false, temperatureCurveOverrideC = false }
  local solar = env.getState() or {}
  if p.month and p.day then
    local year = p.year or solar.year
    local month, day = localDate(p.month, p.day, solar.latitude)
    state.year, state.month, state.day = year, month, day
    solar.year, solar.month, solar.day = year, month, day
  end
  if p.time then
    state.time = env.getSolarTimeOfDayValue(p.time, solar) or env.timeOfDayKeyToTime[p.time]
  else
    state.time, state.dayLength = init.time, init.dayLength
  end
  local low, high = climate.range(p.weather, p.month)
  if low then
    local sunriseT = env.getSolarTimeOfDayValue("sunrise", solar)
    local noonT = env.getSolarTimeOfDayValue("noon", solar)
    if sunriseT and noonT then
      local points = { { sunriseT, low }, { (noonT + 2 / 24) % 1, high } }
      table.sort(points, function(a, b) return a[1] < b[1] end)
      state.temperatureCurveOverrideC = points
    end
  end
  state.numOfDrops = init.numOfDrops
  local weather = M.WEATHER[p.weather] or init
  state.cloudCover, state.fogDensity, state.windSpeed = weather.cloudCover, weather.fogDensity, weather.windSpeed
  if windy(p) then
    state.groundWind = vec3(wind.at(p.weather, p.windSeed, p.windDir, 0))
  else
    state.groundWind = vec3(0, 0, 0)
  end
  return state
end

function M.label(p, withDate)
  if not p then return nil end
  local parts = {}
  if p.time then parts[#parts + 1] = capitalise(p.time) end
  if p.weather then parts[#parts + 1] = capitalise(p.weather) end
  if withDate and p.day and MONTHS[p.month] then
    local month, day = localDate(p.month, p.day, mapLatitude())
    parts[#parts + 1] = string.format("%d %s", day, MONTHS[month])
  end
  if #parts == 0 then return nil end
  if withDate then
    local low, high = climate.range(p.weather, p.month)
    if low then
      local unit = units.temperatureUnit()
      parts[#parts + 1] = string.format("%d to %d %s", units.temperature(low, unit), units.temperature(high, unit), unit == "f" and "°F" or "°C")
    end
  end
  return table.concat(parts, " · ")
end

function M.apply(p)
  local env = core_environment
  if not env or not setsSomething(p) then return end
  if not saved then
    if restoring then
      saved, wasLocked = restoring.state, restoring.wasLocked
    else
      saved = env.getState() or {}
      local g = saved.groundWind
      if g then saved.groundWind = vec3(g.x, g.y, g.z) end
      wasLocked = not env.canChange()
    end
  end
  local state = roundState(env, p)
  round, clockStart, target = p, state.time, state
  env.enableChanges(true)
  local ok, err = pcall(function()
    blend(env, state)
    local weather = M.WEATHER[p.weather]
    rain.target(weather and weather.precipitation or nil, M.BLEND_SECONDS)
    surfaces.apply(p.driving and p.weather or nil)
  end)
  if ok then
    lockTimer, lockAfter = LOCK_DELAY, true
  else
    pcall(env.setState, target)
    rain.clear()
    env.enableChanges(false)
    lockTimer, restoring = nil, nil
    log("E", "cnr_sky", tostring(err))
  end
end

function M.startClock(clockSeconds)
  local env = core_environment
  if not env or not round then return end
  roundTime, started = clockSeconds or 0, true
  local daySeconds = round.daySeconds or 0
  local landing = lockTimer ~= nil
  if landing then
    env.enableChanges(true)
    env.setState(target)
  end
  if daySeconds > 0 and clockStart then
    env.enableChanges(true)
    env.setState({
      time = (clockStart + roundTime / daySeconds) % 1,
      play = true,
      dayLength = daySeconds,
    })
    env.enableChanges(false)
  elseif landing then
    env.enableChanges(false)
  end
  lockTimer, restoring = nil, nil
end

function M.update(dt)
  if rain.active() then
    local ok, err = pcall(rain.update, dt)
    if not ok then
      rain.clear()
      log("E", "cnr_sky", tostring(err))
    end
  end
  if not core_environment then return end
  if lockTimer then
    lockTimer = lockTimer - dt
    if lockTimer <= 0 then
      core_environment.enableChanges(not lockAfter)
      lockTimer, restoring = nil, nil
    end
  end
  if not round then return end
  if started then roundTime = roundTime + dt end
  if not windy(round) then return end
  sinceWind = sinceWind + dt
  if sinceWind < WIND_INTERVAL then return end
  sinceWind = 0
  local x, y, z = wind.at(round.weather, round.windSeed, round.windDir, roundTime)
  be:queueAllObjectLua(string.format("obj:setWind(%f,%f,%f)", x, y, z))
  be:setGroundWind(vec3(x, y, z))
end

function M.restore(immediate)
  local env = core_environment
  if immediate then rain.clear() end
  if env and immediate and not saved and restoring then
    env.enableChanges(true)
    env.setState(restoring.state)
    env.enableChanges(not restoring.wasLocked)
    lockTimer, restoring = nil, nil
    return
  end
  if not env or not saved then return end
  env.enableChanges(true)
  surfaces.restore()
  if not immediate then rain.target(nil, M.BLEND_SECONDS) end
  if immediate then
    env.setState(saved)
    env.enableChanges(not wasLocked)
    lockTimer, restoring = nil, nil
  else
    blend(env, saved)
    restoring = { state = saved, wasLocked = wasLocked }
    lockTimer, lockAfter = LOCK_DELAY, wasLocked
  end
  forget()
end

function M.drop()
  surfaces.drop()
  rain.clear()
  if core_environment then
    if saved then
      core_environment.enableChanges(not wasLocked)
    elseif restoring then
      core_environment.enableChanges(not restoring.wasLocked)
    end
  end
  lockTimer, restoring = nil, nil
  forget()
end

M.BAD_WEATHER = { rain = true, storm = true, fog = true, snow = true }

function M.isBadWeather(key)
  return M.BAD_WEATHER[key] == true
end

function M.isNight()
  local env = core_environment
  if not env or not env.getLightState then return false end
  local light = env.getLightState()
  return light ~= nil and light.isNight == true
end

return M
