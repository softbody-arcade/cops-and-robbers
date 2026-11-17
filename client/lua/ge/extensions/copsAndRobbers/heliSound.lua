local M = {}

M.NAME = "cnr_heli_sound"
M.FILE = "/art/sound/cnr/heli_rotor.ogg"
M.REF_DISTANCE = 40
M.MAX_DISTANCE = 800
M.FADE_IN_SECONDS = 1
M.FADE_OUT_SECONDS = 1
M.MUFFLED = 0.5
M.MUFFLE_SECONDS = 0.5
M.RAY_INTERVAL = 0.25
M.VOLUME_STEP = 0.02
M.LEFTOVER_INTERVAL = 1

local HIT_MARGIN = 2

local FIELDS = {
  { "fileName", M.FILE }, { "is3D", "1" }, { "isLooping", "1" },
  { "referenceDistance", tostring(M.REF_DISTANCE) }, { "maxDistance", tostring(M.MAX_DISTANCE) }, { "volume", "0" },
}

local function reset(s)
  s.vol, s.written, s.muffle, s.blocked, s.rayAt = 0, nil, 1, false, nil
  s.leftoverAt, s.lastPos, s.failed, s.logged, s.clock = nil, nil, nil, nil, nil
  return s
end

function M.new()
  return reset({})
end

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function usable(p)
  return p ~= nil and finite(p.x) and finite(p.y) and finite(p.z)
end

local function remove()
  local obj = scenetree.findObject(M.NAME)
  if obj then obj:delete() end
end

local function leftover(s, clock)
  local at = s.leftoverAt
  if at and clock >= at and clock - at < M.LEFTOVER_INTERVAL then return end
  s.leftoverAt = clock
  remove()
end

local function create(p)
  local obj = createObject("SFXEmitter")
  if Sim and Sim.upcast then obj = Sim.upcast(obj) end
  for _, f in ipairs(FIELDS) do obj:setField(f[1], 0, f[2]) end
  obj.canSave = false
  obj:registerObject(M.NAME)
  if not scenetree.findObject(M.NAME) then
    obj:delete()
    error("rotor sound did not register", 0)
  end
  scenetree.MissionGroup:addObject(obj)
  obj:setPosition(vec3(p.x, p.y, p.z))
  obj:play()
  return obj
end

local function blockedFrom(camPos, p, castRay)
  local dx, dy, dz = p.x - camPos.x, p.y - camPos.y, p.z - camPos.z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if not (dist > HIT_MARGIN) then return false end
  local hit = tonumber(castRay(camPos, vec3(dx / dist, dy / dist, dz / dist), dist))
  return hit ~= nil and hit < dist - HIT_MARGIN
end

local function muffleStep(s, p, clock, dt, camPos, castRay)
  if camPos and castRay then
    local at = s.rayAt
    if not at or clock < at or clock - at >= M.RAY_INTERVAL then
      s.rayAt = clock
      s.blocked = blockedFrom(camPos, p, castRay)
    end
  else
    s.rayAt, s.blocked = nil, false
  end
  local goal = s.blocked and M.MUFFLED or 1
  local step = (1 - M.MUFFLED) / M.MUFFLE_SECONDS * dt
  if s.muffle < goal then
    s.muffle = math.min(goal, s.muffle + step)
  else
    s.muffle = math.max(goal, s.muffle - step)
  end
end

local function ease(s, target, dt)
  if s.vol < target then
    s.vol = math.min(target, s.vol + dt / M.FADE_IN_SECONDS)
  elseif s.vol > target then
    s.vol = math.max(target, s.vol - dt / M.FADE_OUT_SECONDS)
  end
end

local function writeVolume(s, obj, target)
  local w = s.written
  if s.vol == w then return end
  local edge = s.vol <= 0 or s.vol == target
  if w and not edge and math.abs(s.vol - w) <= M.VOLUME_STEP then return end
  obj:setVolumePitchCT(s.vol, 1, 0, 0)
  s.written = s.vol
end

local function step(s, pos, level, clock, dt, camPos, castRay)
  local here = usable(pos)
  local wanted = here and type(level) == "number" and level > 0
  if here then s.lastPos = vec3(pos.x, pos.y, pos.z) end
  if not wanted and s.written == nil then
    leftover(s, clock)
    return
  end
  local p = s.lastPos
  local obj = scenetree.findObject(M.NAME)
  if obj then
    obj:setPosition(vec3(p.x, p.y, p.z))
  elseif wanted then
    s.vol, s.written = 0, 0
    obj = create(p)
  else
    s.vol, s.written = 0, nil
    return
  end
  local target = 0
  if wanted then
    muffleStep(s, p, clock, dt, camPos, castRay)
    target = level * s.muffle
  end
  ease(s, target, dt)
  writeVolume(s, obj, target)
  if not wanted and s.vol <= 0 then
    obj:delete()
    s.vol, s.written, s.muffle, s.blocked, s.rayAt = 0, nil, 1, false, nil
    s.leftoverAt = clock
  end
end

function M.tick(s, pos, level, clock, camPos, castRay)
  clock = clock or 0
  local dt = s.clock and math.max(0, clock - s.clock) or 0
  s.clock = clock
  if s.failed then
    pcall(leftover, s, clock)
    return
  end
  local ok, err = pcall(step, s, pos, level, clock, dt, camPos, castRay)
  if ok then return end
  pcall(remove)
  s.failed, s.vol, s.written = true, 0, nil
  if not s.logged then
    s.logged = true
    log("E", "cnr_heli", "helicopter sound stopped: " .. tostring(err))
  end
end

function M.clear(s)
  pcall(remove)
  reset(s)
end

return M
