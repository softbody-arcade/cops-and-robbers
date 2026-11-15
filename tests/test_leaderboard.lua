local leaderboard = require("cnr.leaderboard")

local function run(player, s, model)
  return {player=player, survivedSeconds=s, map="west_coast_usa", model=model or "pickup", config="x", releasedAt=0, endedAt=s, endReason="caught"}
end

test("load handles nil and missing runs", function()
  assertEq(#leaderboard.load(nil).runs, 0)
  assertEq(#leaderboard.load({}).runs, 0)
  assertEq(#leaderboard.load({runs={run("a", 1)}}).runs, 1)
end)

test("add appends", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, run("a", 1))
  leaderboard.add(b, run("a", 2))
  assertEq(#b.runs, 2)
end)

test("best keeps max per player sorted descending", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, run("Reinder", 100))
  leaderboard.add(b, run("Bob", 300, "etk800"))
  leaderboard.add(b, run("Reinder", 200))
  local best = leaderboard.best(b)
  assertEq(#best, 2)
  assertEq(best[1].player, "Bob"); assertEq(best[1].survivedSeconds, 300); assertEq(best[1].model, "etk800")
  assertEq(best[2].player, "Reinder"); assertEq(best[2].survivedSeconds, 200)
end)

test("best respects limit, default 10", function()
  local b = leaderboard.load(nil)
  for i = 1, 12 do leaderboard.add(b, run("p" .. i, i)) end
  assertEq(#leaderboard.best(b), 10)
  assertEq(#leaderboard.best(b, 3), 3)
  assertEq(leaderboard.best(b, 3)[1].player, "p12")
end)

test("formatTime", function()
  assertEq(leaderboard.formatTime(272.4), "4:32")
  assertEq(leaderboard.formatTime(59.99), "0:59")
  assertEq(leaderboard.formatTime(3725), "62:05")
  assertEq(leaderboard.formatTime(0), "0:00")
end)

test("formatTop", function()
  local b = leaderboard.load(nil)
  local lines = leaderboard.formatTop(b, 5)
  assertEq(#lines, 1); assertEq(lines[1], "No runs yet")
  leaderboard.add(b, run("Reinder", 272.4))
  lines = leaderboard.formatTop(b, 5)
  assertEq(lines[1], "1. Reinder 4:32 (pickup, west_coast_usa)")
end)

test("best filters by map", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, {player="A", survivedSeconds=100, map="italy"})
  leaderboard.add(b, {player="B", survivedSeconds=50, map="west_coast_usa"})
  assertEq(#leaderboard.best(b, 10, "italy"), 1)
  assertEq(leaderboard.best(b, 10, "italy")[1].player, "A")
  assertEq(#leaderboard.best(b, 10), 2)
  assertEq(leaderboard.formatTop(b, 5, "utah")[1], "No runs yet")
end)

test("cop stats count catches and fastest catch", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, {player="R", survivedSeconds=200, endReason="caught", catchers={"Bob", "Ann"}})
  leaderboard.add(b, {player="R", survivedSeconds=80, endReason="caught", catchers={"Bob"}})
  leaderboard.add(b, {player="R", survivedSeconds=30, endReason="called", catchers={"Ann"}})
  local lines = leaderboard.formatTopCops(b, 5)
  assertEq(lines[1], "1. Bob 2 catches, fastest 1:20")
  assertEq(lines[2], "2. Ann 1 catch, fastest 3:20")
  assertEq(leaderboard.formatTopCops(leaderboard.load(nil), 5)[1], "No catches yet")
end)

test("best groups runs by account key and shows the latest name", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, {player="guest123", key="beammp:7", survivedSeconds=100, endedAt=1})
  leaderboard.add(b, {player="Reinder", key="beammp:7", survivedSeconds=50, endedAt=2})
  leaderboard.add(b, {player="Bob", survivedSeconds=80, endedAt=3})
  local best = leaderboard.best(b)
  assertEq(#best, 2)
  assertEq(best[1].player, "Reinder"); assertEq(best[1].survivedSeconds, 100)
end)

test("cop stats group by catcher keys when present", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, {player="R", survivedSeconds=200, endReason="caught", catchers={"guest1"}, catcherKeys={"beammp:9"}, endedAt=1})
  leaderboard.add(b, {player="R", survivedSeconds=80, endReason="caught", catchers={"Bob"}, catcherKeys={"beammp:9"}, endedAt=2})
  local lines = leaderboard.formatTopCops(b, 5)
  assertEq(lines[1], "1. Bob 2 catches, fastest 1:20")
  assertEq(lines[2], nil)
end)

test("validRuns detects a wrong shape", function()
  assertEq(leaderboard.validShape(nil), true)
  assertEq(leaderboard.validShape({runs={}}), true)
  assertEq(leaderboard.validShape({runs=5}), false)
  assertEq(leaderboard.validShape({1, 2}), false)
end)

local function fullRun(o)
  return {
    player = o.player, key = "k:" .. o.player, survivedSeconds = o.s, chaseSeconds = o.s, map = o.map or "west_coast_usa",
    model = o.model or "pickup", endedAt = o.at or 0, endReason = o.reason or "caught",
    catchers = o.catchers or {}, catcherKeys = o.catcherKeys or {}, cops = o.cops or {}, copNames = o.copNames or {},
    copSightSeconds = o.copSight or {}, hiddenSeconds = o.hidden, lostCount = o.lost,
  }
end

local function statsBoard()
  local b = leaderboard.load(nil)
  leaderboard.add(b, fullRun({ player = "Bob", s = 100, at = 1, catchers = { "Ann" }, catcherKeys = { "k:Ann" },
    cops = { "k:Ann", "k:Cid" }, copNames = { "Ann", "Cid" }, copSight = { 50, 30 }, hidden = 40, lost = 2 }))
  leaderboard.add(b, fullRun({ player = "Bob", s = 200, at = 2, map = "italy", reason = "escaped",
    cops = { "k:Ann" }, copNames = { "Ann" }, copSight = { 10 }, hidden = 100, lost = 1 }))
  leaderboard.add(b, fullRun({ player = "Ann", s = 50, at = 3, catchers = { "Bob" }, catcherKeys = { "k:Bob" },
    cops = { "k:Bob", "k:Cid" }, copNames = { "Bob", "Cid" }, copSight = { 40, 5 } }))
  return b
end

local function byName(list)
  local t = {}
  for _, p in ipairs(list) do t[p.name] = p end
  return t
end

test("player stats over all maps", function()
  local list = leaderboard.players(statsBoard(), nil, 20)
  assertEq(#list, 3); assertEq(list[1].name, "Ann"); assertEq(list[3].name, "Cid")
  local p = byName(list)
  assertEq(p.Bob.runs, 2); assertEq(p.Bob.best, 200); assertEq(p.Bob.average, 150); assertEq(p.Bob.escapes, 1)
  assertEq(p.Bob.catches, 1); assertEq(p.Bob.assists, 0)
  assertNear(p.Bob.hiddenPct, 140 / 300 * 100, 1e-9); assertEq(p.Bob.lostThem, 3)
  assertEq(p.Ann.runs, 1); assertEq(p.Ann.catches, 1); assertEq(p.Ann.hiddenPct, nil); assertEq(p.Ann.lostThem, nil)
  assertEq(p.Cid.runs, 0); assertEq(p.Cid.best, nil); assertEq(p.Cid.assists, 1)
end)

test("assists need sight for the given share of the chase", function()
  assertEq(byName(leaderboard.players(statsBoard(), nil, 40)).Cid.assists, 0)
  assertEq(byName(leaderboard.players(statsBoard(), nil, 30)).Cid.assists, 1)
end)

test("the map filter limits every stat", function()
  local p = byName(leaderboard.players(statsBoard(), "west_coast_usa", 20))
  assertEq(p.Bob.runs, 1); assertEq(p.Bob.best, 100); assertNear(p.Bob.hiddenPct, 40, 1e-9); assertEq(p.Bob.lostThem, 2)
  assertEq(#leaderboard.players(statsBoard(), "nowhere", 20), 0)
  assertEq(#leaderboard.runners(statsBoard(), "nowhere", 10), 0)
  assertEq(#leaderboard.cops(statsBoard(), "nowhere", 10), 0)
end)

test("runners, cops and maps lists", function()
  local b = statsBoard()
  local r = leaderboard.runners(b, nil, 10)
  assertEq(r[1].player, "Bob"); assertEq(r[1].survivedSeconds, 200); assertEq(r[1].map, "italy")
  local c = leaderboard.cops(b, nil, 10)
  assertEq(#c, 2); assertEq(c[1].name, "Bob"); assertEq(c[1].catches, 1); assertEq(c[1].fastest, 50)
  local maps = leaderboard.maps(b)
  assertEq(#maps, 2); assertEq(maps[1], "italy"); assertEq(maps[2], "west_coast_usa")
end)

test("a renamed player shows the latest name everywhere", function()
  local b = statsBoard()
  leaderboard.add(b, fullRun({ player = "Ann", s = 10, at = 9, cops = { "k:Bob" }, copNames = { "Bobby" }, copSight = { 1 } }))
  local p = byName(leaderboard.players(b, nil, 20))
  assertEq(p.Bobby ~= nil, true); assertEq(p.Bob, nil)
end)

test("isCurrent accepts format 2 and a missing file only", function()
  assertEq(leaderboard.isCurrent(nil), true)
  assertEq(leaderboard.isCurrent({ format = 2, runs = {} }), true)
  assertEq(leaderboard.isCurrent({ runs = {} }), false)
  assertEq(leaderboard.load(nil).format, 2)
end)
