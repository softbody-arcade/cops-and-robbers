local lightbar = require("copsAndRobbers/lightbar")

test("choose picks light bar parts per slot, prefers them over beacons and ignores flashers, colors and patterns", function()
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
  assertEq(lightbar.choose({ { name = "x_flashers", slots = "roof" } }), nil)
  assertEq(lightbar.choose({}), nil)
end)

test("choose falls back to beacon lights when no light bar fits", function()
  local chosen = lightbar.choose({
    { name = "burnside_beaconlight_red", slots = "burnside_beaconlight" },
    { name = "beacon_color_red", slots = "beacon_color" },
  })
  assertEq(chosen.burnside_beaconlight, "burnside_beaconlight_red")
  assertEq(chosen.beacon_color, nil)
end)

test("isMainLight counts the light itself, not its bulbs, colors or patterns", function()
  assertEq(lightbar.isMainLight("burnside_beaconlight_red"), true)
  assertEq(lightbar.isMainLight("miramar_lightbar"), true)
  assertEq(lightbar.isMainLight("beaconLightBulb_incandescent_80W_1"), false)
  assertEq(lightbar.isMainLight("beacon_color_amber"), false)
  assertEq(lightbar.isMainLight("lightbar_pattern_police"), false)
  assertEq(lightbar.isMainLight(""), false)
  assertEq(lightbar.isMainLight(nil), false)
end)

test("choose ignores beacon bulbs", function()
  assertEq(lightbar.choose({ { name = "beaconLightBulb_sealedbeam_55W_1", slots = "beacon_bulb_F" } }), nil)
end)

test("isLightPart matches light bars, beacons and their colors", function()
  assertEq(lightbar.isLightPart("burnside_beaconlight_red"), true)
  assertEq(lightbar.isLightPart("beacon_color_red"), true)
  assertEq(lightbar.isLightPart("lightbar_color_L_red"), true)
  assertEq(lightbar.isLightPart("miramar_lightbar"), true)
  assertEq(lightbar.isLightPart("burnside_bumper_F"), false)
  assertEq(lightbar.isLightPart(""), false)
  assertEq(lightbar.isLightPart(nil), false)
end)

test("apply fills only empty slots", function()
  local parts = { a = "", b = "roof_rack" }
  local added = lightbar.apply(parts, { a = "lb", b = "lb2", c = "lb3" })
  assertEq(added, true)
  assertEq(parts.a, "lb"); assertEq(parts.b, "roof_rack"); assertEq(parts.c, "lb3")
  assertEq(lightbar.apply({ b = "rack" }, { b = "lb" }), false)
end)
