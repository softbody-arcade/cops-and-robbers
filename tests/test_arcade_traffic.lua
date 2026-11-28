local traffic = require("arcade.traffic")
local roster = require("arcade.roster")

local oldMP = MP

local function setup()
  local sent = {}
  local r = roster.new()
  local t = traffic.new(r, {
    send = function(pid, event, payload)
      sent[#sent + 1] = { pid = pid, event = event, payload = payload }
    end,
  })
  MP = {}
  return t, sent, r
end

test("traffic leaves the requested number of slots free", function()
  assertEq(traffic.perPlayer(5, 6, 1), 5)
  assertEq(traffic.perPlayer(5, 6, 3), 3)
  assertEq(traffic.perPlayer(5, 6, 2), 4)
  assertEq(traffic.perPlayer(5, 4, 1), 3)
  assertEq(traffic.perPlayer(5, 4, 3), 1)
  assertEq(traffic.perPlayer(5, 2, 3), 0)
  assertEq(traffic.perPlayer(5, 1, 1), 0)
  assertEq(traffic.perPlayer(0, 6, 1), 0)
end)

test("unreadable MaxCars means no cap", function()
  assertEq(traffic.perPlayer(5, nil, 1), 5)
  assertEq(traffic.perPlayer(5, nil, 3), 5)
  assertEq(traffic.perPlayer(5, "lots", 1), 5)
end)

test("whole rounds down and clamps negative counts to zero", function()
  assertEq(traffic.whole("2.7"), 2)
  assertEq(traffic.whole(-1), 0)
end)

test("allowance follows eligibility, reserved slots and the current MaxCars", function()
  local t = setup()
  local cfg = { trafficPerPlayer = 5 }
  MP.Settings = { MaxCars = 42 }
  MP.Get = function(key)
    assertEq(key, 42)
    return "5"
  end
  assertEq(traffic.maxCars(), 5)
  assertEq(t:allowance(cfg, 1, false), 0)
  assertEq(t:allowance(cfg, 1, true), 4)
  assertEq(t:allowance(cfg, 3, true), 2)
  MP.Get = function() error("setting unavailable") end
  assertEq(traffic.maxCars(), nil)
  MP.Settings = nil
  assertEq(t:allowance(cfg, 3, true), 5)
end)

test("opening a positive allowance sends it once and keeps the original count", function()
  local t, sent = setup()
  t:open(2, 0)
  t:open(2, -1)
  assertEq(t:openCount(2), nil)
  assertEq(#sent, 0)
  t:open(2, 3)
  t:open(2, 4)
  assertEq(t:openCount(2), 3)
  assertEq(t:openCount(1), nil)
  assertEq(#sent, 1)
  assertEq(sent[1].pid, 2)
  assertEq(sent[1].event, "cnr_trafficStart")
  assertEq(sent[1].payload.count, 3)
end)

test("reports replace traffic, deduplicate vids, and exclude own and AI cars before the cap", function()
  local t, _, r = setup()
  MP.GetPositionRaw = function(pid, vid)
    return { pos = { pid, vid, 0 }, vel = { x = 0, y = 0, z = 4 } }
  end
  local function isAI(vid) return vid == 5 end
  t:report(2, { 6 }, 0, isAI)
  assertEq(#t:cars(), 0)
  t:open(2, 2)
  t:report(2, { 0, 5, "bad", 1, "1", "2", 3 }, 0, isAI)
  local cars = t:cars()
  assertEq(#cars, 2)
  local seen = {}
  for _, car in ipairs(cars) do
    assertEq(car.traffic, true)
    assertEq(car.pos.x, 2)
    assertEq(car.vel.z, 4)
    seen[car.pos.y] = true
  end
  assertEq(seen[1], true)
  assertEq(seen[2], true)
  t:report(2, { 4 }, 0, isAI)
  assertEq(#t:cars(), 1)
  assertEq(t:cars()[1].pos.y, 4)
  r:leaveEarly(2)
  assertEq(t:openCount(2), 2)
  r:leaveLate(2)
  assertEq(t:openCount(2), nil)
  assertEq(#t:cars(), 0)
end)

test("cars skip missing positions, errors and malformed vectors", function()
  local t = setup()
  MP.GetPositionRaw = function(pid, vid)
    if vid == 1 then return nil end
    local raw = { pos = { 1, 2, 3 }, vel = { 1, 2, 3 } }
    if vid == 2 then return raw, "unavailable" end
    if vid == 3 then raw.pos[2] = "bad" end
    if vid == 4 then raw.vel[1] = 0/0 end
    return raw, ""
  end
  t:open(2, 5)
  t:report(2, { 1, 2, 3, 4, 5 }, 0, function() return false end)
  assertEq(#t:cars(), 1)
end)

test("extra cars count every vehicle of the given player except their own vid", function()
  local t = setup()
  MP.GetPlayerVehicles = function(pid)
    if pid == 2 then return { [0] = "own", [1] = "traffic", [5] = "parked" } end
  end
  assertEq(t:extraCars(2, 0), 2)
  assertEq(t:extraCars(2, nil), 3)
  assertEq(t:extraCars(1, 0), 0)
end)

MP = oldMP
