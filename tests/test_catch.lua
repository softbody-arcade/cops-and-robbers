local config = require("cnr.config")
local catch = require("cnr.catch")

local cfg = config.merge(nil)
local function car(x, vx) return {pos={x=x,y=0,z=0}, vel={x=vx or 0,y=0,z=0}} end

test("caught after 7s held", function()
  local t = catch.new(cfg); local p, c
  for i = 0, 28 do p, c = t:update(i*0.25, car(0), {car(5)}) end
  assertEq(c, true); assertNear(p, 1, 1e-9)
end)

test("not caught at 6.75s", function()
  local t = catch.new(cfg); local c
  for i = 0, 27 do _, c = t:update(i*0.25, car(0), {car(5)}) end
  assertEq(c, false)
end)

test("progress is fraction of hold", function()
  local t = catch.new(cfg); local p
  for i = 0, 14 do p = t:update(i*0.25, car(0), {car(5)}) end
  assertNear(p, 3.5/7, 1e-9)
end)

test("moving faster than 3 km/h breaks hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  local p = t:update(5.5, car(0, 1), {car(5)})
  assertNear(p, 4/7, 1e-9)
end)

test("cop beyond 10 m breaks hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  assertNear((t:update(5.5, car(0), {car(10.5)})), 4/7, 1e-9)
end)

test("any one cop in range counts", function()
  local t = catch.new(cfg); local c
  for i = 0, 28 do _, c = t:update(i*0.25, car(0), {car(300), car(9)}) end
  assertEq(c, true)
end)

test("no cops means no hold", function()
  local t = catch.new(cfg)
  assertEq((t:update(0, car(0), {})), 0)
end)

test("missing runner data drains", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  assertNear((t:update(5.5, nil, {car(5)})), 4/7, 1e-9)
end)

test("reset clears hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  t:reset()
  assertEq((t:update(5.5, car(0), {car(5)})), 0)
end)

test("hold drains at twice the fill rate and stops at zero", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  assertNear((t:update(6, car(0, 20), {car(5)})), 3/7, 1e-9)
  assertEq((t:update(9, car(0, 20), {car(5)})), 0)
end)

test("short break does not wipe the catch", function()
  local t = catch.new(cfg); local c
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  t:update(5.25, car(0, 5), {car(5)})
  for i = 1, 10 do _, c = t:update(5.25 + i*0.25, car(0), {car(5)}) end
  assertEq(c, true)
end)
