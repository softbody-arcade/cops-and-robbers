dofile("tests/server_boot.lua")

local function buildRace(env, path)
  serverBoot.fakes(env, {})
  local messages = require("arcade.messages").new({ prefix = "[Race] " })
  local roster = require("arcade.roster").new()
  local store = require("arcade.store")
  local timer = MP.CreateTimer()
  local clock = { now = function() return timer:GetCurrent() end, timer = MP.CreateTimer, unixTime = os.time }
  local race = require("tests.fake_game")
  local manifest = race.manifest(CNR_VERSION)
  local settings = require("arcade.settings")
  local config = settings.new(path, settings.combine(settings.GLOBAL, race.settingsDeclaration()), messages.log)
  local traffic = require("arcade.traffic").new(roster, messages)
  local cars = require("arcade.cars").new(roster, messages, traffic)
  local spectators = require("arcade.spectators").new(roster, messages)
  local colors = require("arcade.playerColors").new(path .. ".colors", roster, messages)
  local panel = require("arcade.panel").new(messages, roster)
  local auto = require("arcade.autoRounds").new()
  local cycle = require("arcade.cycle").new({
    messages = messages, roster = roster, store = store, clock = clock, settings = config,
    traffic = traffic, cars = cars, spectators = spectators, playerColors = colors, panel = panel, autoRounds = auto,
  }, manifest)
  config:load()
  local ctx = cycle:context()
  local game = race.new(ctx)
  cycle:attach(game)
  return cycle, ctx, game
end

local function raceTest(name, check)
  test(name, function()
    local mp, fs, util, realPrint = MP, FS, Util, print
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    assert(file:write("{}"))
    assert(file:close())
    local env = { names = { "Alex", "Blair" } }
    local ok, err = pcall(function()
      local cycle, ctx, game = buildRace(env, path)
      print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        env.logs[#env.logs + 1] = table.concat(parts, " ")
      end
      check(env, cycle, ctx, game)
    end)
    MP, FS, Util, print = mp, fs, util, realPrint
    os.remove(path)
    assert(ok, err)
  end)
end

local function command(cycle, text)
  cycle:onPanel(1, serverBoot.encode({ action = "command", text = text }))
end

local function lap(cycle, pid)
  cycle:onClientEvent("race_lap", pid, "{}")
end

local function finishRace(cycle)
  for _ = 1, 3 do lap(cycle, 2) end
end

raceTest("a race needs two players", function(env, cycle, ctx, game)
  env.names[2] = nil
  command(cycle, "auto on")
  command(cycle, "race")
  assertEq(cycle:state(), "lobby")
  assertEq(game.snapshot, nil)
  local reply = assert(env.lastSent("cnr_panelReply"))
  assertEq(reply.pid, 1)
  assertEq(decodeJson(reply.data).text, "Not enough players")
  assertEq(decodeJson(reply.data).tone, "warn")
  assertEq(env.lastSent("cnr_roundSetup"), nil)

  env.names[2] = "Blair"
  command(cycle, "race")
  cycle:tick()
  finishRace(cycle)
  assertEq(cycle:state(), "results")
  env.names[2] = nil
  cycle:onPlayerDisconnect(2)
  env.sent = {}
  env.clock = assert(ctx.autoRounds:pending())
  cycle:tick()
  assertEq(cycle:state(), "results")
  assertEq(ctx.autoRounds:pending(), nil)
  assertEq(env.lastSent("cnr_roundSetup"), nil)
  local notice = assert(env.lastSent("cnr_notice"), "automatic refusal did not reach the issuer as a notice")
  assertEq(notice.pid, 1)
  assertEq(decodeJson(notice.data).msg, "Not enough players")
  assertEq(decodeJson(notice.data).tone, "warn")
end)

raceTest("laps comes from the game's declaration", function(env, cycle, ctx, game)
  assertEq(ctx.settings:get("laps"), 3)
  command(cycle, "race")
  assertEq(game.snapshot.laps, 3)
end)

raceTest("a race starts, ticks, finishes into results and schedules the next with auto on", function(env, cycle, ctx, game)
  command(cycle, "auto on")
  command(cycle, "race")
  assertEq(cycle:state(), "round")
  assertEq(game.phase, "grid")
  assertEq(ctx.cars:permitted(1), true)
  assertEq(ctx.cars:permitted(2), true)
  cycle:tick()
  assertEq(game.phase, "race")
  finishRace(cycle)
  assertEq(cycle:state(), "results")
  local ending = decodeJson(env.lastSent("cnr_roundEnd").data)
  assertEq(ending.winner, 2)
  assertEq(ending.autoNextSeconds, ctx.settings:get("autoNextDelaySeconds"))
  env.clock = ending.autoNextSeconds - 0.25
  cycle:tick()
  assertEq(cycle:state(), "results")
  env.clock = ending.autoNextSeconds
  cycle:tick()
  assertEq(cycle:state(), "round")
  assertEq(game.phase, "race")
  assertEq(ctx.autoRounds:pending(), nil)
end)

raceTest("a racer joining mid-race and leaving keeps the cleanup order", function(env, cycle, ctx)
  command(cycle, "race")
  cycle:tick()
  env.names[3] = "Cam"
  cycle:onPlayerJoin(3)
  assertEq(env.lastSent("cnr_roundSetup").pid, 3)
  assertEq(cycle:onVehicleSpawn(3, 7, '{"jbm":"coupe"}'), 0)
  assertEq(decodeJson(env.lastSent("cnr_roundCars").data).keys[1], "3-7")
  ctx.roster:setSitOut(3, true)
  env.names[3] = nil
  env.sent = {}
  cycle:onPlayerDisconnect(3)
  assertEq(env.sent[1].ev, "race_left")
  local left = decodeJson(env.sent[1].data)
  assertEq(left.racer, 3)
  assertEq(left.sittingOut, false)
  assertEq(left.vid, 7)
  assertEq(ctx.cars:confirmedVid(3), nil)
  assertEq(env.sent[2].ev, "cnr_roundCars")
  assertEq(#decodeJson(env.sent[2].data).keys, 0)
end)

raceTest("a car the race doesn't allow is refused with 1", function(env, cycle, ctx)
  command(cycle, "race")
  assertEq(cycle:onVehicleSpawn(2, 7, '{"jbm":"van"}'), 1)
  local logged = false
  for _, line in ipairs(env.logs) do
    if line:find("Blair spawned van (vid 7): refused", 1, true) then logged = true end
  end
  assertEq(logged, true)
  local notice = env.lastSent("cnr_notice")
  assertEq(notice.pid, 2)
  assertEq(decodeJson(notice.data).msg, "Race a coupe")
  assertEq(ctx.cars:permitted(2), true)
  assertEq(ctx.cars:activeVid(2), nil)
end)

raceTest("a rebuild targets only the chosen racer", function(env, cycle, ctx)
  command(cycle, "race")
  cycle:tick()
  env.sent = {}
  lap(cycle, 2)
  local rebuilds = 0
  for _, message in ipairs(env.sent) do
    if message.ev == "cnr_rebuild" then
      rebuilds = rebuilds + 1
      assertEq(message.pid, 2)
    end
  end
  assertEq(rebuilds, 1)
  assertEq(ctx.cars:pendingRebuild(2), true)
  assertEq(ctx.cars:pendingRebuild(1), false)
end)

raceTest("its client event reaches clientEvent", function(env, cycle)
  command(cycle, "race")
  cycle:tick()
  cycle:onClientEvent("other_lap", 1, "{}")
  lap(cycle, 1)
  lap(cycle, 1)
  assertEq(cycle:state(), "round")
  lap(cycle, 1)
  assertEq(decodeJson(env.lastSent("cnr_roundEnd").data).winner, 1)
end)

raceTest("its prefix-free command reaches panelAction, and an unknown one doesn't", function(env, cycle)
  cycle:onPanel(1, '{"action":"open"}')
  command(cycle, "race again")
  assertEq(cycle:state(), "lobby")
  assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Not available from the panel")
  command(cycle, " RACE ")
  assertEq(cycle:state(), "round")
  assertEq(decodeJson(env.lastSent("cnr_panelReply").data).text, "Race started")
  assertEq(decodeJson(env.lastSent("cnr_panelState").data).phase, "grid")
end)
