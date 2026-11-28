local panel = require("arcade.panel")
local autoRounds = require("arcade.autoRounds")
local M = {}

function M.parseVehicleData(data)
  if type(data) ~= "string" then return nil end
  local start = data:find("{", 1, true)
  if not start then return nil end
  local json = data:sub(start)
  local ok, decoded = pcall(Util.JsonDecode, json)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

function M.new(services, manifest)
  local y, ctx = {}, {}
  for key, service in pairs(services) do ctx[key] = service end
  local game, lastIssuer, roundIssuer, roundDelay
  local state = "lobby"
  local transport = services.panel
  local now = ctx.clock.now
  local refusalLoggedAt = ctx.roster:perPlayer("refusalLoggedAt", "early")
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

  local function vehicleFacts(pid, vid)
    local cars = ctx.cars
    return {
      permitted = cars:permitted(pid), placementPending = cars:placementPending(pid),
      confirmed = cars:confirmed(pid), replacementAllowed = cars:replacementAllowed(pid),
      activeVid = cars:activeVid(pid), preRound = cars:isPreRound(pid, vid),
      trafficOpen = ctx.traffic:openCount(pid),
    }
  end

  local function refuseVehicle(kind, pid, vid, model, reason, at)
    local last = refusalLoggedAt[pid]
    if not last or at - last >= 10 then
      refusalLoggedAt[pid] = at
      ctx.messages.log(string.format("%s %s %s (vid %s): refused", ctx.roster:name(pid) or tostring(pid),
        kind == "spawn" and "spawned" or "edited", tostring(model or "?"), tostring(vid)))
    end
    ctx.messages.refuse(pid, reason or "Only the round car is allowed")
    return 1
  end

  local function checkVehicle(kind, pid, vid, data)
    local decoded = M.parseVehicleData(data)
    local facts, at = vehicleFacts(pid, vid), now()
    local verdict = y:dispatch("checkVehicle", kind, pid, vid, decoded, facts)
    if not verdict.allow then
      local extraTraffic = kind == "spawn" and facts.trafficOpen and verdict.roundCar == false
      return refuseVehicle(kind, pid, vid, not extraTraffic and decoded and decoded.jbm, verdict.reason, at)
    end
    if kind == "spawn" then
      if verdict.roundCar then
        local right, replaced = ctx.cars:claim(pid, vid)
        if not right then return refuseVehicle(kind, pid, vid, decoded and decoded.jbm, verdict.reason, at) end
        if replaced then y:dispatch("onVehicle", "replaced", pid, vid, nil, facts, at) end
      end
      ctx.cars:forgetPreRound(pid, vid)
    end
    if verdict.notify then y:dispatch("onVehicle", kind, pid, vid, decoded, facts, at) end
    return 0
  end

  function y:onVehicleSpawn(pid, vid, data) return checkVehicle("spawn", pid, vid, data) end
  function y:onVehicleEdited(pid, vid, data) return checkVehicle("edit", pid, vid, data) end

  function y:onVehicleDeleted(pid, vid)
    local facts, at = vehicleFacts(pid, vid), now()
    ctx.cars:forgetPreRound(pid, vid)
    if facts.activeVid == vid and ctx.cars:setActive(pid, nil) then
      self:dispatch("onVehicle", "replaced", pid, vid, nil, facts, at)
      ctx.cars:publish()
    end
    self:dispatch("onVehicle", "delete", pid, vid, nil, facts, at)
  end

  function y:onVehicleReset(pid, vid)
    self:dispatch("onVehicle", "reset", pid, vid, nil, vehicleFacts(pid, vid), now())
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
