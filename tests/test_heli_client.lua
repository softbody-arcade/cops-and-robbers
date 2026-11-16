dofile("tests/env_stubs.lua")
local fake, heli, state
local pos

local function load()
  fake = fakeEnvironment()
  local make = _G.createObject
  _G.createObject = function(class)
    local obj = make(class)
    obj.class = class
    function obj:setPosition(p) self.pos = { x = p.x, y = p.y, z = p.z } end
    return obj
  end
  for _, n in ipairs({ "copsAndRobbers/heli", "copsAndRobbers/shelter" }) do package.loaded[n] = nil end
  heli = require("copsAndRobbers/heli")
  state = heli.new()
  pos = vec3(10, 20, 5)
end

local target = { getPosition = function() return pos end }
local function open() return nil end
local function roofAll() return 1 end

test("the first cover check reports not covered, then only changes", function()
  load()
  assertEq(heli.coverTick(state, 1, target, open), false)
  assertEq(heli.coverTick(state, 2, target, open), nil)
  assertEq(heli.coverTick(state, 3, target, open), nil)
end)

test("cover checks are spaced by the interval", function()
  load()
  assertEq(heli.coverTick(state, 1, target, open), false)
  assertEq(heli.coverTick(state, 1.1, target, roofAll), nil)
  assertEq(heli.coverTick(state, 1.3, target, roofAll), nil)
  assertEq(heli.coverTick(state, 1.4, target, roofAll), nil)
  assertEq(heli.coverTick(state, 1.6, target, roofAll), true)
end)

test("cover needs two equal checks to switch and is resent after a reset", function()
  load()
  assertEq(heli.coverTick(state, 1, target, open), false)
  assertEq(heli.coverTick(state, 2, target, roofAll), nil)
  assertEq(heli.coverTick(state, 3, target, roofAll), true)
  assertEq(heli.coverTick(state, 4, target, roofAll), nil)
  heli.resetCover(state)
  assertEq(heli.coverTick(state, 5, target, roofAll), true)
end)

test("the cover check is cast from above the car", function()
  load()
  local z
  heli.coverTick(state, 1, target, function(p) z = p.z end)
  assertEq(z, 5 + heli.COVER_HEIGHT)
end)

test("the searchlight exists only while tracking at night", function()
  load()
  heli.set(state, { phase = "tracking", seconds = 30 }, 0)
  assertEq(heli.tracking(state), true)
  heli.lightTick(state, target, false)
  assertEq(fake.objects["cnr_heli_light"], nil)
  heli.lightTick(state, target, true)
  assertEq(fake.objects["cnr_heli_light"].class, "SpotLight")
  heli.lightTick(state, target, true)
  assertEq(fake.objects["cnr_heli_light"] ~= nil, true)
  heli.lightTick(state, target, false, 1)
  assertEq(fake.objects["cnr_heli_light"] ~= nil, true)
  heli.lightTick(state, target, false, 1 + heli.FADE_SECONDS + 0.1)
  assertEq(fake.objects["cnr_heli_light"], nil)
end)

test("the searchlight goes when the phase ends or on clear", function()
  load()
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true)
  heli.set(state, { phase = "searching" }, 1)
  heli.lightTick(state, target, true)
  assertEq(fake.objects["cnr_heli_light"], nil)
  heli.set(state, { phase = "tracking" }, 2)
  heli.lightTick(state, target, true)
  assertEq(fake.objects["cnr_heli_light"] ~= nil, true)
  heli.clear(state)
  assertEq(fake.objects["cnr_heli_light"], nil)
  assertEq(heli.tracking(state), false)
  heli.lightTick(state, nil, true)
  assertEq(fake.objects["cnr_heli_light"], nil)
end)

test("the searchlight follows the target", function()
  load()
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true)
  assertEq(fake.objects["cnr_heli_light"].pos.z, 5 + heli.LIGHT_HEIGHT)
  pos = vec3(30, 40, 7)
  heli.lightTick(state, target, true, 0)
  local p = fake.objects["cnr_heli_light"].pos
  assertEq(p.x, 30); assertEq(p.y, 42); assertEq(p.z, 47)
end)

test("set stores the phase, reason and end time", function()
  load()
  heli.set(state, { phase = "grounded", reason = "fog", seconds = 5 }, 10)
  assertEq(state.phase, "grounded"); assertEq(state.reason, "fog"); assertEq(state.endsAt, 15)
  heli.set(state, nil, 20)
  assertEq(state.phase, nil)
end)

local function seeded(seed)
  local x = seed
  return function()
    x = (x * 1103515245 + 12345) % 2147483648
    return x / 2147483648
  end
end

local function horiz(a, c) return math.sqrt((a.x - c.x) ^ 2 + (a.y - c.y) ^ 2) end

test("the light hovers 40 m up within the drift of the car", function()
  load()
  local car = vec3(10, 20, 5)
  for _, t in ipairs({ 0, 1, 3.7, 9, 20, 100 }) do
    local l = heli.lightPose(car, t)
    assertEq(l.z, 45)
    assertEq(horiz(l, car) <= heli.HOVER_DRIFT * math.sqrt(2) + 1e-9, true)
  end
end)

test("the aim stays near a car that drives and turns randomly", function()
  load()
  local rnd = seeded(7)
  local aim = heli.newAim()
  local car, heading, speed, clock, worst = { x = 0, y = 0, z = 0 }, 0, 20, 0, 0
  for _ = 1, 600 do
    clock = clock + 0.1
    if rnd() < 0.1 then speed = rnd() * 40 end
    heading = heading + (rnd() - 0.5) * 1.5
    car.x, car.y = car.x + math.cos(heading) * speed * 0.1, car.y + math.sin(heading) * speed * 0.1
    worst = math.max(worst, horiz(heli.aimStep(aim, car, 0.1, clock, rnd), car))
  end
  assertEq(worst <= heli.AIM_MAX_OFFSET + 0.53, true, tostring(worst))
end)

test("a sudden stop pushes the aim ahead and it recovers within 1.5 s", function()
  load()
  local rnd = seeded(3)
  local aim = heli.newAim()
  local car, clock = { x = 0, y = 0, z = 0 }, 0
  for _ = 1, 50 do
    clock = clock + 0.05
    car.x = car.x + 30 * 0.05
    heli.aimStep(aim, car, 0.05, clock, rnd)
  end
  clock = clock + 0.05
  local a = heli.aimStep(aim, car, 0.05, clock, rnd)
  assertEq(a.x - car.x > 1, true)
  local last
  for _ = 1, 30 do
    clock = clock + 0.05
    last = heli.aimStep(aim, car, 0.05, clock, rnd)
  end
  assertEq(horiz(last, car) <= heli.NUDGE_RADIUS + 0.53, true)
end)

test("nudge goals change every 1.5 to 3 s inside the radius", function()
  load()
  local rnd = seeded(11)
  local aim = heli.newAim()
  local car, clock = { x = 0, y = 0, z = 0 }, 0
  local lastGoal, changedAt, intervals = nil, 0, {}
  for _ = 1, 1500 do
    clock = clock + 0.02
    heli.aimStep(aim, car, 0.02, clock, rnd)
    local key = aim.goal.x .. "," .. aim.goal.y
    assertEq(math.sqrt(aim.goal.x ^ 2 + aim.goal.y ^ 2) <= heli.NUDGE_RADIUS + 1e-9, true)
    if key ~= lastGoal then
      if lastGoal then intervals[#intervals + 1] = clock - changedAt end
      lastGoal, changedAt = key, clock
    end
  end
  assertEq(#intervals >= 8, true)
  for _, d in ipairs(intervals) do
    assertEq(d >= heli.NUDGE_MIN - 0.021 and d <= heli.NUDGE_MAX + 0.021, true, tostring(d))
  end
end)

test("a 50 m jump resets the aim offset", function()
  load()
  local rnd = seeded(5)
  local aim = heli.newAim()
  local car, clock = { x = 0, y = 0, z = 0 }, 0
  for _ = 1, 20 do
    clock = clock + 0.05
    car.x = car.x + 1.5
    heli.aimStep(aim, car, 0.05, clock, rnd)
  end
  assertEq(math.abs(aim.offset.x) > 0.01, true)
  car.x = car.x + 50
  clock = clock + 0.05
  heli.aimStep(aim, car, 0.05, clock, rnd)
  assertEq(math.abs(aim.offset.x) < 0.1, true)
end)

test("the light is aimed on every tick", function()
  load()
  local n = 0
  _G.quatFromDir = function(dir)
    n = n + 1
    return { x = dir.x, y = dir.y, z = dir.z, w = 1 }
  end
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true, 0)
  heli.lightTick(state, target, true, 3)
  local rot = fake.objects["cnr_heli_light"].fields.rotation
  _G.quatFromDir = nil
  assertEq(n, 2)
  assertEq(type(rot), "string")
end)

local LIGHT = "cnr_heli_light"

local function night(clock, ph, extra)
  heli.set(state, { phase = ph }, clock)
  heli.lightTick(state, target, true, clock)
end

local function run(from, to, step)
  local c = from
  while c < to do
    c = c + step
    heli.lightTick(state, target, true, c)
  end
  return c
end

local function dist3(p, c)
  return math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 + (p.z - c.z) ^ 2)
end

test("a helicopter that just arrived flies in from 300 m and sweeps onto the car", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  assertEq(fake.objects[LIGHT], nil)
  night(1, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  local p = obj.pos
  assertEq(math.abs(horiz(p, pos) - heli.APPROACH_DISTANCE) < 15, true)
  assertEq(math.abs(p.z - pos.z - heli.APPROACH_HEIGHT) < 1, true)
  assertEq(math.abs(horiz({ x = state.aim.offset.x, y = state.aim.offset.y }, { x = 0, y = 0 }) - heli.AIM_SWEEP_OFFSET) < 1, true)
  run(1, 1 + heli.APPROACH_SECONDS + 0.5, 0.05)
  assertEq(horiz(obj.pos, pos) <= heli.HOVER_DRIFT * math.sqrt(2) + 1e-6, true)
  assertEq(math.abs(obj.pos.z - pos.z - heli.LIGHT_HEIGHT) < 1e-6, true)
  run(1 + heli.APPROACH_SECONDS + 0.5, 20, 0.05)
  assertEq(math.sqrt(state.aim.offset.x ^ 2 + state.aim.offset.y ^ 2) <= heli.NUDGE_RADIUS + 0.3, true)
end)

test("a departing helicopter moves away, fades and the light goes after 8 s", function()
  load()
  state.random = seeded(4)
  night(0, "tracking")
  run(0, 5, 0.05)
  night(5, "refuelling")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  local c = run(5, 5 + 4, 0.05)
  assertEq(dist3(obj.pos, pos) > 60, true)
  c = run(c, 5 + 7.5, 0.05)
  assertEq(tonumber(obj.fields.brightness) < heli.BRIGHTNESS * 0.2, true)
  assertEq(fake.objects[LIGHT] ~= nil, true)
  run(c, 5 + heli.DEPART_SECONDS + 0.2, 0.05)
  assertEq(fake.objects[LIGHT], nil)
end)

test("going under cover cuts the light at once", function()
  load()
  night(0, "tracking")
  run(0, 3, 0.05)
  night(3, "searching")
  assertEq(fake.objects[LIGHT], nil)
end)

test("a re-found runner fades the light in with the aim off the car", function()
  load()
  state.random = seeded(9)
  night(0, "tracking")
  night(1, "searching")
  night(5, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  assertEq(math.abs(horiz({ x = state.aim.offset.x, y = state.aim.offset.y }, { x = 0, y = 0 }) - heli.FADEIN_AIM_OFFSET) < 1, true)
  heli.lightTick(state, target, true, 5.5)
  assertEq(tonumber(obj.fields.brightness) < heli.BRIGHTNESS, true)
  assertEq(tonumber(obj.fields.brightness) > 0, true)
  run(5.5, 7, 0.05)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  assertEq(horiz(obj.pos, pos) <= heli.HOVER_DRIFT * math.sqrt(2) + 1e-6, true)
end)

test("clear deletes the light at once mid-approach and mid-depart", function()
  load()
  night(0, "arriving")
  night(1, "tracking")
  run(1, 3, 0.05)
  heli.clear(state)
  assertEq(fake.objects[LIGHT], nil)
  night(10, "tracking")
  night(11, "refuelling")
  run(11, 13, 0.05)
  assertEq(fake.objects[LIGHT] ~= nil, true)
  heli.clear(state)
  assertEq(fake.objects[LIGHT], nil)
end)

test("by day no light is created in any phase", function()
  load()
  for i, ph in ipairs({ "arriving", "tracking", "searching", "tracking", "refuelling", "tracking" }) do
    heli.set(state, { phase = ph }, i)
    heli.lightTick(state, target, false, i)
    assertEq(fake.objects[LIGHT], nil)
  end
end)

test("a light created on a fast car does not kick the aim", function()
  load()
  state.random = seeded(6)
  heli.set(state, { phase = "tracking" }, 0)
  local c = 0
  for _ = 1, 10 do
    c = c + 0.05
    pos = vec3(pos.x + 1.5, pos.y, pos.z)
    heli.lightTick(state, target, true, c)
    assertEq(math.sqrt(state.aim.offset.x ^ 2 + state.aim.offset.y ^ 2) <= heli.NUDGE_RADIUS + 0.2, true)
  end
end)

test("a negative step changes nothing", function()
  load()
  local aim = heli.newAim()
  local car = { x = 0, y = 0, z = 0 }
  heli.aimStep(aim, car, 0.05, 1, seeded(1))
  local ox, oy, vx = aim.offset.x, aim.offset.y, aim.vel.x
  heli.aimStep(aim, car, -0.5, 1.01, seeded(1))
  assertEq(aim.offset.x, ox); assertEq(aim.offset.y, oy); assertEq(aim.vel.x, vx)
end)
