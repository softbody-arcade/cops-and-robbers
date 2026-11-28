local roster = require("arcade.roster")
local panel = require("arcade.panel")
local traffic = require("arcade.traffic")
local settings = require("arcade.settings")
local autoRounds = require("arcade.autoRounds")
dofile("tests/server_boot.lua")

local stub = {}
function stub.manifest()
  return { minPlayers = 2, commands = { exact = { "race" }, prefixes = { "grid+ " } } }
end

function stub.settingsDeclaration()
  return { DEFAULTS = { laps = 3 } }
end

local function fixture(service)
  local cycle = require("arcade.cycle")
  local r = roster.new()
  function r:players() return { [7] = "Ann" } end
  local f = { snapshots = 0, starts = 0, calls = {}, prepared = { participants = { 7, 9 } } }
  local messages = { send = function(pid, event, data)
    if event == "cnr_roundEnd" then f.result, f.audience = data, pid end
  end, log = error }
  local function noop() end
  local s = service or {
    snapshot = function() return { autoNextDelaySeconds = 5 } end,
    get = function(_, key) return key == "autoNextRound" end,
  }
  local snapshot = s.snapshot
  function s:snapshot() f.snapshots = f.snapshots + 1; return snapshot(self) end
  local services = {
    settings = s, roster = r, messages = messages, clock = { now = function() return 20 end },
    panel = panel.new(messages, r), autoRounds = autoRounds.new(), traffic = traffic.new(r, messages),
    cars = { clearRound = noop, clearPublished = noop, setPublishing = function(_, on) f.publishing = on end },
    spectators = { releaseAll = noop },
  }
  local y = cycle.new(services, stub.manifest())
  f.cycle, f.ctx = y, y:context()
  local function called(hook) f.calls[#f.calls + 1] = hook; return {} end
  local game = {
    canStart = function(_, request) f.request = request; return f.prepared, "No runner" end,
    start = function(_, prepared, values, now)
      f.starts = f.starts + 1
      f.preparedAtStart, f.snapshot, f.now = prepared, values, now
      f.stateAtStart = y:state()
      f.publishingAtStart = f.publishing
    end,
    panelState = function() return called("panel") end,
    lobbyFields = function() return called("lobby") end,
    tick = function() called("tick") end,
    roundFinished = function() f.finishedIn = y:state(); f.publishingAtFinish = f.publishing end,
  }
  y:attach(game)
  return f
end

test("canStart refuses before a snapshot, state change or start", function()
  local f = fixture()
  f.prepared = nil
  local ok, reason = f.ctx.round:start({ issuer = 7 })
  assertEq(ok, nil)
  assertEq(reason, "No runner")
  assertEq(f.cycle:state(), "lobby")
  assertEq(f.snapshots, 0)
  assertEq(f.starts, 0)
end)

test("a non-solo start needs the manifest's minimum before taking a snapshot", function()
  local f = fixture()
  f.prepared.participants = { 7 }
  local ok, reason = f.ctx.round:start({ issuer = 7 })
  assertEq(ok, nil)
  assertEq(reason, "Not enough players")
  assertEq(f.snapshots, 0)
  assertEq(f.starts, 0)
  assertEq(f.cycle:state(), "lobby")
end)

test("solo starts with no participants and receives the prepared data and time", function()
  local f = fixture()
  f.prepared = { solo = true, participants = {} }
  assertEq(f.ctx.round:start({ issuer = 7 }), true)
  assertEq(f.stateAtStart, "round")
  assertEq(f.publishingAtStart, true)
  assertEq(f.preparedAtStart, f.prepared)
  assertEq(f.now, 20)
end)

test("the first snapshot includes the game's own defaults and survives a settings change", function()
  local env = serverBoot.boot()
  local s = settings.new(env.dir .. "race.json", settings.combine(settings.GLOBAL, stub.settingsDeclaration()))
  s:load()
  local f = fixture(s)
  assertEq(f.ctx.settings:get("laps"), 3)
  assert(f.ctx.round:start({ issuer = 7 }))
  assert(s:set("laps", "8"))
  assertEq(f.ctx.settings:get("laps"), 8)
  assertEq(f.snapshot.laps, 3)
  env.cleanup()
end)

test("finish enters results, stops publishing and permits another start", function()
  local f = fixture()
  assert(f.ctx.round:start({ issuer = 7 }))
  f.ctx.round:finish({}, -1, false)
  assertEq(f.finishedIn, "results")
  assertEq(f.publishingAtFinish, false)
  assert(f.ctx.round:start({ issuer = 7 }))
  assertEq(f.cycle:state(), "round")
  assertEq(f.starts, 2)
end)

test("finish adds the automatic delay only to the delivered payload", function()
  local f = fixture()
  assert(f.ctx.round:start({ issuer = 7 }))
  local result = { winner = 7 }
  f.ctx.round:finish(result, 7, true)
  assertEq(f.result.winner, 7)
  assertEq(f.result.autoNextSeconds, 5)
  assertEq(f.audience, 7)
  assertEq(result.autoNextSeconds, nil)
end)

test("startNext asks the game to prepare next with an online issuer", function()
  local f = fixture()
  f.cycle:startNext()
  assertEq(f.request.command, "next")
  assertEq(f.request.issuer, 7)
end)

test("tick pushes the panel lazily and the lobby before a due start and round tick", function()
  local f = fixture()
  f.cycle:tick()
  assertEq(table.concat(f.calls, ","), "lobby")
  f.ctx.panel:push(7)
  f.calls = {}
  f.ctx.autoRounds:schedule(20)
  f.cycle:tick()
  assertEq(table.concat(f.calls, ","), "panel,lobby,tick")
  assertEq(f.request.command, "next")
end)

test("each cycle uses literal game prefixes, exact commands and the common commands", function()
  local f = fixture()
  assertEq(f.cycle:allowCommand(" auto on "), "auto on")
  assertEq(f.cycle:allowCommand(" RACE "), "race")
  assertEq(f.cycle:allowCommand("GRID+ Ann"), "grid+ Ann")
  assertEq(f.cycle:allowCommand("grid+  Ann"), nil)
  assertEq(f.cycle:allowCommand("go"), nil)
end)

test("a new traffic service exposes the current server capacity", function()
  local original = MP
  MP = { Settings = { MaxCars = 12 }, Get = function(key) return tostring(key) end }
  local t = traffic.new(roster.new(), {})
  local capacity = t:maxCars()
  MP = original
  assertEq(capacity, 12)
end)

test("clearing round traffic removes open allowances and reported cars", function()
  local original = MP
  MP = { GetPositionRaw = function() return { pos = {1, 2, 3}, vel = {0, 0, 0} } end }
  local t = traffic.new(roster.new(), { send = function() end })
  t:open(7, 2)
  t:report(7, { 3 }, 0, function() return false end)
  assertEq(#t:cars(), 1)
  t:clearRound()
  local count = #t:cars()
  MP = original
  assertEq(count, 0)
  assertEq(t:openCount(7), nil)
end)

test("a cancelled countdown cannot supply the issuer for a later next start", function()
  local f = fixture()
  function f.ctx.roster:players() return { [7] = "Ann", [9] = "Bob" } end
  assert(f.ctx.round:start({ issuer = 7 }))
  f.ctx.round:finish({}, -1, true)
  f.ctx.autoRounds:cancel()
  assert(f.ctx.round:start({ issuer = 9 }))
  f.ctx.round:finish({}, -1, false)
  f.cycle:startNext()
  assertEq(f.request.issuer, 9)
end)
