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

test("cover switches only after four checks in a row", function()
  local s = shelter.new()
  assertEq(shelter.step(s, true), false); assertEq(s.covered, false)
  assertEq(shelter.step(s, true), false); assertEq(s.covered, false)
  assertEq(shelter.step(s, true), false); assertEq(s.covered, false)
  assertEq(shelter.step(s, true), true); assertEq(s.covered, true)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, true), false); assertEq(s.covered, true)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, false), false)
  assertEq(shelter.step(s, false), true); assertEq(s.covered, false)
end)
