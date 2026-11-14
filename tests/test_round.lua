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
  r:go(1, 3)
  return r
end

local function stillCars() return {[1]=car(0), [2]=car(5), [3]=car(500)} end

test("start asks issuer to pick vehicle", function()
  local r = round.new((config.merge(nil)))
  local fx = r:start(0, 1, 2, players)
  assertEq(r.state, "picking")
  assertEq(find(fx, "pickVehicle").pid, 2)
end)

test("vehiclePicked from issuer sets up everyone in prep", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:vehiclePicked(1, 2, "pickup", "cfg", players)
  assertEq(r.state, "prep")
  assertEq(count(fx, "setup"), 3)
  assertEq(find(fx, "setup", 1).role, "runner")
  assertEq(find(fx, "setup", 2).role, "cop")
  assertEq(find(fx, "setup", 2).phase, "prep")
  local i2, i3 = find(fx, "setup", 2).copIndex, find(fx, "setup", 3).copIndex
  assertEq(i2 ~= i3, true)
  assertEq(find(fx, "broadcast").msg, "Reinder is the runner! Car: pickup. Change your paint if you like, then type /cnr go")
  assertEq(r.vehicle.model, "pickup"); assertEq(r.vehicle.config, "cfg")
end)

test("vehiclePicked from someone else is ignored", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  local fx = r:vehiclePicked(1, 3, "pickup", "cfg", players)
  assertEq(#fx, 0); assertEq(r.state, "picking")
end)

test("prep waits for go without a timeout", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  local fx = r:tick(500, stillCars(), {})
  assertEq(r.state, "prep"); assertEq(find(fx, "roundEnd"), nil)
end)

test("go starts the runner countdown", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  local fx = r:go(5, 3)
  assertEq(r.state, "countdown")
  assertEq(find(fx, "countdown").seconds, 3)
  assertEq(find(fx, "broadcast").msg, "Runner starts in 3s")
end)

test("go outside prep is rejected", function()
  local r = round.new((config.merge(nil)))
  assertEq(find(r:go(0, 2), "reply", 2).msg, "No round set up, use /cnr start <name>")
  r = started()
  assertEq(find(r:go(2, 2), "reply", 2).msg, "Round already started")
  assertEq(r.state, "countdown")
end)

test("runner released after countdown, cops after head start", function()
  local r = started()
  local fx = r:tick(3.9, stillCars(), {})
  assertEq(r.state, "countdown"); assertEq(find(fx, "runnerGo"), nil)
  fx = r:tick(4.0, stillCars(), {})
  assertEq(r.state, "headstart")
  assertEq(find(fx, "runnerGo").headStartSeconds, 7)
  assertEq(find(fx, "broadcast").msg, "Reinder is off! Cops released in 7s")
end)

test("release exactly after head start", function()
  local r = started()
  r:tick(4, stillCars(), {})
  local fx = r:tick(10.9, stillCars(), {})
  assertEq(r.state, "headstart"); assertEq(find(fx, "release"), nil)
  fx = r:tick(11.0, stillCars(), {})
  assertEq(r.state, "running"); assertEq(r.releasedAt, 11.0)
  assertEq(find(fx, "release") ~= nil, true)
  assertEq(find(fx, "broadcast").msg, "Cops released!")
end)

test("no catch during head start", function()
  local r = started()
  for t = 1, 10.75, 0.25 do
    local fx = r:tick(t, stillCars(), {})
    assertEq(find(fx, "roundEnd"), nil)
  end
end)

test("catch after release plus hold time records the run", function()
  local r = started()
  r:tick(4, stillCars(), {})
  r:tick(11, stillCars(), {})
  local fx
  for i = 1, 40 do
    fx = r:tick(11 + i * 0.25, stillCars(), {})
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
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  fx = r:playerLeft(12, 1)
  assertEq(find(fx, "roundEnd").explode, false)
end)

test("runner disconnect while running records disconnect", function()
  local r = started()
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local fx = r:playerLeft(71, 1)
  local e = find(fx, "roundEnd")
  assertEq(e.reason, "disconnect"); assertNear(e.survivedSeconds, 60, 1e-9)
  assertEq(find(fx, "record").run.endReason, "disconnect")
  assertEq(r.state, "idle")
end)

test("runner disconnect during head start cancels without record", function()
  local r = started()
  r:tick(4, stillCars(), {})
  local fx = r:playerLeft(6, 1)
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
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local fx = r:playerLeft(12, 3)
  assertEq(find(fx, "roundEnd"), nil); assertEq(r.state, "running")
end)

test("start while running is rejected", function()
  local r = started()
  local fx = r:start(2, 3, 3, players)
  assertEq(find(fx, "reply", 3).msg, "A round is already running")
  assertEq(r.runnerId, 1); assertEq(r.state, "countdown")
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
  r:tick(4, {}, {}); r:tick(11, {}, {})
  local fx
  for i = 1, 40 do
    fx = r:tick(11 + i * 0.25, {[2]=car(5)}, {})
    assertEq(find(fx, "roundEnd"), nil)
  end
  for i = 1, 40 do
    fx = r:tick(20 + i * 0.25, {[1]=car(0)}, {})
    assertEq(find(fx, "roundEnd"), nil)
  end
end)

test("state effects only on change", function()
  local r = started()
  r:tick(4, stillCars(), {})
  local fx = r:tick(5, stillCars(), {})
  assertEq(find(fx, "state", 1) ~= nil, true)
  fx = r:tick(5, stillCars(), {})
  assertEq(find(fx, "state", 1), nil)
  r = started()
  fx = r:tick(4, stillCars(), {})
  assertEq(find(fx, "state", 1).resetAllowed, false)
  assertEq(find(fx, "state", 1).resetHint, "Stay still 7s to reset")
  fx = r:tick(4.1, stillCars(), {})
  assertEq(find(fx, "state", 1), nil)
end)

test("catch progress reported rounded to 0.05", function()
  local r = started()
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local fx = r:tick(11.25, stillCars(), {})
  fx = r:tick(12.75, stillCars(), {})
  assertNear(find(fx, "state", 2).catchProgress, 0.25, 1e-9)
end)

test("mid-round join gets cop setup with the current phase", function()
  local r = started()
  local fx = r:playerJoined(3, 4, "Dan")
  local s = find(fx, "setup", 4)
  assertEq(s.role, "cop"); assertEq(s.phase, "countdown"); assertNear(s.countdownRemaining, 1, 1e-9)
  r:tick(4, stillCars(), {})
  fx = r:playerJoined(6, 8, "Fay")
  assertEq(find(fx, "setup", 8).phase, "headstart"); assertNear(find(fx, "setup", 8).headStartRemaining, 5, 1e-9)
  r:tick(11, stillCars(), {})
  fx = r:playerJoined(12, 5, "Eve")
  assertEq(find(fx, "setup", 5).phase, "running")
  assertEq(#r:playerJoined(9, 6, "x") > 0, true)
  local idle = round.new((config.merge(nil)))
  assertEq(#idle:playerJoined(0, 7, "y"), 0)
end)

test("illegal reset is announced, legal one is not", function()
  local r = started()
  r:tick(4, {[1]=car(0, 20), [2]=car(5), [3]=car(500)}, {})
  r:tick(11, {[1]=car(0, 20), [2]=car(5), [3]=car(500)}, {})
  local fx = r:vehicleReset(11.1, 1)
  assertEq(find(fx, "broadcast").msg, "Reinder reset illegally")
  for i = 0, 28 do r:tick(11.2 + i * 0.25, {[1]=car(0), [2]=car(50), [3]=car(500)}, {}) end
  fx = r:vehicleReset(18.5, 1)
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

test("resets during prep and countdown are not judged", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  assertEq(find(r:vehicleReset(60, 2), "broadcast"), nil)
  r:go(100, 2)
  assertEq(find(r:vehicleReset(101, 2), "broadcast"), nil)
  r:tick(103, stillCars(), {})
  assertEq(find(r:vehicleReset(103.5, 2), "broadcast"), nil)
  assertEq(find(r:vehicleReset(107, 2), "broadcast").msg, "Bob reset illegally")
end)

local function running()
  local r = started()
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  return r
end

local function kmh(x, v) return {pos={x=x,y=0,z=0}, vel={x=v/3.6,y=0,z=0}} end

test("cop crash gives a penalty and freezes", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 80), [2]=kmh(200, 120), [3]=kmh(500, 0)}, {})
  local fx = r:tick(11.5, {[1]=kmh(0, 80), [2]=kmh(200, 10), [3]=kmh(500, 0)}, {})
  local p = find(fx, "penalty", 2)
  assertEq(p.seconds, 10)
  assertEq(find(fx, "broadcast").msg, "Bob crashed hard: 10s penalty")
  assertEq(find(fx, "state", 2).resetHint, "Crash penalty 10s")
  fx = r:tick(21.5, {[1]=kmh(0, 80), [2]=kmh(200, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penaltyEnd", 2) ~= nil, true)
end)

test("runner crash has no penalty", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 120), [2]=kmh(200, 0), [3]=kmh(500, 0)}, {})
  local fx = r:tick(11.5, {[1]=kmh(0, 0), [2]=kmh(200, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penalty"), nil)
end)

test("penalized cop does not count toward a catch", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 0), [2]=kmh(5, -100), [3]=kmh(500, 0)}, {})
  r:tick(11.5, {[1]=kmh(0, 0), [2]=kmh(5, 0), [3]=kmh(500, 0)}, {})
  local fx
  for i = 1, 36 do
    fx = r:tick(11.5 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(5, 0), [3]=kmh(500, 0)}, {})
    assertEq(find(fx, "roundEnd"), nil)
  end
end)

test("no crash detection before cops are released", function()
  local r = started()
  r:tick(4, stillCars(), {})
  r:tick(4.25, {[1]=kmh(0, 0), [2]=kmh(200, 120), [3]=kmh(500, 0)}, {})
  local fx = r:tick(4.5, {[1]=kmh(0, 0), [2]=kmh(200, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penalty"), nil)
end)

test("cop rammed by the runner gets no penalty", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(10, -100), [2]=kmh(0, 0), [3]=kmh(500, 0)}, {})
  r:tick(11.5, {[1]=kmh(5, -100), [2]=kmh(0, 60), [3]=kmh(500, 0)}, {})
  local fx = r:tick(11.75, {[1]=kmh(4, 0), [2]=kmh(0, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penalty"), nil)
end)

test("two cops colliding: only the one driving in is penalized", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(-500, 0), [2]=kmh(100, 120), [3]=kmh(108, 0)}, {})
  local fx = r:tick(11.5, {[1]=kmh(-500, 0), [2]=kmh(104, 0), [3]=kmh(108, 60)}, {})
  assertEq(find(fx, "penalty", 2) ~= nil, true)
  fx = r:tick(11.75, {[1]=kmh(-500, 0), [2]=kmh(104, 0), [3]=kmh(110, 0)}, {})
  assertEq(find(fx, "penalty", 3), nil)
end)

test("test cop: issuer is cop, AI runner and AI partner", function()
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder", [2]="Bob"}, {test=true, role="cop"})
  assertEq(r.state, "picking")
  local fx = r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder", [2]="Bob"})
  assertEq(count(fx, "setup"), 1)
  local s1 = find(fx, "setup", 1)
  assertEq(s1.role, "cop"); assertEq(s1.colorHex, "#20c020"); assertEq(s1.inPlace, true)
  local ai = find(fx, "setupAI", 1).ai
  assertEq(#ai, 2)
  assertEq(ai[1].id, round.AI_FIRST); assertEq(ai[1].role, "runner"); assertEq(ai[1].colorHex, "#1f5fff")
  assertEq(ai[2].role, "cop"); assertEq(ai[2].colorHex, "#e02020")
  assertEq(r.runnerId, round.AI_FIRST)
  assertEq(find(fx, "broadcast").msg, "Test round: you are a cop with an AI runner and an AI partner. Type /cnr go to start")
end)

test("test runner: AI cops can catch, nothing is recorded", function()
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder"}, {test=true, role="runner"})
  local fx = r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder"})
  assertEq(find(fx, "setup", 1).role, "runner")
  assertEq(find(fx, "setup", 1).colorHex, "#1f5fff")
  local ai = find(fx, "setupAI", 1).ai
  assertEq(ai[1].role, "cop"); assertEq(ai[1].colorHex, "#20c020")
  assertEq(ai[2].role, "cop"); assertEq(ai[2].colorHex, "#e02020")
  r:go(2, 1)
  local a1 = round.AI_FIRST
  local cars = {[1]=car(0), [a1]=car(5), [a1 - 1]=car(500)}
  r:tick(5, cars, {}); r:tick(12, cars, {})
  for i = 1, 40 do
    fx = r:tick(12 + i * 0.25, cars, {})
    if find(fx, "roundEnd") then break end
  end
  assertEq(find(fx, "roundEnd").reason, "caught")
  assertEq(find(fx, "record"), nil)
end)

test("AI ids never collide with broadcast or players", function()
  assertEq(round.AI_FIRST <= -10, true)
  assertEq(round.isAI(round.AI_FIRST), true)
  assertEq(round.isAI(-1), false)
  assertEq(round.isAI(0), false)
end)

test("test round needs a role", function()
  local r = round.new((config.merge(nil)))
  local fx = r:start(0, nil, 1, {[1]="Reinder"}, {test=true})
  assertEq(find(fx, "reply", 1).msg, "Usage: /cnr test <runner|cop>")
  assertEq(r.state, "idle")
end)

test("stop ends a test round without record", function()
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder"}, {test=true, role="cop"})
  r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder"})
  local fx = r:stop(5, 1)
  assertEq(find(fx, "record"), nil)
  assertEq(find(fx, "roundEnd").reason, "cancelled")
end)
