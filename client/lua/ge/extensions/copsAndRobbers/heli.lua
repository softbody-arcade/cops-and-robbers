local shelter = require("copsAndRobbers/shelter")

local M = {}

M.COVER_INTERVAL = 0.25
M.COVER_HEIGHT = 1.5
M.LIGHT_HEIGHT = 40
M.LIGHT_NAME = "cnr_heli_light"
M.HOVER_DRIFT = 2
M.BRIGHTNESS = 80
M.AIM_LAG = 0.08
M.AIM_SPRING = 6
M.AIM_DAMPING = 4.5
M.AIM_MAX_OFFSET = 6
M.NUDGE_RADIUS = 1.0
M.NUDGE_MIN = 1.5
M.NUDGE_MAX = 3.0
M.APPROACH_DISTANCE = 300
M.APPROACH_HEIGHT = 60
M.APPROACH_SECONDS = 8
M.AIM_SWEEP_OFFSET = 15
M.DEPART_SECONDS = 8
M.DEPART_FADE_SECONDS = 3
M.DEPART_AIM_DRIFT = 60
M.FADE_SECONDS = 1.5
M.FADEIN_SECONDS = 1
M.REFOUND_AIM_OFFSET = 8
M.JUMP_METERS = 30
M.MAX_STEP = 0.1
M.LEFTOVER_INTERVAL = 1

local FIELDS = {
  { "brightness", M.BRIGHTNESS }, { "range", 120 }, { "innerAngle", 8 }, { "outerAngle", 16 },
  { "color", "0.85 0.92 1 1" }, { "castShadows", "true" },
}

function M.new()
  return { phase = nil, reason = nil, endsAt = nil, cover = shelter.new(), sent = false, lastCheck = nil }
end

function M.set(state, d, clock)
  state.failed = nil
  if type(d) ~= "table" or type(d.phase) ~= "string" then
    state.phase, state.reason, state.endsAt = nil, nil, nil
    return
  end
  local seconds = tonumber(d.seconds)
  state.phase, state.reason = d.phase, d.reason
  state.endsAt = seconds and clock + seconds or nil
end

function M.tracking(state)
  return state.phase == "tracking"
end

function M.resetCover(state)
  state.cover, state.sent, state.lastCheck = shelter.new(), false, nil
end

function M.coverTick(state, clock, obj, castUp)
  if state.lastCheck and clock - state.lastCheck < M.COVER_INTERVAL then return nil end
  state.lastCheck = clock
  local p = obj:getPosition()
  local roofed = shelter.roofed(vec3(p.x, p.y, p.z + M.COVER_HEIGHT), castUp) and true or false
  if not state.sent then
    state.sent = true
    state.cover = { covered = roofed, pending = nil, count = 0 }
    return roofed
  end
  if shelter.step(state.cover, roofed) then return state.cover.covered end
  return nil
end

local function removeLight(state)
  local obj = scenetree.findObject(M.LIGHT_NAME)
  if obj then obj:delete() end
  state.light, state.aim, state.fx = nil, nil, nil
end

function M.newAim()
  return { offset = { x = 0, y = 0 }, vel = { x = 0, y = 0 }, goal = { x = 0, y = 0 }, nextNudge = nil, lastCar = nil, lastCarVel = { x = 0, y = 0 }, velKnown = false }
end

function M.lightPose(carPos, t)
  return vec3(carPos.x + M.HOVER_DRIFT * math.sin(0.7 * t), carPos.y + M.HOVER_DRIFT * math.cos(0.48 * t), carPos.z + M.LIGHT_HEIGHT)
end

local function pickGoal(aim, clock, random)
  local angle = random() * 2 * math.pi
  local radius = M.NUDGE_RADIUS * math.sqrt(random())
  aim.goal.x, aim.goal.y = radius * math.cos(angle), radius * math.sin(angle)
  aim.nextNudge = clock + M.NUDGE_MIN + random() * (M.NUDGE_MAX - M.NUDGE_MIN)
end

function M.aimStep(aim, carPos, dt, clock, random)
  random = random or math.random
  dt = math.max(0, math.min(dt, M.MAX_STEP))
  local last = aim.lastCar
  local cap = math.max(M.AIM_MAX_OFFSET, math.sqrt(aim.offset.x ^ 2 + aim.offset.y ^ 2))
  if last and (carPos.x - last.x) ^ 2 + (carPos.y - last.y) ^ 2 > M.JUMP_METERS ^ 2 then
    aim.offset.x, aim.offset.y, aim.vel.x, aim.vel.y = 0, 0, 0, 0
    aim.lastCarVel.x, aim.lastCarVel.y = 0, 0
    aim.velKnown = false
    last = nil
  end
  if last and dt > 0 then
    local vx, vy = (carPos.x - last.x) / dt, (carPos.y - last.y) / dt
    if aim.velKnown then
      aim.offset.x = aim.offset.x - (vx - aim.lastCarVel.x) * M.AIM_LAG
      aim.offset.y = aim.offset.y - (vy - aim.lastCarVel.y) * M.AIM_LAG
    end
    aim.velKnown = true
    aim.lastCarVel.x, aim.lastCarVel.y = vx, vy
  end
  aim.lastCar = { x = carPos.x, y = carPos.y }
  if not aim.nextNudge or clock >= aim.nextNudge then pickGoal(aim, clock, random) end
  local o, v, g = aim.offset, aim.vel, aim.goal
  v.x = v.x + (M.AIM_SPRING * (g.x - o.x) - M.AIM_DAMPING * v.x) * dt
  v.y = v.y + (M.AIM_SPRING * (g.y - o.y) - M.AIM_DAMPING * v.y) * dt
  o.x, o.y = o.x + v.x * dt, o.y + v.y * dt
  local len = math.sqrt(o.x * o.x + o.y * o.y)
  if len > cap then o.x, o.y = o.x * cap / len, o.y * cap / len end
  local tx = 0.08 * math.sin(9 * clock) + 0.04 * math.sin(14 * clock)
  local ty = 0.08 * math.cos(8 * clock) + 0.04 * math.cos(13 * clock)
  return vec3(carPos.x + o.x + tx, carPos.y + o.y + ty, carPos.z)
end

local function aimLight(obj, lightPos, aimPos)
  if not quatFromDir then return end
  local q = quatFromDir(vec3(aimPos.x - lightPos.x, aimPos.y - lightPos.y, aimPos.z - lightPos.z), vec3(0, 0, 1))
  if q.toTorqueQuat then q = q:toTorqueQuat() end
  obj:setField("rotation", 0, q.x .. " " .. q.y .. " " .. q.z .. " " .. q.w)
end

local function createLight(state)
  local obj = createObject("SpotLight")
  if not obj then return false end
  for _, f in ipairs(FIELDS) do obj:setField(f[1], 0, tostring(f[2])) end
  obj.canSave = false
  obj:registerObject(M.LIGHT_NAME)
  if not scenetree.findObject(M.LIGHT_NAME) then
    obj:delete()
    log("E", "cnr_heli", "searchlight did not register")
    return false
  end
  scenetree.MissionGroup:addObject(obj)
  state.light = obj
  state.aim = M.newAim()
  state.fx = { mode = "hover", t0 = 0 }
  return true
end

local function applyBrightness(obj, value)
  obj:setField("brightness", 0, value)
end

local function setBrightness(state, factor)
  pcall(applyBrightness, state.light, tostring(M.BRIGHTNESS * math.max(0, math.min(1, factor))))
end

local function offsetFrom(p, car)
  return p and { x = p.x - car.x, y = p.y - car.y, z = p.z - car.z } or nil
end

local function randomDir(random)
  local h = random() * 2 * math.pi
  return math.cos(h), math.sin(h)
end

local function offsetAim(state, dist, random)
  local dx, dy = randomDir(random)
  local aim = state.aim
  aim.offset.x, aim.offset.y, aim.vel.x, aim.vel.y = dx * dist, dy * dist, 0, 0
end

local function toMode(state, mode, clock)
  local fx = state.fx
  fx.mode, fx.t0 = mode, clock
end

local function startApproach(state, car, clock, random)
  local fresh = not state.light
  if fresh and not createLight(state) then error("no light") end
  local fx = state.fx
  if fresh or not fx.pos then
    local dx, dy = randomDir(random)
    fx.startOff = { x = dx * M.APPROACH_DISTANCE, y = dy * M.APPROACH_DISTANCE, z = M.APPROACH_HEIGHT }
    fx.fromBright = 1
    offsetAim(state, M.AIM_SWEEP_OFFSET, random)
  else
    fx.startOff = offsetFrom(fx.pos, car)
    fx.fromBright = fx.bright or 1
  end
  toMode(state, "approach", clock)
end

local function startRefound(state, clock, random)
  if not state.light and not createLight(state) then error("no light") end
  offsetAim(state, M.REFOUND_AIM_OFFSET, random)
  toMode(state, "hover", clock)
  state.fx.dirty = true
end

local function startFadeIn(state, car, clock)
  local fx = state.fx
  fx.startOff = offsetFrom(fx.pos, car)
  fx.fromBright = fx.bright or 0
  toMode(state, "fadein", clock)
end

local function startDepart(state, car, clock, random)
  local dx, dy = randomDir(random)
  local fx = state.fx
  fx.dir = { x = dx, y = dy }
  fx.startOff = offsetFrom(fx.pos, car)
  fx.fromBright = fx.bright or 1
  toMode(state, "depart", clock)
end

local function startFade(state, clock)
  local fx = state.fx
  fx.hold = fx.pos and { x = fx.pos.x, y = fx.pos.y, z = fx.pos.z } or nil
  fx.fromBright = fx.bright or 1
  toMode(state, "fade", clock)
end

local function glide(car, hover, s, e)
  return vec3(
    car.x + s.x + (hover.x - car.x - s.x) * e,
    car.y + s.y + (hover.y - car.y - s.y) * e,
    car.z + s.z + (hover.z - car.z - s.z) * e)
end

local function advance(state, car, clock)
  local fx = state.fx
  local hover = M.lightPose(car, clock)
  local light, bright, extra = hover, 1, nil
  local elapsed = clock - fx.t0
  if fx.mode == "approach" then
    local p = math.min(1, elapsed / M.APPROACH_SECONDS)
    light = glide(car, hover, fx.startOff, 1 - (1 - p) ^ 2)
    bright = fx.fromBright + (1 - fx.fromBright) * p
    if p >= 1 then
      fx.mode = "hover"
      fx.dirty = true
    end
  elseif fx.mode == "depart" then
    local p = math.min(1, elapsed / M.DEPART_SECONDS)
    local e = p * p
    local d = fx.dir
    local s = fx.startOff or offsetFrom(hover, car)
    light = vec3(
      car.x + s.x + d.x * M.APPROACH_DISTANCE * e,
      car.y + s.y + d.y * M.APPROACH_DISTANCE * e,
      car.z + s.z + (M.APPROACH_HEIGHT - s.z) * e)
    bright = fx.fromBright * (M.DEPART_SECONDS - elapsed) / M.DEPART_FADE_SECONDS
    extra = { x = d.x * M.DEPART_AIM_DRIFT * e, y = d.y * M.DEPART_AIM_DRIFT * e }
    if p >= 1 then return false end
  elseif fx.mode == "fade" then
    light = fx.hold or hover
    bright = fx.fromBright * (1 - elapsed / M.FADE_SECONDS)
    if elapsed >= M.FADE_SECONDS then return false end
  elseif fx.mode == "fadein" then
    local p = math.min(1, elapsed / M.FADEIN_SECONDS)
    if fx.startOff then light = glide(car, hover, fx.startOff, 1 - (1 - p) ^ 2) end
    bright = fx.fromBright + (1 - fx.fromBright) * p
    if p >= 1 then
      fx.mode = "hover"
      fx.dirty = true
    end
  end
  fx.bright = math.max(0, math.min(1, bright))
  if fx.mode ~= "hover" then
    setBrightness(state, fx.bright)
  elseif fx.dirty then
    fx.dirty = nil
    setBrightness(state, 1)
  end
  fx.pos = light
  local aim = state.aim
  local aimPos = M.aimStep(aim, car, aim.lastClock and clock - aim.lastClock or 0, clock, state.random)
  aim.lastClock = clock
  if extra then aimPos = vec3(aimPos.x + extra.x, aimPos.y + extra.y, aimPos.z) end
  state.light:setPosition(light)
  pcall(aimLight, state.light, light, aimPos)
  return true
end

local function leftover(state, clock)
  if state.light then return true end
  local at = state.leftoverAt
  if at and clock >= at and clock - at < M.LEFTOVER_INTERVAL then return false end
  state.leftoverAt = clock
  return scenetree.findObject(M.LIGHT_NAME) ~= nil
end

local function tickLight(state, target, night, clock)
  local random = state.random or math.random
  if state.light and not scenetree.findObject(M.LIGHT_NAME) then
    state.light, state.aim, state.fx = nil, nil, nil
  end
  if not target then
    if leftover(state, clock) then removeLight(state) end
    return
  end
  local phase, last = state.phase, state.lightPhase
  state.lightPhase = phase
  local car = target:getPosition()
  local desired = phase == "tracking" and night
  if phase ~= last then
    if phase == "tracking" then
      if desired and (last == "arriving" or last == "refuelling") then
        startApproach(state, car, clock, random)
      elseif desired and last == "searching" then
        startRefound(state, clock, random)
      end
    elseif state.light then
      if phase == "refuelling" and last == "tracking" and state.fx.mode ~= "fade" then
        startDepart(state, car, clock, random)
      elseif not (state.fx.mode == "depart" and phase == "refuelling") then
        removeLight(state)
      end
    end
  end
  if state.light and not night and state.fx.mode ~= "fade" then startFade(state, clock) end
  if desired then
    if not state.light then
      if not createLight(state) then error("no light") end
    elseif state.fx.mode == "fade" or state.fx.mode == "depart" then
      startFadeIn(state, car, clock)
    end
  end
  if state.light and not advance(state, car, clock) then removeLight(state) end
end

function M.lightTick(state, target, night, clock)
  clock = clock or 0
  if state.failed then
    if leftover(state, clock) then pcall(removeLight, state) end
    return
  end
  local ok = pcall(tickLight, state, target, night, clock)
  if not ok then
    pcall(removeLight, state)
    state.failed = true
  end
end

function M.wantsNight(state)
  return state.phase == "tracking" or state.light ~= nil
end

function M.clear(state)
  pcall(removeLight, state)
  state.phase, state.reason, state.endsAt, state.failed, state.lightPhase = nil, nil, nil, nil, nil
  M.resetCover(state)
end

return M
