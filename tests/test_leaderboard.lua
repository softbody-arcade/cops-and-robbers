local leaderboard = require("cnr.leaderboard")

local function run(player, s, model)
  return {player=player, survivedSeconds=s, map="west_coast_usa", model=model or "pickup", config="x", releasedAt=0, endedAt=s, endReason="caught"}
end

test("load handles nil and missing runs", function()
  assertEq(leaderboard.load(nil).format, 2)
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

test("best filters by map", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, {player="A", survivedSeconds=100, map="italy"})
  leaderboard.add(b, {player="B", survivedSeconds=50, map="west_coast_usa"})
  assertEq(#leaderboard.best(b, 10, "italy"), 1)
  assertEq(leaderboard.best(b, 10, "italy")[1].player, "A")
  assertEq(#leaderboard.best(b, 10), 2)
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


test("validShape accepts a missing file or a current board with a runs table", function()
  assertEq(leaderboard.validShape(nil), true)
  assertEq(leaderboard.validShape({ format = 2, runs = {} }), true)
  assertEq(leaderboard.validShape({ runs = {} }), false)
  assertEq(leaderboard.validShape({ format = 1, runs = {} }), false)
  assertEq(leaderboard.validShape({ format = 2, runs = 5 }), false)
  assertEq(leaderboard.validShape({1, 2}), false)
end)

local function fullRun(o)
  return {
    player = o.player, key = o.key or ("k:" .. o.player), survivedSeconds = o.s, chaseSeconds = o.s, map = o.map or "west_coast_usa",
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
  assertEq(#c, 3); assertEq(c[1].name, "Bob"); assertEq(c[1].catches, 1); assertEq(c[1].fastest, 50)
  local maps = leaderboard.maps(b)
  assertEq(#maps, 2); assertEq(maps[1], "italy"); assertEq(maps[2], "west_coast_usa")
end)

test("a renamed player shows the latest name everywhere", function()
  local b = statsBoard()
  leaderboard.add(b, fullRun({ player = "Ann", s = 10, at = 9, cops = { "k:Bob" }, copNames = { "Bobby" }, copSight = { 1 } }))
  local p = byName(leaderboard.players(b, nil, 20))
  assertEq(p.Bobby ~= nil, true); assertEq(p.Bob, nil)
end)

test("a renamed player shows the latest name in every tab and map filter", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, fullRun({ player = "Ann", s = 50, at = 1, map = "italy", catchers = { "Bob" }, catcherKeys = { "k:Bob" },
    cops = { "k:Bob" }, copNames = { "Bob" }, copSight = { 10 } }))
  leaderboard.add(b, fullRun({ player = "Robert", key = "k:Bob", s = 80, at = 2 }))
  assertEq(leaderboard.cops(b, nil, 10)[1].name, "Robert")
  assertEq(byName(leaderboard.players(b, "italy", 20)).Robert ~= nil, true)
  assertEq(byName(leaderboard.players(b, "italy", 20)).Bob, nil)
  local early = leaderboard.load(nil)
  leaderboard.add(early, fullRun({ player = "Bob", s = 90, at = 1 }))
  leaderboard.add(early, fullRun({ player = "Ann", s = 10, at = 2, cops = { "k:Bob" }, copNames = { "Robert" }, copSight = { 1 } }))
  assertEq(leaderboard.runners(early, nil, 10)[1].player, "Robert")
end)

test("the mode filter counts runs without a mode as random", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, fullRun({ player = "Ann", s = 50, at = 1 }))
  local evo = fullRun({ player = "Bob", s = 90, at = 2 })
  evo.mode = "evolving"
  leaderboard.add(b, evo)
  assertEq(#leaderboard.runners(b, { mode = "evolving" }, 10), 1)
  assertEq(leaderboard.runners(b, { mode = "evolving" }, 10)[1].player, "Bob")
  assertEq(leaderboard.runners(b, { mode = "random" }, 10)[1].player, "Ann")
  assertEq(#leaderboard.runners(b, { mode = "random" }, 10), 1)
  assertEq(#leaderboard.runners(b, nil, 10), 2)
  assertEq(#leaderboard.players(b, { mode = "evolving" }, 20), 1)
  assertEq(#leaderboard.runners(b, { map = "west_coast_usa", mode = "evolving" }, 10), 1)
  assertEq(#leaderboard.runners(b, { map = "italy", mode = "evolving" }, 10), 0)
end)

test("cops rows count assists by the same rule as players", function()
  local b = statsBoard()
  local c = byName(leaderboard.cops(b, nil, 10, 20))
  assertEq(c.Ann.assists, 0); assertEq(c.Bob.assists, 0)
  b = leaderboard.load(nil)
  leaderboard.add(b, fullRun({ player = "Bob", s = 100, at = 1, catchers = { "Ann" }, catcherKeys = { "k:Ann" },
    cops = { "k:Ann", "k:Cid" }, copNames = { "Ann", "Cid" }, copSight = { 50, 30 } }))
  leaderboard.add(b, fullRun({ player = "Bob", s = 100, at = 2, catchers = { "Cid" }, catcherKeys = { "k:Cid" },
    cops = { "k:Ann", "k:Cid" }, copNames = { "Ann", "Cid" }, copSight = { 10, 50 } }))
  local rows = byName(leaderboard.cops(b, nil, 10, 20))
  assertEq(rows.Cid.assists, 1); assertEq(rows.Ann.assists, 0)
  assertEq(byName(leaderboard.cops(b, nil, 10, 5)).Ann.assists, 1)
end)

test("cops rank catches first and assists second, including assists without catches", function()
  local b = statsBoard()
  leaderboard.add(b, fullRun({ player = "Runner", s = 20, catchers = { "Kim" }, catcherKeys = { "k:Kim" },
    cops = { "k:Ann", "k:Cid", "k:Pat" }, copNames = { "Ann", "Cid", "Pat" }, copSight = { 10, 10, 0 } }))
  local rows = leaderboard.cops(b)
  assertEq(#rows, 4)
  assertEq(rows[1].name, "Ann"); assertEq(rows[1].assists, 1)
  assertEq(rows[2].name, "Kim"); assertEq(rows[3].name, "Bob")
  assertEq(rows[4].name, "Cid"); assertEq(rows[4].catches, 0)
  assertEq(rows[4].assists, 2); assertEq(rows[4].fastest, nil)
  assertEq(#leaderboard.cops(b, "italy"), 0)
end)

test("rounds lists newest first with cops and sight share", function()
  local b = statsBoard()
  b.runs[1].timeline = { { t = 1, kind = "seen", name = "Ann" } }
  local list = leaderboard.rounds(b, nil, 10)
  assertEq(#list, 3)
  assertEq(list[1].id, 3); assertEq(list[2].id, 2); assertEq(list[3].id, 1)
  assertEq(list[3].player, "Bob"); assertEq(list[3].survivedSeconds, 100)
  assertEq(list[3].endReason, "caught"); assertEq(list[3].map, "west_coast_usa")
  assertEq(list[3].cops[1].name, "Ann"); assertEq(list[3].cops[1].sightPct, 50)
  assertEq(list[3].cops[1].catcher, true); assertEq(list[3].cops[2].catcher, false)
  assertEq(list[3].cops[2].sightPct, 30)
  assertEq(#list[3].timeline, 1)
  assertEq(list[2].timeline, nil)
  assertEq(#leaderboard.rounds(b, nil, 2), 2)
  assertEq(#leaderboard.rounds(b, "italy", 10), 1)
end)

test("an old run without a timeline or sight data", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, { player = "Old", survivedSeconds = 60, map = "italy", endedAt = 5, endReason = "caught" })
  local r = leaderboard.rounds(b, nil, 10)[1]
  assertEq(r.timeline, nil)
  assertEq(#r.cops, 0)
  leaderboard.add(b, fullRun({ player = "Dim", s = 80, at = 6, cops = { "k:A" }, copNames = { "A" }, copSight = { 20 } }))
  local d = leaderboard.rounds(b, nil, 10)[1]
  assertEq(d.cops[1].sightPct, nil)
  assertEq(d.timeline, nil)
  b.runs[2].timeline = {}
  assertEq(leaderboard.rounds(b, nil, 10)[1].timeline, nil)
end)

test("a run saved with a timeline is tracked even when nothing happened", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, { player = "Old", survivedSeconds = 60, map = "italy", endedAt = 5, endReason = "caught" })
  leaderboard.add(b, { player = "Clean", survivedSeconds = 30, map = "italy", endedAt = 6, endReason = "caught", timeline = {} })
  leaderboard.add(b, { player = "Busy", survivedSeconds = 90, map = "italy", endedAt = 7, endReason = "escaped",
    timeline = { { t = 3, kind = "lost", name = "Busy" } } })
  local list = leaderboard.rounds(b, nil, 10)
  assertEq(list[1].player, "Busy"); assertEq(list[1].tracked, true); assertEq(#list[1].timeline, 1)
  assertEq(list[2].player, "Clean"); assertEq(list[2].tracked, true); assertEq(list[2].timeline, nil)
  assertEq(list[3].player, "Old"); assertEq(list[3].tracked, nil); assertEq(list[3].timeline, nil)
end)

test("rounds also gives how many rounds match the filter", function()
  local b = statsBoard()
  local list, total = leaderboard.rounds(b, nil, 2)
  assertEq(#list, 2); assertEq(total, 3)
  list, total = leaderboard.rounds(b, "italy", 10)
  assertEq(#list, 1); assertEq(total, 1)
end)

test("rounds pass the run's conditions on", function()
  local b = leaderboard.load(nil)
  leaderboard.add(b, { player = "A", survivedSeconds = 60, map = "italy", endedAt = 5, endReason = "caught", sky = { time = "night", weather = "snow" } })
  leaderboard.add(b, { player = "B", survivedSeconds = 60, map = "italy", endedAt = 6, endReason = "caught" })
  local list = leaderboard.rounds(b, nil, 10)
  assertEq(list[2].sky.weather, "snow"); assertEq(list[1].sky, nil)
end)

test("the traffic filter splits runs with and without traffic", function()
  local b = leaderboard.load(nil)
  local a = run("A", 300); a.traffic = 5
  local plain = run("B", 200)
  local zero = run("C", 100); zero.traffic = 0
  leaderboard.add(b, a); leaderboard.add(b, plain); leaderboard.add(b, zero)
  local with = leaderboard.runners(b, { traffic = "with" }, 10)
  assertEq(#with, 1); assertEq(with[1].player, "A")
  local without = leaderboard.runners(b, { traffic = "without" }, 10)
  assertEq(#without, 2); assertEq(without[1].player, "B"); assertEq(without[2].player, "C")
  assertEq(#leaderboard.runners(b, {}, 10), 3)
  assertEq(#leaderboard.rounds(b, { traffic = "without" }), 2)
  assertEq(leaderboard.rounds(b, { traffic = "with" })[1].traffic, 5)
end)

test("traffic for the runner only is its own kind in the filter and reaches the rounds list", function()
  local b = leaderboard.load(nil)
  local all = run("A", 300); all.traffic = 5
  local runnerOnly = run("B", 200); runnerOnly.traffic = 5; runnerOnly.trafficRunnerOnly = true
  all.catchers = { "Lee" }; runnerOnly.catchers = { "Kim" }
  local none = run("C", 100)
  leaderboard.add(b, all); leaderboard.add(b, runnerOnly); leaderboard.add(b, none)
  local with = leaderboard.runners(b, { traffic = "with" }, 10)
  assertEq(#with, 1); assertEq(with[1].player, "A")
  local runner = leaderboard.runners(b, { traffic = "runner" }, 10)
  assertEq(#runner, 1); assertEq(runner[1].player, "B")
  local without = leaderboard.runners(b, { traffic = "without" }, 10)
  assertEq(#without, 1); assertEq(without[1].player, "C")
  local cops = leaderboard.cops(b, { traffic = "runner" }, 10)
  assertEq(#cops, 1); assertEq(cops[1].name, "Kim")
  local rounds = leaderboard.rounds(b, nil, 10)
  assertEq(rounds[2].trafficRunnerOnly, true)
  assertEq(rounds[1].trafficRunnerOnly, nil)
  assertEq(rounds[3].trafficRunnerOnly, nil)
end)

test("a timeline cause reaches the rounds list", function()
  local b = leaderboard.load(nil)
  local r = run("Bob", 60)
  r.timeline = { { t = 3, kind = "penalty", name = "Bob", seconds = 10, cause = "traffic" } }
  leaderboard.add(b, r)
  assertEq(leaderboard.rounds(b)[1].timeline[1].cause, "traffic")
end)
