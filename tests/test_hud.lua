local hud = require("copsAndRobbers/hud")

local RULES = {
  runnerCountdownSeconds = 3, headStartSeconds = 7, catchHoldSeconds = 7, catchRadiusMeters = 10, catchMaxSpeedKmh = 3,
  resetWaitSeconds = 7, copResetMinDistanceMeters = 1000, crashSpeedLossKmh = 50, crashPenaltySeconds = 10,
  sightMaxMeters = 400, lastSeenIntervalSeconds = 30, roundTimeLimitSeconds = 0, carMode = "random",
}

local function rules(over)
  local r = {}
  for k, v in pairs(RULES) do r[k] = v end
  for k, v in pairs(over or {}) do r[k] = v end
  return r
end

test("formatTime", function()
  assertEq(hud.formatTime(0), "0:00"); assertEq(hud.formatTime(192.7), "3:12")
end)

test("catchAt extrapolates between samples", function()
  local s = hud.new()
  hud.catchSample(s, 10.0, 0.10); hud.catchSample(s, 10.25, 0.14)
  assertNear(hud.catchAt(s, 10.35), 0.156, 1e-9)
end)

test("catchAt stops extrapolating 0.3 s after the last sample", function()
  local s = hud.new()
  hud.catchSample(s, 10.0, 0.10); hud.catchSample(s, 10.25, 0.14)
  assertNear(hud.catchAt(s, 12.0), 0.18, 1e-9)
end)

test("catchAt clamps to 0..1 and drains", function()
  local s = hud.new()
  hud.catchSample(s, 0, 0.98); hud.catchSample(s, 0.25, 0.99)
  assertEq(hud.catchAt(s, 0.5), 1)
  local d = hud.new()
  hud.catchSample(d, 0, 0.05); hud.catchSample(d, 0.25, 0.01)
  assertEq(hud.catchAt(d, 0.5), 0)
end)

test("single sample returns its value", function()
  local s = hud.new(); hud.catchSample(s, 3, 0.42)
  assertNear(hud.catchAt(s, 9), 0.42, 1e-9)
end)

test("payload hides status before the chase and shows catch per role", function()
  local s = hud.new(); hud.catchSample(s, 1, 0.996)
  local p = hud.payload(s, 1, { active = true, role = "runner", resetAllowed = false, resetHint = "Stop to reset" })
  assertEq(p.visible, true); assertEq(p.mode, "round"); assertEq(p.status, nil)
  assertEq(p.catch.visible, true); assertEq(p.catch.percent, 99)
  assertEq(p.catch.label, "BEING CAUGHT"); assertEq(p.catch.tone, "runner")
  local c = hud.payload(s, 1, { active = true, role = "cop", chaseStart = 0 })
  assertEq(c.catch.label, "HOLDING RUNNER"); assertEq(c.catch.tone, "cop")
end)

test("payload status line", function()
  local s = hud.new()
  local p = hud.payload(s, 200, { active = true, role = "cop", chaseStart = 7.3, resetAllowed = true, infoText = "Runner 640 m NE" })
  assertEq(p.status.role, "cop"); assertEq(p.status.time, "3:12")
  assertEq(p.status.reset, "Reset OK"); assertEq(p.status.info, "Runner 640 m NE")
  assertEq(p.status.releaseIn, nil)
  assertEq(p.catch.visible, false)
  local q = hud.payload(s, 200, { active = true, role = "runner", chaseStart = 0, penalty = true, resetHint = "x" })
  assertEq(q.status.role, "runner"); assertEq(q.status.reset, "Penalty")
  local h = hud.payload(s, 200, { active = true, role = "runner", chaseStart = 0, resetHint = "Stay still 4s to reset" })
  assertEq(h.status.reset, "Stay still 4s to reset")
end)

test("percent stays at 99 until the server says 1", function()
  local s = hud.new()
  hud.catchSample(s, 0, 0.98); hud.catchSample(s, 0.25, 0.99)
  local p = hud.payload(s, 0.5, { active = true, role = "runner" })
  assertEq(p.catch.percent, 99)
  hud.catchSample(s, 0.5, 1)
  assertEq(hud.payload(s, 0.6, { active = true, role = "runner" }).catch.percent, 100)
end)

test("jittered samples cannot push the bar more than one server step ahead", function()
  local s = hud.new()
  hud.catchSample(s, 10.00, 0.40); hud.catchSample(s, 10.25, 0.44)
  hud.catchSample(s, 10.80, 0.47); hud.catchSample(s, 10.81, 0.51)
  assertNear(hud.catchAt(s, 11.0), 0.55, 1e-9)
end)

test("a countdown counts down in the centre and disappears at zero", function()
  local s = hud.new()
  local p = hud.payload(s, 10.2, { active = true, role = "cop", timer = { label = "Cops released in", endsAt = 17 } })
  assertEq(p.center.kind, "countdown"); assertEq(p.center.label, "COPS RELEASED IN"); assertEq(p.center.number, 7)
  assertEq(hud.payload(s, 17.0, { active = true, role = "cop", timer = { label = "Cops released in", endsAt = 17 } }).center, nil)
end)

test("each countdown has its tone", function()
  local s = hud.new()
  local function at(label) return hud.payload(s, 0, { active = true, role = "cop", timer = { label = label, endsAt = 3 } }).center end
  assertEq(at("Runner starts in").label, "RUNNER STARTS IN"); assertEq(at("Runner starts in").tone, "runner")
  assertEq(at("Cops released in").tone, "cop")
  assertEq(at("Crash penalty").label, "CRASH PENALTY"); assertEq(at("Crash penalty").tone, "warn")
end)

test("flash beats the timer and expires", function()
  local s = hud.new()
  local info = { active = true, role = "runner", flash = { text = "GO! RUN!", untilT = 5 }, timer = { label = "Cops released in", endsAt = 11 } }
  assertEq(hud.payload(s, 4, info).center.kind, "flash")
  assertEq(hud.payload(s, 4, info).center.text, "GO! RUN!")
  assertEq(hud.payload(s, 4, info).center.number, nil)
  assertEq(hud.payload(s, 5, info).center.label, "COPS RELEASED IN")
end)

test("prep shows the role in the centre and the waiting line with your colour at the bottom", function()
  local s = hud.new()
  local p = hud.payload(s, 1, { active = true, role = "cop", color = "#ff8800", rules = RULES,
    prep = { role = "cop", car = "Gavril D-Series", waiting = "go", runner = "Bob" } })
  assertEq(p.center.kind, "role"); assertEq(p.center.role, "cop"); assertEq(p.center.car, "Gavril D-Series")
  assertEq(p.center.title, "YOU'RE A COP")
  assertEq(p.center.rule, "Bob is the runner. You're released 7 s after the runner. Catch them by holding them under 3 km/h within 10 m for 7 s.")
  assertEq(p.prep.waiting, "Waiting for the host to press GO"); assertEq(p.prep.color, "#ff8800")
  assertEq(p.lobby, nil); assertEq(p.status, nil)
  local r = hud.payload(s, 1, { active = true, role = "runner", rules = RULES, prep = { role = "runner", car = "x", waiting = "go" } })
  assertEq(r.center.role, "runner"); assertEq(r.center.title, "YOU'RE THE RUNNER")
  assertEq(r.center.rule, "Survive as long as you can. Cops catch you by holding you under 3 km/h within 10 m for 7 s.")
  assertEq(r.prep.color, nil)
end)

test("rule lines use the live settings", function()
  assertEq(hud.ruleLine("runner", nil, RULES), "Survive as long as you can. Cops catch you by holding you under 3 km/h within 10 m for 7 s.")
  assertEq(hud.ruleLine("cop", "Bob", RULES), "Bob is the runner. You're released 7 s after the runner. Catch them by holding them under 3 km/h within 10 m for 7 s.")
  local custom = rules({ catchMaxSpeedKmh = 5, catchRadiusMeters = 12.5, catchHoldSeconds = 4, headStartSeconds = 15 })
  assertEq(hud.ruleLine("cop", "Ann", custom), "Ann is the runner. You're released 15 s after the runner. Catch them by holding them under 5 km/h within 12.5 m for 4 s.")
  assertEq(hud.ruleLine("runner", nil, nil), "Survive as long as you can. Cops catch you by holding you under 3 km/h within 10 m for 7 s.")
  assertEq(hud.ruleLine("cop", nil, RULES), "You're released 7 s after the runner. Catch them by holding them under 3 km/h within 10 m for 7 s.")
end)

test("a cop's rule line names the runner only once known", function()
  local p = hud.payload(hud.new(), 1, { active = true, role = "cop", rules = RULES, prep = { role = "cop", car = "x", waiting = "go" } })
  assertEq(p.center.rule:sub(1, 15), "You're released")
end)

test("reset flash", function()
  local s = hud.new()
  local q = hud.payload(s, 1, { active = true, role = "cop", chaseStart = 0, resetFlashUntil = 1.5 })
  assertEq(q.status.resetFlash, true)
  assertEq(hud.payload(s, 2, { active = true, role = "cop", chaseStart = 0, resetFlashUntil = 1.5 }).status.resetFlash, false)
end)

test("notices: newest two unexpired, newest first, with tone", function()
  local s = hud.new()
  local p = hud.payload(s, 10, { active = true, role = "cop", events = {
    { text = "a", untilT = 9 }, { text = "b", untilT = 12 }, { text = "c", untilT = 13, tone = "warn" }, { text = "d", untilT = 14 } } })
  assertEq(#p.notices, 2); assertEq(p.notices[1].text, "d"); assertEq(p.notices[1].tone, "info")
  assertEq(p.notices[2].text, "c"); assertEq(p.notices[2].tone, "warn")
  assertEq(p.events, nil)
  local l = hud.payload(s, 10, { active = false, events = { { text = "x", untilT = 11, tone = "warn" } } })
  assertEq(l.notices[1].text, "x")
end)

test("result card replaces the round for its time and counts down to the next round", function()
  local s = hud.new()
  local info = { active = false, events = { { text = "x", untilT = 99 } }, flash = { text = "GO!", untilT = 99 },
    result = { title = "RUNNER CAUGHT", runner = "Reinder", time = "4:12", catchers = "Bob", untilT = 20, nextAt = 25.2 } }
  local p = hud.payload(s, 12, info)
  assertEq(p.visible, true); assertEq(p.mode, "result")
  assertEq(p.result.title, "RUNNER CAUGHT"); assertEq(p.result.runner, "Reinder"); assertEq(p.result.time, "4:12")
  assertEq(p.result.catchers, "Bob"); assertEq(p.result.nextIn, 14)
  assertEq(p.center, nil); assertEq(p.lobby, nil); assertEq(p.status, nil); assertEq(#p.result.rows, 0)
  assertEq(p.result.top, nil)
  local after = hud.payload(s, 20, info)
  assertEq(after.mode, "lobby"); assertEq(after.result, nil); assertEq(after.visible, true)
end)

test("result without runner or next round", function()
  local s = hud.new()
  local p = hud.payload(s, 1, { active = false, result = { title = "ROUND CANCELLED", untilT = 5 } })
  assertEq(p.result.title, "ROUND CANCELLED"); assertEq(p.result.runner, nil); assertEq(p.result.nextIn, nil)
end)

test("result rows pass through with your own row marked", function()
  local p = hud.payload(hud.new(), 1, { active = false, result = { title = "ESCAPED", untilT = 5,
    rows = { { rank = 1, player = "Bob", time = "8:41", me = true }, { rank = 2, player = "Ann", time = "1:15" } } } })
  assertEq(#p.result.rows, 2)
  assertEq(p.result.rows[1].rank, 1); assertEq(p.result.rows[1].player, "Bob"); assertEq(p.result.rows[1].time, "8:41")
  assertEq(p.result.rows[1].me, true); assertEq(p.result.rows[2].me, false)
end)

test("the queued change shows next to the prep line", function()
  local s = hud.new()
  local p = hud.payload(s, 0, { active = true, role = "cop", prep = { role = "cop", car = "x", waiting = "change", runner = "Bob" },
    change = { runner = "Bob", changes = { { label = "Engine", from = "4.5L V8", to = "6.0L V8" }, { label = "Intake", from = "Stock", to = "Big" } } } })
  assertEq(p.change.title, "BOB'S CHANGE (2)"); assertEq(#p.change.lines, 2); assertEq(p.change.lines[1].to, "6.0L V8")
  assertEq(p.prep.waiting, "Waiting for Bob's change")
  local none = hud.payload(s, 0, { active = true, change = { runner = "Bob", changes = {} } })
  assertEq(none.change.title, "BOB'S CHANGE: none yet")
  local many = {}
  for i = 1, 6 do many[i] = { label = "P" .. i, from = "a", to = "b" } end
  local big = hud.payload(s, 0, { active = true, change = { runner = "Bob", changes = many } })
  assertEq(#big.change.lines, 4); assertEq(big.change.more, 2)
end)

test("applying takes the centre", function()
  local p = hud.payload(hud.new(), 0, { active = true, applying = true, prep = { role = "cop", car = "x", waiting = "go" } })
  assertEq(p.center.kind, "applying"); assertEq(p.center.text, "APPLYING CHANGES")
  assertEq(p.prep.waiting, "Waiting for the host to press GO")
end)

test("the status line carries a sight tag separately from the distance", function()
  local p = hud.payload(hud.new(), 10, { active = true, role = "runner", chaseStart = 0, infoTag = "SPOTTED", infoText = "Nearest cop 120 m" })
  assertEq(p.status.tag, "SPOTTED"); assertEq(p.status.info, "Nearest cop 120 m")
end)

test("change lines keep how many parts came with them", function()
  local p = hud.payload(hud.new(), 0, { active = true, change = { runner = "Gizmo", changes = { { label = "Engine", from = "2.0L I4", to = "3.0L I6", extra = 12 } } } })
  assertEq(p.change.title, "GIZMO'S CHANGE (1)"); assertEq(p.change.lines[1].extra, 12)
end)

test("the runner's own change block offers Apply", function()
  local p = hud.payload(hud.new(), 0, { active = true, change = { runner = "Bob", changes = {}, canApply = true } })
  assertEq(p.change.canApply, true)
  local q = hud.payload(hud.new(), 0, { active = true, change = { runner = "Bob", changes = {} } })
  assertEq(q.change.canApply, nil)
end)

test("the prep line says what everyone is waiting for", function()
  local function waiting(prep) return hud.payload(hud.new(), 0, { active = true, prep = prep }).prep.waiting end
  assertEq(waiting({ role = "runner", car = "x", waiting = "change" }), "Make your change, then press Apply")
  assertEq(waiting({ role = "cop", car = "x", waiting = "change", runner = "Bob" }), "Waiting for Bob's change")
  assertEq(waiting({ role = "cop", car = "x", waiting = "change" }), "Waiting for the runner's change")
  assertEq(waiting({ role = "runner", car = "x", waiting = "go" }), "Waiting for the host to press GO")
  assertEq(waiting({ role = "cop", car = "x" }), "Waiting for the host to press GO")
end)

test("lobby payload when idle", function()
  local p = hud.payload(hud.new(), 0, { active = false, lobby = { online = 3, active = false }, color = "#00ff00",
    warnings = { "Bind a reset or recover button to reset during rounds" }, apps = { panel = true, board = false } })
  assertEq(p.visible, true); assertEq(p.mode, "lobby"); assertEq(p.driving, false)
  assertEq(p.lobby.online, 3); assertEq(p.lobby.status, "Waiting for the host to start a round")
  assertEq(p.lobby.color, "#00ff00")
  assertEq(#p.lobby.warnings, 1); assertEq(p.lobby.warnings[1], "Bind a reset or recover button to reset during rounds")
  assertEq(p.lobby.apps.panel, true); assertEq(p.lobby.apps.board, false)
  assertEq(p.center, nil); assertEq(p.status, nil); assertEq(p.prep, nil); assertEq(p.result, nil)
  assertEq(p.catch.visible, false)
  local bare = hud.payload(hud.new(), 0, {})
  assertEq(bare.lobby.status, "Waiting for the host to start a round"); assertEq(#bare.lobby.warnings, 0)
  assertEq(bare.lobby.apps.panel, false); assertEq(bare.lobby.apps.board, false); assertEq(bare.lobby.color, nil)
end)

test("a round you're not in shows as running in the lobby", function()
  local p = hud.payload(hud.new(), 0, { active = false, lobby = { online = 4, active = true } })
  assertEq(p.mode, "lobby"); assertEq(p.lobby.status, "A round is running")
end)

test("practice by someone else keeps the lobby", function()
  local p = hud.payload(hud.new(), 0, { active = false, lobby = { online = 3, practice = "Bob", active = false } })
  assertEq(p.mode, "lobby"); assertEq(p.lobby.status, "Practice round: Bob"); assertEq(p.center, nil)
  local mine = hud.payload(hud.new(), 0, { active = true, role = "runner", lobby = { online = 3, practice = "Reinder", active = false },
    prep = { role = "runner", car = "x", waiting = "go" } })
  assertEq(mine.mode, "round"); assertEq(mine.lobby, nil)
end)

test("time limit shows only when set", function()
  local s = hud.new()
  local p = hud.payload(s, 200, { active = true, role = "cop", chaseStart = 8, rules = rules({ roundTimeLimitSeconds = 600 }) })
  assertEq(p.status.time, "3:12"); assertEq(p.status.limit, "10:00")
  assertEq(hud.payload(s, 200, { active = true, role = "cop", chaseStart = 8, rules = rules({ roundTimeLimitSeconds = 0 }) }).status.limit, nil)
  assertEq(hud.payload(s, 200, { active = true, role = "cop", chaseStart = 8 }).status.limit, nil)
end)

test("help rules read sensibly at 0", function()
  local off = rules({ roundTimeLimitSeconds = 0, sightMaxMeters = 0 })
  local p = hud.payload(hud.new(), 0, { active = false, rules = off, helpOpen = true })
  assertEq(p.help.open, true)
  for k, v in pairs(off) do assertEq(p.help.rules[k], v, k) end
  assertEq(p.help.rules.noLimit, true); assertEq(p.help.rules.sightOff, true)
  assertEq(off.noLimit, nil); assertEq(off.sightOff, nil)
  local on = hud.payload(hud.new(), 0, { active = false, rules = rules({ roundTimeLimitSeconds = 600 }), helpOpen = true })
  assertEq(on.help.rules.noLimit, false); assertEq(on.help.rules.sightOff, false)
  local closed = hud.payload(hud.new(), 0, { active = false, rules = off, helpOpen = false })
  assertEq(closed.help.open, false); assertEq(closed.help.rules, nil)
end)

test("the runner's chase line counts down to the cops' release during the head start", function()
  local s = hud.new()
  local p = hud.payload(s, 10.2, { active = true, role = "runner", releaseAt = 17, resetHint = "Stay still 4s to reset" })
  assertEq(p.status.role, "runner"); assertEq(p.status.time, "0:00"); assertEq(p.status.releaseIn, 7)
  assertEq(p.status.reset, "Stay still 4s to reset")
  local cop = hud.payload(s, 10.2, { active = true, role = "cop", releaseAt = 17, timer = { label = "Cops released in", endsAt = 17 } })
  assertEq(cop.status, nil)
  local chase = hud.payload(s, 20, { active = true, role = "runner", releaseAt = 17, chaseStart = 17 })
  assertEq(chase.status.time, "0:03"); assertEq(chase.status.releaseIn, nil)
end)

test("driving is true from the countdown to the end of the round", function()
  local s = hud.new()
  local prep = { role = "runner", car = "x", waiting = "go" }
  assertEq(hud.payload(s, 0, { active = false }).driving, false)
  assertEq(hud.payload(s, 0, { active = true, role = "runner", prep = prep }).driving, false)
  assertEq(hud.payload(s, 0, { active = true, role = "runner", prep = prep, applying = true }).driving, false)
  assertEq(hud.payload(s, 0, { active = true, role = "runner", timer = { label = "Runner starts in", endsAt = 3 } }).driving, true)
  assertEq(hud.payload(s, 4, { active = true, role = "runner", releaseAt = 10 }).driving, true)
  assertEq(hud.payload(s, 20, { active = true, role = "runner", chaseStart = 10 }).driving, true)
  assertEq(hud.payload(s, 21, { active = false, result = { title = "ESCAPED", untilT = 30 } }).driving, false)
end)
