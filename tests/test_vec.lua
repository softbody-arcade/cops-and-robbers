local vec = require("cnr.vec")

test("toVec accepts keyed and array", function()
  assertEq(vec.toVec({x=1,y=2,z=3}).z, 3)
  assertEq(vec.toVec({4,5,6}).x, 4)
  assertEq(vec.toVec("nope"), nil)
  assertEq(vec.toVec({1,2}), nil)
end)

test("dist and speed", function()
  assertNear(vec.dist({x=0,y=0,z=0},{x=3,y=4,z=0}), 5, 1e-9)
  assertNear(vec.speedKmh({x=10,y=0,z=0}), 36, 1e-9)
end)
