local panel = require("arcade.panel")
local autoRounds = require("arcade.autoRounds")
local M = {}

function M.new(services, manifest)
  local y, ctx = {}, {}
  for key, service in pairs(services) do ctx[key] = service end
  local game, lastIssuer, roundIssuer, roundDelay
  local state = "lobby"
  local transport = services.panel
  local now = ctx.clock.now
  local allow = panel.allowList(manifest.commands)
  ctx.round, ctx.panel = {}, {}
  ctx.version = manifest.version

  function y:context() return ctx end
  function y:attach(instance) game = instance end
  function y:state() return state end
  function y:allowCommand(text) return allow(text) end

  function y:dispatch(hook, ...)
    return game[hook](game, ...)
  end

  function ctx.round:start(request)
    local prepared, reason = y:dispatch("canStart", request)
    if not prepared then return nil, reason end
    if not prepared.solo and #prepared.participants < manifest.minPlayers then return nil, "Not enough players" end
    local snapshot = ctx.settings:snapshot()
    roundDelay = snapshot.autoNextDelaySeconds
    roundIssuer = request.issuer
    if not ctx.autoRounds:pending() then lastIssuer = roundIssuer end
    state = "round"
    ctx.cars:setPublishing(true)
    y:dispatch("start", prepared, snapshot, now())
    return true
  end

  function ctx.round:finish(result, audience, scheduleNext)
    ctx.spectators:releaseAll()
    local delay = scheduleNext and ctx.settings:get("autoNextRound") and roundDelay
    local payload = {}
    for key, value in pairs(result) do payload[key] = value end
    if delay then payload.autoNextSeconds = delay end
    ctx.messages.send(audience, "cnr_roundEnd", payload)
    ctx.cars:clearRound()
    ctx.traffic:clearRound()
    ctx.cars:clearPublished()
    if delay then
      lastIssuer = roundIssuer
      ctx.autoRounds:schedule(now() + delay)
    end
    state = "results"
    ctx.cars:setPublishing(false)
    y:dispatch("roundFinished")
  end

  function y:startNext()
    local players = ctx.roster:players()
    local issuer = lastIssuer
    if not players[issuer] then
      issuer = nil
      for pid in pairs(players) do
        if not issuer or pid < issuer then issuer = pid end
      end
    end
    if issuer then return ctx.round:start({ issuer = issuer, command = "next" }) end
  end

  local function panelState() return y:dispatch("panelState") end
  local function lobbyState() return y:dispatch("lobbyFields") end

  function ctx.panel:push(pid) transport:push(panelState, pid) end
  function ctx.panel:pushLobby(pid) transport:pushLobby(lobbyState, pid) end
  function ctx.panel:command(name, handler) transport:command(name, handler) end

  local startScheduled = autoRounds.register(transport, {
    settings = ctx.settings, a = ctx.autoRounds, send = ctx.messages.send,
    isActive = function() return state == "round" end,
    startNext = function() return y:startNext() end,
    reloadRound = function() ctx.settings:load() end,
    pushRules = function() y:dispatch("rulesChanged") end,
  })

  function y:tick()
    transport:tick(panelState, lobbyState)
    if ctx.autoRounds:due(now()) then startScheduled() end
    if state == "round" then self:dispatch("tick", now()) end
  end

  return y
end

return M
