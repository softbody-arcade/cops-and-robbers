local shelter = require("copsAndRobbers/shelter")
local flight = require("copsAndRobbers/heliFlight")
local beam = require("copsAndRobbers/beam")

local M = {}

M.COVER_INTERVAL = 0.25
M.COVER_HEIGHT = 1.5
M.LIGHT_NAME = "cnr_heli_light"
M.BRIGHTNESS = 80
M.RANGE_MIN = 120
M.RANGE_MARGIN = 30
M.RANGE_MAX = 400
M.RANGE_STEP = 5
M.AIM_LAG = 0.08
M.AIM_SPRING = 6
M.AIM_DAMPING = 4.5
M.AIM_MAX_OFFSET = 6
M.NUDGE_RADIUS = 1.0
M.NUDGE_MIN = 1.5
M.NUDGE_MAX = 3.0
M.APPROACH_DISTANCE = flight.APPROACH_DISTANCE
M.APPROACH_HEIGHT = flight.APPROACH_HEIGHT
M.APPROACH_SECONDS = flight.APPROACH_SECONDS
M.AIM_SWEEP_OFFSET = 15
M.DEPART_SECONDS = flight.DEPART_SECONDS
M.DEPART_FADE_SECONDS = flight.DEPART_FADE_SECONDS
M.DEPART_AIM_DRIFT = 60
M.FADE_SECONDS = 1.5
M.FADEIN_SECONDS = 1
M.REFOUND_AIM_OFFSET = 8
M.JUMP_METERS = flight.JUMP_METERS
M.MAX_STEP = flight.MAX_STEP
M.LEFTOVER_INTERVAL = 1
M.FLARE_TYPE = "BNG_LightFlare_1"
M.FLARE_STEP = 0.05
M.HIT_MARGIN = 2

local FIELDS = {
  { "brightness", M.BRIGHTNESS }, { "range", M.RANGE_MIN }, { "innerAngle", 8 }, { "outerAngle", 16 },
  { "color", "0.85 0.92 1 1" }, { "castShadows", "true" },
}

function M.new()
  return { phase = nil, reason = nil, endsAt = nil, cover = shelter.new(), sent = false, lastCheck = nil, beamQuads = {} }
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
  state.seed = tonumber(d.seed)
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

local function forgetLight(state)
  state.light, state.aim, state.fx, state.lightPos, state.aimPos = nil, nil, nil, nil, nil
  state.beamHit, state.rayAt = nil, nil
end

local function removeLight(state)
  local obj = scenetree.findObject(M.LIGHT_NAME)
  if obj then obj:delete() end
  forgetLight(state)
end

function M.newAim()
  return { offset = { x = 0, y = 0 }, vel = { x = 0, y = 0 }, goal = { x = 0, y = 0 }, nextNudge = nil, lastCar = nil, lastRelVel = { x = 0, y = 0 }, velKnown = false }
end

local function pickGoal(aim, clock, random)
  local angle = random() * 2 * math.pi
  local radius = M.NUDGE_RADIUS * math.sqrt(random())
  aim.goal.x, aim.goal.y = radius * math.cos(angle), radius * math.sin(angle)
  aim.nextNudge = clock + M.NUDGE_MIN + random() * (M.NUDGE_MAX - M.NUDGE_MIN)
end

function M.aimStep(aim, carPos, dt, clock, random, heliVel)
  random = random or math.random
  dt = math.max(0, math.min(dt, M.MAX_STEP))
  local last = aim.lastCar
  local cap = math.max(M.AIM_MAX_OFFSET, math.sqrt(aim.offset.x ^ 2 + aim.offset.y ^ 2))
  if last and (carPos.x - last.x) ^ 2 + (carPos.y - last.y) ^ 2 > M.JUMP_METERS ^ 2 then
    aim.offset.x, aim.offset.y, aim.vel.x, aim.vel.y = 0, 0, 0, 0
    aim.lastRelVel.x, aim.lastRelVel.y = 0, 0
    aim.velKnown = false
    last = nil
  end
  if last and dt > 0 then
    local vx, vy = (carPos.x - last.x) / dt, (carPos.y - last.y) / dt
    if heliVel then vx, vy = vx - heliVel.x, vy - heliVel.y end
    if aim.velKnown then
      aim.offset.x = aim.offset.x - (vx - aim.lastRelVel.x) * M.AIM_LAG
      aim.offset.y = aim.offset.y - (vy - aim.lastRelVel.y) * M.AIM_LAG
    end
    aim.velKnown = true
    aim.lastRelVel.x, aim.lastRelVel.y = vx, vy
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

local function applyField(obj, name, value)
  obj:setField(name, 0, value)
end

local function createLight(state)
  local obj = createObject("SpotLight")
  if not obj then return false end
  for _, f in ipairs(FIELDS) do obj:setField(f[1], 0, tostring(f[2])) end
  pcall(applyField, obj, "flareType", M.FLARE_TYPE)
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
  state.lightRange, state.flareScale = nil, nil
  return true
end

local function setBrightness(state, factor)
  pcall(applyField, state.light, "brightness", tostring(M.BRIGHTNESS * math.max(0, math.min(1, factor))))
end

local function writeFlare(state, bright)
  local edge = bright >= 1 or bright <= 0
  if state.flareScale and math.abs(bright - state.flareScale) <= M.FLARE_STEP and not (edge and bright ~= state.flareScale) then return end
  if pcall(applyField, state.light, "flareScale", tostring(bright)) then state.flareScale = bright end
end

local function slantOf(lightPos, car)
  local dx, dy, dz = lightPos.x - car.x, lightPos.y - car.y, lightPos.z - car.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function writeRange(state, lightPos, car)
  local range = math.min(M.RANGE_MAX, math.floor(math.max(M.RANGE_MIN, slantOf(lightPos, car) + M.RANGE_MARGIN) + 0.5))
  if state.lightRange and math.abs(range - state.lightRange) <= M.RANGE_STEP then return end
  if pcall(applyField, state.light, "range", tostring(range)) then state.lightRange = range end
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
  if fx.mode == "depart" and fx.extra then
    local o = state.aim.offset
    o.x, o.y = o.x + fx.extra.x, o.y + fx.extra.y
  end
  fx.mode, fx.t0, fx.extra = mode, clock, nil
end

local function startApproach(state, clock, random)
  local fresh = not state.light
  if fresh and not createLight(state) then error("no light") end
  local fx = state.fx
  if fresh then
    fx.fromBright = 0
    offsetAim(state, M.AIM_SWEEP_OFFSET, random)
  else
    fx.fromBright = fx.bright or 1
  end
  toMode(state, "approach", clock)
end

local function startRefound(state, clock, random)
  if not state.light and not createLight(state) then error("no light") end
  toMode(state, "hover", clock)
  offsetAim(state, M.REFOUND_AIM_OFFSET, random)
  state.fx.dirty = true
end

local function startFadeIn(state, clock)
  local fx = state.fx
  fx.fromBright = fx.bright or 0
  toMode(state, "fadein", clock)
end

local function startDepart(state, car, clock)
  local fx, to = state.fx, state.flight.leaving
  local dx, dy = to.x - car.x, to.y - car.y
  local len = math.sqrt(dx * dx + dy * dy)
  fx.dir = { x = dx / len, y = dy / len }
  fx.fromBright = fx.bright or 1
  toMode(state, "depart", clock)
end

local function startFade(state, clock)
  local fx = state.fx
  fx.fromBright = fx.bright or 1
  toMode(state, "fade", clock)
end

local function advance(state, car, clock)
  local fx, f = state.fx, state.flight
  local bright, extra = 1, nil
  local elapsed = clock - fx.t0
  if fx.mode == "approach" then
    local p = math.min(1, elapsed / M.APPROACH_SECONDS)
    bright = fx.fromBright + (1 - fx.fromBright) * p
    if p >= 1 then
      fx.mode = "hover"
      fx.dirty = true
    end
  elseif fx.mode == "depart" then
    local p = math.min(1, elapsed / M.DEPART_SECONDS)
    local e = p * p
    local d = fx.dir
    bright = fx.fromBright * math.min(1, (M.DEPART_SECONDS - elapsed) / M.DEPART_FADE_SECONDS)
    extra = { x = d.x * M.DEPART_AIM_DRIFT * e, y = d.y * M.DEPART_AIM_DRIFT * e }
    fx.extra = extra
    if p >= 1 then return false end
  elseif fx.mode == "fade" then
    bright = fx.fromBright * (1 - elapsed / M.FADE_SECONDS)
    if elapsed >= M.FADE_SECONDS then return false end
  elseif fx.mode == "fadein" then
    local p = math.min(1, elapsed / M.FADEIN_SECONDS)
    bright = fx.fromBright + (1 - fx.fromBright) * p
    if p >= 1 then
      fx.mode = "hover"
      fx.dirty = true
    end
  end
  fx.bright = math.max(0, math.min(1, bright))
  writeFlare(state, fx.bright)
  if fx.mode ~= "hover" then
    setBrightness(state, fx.bright)
  elseif fx.dirty then
    fx.dirty = nil
    setBrightness(state, 1)
  end
  local light = f.pos
  local aim = state.aim
  local aimPos = M.aimStep(aim, car, aim.lastClock and clock - aim.lastClock or 0, clock, state.random, f.vel)
  aim.lastClock = clock
  if extra then aimPos = vec3(aimPos.x + extra.x, aimPos.y + extra.y, aimPos.z) end
  state.light:setPosition(light)
  writeRange(state, light, car)
  state.lightPos, state.aimPos = light, aimPos
  pcall(aimLight, state.light, light, aimPos)
  return true
end

local function carVelocity(state, target, car, dt)
  local last, kept = state.lastCar, state.carVel
  local jumped = last and (car.x - last.x) ^ 2 + (car.y - last.y) ^ 2 + (car.z - last.z) ^ 2 > M.JUMP_METERS ^ 2
  state.lastCar = vec3(car.x, car.y, car.z)
  if kept and (dt <= 0 or jumped) then return kept end
  local v
  if target.getVelocity then
    local tv = target:getVelocity()
    if tv then v = vec3(tv.x, tv.y, tv.z) end
  end
  if not v and last and dt > 0 then
    v = vec3((car.x - last.x) / dt, (car.y - last.y) / dt, (car.z - last.z) / dt)
  end
  v = v or vec3(0, 0, 0)
  state.carVel = v
  return v
end

local function dropFlight(state)
  if state.light then removeLight(state) end
  state.flight, state.leftAt, state.flightRandom = nil, nil, nil
end

local function fly(state, phase, last, car, carVel, dt, clock, random)
  local f = state.flight
  if f then flight.step(f, car, carVel, dt) end
  if phase == "tracking" or phase == "searching" then
    if not f then
      state.flightRandom = state.seed and flight.seeded(state.seed) or random
      random = state.flightRandom
      if last == "arriving" or last == "refuelling" then
        state.flight = flight.arrive(car, random, carVel)
      else
        state.flight = flight.at(car, carVel, random)
      end
    elseif f.leaving then
      flight.resume(f)
      state.leftAt = nil
    end
  elseif phase == "refuelling" then
    if f and not f.leaving then
      flight.leave(f, car, state.flightRandom or random)
      state.leftAt = clock
    end
  elseif f then
    dropFlight(state)
  end
end

local function leftover(state, clock)
  if state.light then return true end
  local at = state.leftoverAt
  if at and clock >= at and clock - at < M.LEFTOVER_INTERVAL then return false end
  state.leftoverAt = clock
  return scenetree.findObject(M.LIGHT_NAME) ~= nil
end

local drawTri

local function drawQuad(a, b, c, d, clr)
  drawTri(a, b, c, clr, true)
  drawTri(a, c, d, clr, true)
end

local function castBeam(state, lightPos, aimPos, clock)
  if not castRayStatic or (state.rayAt and clock >= state.rayAt and clock - state.rayAt < beam.RAY_INTERVAL) then return end
  state.rayAt, state.beamHit = clock, nil
  local ax, ay, az = aimPos.x - lightPos.x, aimPos.y - lightPos.y, aimPos.z - lightPos.z
  local axisLen = math.sqrt(ax * ax + ay * ay + az * az)
  if not (axisLen > 0) then return end
  local d = tonumber(castRayStatic(lightPos, vec3(ax / axisLen, ay / axisLen, az / axisLen), axisLen))
  if d and d < axisLen - M.HIT_MARGIN and lightPos.z + az / axisLen * d > aimPos.z + M.HIT_MARGIN then state.beamHit = d end
end

local function drawBeam(state, clock, weather)
  local lightPos, aimPos = state.lightPos, state.aimPos
  castBeam(state, lightPos, aimPos, clock)
  local camPos = core_camera and core_camera.getPosition and core_camera.getPosition() or nil
  local n = beam.quads(lightPos, aimPos, beam.strength(weather, state.fx.bright), state.beamHit, camPos, state.beamQuads)
  drawTri = require("utils/debugDraw").drawTriSolid
  beam.draw(state.beamQuads, n, drawQuad, color)
end

local function beamTick(state, car, clock, opts)
  if (opts and opts.beam == false) or state.beamFailed or not (debugDrawer and color) then return end
  if slantOf(state.lightPos, car) > M.RANGE_MAX then return end
  local ok, err = pcall(drawBeam, state, clock, opts and opts.weather)
  if not ok then
    state.beamFailed = true
    log("E", "cnr_heli", "searchlight beam stopped: " .. tostring(err))
  end
end

local function tickLight(state, target, night, clock, opts)
  local random = state.random or math.random
  if state.light and not scenetree.findObject(M.LIGHT_NAME) then forgetLight(state) end
  if not target then
    if leftover(state, clock) then removeLight(state) end
    return
  end
  local phase, last = state.phase, state.lightPhase
  state.lightPhase = phase
  local car = target:getPosition()
  local dt = state.lastClock and clock - state.lastClock or 0
  state.lastClock = clock
  fly(state, phase, last, car, carVelocity(state, target, car, dt), dt, clock, random)
  local desired = phase == "tracking" and night
  if phase ~= last then
    if phase == "tracking" then
      if desired and (last == "arriving" or last == "refuelling") then
        startApproach(state, clock, random)
      elseif desired and last == "searching" then
        startRefound(state, clock, random)
      end
    elseif state.light then
      if phase == "refuelling" and last == "tracking" and state.fx.mode ~= "fade" and state.flight then
        startDepart(state, car, clock)
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
      startFadeIn(state, clock)
    end
  end
  if state.light and not (state.flight and advance(state, car, clock)) then removeLight(state) end
  if state.leftAt and clock - state.leftAt >= M.DEPART_SECONDS then dropFlight(state) end
  if state.light then beamTick(state, car, clock, opts) end
end

function M.lightTick(state, target, night, clock, opts)
  clock = clock or 0
  if state.failed then
    if leftover(state, clock) then pcall(removeLight, state) end
    return
  end
  local ok = pcall(tickLight, state, target, night, clock, opts)
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
  state.flight, state.leftAt, state.lastClock, state.lastCar, state.carVel = nil, nil, nil, nil, nil
  state.flightRandom, state.seed = nil, nil
  state.beamFailed = nil
  M.resetCover(state)
end

return M
