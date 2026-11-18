local climate = require("cnr.climate")
test("climate gives the table's range per weather and month", function()
  local lo, hi = climate.range("clear", 7); assertEq(lo, 20); assertEq(hi, 31)
  lo, hi = climate.range("rain", 4); assertEq(lo, 10); assertEq(hi, 13)
  lo, hi = climate.range("fog", 10); assertEq(lo, 10); assertEq(hi, 14)
  lo, hi = climate.range("cloudy", 1); assertEq(lo, 2); assertEq(hi, 5)
  lo, hi = climate.range("snow", 12); assertEq(lo, -4); assertEq(hi, 0)
  lo, hi = climate.range("snow", 1); assertEq(lo, -5); assertEq(hi, -1)
  lo, hi = climate.range("thunderstorm", 7); assertEq(lo, 22); assertEq(hi, 25)
  lo, hi = climate.offset("thunderstorm"); assertEq(lo, 2); assertEq(hi, -6)
end)
test("the low is always below the high", function()
  for _, w in ipairs({ "clear", "cloudy", "rain", "storm", "fog", "snow", "thunderstorm" }) do
    for m = 1, 12 do
      local lo, hi = climate.range(w, m)
      assertEq(lo < hi, true, w .. " " .. m)
      if w == "snow" then assertEq(hi <= 0, true, "snow " .. m) end
    end
  end
  local lo, hi = climate.range("storm", 11); assertEq(lo, 6); assertEq(hi, 8)
end)
test("unknown weather or month gives nothing", function()
  assertEq(climate.range("hail", 5), nil)
  assertEq(climate.range("rain", 13), nil)
  assertEq(climate.range(nil, 5), nil)
  assertEq(climate.range("rain", nil), nil)
end)
