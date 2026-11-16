local wind = require("copsAndRobbers/wind")
local surfaces = require("copsAndRobbers/surfaces")
local shelter = require("copsAndRobbers/shelter")

local M = {}

M.WEATHER = {
  clear = { cloudCover = 0.4, fogDensity = 0.4, windSpeed = 1 },
  cloudy = { cloudCover = 1.8, fogDensity = 1, windSpeed = 2 },
  rain = {
    cloudCover = 2.2, fogDensity = 4, windSpeed = 3, temperatureC = 8,
    precipitation = { dataBlock = "rain_medium", numDrops = 3000, dropSize = 1, minSpeed = 0.1, maxSpeed = 0.3 },
  },
  storm = {
    cloudCover = 3.0, fogDensity = 8, windSpeed = 8, temperatureC = 8,
    precipitation = { dataBlock = "rain_medium", numDrops = 6000, dropSize = 1, minSpeed = 0.1, maxSpeed = 0.3 },
  },
  fog = { cloudCover = 1.5, fogDensity = 15, windSpeed = 1, temperatureC = 5 },
  snow = {
    cloudCover = 2.2, fogDensity = 5, windSpeed = 2, temperatureC = -5,
    precipitation = { dataBlock = "Snow_menu", numDrops = 5000, dropSize = 0.2, minSpeed = 0.1, maxSpeed = 0.3 },
  },
}

local PRECIPITATION_NAME = "cnr_precipitation"
local WIND_INTERVAL = 0.25
local COVER_INTERVAL = 0.25
local SECONDS_PER_DAY = 86400

local saved, wasLocked, round, clockStart
local roundTime, started, sinceWind = 0, false, 0
local cover, sinceCover = shelter.new(), 0

local function forget()
  wind.reset()
  saved, wasLocked, round, clockStart = nil, false, nil, nil
  roundTime, started, sinceWind = 0, false, 0
  cover, sinceCover = shelter.new(), 0
end

local function capitalise(key)
  return key:sub(1, 1):upper() .. key:sub(2)
end

local function setsSomething(p)
  return p ~= nil and (p.time ~= nil or p.weather ~= nil or (p.clockSpeed or 0) > 0)
end

local function windy(p)
  return p.driving and wind.WEATHER[p.weather] ~= nil
end

local function precipitates(p)
  local weather = M.WEATHER[p.weather]
  return weather ~= nil and weather.precipitation ~= nil
end

local function castUp(pos, range)
  return castRayStatic(pos, vec3(0, 0, 1), range)
end

local function setHidden(obj, hide)
  if obj.setHidden then obj:setHidden(hide) else obj:setField("hidden", 0, hide and "1" or "0") end
end

local function updateCover(dt)
  sinceCover = sinceCover + dt
  if sinceCover < COVER_INTERVAL then return end
  sinceCover = 0
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  if not cam or not castRayStatic then return end
  if not shelter.step(cover, shelter.roofed(cam, castUp)) then return end
  local obj = scenetree.findObject(PRECIPITATION_NAME)
  if obj then setHidden(obj, cover.covered) end
end

local function removePrecipitation()
  local obj = scenetree.findObject(PRECIPITATION_NAME)
  if obj then obj:delete() end
end

local function createPrecipitation(spec)
  local obj = createObject("Precipitation")
  local fields = {
    { "dataBlock", spec.dataBlock }, { "numDrops", spec.numDrops }, { "dropSize", spec.dropSize },
    { "minSpeed", spec.minSpeed }, { "maxSpeed", spec.maxSpeed },
    { "boxWidth", 40 }, { "boxHeight", 20 }, { "useWind", 1 },
  }
  for _, field in ipairs(fields) do obj:setField(field[1], 0, tostring(field[2])) end
  obj.canSave = false
  obj:registerObject(PRECIPITATION_NAME)
  if scenetree.findObject(PRECIPITATION_NAME) then
    scenetree.MissionGroup:addObject(obj)
  else
    obj:delete()
    log("E", "cnr_sky", "precipitation object did not register")
  end
end

local function roundState(env, p)
  local init = env.getInitState() or {}
  local state = { play = false, temperatureCurveOverrideC = false }
  if p.time then
    state.time = env.getSolarTimeOfDayValue(p.time) or env.timeOfDayKeyToTime[p.time]
  else
    state.time, state.dayLength = init.time, init.dayLength
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

function M.label(p)
  if not p then return nil end
  local parts = {}
  if p.time then parts[#parts + 1] = capitalise(p.time) end
  if p.weather then parts[#parts + 1] = capitalise(p.weather) end
  if #parts == 0 then return nil end
  return table.concat(parts, " · ")
end

function M.apply(p)
  local env = core_environment
  if not env or not setsSomething(p) then return end
  if not saved then
    saved = env.getState() or {}
    local g = saved.groundWind
    if g then saved.groundWind = vec3(g.x, g.y, g.z) end
    wasLocked = not env.canChange()
  end
  local state = roundState(env, p)
  round, clockStart = p, state.time
  env.enableChanges(true)
  local ok, err = pcall(function()
    env.setState(state)
    local weather = M.WEATHER[p.weather]
    if weather and weather.temperatureC then
      env.setTemperatureProfile({ averageC = weather.temperatureC })
    end
    removePrecipitation()
    cover, sinceCover = shelter.new(), 0
    if weather and weather.precipitation then createPrecipitation(weather.precipitation) end
    surfaces.apply(p.driving and p.weather or nil)
  end)
  env.enableChanges(false)
  if not ok then log("E", "cnr_sky", tostring(err)) end
end

function M.startClock(clockSeconds)
  local env = core_environment
  if not env or not round then return end
  roundTime, started = clockSeconds or 0, true
  local speed = round.clockSpeed or 0
  if speed <= 0 or not clockStart then return end
  env.enableChanges(true)
  env.setState({
    time = (clockStart + roundTime * speed / SECONDS_PER_DAY) % 1,
    play = true,
    dayLength = SECONDS_PER_DAY / speed,
  })
  env.enableChanges(false)
end

function M.update(dt)
  if not core_environment or not round then return end
  if started then roundTime = roundTime + dt end
  if precipitates(round) then updateCover(dt) end
  if not windy(round) then return end
  sinceWind = sinceWind + dt
  if sinceWind < WIND_INTERVAL then return end
  sinceWind = 0
  local x, y, z = wind.at(round.weather, round.windSeed, round.windDir, roundTime)
  be:queueAllObjectLua(string.format("obj:setWind(%f,%f,%f)", x, y, z))
  be:setGroundWind(vec3(x, y, z))
end

function M.restore()
  local env = core_environment
  if not env or not saved then return end
  env.enableChanges(true)
  env.setState(saved)
  surfaces.restore()
  removePrecipitation()
  env.enableChanges(not wasLocked)
  forget()
end

function M.drop()
  surfaces.drop()
  if core_environment and saved then core_environment.enableChanges(not wasLocked) end
  forget()
end

function M.isNight()
  local env = core_environment
  if not env or not env.getLightState then return false end
  local light = env.getLightState()
  return light ~= nil and light.isNight == true
end

return M
