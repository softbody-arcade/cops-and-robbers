local shelter = require("copsAndRobbers/shelter")

local M = {}

M.NAME = "cnr_precipitation"
M.SOUND = "cnr_rain_sound"
M.FADE_INTERVAL = 0.1
local COVER_INTERVAL = 0.25
local EPSILON = 1e-6

local cur, goal, rateOut, rateIn = nil, nil, 0, 0
local sinceWrite, sinceCover = 0, 0
local cover = shelter.new()

local function castUp(pos, range)
  return castRayStatic(pos, vec3(0, 0, 1), range)
end

local function setHidden(obj, hide)
  if obj.setHidden then obj:setHidden(hide) else obj:setField("hidden", 0, hide and "1" or "0") end
end

local function setSpecFields(obj, spec)
  local fields = {
    { "dropSize", spec.dropSize }, { "minSpeed", spec.minSpeed }, { "maxSpeed", spec.maxSpeed },
    { "boxWidth", 40 }, { "boxHeight", 20 }, { "useWind", 1 }, { "splashSize", 0.25 },
  }
  for _, field in ipairs(fields) do obj:setField(field[1], 0, tostring(field[2])) end
end

local function removeNamed(name)
  local obj = scenetree.findObject(name)
  if obj then obj:delete() end
end

local function removeAll()
  removeNamed(M.NAME)
  removeNamed(M.SOUND)
  cur = nil
end

local function baseVolume()
  local spec, ramp = cur.spec, cur.ramp
  if ramp then
    local share = 1
    if ramp.d1 ~= ramp.d0 then share = math.max(0, math.min(1, (cur.drops - ramp.d0) / (ramp.d1 - ramp.d0))) end
    return ramp.v0 + ((ramp.v1 or spec.volume) - ramp.v0) * share
  end
  return spec.volume * cur.drops / spec.numDrops
end

local function fadeRamp()
  if cur.spec.volume then cur.ramp = { v0 = baseVolume(), d0 = cur.drops, d1 = 0, v1 = 0 } end
end

local function volumeOf()
  local volume = baseVolume()
  if cover.covered then volume = volume / 2 end
  return volume
end

local function writeDrops()
  sinceWrite = 0
  local count = math.floor(cur.drops + EPSILON)
  local volume = cur.spec.volume and volumeOf() or nil
  if count == cur.wroteDrops and volume == cur.wroteVolume then return end
  cur.wroteDrops, cur.wroteVolume = count, volume
  local obj = scenetree.findObject(M.NAME)
  if obj then obj.numDrops = count end
  local snd = scenetree.findObject(M.SOUND)
  if snd and volume then snd:setVolumePitchCT(volume, 1, 0, 0) end
end

local function createSound()
  local snd = createObject("SFXEmitter")
  if Sim and Sim.upcast then snd = Sim.upcast(snd) end
  snd:setField("track", 0, "amb_rain_medium")
  if MatrixF then snd:setTransform(MatrixF(true)) end
  snd.canSave = false
  snd:registerObject(M.SOUND)
  if not scenetree.findObject(M.SOUND) then
    snd:delete()
    log("E", "cnr_sky", "rain sound did not register")
    return
  end
  scenetree.MissionGroup:addObject(snd)
  snd:setVolumePitchCT(0, 1, 0, 0)
  snd:play()
end

local function create(spec)
  local obj = createObject("Precipitation")
  obj:setField("dataBlock", 0, spec.dataBlock)
  obj:setField("numDrops", 0, "0")
  setSpecFields(obj, spec)
  obj.canSave = false
  obj:registerObject(M.NAME)
  if not scenetree.findObject(M.NAME) then
    obj:delete()
    log("E", "cnr_sky", "precipitation object did not register")
    return false
  end
  scenetree.MissionGroup:addObject(obj)
  if cover.covered then setHidden(obj, true) end
  cur = { spec = spec, drops = 0 }
  if spec.volume then createSound() end
  return true
end

local function sameKind()
  return cur ~= nil and goal ~= nil and cur.spec.dataBlock == goal.dataBlock
end

function M.active()
  return cur ~= nil or goal ~= nil
end

function M.clear()
  removeAll()
  goal = nil
  cover, sinceCover, sinceWrite = shelter.new(), 0, 0
end

function M.resetRoof()
  cover, sinceCover = shelter.new(), 0
  if not cur then return end
  cur.wroteDrops, cur.wroteVolume = nil, nil
  local obj = scenetree.findObject(M.NAME)
  if obj then setHidden(obj, false) end
end

function M.target(spec, seconds)
  if not M.active() then cover, sinceCover = shelter.new(), 0 end
  goal = spec
  if seconds <= 0 then
    if cur and not sameKind() then removeAll() end
    if spec then
      if not cur then create(spec) end
      if cur then
        cur.spec, cur.ramp, cur.fieldsIn = spec, nil, nil
        cur.drops = spec.numDrops
        local obj = scenetree.findObject(M.NAME)
        if obj then setSpecFields(obj, spec) end
        writeDrops()
      end
    end
    return
  end
  if not spec then
    if cur then
      rateOut = cur.drops / seconds
      fadeRamp()
    end
  elseif sameKind() then
    cur.fieldsIn = seconds / 2
    local ramp = nil
    if spec.volume and spec.numDrops ~= cur.drops then ramp = { v0 = baseVolume(), d0 = cur.drops, d1 = spec.numDrops } end
    cur.ramp = ramp
    cur.spec = spec
    rateIn = math.max(1, math.abs(spec.numDrops - cur.drops)) / seconds
  elseif cur then
    rateOut = cur.drops / (seconds / 2)
    fadeRamp()
    rateIn = spec.numDrops / (seconds / 2)
  else
    rateIn = spec.numDrops / seconds
  end
end

local function updateCover(dt)
  sinceCover = sinceCover + dt
  if sinceCover < COVER_INTERVAL then return false end
  sinceCover = 0
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  if not cam or not castRayStatic then return false end
  if not shelter.step(cover, shelter.roofed(cam, castUp)) then return false end
  local obj = scenetree.findObject(M.NAME)
  if obj then setHidden(obj, cover.covered) end
  return true
end

local function switchFields(dt)
  cur.fieldsIn = cur.fieldsIn - dt
  if cur.fieldsIn > EPSILON then return end
  cur.fieldsIn = nil
  local obj = scenetree.findObject(M.NAME)
  if obj then setSpecFields(obj, cur.spec) end
end

function M.update(dt)
  sinceWrite = sinceWrite + dt
  if cur and cur.fieldsIn then switchFields(dt) end
  local reached = false
  if cur and not sameKind() then
    cur.drops = cur.drops - rateOut * dt
    if cur.drops <= EPSILON then
      removeAll()
      reached = true
    end
  end
  if goal and not cur and not create(goal) then goal = nil end
  if sameKind() and cur.drops ~= goal.numDrops then
    local diff = goal.numDrops - cur.drops
    local step = rateIn * dt
    if math.abs(diff) <= step + EPSILON then
      cur.drops, cur.ramp = goal.numDrops, nil
      reached = true
    else
      cur.drops = cur.drops + (diff > 0 and step or -step)
    end
  end
  local changed = cur and updateCover(dt)
  if cur and (changed or reached or sinceWrite >= M.FADE_INTERVAL - EPSILON) then writeDrops() end
end

return M
