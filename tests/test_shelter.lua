local shelter = require("copsAndRobbers/shelter")

local function v(x, y, z) return { x = x, y = y, z = z } end
_G.vec3 = _G.vec3 or v

local function roofAt(height, sides)
  return function(pos)
    local center = pos.x == 0 and pos.y == 0
    if center then return height end
    if sides and sides[pos.x .. "," .. pos.y] then return height end
    return nil
  end
end

test("a roof close above with cover around counts as shelter", function()
  local cast = roofAt(3, { ["3,0"] = true, ["0,3"] = true })
  assertEq(shelter.roofed(v(0, 0, 0), cast), true)
end)

test("a beam overhead, like a street-light arm, is not shelter", function()
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(3, { ["3,0"] = true, ["-3,0"] = true })), false)
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(3, { ["0,3"] = true, ["0,-3"] = true })), false)
end)

test("cover on both axes is shelter", function()
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(3, { ["-3,0"] = true, ["0,-3"] = true })), true)
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(3, { ["3,0"] = true, ["0,3"] = true, ["-3,0"] = true, ["0,-3"] = true })), true)
end)

test("a roof only straight above, like a tree, is not shelter", function()
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(3, {})), false)
end)

test("nothing straight above is not shelter, whatever is around", function()
  local cast = function(pos) if pos.x ~= 0 or pos.y ~= 0 then return 3 end return nil end
  assertEq(shelter.roofed(v(0, 0, 0), cast), false)
end)

test("a high bridge is not shelter", function()
  local all = { ["3,0"] = true, ["-3,0"] = true, ["0,3"] = true, ["0,-3"] = true }
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(20, all)), false)
  assertEq(shelter.roofed(v(0, 0, 0), roofAt(11.9, all)), true)
end)

test("cover switches only after two checks in a row", function()
  local s = shelter.new()
  assertEq(shelter.step(s, true), false); assertEq(s.covered, false)
  assertEq(shelter.step(s, true), true); assertEq(s.covered, true)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, true), false); assertEq(s.covered, true)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, false), true); assertEq(s.covered, false)
end)

local function blocking(blocked, calls)
  return function(from, dir, d)
    if calls then calls[#calls + 1] = { from = from, dir = dir, d = d } end
    if blocked(from, dir, d) then return 5 end
    return nil
  end
end

test("the helicopter sees the car when one ray gets through", function()
  local from, car = v(10, -30, 55), v(10, 20, 5)
  local function blockedToFrontAndMiddle(f, dir, d)
    return f.y + dir.y * d > 19
  end
  assertEq(shelter.inSight(from, car, 1.5, 0, 1, blocking(blockedToFrontAndMiddle)), true)
end)

test("covered only when every ray is blocked", function()
  local all = blocking(function() return true end)
  assertEq(shelter.inSight(v(10, -30, 55), v(10, 20, 5), 1.5, 0, 1, all), false)
end)

test("a hit at the point itself does not block", function()
  local cast = function(from, dir, d) return d - 0.3 end
  assertEq(shelter.inSight(v(10, -30, 55), v(10, 20, 5), 1.5, 0, 1, cast), true)
end)

test("no direction gives only the middle point", function()
  local calls = {}
  local cast = blocking(function() return true end, calls)
  assertEq(shelter.inSight(v(10, -30, 55), v(10, 20, 5), 1.5, 0, 0, cast), false)
  assertEq(#calls, 1)
  local d = calls[1].dir
  assertEq(d.x == d.x and d.y == d.y and d.z == d.z, true)
end)

test("the helicopter at the point sees it", function()
  local called = false
  local cast = function() called = true; return 0 end
  assertEq(shelter.inSight(v(10, 20, 6.5), v(10, 20, 5), 1.5, 0, 1, cast), true)
  assertEq(called, false)
end)

test("a nil, full or longer return counts as seen", function()
  local from, car = v(10, -30, 55), v(10, 20, 5)
  assertEq(shelter.inSight(from, car, 1.5, 0, 1, function() return nil end), true)
  assertEq(shelter.inSight(from, car, 1.5, 0, 1, function(f, dir, d) return d end), true)
  assertEq(shelter.inSight(from, car, 1.5, 0, 1, function(f, dir, d) return d + 10 end), true)
end)

test("the points sit 1.5 m up and 2 m ahead and behind", function()
  local calls = {}
  local from = v(10, -30, 55)
  shelter.inSight(from, v(10, 20, 5), 1.5, 0, 1, blocking(function() return true end, calls))
  assertEq(#calls, 3)
  local want = { v(10, 20, 6.5), v(10, 22, 6.5), v(10, 18, 6.5) }
  for i, c in ipairs(calls) do
    assertEq(math.abs(from.x + c.dir.x * c.d - want[i].x) < 1e-6, true)
    assertEq(math.abs(from.y + c.dir.y * c.d - want[i].y) < 1e-6, true)
    assertEq(math.abs(from.z + c.dir.z * c.d - want[i].z) < 1e-6, true)
  end
end)

test("points beyond the range are not seen", function()
  local calls = 0
  local cast = function() calls = calls + 1; return nil end
  local from = v(0, 0, 1.5)
  assertEq(shelter.inSight(from, v(401, 0, 0), 1.5, 0, 0, cast, 400), false)
  assertEq(calls, 0)
  assertEq(shelter.inSight(from, v(399, 0, 0), 1.5, 0, 0, cast, 400), true)
  assertEq(calls, 1)
  assertEq(shelter.inSight(from, v(401, 0, 0), 1.5, 0, 0, cast), true)
end)
