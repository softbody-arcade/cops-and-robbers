local visibility = require("copsAndRobbers/visibility")
local epsilon = 1e-9
local nan = 0 / 0
local infinity = math.huge

local function clearRange(gazeCos, carForwardCos, maxMeters)
  return visibility.range(maxMeters or 400, gazeCos, carForwardCos, 1, false, 0, 0.0004, 1)
end

local function assertFiniteNear(actual, expected)
  assert(type(actual) == "number" and actual == actual and math.abs(actual) < infinity)
  assertNear(actual, expected, epsilon)
end

test("bearing measures horizontal cosine independently of scale and height", function()
  local compass = {
    {x = 0, y = 1, expected = 1},
    {x = 1, y = 0, expected = 0},
    {x = -1, y = 0, expected = 0},
    {x = 0, y = -1, expected = -1},
  }
  for _, direction in ipairs(compass) do
    assertFiniteNear(visibility.bearing({x = 0, y = 1, z = 0}, direction), direction.expected)
    local scaled = {x = direction.x * 7, y = direction.y * 7, z = -90}
    assertFiniteNear(visibility.bearing({x = 0, y = 40, z = 5}, scaled), direction.expected)
  end
  assertFiniteNear(visibility.bearing({x = 1e308, y = 1e308}, {x = 0, y = 1}), math.sqrt(0.5))
end)

test("bearing rejects unusable horizontal directions", function()
  local north = {x = 0, y = 1}
  assertEq(visibility.bearing(nil, north), nil)
  assertEq(visibility.bearing(north, nil), nil)
  local unusable = {
    {}, {x = 0, y = 0, z = 1}, {x = 0.001, y = 0}, {x = 0.0005, y = 0.0005},
    {x = nan, y = 1}, {x = 0, y = infinity}, {x = -infinity, y = 1},
  }
  for _, direction in ipairs(unusable) do
    assertEq(visibility.bearing(direction, north), nil)
    assertEq(visibility.bearing(north, direction), nil)
  end
  assertFiniteNear(visibility.bearing({x = 0.00101, y = 0}, north), 0)
end)

test("gaze range decreases as the runner moves away from direct gaze", function()
  assertFiniteNear(clearRange(math.sqrt(0.5), nil), 400 * 2 ^ (math.sqrt(0.5) - 1))
  local previous = clearRange(1, nil)
  assertFiniteNear(previous, 400)
  for angle = 1, 180 do
    local current = clearRange(math.cos(math.rad(angle)), nil)
    assert(current < previous, "gaze range should decrease at " .. angle .. " degrees")
    previous = current
  end
  assertFiniteNear(previous, 100)
end)

test("the rear mirror floor tapers symmetrically over thirty degrees", function()
  local carForward = {x = 0, y = 1}
  local function mirrorRange(offset)
    local angle = math.rad(offset)
    local delta = {x = math.sin(angle), y = -math.cos(angle)}
    return clearRange(-1, visibility.bearing(carForward, delta))
  end

  local offsets = {{0, 200}, {15, 150}, {30, 100}, {45, 100}, {90, 100}}
  for _, sample in ipairs(offsets) do
    assertFiniteNear(mirrorRange(sample[1]), sample[2])
    assertFiniteNear(mirrorRange(-sample[1]), sample[2])
  end

  local previous = mirrorRange(0)
  for angle = 1, 30 do
    local current = mirrorRange(angle)
    assert(current <= previous, "mirror floor should not increase at " .. angle .. " degrees")
    previous = current
  end
end)

test("direct rear gaze can improve on the mirror and missing bearings have defined ranges", function()
  assertFiniteNear(clearRange(-1, -1), 200)
  assertFiniteNear(clearRange(1, -1), 400)
  assertFiniteNear(clearRange(-1, 0), 100)
  assertFiniteNear(clearRange(1, nil), 400)
  assertFiniteNear(clearRange(nil, -1), 200)
  assertFiniteNear(clearRange(nil, nil), 100)
end)

test("lighting and weather scale every sight direction", function()
  local cases = {
    {1, false, 0, 0.0004, 1.00, 400, 200, 100},
    {1, false, 0, 0.0010, 1.00, 390, 195,  98},
    {1, false, 0, 0.0020, 0.85, 318, 159,  79},
    {1, false, 0, 0.0040, 0.70, 239, 119,  60},
    {1, false, 0, 0.0050, 0.75, 243, 122,  61},
    {1, false, 0, 0.0150, 1.00, 160,  80,  40},
    {0, false, 0, 0.0004, 1.00, 120,  60,  30},
    {0, true,  0, 0.0004, 1.00, 220, 110,  55},
    {0, false, 1, 0.0004, 1.00, 200, 100,  50},
    {0, true,  1, 0.0004, 1.00, 300, 150,  75},
  }
  local bearings = {{1,1,6}, {0,0,7}, {-1,0,8}, {-1,-1,7}, {1,-1,6}}
  for rowIndex, row in ipairs(cases) do
    for bearingIndex, pair in ipairs(bearings) do
      local meters = visibility.range(400, pair[1], pair[2], row[1], row[2], row[3], row[4], row[5])
      assert(meters >= 0 and meters <= 400)
      assertEq(math.floor(meters + 0.5), row[pair[3]],
        "weather row " .. rowIndex .. ", bearing " .. bearingIndex)
    end
  end
end)

test("the configured maximum scales range and zero disables ground sight", function()
  local bearings = {{1,1,200}, {0,0,100}, {-1,0,50}, {-1,-1,100}, {1,-1,200}}
  for _, pair in ipairs(bearings) do
    assertFiniteNear(clearRange(pair[1], pair[2], 200), pair[3])
    assertEq(clearRange(pair[1], pair[2], 0), 0)
  end
  assertEq(clearRange(nil, nil, 0), 0)
end)

test("the runner at 170 metres is seen at night with headlights in the rain blend", function()
  local cases = {
    {false, 0.5, 141, false}, {true, 0.5, 230, true},
    {true, 0, 194, true}, {false, 0, 106, false},
  }
  for _, row in ipairs(cases) do
    local night = visibility.range(400, 1, 1, 0, row[1], row[2], 0.0015, 0.925)
    assertEq(math.floor(night + 0.5), row[3])
    assertEq(170 <= night, row[4])
    local day = visibility.range(400, 1, 1, 1, row[1], row[2], 0.0015, 0.925)
    assertEq(math.floor(day + 0.5), 353)
  end
  assertFiniteNear(visibility.range(400, 1, 1, 0.5, true, 1, 0.0004, 1), 350)
end)

test("denser fog and stronger precipitation never extend sight range", function()
  for _, daylight in ipairs({0, 1}) do
    local previousFogRange, previousPrecipitationRange = infinity, infinity
    for step = 0, 30 do
      local fogRange = visibility.range(400, 1, 1, daylight, true, 1, 0.0004 + step * 0.0005, 1)
      local precipitationRange = visibility.range(400, 1, 1, daylight, true, 1, 0.0004, 1 - step * 0.01)
      assert(fogRange <= previousFogRange)
      assert(precipitationRange <= previousPrecipitationRange)
      previousFogRange, previousPrecipitationRange = fogRange, precipitationRange
    end
  end
end)

test("invalid measurements use their range fallbacks", function()
  local function checkInvalid(value)
    assertFiniteNear(visibility.range(value, 1, 1, 1, false, 0, 0.0004, 1), 0)
    assertFiniteNear(visibility.range(400, value, 1, 1, false, 0, 0.0004, 1), 100)
    assertFiniteNear(visibility.range(400, -1, value, 1, false, 0, 0.0004, 1), 100)
    assertFiniteNear(visibility.range(400, 1, 1, value, true, 1, 0.0004, 1), 300)
    assertFiniteNear(visibility.range(400, 1, 1, 0, true, value, 0.0004, 1), 220)
    assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, value, 1), 160)
    assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, 0.0004, value), 280)
  end

  checkInvalid(nil)
  for _, value in ipairs({nan, infinity, -infinity, "1"}) do
    checkInvalid(value)
  end
end)

test("only boolean true counts as active lamps", function()
  assertFiniteNear(visibility.range(400, 1, 1, 0, nil, 0, 0.0004, 1), 120)
  for _, value in ipairs({false, 0, 1, "true", {}}) do
    assertFiniteNear(visibility.range(400, 1, 1, 0, value, 0, 0.0004, 1), 120)
  end
  assertFiniteNear(visibility.range(400, 1, 1, 0, true, 0, 0.0004, 1), 220)
end)

test("finite out-of-domain measurements clamp to sight range limits", function()
  assertFiniteNear(clearRange(1, 1, -400), 0)
  assertFiniteNear(clearRange(2, 1), 400)
  assertFiniteNear(clearRange(-2, 1), 100)
  assertFiniteNear(clearRange(-1, 2), 100)
  assertFiniteNear(clearRange(-1, -2), 200)
  assertFiniteNear(visibility.range(400, 1, 1, -1, false, 0, 0.0004, 1), 120)
  assertFiniteNear(visibility.range(400, 1, 1, 2, false, 0, 0.0004, 1), 400)
  assertFiniteNear(visibility.range(400, 1, 1, 0, false, -1, 0.0004, 1), 120)
  assertFiniteNear(visibility.range(400, 1, 1, 0, false, 2, 0.0004, 1), 200)
  assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, 0, 1), 400)
  assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, 1e308, 1), 160)
  assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, 0.0004, 0), 280)
  assertFiniteNear(visibility.range(400, 1, 1, 1, false, 0, 0.0004, 2), 400)
  assertFiniteNear(visibility.range(400, 1, 1, 0, true, 1, 0.015, 1), 120)
end)

test("twilight smooths both clock boundaries including a crossing at clock wrap", function()
  local w = 30 / 1440
  local offsets = {-w, -w / 2, 0, w / 2, w}
  local factors = {0, 0.15625, 0.5, 0.84375, 1}

  assertFiniteNear(visibility.daylight(0, 0.75, 0.25), 1)
  assertFiniteNear(visibility.daylight(0.5, 0.75, 0.25), 0)
  for _, anchors in ipairs({{0.75, 0.25}, {0.99, 0.49}, {0.49, 0.99}}) do
    local sunrise, sunset = anchors[1], anchors[2]
    for i, offset in ipairs(offsets) do
      assertFiniteNear(visibility.daylight((sunrise + offset) % 1, sunrise, sunset), factors[i])
      assertFiniteNear(visibility.daylight((sunset + offset) % 1, sunrise, sunset), factors[#factors + 1 - i])
    end
  end
end)

test("daylight is unavailable without finite distinct clock values", function()
  local function checkInvalid(value)
    assertEq(visibility.daylight(value, 0.75, 0.25), nil)
    assertEq(visibility.daylight(0, value, 0.25), nil)
    assertEq(visibility.daylight(0, 0.75, value), nil)
  end

  checkInvalid(nil)
  for _, value in ipairs({nan, infinity, -infinity, "0"}) do
    checkInvalid(value)
  end
  assertEq(visibility.daylight(0, 0.75, 0.75), nil)
  assertEq(visibility.daylight(0, 0, 1), nil)
end)
