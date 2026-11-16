local units = require("copsAndRobbers/units")

test("metric distance is unchanged", function()
  assertEq(units.distance(640, "metric"), "640 m")
  assertEq(units.distance(999.4, "metric"), "999 m")
  assertEq(units.distance(999.5, "metric"), "1.0 km")
  assertEq(units.distance(1500, nil), "1.5 km")
end)
test("imperial distance in 10 ft steps, then miles", function()
  assertEq(units.distance(0, "imperial"), "0 ft")
  assertEq(units.distance(100, "imperial"), "330 ft")
  assertEq(units.distance(303, "imperial"), "990 ft")
  assertEq(units.distance(304, "imperial"), "0.2 mi")
  assertEq(units.distance(1609.344, "imperial"), "1.0 mi")
  assertEq(units.distance(2414, "imperial"), "1.5 mi")
end)
test("an unknown or missing game unit means metric", function()
  assertEq(units.unit("imperial"), "imperial")
  assertEq(units.unit("metric"), "metric")
  assertEq(units.unit("Imperial "), "metric")
  assertEq(units.unit(nil), "metric")
  _G.settings = nil
  assertEq(units.read(), "metric")
  _G.settings = { getValue = function() error("boom") end }
  assertEq(units.read(), "metric")
  _G.settings = { getValue = function(k) return k == "uiUnitLength" and "imperial" or nil end }
  assertEq(units.read(), "imperial")
  _G.settings = nil
end)
