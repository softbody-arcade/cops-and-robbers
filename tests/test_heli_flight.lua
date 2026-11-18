dofile("tests/env_stubs.lua")
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
_G.vec3 = _G.vec3 or function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
package.loaded["copsAndRobbers/heliFlight"] = nil
local flight = require("copsAndRobbers/heliFlight")

local DT = 0.05

local function seeded(seed)
  local s = seed
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
end

local function len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function horiz(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

local function runSteady(f, car, vel, seconds)
  for _ = 1, math.floor(seconds / DT + 0.5) do
    car = vec3(car.x + vel.x * DT, car.y + vel.y * DT, car.z + vel.z * DT)
    flight.step(f, car, vel, DT)
  end
  return car
end

test("speed and acceleration stay within the limits under random car motion", function()
  local random = seeded(7)
  local car = vec3(0, 0, 0)
  local vel = vec3(0, 0, 0)
  local f = flight.arrive(car, random)
  for _ = 1, 2400 do
    vel = vec3(vel.x + (random() - 0.5) * 20, vel.y + (random() - 0.5) * 20, 0)
    local l = len(vel)
    if l > 90 then vel = vec3(vel.x * 90 / l, vel.y * 90 / l, 0) end
    car = vec3(car.x + vel.x * DT, car.y + vel.y * DT, 0)
    local before = f.vel
    flight.step(f, car, vel, DT)
    assertEq(len(f.vel) <= 70 + 1e-6, true, "speed")
    local dv = dist(f.vel, before)
    assertEq(dv <= 8 * DT + 1e-6, true, "accel")
  end
end)

test("behind a steady car it settles on the follow point", function()
  for _, side in ipairs({ -1, 1 }) do
    local random = function() return side == 1 and 0.9 or 0.1 end
    local car = vec3(0, 0, 0)
    local f = flight.at(car, vec3(30, 0, 0), random)
    f.pos = vec3(-200, 100, 80)
    f.vel = vec3(10, 0, 0)
    f.mode = "follow"
    assertEq(f.side, side)
    car = runSteady(f, car, vec3(30, 0, 0), 60)
    assertNear(f.pos.x - car.x, -40, 3)
    assertNear(f.pos.y - car.y, 60 * side, 3)
    assertNear(f.pos.z - car.z, 100, 3)
  end
end)

test("a stopping car is overshot, then circled", function()
  for _, side in ipairs({ -1, 1 }) do
    local random = function() return side == 1 and 0.9 or 0.1 end
    local car = vec3(0, 0, 0)
    local f = flight.at(car, vec3(30, 0, 0), random)
    assertEq(f.mode, "follow")
    car = runSteady(f, car, vec3(30, 0, 0), 30)
    local still = vec3(0, 0, 0)
    local minHoriz = math.huge
    local prev, rates = nil, {}
    for i = 1, 1200 do
      flight.step(f, car, still, DT)
      local h = horiz(f.pos, car)
      if h < minHoriz then minHoriz = h end
      if i * DT >= 40 then
        assertNear(h, 80, 2, "radius")
        assertNear(f.pos.z - car.z, 100, 2, "height")
        local b = math.atan2(f.pos.y - car.y, f.pos.x - car.x)
        if prev then
          local d = b - prev
          while d > math.pi do d = d - 2 * math.pi end
          while d < -math.pi do d = d + 2 * math.pi end
          rates[#rates + 1] = d / DT
        end
        prev = b
      end
    end
    assertEq(minHoriz < 25, true, "overshoot")
    local want = 2 * math.pi / 40
    for _, r in ipairs(rates) do
      assertEq(r * side > 0, true, "direction")
      assertNear(math.abs(r), want, want * 0.2, "rate")
    end
  end
end)

test("the fly-in reaches its target point", function()
  local car = vec3(100, 200, 10)
  local f = flight.arrive(car, seeded(3))
  assertNear(horiz(f.pos, car), 300, 1e-6)
  assertNear(f.pos.z - car.z, 120, 1e-6)
  assertEq(len(f.vel), 0)
  for _ = 1, 400 do flight.step(f, car, vec3(0, 0, 0), DT) end
  assertEq(dist(f.pos, flight.target(f, car, vec3(0, 0, 0))) <= 5, true)
end)

test("the fly-away leaves a still car and grows every second", function()
  for seed = 1, 20 do
    local random = seeded(seed)
    local car = vec3(0, 0, 0)
    local f = flight.at(car, vec3(0, 0, 0), random)
    for _ = 1, 200 do flight.step(f, car, vec3(0, 0, 0), DT) end
    local bearing = math.atan2(f.pos.y - car.y, f.pos.x - car.x)
    flight.leave(f, car, random)
    local out = math.atan2(f.leaving.y - car.y, f.leaving.x - car.x)
    local d = out - bearing
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    assertEq(math.abs(d) <= math.rad(60) + 1e-9, true, "heading")
    assertNear(horiz(f.leaving, car), 600, 1e-6)
    assertNear(f.leaving.z, 150, 1e-6)
    local last = dist(f.pos, car)
    for second = 1, 8 do
      for _ = 1, 20 do flight.step(f, car, vec3(0, 0, 0), DT) end
      local now = dist(f.pos, car)
      assertEq(now > last, true, "grows at " .. second .. " seed " .. seed)
      last = now
    end
    assertEq(last > 200, true, "far at 8 s, seed " .. seed)
  end
end)

test("resume clears leaving and keeps position and velocity", function()
  local car = vec3(0, 0, 0)
  local f = flight.arrive(car, seeded(5))
  flight.leave(f, car, seeded(6))
  for _ = 1, 40 do flight.step(f, car, vec3(0, 0, 0), DT) end
  local p, v = f.pos, f.vel
  flight.resume(f)
  assertEq(f.leaving, nil)
  assertEq(f.pos, p)
  assertEq(f.vel, v)
end)

test("no step moves further than the top speed allows", function()
  local random = seeded(11)
  local car = vec3(0, 0, 0)
  local f = flight.arrive(car, random)
  for i = 1, 1200 do
    local vel = vec3(math.sin(i / 40) * 50, math.cos(i / 25) * 50, 0)
    car = vec3(car.x + vel.x * DT, car.y + vel.y * DT, 0)
    local before = f.pos
    flight.step(f, car, vel, DT)
    assertEq(dist(f.pos, before) <= 70 * DT + 1e-6, true)
  end
end)

test("at starts on the target point with the car's velocity", function()
  local car = vec3(5, 6, 7)
  local vel = vec3(20, 10, 0)
  local f = flight.at(car, vel, seeded(2))
  local t = flight.target(f, car, vel)
  assertEq(dist(f.pos, t), 0)
  assertEq(f.vel.x, 20)
  assertEq(f.vel.y, 10)
  assertEq(f.vel.z, 0)
  local slow = flight.at(car, vec3(1, 0, 0), seeded(2))
  assertEq(slow.mode, "circle")
  assertNear(horiz(slow.pos, car), 80, 1e-9)
end)

test("arrive circles without a velocity and follows from 6 m/s", function()
  local car = vec3(0, 0, 0)
  assertEq(flight.arrive(car, seeded(1)).mode, "circle")
  assertEq(flight.arrive(car, seeded(1), vec3(5.9, 0, 0)).mode, "circle")
  assertEq(flight.arrive(car, seeded(1), vec3(6, 0, 0)).mode, "follow")
  assertEq(flight.arrive(car, seeded(1), vec3(0, 20, 0)).mode, "follow")
  local f = flight.arrive(car, seeded(1))
  assertNear(math.cos(f.orbit), f.pos.x / 300, 1e-9)
  assertNear(math.sin(f.orbit), f.pos.y / 300, 1e-9)
end)

test("at follows from exactly 6 m/s and circles at 5.9 m/s", function()
  local car = vec3(0, 0, 0)
  assertEq(flight.at(car, vec3(5.9, 0, 0), seeded(1)).mode, "circle")
  assertEq(flight.at(car, vec3(6, 0, 0), seeded(1)).mode, "follow")
end)

test("target keeps the heading below 1 m/s like step", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(30, 0, 0), seeded(2))
  flight.step(f, car, vec3(30, 0, 0), DT)
  local a = flight.target(f, car, vec3(0.5, 0.5, 0))
  local b = flight.target(f, car, vec3(0, 0, 0))
  assertNear(a.x, b.x, 1e-9)
  assertNear(a.y, b.y, 1e-9)
end)

test("speeds between slow and fast keep the mode", function()
  local car = vec3(0, 0, 0)
  local circling = flight.at(car, vec3(0, 0, 0), seeded(4))
  local following = flight.at(car, vec3(30, 0, 0), seeded(4))
  assertEq(circling.mode, "circle")
  assertEq(following.mode, "follow")
  for _ = 1, 100 do
    flight.step(circling, car, vec3(6, 0, 0), DT)
    flight.step(following, car, vec3(6, 0, 0), DT)
  end
  assertEq(circling.mode, "circle")
  assertEq(following.mode, "follow")
  flight.step(circling, car, vec3(8, 0, 0), DT)
  flight.step(following, car, vec3(4, 0, 0), DT)
  assertEq(circling.mode, "follow")
  assertEq(following.mode, "circle")
end)

test("a car jump shifts the helicopter and leaves the step unchanged relative to the car", function()
  local function build()
    local car = vec3(0, 0, 0)
    local f = flight.at(car, vec3(30, 0, 0), seeded(9))
    runSteady(f, car, vec3(30, 0, 0), 5)
    return f
  end
  local a, b = build(), build()
  local carA = vec3(150, 0, 0)
  local carB = vec3(150 + 2000, 300, 40)
  flight.leave(a, carA, seeded(1))
  flight.leave(b, carA, seeded(1))
  a.lastCar = vec3(carA.x, carA.y, carA.z)
  b.lastCar = vec3(carA.x, carA.y, carA.z)
  local nextA = carA
  local nextB = carB
  flight.step(a, nextA, vec3(30, 0, 0), DT)
  flight.step(b, nextB, vec3(30, 0, 0), DT)
  assertNear(b.pos.x - nextB.x, a.pos.x - nextA.x, 1e-9)
  assertNear(b.pos.y - nextB.y, a.pos.y - nextA.y, 1e-9)
  assertNear(b.pos.z - nextB.z, a.pos.z - nextA.z, 1e-9)
  assertNear(b.leaving.x - nextB.x, a.leaving.x - nextA.x, 1e-9)
  assertNear(b.vel.x, a.vel.x, 1e-9)
  assertNear(b.vel.y, a.vel.y, 1e-9)
end)

test("a 50 m car jump does not speed the helicopter up", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(30, 0, 0), seeded(8))
  flight.step(f, vec3(0, 0, 0), vec3(30, 0, 0), DT)
  local before = f.vel.x
  flight.step(f, vec3(50, 0, 0), vec3(30, 0, 0), DT)
  assertEq(f.vel.x <= before + 1e-9, true)
end)

test("dt of zero or less changes nothing and makes no NaN", function()
  local car = vec3(0, 0, 0)
  local f = flight.arrive(car, seeded(12))
  flight.step(f, car, vec3(0, 0, 0), DT)
  local px, py, pz, vx, vy, vz, orbit = f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.orbit
  for _, dt in ipairs({ 0, -1, 0 / 0 }) do
    flight.step(f, vec3(500, 0, 0), vec3(9, 9, 0), dt)
    assertEq(f.pos.x, px)
    assertEq(f.pos.y, py)
    assertEq(f.pos.z, pz)
    assertEq(f.vel.x, vx)
    assertEq(f.vel.y, vy)
    assertEq(f.vel.z, vz)
    assertEq(f.orbit, orbit)
  end
end)

test("a long frame is clamped to the maximum step", function()
  local car = vec3(0, 0, 0)
  local a = flight.arrive(car, seeded(13))
  local b = flight.arrive(car, seeded(13))
  flight.step(a, car, vec3(0, 0, 0), 5)
  flight.step(b, car, vec3(0, 0, 0), 0.1)
  assertEq(a.pos.x, b.pos.x)
  assertEq(a.vel.x, b.vel.x)
end)

test("target is pure", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(14))
  local orbit = f.orbit
  flight.target(f, car, vec3(0, 0, 0))
  flight.target(f, car, vec3(0, 0, 0))
  assertEq(f.orbit, orbit)
end)

test("seeded generators repeat", function()
  local a, b = flight.seeded(42), flight.seeded(42)
  for _ = 1, 10 do
    local x, y = a(), b()
    assertEq(x, y)
    assertEq(x >= 0 and x < 1, true)
  end
  assertEq(flight.seeded(43)() ~= flight.seeded(42)(), true)
  for _, s in ipairs({ 0 / 0, math.huge, -math.huge }) do
    local g, one = flight.seeded(s), flight.seeded(1)
    for _ = 1, 5 do
      local x = g()
      assertEq(x == x and x >= 0 and x < 1, true)
      assertEq(x, one())
    end
  end
  for _, s in ipairs({ 0, 2147483647 }) do
    local g = flight.seeded(s)
    for _ = 1, 5 do
      local x = g()
      assertEq(x == x and x >= 0 and x < 1, true)
    end
  end
end)

test("arrive and at draw the same side from the same generator", function()
  local car = vec3(100, 200, 10)
  for s = 1, 20 do
    local a = flight.arrive(car, flight.seeded(s))
    local b = flight.at(car, vec3(0, 0, 0), flight.seeded(s))
    assertEq(a.side, b.side)
  end
end)

test("arrive and at take the same bearing from the same generator", function()
  local car = vec3(100, 200, 10)
  for s = 1, 20 do
    local a = flight.arrive(car, flight.seeded(s))
    local b = flight.at(car, vec3(0, 0, 0), flight.seeded(s))
    assertNear(a.orbit, b.orbit, 1e-9)
  end
end)

local function bearingOf(p, c) return math.atan2(p.y - c.y, p.x - c.x) end
local function wrap(d)
  while d > math.pi do d = d - 2 * math.pi end
  while d < -math.pi do d = d + 2 * math.pi end
  return d
end
local function sideRandom(side) return function() return side == 1 and 0.9 or 0.1 end end

test("search circles the spot", function()
  for _, side in ipairs({ -1, 1 }) do
    local car = vec3(0, 0, 0)
    local spot = vec3(500, 300, 20)
    local f = flight.arrive(car, sideRandom(side), vec3(0, 0, 0), spot)
    flight.search(f, spot)
    local prev
    for i = 1, 2400 do
      flight.step(f, car, vec3(0, 0, 0), DT)
      if i * DT >= 60 then
        assertNear(horiz(f.pos, spot), 120, 3, "radius")
        assertNear(f.pos.z - spot.z, 100, 2, "height")
        local b = bearingOf(f.pos, spot)
        if prev then
          local r = wrap(b - prev) / DT
          assertEq(r * side > 0, true, "direction")
          assertNear(math.abs(r), 2 * math.pi / 40, 2 * math.pi / 40 * 0.2, "rate")
        end
        prev = b
      end
    end
  end
end)

test("search ignores the car", function()
  local spot = vec3(500, 300, 20)
  local function run(drive)
    local car = vec3(0, 0, 0)
    local f = flight.arrive(car, seeded(5), vec3(0, 0, 0), spot)
    flight.search(f, spot)
    local out = {}
    for _ = 1, 1200 do
      local vel = drive and vec3(30, 0, 0) or vec3(0, 0, 0)
      car = vec3(car.x + vel.x * DT, car.y, car.z)
      flight.step(f, car, vel, DT)
      out[#out + 1] = f.pos
    end
    return out
  end
  local a, b = run(false), run(true)
  for i = 1, #a do
    assertNear(a[i].x, b[i].x, 1e-9)
    assertNear(a[i].y, b[i].y, 1e-9)
    assertNear(a[i].z, b[i].z, 1e-9)
  end
end)

test("search keeps the limits", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(3), vec3(100, 0, 0))
  for i = 1, 1200 do
    if i == 400 then flight.search(f, vec3(f.spot.x + 500, f.spot.y, f.spot.z)) end
    local before = f.vel
    flight.step(f, car, vec3(0, 0, 0), DT)
    assertEq(len(f.vel) <= 70 + 1e-6, true, "speed")
    assertEq(dist(f.vel, before) <= 8 * DT + 1e-6, true, "accel")
  end
end)

test("a guided spot is circled while it moves", function()
  for _, side in ipairs({ -1, 1 }) do
    local car = vec3(0, 0, 0)
    local spot = vec3(0, 0, 0)
    local f = flight.at(car, vec3(0, 0, 0), sideRandom(side), spot)
    local prev
    for i = 1, 2400 do
      spot = vec3(spot.x + 30 * DT, spot.y, spot.z)
      f.spot = vec3(spot.x, spot.y, spot.z)
      f.spotVel = vec3(30, 0, 0)
      car = vec3(spot.x, spot.y, spot.z)
      flight.step(f, car, vec3(30, 0, 0), DT)
      if i * DT >= 60 then
        assertNear(horiz(f.pos, spot), 120, 3, "radius")
        local b = bearingOf(f.pos, spot)
        if prev then assertEq(wrap(b - prev) * side > 0, true, "direction") end
        prev = b
      end
    end
  end
end)

test("a car jump moves the spot", function()
  local function build()
    local car = vec3(0, 0, 0)
    local spot = vec3(300, 100, 0)
    local f = flight.at(car, vec3(0, 0, 0), seeded(9), spot)
    for _ = 1, 100 do flight.step(f, car, vec3(0, 0, 0), DT) end
    return f
  end
  local a, b = build(), build()
  local ca, cb = vec3(0, 0, 0), vec3(2000, 300, 40)
  flight.step(a, ca, vec3(0, 0, 0), DT)
  flight.step(b, cb, vec3(0, 0, 0), DT)
  assertNear(b.spot.x - a.spot.x, 2000, 1e-9)
  assertNear(b.spot.y - a.spot.y, 300, 1e-9)
  assertNear(b.spot.z - a.spot.z, 40, 1e-9)
  assertNear(b.pos.x - b.spot.x, a.pos.x - a.spot.x, 1e-9)
  assertNear(b.pos.y - b.spot.y, a.pos.y - a.spot.y, 1e-9)
  assertNear(b.pos.z - b.spot.z, a.pos.z - a.spot.z, 1e-9)
end)

test("arrive at a spot 2 km from the car doesn't move the spot or the helicopter on the first step", function()
  local car = vec3(0, 0, 0)
  local spot = vec3(2000, 0, 0)
  local f = flight.arrive(car, seeded(4), vec3(0, 0, 0), spot)
  flight.search(f, spot)
  assertEq(f.lastCar.x, 0)
  assertEq(f.lastCar.y, 0)
  assertEq(f.lastCar.z, 0)
  local before = f.pos
  flight.step(f, car, vec3(0, 0, 0), DT)
  assertNear(f.spot.x, 2000, 1e-9)
  assertNear(f.spot.y, 0, 1e-9)
  assertEq(dist(f.pos, before) <= 70 * DT, true)
end)

test("arrive with a spot starts 300 m out from it", function()
  local car = vec3(0, 0, 0)
  local spot = vec3(1000, -400, 15)
  local f = flight.arrive(car, flight.seeded(7), vec3(0, 0, 0), spot)
  local g = flight.arrive(car, flight.seeded(7))
  assertNear(horiz(f.pos, spot), 300, 1e-6)
  assertNear(f.pos.z - spot.z, 120, 1e-6)
  assertEq(len(f.vel), 0)
  assertEq(f.side, g.side)
end)

test("follow after a search starts the circle at the helicopter's bearing", function()
  local car = vec3(0, 0, 0)
  local spot = vec3(200, 0, 0)
  local f = flight.arrive(car, seeded(6), vec3(0, 0, 0), spot)
  flight.search(f, spot)
  for _ = 1, 600 do flight.step(f, car, vec3(0, 0, 0), DT) end
  local g = { pos = f.pos, vel = f.vel, side = f.side, headingX = 1, headingY = 0,
    spot = f.spot, spotVel = f.spotVel, searchAngle = f.searchAngle, lastCar = f.lastCar }
  flight.follow(f, car, vec3(0, 0, 0))
  assertEq(f.spot, nil)
  assertEq(f.spotVel, nil)
  assertEq(f.mode, "circle")
  local t = flight.target(f, car, vec3(0, 0, 0))
  assertNear(wrap(bearingOf(t, car) - bearingOf(f.pos, car)), 0, 1e-9)
  flight.follow(g, car, vec3(20, 0, 0))
  assertEq(g.mode, "follow")
end)

test("follow after search returns to trailing", function()
  local car = vec3(0, 0, 0)
  local spot = vec3(200, 0, 0)
  local f = flight.arrive(car, seeded(6), vec3(0, 0, 0), spot)
  flight.search(f, spot)
  for _ = 1, 400 do flight.step(f, car, vec3(0, 0, 0), DT) end
  local vel = vec3(30, 0, 0)
  flight.follow(f, car, vel)
  car = runSteady(f, car, vel, 60)
  assertEq(dist(f.pos, flight.target(f, car, vel)) <= 3, true)
end)

test("leaving while searching adds no circle velocity", function()
  local car = vec3(0, 0, 0)
  local spot = vec3(0, 0, 0)
  local a = flight.at(car, vec3(0, 0, 0), seeded(8), spot)
  local b = flight.at(car, vec3(0, 0, 0), seeded(8))
  b.pos = vec3(a.pos.x, a.pos.y, a.pos.z)
  for _ = 1, 100 do flight.step(a, car, vec3(0, 0, 0), DT) end
  b.pos = vec3(a.pos.x, a.pos.y, a.pos.z)
  b.vel = vec3(a.vel.x, a.vel.y, a.vel.z)
  flight.leave(a, car, seeded(2))
  flight.leave(b, car, seeded(2))
  for _ = 1, 100 do
    flight.step(a, car, vec3(0, 0, 0), DT)
    flight.step(b, car, vec3(0, 0, 0), DT)
    assertNear(a.pos.x, b.pos.x, 1e-9)
    assertNear(a.pos.y, b.pos.y, 1e-9)
    assertNear(a.pos.z, b.pos.z, 1e-9)
  end
end)

test("at with a spot starts on its circle", function()
  local car = vec3(10, 20, 0)
  local spot = vec3(400, 100, 5)
  for s = 1, 10 do
    local f = flight.at(car, vec3(0, 0, 0), flight.seeded(s), spot)
    local g = flight.at(car, vec3(0, 0, 0), flight.seeded(s))
    assertNear(horiz(f.pos, spot), 120, 1e-6)
    assertNear(f.pos.z - spot.z, 100, 1e-6)
    assertEq(len(f.vel), 0)
    assertEq(f.side, g.side)
    assertEq(f.lastCar.x, 10)
  end
end)

test("jumpOf reports a jump over 30 m in 3D", function()
  assertEq(flight.jumpOf(nil, vec3(5, 5, 5)), nil)
  assertEq(flight.jumpOf(vec3(0, 0, 0), vec3(29, 0, 0)), nil)
  local x, y, z = flight.jumpOf(vec3(0, 0, 0), vec3(31, 0, 0))
  assertEq(x, 31); assertEq(y, 0); assertEq(z, 0)
  x, y, z = flight.jumpOf(vec3(0, 0, 0), vec3(0, 0, 31))
  assertEq(x, 0); assertEq(y, 0); assertEq(z, 31)
  assertEq(flight.jumpOf(vec3(0, 0, 0), vec3(20, 20, 10)), nil)
end)

test("tracking settles 40 m back, 60 m to the side, 100 m up", function()
  for _, side in ipairs({ -1, 1 }) do
    local random = function() return side == 1 and 0.9 or 0.1 end
    local car = vec3(0, 0, 0)
    local f = flight.at(car, vec3(30, 0, 0), random)
    car = runSteady(f, car, vec3(30, 0, 0), 60)
    assertNear(f.pos.x - car.x, -40, 3)
    assertNear(f.pos.y - car.y, 60 * side, 3)
    assertNear(f.pos.z - car.z, 100, 3)
  end
end)

test("a stopped car is circled at 80 m and a search spot at 120 m", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(3))
  assertNear(horiz(f.pos, car), 80, 1e-9)
  assertNear(f.pos.z - car.z, 100, 2)
  local spot = vec3(500, 0, 0)
  local g = flight.at(car, vec3(0, 0, 0), seeded(3), spot)
  assertNear(horiz(g.pos, spot), 120, 1e-9)
  assertNear(g.pos.z - spot.z, 100, 2)
end)

test("arrive starts 300 m out and 120 m up; leave aims 600 m out and 150 m up", function()
  local car = vec3(100, 200, 10)
  local f = flight.arrive(car, seeded(3))
  assertNear(horiz(f.pos, car), 300, 1e-6)
  assertNear(f.pos.z - car.z, 120, 1e-6)
  flight.leave(f, car, seeded(4))
  assertNear(horiz(f.leaving, car), 600, 1e-6)
  assertNear(f.leaving.z - car.z, 150, 1e-6)
end)

test("the new heights keep the limits", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(30, 0, 0), seeded(5))
  local vel = vec3(30, 0, 0)
  for i = 1, 2400 do
    local a = i * DT < 20 and 0 or math.min(math.pi / 2, (i * DT - 20) * 0.3)
    vel = vec3(30 * math.cos(a), 30 * math.sin(a), 0)
    car = vec3(car.x + vel.x * DT, car.y + vel.y * DT, 0)
    local before = f.vel
    flight.step(f, car, vel, DT)
    assertEq(len(f.vel) <= 70 + 1e-6, true, "speed")
    assertEq(dist(f.vel, before) <= 8 * DT + 1e-6, true, "accel")
  end
end)

test("a lead is followed like a car", function()
  for _, side in ipairs({ -1, 1 }) do
    local random = function() return side == 1 and 0.9 or 0.1 end
    local lead = vec3(0, 0, 0)
    local f = flight.at(lead, vec3(0, 0, 0), random)
    local car = vec3(0, 0, 0)
    local vel = vec3(45, 0, 0)
    for _ = 1, 1200 do
      lead = vec3(lead.x + vel.x * DT, lead.y, lead.z)
      flight.lead(f, lead, vel)
      flight.step(f, car, vec3(0, 0, 0), DT)
    end
    assertNear(f.pos.x - lead.x, -40, 3)
    assertNear(f.pos.y - lead.y, 60 * side, 3)
    assertNear(f.pos.z - lead.z, 100, 3)
    assertEq(f.spot, nil)
  end
end)

test("a lead that jumps 1 km keeps the limits", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(6))
  local lead = vec3(0, 0, 0)
  local vel = vec3(30, 0, 0)
  for i = 1, 1200 do
    lead = vec3(lead.x + vel.x * DT + (i == 600 and 1000 or 0), lead.y, lead.z)
    flight.lead(f, lead, vel)
    local before = f.vel
    flight.step(f, car, vec3(0, 0, 0), DT)
    assertEq(len(f.vel) <= 70 + 1e-6, true, "speed")
    assertEq(dist(f.vel, before) <= 8 * DT + 1e-6, true, "accel")
  end
end)

test("departure from a moving lead follows the fly-away with no lead velocity added", function()
  local car, parked = vec3(0, 0, 0), vec3(0, 0, 0)
  local lead, vel = vec3(1000, 200, 15), vec3(0, 45, 0)
  local f = flight.at(car, parked, seeded(8))
  local reference = flight.at(car, parked, seeded(8))
  for _ = 1, 600 do
    lead = vec3(lead.x, lead.y + vel.y * DT, lead.z)
    flight.lead(f, lead, vel)
    flight.step(f, car, parked, DT)
  end
  reference.pos, reference.vel = f.pos, f.vel
  flight.leave(reference, lead, seeded(2))
  flight.leave(f, lead, seeded(2))
  for _ = 1, math.floor(flight.DEPART_SECONDS / DT) do
    flight.step(f, car, parked, DT)
    flight.step(reference, car, parked, DT)
    assertNear(dist(f.pos, reference.pos), 0, 1e-9)
    assertNear(dist(f.vel, reference.vel), 0, 1e-9)
  end
end)

test("a car jump shifts the lead", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(6))
  flight.lead(f, vec3(10, 20, 0), vec3(30, 0, 0))
  flight.step(f, vec3(5000, 0, 0), vec3(0, 0, 0), DT)
  assertNear(f.lead.x, 5010, 1e-9)
  assertNear(f.lead.y, 20, 1e-9)
end)

test("search and follow clear the lead", function()
  local car = vec3(0, 0, 0)
  local f = flight.at(car, vec3(0, 0, 0), seeded(6))
  flight.lead(f, vec3(10, 20, 0), vec3(30, 0, 0))
  flight.search(f, vec3(50, 50, 0))
  assertEq(f.lead, nil)
  assertEq(f.leadVel, nil)
  flight.lead(f, vec3(10, 20, 0), vec3(30, 0, 0))
  assertEq(f.spot, nil)
  flight.follow(f, car, vec3(0, 0, 0))
  assertEq(f.lead, nil)
  assertEq(f.leadVel, nil)
end)
