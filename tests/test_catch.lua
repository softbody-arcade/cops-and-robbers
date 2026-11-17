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

test("moving faster than 3 km/h and 3 m in 2 s breaks hold", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  local p = t:update(5.5, car(3, 1), {car(5)})
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
  assertNear((t:update(6, car(4, 20), {car(5)})), 3/7, 1e-9)
  assertEq((t:update(9, car(20, 20), {car(5)})), 0)
end)

test("short break does not wipe the catch", function()
  local t = catch.new(cfg); local c
  for i = 0, 20 do t:update(i*0.25, car(0), {car(5)}) end
  t:update(5.25, car(0, 5), {car(5)})
  for i = 1, 10 do _, c = t:update(5.25 + i*0.25, car(0), {car(5)}) end
  assertEq(c, true)
end)

local function moving(x, vxKmh) return car(x, vxKmh / 3.6) end

test("a stuck runner rocking 1.5 m each way at up to 15 km/h is caught once 2 s of rocking count as held", function()
  local t = catch.new(cfg)
  local w = 15 / 3.6 / 1.5
  local caughtAt
  for i = 0, 60 do
    local now = i * 0.25
    local runner = car(1.5 * math.sin(w * now), 1.5 * w * math.cos(w * now))
    local _, c = t:update(now, runner, { car(5) })
    if c and not caughtAt then caughtAt = now end
  end
  assert(caughtAt, "never caught")
  assertEq(caughtAt >= cfg.catchHoldSeconds, true, "caught at " .. caughtAt)
  assertEq(caughtAt <= cfg.catchHoldSeconds + 2.5, true, "caught at " .. caughtAt)
end)

test("a runner driving away at 20 km/h is never held, even with a cop alongside", function()
  local t = catch.new(cfg)
  for i = 0, 80 do
    local x = i * 0.25 * 20 / 3.6
    local p, c = t:update(i * 0.25, moving(x, 20), { moving(x + 5, 20) })
    assertEq(p, 0, "at " .. i * 0.25)
    assertEq(c, false)
  end
end)

test("a runner creeping straight at 4 km/h with a cop alongside is never held", function()
  local t = catch.new(cfg)
  for i = 0, 80 do
    local x = i * 0.25 * 4 / 3.6
    local p, c = t:update(i * 0.25, moving(x, 4), { moving(x + 3, 4) })
    assertEq(p, 0, "at " .. i * 0.25)
    assertEq(c, false)
  end
end)

test("a runner rocking 1.5 m each way while drifting 0.5 m per 2 s is still held", function()
  local t = catch.new(cfg)
  local w = 15 / 3.6 / 1.5
  local caughtAt
  for i = 0, 80 do
    local now = i * 0.25
    local x = 1.5 * math.sin(w * now) + 0.25 * now
    local _, c = t:update(now, car(x, 1.5 * w * math.cos(w * now)), { car(5) })
    if c and not caughtAt then caughtAt = now end
  end
  assert(caughtAt, "never caught")
end)

test("a runner at a steady 6 km/h with a cop alongside is never held", function()
  local t = catch.new(cfg)
  for i = 0, 80 do
    local x = i * 0.25 * 6 / 3.6
    local p, c = t:update(i * 0.25, moving(x, 6), { moving(x + 3, 6) })
    assertEq(p, 0, "at " .. i * 0.25)
    assertEq(c, false)
  end
end)

test("a cop beyond the catch radius never holds a stuck runner", function()
  local t = catch.new(cfg)
  for i = 0, 80 do
    local p = t:update(i * 0.25, car(0, 10 / 3.6), { car(10.5) })
    assertEq(p, 0, "at " .. i * 0.25)
  end
end)

test("reset clears the movement history", function()
  local t = catch.new(cfg)
  for i = 0, 20 do t:update(i * 0.25, car(0, 10 / 3.6), { car(5) }) end
  t:reset()
  local p
  for i = 21, 27 do p = t:update(i * 0.25, car(0, 10 / 3.6), { car(5) }) end
  assertEq(p, 0)
  p = t:update(7.25, car(0, 10 / 3.6), { car(5) })
  assertEq(p > 0, true)
end)

test("the movement history stays bounded and works with ticks that never land 2 s apart", function()
  local t = catch.new(cfg)
  local p
  for i = 0, 6 do p = t:update(i * 0.3, car(0, 10 / 3.6), { car(5) }) end
  assertEq(p, 0)
  p = t:update(2.1, car(0, 10 / 3.6), { car(5) })
  assertEq(p > 0, true)
  for i = 8, 200 do t:update(i * 0.3, car(0, 10 / 3.6), { car(5) }) end
  assertEq(#t.history <= 9, true, "history " .. #t.history)
end)
