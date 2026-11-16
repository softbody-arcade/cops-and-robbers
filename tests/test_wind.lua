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
  assertNear(x, 4, 1e-6); assertNear(y, 0, 1e-6)
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
  assertEq(strongest > 18, true)
end)

test("storm gusts never pass the peak or turn more than 30 degrees", function()
  for i = 0, 6000 do
    local t = i * 0.1
    local x, y = wind.at("storm", 4242, 0, t)
    assertEq(speed(x, y) <= 25 + 1e-6, true, "peak at " .. t)
    assertEq(math.abs(math.deg(math.atan(x, y))) <= 30 + 1e-6, true, "turn at " .. t)
  end
end)
