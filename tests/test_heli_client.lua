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
  heli.lightTick(state, target, false)
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
  assertEq(p.x, 42); assertEq(p.y, 40); assertEq(p.z, 47)
end)

test("set stores the phase, reason and end time", function()
  load()
  heli.set(state, { phase = "grounded", reason = "fog", seconds = 5 }, 10)
  assertEq(state.phase, "grounded"); assertEq(state.reason, "fog"); assertEq(state.endsAt, 15)
  heli.set(state, nil, 20)
  assertEq(state.phase, nil)
end)

local function near(a, b) return math.abs(a - b) < 1e-6 end

test("the light pose circles the car and aims with a wobble", function()
  load()
  local car = vec3(10, 20, 5)
  local l, a = heli.lightPose(car, 0)
  assertEq(near(l.x, 22) and near(l.y, 20) and near(l.z, 45), true)
  assertEq(near(a.x, 10) and near(a.y, 21.5) and near(a.z, 5), true)
  local l2 = heli.lightPose(car, 2 * math.pi / heli.ORBIT_SPEED)
  assertEq(near(l2.x, 22) and near(l2.y, 20) and near(l2.z, 45), true)
  for _, t in ipairs({ 1, 3.7, 9, 20 }) do
    local p = heli.lightPose(car, t)
    assertEq(near(math.sqrt((p.x - 10) ^ 2 + (p.y - 20) ^ 2), 12), true)
  end
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
