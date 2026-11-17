local shelter = require("copsAndRobbers/shelter")
local flight = require("copsAndRobbers/heliFlight")
local beam = require("copsAndRobbers/beam")
local search = require("copsAndRobbers/heliSearch")

local M = {}

M.COVER_INTERVAL = 0.25
M.COVER_HEIGHT = 1.5
M.LIGHT_NAME = "cnr_heli_light"
M.BRIGHTNESS = 160
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
M.DEPART_SECONDS = flight.DEPART_SECONDS
M.DEPART_FADE_SECONDS = flight.DEPART_FADE_SECONDS
M.DEPART_AIM_DRIFT = 60
M.FADE_SECONDS = 1.5
M.FADEIN_SECONDS = 1
M.MAX_STEP = flight.MAX_STEP
M.LEFTOVER_INTERVAL = 1
M.FLARE_TYPE = "BNG_LightFlare_1"
M.FLARE_STEP = 0.05
M.HIT_MARGIN = 2
M.SIGHT_RANGE = 400
M.SWEEP_RADIUS = 150
M.SWEEP_PERIOD = 40
M.SWEEP_TURN = 8
M.SWEEP_RAY_HEIGHT = 100
M.SWEEP_RAY_LENGTH = 200
M.SWEEP_RAY_INTERVAL = 0.25
M.AIM_SWITCH_SECONDS = 0.5
M.TARGET_MISSING_SECONDS = search.TARGET_MISSING_SECONDS

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
    state.phase, state.reason, state.endsAt, state.seed, state.guided = nil, nil, nil, nil, false
    return
  end
  local seconds = tonumber(d.seconds)
  state.phase, state.reason = d.phase, d.reason
  state.endsAt = seconds and clock + seconds or nil
  state.seed = tonumber(d.seed)
  state.guided = d.guided == true
  state.flightFailed = nil
end

function M.tracking(state)
  return state.phase == "tracking"
end

function M.resetCover(state)
  state.cover, state.sent, state.lastCheck = shelter.new(), false, nil
end

function M.coverTick(state, clock, obj, castRay)
  if state.lastCheck and clock - state.lastCheck < M.COVER_INTERVAL then return nil end
  state.lastCheck = clock
  local f = state.flight
  local covered = true
  if f and castRay then
    local p = obj:getPosition()
    local dir = obj.getDirectionVector and obj:getDirectionVector()
    covered = not shelter.inSight(f.pos, p, M.COVER_HEIGHT, dir and dir.x or 0, dir and dir.y or 0, castRay, M.SIGHT_RANGE)
  end
  if not state.sent then
    state.sent = true
    state.cover = { covered = covered, pending = nil, count = 0 }
    return covered
  end
  if shelter.step(state.cover, covered) then return state.cover.covered end
  return nil
end

local function forgetLight(state)
  state.light, state.aim, state.fx, state.lightPos, state.aimPos = nil, nil, nil, nil, nil
  state.beamHit, state.rayAt, state.aimSwitch = nil, nil, nil
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
  if flight.jumpOf(last, carPos) then
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
  aim.lastCar = { x = carPos.x, y = carPos.y, z = carPos.z }
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

local function lightError(state, msg)
  if state.lightLogged then return end
  state.lightLogged = true
  log("E", "cnr_heli", msg)
end

local function setUpLight(obj)
  for _, f in ipairs(FIELDS) do obj:setField(f[1], 0, tostring(f[2])) end
  pcall(applyField, obj, "flareType", M.FLARE_TYPE)
  obj.canSave = false
  obj:registerObject(M.LIGHT_NAME)
end

local function createLight(state)
  local obj = createObject("SpotLight")
  if not obj then return false end
  local ok, err = pcall(setUpLight, obj)
  if not ok then
    pcall(function() obj:delete() end)
    error(err, 0)
  end
  if not scenetree.findObject(M.LIGHT_NAME) then
    obj:delete()
    lightError(state, "searchlight did not register")
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

local function slantOf(lightPos, aimPos)
  local dx, dy, dz = lightPos.x - aimPos.x, lightPos.y - aimPos.y, lightPos.z - aimPos.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function writeRange(state, lightPos, aimPos)
  local range = math.min(M.RANGE_MAX, math.floor(math.max(M.RANGE_MIN, slantOf(lightPos, aimPos) + M.RANGE_MARGIN) + 0.5))
  if state.lightRange and math.abs(range - state.lightRange) <= M.RANGE_STEP then return end
  if pcall(applyField, state.light, "range", tostring(range)) then state.lightRange = range end
end

local function switchLeft(s, clock)
  if not s then return 0, 0, 0 end
  local k = math.exp(-(clock - s.at) / M.AIM_SWITCH_SECONDS)
  return s.x * k, s.y * k, s.z * k
end

local function foldDrift(state, extra, clock)
  local f = state.flight
  if f and (f.spot or search.roadAim(state, clock)) then
    local x, y, z = switchLeft(state.aimSwitch, clock)
    state.aimSwitch = { x = x + extra.x, y = y + extra.y, z = z, at = clock }
  else
    local o = state.aim.offset
    o.x, o.y = o.x + extra.x, o.y + extra.y
  end
end

local function toMode(state, mode, clock)
  local fx = state.fx
  if fx.mode == "depart" and fx.extra then foldDrift(state, fx.extra, clock) end
  fx.mode, fx.t0, fx.extra = mode, clock, nil
end

local function startApproach(state, clock)
  local fresh = not state.light
  if fresh and not createLight(state) then error("no light") end
  local fx = state.fx
  fx.fromBright = fresh and 0 or (fx.bright or 1)
  toMode(state, "approach", clock)
end

local function startFadeIn(state, clock)
  local fx = state.fx
  fx.fromBright = fx.bright or 0
  toMode(state, "fadein", clock)
end

local function startDepart(state, ref, clock)
  local fx, to = state.fx, state.flight.leaving
  local dx, dy = to.x - ref.x, to.y - ref.y
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

function M.sweepPoint(spot, t)
  local u = (t % M.SWEEP_PERIOD) / M.SWEEP_PERIOD
  local r = M.SWEEP_RADIUS * (1 - math.abs(1 - 2 * u))
  local a = 2 * math.pi * t / M.SWEEP_TURN
  return vec3(spot.x + r * math.cos(a), spot.y + r * math.sin(a), spot.z)
end

local function groundBelow(spot, x, y)
  local z = spot.z
  if not castRayStatic then return z end
  local d = tonumber(castRayStatic(vec3(x, y, z + M.SWEEP_RAY_HEIGHT), vec3(0, 0, -1), M.SWEEP_RAY_LENGTH))
  if d and d < M.SWEEP_RAY_LENGTH then return z + M.SWEEP_RAY_HEIGHT - d end
  return z
end

local function groundedAim(state, x, y, z, clock)
  local from = state.sweepAt or clock
  local at = state.sweepRayAt
  if not at or state.sweepRayFor ~= from or state.jumpAt ~= state.sweepRayJump or clock < at or clock - at >= M.SWEEP_RAY_INTERVAL then
    state.sweepRayAt, state.sweepRayFor, state.sweepRayJump = clock, from, state.jumpAt
    state.sweepZ = groundBelow({ z = z }, x, y)
  end
  return x, y, state.sweepZ
end

local function aimAt(state, f, carAim, extra, clock)
  local x, y, z
  local rx, ry, rz = search.roadAim(state, clock)
  if rx then
    x, y, z = groundedAim(state, rx, ry, rz, clock)
  elseif f.spot then
    local p = M.sweepPoint(f.spot, clock - (state.sweepAt or clock))
    x, y, z = groundedAim(state, p.x, p.y, f.spot.z, clock)
  elseif f.lead then
    x, y, z = groundedAim(state, f.lead.x, f.lead.y, f.lead.z, clock)
  else
    x, y, z = carAim.x, carAim.y, carAim.z
  end
  if extra then x, y = x + extra.x, y + extra.y end
  if state.retargetAt ~= state.aimRetarget then
    local prev = state.aimPos
    if prev then state.aimSwitch = { x = prev.x - x, y = prev.y - y, z = prev.z - z, at = clock } end
    state.aimRetarget = state.retargetAt
  end
  local sx, sy, sz = switchLeft(state.aimSwitch, clock)
  return vec3(x + sx, y + sy, z + sz)
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
  local carAim = M.aimStep(aim, car, aim.lastClock and clock - aim.lastClock or 0, clock, state.random, f.vel)
  aim.lastClock = clock
  local aimPos = aimAt(state, f, carAim, extra, clock)
  state.light:setPosition(light)
  writeRange(state, light, aimPos)
  state.lightPos, state.aimPos = light, aimPos
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

local function beamTick(state, clock, opts)
  if (opts and opts.beam == false) or state.beamFailed or not color then return end
  if slantOf(state.lightPos, state.aimPos) > M.RANGE_MAX then return end
  local ok, err = pcall(drawBeam, state, clock, opts and opts.weather)
  if not ok then
    state.beamFailed = true
    log("E", "cnr_heli", "searchlight beam stopped: " .. tostring(err))
  end
end

local function isUp(phase)
  return phase == "tracking" or phase == "searching"
end

local function tickLight(state, target, phase, last, night, clock, opts)
  if state.light and not scenetree.findObject(M.LIGHT_NAME) then forgetLight(state) end
  if not target then
    if leftover(state, clock) then removeLight(state) end
    return
  end
  local car = target:getPosition()
  local f = state.flight
  local desired = isUp(phase) and night and f ~= nil
  if phase ~= last and not (isUp(phase) and isUp(last)) then
    if isUp(phase) and (last == "arriving" or last == "refuelling") then
      if desired then startApproach(state, clock) end
    elseif state.light then
      if phase == "refuelling" and isUp(last) and f and state.fx.mode ~= "fade" then
        startDepart(state, f.spot or f.lead or car, clock)
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
  if state.light then beamTick(state, clock, opts) end
end

function M.lightTick(state, target, night, clock, opts)
  clock = clock or 0
  local phase, last = state.phase, state.lightPhase
  if not state.flightFailed then
    local ok, err = pcall(search.tick, state, target, phase, last, clock, opts)
    if not ok then
      pcall(search.drop, state)
      state.flightFailed = true
      if not state.flightLogged then
        state.flightLogged = true
        log("E", "cnr_heli", "helicopter flight stopped: " .. tostring(err))
      end
    end
  end
  if state.failed then
    if leftover(state, clock) then pcall(removeLight, state) end
  else
    local ok, err = pcall(tickLight, state, target, phase, last, night, clock, opts)
    if not ok then
      pcall(removeLight, state)
      state.failed = true
      lightError(state, "searchlight stopped: " .. tostring(err))
    end
  end
  if target then state.lightPhase = phase end
end

function M.wantsNight(state)
  return isUp(state.phase) or state.light ~= nil
end

M.soundLevel = search.soundLevel

function M.clear(state)
  pcall(removeLight, state)
  state.phase, state.reason, state.endsAt, state.failed, state.lightPhase = nil, nil, nil, nil, nil
  search.clear(state)
  state.seed = nil
  state.beamFailed = nil
  state.guided = nil
  state.flightLogged = nil
  state.aimSwitch, state.aimRetarget, state.sweepZ, state.sweepRayAt, state.sweepRayFor = nil, nil, nil, nil, nil
  state.sweepRayJump = nil
  state.lightLogged = nil
  M.resetCover(state)
end

return M
