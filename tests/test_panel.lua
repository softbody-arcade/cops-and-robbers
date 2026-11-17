local panel = require("cnr.panel")

test("allow accepts bindable, start <name> and auto on/off", function()
  assertEq(panel.allow("  GO "), "go")
  assertEq(panel.allow("start Reinder"), "start Reinder")
  assertEq(panel.allow("START =next"), "start =next")
  assertEq(panel.allow("auto off"), "auto off")
  assertEq(panel.allow("next"), "next")
  assertEq(panel.allow("test cop"), "test cop")
end)

test("allow rejects over-long and unknown text", function()
  assertEq(panel.allow("set headStartSeconds 1"), nil)
  assertEq(panel.allow("start"), nil)
  assertEq(panel.allow("auto maybe"), nil)
  assertEq(panel.allow("start " .. string.rep("a", 70)), nil)
  assertEq(panel.allow(nil), nil)
end)

test("can follows the round state", function()
  local idle = panel.can("idle", false)
  assertEq(idle.start, true); assertEq(idle.test, true); assertEq(idle.settings, true)
  assertEq(idle.go, false); assertEq(idle.reroll, false); assertEq(idle["end"], false); assertEq(idle.stop, false)
  local prep = panel.can("prep", false)
  assertEq(prep.go, true); assertEq(prep.reroll, true); assertEq(prep.stop, true); assertEq(prep.start, false)
  assertEq(panel.can("headstart", false)["end"], false)
  assertEq(panel.can("running", false)["end"], true)
  assertEq(panel.can("running", true).start, true)
end)

test("snapshot sorts players, floors elapsed and copies lists", function()
  local cfg = { excludedModels = { "citybus" }, autoNextRound = true, headStartSeconds = 7 }
  local snap = panel.snapshot({
    version = "1.5.0", map = "west_coast_usa", phase = "running", runner = "Ann", test = false,
    elapsed = 12.9, players = { { name = "bob", runs = 0 }, { name = "Ann", runs = 1 } }, cfg = cfg, defaults = { excludedModels = { "x" } },
  })
  assertEq(snap.players[1].name, "Ann"); assertEq(snap.players[2].name, "bob"); assertEq(#snap.players, 2)
  assertEq(snap.elapsed, 12)
  snap.settings.excludedModels[1] = "changed"
  assertEq(cfg.excludedModels[1], "citybus")
  assertEq(snap.auto, true)
  assertEq(snap.can["end"], true)
  assertEq(snap.runner, "Ann"); assertEq(snap.phase, "running"); assertEq(snap.test, false)
  assertEq(snap.car, nil)
  assertEq(panel.snapshot({ phase = "prep", car = "pickup" }).car, "pickup")
end)

test("signature is order independent and sees value changes", function()
  local a, b = {}, {}
  a.x = 1; a.y = { list = { "p", "q" }, flag = true }; a.z = "s"
  b.z = "s"; b.y = { flag = true, list = { "p", "q" } }; b.x = 1
  assertEq(panel.signature(a), panel.signature(b))
  b.y.list[2] = "r"
  assertEq(panel.signature(a) == panel.signature(b), false)
end)

test("applyValues saves several values at once", function()
  local updated, keys = panel.applyValues({}, { headStartSeconds = 9, explodeOnCatch = true, excludedModels = { "citybus", "us_semi" } })
  assertEq(updated.headStartSeconds, 9)
  assertEq(updated.explodeOnCatch, true)
  assertEq(updated.excludedModels[2], "us_semi")
  assertEq(table.concat(keys, ","), "excludedModels,explodeOnCatch,headStartSeconds")
end)

test("applyValues formats numbers without trailing .0", function()
  assertEq(tostring(panel.applyValues({}, { headStartSeconds = 8.0 }).headStartSeconds), "8")
  assertEq(panel.applyValues({}, { stillMaxSpeedKmh = 1.5 }).stillMaxSpeedKmh, 1.5)
end)

test("applyValues rejects bad input", function()
  local u, err = panel.applyValues({}, { headStartSeconds = 9, catchHoldSeconds = 0 })
  assertEq(u, nil); assertEq(err:find("catchHoldSeconds", 1, true) ~= nil, true)
  u, err = panel.applyValues({}, { nope = 1 })
  assertEq(u, nil); assertEq(err:find("Unknown setting", 1, true) ~= nil, true)
  for _, bad in ipairs({ "x", {} }) do
    u, err = panel.applyValues({}, bad)
    assertEq(u, nil); assertEq(err, "Nothing to save")
  end
  u, err = panel.applyValues({}, nil)
  assertEq(u, nil); assertEq(err, "Nothing to save")
  local ok, res, lerr = pcall(panel.applyValues, {}, { excludedModels = { "a", true } })
  assertEq(ok, true)
  assertEq(res, nil); assertEq(lerr:find("excludedModels", 1, true) ~= nil, true)
end)

test("applyValues leaves raw untouched", function()
  local raw = { headStartSeconds = 5 }
  panel.applyValues(raw, { headStartSeconds = 9 })
  assertEq(raw.headStartSeconds, 5)
end)

test("applyValues resets spawn distances when min is above the default max", function()
  local updated, err = panel.applyValues({ copSpawnMinMeters = 200 }, { copSpawnMinMeters = 50, copSpawnMaxMeters = 150 })
  assertEq(err ~= nil and type(err) == "string", false)
  assertEq(updated.copSpawnMinMeters, 50); assertEq(updated.copSpawnMaxMeters, 150)
end)

test("applyValues accepts both spawn distances lowered together", function()
  local updated = panel.applyValues({}, { copSpawnMinMeters = 10, copSpawnMaxMeters = 20 })
  assertEq(updated.copSpawnMinMeters, 10); assertEq(updated.copSpawnMaxMeters, 20)
end)

test("applyValues still rejects a max below the min", function()
  local updated, err = panel.applyValues({}, { copSpawnMinMeters = 100, copSpawnMaxMeters = 80 })
  assertEq(updated, nil)
  assertEq(err:find("copSpawnMaxMeters", 1, true) ~= nil, true)
end)

test("applyValues raises the weather change max to the min", function()
  local updated = panel.applyValues({}, { weatherChangeMinMinutes = 10, weatherChangeMaxMinutes = 5 })
  assertEq(updated.weatherChangeMinMinutes, 10); assertEq(updated.weatherChangeMaxMinutes, 10)
end)

test("applyValues saves both weather change minutes together in any order", function()
  local u = panel.applyValues({ weatherChangeMinMinutes = 5, weatherChangeMaxMinutes = 8 }, { weatherChangeMinMinutes = 2, weatherChangeMaxMinutes = 3 })
  assertEq(u.weatherChangeMinMinutes, 2); assertEq(u.weatherChangeMaxMinutes, 3)
  u = panel.applyValues({}, { weatherChangeMinMinutes = 1, weatherChangeMaxMinutes = 2 })
  assertEq(u.weatherChangeMinMinutes, 1); assertEq(u.weatherChangeMaxMinutes, 2)
  u = panel.applyValues({ weatherChangeMinMinutes = 5, weatherChangeMaxMinutes = 8 }, { weatherChangeMinMinutes = 6, weatherChangeMaxMinutes = 4 })
  assertEq(u.weatherChangeMinMinutes, 6); assertEq(u.weatherChangeMaxMinutes, 6)
end)

test("applyValues accepts list entries that are strings or numbers only", function()
  local updated = panel.applyValues({}, { excludedModels = { "a", 3 } })
  assertEq(updated.excludedModels[1], "a"); assertEq(updated.excludedModels[2], "3")
  local u, err = panel.applyValues({}, { excludedModels = { "a", { x = 1 } } })
  assertEq(u, nil); assertEq(err:find("excludedModels", 1, true) ~= nil, true)
  u, err = panel.applyValues({}, { excludedModels = 5 })
  assertEq(u, nil); assertEq(err:find("excludedModels", 1, true) ~= nil, true)
  assertEq(panel.applyValues({}, { excludedModels = "citybus, us_semi" }).excludedModels[2], "us_semi")
end)

test("playerRows sorts case-insensitively and flags next and last", function()
  local rows = panel.playerRows({
    { name = "bob", runs = 2 }, { name = "Ann", runs = 0, role = "runner", state = "ready" }, { name = "Cy", runs = 1 },
  }, "Ann", "bob")
  assertEq(#rows, 3)
  assertEq(rows[1].name, "Ann"); assertEq(rows[2].name, "bob"); assertEq(rows[3].name, "Cy")
  assertEq(rows[1].next, true); assertEq(rows[1].last, false); assertEq(rows[1].role, "runner"); assertEq(rows[1].state, "ready")
  assertEq(rows[2].next, false); assertEq(rows[2].last, true); assertEq(rows[2].runs, 2)
  assertEq(rows[3].role, nil)
end)

test("goBlocked says why GO waits", function()
  assertEq(panel.goBlocked("prep", true, "Bob", 0), "Waiting for Bob to apply the change")
  assertEq(panel.goBlocked("applying", true, "Bob", 2), "Applying the change: 2 cars still loading")
  assertEq(panel.goBlocked("applying", true, "Bob", 1), "Applying the change: 1 car still loading")
  assertEq(panel.goBlocked("applying", true, "Bob", 0), "Applying the change")
  assertEq(panel.goBlocked("applying", true, "Bob", nil), "Applying the change")
  assertEq(panel.goBlocked("prep", false, "Bob", 0), nil)
  assertEq(panel.goBlocked("applying", false, "Bob", 3), nil)
  assertEq(panel.goBlocked("running", true, "Bob", 0), nil)
  assertEq(panel.goBlocked("idle", true, nil, 0), nil)
end)

test("New sky is offered before GO with a random setting", function()
  assertEq(panel.allow("sky"), "sky")
  assertEq(panel.can("prep", false, false, true).sky, true)
  assertEq(panel.can("ready", false, true, true).sky, true)
  assertEq(panel.can("prep", false, false, false).sky, false)
  assertEq(panel.can("countdown", false, false, true).sky, false)
  assertEq(panel.snapshot({ phase = "prep", skyRandom = true }).can.sky, true)
end)

test("snapshot passes the traffic note", function()
  assertEq(panel.snapshot({ trafficNote = "x" }).trafficNote, "x")
end)

test("player rows say who sits out", function()
  local rows = panel.playerRows({ { name = "Ann", runs = 0, sitOut = true }, { name = "Bob", runs = 1 } })
  assertEq(rows[1].sitOut, true); assertEq(rows[2].sitOut, nil)
end)
