local wind = require("copsAndRobbers/wind")
local surfaces = require("copsAndRobbers/surfaces")
local rain = require("copsAndRobbers/rain")
local skyChanges = require("copsAndRobbers/skyChanges")
local strikeClock = require("copsAndRobbers/strikeClock")
local units = require("copsAndRobbers/units")

local M = {}

M.WEATHER = {
  clear = { cloudCover = 0.4, fogDensity = 0.4, windSpeed = 0.1 },
  cloudy = { cloudCover = 1.8, fogDensity = 1, windSpeed = 0.3 },
  rain = {
    cloudCover = 2.2, fogDensity = 2, windSpeed = 0.5,
    precipitation = { dataBlock = "rain_medium", numDrops = 1500, dropSize = 1, minSpeed = 0.4, maxSpeed = 0.5, volume = 1.0 },
  },
  storm = {
    cloudCover = 3.0, fogDensity = 4, windSpeed = 1.5,
    precipitation = { dataBlock = "rain_medium", numDrops = 3000, dropSize = 1, minSpeed = 0.4, maxSpeed = 0.5, volume = 2.0 },
  },
  fog = { cloudCover = 1.5, fogDensity = 15, windSpeed = 0.1 },
  snow = {
    cloudCover = 2.2, fogDensity = 5, windSpeed = 0.4,
    precipitation = { dataBlock = "Snow_menu", numDrops = 5000, dropSize = 0.2, minSpeed = 0.1, maxSpeed = 0.3 },
  },
}
M.WEATHER.thunderstorm = M.WEATHER.storm

M.BLEND_SECONDS = 3
M.STEP_SECONDS = 0.5
M.START_LEAD = 1 / 24
M.LEAD_SECONDS = 75
local LOCK_DELAY = M.BLEND_SECONDS + 0.5
local WIND_INTERVAL = 0.25
local EPSILON = 1e-6
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local saved, wasLocked, round, clockStart, target
local syncedStrikes
local stormSpans, frameLo, frameHi, frameCovered, frameStorm
local weatherFrom, weatherTo, weatherProgress
local lockTimer, lockAfter, restoring
local roundTime, started, sinceWind = 0, false, 0
local sinceStep, wrote, curveIndex, rainIndex, seenIndex, windOn, failed = 0, nil, nil, 0, 0, false, {}

local function forget()
  wind.reset()
  stormSpans, frameLo, syncedStrikes = nil, nil, nil
  weatherFrom, weatherTo, weatherProgress = nil, nil, nil
  saved, wasLocked, round, clockStart, target = nil, false, nil, nil, nil
  roundTime, started, sinceWind = 0, false, 0
  sinceStep, wrote, curveIndex, rainIndex, seenIndex, windOn, failed = 0, nil, nil, 0, 0, false, {}
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

local function between(from, to, k)
  local a, b = M.WEATHER[from], M.WEATHER[to]
  if not (a and b) then return nil end
  local j = 1 - k
  return a.cloudCover * j + b.cloudCover * k, a.fogDensity * j + b.fogDensity * k, a.windSpeed * j + b.windSpeed * k
end

local function precipitation(weather)
  local spec = M.WEATHER[weather]
  return spec and spec.precipitation or nil
end

local function resumeRain(from, to, progress)
  if progress >= 1 then
    rain.target(precipitation(to), 0)
  else
    rain.resume(precipitation(from), precipitation(to), skyChanges.CHANGE_SECONDS, skyChanges.CHANGE_SECONDS * progress)
  end
end

local function windAt(p, t)
  if not p.driving then return 0, 0, 0, false end
  local from, to, progress = skyChanges.at(p, t)
  if not (wind.WEATHER[to] or (progress < 1 and wind.WEATHER[from])) then return 0, 0, 0, false end
  local k = skyChanges.smooth(progress)
  local j = 1 - k
  local ax, ay, az = wind.at(from, p.windSeed, p.windDir, t)
  local bx, by, bz = wind.at(to, p.windSeed, p.windDir, t)
  return ax * j + bx * k, ay * j + by * k, az * j + bz * k, true
end

local function turningRange(p)
  local temps = p.temps
  local a, b = temps and temps[1], temps and temps[2]
  if not (a and b and type(a.c) == "number" and type(b.c) == "number") then return nil end
  return math.min(a.c, b.c), math.max(a.c, b.c)
end

local function roundState(env, p, at)
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
    local t = env.getSolarTimeOfDayValue(p.time, solar) or env.timeOfDayKeyToTime[p.time]
    local daySeconds = tonumber(p.daySeconds) or 0
    if t and daySeconds > 0 then t = (t - math.min(M.START_LEAD, M.LEAD_SECONDS / daySeconds)) % 1 end
    state.time = t
  else
    state.time, state.dayLength = init.time, init.dayLength
  end
  local curve, index = skyChanges.curve(p, state.time, at)
  state.temperatureCurveOverrideC = curve or false
  state.numOfDrops = init.numOfDrops
  local from, to, progress = skyChanges.at(p, at)
  local cloudCover, fogDensity, windSpeed = between(from, to, skyChanges.smooth(progress))
  if not cloudCover then
    local weather = M.WEATHER[to] or init
    cloudCover, fogDensity, windSpeed = weather.cloudCover, weather.fogDensity, weather.windSpeed
  end
  state.cloudCover, state.fogDensity, state.windSpeed = cloudCover, fogDensity, windSpeed
  local x, y, z = windAt(p, at)
  state.groundWind = vec3(x, y, z)
  return state, index
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
    local low, high = turningRange(p)
    if low then
      local unit = units.temperatureUnit()
      parts[#parts + 1] = string.format("%d to %d %s", units.temperature(low, unit), units.temperature(high, unit), unit == "f" and "°F" or "°C")
    end
  end
  return table.concat(parts, " · ")
end

function M.prepLabel(p)
  local label = M.label(p, true)
  local forecast = p and skyChanges.prepForecast(p)
  if label and forecast then return label .. " · " .. forecast end
  return label or forecast
end

local function fail(part, err)
  failed[part] = true
  log("E", "cnr_sky", part .. ": " .. tostring(err))
end

local function failGrip(err)
  fail("grip", err)
  pcall(surfaces.restore)
end

local function thunderstormSpans(p)
  local seed = p.lightningSeed
  if type(seed) ~= "number" or seed < 1 or seed > 2147483646 or seed ~= math.floor(seed) then return end
  local spans = {}
  local changes = p.changes or {}
  local from = p.weather
  if from == "thunderstorm" then
    spans[#spans + 1] = {0, changes[1] and changes[1].at or math.huge}
  end
  for i, change in ipairs(changes) do
    local finish = changes[i + 1] and changes[i + 1].at or math.huge
    if change.to == "thunderstorm" then
      spans[#spans + 1] = {change.at, finish}
    elseif from == "thunderstorm" then
      spans[#spans + 1] = {change.at, math.min(change.at + skyChanges.CHANGE_SECONDS, finish)}
    end
    from = change.to
  end
  return spans
end

local function intersectsStorm(lo, hi)
  if hi > lo then
    for _, span in ipairs(stormSpans) do
      if hi >= span[1] and lo < span[2] and span[1] < span[2] then return true end
    end
  end
  return false
end

local function runningDay(state, start, daySeconds, at)
  if start and daySeconds and daySeconds > 0 then
    state.time = (start + at / daySeconds) % 1
    state.play, state.dayLength = true, daySeconds
    return state
  end
end

function M.apply(p, prep)
  frameLo = nil
  if prep then started = false end
  if not setsSomething(p) then
    if round then M.restore(true) end
    return
  end
  local env = core_environment
  if not env then return end
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
  local newRound = round == nil
  local at = started and roundTime or tonumber(p.clockSeconds) or 0
  local state, curveNow = roundState(env, p, at)
  local from, to, progress, index = skyChanges.at(p, at)
  weatherFrom, weatherTo, weatherProgress = from, to, progress
  round, clockStart, target = p, state.time, state
  stormSpans, roundTime = thunderstormSpans(p), at
  if p.lightningClockSync and stormSpans and #stormSpans > 0 then
    if prep or not syncedStrikes or syncedStrikes.seed ~= p.lightningSeed then
      syncedStrikes = strikeClock.new(p.lightningSeed)
    end
  else
    syncedStrikes = nil
  end
  if started then runningDay(state, clockStart, p.daySeconds, at) end
  wrote, curveIndex = { state.cloudCover, state.fogDensity, state.windSpeed }, curveNow
  rainIndex, seenIndex, sinceStep = index, index, 0
  env.enableChanges(true)
  local ok, err = pcall(function()
    blend(env, state)
    if newRound then rain.resetRoof() end
    if index > 0 and progress < 1 then
      resumeRain(from, to, progress)
    else
      rain.target(precipitation(to), M.BLEND_SECONDS)
    end
  end)
  if ok then
    local gripOk, gripErr = pcall(function()
      if p.driving then
        surfaces.blend(skyChanges.grip(p, at))
      else
        surfaces.apply(nil)
      end
    end)
    if not gripOk then failGrip(gripErr) end
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
  if not started then roundTime = clockSeconds or 0 end
  started = true
  local landing = lockTimer ~= nil
  if landing then
    env.enableChanges(true)
    env.setState(target)
  end
  local day = runningDay({}, clockStart, round.daySeconds, roundTime)
  if day then
    env.enableChanges(true)
    env.setState(day)
    env.enableChanges(false)
  elseif landing then
    env.enableChanges(false)
  end
  lockTimer, restoring = nil, nil
end

local function lockedWrite(state)
  local env = core_environment
  local ok, err = pcall(function()
    env.enableChanges(true)
    env.setState(state)
  end)
  pcall(env.enableChanges, false)
  return ok, err
end

local function stepClouds(from, to, progress)
  local cloudCover, fogDensity, windSpeed = between(from, to, skyChanges.smooth(progress))
  if not cloudCover then return end
  if wrote and cloudCover == wrote[1] and fogDensity == wrote[2] and windSpeed == wrote[3] then return end
  local ok, err = lockedWrite({ cloudCover = cloudCover, fogDensity = fogDensity, windSpeed = windSpeed })
  if ok then
    wrote = { cloudCover, fogDensity, windSpeed }
  else
    fail("clouds", err)
  end
end

local function stepCurve()
  local curve, index = skyChanges.curve(round, clockStart, roundTime)
  if not curve or index == curveIndex then return end
  curveIndex = index
  local ok, err = lockedWrite({ temperatureCurveOverrideC = curve })
  if not ok then fail("curve", err) end
end

local function stepRain(from, to, progress, index)
  if index == rainIndex then return end
  rainIndex = index
  local ok, err = pcall(resumeRain, from, to, progress)
  if not ok then
    pcall(rain.clear)
    fail("rain", err)
  end
end

local function stepGrip()
  local ok, err = pcall(function() surfaces.blend(skyChanges.grip(round, roundTime)) end)
  if not ok then failGrip(err) end
end

local function step()
  local from, to, progress, index = skyChanges.at(round, roundTime)
  weatherFrom, weatherTo, weatherProgress = from, to, progress
  if not failed.clouds then stepClouds(from, to, progress) end
  if not failed.curve then stepCurve() end
  if not failed.rain then stepRain(from, to, progress, index) end
  if round.driving and not failed.grip then stepGrip() end
end

local function newChange()
  local upcoming = round.changes and round.changes[seenIndex + 1]
  if not upcoming or upcoming.at > roundTime then return nil end
  local from, to, _, index = skyChanges.at(round, roundTime)
  seenIndex = index
  return { from = from, to = to, notice = skyChanges.notice(from, to) }
end

local function pushWind(dt)
  if not round.driving then return end
  sinceWind = sinceWind + dt
  if sinceWind < WIND_INTERVAL then return end
  sinceWind = 0
  local x, y, z, active = windAt(round, roundTime)
  if not (active or windOn) then return end
  windOn = active
  be:queueAllObjectLua(string.format("obj:setWind(%f,%f,%f)", x, y, z))
  be:setGroundWind(vec3(x, y, z))
end

function M.syncLightningClock(reply)
  if started then strikeClock.receive(syncedStrikes, reply) end
end

function M.lightningFrame()
  if frameLo then return round, frameLo, frameHi, frameCovered, frameStorm end
end

function M.update(dt, hasVisualTail)
  frameLo = nil
  if core_environment and started then
    local lo = roundTime
    roundTime = roundTime + dt
    if stormSpans then
      if syncedStrikes then
        frameLo, frameHi = strikeClock.frame(syncedStrikes)
      else
        frameLo, frameHi = lo, roundTime
      end
      frameStorm = frameLo ~= nil and intersectsStorm(frameLo, frameHi)
    end
  end
  local ok, err = pcall(rain.update, dt, frameLo ~= nil and (frameStorm or hasVisualTail))
  if not ok then
    rain.clear()
    log("E", "cnr_sky", tostring(err))
  end
  frameCovered = rain.covered()
  if not core_environment then return nil end
  if lockTimer then
    lockTimer = lockTimer - dt
    if lockTimer <= 0 then
      core_environment.enableChanges(not lockAfter)
      lockTimer, restoring = nil, nil
    end
  end
  if not round then return nil end
  local change
  if started then
    change = newChange()
    sinceStep = sinceStep + dt
    if sinceStep >= M.STEP_SECONDS - EPSILON and not lockTimer and (round.changes or round.temps) then
      sinceStep = 0
      step()
    end
  end
  pushWind(dt)
  return change
end

function M.weather()
  if weatherProgress and weatherProgress < 1 and M.isBadWeather(weatherFrom) and not M.isBadWeather(weatherTo) then
    return weatherFrom
  end
  return weatherTo
end

function M.weatherBlend()
  return weatherFrom, weatherTo, weatherProgress and skyChanges.smooth(weatherProgress)
end

function M.forecast(heliOn)
  if not (round and started) then return nil end
  return skyChanges.forecast(round, roundTime, heliOn)
end

function M.restore(immediate)
  started, frameLo = false, nil
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
  local restored, restoreErr = pcall(surfaces.restore)
  if not restored and not failed.grip then
    failed.grip = true
    log("E", "cnr_sky", "grip: " .. tostring(restoreErr))
  end
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

M.BAD_WEATHER = { rain = true, storm = true, thunderstorm = true, fog = true, snow = true }

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
