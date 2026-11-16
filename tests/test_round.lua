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
  assertEq(find(fx, "broadcast"), nil)
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
  assertEq(find(fx, "broadcast"), nil)
end)

test("go outside prep is rejected", function()
  local r = round.new((config.merge(nil)))
  assertEq(find(r:go(0, 2), "reply", 2).msg, 'No round set up, start one in the panel')
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
  assertEq(find(fx, "broadcast"), nil)
end)

test("release exactly after head start", function()
  local r = started()
  r:tick(4, stillCars(), {})
  local fx = r:tick(10.9, stillCars(), {})
  assertEq(r.state, "headstart"); assertEq(find(fx, "release"), nil)
  fx = r:tick(11.0, stillCars(), {})
  assertEq(r.state, "running"); assertEq(r.releasedAt, 11.0)
  assertEq(find(fx, "release") ~= nil, true)
  assertEq(find(fx, "broadcast"), nil)
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
  assertEq(find(fx, "broadcast").tone, "warn")
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
  assertEq(find(fx, "broadcast").tone, nil)
  assertEq(find(fx, "roundEnd").message, "Vehicle pick timed out")
end)

test("a cancelled round carries its reason on the round end", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  local e = find(r:playerLeft(2, 1), "roundEnd")
  assertEq(e.reason, "cancelled"); assertEq(e.message, "Runner left, round cancelled")
  assertEq(find(started():stop(3, 2), "roundEnd").message, "Round cancelled")
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
  assertEq(find(r:vehicleReset(107, 2), "broadcast"), nil)
  assertEq(find(r:vehicleReset(109, 2), "broadcast").msg, "Bob reset illegally")
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
  assertEq(find(fx, "broadcast"), nil)
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
  assertEq(s1.role, "cop"); assertEq(s1.colorHex, "#1f6fe0"); assertEq(s1.inPlace, true)
  local ai = find(fx, "setupAI", 1).ai
  assertEq(#ai, 2)
  assertEq(ai[1].id, round.AI_FIRST); assertEq(ai[1].role, "runner"); assertEq(ai[1].colorHex, "#d83a2c")
  assertEq(ai[2].role, "cop"); assertEq(ai[2].colorHex, "#6fb0ff")
  assertEq(r.runnerId, round.AI_FIRST)
  assertEq(find(fx, "broadcast"), nil)
  assertEq(r.players[round.AI_FIRST], "AI runner"); assertEq(r.players[round.AI_FIRST - 1], "AI cop")
end)

test("test runner: AI cops can catch, nothing is recorded", function()
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder"}, {test=true, role="runner"})
  local fx = r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder"})
  assertEq(find(fx, "setup", 1).role, "runner")
  assertEq(find(fx, "setup", 1).colorHex, "#d83a2c")
  local ai = find(fx, "setupAI", 1).ai
  assertEq(ai[1].role, "cop"); assertEq(ai[1].colorHex, "#1f6fe0")
  assertEq(ai[2].role, "cop"); assertEq(ai[2].colorHex, "#6fb0ff")
  assertEq(r.players[round.AI_FIRST], "AI cop 1"); assertEq(r.players[round.AI_FIRST - 1], "AI cop 2")
  assertEq(find(fx, "broadcast"), nil)
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
  assertEq(find(fx, "reply", 1).msg, 'Pick practice as runner or as cop')
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

test("test round catch is announced", function()
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder"}, {test=true, role="runner"})
  r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder"})
  r:go(2, 1)
  local a1 = round.AI_FIRST
  local cars = {[1]=car(0), [a1]=car(5), [a1 - 1]=car(500)}
  r:tick(5, cars, {}); r:tick(12, cars, {})
  local fx
  for i = 1, 40 do
    fx = r:tick(12 + i * 0.25, cars, {})
    if find(fx, "roundEnd") then break end
  end
  assertEq(find(fx, "roundEnd").reason, "caught")
  assertEq(find(fx, "broadcast"), nil)
end)

test("penalty effect carries the offender name", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 80), [2]=kmh(200, 120), [3]=kmh(500, 0)}, {})
  local fx = r:tick(11.5, {[1]=kmh(0, 80), [2]=kmh(200, 10), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penalty", 2).name, "Bob")
end)

test("frozen cops get no reset hints during head start", function()
  local r = started()
  local fx = r:tick(4, stillCars(), {})
  assertEq(find(fx, "state", 1) ~= nil, true)
  assertEq(find(fx, "state", 2), nil)
  fx = r:tick(11, stillCars(), {})
  assertEq(find(fx, "state", 2) ~= nil, true)
end)

test("cop rejoining mid-chase resumes where they left with their penalty", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 80), [2]=kmh(800, 120), [3]=kmh(500, 0)}, {})
  r:tick(11.5, {[1]=kmh(0, 80), [2]=kmh(801, 0), [3]=kmh(500, 0)}, {})
  r:playerLeft(14, 2)
  local fx = r:playerJoined(20, 7, "Bob")
  local s = find(fx, "setup", 7)
  assertNear(s.resumePos.x, 801, 1e-9)
  local p = find(fx, "penalty", 7)
  assertNear(p.seconds, 1.5, 1e-9)
  fx = r:tick(24.5, {[1]=kmh(0, 0), [7]=kmh(801, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "penaltyEnd", 7) ~= nil, true)
end)

test("rejoining without history gets a normal setup", function()
  local r = running()
  local fx = r:playerJoined(20, 9, "Zed")
  assertEq(find(fx, "setup", 9).resumePos, nil)
  assertEq(find(fx, "penalty", 9), nil)
end)

local function testRunning(role)
  local r = round.new((config.merge(nil)))
  r:start(0, nil, 1, {[1]="Reinder", [2]="Bob"}, {test=true, role=role})
  r:vehiclePicked(1, 1, "pickup", "cfg", {[1]="Reinder", [2]="Bob"})
  return r
end

test("test round effects are scoped to the issuer", function()
  local r = testRunning("cop")
  local fx = r:go(2, 1)
  assertEq(find(fx, "countdown").to, 1)
  fx = r:tick(5, {[1]=car(0)}, {})
  assertEq(find(fx, "runnerGo").to, 1)
  fx = r:stop(6, 1)
  assertEq(find(fx, "roundEnd").to, 1)
end)

test("normal round effects are not scoped", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  assertEq(find(r:go(2, 2), "countdown").to, nil)
end)

test("test issuer leaving cancels the test", function()
  local r = testRunning("cop")
  r:go(2, 1)
  local fx = r:playerLeft(3, 1)
  assertEq(r.state, "idle")
  assertEq(find(fx, "roundEnd").reason, "cancelled")
end)

test("end during the chase records a called run", function()
  local r = running()
  local fx = r:endCalled(71, 2)
  local e = find(fx, "roundEnd")
  assertEq(e.reason, "called"); assertNear(e.survivedSeconds, 60, 1e-9)
  assertEq(find(fx, "record").run.endReason, "called")
end)

test("end before the chase is rejected", function()
  local r = started()
  local fx = r:endCalled(2, 2)
  assertEq(find(fx, "reply", 2).msg, 'The chase has not started, use Cancel')
  assertEq(r.state, "countdown")
end)

test("time limit ends the round as escaped", function()
  local r = started({roundTimeLimitSeconds=60})
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local far = {[1]=kmh(0, 50), [2]=kmh(900, 50), [3]=kmh(1500, 50)}
  local fx = r:tick(70.9, far, {})
  assertEq(find(fx, "roundEnd"), nil)
  fx = r:tick(71, far, {})
  assertEq(find(fx, "roundEnd").reason, "escaped")
  assertEq(find(fx, "record").run.endReason, "escaped")
end)

test("last seen ping every interval with nearest cop distance", function()
  local r = started({lastSeenIntervalSeconds=30})
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local far = {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(900, 50)}
  local fx = r:tick(40.9, far, {})
  assertEq(find(fx, "lastSeen"), nil)
  fx = r:tick(41, far, {})
  local e = find(fx, "lastSeen")
  assertNear(e.pos.x, 0, 1e-9); assertNear(e.nearestCop, 300, 1e-9)
  fx = r:tick(42, far, {})
  assertEq(find(fx, "lastSeen"), nil)
  fx = r:tick(71, far, {})
  assertEq(find(fx, "lastSeen") ~= nil, true)
end)

test("last seen off when interval is 0", function()
  local r = started({lastSeenIntervalSeconds=0})
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  local far = {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(900, 50)}
  for t = 12, 100, 1 do assertEq(find(r:tick(t, far, {}), "lastSeen"), nil) end
end)

test("catch credits cops within the radius", function()
  local r = running()
  local cars = {[1]=car(0), [2]=car(5), [3]=car(8)}
  local fx
  for i = 1, 40 do
    fx = r:tick(11 + i * 0.25, cars, {})
    if find(fx, "roundEnd") then break end
  end
  local e = find(fx, "roundEnd")
  assertEq(table.concat(e.catchers, ","), "Ann,Bob")
  assertEq(table.concat(find(fx, "record").run.catchers, ","), "Ann,Bob")
end)

test("reroll in prep goes back to picking", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players)
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  local fx = r:reroll(5, 3)
  assertEq(r.state, "picking")
  assertEq(find(fx, "pickVehicle").pid, 3)
  fx = r:vehiclePicked(6, 3, "etk800", "cfg2", players)
  assertEq(r.state, "prep"); assertEq(r.vehicle.model, "etk800")
end)

test("reroll outside prep is rejected", function()
  local r = started()
  assertEq(find(r:reroll(2, 2), "reply", 2).msg, "You can only reroll during prep")
end)

test("runner cannot reset while being caught", function()
  local r = running()
  for i = 0, 16 do r:tick(11 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(300, 0), [3]=kmh(500, 0)}, {}) end
  local fx
  local lastAllowed, lastHint
  for i = 1, 16 do
    fx = r:tick(15 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(5, 0), [3]=kmh(500, 0)}, {})
    local s = find(fx, "state", 1)
    if s then lastAllowed, lastHint = s.resetAllowed, s.resetHint end
  end
  assertEq(lastAllowed, false)
  assertEq(lastHint, "Can't reset while being caught")
  assertEq(find(r:vehicleReset(19.1, 1), "broadcast").msg, "Reinder reset illegally")
end)

test("runner can reset again once the hold has drained", function()
  local r = running()
  for i = 0, 8 do r:tick(11 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(5, 0), [3]=kmh(500, 0)}, {}) end
  local fx, allowed
  for i = 1, 60 do
    fx = r:tick(13 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(300, 0), [3]=kmh(500, 0)}, {})
    local s = find(fx, "state", 1)
    if s then allowed = s.resetAllowed end
  end
  assertEq(allowed, true)
end)

test("a jump without an allowed reset is announced as a teleport", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 50), [2]=kmh(10, 50), [3]=kmh(500, 0)}, {})
  local fx = r:tick(11.5, {[1]=kmh(0, 50), [2]=kmh(900, 50), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast").msg, "Bob teleported")
  assertEq(find(fx, "broadcast").tone, "warn")
  fx = r:tick(11.75, {[1]=kmh(0, 50), [2]=kmh(1500, 50), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
end)

test("normal driving and allowed resets are not teleports", function()
  local r = running()
  local fx = r:tick(11.25, {[1]=kmh(0, 0), [2]=kmh(8, 40), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
  fx = r:tick(11.5, {[1]=kmh(0, 0), [2]=kmh(11, 40), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
  for i = 1, 30 do r:tick(11.5 + i * 0.25, {[1]=kmh(0, 0), [2]=kmh(30, 0), [3]=kmh(500, 0)}, {}) end
  assertEq(find(r:vehicleReset(19.1, 2), "broadcast"), nil)
  fx = r:tick(19.25, {[1]=kmh(0, 0), [2]=kmh(200, 0), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
end)

test("setup placement is not a teleport", function()
  local r = started()
  local fx = r:tick(1.5, {[1]=kmh(0, 0), [2]=kmh(5000, 0), [3]=kmh(500, 0)}, {})
  fx = r:tick(1.75, {[1]=kmh(0, 0), [2]=kmh(100, 0), [3]=kmh(400, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
end)

test("relocation by the map is not a reset or teleport", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 50), [2]=kmh(10, 50), [3]=kmh(500, 0)}, {})
  r:relocated(11.3, 2)
  assertEq(find(r:vehicleReset(11.35, 2), "broadcast"), nil)
  local fx = r:tick(11.5, {[1]=kmh(0, 50), [2]=kmh(900, 50), [3]=kmh(500, 0)}, {})
  assertEq(find(fx, "broadcast"), nil)
  assertEq(find(fx, "penalty"), nil)
end)

test("relocation of an unknown player is ignored", function()
  local r = running()
  assertEq(#r:relocated(12, 42), 0)
end)

test("catch progress reported at 1% precision", function()
  local r = running()
  local fx = r:tick(12.5, stillCars(), {})
  assertNear(find(fx, "state", 2).catchProgress, 0.21, 1e-9)
end)

test("catch progress is floored, never reported as 1 before the catch", function()
  local r = running()
  local fx
  for i = 1, 27 do fx = r:tick(11 + i * 0.25, stillCars(), {}) end
  fx = r:tick(17.99, stillCars(), {})
  assertEq(find(fx, "roundEnd"), nil)
  assertNear(find(fx, "state", 2).catchProgress, 0.99, 1e-9)
end)

test("joining during the chase tells how long it has been running", function()
  local r = running()
  local fx = r:playerJoined(41, 9, "Zed")
  assertNear(find(fx, "setup", 9).chaseElapsed, 30, 1e-9)
  local r2 = started()
  assertEq(find(r2:playerJoined(2, 9, "Zed"), "setup", 9).chaseElapsed, nil)
end)

local function chasing(cfg)
  local r = started(cfg)
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  return r
end

local function farCars() return {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(900, 50)} end

test("sight pings carry the exact runner position the round used, geo included", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  local function cars()
    local c = farCars()
    c[1].geo = { lat = 52, lon = 5, h = 0 }
    return c
  end
  r:sightReport(12, 2, true)
  assertEq(find(r:tick(12, cars(), {}), "live").geo.lat, 52)
  r:sightReport(12.5, 2, false)
  local lost
  for t = 13, 16 do lost = lost or find(r:tick(t, cars(), {}), "lastSeen") end
  assertEq(lost.geo.lat, 52)
  local regular
  for t = 17, 50 do regular = regular or find(r:tick(t, cars(), {}), "lastSeen") end
  assertEq(regular.geo.lat, 52)
end)

test("a cop's sight sends live updates and holds back the regular ping", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  r:sightReport(12, 2, true)
  local fx = r:tick(12, farCars(), {})
  local e = find(fx, "live")
  assertNear(e.pos.x, 0, 1e-9); assertNear(e.nearestCop, 300, 1e-9)
  assertEq(find(r:tick(12.5, farCars(), {}), "live"), nil)
  assertEq(find(r:tick(13, farCars(), {}), "live") ~= nil, true)
  for t = 14, 41 do
    if t % 5 == 0 then r:sightReport(t, 2, true) end
    fx = r:tick(t, farCars(), {})
    assertEq(find(fx, "lastSeen"), nil)
  end
end)

test("only a close cop who sees the runner gets no route", function()
  local r = chasing()
  r:sightReport(12, 2, true)
  local cars = {[1]=kmh(0, 50), [2]=kmh(40, 50), [3]=kmh(45, 50)}
  local e = find(r:tick(12, cars, {}), "live")
  assertEq(e.noRoute[2], true); assertEq(e.noRoute[3], nil)
  local r2 = chasing()
  r2:sightReport(12, 2, true)
  assertEq(find(r2:tick(12, farCars(), {}), "live").noRoute[2], nil)
end)

test("losing sight sends an immediate last seen after the grace period", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  r:sightReport(12, 2, true)
  r:tick(12, farCars(), {})
  r:sightReport(20, 2, false)
  local fx = r:tick(21, farCars(), {})
  assertEq(find(fx, "live") ~= nil, true); assertEq(find(fx, "lastSeen"), nil)
  fx = r:tick(21.6, farCars(), {})
  assertEq(find(fx, "lastSeen") ~= nil, true)
  assertEq(find(fx, "spotted").spotted, false)
  assertEq(find(r:tick(22, farCars(), {}), "live"), nil)
  assertEq(find(r:tick(51.5, farCars(), {}), "lastSeen"), nil)
  assertEq(find(r:tick(51.6, farCars(), {}), "lastSeen") ~= nil, true)
end)

test("spotted is announced once when sight starts", function()
  local r = chasing()
  r:sightReport(12, 2, true)
  assertEq(find(r:tick(12, farCars(), {}), "spotted").spotted, true)
  assertEq(find(r:tick(13, farCars(), {}), "spotted"), nil)
end)

test("sight is off when sightMaxMeters is 0", function()
  local r = chasing({sightMaxMeters=0, lastSeenIntervalSeconds=30})
  r:sightReport(12, 2, true)
  assertEq(find(r:tick(12, farCars(), {}), "live"), nil)
  assertEq(find(r:tick(41, farCars(), {}), "lastSeen") ~= nil, true)
end)

test("sight reports from the runner or before the chase are ignored", function()
  local r = started()
  r:sightReport(2, 2, true)
  r:tick(4, stillCars(), {}); r:tick(11, stillCars(), {})
  assertEq(find(r:tick(12, farCars(), {}), "live"), nil)
  r:sightReport(12, 1, true)
  assertEq(find(r:tick(13, farCars(), {}), "live"), nil)
end)

test("a cop who leaves stops counting as sight", function()
  local r = chasing()
  r:sightReport(12, 2, true)
  r:tick(12, farCars(), {})
  r:playerLeft(13, 2)
  r:tick(13, farCars(), {})
  assertEq(find(r:tick(15, {[1]=kmh(0, 50), [3]=kmh(900, 50)}, {}), "live"), nil)
end)

test("no live updates after the runner is caught", function()
  local r = chasing({catchHoldSeconds=1})
  r:sightReport(12, 2, true)
  local held = {[1]=car(0), [2]=car(5), [3]=car(500)}
  local fx = r:tick(12, held, {})
  fx = r:tick(13.1, held, {})
  assertEq(find(fx, "live"), nil)
end)

test("the record carries cops, their sight time, hidden time and lost count", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  r:sightReport(11, 2, true)
  for t = 11, 20 do r:tick(t, farCars(), {}) end
  r:sightReport(20, 2, false)
  for t = 21, 31 do r:tick(t, farCars(), {}) end
  local fx = r:endCalled(31, 1)
  local run = find(fx, "record").run
  assertEq(run.copIds[1], 2); assertEq(run.copIds[2], 3); assertEq(#run.copIds, 2)
  assertNear(run.copSight[1], 10, 1.01); assertEq(run.copSight[2], 0)
  assertNear(run.hiddenSeconds, 10, 1.01)
  assertEq(run.lostCount, 1)
  assertNear(run.chaseSeconds, 20, 1e-9)
end)

test("without sight the record has no hidden time or lost count", function()
  local r = chasing({sightMaxMeters=0})
  for t = 12, 20 do r:tick(t, farCars(), {}) end
  local run = find(r:endCalled(20, 1), "record").run
  assertEq(run.hiddenSeconds, nil); assertEq(run.lostCount, nil)
  assertEq(#run.copIds, 2)
end)

test("a cop who left before the end is not in the record", function()
  local r = chasing()
  for t = 12, 15 do r:tick(t, farCars(), {}) end
  r:playerLeft(15, 3)
  local run = find(r:endCalled(20, 1), "record").run
  assertEq(#run.copIds, 1); assertEq(run.copIds[1], 2)
end)

test("a cop whose game stops reporting stops counting as sight", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  r:sightReport(12, 2, true)
  r:tick(12, farCars(), {})
  local lost
  for t = 13, 30 do
    local fx = r:tick(t, farCars(), {})
    if find(fx, "lastSeen") then lost = t end
  end
  assertEq(lost, 24)
end)

test("sight time stays with the cop's name when they leave, not with the reused pid", function()
  local r = chasing()
  r:sightReport(11, 3, true)
  local near = {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(200, 50)}
  for t = 12, 20 do r:tick(t, near, {}) end
  r:playerLeft(20, 3)
  r:playerJoined(21, 3, "Cid")
  r:playerJoined(21, 4, "Ann")
  for t = 22, 25 do r:tick(t, {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(900, 50), [4]=kmh(200, 50)}, {}) end
  local run = find(r:endCalled(25, 1), "record").run
  local byPid = {}
  for i, pid in ipairs(run.copIds) do byPid[pid] = run.copSight[i] end
  assertEq(byPid[3], 0)
  assertEq(byPid[4] >= 8, true)
end)

local BUILD = { model = "pickup", config = { format = 2, model = "pickup", parts = { pickup_engine = "v8" }, vars = {} }, step = 3, name = "Gavril D-Series" }

local function evolvingPrep()
  local r = round.new((config.merge(nil)))
  local fx = r:start(0, 1, 2, players, { build = BUILD })
  return r, fx
end

local NEW = { format = 2, model = "pickup", parts = { pickup_engine = "v8_60" }, vars = {} }

local function rebuilt(r, now)
  return find(r:setupReceived(now or 2, 1, NEW), "rebuild").id
end

local function allReady(r, id, now)
  for _, p in ipairs({ 1, 2, 3 }) do r:vehicleReady(now or 3, p, id) end
end

test("an evolving start skips picking and sets everyone up with the build", function()
  local r, fx = evolvingPrep()
  assertEq(r.state, "prep"); assertEq(r.evolving, true)
  assertEq(find(fx, "pickVehicle"), nil)
  assertEq(count(fx, "setup"), 3)
  assertEq(r.vehicle.config, BUILD.config); assertEq(r.vehicle.model, "pickup")
end)

test("apply asks the runner for his setup, then rebuilds every car until all are ready", function()
  local r = evolvingPrep()
  local fx = r:apply(1, 2)
  assertEq(r.state, "applying"); assertEq(find(fx, "requestSetup").pid, 1)
  fx = r:setupReceived(2, 1, NEW)
  local id = find(fx, "rebuild").id
  assertEq(find(fx, "rebuild").config, NEW); assertEq(r.vehicle.config, NEW)
  assertEq(#r:vehicleReady(3, 1, id), 0); assertEq(#r:vehicleReady(3, 2, id), 0)
  assertEq(r.state, "applying")
  fx = r:vehicleReady(3, 3, id)
  assertEq(find(fx, "applied") ~= nil, true); assertEq(r.state, "ready")
end)

test("a car report from before the rebuild doesn't count as ready", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  local id = rebuilt(r)
  allReady(r, nil)
  assertEq(r.state, "applying")
  r:vehicleReady(3, 1, id); r:vehicleReady(3, 2, id)
  assertEq(find(r:vehicleReady(3, 3, id), "applied") ~= nil, true)
end)

test("a car report for an earlier rebuild doesn't count as ready", function()
  local old = evolvingPrep()
  old:apply(1, 2)
  local oldId = rebuilt(old)
  local r = evolvingPrep()
  r:apply(1, 2)
  local id = rebuilt(r)
  assertEq(id ~= oldId, true)
  allReady(r, oldId)
  assertEq(r.state, "applying")
end)

test("the rebuild after a missing setup reply has its own id", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  local id = find(r:tick(6, stillCars(), {}), "rebuild").id
  assertEq(id ~= nil, true)
  allReady(r, id, 7)
  assertEq(r.state, "ready")
end)

test("only the runner's setup counts, and only once", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  assertEq(#r:setupReceived(2, 2, NEW), 0)
  r:setupReceived(2, 1, NEW)
  assertEq(#r:setupReceived(2.5, 1, BUILD.config), 0)
  assertEq(r.vehicle.config, NEW)
end)

test("applying moves on 20 s after the rebuild", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  r:setupReceived(2, 1, NEW)
  assertEq(find(r:tick(21.9, stillCars(), {}), "applied"), nil)
  local e = find(r:tick(22, stillCars(), {}), "applied")
  assertEq(e.timedOut, true); assertEq(r.state, "ready")
end)

test("without a setup reply the cars rebuild with the current build after 5 s", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  assertEq(find(r:tick(5.9, stillCars(), {}), "rebuild"), nil)
  local fx = r:tick(6, stillCars(), {})
  assertEq(find(fx, "rebuild").config, BUILD.config)
  assertEq(find(fx, "applied"), nil)
  assertEq(find(r:tick(25.9, stillCars(), {}), "applied"), nil)
  assertEq(find(r:tick(26, stillCars(), {}), "applied") ~= nil, true)
  assertEq(r.vehicle.config, BUILD.config)
end)

test("GO needs the change applied first in evolving mode", function()
  local r = evolvingPrep()
  assertEq(find(r:go(1, 2), "reply").msg, "Apply the change first")
  r:apply(1, 2)
  local id = rebuilt(r)
  assertEq(find(r:go(2.5, 2), "reply").msg, "Apply the change first")
  allReady(r, id)
  assertEq(find(r:go(4, 2), "countdown") ~= nil, true)
end)

test("apply only works during evolving prep", function()
  local r = started()
  assertEq(find(r:apply(5, 2), "reply") ~= nil, true)
  local e = evolvingPrep()
  e:apply(1, 2)
  assertEq(find(e:apply(1.5, 2), "reply") ~= nil, true)
end)

test("new car is not available in evolving mode", function()
  local r = evolvingPrep()
  assertEq(find(r:reroll(1, 2), "reply").msg, "New car isn't available in evolving mode")
  assertEq(r.state, "prep")
end)

test("the runner leaving while applying cancels the round", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  local fx = r:playerLeft(2, 1)
  assertEq(find(fx, "roundEnd") ~= nil, true); assertEq(r.state, "idle")
end)

test("a cop leaving while applying no longer holds the round up", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  local id = rebuilt(r)
  r:vehicleReady(3, 1, id); r:vehicleReady(3, 2, id)
  local fx = r:playerLeft(4, 3)
  assertEq(find(fx, "applied") ~= nil, true); assertEq(r.state, "ready")
end)

test("the record keeps the mode and the build", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  allReady(r, rebuilt(r))
  r:go(4, 2)
  r:tick(7, stillCars(), {}); r:tick(14, stillCars(), {})
  local run = find(r:endCalled(30, 1), "record").run
  assertEq(run.mode, "evolving"); assertEq(run.buildStep, 3); assertEq(run.buildName, "Gavril D-Series")
  local plain = chasing()
  assertEq(find(plain:endCalled(20, 1), "record").run.mode, "random")
end)

test("evolving runs don't store the whole build config in the leaderboard", function()
  local r = evolvingPrep()
  r:apply(1, 2)
  allReady(r, rebuilt(r))
  r:go(4, 2)
  r:tick(7, stillCars(), {}); r:tick(14, stillCars(), {})
  assertEq(find(r:endCalled(30, 1), "record").run.config, nil)
end)

test("live nearest-cop distance ignores cops serving a penalty", function()
  local r = chasing()
  r.penalties[2] = 999
  r:sightReport(12, 3, true)
  local cars = {[1]=kmh(0, 50), [2]=kmh(20, 50), [3]=kmh(300, 50)}
  assertNear(find(r:tick(12, cars, {}), "live").nearestCop, 300, 1e-9)
end)

test("a gap without the runner's position isn't credited all at once", function()
  local r = chasing()
  r:tick(12, farCars(), {})
  r:tick(32, farCars(), {})
  local run = find(r:endCalled(33, 1), "record").run
  assertEq(run.hiddenSeconds <= 3, true)
end)

test("a sight report from a cop far beyond sight range doesn't count", function()
  local r = chasing({sightMaxMeters=400})
  r:sightReport(12, 3, true)
  assertEq(find(r:tick(12, {[1]=kmh(0, 50), [2]=kmh(300, 50), [3]=kmh(900, 50)}, {}), "live"), nil)
end)

test("an illegal reset is noted", function()
  local r = running()
  r:vehicleReset(15.04, 1)
  local n = r.timeline[1]
  assertEq(n.kind, "illegalReset"); assertEq(n.name, "Reinder"); assertEq(n.t, 4)
  assertEq(n.seconds, nil)
end)

test("a crash penalty is noted with its seconds", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 80), [2]=kmh(200, 120), [3]=kmh(500, 0)}, {})
  r:tick(11.5, {[1]=kmh(0, 80), [2]=kmh(200, 10), [3]=kmh(500, 0)}, {})
  local n
  for _, e in ipairs(r.timeline) do if e.kind == "penalty" then n = e end end
  assertEq(n.kind, "penalty"); assertEq(n.name, "Bob"); assertEq(n.seconds, 10); assertEq(n.t, 0.5)
end)

test("losing the cops is noted", function()
  local r = chasing({lastSeenIntervalSeconds=30})
  r:sightReport(11, 2, true)
  for t = 11, 20 do r:tick(t, farCars(), {}) end
  r:sightReport(20, 2, false)
  for t = 21, 31 do r:tick(t, farCars(), {}) end
  local lost
  for _, n in ipairs(r.timeline) do if n.kind == "lost" then lost = n end end
  assertEq(lost ~= nil, true)
  assertEq(lost.name, "Reinder")
end)

test("a teleport is noted", function()
  local r = running()
  r:tick(11.25, {[1]=kmh(0, 50), [2]=kmh(10, 50), [3]=kmh(500, 0)}, {})
  r:tick(11.5, {[1]=kmh(0, 50), [2]=kmh(900, 50), [3]=kmh(500, 0)}, {})
  local n = r.timeline[1]
  assertEq(n.kind, "teleport"); assertEq(n.name, "Bob")
end)

test("the timeline stops at 50", function()
  local r = running()
  for i = 1, 60 do r:note(11 + i, "partsChanged", "Bob") end
  assertEq(#r.timeline, 50)
  local idle = round.new((config.merge(nil)))
  idle:note(1, "partsChanged", "Bob")
  assertEq(#idle.timeline, 0)
end)

test("the timeline is saved with the run", function()
  local r = running()
  r:note(15, "partsChanged", "Bob")
  r:vehicleReset(16, 1)
  local run = find(r:endCalled(20, 1), "record").run
  assertEq(#run.timeline, 2)
  assertEq(run.timeline[1].kind, "partsChanged"); assertEq(run.timeline[1].t, 4)
  assertEq(run.timeline[2].kind, "illegalReset")
  local quiet = find(running():endCalled(20, 1), "record").run
  assertEq(#quiet.timeline, 0)
end)

test("start keeps the sky it is given, New car keeps it, clear drops it", function()
  local r = round.new((config.merge(nil)))
  r:start(0, 1, 2, players, { sky = { weather = "rain" } })
  r:vehiclePicked(1, 2, "pickup", "cfg", players)
  r:reroll(2, 2)
  r:vehiclePicked(3, 2, "etk800", "cfg", players)
  assertEq(r.sky.weather, "rain")
  r:clear()
  assertEq(r.sky, nil)
end)
