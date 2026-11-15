local geo = require("cnr.geo")

local ref = geo.newRef(52.0, 5.0)

test("reference point maps to origin", function()
  local p = geo.toLocal(ref, 52.0, 5.0, 0)
  assertNear(p.x, 0, 1e-6); assertNear(p.y, 0, 1e-6); assertNear(p.z, 0, 1e-6)
end)

test("north and east are y and x", function()
  local n = geo.toLocal(ref, 52.001, 5.0, 0)
  assertNear(n.x, 0, 0.01); assertNear(n.y, 111.3, 0.5)
  local e = geo.toLocal(ref, 52.0, 5.001, 0)
  assertNear(e.y, 0, 0.01); assertNear(e.x, 68.7, 0.5)
end)

test("height is up", function()
  assertNear(geo.toLocal(ref, 52.0, 5.0, 30).z, 30, 1e-6)
end)

test("ten metres apart stays ten metres apart far from the reference", function()
  local a = geo.toLocal(ref, 52.2, 5.3, 0)
  local b = geo.toLocal(ref, 52.2 + 10 / 111250, 5.3, 0)
  local dx, dy = b.x - a.x, b.y - a.y
  assertNear(math.sqrt(dx * dx + dy * dy), 10, 0.05)
end)

test("valid rejects garbage", function()
  assertEq(geo.valid(52, 5), true)
  assertEq(geo.valid(91, 5), false)
  assertEq(geo.valid(52, "x"), false)
  assertEq(geo.valid(0/0, 5), false)
end)
