local config = require("cnr.config")
local crash = require("cnr.crash")

local cfg = config.merge(nil)
local function car(kmh) return {pos={x=0,y=0,z=0}, vel={x=kmh/3.6,y=0,z=0}} end

test("losing 50 km/h within half a second is a crash", function()
  local d = crash.new(cfg)
  assertEq(d:update(0, car(100)), false)
  assertEq(d:update(0.25, car(100)), false)
  assertEq(d:update(0.5, car(45)), true)
end)

test("hard braking is not a crash", function()
  local d = crash.new(cfg)
  local crashed = false
  for i = 0, 40 do
    local kmh = math.max(0, 100 - i * 9)
    crashed = crashed or d:update(i * 0.25, car(kmh))
  end
  assertEq(crashed, false)
end)

test("loss spread over more than the window is not a crash", function()
  local d = crash.new(cfg)
  d:update(0, car(100))
  assertEq(d:update(0.75, car(40)), false)
end)

test("detector clears after a crash", function()
  local d = crash.new(cfg)
  d:update(0, car(100))
  assertEq(d:update(0.25, car(10)), true)
  assertEq(d:update(0.5, car(0)), false)
end)

test("missing data and reset clear history", function()
  local d = crash.new(cfg)
  d:update(0, car(100))
  d:update(0.25, nil)
  assertEq(d:update(0.5, car(0)), false)
  d:update(1, car(100))
  d:reset()
  assertEq(d:update(1.25, car(0)), false)
end)
