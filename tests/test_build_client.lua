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

local SLOTS = {
  v8 = { pickup_intake = "Intake", pickup_exhaust = "Exhaust" },
  v8_60 = { pickup_intake = "Intake", pickup_exhaust = "Exhaust" },
  exhaust_dual = { pickup_tips = "Exhaust Tips" },
}
local function slotsOf(id) return SLOTS[id] end

test("parts that come with a swap are grouped under it", function()
  local changes = build.diff(
    { pickup_engine = "v8", pickup_intake = "small", pickup_exhaust = "exhaust_single", pickup_tips = "tip", pickup_wheel_F = "steel" },
    { pickup_engine = "v8_60", pickup_intake = "big", pickup_exhaust = "exhaust_dual", pickup_tips = "dual_tips", pickup_wheel_F = "alloy" })
  local roots = build.group(changes, slotsOf)
  assertEq(#roots, 2)
  assertEq(roots[1].slot, "pickup_engine"); assertEq(roots[1].extra, 3)
  assertEq(roots[2].slot, "pickup_wheel_F"); assertEq(roots[2].extra, 0)
end)

test("without part information every change stands on its own", function()
  local roots = build.group(build.diff({ a = "x", b = "y" }, { a = "x2", b = "y2" }), function() return nil end)
  assertEq(#roots, 2)
end)
