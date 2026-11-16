local wind = require("copsAndRobbers/wind")

local function speed(x, y) return math.sqrt(x * x + y * y) end

test("calm weathers have no wind", function()
  for _, w in ipairs({ "clear", "cloudy", "fog" }) do
    local x, y, z = wind.at(w, 7, 0, 30)
    assertEq(x, 0); assertEq(y, 0); assertEq(z, 0)
  end
  assertEq((wind.at(nil, 7, 0, 30)), 0)
end)

test("at the start only the steady wind blows, towards dirDeg", function()
  local x, y = wind.at("rain", 7, 90, 0)
  assertNear(x, 5, 1e-6); assertNear(y, 0, 1e-6)
end)

test("the same seed and time give the same wind, another seed differs", function()
  local same, differs = true, false
  for t = 0, 120, 0.5 do
    local ax, ay = wind.at("storm", 12345, 40, t)
    local bx, by = wind.at("storm", 12345, 40, t)
    local cx, cy = wind.at("storm", 777, 40, t)
    if ax ~= bx or ay ~= by then same = false end
    if math.abs(ax - cx) > 0.01 or math.abs(ay - cy) > 0.01 then differs = true end
  end
  assertEq(same, true); assertEq(differs, true)
end)

test("storm gusts come within a minute", function()
  local strongest = 0
  for i = 0, 600 do
    local x, y = wind.at("storm", 4242, 0, i * 0.1)
    strongest = math.max(strongest, speed(x, y))
  end
  assertEq(strongest > 21, true)
end)

test("storm gusts never pass the peak or turn more than 30 degrees", function()
  for i = 0, 6000 do
    local t = i * 0.1
    local x, y = wind.at("storm", 4242, 0, t)
    assertEq(speed(x, y) <= 26 + 1e-6, true, "peak at " .. t)
    assertEq(math.abs(math.deg(math.atan(x, y))) <= 30 + 1e-6, true, "turn at " .. t)
  end
end)

test("rain and snow gusts stay realistic: about 1.5 times the steady wind, turning up to 15 degrees", function()
  for _, w in ipairs({ { "rain", 5, 8 }, { "snow", 4, 6 } }) do
    local turned, strongest = false, 0
    for i = 0, 6000 do
      local x, y = wind.at(w[1], 99, 0, i * 0.1)
      local s, a = speed(x, y), math.abs(math.deg(math.atan(x, y)))
      strongest = math.max(strongest, s)
      assertEq(s <= w[3] + 1e-6, true, w[1] .. " peak")
      assertEq(a <= 15 + 1e-6, true, w[1] .. " turn")
      if a > 1 then turned = true end
    end
    assertEq(strongest > w[2], true, w[1] .. " gusts")
    assertEq(turned, true, w[1] .. " turns")
  end
end)
