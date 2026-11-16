local shelter = require("copsAndRobbers/shelter")

local M = {}

M.COVER_INTERVAL = 0.25
M.COVER_HEIGHT = 1.5
M.LIGHT_HEIGHT = 40
M.LIGHT_NAME = "cnr_heli_light"
M.HOVER_DRIFT = 2
M.AIM_LAG = 0.12
M.AIM_SPRING = 14
M.AIM_DAMPING = 5
M.AIM_MAX_OFFSET = 6
M.NUDGE_RADIUS = 1.2
M.NUDGE_MIN = 0.4
M.NUDGE_MAX = 1.2
M.JUMP_METERS = 30
M.MAX_STEP = 0.1

local FIELDS = {
  { "brightness", 80 }, { "range", 120 }, { "innerAngle", 8 }, { "outerAngle", 16 },
  { "color", "0.85 0.92 1 1" }, { "castShadows", "false" },
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
  state.light, state.aim = nil, nil
end

function M.newAim()
  return { offset = { x = 0, y = 0 }, vel = { x = 0, y = 0 }, goal = { x = 0, y = 0 }, nextNudge = nil, lastCar = nil, lastCarVel = { x = 0, y = 0 } }
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
  dt = math.min(dt, M.MAX_STEP)
  local last = aim.lastCar
  if last and (carPos.x - last.x) ^ 2 + (carPos.y - last.y) ^ 2 > M.JUMP_METERS ^ 2 then
    aim.offset.x, aim.offset.y, aim.vel.x, aim.vel.y = 0, 0, 0, 0
    aim.lastCarVel.x, aim.lastCarVel.y = 0, 0
    last = nil
  end
  if last and dt > 0 then
    local vx, vy = (carPos.x - last.x) / dt, (carPos.y - last.y) / dt
    aim.offset.x = aim.offset.x - (vx - aim.lastCarVel.x) * M.AIM_LAG
    aim.offset.y = aim.offset.y - (vy - aim.lastCarVel.y) * M.AIM_LAG
    aim.lastCarVel.x, aim.lastCarVel.y = vx, vy
  end
  aim.lastCar = { x = carPos.x, y = carPos.y }
  if not aim.nextNudge or clock >= aim.nextNudge then pickGoal(aim, clock, random) end
  local o, v, g = aim.offset, aim.vel, aim.goal
  v.x = v.x + (M.AIM_SPRING * (g.x - o.x) - M.AIM_DAMPING * v.x) * dt
  v.y = v.y + (M.AIM_SPRING * (g.y - o.y) - M.AIM_DAMPING * v.y) * dt
  o.x, o.y = o.x + v.x * dt, o.y + v.y * dt
  local len = math.sqrt(o.x * o.x + o.y * o.y)
  if len > M.AIM_MAX_OFFSET then o.x, o.y = o.x * M.AIM_MAX_OFFSET / len, o.y * M.AIM_MAX_OFFSET / len end
  local tx = 0.25 * math.sin(19.5 * clock) + 0.12 * math.sin(33 * clock)
  local ty = 0.25 * math.cos(17 * clock) + 0.12 * math.cos(29 * clock)
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
  return true
end

local function placeLight(state, target, clock)
  clock = clock or 0
  local car = target:getPosition()
  local aim = state.aim
  local aimPos = M.aimStep(aim, car, aim.lastClock and clock - aim.lastClock or 0, clock, state.random)
  aim.lastClock = clock
  local lightPos = M.lightPose(car, clock)
  state.light:setPosition(lightPos)
  pcall(aimLight, state.light, lightPos, aimPos)
end

function M.lightTick(state, target, night, clock)
  if M.tracking(state) and night and target and not state.failed then
    local ok = pcall(function()
      if not state.light or not scenetree.findObject(M.LIGHT_NAME) then
        if not createLight(state) then error("no light") end
      end
      placeLight(state, target, clock)
    end)
    if not ok then
      pcall(removeLight, state)
      state.failed = true
    end
  elseif state.light or scenetree.findObject(M.LIGHT_NAME) then
    pcall(removeLight, state)
  end
end

function M.clear(state)
  pcall(removeLight, state)
  state.phase, state.reason, state.endsAt, state.failed = nil, nil, nil, nil
  M.resetCover(state)
end

return M
