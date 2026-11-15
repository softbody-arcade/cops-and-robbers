local build = require("copsAndRobbers/build")

test("diff lists changed, added and removed slots in slot order and ignores liveries", function()
  local base = { pickup_engine = "v8", pickup_wheel_F = "steel", pickup_paint_design = "a", pickup_bed = "long" }
  local cur = { pickup_engine = "v8_60", pickup_wheel_F = "steel", pickup_paint_design = "b", pickup_intake = "big", pickup_bed = "" }
  local d = build.diff(base, cur)
  assertEq(#d, 3)
  assertEq(d[1].slot, "pickup_bed"); assertEq(d[1].from, "long"); assertEq(d[1].to, "")
  assertEq(d[2].slot, "pickup_engine"); assertEq(d[2].to, "v8_60")
  assertEq(d[3].slot, "pickup_intake"); assertEq(d[3].from, "")
end)

test("equal setups give no changes", function()
  assertEq(#build.diff({ a = "x", b = "" }, { a = "x" }), 0)
  assertEq(#build.varsDiff({ gear1 = 3.1 }, { gear1 = 3.1 }), 0)
end)

test("varsDiff lists changed tuning values", function()
  local d = build.varsDiff({ gear1 = 3.1, tire = 30 }, { gear1 = 3.45, tire = 30, extra = 1 })
  assertEq(#d, 2); assertEq(d[1].name, "extra"); assertEq(d[2].name, "gear1"); assertEq(d[2].to, 3.45)
end)

test("slot labels drop the model prefix and read like words", function()
  assertEq(build.label("pickup_engine", "pickup"), "Engine")
  assertEq(build.label("pickup_wheel_F", "pickup"), "Wheel F")
  assertEq(build.label("tire_R_15x7", "pickup"), "Tire R 15x7")
  assertEq(build.varLabel("$gear_1"), "Gear 1")
end)
