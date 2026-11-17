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
    assertNear(f.pos.x - car.x, -25, 3)
    assertNear(f.pos.y - car.y, 15 * side, 3)
    assertNear(f.pos.z - car.z, 50, 3)
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
        assertNear(h, 30, 2, "radius")
        assertNear(f.pos.z - car.z, 50, 2, "height")
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
  assertNear(f.pos.z - car.z, 60, 1e-6)
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
    assertNear(horiz(f.leaving, car), 400, 1e-6)
    assertNear(f.leaving.z, 80, 1e-6)
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
  assertNear(horiz(slow.pos, car), 30, 1e-9)
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
