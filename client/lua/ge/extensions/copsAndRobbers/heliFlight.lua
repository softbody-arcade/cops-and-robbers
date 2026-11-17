local M = {}

M.MAX_SPEED = 70
M.MAX_ACCEL = 8
M.FOLLOW_GAIN = 0.4
M.SLOW_SPEED = 5
M.FAST_SPEED = 7
M.START_FOLLOW_SPEED = 6
M.FOLLOW_BACK = 25
M.FOLLOW_SIDE = 15
M.HELI_HEIGHT = 50
M.ORBIT_RADIUS = 30
M.ORBIT_PERIOD = 40
M.APPROACH_DISTANCE = 300
M.APPROACH_HEIGHT = 60
M.DEPART_DISTANCE = 400
M.DEPART_HEIGHT = 80
M.DEPART_HEADING_SPREAD = 60
M.APPROACH_SECONDS = 8
M.DEPART_SECONDS = 8
M.DEPART_FADE_SECONDS = 3
M.JUMP_METERS = 30
M.MAX_STEP = 0.1

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function horizontalSpeed(v)
  return math.sqrt(v.x * v.x + v.y * v.y)
end

local function pickSide(random)
  return random() < 0.5 and -1 or 1
end

local function headingOf(carVel, fallbackX, fallbackY)
  local speed = horizontalSpeed(carVel)
  if speed > 1e-6 then return carVel.x / speed, carVel.y / speed end
  return fallbackX, fallbackY
end

function M.target(f, carPos, carVel)
  if f.leaving then
    return vec3(f.leaving.x, f.leaving.y, f.leaving.z)
  end
  if f.mode == "circle" then
    return vec3(
      carPos.x + M.ORBIT_RADIUS * math.cos(f.orbit),
      carPos.y + M.ORBIT_RADIUS * math.sin(f.orbit),
      carPos.z + M.HELI_HEIGHT)
  end
  local dx, dy = headingOf(carVel, f.headingX, f.headingY)
  return vec3(
    carPos.x - M.FOLLOW_BACK * dx + M.FOLLOW_SIDE * f.side * -dy,
    carPos.y - M.FOLLOW_BACK * dy + M.FOLLOW_SIDE * f.side * dx,
    carPos.z + M.HELI_HEIGHT)
end

local function startMode(f, carPos, carVel, bearing)
  if horizontalSpeed(carVel) >= M.START_FOLLOW_SPEED then
    f.mode = "follow"
  else
    f.mode = "circle"
  end
  f.orbit = bearing
end

function M.arrive(carPos, random)
  random = random or math.random
  local heading = random() * 2 * math.pi
  local f = {
    pos = vec3(
      carPos.x + M.APPROACH_DISTANCE * math.cos(heading),
      carPos.y + M.APPROACH_DISTANCE * math.sin(heading),
      carPos.z + M.APPROACH_HEIGHT),
    vel = vec3(0, 0, 0),
    side = pickSide(random),
    headingX = 1,
    headingY = 0,
    lastCar = vec3(carPos.x, carPos.y, carPos.z),
  }
  startMode(f, carPos, vec3(0, 0, 0), heading)
  return f
end

function M.at(carPos, carVel, random)
  random = random or math.random
  local f = {
    vel = vec3(carVel.x, carVel.y, carVel.z),
    side = pickSide(random),
    headingX = 1,
    headingY = 0,
    lastCar = vec3(carPos.x, carPos.y, carPos.z),
  }
  startMode(f, carPos, carVel, random() * 2 * math.pi)
  local p = M.target(f, carPos, carVel)
  f.pos = p
  return f
end

function M.leave(f, carPos, random)
  random = random or math.random
  local bearing = atan2(f.pos.y - carPos.y, f.pos.x - carPos.x)
  local spread = math.rad(M.DEPART_HEADING_SPREAD)
  local heading = bearing + (random() * 2 - 1) * spread
  f.leaving = vec3(
    carPos.x + M.DEPART_DISTANCE * math.cos(heading),
    carPos.y + M.DEPART_DISTANCE * math.sin(heading),
    carPos.z + M.DEPART_HEIGHT)
end

function M.resume(f)
  f.leaving = nil
end

function M.step(f, carPos, carVel, dt)
  if not dt or dt <= 0 then return end
  if dt > M.MAX_STEP then dt = M.MAX_STEP end

  local last = f.lastCar
  if last then
    local jx, jy, jz = carPos.x - last.x, carPos.y - last.y, carPos.z - last.z
    if math.sqrt(jx * jx + jy * jy + jz * jz) > M.JUMP_METERS then
      f.pos = vec3(f.pos.x + jx, f.pos.y + jy, f.pos.z + jz)
      if f.leaving then
        f.leaving = vec3(f.leaving.x + jx, f.leaving.y + jy, f.leaving.z + jz)
      end
    end
  end
  f.lastCar = vec3(carPos.x, carPos.y, carPos.z)

  local speed = horizontalSpeed(carVel)
  if speed > 1 then f.headingX, f.headingY = carVel.x / speed, carVel.y / speed end
  if f.mode == "circle" then
    if speed > M.FAST_SPEED then f.mode = "follow" end
  elseif speed < M.SLOW_SPEED then
    f.mode = "circle"
    f.orbit = atan2(f.pos.y - carPos.y, f.pos.x - carPos.x)
  end

  local omega = 2 * math.pi / M.ORBIT_PERIOD * f.side
  if f.mode == "circle" then f.orbit = f.orbit + omega * dt end

  local t = M.target(f, carPos, carVel)
  local wx = M.FOLLOW_GAIN * (t.x - f.pos.x)
  local wy = M.FOLLOW_GAIN * (t.y - f.pos.y)
  local wz = M.FOLLOW_GAIN * (t.z - f.pos.z)
  if not f.leaving then
    wx, wy, wz = wx + carVel.x, wy + carVel.y, wz + carVel.z
    if f.mode == "circle" then
      wx = wx - M.ORBIT_RADIUS * omega * math.sin(f.orbit)
      wy = wy + M.ORBIT_RADIUS * omega * math.cos(f.orbit)
    end
  end
  local wl = math.sqrt(wx * wx + wy * wy + wz * wz)
  if wl > M.MAX_SPEED then
    local k = M.MAX_SPEED / wl
    wx, wy, wz = wx * k, wy * k, wz * k
  end

  local dx, dy, dz = wx - f.vel.x, wy - f.vel.y, wz - f.vel.z
  local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
  local limit = M.MAX_ACCEL * dt
  if dl > limit then
    local k = limit / dl
    dx, dy, dz = dx * k, dy * k, dz * k
  end
  f.vel = vec3(f.vel.x + dx, f.vel.y + dy, f.vel.z + dz)
  f.pos = vec3(f.pos.x + f.vel.x * dt, f.pos.y + f.vel.y * dt, f.pos.z + f.vel.z * dt)
end

return M
