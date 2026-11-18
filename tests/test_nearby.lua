package.path = "client/lua/ge/extensions/?.lua;" .. package.path
local nearby = require("copsAndRobbers/nearby")

local here = { x = 0, y = 0, z = 0 }

test("nearest sorts by distance and keeps the index", function()
  local r = nearby.nearest({ { x = 30, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, { x = 20, y = 0, z = 0 } }, here, 3)
  assertEq(r[1].index, 2); assertEq(r[2].index, 3); assertEq(r[3].index, 1)
  assertEq(r[1].meters, 10); assertEq(r[3].meters, 30)
end)

test("nearest honours the limit", function()
  local pts = {}
  for i = 1, 6 do pts[i] = { x = i * 10, y = 0, z = 0 } end
  assertEq(#nearby.nearest(pts, here, 3), 3)
end)

test("nearest rounds meters", function()
  assertEq(nearby.nearest({ { x = 3, y = 5, z = 0 } }, here, 3)[1].meters, 6)
end)

test("nearest of nothing is empty", function()
  assertEq(#nearby.nearest({}, here, 3), 0)
  assertEq(#nearby.nearest(nil, here, 3), 0)
end)

test("nearest sorts stations on different floors at the same XY", function()
  local r = nearby.nearest({ { x = 0, y = 0, z = 300 }, { x = 0, y = 0, z = 10 } }, here, 3)
  assertEq(r[1].index, 2); assertEq(r[1].meters, 10)
  assertEq(r[2].index, 1); assertEq(r[2].meters, 300)
end)
