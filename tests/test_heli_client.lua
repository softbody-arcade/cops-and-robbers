dofile("tests/env_stubs.lua")
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
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
  for _, n in ipairs({ "copsAndRobbers/heli", "copsAndRobbers/shelter", "copsAndRobbers/heliFlight", "copsAndRobbers/beam" }) do package.loaded[n] = nil end
  heli = require("copsAndRobbers/heli")
  state = heli.new()
  pos = vec3(10, 20, 5)
end

local target = { getPosition = function() return pos end }
local function open() return nil end
local function roofAll() return 1 end

local function seeded(seed)
  local x = seed
  return function()
    x = (x * 1103515245 + 12345) % 2147483648
    return x / 2147483648
  end
end

local function horiz(a, c) return math.sqrt((a.x - c.x) ^ 2 + (a.y - c.y) ^ 2) end

local function dist3(p, c)
  return math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 + (p.z - c.z) ^ 2)
end

local function copyPos(p) return { x = p.x, y = p.y, z = p.z } end

local function aimOff() return math.sqrt(state.aim.offset.x ^ 2 + state.aim.offset.y ^ 2) end

local function atFlight(obj)
  local f = state.flight.pos
  assertEq(obj.pos.x, f.x); assertEq(obj.pos.y, f.y); assertEq(obj.pos.z, f.z)
  assertEq(state.lightPos.x, f.x); assertEq(state.lightPos.y, f.y); assertEq(state.lightPos.z, f.z)
end

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

test("the searchlight casts shadows, so a bridge deck or tunnel roof blocks the beam", function()
  load()
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true, 0)
  assertEq(fake.objects["cnr_heli_light"].fields.castShadows, "true")
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

test("the searchlight hangs from the helicopter, which follows the target", function()
  load()
  state.random = seeded(1)
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true, 0)
  local obj = fake.objects["cnr_heli_light"]
  atFlight(obj)
  local c = 0
  for _ = 1, 200 do
    c = c + 0.05
    pos = vec3(pos.x + 1, pos.y, pos.z)
    heli.lightTick(state, target, true, c)
    atFlight(obj)
    assertEq(dist3(obj.pos, pos) < 100, true, tostring(dist3(obj.pos, pos)))
  end
  assertEq(pos.x - obj.pos.x > 0, true)
end)

test("set stores the phase, reason and end time", function()
  load()
  heli.set(state, { phase = "grounded", reason = "fog", seconds = 5 }, 10)
  assertEq(state.phase, "grounded"); assertEq(state.reason, "fog"); assertEq(state.endsAt, 15)
  heli.set(state, nil, 20)
  assertEq(state.phase, nil)
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

test("a helicopter that just arrived flies in from 300 m and sweeps onto the car", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  assertEq(fake.objects[LIGHT], nil)
  assertEq(state.flight, nil)
  night(1, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  atFlight(obj)
  local p = obj.pos
  assertEq(math.abs(horiz(p, pos) - heli.APPROACH_DISTANCE) < 15, true)
  assertEq(math.abs(p.z - pos.z - heli.APPROACH_HEIGHT) < 1, true)
  assertNear(horiz(state.aimPos, pos), heli.AIM_SWEEP_OFFSET, 1)
  assertEq(tonumber(obj.fields.brightness) < heli.BRIGHTNESS * 0.05, true, obj.fields.brightness)
  run(1, 1 + heli.APPROACH_SECONDS / 2, 0.05)
  assertNear(tonumber(obj.fields.brightness), heli.BRIGHTNESS / 2, heli.BRIGHTNESS * 0.02)
  run(1 + heli.APPROACH_SECONDS / 2, 1 + heli.APPROACH_SECONDS + 0.5, 0.05)
  atFlight(obj)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  assertEq(horiz(obj.pos, pos) < 100, true, tostring(horiz(obj.pos, pos)))
  run(1 + heli.APPROACH_SECONDS + 0.5, 20, 0.05)
  assertEq(aimOff() <= heli.NUDGE_RADIUS + 0.3, true, tostring(aimOff()))
end)

local function departs(obj, c, from, fieldFades)
  local f, last, nextCheck = state.flight, dist3(obj.pos, pos), from + 1
  assertEq(f.leaving ~= nil, true)
  while fake.objects[LIGHT] do
    atFlight(obj)
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    if fake.objects[LIGHT] then
      assertEq(state.flight, f)
      if c >= nextCheck then
        assertEq(dist3(obj.pos, pos) > last, true, tostring(c))
        last, nextCheck = dist3(obj.pos, pos), nextCheck + 1
      end
      if c >= from + 7.5 then
        assertEq(state.fx.bright < 0.2, true)
        if fieldFades then assertEq(tonumber(obj.fields.brightness) < heli.BRIGHTNESS * 0.2, true) end
      end
    end
  end
  assertEq(state.flight, nil)
  assertNear(c, from + heli.DEPART_SECONDS, 0.051)
  return c
end

test("a departing helicopter flies away with the light, which fades and goes with the flight after 8 s", function()
  load()
  state.random = seeded(4)
  night(0, "tracking")
  run(0, 5, 0.05)
  night(5, "refuelling")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  local d0 = dist3(obj.pos, pos)
  departs(obj, 5, 5, true)
  assertEq(dist3(obj.pos, pos) > d0 + 150, true, tostring(dist3(obj.pos, pos)))
end)

test("going under cover cuts the light at once", function()
  load()
  night(0, "tracking")
  run(0, 3, 0.05)
  night(3, "searching")
  assertEq(fake.objects[LIGHT], nil)
end)

test("a re-found runner gets the light at once at full brightness, the aim 8 m off then swinging in", function()
  load()
  state.random = seeded(9)
  night(0, "tracking")
  night(1, "searching")
  assertEq(fake.objects[LIGHT], nil)
  night(5, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  atFlight(obj)
  assertEq(math.abs(aimOff() - heli.REFOUND_AIM_OFFSET) < 1e-6, true)
  run(5, 5.5, 0.05)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  assertEq(aimOff() < heli.REFOUND_AIM_OFFSET - 0.5, true, tostring(aimOff()))
  assertEq(aimOff() > 2, true, tostring(aimOff()))
  run(5.5, 9, 0.05)
  assertEq(aimOff() <= heli.NUDGE_RADIUS + 0.3, true, tostring(aimOff()))
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
end)

test("clear deletes the light at once mid-approach and mid-depart", function()
  load()
  night(0, "arriving")
  night(1, "tracking")
  run(1, 3, 0.05)
  assertEq(state.flight ~= nil, true)
  heli.clear(state)
  assertEq(fake.objects[LIGHT], nil)
  assertEq(state.flight, nil)
  night(10, "tracking")
  night(11, "refuelling")
  run(11, 13, 0.05)
  assertEq(fake.objects[LIGHT] ~= nil, true)
  assertEq(state.flight.leaving ~= nil, true)
  heli.clear(state)
  assertEq(fake.objects[LIGHT], nil)
  assertEq(state.flight, nil)
  assertEq(state.lightPos, nil)
  assertEq(state.aimPos, nil)
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

test("with no target a leftover light is looked for about once a second and deleted", function()
  load()
  local finds = 0
  local find = scenetree.findObject
  scenetree.findObject = function(name)
    finds = finds + 1
    return find(name)
  end
  for i = 1, 40 do heli.lightTick(state, nil, false, i * 0.05) end
  assertEq(finds <= 2, true, tostring(finds))
  createObject("SpotLight"):registerObject(LIGHT)
  for i = 41, 70 do heli.lightTick(state, nil, false, i * 0.05) end
  assertEq(fake.objects[LIGHT], nil)
end)

test("a refuel during the fly-in flies away from where the light is, without a jump", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  night(1, "tracking")
  local c = run(1, 3, 0.05)
  local obj = fake.objects[LIGHT]
  local prev = copyPos(obj.pos)
  assertEq(dist3(prev, pos) > 100, true)
  c = c + 0.05
  night(c, "refuelling")
  local worst = dist3(obj.pos, prev)
  while fake.objects[LIGHT] do
    atFlight(obj)
    prev = copyPos(obj.pos)
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    worst = math.max(worst, dist3(obj.pos, prev))
  end
  assertEq(worst <= 70 * 0.05 + 1e-9, true, tostring(worst))
  assertEq(state.flight, nil)
  assertEq(c <= 3.05 + heli.DEPART_SECONDS + 0.1, true)
end)

test("back from a short refuel the helicopter turns back from where it is, brightening, the aim point not jumping", function()
  load()
  state.random = seeded(4)
  night(0, "tracking")
  run(0, 2, 0.05)
  night(2, "refuelling")
  local c = run(2, 9, 0.05)
  local obj = fake.objects[LIGHT]
  local f = state.flight
  local before, b0, aimBefore = copyPos(obj.pos), tonumber(obj.fields.brightness), copyPos(state.aimPos)
  assertEq(b0 < heli.BRIGHTNESS * 0.5, true)
  assertEq(horiz(aimBefore, pos) > 30, true, tostring(horiz(aimBefore, pos)))
  c = c + 0.05
  night(c, "tracking")
  assertEq(fake.objects[LIGHT], obj)
  assertEq(state.flight, f)
  assertEq(f.leaving, nil)
  atFlight(obj)
  assertEq(dist3(obj.pos, before) <= 70 * 0.05 + 1e-9, true, tostring(dist3(obj.pos, before)))
  assertEq(tonumber(obj.fields.brightness) <= b0 + heli.BRIGHTNESS * 0.05, true, obj.fields.brightness)
  assertEq(tonumber(obj.fields.brightness) >= b0 - 1e-6, true, obj.fields.brightness)
  assertEq(horiz(state.aimPos, aimBefore) < 2, true, tostring(horiz(state.aimPos, aimBefore)))
  local prevAim, worst = copyPos(state.aimPos), 0
  local resumed, stop = c, c + heli.APPROACH_SECONDS + 0.5
  while c < stop do
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    worst = math.max(worst, horiz(state.aimPos, prevAim))
    prevAim = copyPos(state.aimPos)
    atFlight(obj)
    if math.abs(c - resumed - 0.5) < 0.025 then assertEq(horiz(state.aimPos, pos) > 10, true, tostring(horiz(state.aimPos, pos))) end
  end
  assertEq(worst < 5, true, tostring(worst))
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  assertEq(aimOff() < heli.AIM_MAX_OFFSET, true, tostring(aimOff()))
end)

test("going under cover during the fly-in cuts the light at once", function()
  load()
  night(0, "arriving")
  night(1, "tracking")
  run(1, 3, 0.05)
  assertEq(fake.objects[LIGHT] ~= nil, true)
  night(3.05, "searching")
  assertEq(fake.objects[LIGHT], nil)
end)

test("a phase change while the target is missing for a moment is not lost", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  heli.set(state, { phase = "tracking" }, 1)
  heli.lightTick(state, nil, true, 1)
  heli.lightTick(state, target, true, 1.05)
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  assertEq(math.abs(horiz(obj.pos, pos) - heli.APPROACH_DISTANCE) < 15, true, tostring(horiz(obj.pos, pos)))
end)

test("a brightness error does not take the light down", function()
  load()
  state.random = seeded(4)
  night(0, "tracking")
  run(0, 1, 0.05)
  local obj = fake.objects[LIGHT]
  local set = obj.setField
  obj.setField = function(self, name, i, v)
    if name == "brightness" then error("bad field") end
    return set(self, name, i, v)
  end
  night(1, "refuelling")
  local d0 = dist3(obj.pos, pos)
  local c = run(1, 4, 0.05)
  assertEq(fake.objects[LIGHT], obj)
  assertEq(state.failed, nil)
  atFlight(obj)
  assertEq(dist3(obj.pos, pos) > d0, true)
  departs(obj, c, 1)
  assertEq(state.failed, nil)
end)

test("night coming back during the night-end fade fades in from where the light is", function()
  load()
  night(0, "tracking")
  local c = run(0, 1, 0.05)
  local obj = fake.objects[LIGHT]
  for _ = 1, 15 do
    c = c + 0.05
    pos = vec3(pos.x + 1, pos.y, pos.z)
    heli.lightTick(state, target, false, c)
  end
  local before, b0 = copyPos(obj.pos), tonumber(obj.fields.brightness)
  assertEq(b0 > heli.BRIGHTNESS * 0.4 and b0 < heli.BRIGHTNESS * 0.6, true, tostring(b0))
  c = c + 0.05
  heli.lightTick(state, target, true, c)
  assertEq(fake.objects[LIGHT], obj)
  assertEq(tonumber(obj.fields.brightness) >= b0, true, obj.fields.brightness)
  assertEq(state.fx.mode, "fadein")
  atFlight(obj)
  assertEq(dist3(obj.pos, before) <= 70 * 0.05 + 1e-9, true, tostring(dist3(obj.pos, before)))
  run(c, c + heli.FADEIN_SECONDS + 0.1, 0.05)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  atFlight(obj)
end)

test("the light sits at the helicopter through the fly-in, the hover, a night fade and fade-in, and the fly-away", function()
  load()
  state.random = seeded(8)
  night(0, "arriving")
  night(1, "tracking")
  local obj = fake.objects[LIGHT]
  atFlight(obj)
  local c = 1
  local function tick(n, isNight, mode)
    for _ = 1, n do
      c = c + 0.05
      pos = vec3(pos.x + 0.5, pos.y, pos.z)
      heli.lightTick(state, target, isNight, c)
      if fake.objects[LIGHT] then atFlight(obj) end
    end
    if mode then assertEq(state.fx.mode, mode) end
  end
  tick(20, true, "approach")
  tick(200, true, "hover")
  tick(10, false, "fade")
  tick(10, true, "fadein")
  tick(30, true, "hover")
  heli.set(state, { phase = "refuelling" }, c)
  tick(100, true, "depart")
end)

test("under cover the light is cut while the helicopter flies on, and on the way out it is back at once at the helicopter", function()
  load()
  state.random = seeded(12)
  night(0, "tracking")
  local c = run(0, 3, 0.05) + 0.05
  night(c, "searching")
  assertEq(fake.objects[LIGHT], nil)
  local f = state.flight
  assertEq(f ~= nil, true)
  local before = copyPos(f.pos)
  for _ = 1, 40 do
    local prev = copyPos(f.pos)
    c = c + 0.05
    pos = vec3(pos.x + 1, pos.y, pos.z)
    heli.lightTick(state, target, false, c)
    assertEq(fake.objects[LIGHT], nil)
    assertEq(dist3(f.pos, prev) > 0, true)
  end
  assertEq(state.flight, f)
  assertEq(dist3(f.pos, before) > 3, true, tostring(dist3(f.pos, before)))
  c = c + 0.05
  night(c, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  assertEq(state.flight, f)
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  atFlight(obj)
  assertNear(aimOff(), heli.REFOUND_AIM_OFFSET, 1e-6)
end)

test("by day the helicopter still flies: arriving, tracking and refuelling make a flight and never a light, dropped after 8 s", function()
  load()
  state.random = seeded(3)
  local function day(clock, ph)
    if ph then heli.set(state, { phase = ph }, clock) end
    heli.lightTick(state, target, false, clock)
    assertEq(fake.objects[LIGHT], nil)
  end
  day(0, "arriving")
  assertEq(state.flight, nil)
  day(1, "tracking")
  local f = state.flight
  assertEq(f ~= nil, true)
  assertNear(horiz(f.pos, pos), heli.APPROACH_DISTANCE, 1)
  local c = 1
  while c < 6 do
    c = c + 0.05
    day(c)
  end
  assertEq(state.flight, f)
  assertEq(horiz(f.pos, pos) < heli.APPROACH_DISTANCE - 50, true, tostring(horiz(f.pos, pos)))
  c = c + 0.05
  day(c, "refuelling")
  local left = c
  assertEq(f.leaving ~= nil, true)
  while c < left + heli.DEPART_SECONDS - 0.1 do
    c = c + 0.05
    day(c)
    assertEq(state.flight, f)
  end
  while c < left + heli.DEPART_SECONDS + 0.1 do
    c = c + 0.05
    day(c)
  end
  assertEq(state.flight, nil)
end)

test("joining mid-round puts the helicopter on its target point, not 300 m out", function()
  load()
  state.random = seeded(5)
  local flight = require("copsAndRobbers/heliFlight")
  heli.set(state, { phase = "tracking", seconds = 40 }, 0)
  heli.lightTick(state, target, true, 0)
  local f = state.flight
  assertEq(f ~= nil, true)
  assertNear(dist3(f.pos, flight.target(f, pos, vec3(0, 0, 0))), 0, 1e-9)
  assertEq(dist3(f.pos, pos) < 70, true, tostring(dist3(f.pos, pos)))
  local obj = fake.objects[LIGHT]
  assertEq(tonumber(obj.fields.brightness), heli.BRIGHTNESS)
  atFlight(obj)
end)

test("a 2 km car jump moves the helicopter with the car: the light's step matches the one without the jump", function()
  local function drive(jumpAt, withVelocity)
    load()
    state.random = seeded(21)
    local shift, jumping = 0, false
    local car = { getPosition = function() return pos end }
    if withVelocity then
      car.getVelocity = function() return jumping and vec3(15, 0, 0) or vec3(0, 0, 0) end
    end
    heli.set(state, { phase = "tracking" }, 0)
    local out, c = {}, 0
    for i = 0, 60 do
      jumping = i == jumpAt
      if jumping then shift = 2000 end
      pos = vec3(10 + shift, 20, 5)
      heli.lightTick(state, car, true, c)
      local p = fake.objects[LIGHT].pos
      out[i] = { x = p.x - pos.x, y = p.y - pos.y, z = p.z - pos.z }
      c = c + 0.05
    end
    return out
  end
  for _, withVelocity in ipairs({ false, true }) do
    local plain, jumped = drive(nil, withVelocity), drive(40, withVelocity)
    for i = 0, 60 do
      local msg = tostring(withVelocity) .. " " .. i
      assertNear(jumped[i].x, plain[i].x, 1e-9, msg)
      assertNear(jumped[i].y, plain[i].y, 1e-9, msg)
      assertNear(jumped[i].z, plain[i].z, 1e-9, msg)
    end
  end
end)

test("the light's range follows the slant to the car: 130 at 100 m, 120 at 60 m, capped, rewritten past 5 m", function()
  load()
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true, 0)
  local obj = fake.objects[LIGHT]
  local function at(dx, dz)
    state.flight.pos = vec3(pos.x + dx, pos.y, pos.z + dz)
    heli.lightTick(state, target, true, 0)
    return tonumber(obj.fields.range)
  end
  assertEq(at(0, 100), 130)
  assertEq(at(0, 104), 130)
  assertEq(at(60, 0), 120)
  assertEq(at(0, 100.6), 131)
  assertEq(at(0, 1000), 400)
  assertEq(state.lightRange, 400)
end)

test("the range is written when the light is created, even when the stored value already matches", function()
  local function flyIn(stored)
    load()
    state.random = seeded(2)
    night(0, "arriving")
    state.lightRange = stored
    night(1, "tracking")
    return fake.objects[LIGHT]
  end
  local obj = flyIn(nil)
  local want = math.floor(dist3(obj.pos, pos) + 30 + 0.5)
  assertEq(want > 300, true)
  assertEq(tonumber(obj.fields.range), want)
  obj = flyIn(want)
  assertEq(tonumber(obj.fields.range), want)
end)

test("the aim does not slip when the car and the helicopter brake together, and does when the car brakes alone", function()
  local function brake(heliBrakes)
    load()
    local rnd = seeded(13)
    local aim = heli.newAim()
    local car, clock, v, worst = { x = 0, y = 0, z = 0 }, 0, 30, 0
    for i = 1, 100 do
      if i > 40 then v = math.max(0, v - 30 * 0.05) end
      clock = clock + 0.05
      car.x = car.x + v * 0.05
      heli.aimStep(aim, car, 0.05, clock, rnd, vec3(heliBrakes and v or 30, 0, 0))
      worst = math.max(worst, math.sqrt(aim.offset.x ^ 2 + aim.offset.y ^ 2))
    end
    return worst
  end
  local together, alone = brake(true), brake(false)
  assertEq(together <= heli.NUDGE_RADIUS + 0.3, true, tostring(together))
  assertEq(alone > 1, true, tostring(alone))
end)

test("a target with getVelocity gives the helicopter the car's own velocity", function()
  load()
  state.random = seeded(5)
  local moving = { getPosition = function() return pos end, getVelocity = function() return vec3(25, 0, 0) end }
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, moving, true, 0)
  assertEq(state.flight.mode, "follow")
  assertEq(state.flight.vel.x, 25)
  heli.lightTick(state, moving, true, 0.05)
  heli.lightTick(state, moving, true, 0.1)
  assertEq(state.flight.mode, "follow")
end)

test("night ending during the fly-away puts the drift into the aim offset, so the aim point does not jump", function()
  load()
  state.random = seeded(4)
  night(0, "tracking")
  run(0, 2, 0.05)
  night(2, "refuelling")
  local c = run(2, 7, 0.05)
  local aimBefore = copyPos(state.aimPos)
  assertEq(horiz(aimBefore, pos) > 20, true, tostring(horiz(aimBefore, pos)))
  c = c + 0.05
  heli.lightTick(state, target, false, c)
  assertEq(state.fx.mode, "fade")
  assertEq(aimOff() > 20, true, tostring(aimOff()))
  assertEq(horiz(state.aimPos, aimBefore) < 2, true, tostring(horiz(state.aimPos, aimBefore)))
end)

test("a 2 km jump on the refuel's first tick leaves the leaving point 400 m out on the helicopter's side, never over the runner", function()
  for _, gap in ipairs({ 0, 3 }) do
    load()
    state.random = seeded(4)
    night(0, "tracking")
    local c = run(0, 5, 0.05)
    local f = state.flight
    local bx, by = f.pos.x - pos.x, f.pos.y - pos.y
    local bl = math.sqrt(bx * bx + by * by)
    heli.set(state, { phase = "refuelling" }, c)
    for _ = 1, gap do
      c = c + 0.05
      heli.lightTick(state, nil, true, c)
    end
    pos = vec3(pos.x - bx / bl * 2000, pos.y - by / bl * 2000, pos.z)
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    assertEq(state.flight, f)
    local lx, ly = f.leaving.x - pos.x, f.leaving.y - pos.y
    local hx, hy = f.pos.x - pos.x, f.pos.y - pos.y
    local ll, hl = math.sqrt(lx * lx + ly * ly), math.sqrt(hx * hx + hy * hy)
    assertNear(ll, 400, 1e-6, tostring(gap))
    assertNear(f.leaving.z - pos.z, 80, 1e-6, tostring(gap))
    assertEq(hl < 60, true, tostring(hl))
    assertEq((lx * hx + ly * hy) / (ll * hl) >= 0.5 - 1e-9, true, tostring(gap))
    if gap == 0 then
      assertEq(state.fx.mode, "depart")
      assertEq((state.fx.dir.x * hx + state.fx.dir.y * hy) / hl >= 0.5 - 1e-9, true)
    end
    local closest = hl
    while state.flight do
      c = c + 0.05
      heli.lightTick(state, target, true, c)
      if state.flight then closest = math.min(closest, horiz(f.pos, pos)) end
    end
    assertEq(closest > 20, true, gap .. " " .. closest)
  end
end)

test("arrive, at and resume on the same tick as a 2 km jump place the helicopter by the car's new position", function()
  load()
  state.random = seeded(6)
  night(0, "arriving")
  pos = vec3(pos.x + 2000, pos.y, pos.z)
  night(0.05, "tracking")
  assertNear(horiz(state.flight.pos, pos), heli.APPROACH_DISTANCE, 1)

  load()
  state.random = seeded(6)
  local flight = require("copsAndRobbers/heliFlight")
  heli.lightTick(state, target, true, 0)
  pos = vec3(pos.x + 2000, pos.y, pos.z)
  night(0.05, "tracking")
  assertNear(dist3(state.flight.pos, flight.target(state.flight, pos, vec3(0, 0, 0))), 0, 1)

  load()
  state.random = seeded(6)
  night(0, "tracking")
  local c = run(0, 5, 0.05) + 0.05
  night(c, "refuelling")
  c = run(c, c + 3, 0.05)
  local f = state.flight
  local before = horiz(f.pos, pos)
  pos = vec3(pos.x + 2000, pos.y, pos.z)
  c = c + 0.05
  night(c, "tracking")
  assertEq(state.flight, f)
  assertEq(f.leaving, nil)
  assertNear(horiz(f.pos, pos), before, 70 * 0.05 + 1e-6)
end)

local drawn

local function packedColor(r, g, b, a)
  local function byte(v) return math.max(0, math.min(255, math.floor(v))) end
  return byte(r) * 16777216 + byte(g) * 65536 + byte(b) * 256 + byte(a or 255)
end

local function stubBeam(cast)
  drawn = { calls = 0, tris = 0, far = 0, colors = {}, depth = true }
  _G.debugDrawer = {}
  package.loaded["utils/debugDraw"] = { drawTriSolid = function(a, b, c, clr, useZ)
    if type(clr) ~= "number" then error("expect number colour, got " .. type(clr)) end
    drawn.tris = drawn.tris + 1
    drawn.calls = math.floor(drawn.tris / 2)
    drawn.colors[clr] = true
    drawn.depth = drawn.depth and useZ == true
    drawn.last = { a, b, c }
    for _, v in ipairs({ a, b, c }) do drawn.far = math.max(drawn.far, dist3(v, state.lightPos)) end
  end }
  _G.color = packedColor
  _G.core_camera = { getPosition = function() return vec3(pos.x + 100, pos.y + 100, pos.z) end }
  _G.castRayStatic = cast
end

local function beamTest(name, fn)
  test(name, function()
    local saved = { _G.debugDrawer, _G.color, _G.core_camera, _G.castRayStatic, package.loaded["utils/debugDraw"] }
    local ok, err = pcall(fn)
    _G.debugDrawer, _G.color, _G.core_camera, _G.castRayStatic = saved[1], saved[2], saved[3], saved[4]
    package.loaded["utils/debugDraw"] = saved[5]
    if not ok then error(err, 0) end
  end)
end

local function drawsAt(c, isNight, opts)
  drawn.calls, drawn.tris, drawn.far = 0, 0, 0
  heli.lightTick(state, target, isNight, c, opts)
  return drawn.calls
end

beamTest("each beam quad is two depth-tested triangles in the quad's winding, with the game's packed colour", function()
  load()
  stubBeam()
  local quads = {}
  package.loaded["copsAndRobbers/beam"].draw = function(list, n, drawQuad, colorFn)
    local q = list[1]
    quads[1] = q
    drawQuad(q.a, q.b, q.c, q.d, colorFn(217, 235, 255, q.alpha))
    return 1
  end
  local tris = {}
  package.loaded["utils/debugDraw"].drawTriSolid = function(a, b, c, clr, useZ)
    tris[#tris + 1] = { a = a, b = b, c = c, clr = clr, useZ = useZ }
  end
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, target, true, 0, { weather = "rain" })
  assertEq(state.beamFailed, nil)
  assertEq(#tris, 2)
  local q = quads[1]
  assertEq(tris[1].a == q.a and tris[1].b == q.b and tris[1].c == q.c, true)
  assertEq(tris[2].a == q.a and tris[2].b == q.c and tris[2].c == q.d, true)
  assertEq(tris[1].clr, packedColor(217, 235, 255, q.alpha))
  assertEq(type(tris[1].clr), "number")
  assertEq(tris[1].useZ, true)
  assertEq(tris[2].useZ, true)
end)

beamTest("without the game's debug draw module the beam stops and the light stays", function()
  load()
  stubBeam()
  package.loaded["utils/debugDraw"] = nil
  local savedPath = package.path
  package.path = ""
  local ok, err = pcall(function()
    heli.set(state, { phase = "tracking" }, 0)
    heli.lightTick(state, target, true, 0)
  end)
  package.path = savedPath
  if not ok then error(err, 0) end
  assertEq(state.beamFailed, true)
  assertEq(state.failed, nil)
  assertEq(fake.objects[LIGHT] ~= nil, true)
end)

beamTest("at night while tracking the beam is drawn and the light has a glare", function()
  load()
  stubBeam()
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, true, { weather = "rain", beam = true }), 1200)
  assertEq(fake.objects[LIGHT].fields.flareType, "BNG_LightFlare_1")
  assertEq(drawsAt(0.05, true), 1200)
end)

beamTest("the beam setting off draws no beam and keeps the glare; on again draws on the next tick", function()
  load()
  stubBeam()
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, true, { beam = false }), 0)
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  assertEq(obj.fields.flareType, "BNG_LightFlare_1")
  assertEq(drawsAt(0.05, true, { beam = true }) > 0, true)
  assertEq(drawsAt(0.1, true, { beam = false }), 0)
  assertEq(fake.objects[LIGHT], obj)
  assertEq(obj.fields.flareType, "BNG_LightFlare_1")
  assertEq(tonumber(obj.fields.flareScale), 1)
  assertEq(drawsAt(0.15, true, { beam = true }) > 0, true)
end)

beamTest("no beam by day, without a light, or at a slant over 400 m", function()
  load()
  stubBeam()
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, false), 0)
  assertEq(fake.objects[LIGHT], nil)
  heli.set(state, { phase = "searching" }, 1)
  assertEq(drawsAt(1, true), 0)
  assertEq(fake.objects[LIGHT], nil)
  drawn.calls = 0
  heli.lightTick(state, nil, true, 1.5)
  assertEq(drawn.calls, 0)
  heli.set(state, { phase = "tracking" }, 2)
  assertEq(drawsAt(2, true) > 0, true)
  state.flight.pos = vec3(pos.x + 300, pos.y, pos.z + 280)
  assertEq(drawsAt(2, true), 0)
  assertEq(fake.objects[LIGHT] ~= nil, true)
  state.flight.pos = vec3(pos.x + 300, pos.y, pos.z + 250)
  assertEq(drawsAt(2, true) > 0, true)
end)

beamTest("a drawer error stops the beam for the round and keeps the light and its glare", function()
  load()
  stubBeam()
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, true) > 0, true)
  local obj = fake.objects[LIGHT]
  package.loaded["utils/debugDraw"].drawTriSolid = function() error("draw failed") end
  heli.lightTick(state, target, true, 0.05)
  assertEq(state.beamFailed, true)
  assertEq(state.failed, nil)
  assertEq(fake.objects[LIGHT], obj)
  stubBeam()
  assertEq(drawsAt(0.1, true), 0)
  assertEq(fake.objects[LIGHT], obj)
  assertEq(obj.fields.flareType, "BNG_LightFlare_1")
  heli.clear(state)
  heli.set(state, { phase = "tracking" }, 1)
  assertEq(drawsAt(1, true) > 0, true)
end)

beamTest("an error working out the quads stops the beam and keeps the light", function()
  load()
  stubBeam()
  require("copsAndRobbers/beam").quads = function() error("quads failed") end
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, true), 0)
  assertEq(state.beamFailed, true)
  assertEq(state.failed, nil)
  local obj = fake.objects[LIGHT]
  assertEq(obj ~= nil, true)
  run(0, 1, 0.05)
  assertEq(fake.objects[LIGHT], obj)
  assertEq(state.failed, nil)
end)

beamTest("the occlusion ray ends the beam at a hit, every 0.25 s, ignoring a hit within 2 m of the aim point", function()
  load()
  local casts = {}
  local short = false
  stubBeam(function(origin, dir, maxDist)
    casts[#casts + 1] = { origin = origin, dir = dir, maxDist = maxDist }
    return short and maxDist - 1 or maxDist / 2
  end)
  heli.set(state, { phase = "tracking" }, 0)
  assertEq(drawsAt(0, true) > 0, true)
  local axisLen = dist3(state.lightPos, state.aimPos)
  assertEq(#casts, 1)
  local cast = casts[1]
  assertNear(cast.maxDist, axisLen, 1e-9)
  assertNear(dist3(cast.origin, state.lightPos), 0, 1e-9)
  local toAim = vec3((state.aimPos.x - state.lightPos.x) / axisLen, (state.aimPos.y - state.lightPos.y) / axisLen, (state.aimPos.z - state.lightPos.z) / axisLen)
  assertNear(dist3(cast.dir, toAim), 0, 1e-9)
  assertNear(state.beamHit, axisLen / 2, 1e-9)
  assertEq(drawn.far <= axisLen / 2 + 1e-6, true, tostring(drawn.far))
  short = true
  assertEq(drawsAt(0.1, true) > 0, true)
  assertEq(#casts, 1)
  assertEq(drawn.far <= state.beamHit + 1e-6, true, tostring(drawn.far))
  assertEq(drawsAt(0.3, true) > 0, true)
  assertEq(#casts, 2)
  assertEq(state.beamHit, nil)
  axisLen = dist3(state.lightPos, state.aimPos)
  assertEq(drawn.far > 0.9 * axisLen, true, tostring(drawn.far))
end)

beamTest("a low beam's ray hitting the road at the lit spot does not cut the beam; a deck 5 m above the spot does", function()
  load()
  local mode, casts = "none", 0
  stubBeam(function(origin, dir, maxDist)
    casts = casts + 1
    if mode == "road" then return maxDist - 2.6 end
    if mode == "deck" then return maxDist - 5 / -dir.z end
    return maxDist
  end)
  heli.set(state, { phase = "tracking" }, 0)
  drawsAt(0, true)
  state.flight.pos = vec3(pos.x - 257, pos.y, pos.z + 50)
  mode = "road"
  assertEq(drawsAt(0.3, true) > 0, true)
  assertEq(casts, 2)
  local axisLen = dist3(state.lightPos, state.aimPos)
  local elevation = math.deg(math.asin((state.lightPos.z - state.aimPos.z) / axisLen))
  assertNear(elevation, 11, 1, "elevation")
  assertEq(state.beamHit, nil)
  assertEq(drawn.far > axisLen, true, tostring(drawn.far))
  mode = "deck"
  assertEq(drawsAt(0.6, true) > 0, true)
  assertEq(casts, 3)
  axisLen = dist3(state.lightPos, state.aimPos)
  assertEq(state.beamHit ~= nil and state.beamHit < axisLen - 20, true, tostring(state.beamHit))
  assertEq(drawn.far <= state.beamHit + 1e-6, true, tostring(drawn.far))
end)

test("the glare's scale follows the light's brightness through the fly-in", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  night(1, "tracking")
  local obj = fake.objects[LIGHT]
  assertEq(obj.fields.flareType, "BNG_LightFlare_1")
  assertEq(tonumber(obj.fields.flareScale) < 0.05, true, obj.fields.flareScale)
  local c = 1
  while c < 1 + heli.APPROACH_SECONDS + 0.5 do
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    assertEq(math.abs(tonumber(obj.fields.flareScale) - state.fx.bright) <= 0.05 + 1e-9, true, c .. " " .. obj.fields.flareScale)
  end
  assertEq(tonumber(obj.fields.flareScale) > 0.94, true, obj.fields.flareScale)
end)

test("a refuel during the fly-in never raises the brightness on any fly-away frame", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  night(1, "tracking")
  local c = run(1, 3, 0.05)
  local prev = state.fx.bright
  assertEq(prev > 0 and prev < 1, true, tostring(prev))
  c = c + 0.05
  night(c, "refuelling")
  assertEq(state.fx.bright <= prev + 1e-9, true, tostring(state.fx.bright))
  prev = state.fx.bright
  while fake.objects[LIGHT] do
    c = c + 0.05
    heli.lightTick(state, target, true, c)
    if fake.objects[LIGHT] then
      assertEq(state.fx.bright <= prev + 1e-9, true, c .. " " .. state.fx.bright .. " " .. prev)
      prev = state.fx.bright
    end
  end
end)

test("a target whose getVelocity returns nil falls back to the position delta", function()
  load()
  state.random = seeded(5)
  local nilVel = { getPosition = function() return pos end, getVelocity = function() return nil end }
  heli.set(state, { phase = "tracking" }, 0)
  heli.lightTick(state, nilVel, true, 0)
  pos = vec3(pos.x + 1.5, pos.y, pos.z)
  heli.lightTick(state, nilVel, true, 0.05)
  assertNear(state.carVel.x, 30, 1e-6)
  assertEq(state.flight ~= nil, true)
end)

test("the glare's scale is exactly 1 at full brightness after the fly-in", function()
  load()
  state.random = seeded(2)
  night(0, "arriving")
  night(1, "tracking")
  local obj = fake.objects[LIGHT]
  run(1, 1 + heli.APPROACH_SECONDS + 1, 0.05)
  assertEq(state.fx.bright, 1)
  assertEq(tonumber(obj.fields.flareScale), 1)
end)
