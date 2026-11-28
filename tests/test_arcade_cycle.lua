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

local savedMP, savedUtil = MP, Util
local vehiclePacket = 'USER:Ann:7-4:{"jbm":"coupe","vcf":{"parts":{"engine":"stock"}}}'

local function vehicleFixture(verdict)
  local f = { time = 20, logs = {}, replies = {}, published = {}, events = {}, owned = {}, decodes = 0 }
  MP = {
    GetPlayerVehicles = function() return f.owned end,
    GetPlayerName = function() return "Ann" end,
  }
  Util = { JsonDecode = function(data)
    f.decodes = f.decodes + 1
    return decodeJson(data)
  end }
  local messages = {
    log = function(line) f.logs[#f.logs + 1] = line end,
    refuse = function(pid, reason) f.replies[#f.replies + 1] = { pid, reason } end,
    send = function(pid, event, data)
      if event == "cnr_roundCars" then f.published[#f.published + 1] = table.concat(data.keys, ",") end
    end,
  }
  local r = roster.new()
  f.traffic = traffic.new(r, messages)
  f.cars = require("arcade.cars").new(r, messages, f.traffic)
  f.cars:setPublishing(true)
  f.cycle = require("arcade.cycle").new({
    roster = r, messages = messages, panel = panel.new(messages, r), cars = f.cars,
    traffic = f.traffic, clock = { now = function() return f.time end },
  }, stub.manifest())
  f.cycle:attach({
    checkVehicle = function(_, kind, pid, vid, decoded, facts)
      f.checked = { kind = kind, pid = pid, vid = vid, decoded = decoded, facts = facts }
      return verdict
    end,
    onVehicle = function(_, kind, pid, vid, decoded, facts, now)
      f.events[#f.events + 1] = { kind = kind, pid = pid, vid = vid, decoded = decoded, facts = facts, now = now }
    end,
  })
  return f
end

test("a refused spawn replies each time but logs only once per ten seconds", function()
  local f = vehicleFixture({ allow = false, reason = "Grid is closed", notify = false })
  for _, at in ipairs({ 20, 29.9, 30 }) do
    f.time = at
    assertEq(f.cycle:onVehicleSpawn(7, 4, vehiclePacket), 1)
    assertEq(#f.logs, at == 30 and 2 or 1)
  end
  assertEq(f.logs[1], "Ann spawned coupe (vid 4): refused")
  assertEq(#f.replies, 3)
  assertEq(f.replies[2][1], 7)
  assertEq(f.replies[2][2], "Grid is closed")
  assertEq(#f.events, 0)
end)

test("a round car without a permit or replacement right is refused", function()
  local f = vehicleFixture({ allow = true, roundCar = true, notify = true })
  assertEq(f.cycle:onVehicleSpawn(7, 4, vehiclePacket), 1)
  assertEq(f.replies[1][2], "Only the round car is allowed")
  assertEq(f.logs[1], "Ann spawned coupe (vid 4): refused")
  assertEq(f.cars:activeVid(7), nil)
  assertEq(#f.events, 0)
end)

test("a first round car uses a permit and waits for confirmation to publish", function()
  local f = vehicleFixture({ allow = true, roundCar = true, notify = true })
  f.owned[4] = "spare"
  f.cars:setup(7, {})
  assertEq(f.cycle:onVehicleSpawn(7, 4, vehiclePacket), 0)
  assertEq(f.checked.facts.permitted, true)
  assertEq(f.checked.facts.placementPending, true)
  assertEq(f.checked.facts.confirmed, false)
  assertEq(f.checked.facts.preRound, true)
  assertEq(f.cars:isPreRound(7, 4), false)
  assertEq(f.cars:permitted(7), false)
  assertEq(f.cars:activeVid(7), 4)
  assertEq(f.events[1].kind, "spawn")
  assertEq(#f.published, 0)
  f.cars:confirm(7, 4)
  f.cars:publish()
  assertEq(f.published[1], "7-4")
end)

test("deleting a confirmed car allows one immediate replacement above the traffic cap", function()
  local f = vehicleFixture({ allow = true, roundCar = true, notify = true })
  f.cars:setup(7, {})
  f.cars:confirm(7, 0)
  f.cars:publish()
  f.traffic:open(7, 1)
  f.owned = { [1] = "traffic", [2] = "spare" }
  assertEq(f.cycle:onVehicleDeleted(7, 0), nil)
  assertEq(f.events[1].kind, "replaced")
  assertEq(f.events[2].kind, "delete")
  assertEq(f.published[2], "")
  assertEq(f.cycle:onVehicleSpawn(7, 4, vehiclePacket), 0)
  assertEq(f.checked.facts.replacementAllowed, true)
  assertEq(f.checked.facts.trafficOpen, 1)
  assertEq(f.events[3].kind, "replaced")
  assertEq(f.events[3].vid, 4)
  assertEq(f.events[3].decoded, nil)
  assertEq(f.events[4].kind, "spawn")
  assertEq(f.published[3], "7-4")
  assertEq(f.cycle:onVehicleSpawn(7, 5, vehiclePacket), 1)
  assertEq(f.cycle:onVehicleReset(7, 4), nil)
  assertEq(f.events[5].kind, "reset")
  assertEq(f.events[5].facts.activeVid, 4)
end)

test("only a notifying edit delivers its once-decoded packet to the game", function()
  local verdict = { allow = true, notify = false }
  local f = vehicleFixture(verdict)
  assertEq(f.cycle:onVehicleEdited(7, 4, vehiclePacket), 0)
  assertEq(#f.events, 0)
  verdict.notify = true
  assertEq(f.cycle:onVehicleEdited(7, 4, vehiclePacket), 0)
  assertEq(f.decodes, 2)
  assertEq(f.checked.kind, "edit")
  assertEq(f.checked.decoded.vcf.parts.engine, "stock")
  local edit = f.events[1]
  assertEq(edit.kind, "edit")
  assertEq(edit.pid, 7)
  assertEq(edit.vid, 4)
  assertEq(edit.decoded, f.checked.decoded)
  assertEq(edit.facts, f.checked.facts)
  assertEq(edit.now, 20)
end)

MP, Util = savedMP, savedUtil
