local M = {}

M.MAX_SPEED = 70
M.MAX_ACCEL = 8
M.FOLLOW_GAIN = 0.4
M.SLOW_SPEED = 5
M.FAST_SPEED = 7
M.START_FOLLOW_SPEED = 6
M.FOLLOW_BACK = 40
M.FOLLOW_SIDE = 60
M.HELI_HEIGHT = 100
M.ORBIT_RADIUS = 80
M.ORBIT_PERIOD = 40
M.APPROACH_DISTANCE = 300
M.APPROACH_HEIGHT = 120
M.DEPART_DISTANCE = 600
M.DEPART_HEIGHT = 150
M.DEPART_HEADING_SPREAD = 60
M.APPROACH_SECONDS = 8
M.DEPART_SECONDS = 8
M.DEPART_FADE_SECONDS = 3
M.JUMP_METERS = 30
M.MAX_STEP = 0.1
M.SEARCH_RADIUS = 120
M.SEARCH_PERIOD = 40

local SCAN_INTERVAL = 0.2
local CLEARANCE = 20
local NOSE_MARGIN = 5
local LOOK_AHEAD = 1.5
local CLIMB_RATE = 40
local DESCENT_RATE = 20
local PROBE_HEIGHT = 2500

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function horizontalSpeed(v)
  return math.sqrt(v.x * v.x + v.y * v.y)
end

function M.seeded(seed)
  local n = tonumber(seed) or 1
  if n ~= n or n == math.huge or n == -math.huge then n = 1 end
  n = math.floor(n)
  if n < 1 or n > 2147483646 then n = n % 2147483646 + 1 end
  local x = n
  return function()
    x = x * 16807 % 2147483647
    return x / 2147483647
  end
end

local function pickSide(random)
  return random() < 0.5 and -1 or 1
end

local function headingOf(carVel, fallbackX, fallbackY)
  local speed = horizontalSpeed(carVel)
  if speed > 1 then return carVel.x / speed, carVel.y / speed end
  return fallbackX, fallbackY
end

function M.target(f, carPos, carVel)
  if f.leaving then
    return vec3(f.leaving.x, f.leaving.y, f.leaving.z)
  end
  if f.spot then
    return vec3(
      f.spot.x + M.SEARCH_RADIUS * math.cos(f.searchAngle),
      f.spot.y + M.SEARCH_RADIUS * math.sin(f.searchAngle),
      f.spot.z + M.HELI_HEIGHT)
  end
  if f.lead then
    local dx, dy = headingOf(f.leadVel, f.headingX, f.headingY)
    return vec3(
      f.lead.x - M.FOLLOW_BACK * dx + M.FOLLOW_SIDE * f.side * -dy,
      f.lead.y - M.FOLLOW_BACK * dy + M.FOLLOW_SIDE * f.side * dx,
      f.lead.z + M.HELI_HEIGHT)
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

local function startMode(f, carVel, bearing)
  if horizontalSpeed(carVel) >= M.START_FOLLOW_SPEED then
    f.mode = "follow"
  else
    f.mode = "circle"
  end
  f.orbit = bearing
end

function M.search(f, spot)
  f.spot = vec3(spot.x, spot.y, spot.z)
  f.spotVel = vec3(0, 0, 0)
  f.lead = nil
  f.leadVel = nil
  f.searchAngle = atan2(f.pos.y - spot.y, f.pos.x - spot.x)
end

function M.lead(f, pos, vel)
  f.lead = vec3(pos.x, pos.y, pos.z)
  f.leadVel = vec3(vel.x, vel.y, vel.z)
  f.spot = nil
  f.spotVel = nil
end

function M.follow(f, carPos, carVel)
  f.spot = nil
  f.spotVel = nil
  f.lead = nil
  f.leadVel = nil
  startMode(f, carVel, atan2(f.pos.y - carPos.y, f.pos.x - carPos.x))
end

function M.arrive(carPos, random, carVel, spot)
  random = random or math.random
  local side = pickSide(random)
  local heading = random() * 2 * math.pi
  local origin = spot or carPos
  local f = {
    pos = vec3(
      origin.x + M.APPROACH_DISTANCE * math.cos(heading),
      origin.y + M.APPROACH_DISTANCE * math.sin(heading),
      origin.z + M.APPROACH_HEIGHT),
    vel = vec3(0, 0, 0),
    side = side,
    headingX = 1,
    headingY = 0,
    lastCar = vec3(carPos.x, carPos.y, carPos.z),
  }
  startMode(f, carVel or vec3(0, 0, 0), heading)
  return f
end

function M.at(carPos, carVel, random, spot)
  random = random or math.random
  if spot then
    local f = {
      vel = vec3(0, 0, 0),
      side = pickSide(random),
      headingX = 1,
      headingY = 0,
      lastCar = vec3(carPos.x, carPos.y, carPos.z),
    }
    f.spot = vec3(spot.x, spot.y, spot.z)
    f.spotVel = vec3(0, 0, 0)
    f.searchAngle = random() * 2 * math.pi
    f.pos = M.target(f, carPos, carVel)
    return f
  end
  local f = {
    vel = vec3(carVel.x, carVel.y, carVel.z),
    side = pickSide(random),
    headingX = 1,
    headingY = 0,
    lastCar = vec3(carPos.x, carPos.y, carPos.z),
  }
  startMode(f, carVel, random() * 2 * math.pi)
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

function M.jumpOf(last, pos)
  if not last then return nil end
  local jx, jy, jz = pos.x - last.x, pos.y - last.y, pos.z - last.z
  if math.sqrt(jx * jx + jy * jy + jz * jz) > M.JUMP_METERS then return jx, jy, jz end
  return nil
end

local function floorAt(x, y, z)
  local top = z + PROBE_HEIGHT
  local length = PROBE_HEIGHT + CLEARANCE
  local d = castRayStatic(vec3(x, y, top), vec3(0, 0, -1), length)
  if type(d) == "number" and d >= 0 and d < length then return top - d + CLEARANCE end
  return -math.huge
end

local function scanClearance(f, z)
  local p = f.pos
  local floor = floorAt(p.x, p.y, z)
  local speed = horizontalSpeed(f.vel)
  if speed < 0.1 then return floor, floor end
  local dx, dy = f.vel.x / speed, f.vel.y / speed
  local near = NOSE_MARGIN + speed * (SCAN_INTERVAL + M.MAX_STEP)
  local flightZ = math.max(z + (f.lift or 0), floor)
  floor = math.max(floor, floorAt(p.x + dx * near, p.y + dy * near, z))
  local reach = near + speed * LOOK_AHEAD
  local ahead = floorAt(p.x + dx * reach, p.y + dy * reach, z)
  local hit = castRayStatic(vec3(p.x, p.y, flightZ), vec3(dx, dy, 0), reach)
  if type(hit) == "number" and hit >= 0 and hit < reach then
    local top = floorAt(p.x + dx * (hit + 0.25), p.y + dy * (hit + 0.25), z)
    if hit <= near then floor = math.max(floor, top) end
    ahead = math.max(ahead, top)
  end
  return floor, math.max(floor, ahead)
end

function M.clearance(f, clock, dt)
  local z = f.nominalZ or f.pos.z
  if castRayStatic and (not f.scanAt or clock < f.scanAt or clock - f.scanAt >= SCAN_INTERVAL) then
    f.scanAt = clock
    local ok, floor, ahead = pcall(scanClearance, f, z)
    if ok then
      f.floor, f.ahead = floor, ahead
    elseif not f.scanLogged then
      f.scanLogged = true
      log("E", "cnr_heli", "helicopter clearance scan failed: " .. tostring(floor))
    end
  end
  if not f.floor then return end
  local lift = f.lift or 0
  local step = math.max(0, math.min(dt, M.MAX_STEP))
  local desired = math.max(0, f.ahead - z)
  local climb = math.min(desired, lift + step * CLIMB_RATE)
  lift = math.max(f.floor - z, lift - step * DESCENT_RATE, climb)
  f.lift = lift
  f.nominalZ = lift > 0 and z or nil
  f.pos.z = z + lift
end

function M.step(f, carPos, carVel, dt)
  if not dt or not (dt > 0) then return end
  if dt > M.MAX_STEP then dt = M.MAX_STEP end

  local z = f.nominalZ or f.pos.z
  local jx, jy, jz = M.jumpOf(f.lastCar, carPos)
  if jx then
    f.scanAt, f.floor, f.ahead, f.lift = nil, nil, nil, nil
    z = z + jz
    f.pos = vec3(f.pos.x + jx, f.pos.y + jy, f.pos.z + jz)
    if f.leaving then
      f.leaving = vec3(f.leaving.x + jx, f.leaving.y + jy, f.leaving.z + jz)
    end
    if f.spot then
      f.spot = vec3(f.spot.x + jx, f.spot.y + jy, f.spot.z + jz)
    end
    if f.lead then
      f.lead = vec3(f.lead.x + jx, f.lead.y + jy, f.lead.z + jz)
    end
  end
  f.lastCar = vec3(carPos.x, carPos.y, carPos.z)

  local leading = f.lead ~= nil and not f.leaving
  local searching = f.spot ~= nil
  local omega
  if leading then
    f.headingX, f.headingY = headingOf(f.leadVel, f.headingX, f.headingY)
  elseif searching then
    omega = 2 * math.pi / M.SEARCH_PERIOD * f.side
    if not f.leaving then f.searchAngle = f.searchAngle + omega * dt end
  else
    local speed = horizontalSpeed(carVel)
    f.headingX, f.headingY = headingOf(carVel, f.headingX, f.headingY)
    if f.mode == "circle" then
      if speed > M.FAST_SPEED then f.mode = "follow" end
    elseif speed < M.SLOW_SPEED then
      f.mode = "circle"
      f.orbit = atan2(f.pos.y - carPos.y, f.pos.x - carPos.x)
    end
    omega = 2 * math.pi / M.ORBIT_PERIOD * f.side
    if f.mode == "circle" then f.orbit = f.orbit + omega * dt end
  end

  local t = M.target(f, carPos, carVel)
  local wx = M.FOLLOW_GAIN * (t.x - f.pos.x)
  local wy = M.FOLLOW_GAIN * (t.y - f.pos.y)
  local wz = M.FOLLOW_GAIN * (t.z - z)
  if leading then
    wx, wy, wz = wx + f.leadVel.x, wy + f.leadVel.y, wz + f.leadVel.z
  elseif not f.leaving and searching then
    local sv = f.spotVel
    if sv then wx, wy, wz = wx + sv.x, wy + sv.y, wz + sv.z end
    wx = wx - M.SEARCH_RADIUS * omega * math.sin(f.searchAngle)
    wy = wy + M.SEARCH_RADIUS * omega * math.cos(f.searchAngle)
  elseif not f.leaving then
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
  f.pos = vec3(f.pos.x + f.vel.x * dt, f.pos.y + f.vel.y * dt, z + f.vel.z * dt)
  f.nominalZ = nil
end

return M
