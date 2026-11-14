local config = require("cnr.config")
local round = require("cnr.round")

local function car(x, vx) return {pos={x=x,y=0,z=0}, vel={x=vx or 0,y=0,z=0}} end
local players = {[1]="Reinder", [2]="Bob", [3]="Ann"}

local function find(effects, kind, pid)
  for _, e in ipairs(effects) do
    if e.kind == kind and (pid == nil or e.pid == pid) then return e end
  end
end

local function count(effects, kind)
  local n = 0
  for _, e in ipairs(effects) do if e.kind == kind then n = n + 1 end end
  return n
end

local function started(cfgOverrides)
  local r = round.new((config.merge(cfgOverrides)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "vehicles/pickup/base.pc", players)
  return r
end

local function stillCars() return {[1]=car(0), [2]=car(5), [3]=car(500)} end

test("start asks issuer to pick vehicle", function()
  local r = round.new((config.merge(nil)))
  local fx = r:start(0, 1, 2, players)
  assertEq(r.state, "picking")
  assertEq(find(fx, "pickVehicle").pid, 2)
end)

test("vehiclePicked from issuer sets up everyone", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:vehiclePicked(1, 2, "pickup", "cfg", players)
  assertEq(r.state, "headstart")
  assertEq(count(fx, "setup"), 3)
  assertEq(find(fx, "setup", 1).role, "runner")
  assertEq(find(fx, "setup", 2).role, "cop")
  assertEq(find(fx, "setup", 2).headStartRemaining, 7)
  local i2, i3 = find(fx, "setup", 2).copIndex, find(fx, "setup", 3).copIndex
  assertEq(i2 ~= i3, true)
  assertEq(find(fx, "broadcast").msg, "Reinder is the runner! Car: pickup. Cops released in 7s")
  assertEq(r.vehicle.model, "pickup"); assertEq(r.vehicle.config, "cfg")
end)

test("vehiclePicked from someone else is ignored", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:vehiclePicked(1, 3, "pickup", "cfg", players)
  assertEq(#fx, 0); assertEq(r.state, "picking")
end)

test("release exactly after head start", function()
  local r = started()
  local fx = r:tick(7.9, stillCars(), {})
  assertEq(r.state, "headstart"); assertEq(find(fx, "release"), nil)
  fx = r:tick(8.0, stillCars(), {})
  assertEq(r.state, "running"); assertEq(r.releasedAt, 8.0)
  assertEq(find(fx, "release") ~= nil, true)
  assertEq(find(fx, "broadcast").msg, "Cops released!")
end)

test("no catch during head start", function()
  local r = started()
  for t = 1, 7.75, 0.25 do
    local fx = r:tick(t, stillCars(), {})
    assertEq(find(fx, "roundEnd"), nil)
  end
end)

test("catch after release plus hold time records the run", function()
  local r = started()
  r:tick(8, stillCars(), {})
  local fx
  for i = 1, 40 do
    fx = r:tick(8 + i * 0.25, stillCars(), {})
    if find(fx, "roundEnd") then break end
  end
  local e = find(fx, "roundEnd")
  assertEq(e.reason, "caught")
  assertNear(e.survivedSeconds, 7, 0.26)
  assertEq(e.runnerName, "Reinder"); assertEq(e.runnerId, 1)
  assertEq(e.explode, false)
  local rec = find(fx, "record")
  assertEq(rec.run.player, "Reinder"); assertEq(rec.run.endReason, "caught"); assertEq(rec.run.model, "pickup")
  assertEq(r.state, "idle")
end)

test("explode only when configured and caught", function()
  local r = started({explodeOnCatch=true})
  local fx
  for i = 0, 80 do
    fx = r:tick(8 + i * 0.25, stillCars(), {})
    if find(fx, "roundEnd") then break end
  end
  assertEq(find(fx, "roundEnd").explode, true)
  r = started({explodeOnCatch=true})
  r:tick(8, stillCars(), {})
  fx = r:playerLeft(9, 1)
  assertEq(find(fx, "roundEnd").explode, false)
end)

test("runner disconnect while running records disconnect", function()
  local r = started()
  r:tick(8, stillCars(), {})
  local fx = r:playerLeft(68, 1)
  local e = find(fx, "roundEnd")
  assertEq(e.reason, "disconnect"); assertNear(e.survivedSeconds, 60, 1e-9)
  assertEq(find(fx, "record").run.endReason, "disconnect")
  assertEq(r.state, "idle")
end)

test("runner disconnect during head start cancels without record", function()
  local r = started()
  local fx = r:playerLeft(3, 1)
  assertEq(find(fx, "roundEnd").reason, "cancelled")
  assertEq(find(fx, "record"), nil)
  assertEq(r.state, "idle")
end)

test("issuer leaving while picking cancels", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:playerLeft(1, 2)
  assertEq(r.state, "idle"); assertEq(find(fx, "record"), nil)
end)

test("cop leaving keeps round going", function()
  local r = started()
  r:tick(8, stillCars(), {})
  local fx = r:playerLeft(9, 3)
  assertEq(find(fx, "roundEnd"), nil); assertEq(r.state, "running")
end)

test("start while running is rejected", function()
  local r = started()
  local fx = r:start(2, 3, 3, players)
  assertEq(find(fx, "reply", 3).msg, "A round is already running")
  assertEq(r.runnerId, 1); assertEq(r.state, "headstart")
end)

test("stop while idle is rejected, stop while running cancels", function()
  local r = round.new((config.merge(nil)))
  assertEq(find(r:stop(0, 2), "reply", 2).msg, "No round running")
  r = started()
  local fx = r:stop(3, 2)
  assertEq(find(fx, "roundEnd").reason, "cancelled")
  assertEq(find(fx, "record"), nil)
  assertEq(r.state, "idle")
end)

test("missing car data is skipped", function()
  local r = started()
  r:tick(8, {}, {})
  local fx
  for i = 1, 40 do
    fx = r:tick(8 + i * 0.25, {[2]=car(5)}, {})
    assertEq(find(fx, "roundEnd"), nil)
  end
  for i = 1, 40 do
    fx = r:tick(20 + i * 0.25, {[1]=car(0)}, {})
    assertEq(find(fx, "roundEnd"), nil)
  end
end)

test("state effects only on change", function()
  local r = started()
  local fx = r:tick(2, stillCars(), {})
  assertEq(find(fx, "state", 1).resetAllowed, false)
  assertEq(find(fx, "state", 1).resetHint, "Stay still 7s to reset")
  fx = r:tick(2.1, stillCars(), {})
  assertEq(find(fx, "state", 1), nil)
end)

test("catch progress reported rounded to 0.05", function()
  local r = started()
  r:tick(8, stillCars(), {})
  local fx = r:tick(8.25, stillCars(), {})
  fx = r:tick(9.75, stillCars(), {})
  assertNear(find(fx, "state", 2).catchProgress, 0.25, 1e-9)
end)

test("mid-round join gets cop setup", function()
  local r = started()
  local fx = r:playerJoined(3, 4, "Dan")
  local s = find(fx, "setup", 4)
  assertEq(s.role, "cop"); assertNear(s.headStartRemaining, 5, 1e-9)
  r:tick(8, stillCars(), {})
  fx = r:playerJoined(9, 5, "Eve")
  assertEq(find(fx, "setup", 5).headStartRemaining, 0)
  assertEq(#r:playerJoined(9, 6, "x") > 0, true)
  local idle = round.new((config.merge(nil)))
  assertEq(#idle:playerJoined(0, 7, "y"), 0)
end)

test("illegal reset is announced, legal one is not", function()
  local r = started()
  r:tick(8, {[1]=car(0, 20), [2]=car(5), [3]=car(500)}, {})
  local fx = r:vehicleReset(8.1, 1)
  assertEq(find(fx, "broadcast").msg, "Reinder reset illegally")
  for i = 0, 28 do r:tick(8.2 + i * 0.25, {[1]=car(0), [2]=car(50), [3]=car(500)}, {}) end
  fx = r:vehicleReset(15.5, 1)
  assertEq(find(fx, "broadcast"), nil)
end)

test("pick times out after 10s", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:tick(9.9, {}, {})
  assertEq(r.state, "picking")
  fx = r:tick(10, {}, {})
  assertEq(r.state, "idle")
  assertEq(find(fx, "broadcast").msg, "Vehicle pick timed out")
end)
