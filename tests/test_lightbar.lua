local lightbar = require("copsAndRobbers/lightbar")

test("choose picks light bar parts per slot and ignores beacons, flashers, colors and patterns", function()
  local chosen = lightbar.choose({
    { name = "miramar_lightbar", slots = { "miramar_roof_accessory", "miramar_roof_accessory_ute" } },
    { name = "miramar_beacon", slots = { "miramar_roof_accessory" } },
    { name = "miramar_flashers", slots = "miramar_flashers" },
    { name = "lightbar_color_L_red", slots = "lightbar_color_L" },
    { name = "lightbar_pattern_police", slots = "lightbar_pattern" },
  })
  assertEq(chosen.miramar_roof_accessory, "miramar_lightbar")
  assertEq(chosen.miramar_roof_accessory_ute, "miramar_lightbar")
  assertEq(chosen.miramar_flashers, nil)
  assertEq(chosen.lightbar_color_L, nil)
  assertEq(chosen.lightbar_pattern, nil)
end)

test("choose is deterministic when several light bars fit a slot", function()
  local chosen = lightbar.choose({
    { name = "x_lightbar_b", slots = "roof" },
    { name = "x_lightbar_a", slots = "roof" },
  })
  assertEq(chosen.roof, "x_lightbar_a")
end)

test("choose returns nil when nothing fits", function()
  assertEq(lightbar.choose({ { name = "x_beacon", slots = "roof" } }), nil)
  assertEq(lightbar.choose({}), nil)
end)

test("apply fills only empty slots", function()
  local parts = { a = "", b = "roof_rack" }
  local added = lightbar.apply(parts, { a = "lb", b = "lb2", c = "lb3" })
  assertEq(added, true)
  assertEq(parts.a, "lb"); assertEq(parts.b, "roof_rack"); assertEq(parts.c, "lb3")
  assertEq(lightbar.apply({ b = "rack" }, { b = "lb" }), false)
end)
