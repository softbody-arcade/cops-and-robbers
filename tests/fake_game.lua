local race = {}

function race.manifest(version)
  return { id = "race", name = "Race", version = version, minPlayers = 2,
    commands = { exact = { "race" }, prefixes = {} }, actions = {}, clientEvents = { "race_lap" } }
end

function race.settingsDeclaration()
  return { DEFAULTS = { laps = 3 }, POSITIVE = { laps = true }, WHOLE = { laps = true } }
end

function race.new(ctx)
  local game = { phase = "lobby" }
  local laps = {}
  local rebuildId = 0

  function game:canStart()
    return { participants = ctx.roster:playingList(ctx.roster:players()) }
  end

  local function enter(pid)
    laps[pid] = 0
    ctx.cars:setup(pid, { model = "coupe" })
  end

  function game:start(prepared, snapshot)
    self.phase, self.snapshot = "grid", snapshot
    for _, pid in ipairs(prepared.participants) do enter(pid) end
  end

  function game:tick()
    if self.phase == "grid" then self.phase = "race" end
  end

  function game:join(pid)
    if self.phase == "grid" or self.phase == "race" then enter(pid) end
  end

  function game:leave(pid)
    if laps[pid] then
      ctx.messages.send(-1, "race_left", { racer = pid, vid = ctx.cars:confirmedVid(pid), sittingOut = ctx.roster:sittingOut(pid) })
      laps[pid] = nil
    end
  end

  function game:checkVehicle(kind, pid, vid, decoded)
    local allowed = laps[pid] ~= nil and decoded ~= nil and decoded.jbm == "coupe"
    return { allow = allowed, reason = "Race a coupe", roundCar = true, notify = true }
  end

  function game:onVehicle(kind, pid, vid)
    if kind == "spawn" then
      ctx.cars:confirm(pid, vid)
      ctx.cars:publish()
    end
  end

  function game:clientEvent(name, pid)
    assert(name == "race_lap")
    if self.phase ~= "race" or not laps[pid] then return end
    laps[pid] = laps[pid] + 1
    if laps[pid] == self.snapshot.laps then
      ctx.round:finish({ winner = pid }, -1, true)
    elseif laps[pid] == 1 then
      rebuildId = rebuildId + 1
      ctx.cars:rebuild({ pid }, { rebuildId = rebuildId }, rebuildId)
    end
  end

  function game:panelAction(pid, action, payload)
    assert(action == "command" and payload.text == "race")
    if ctx.round:start({ issuer = pid, command = payload.text }) then ctx.messages.reply(pid, "Race started") end
  end

  function game:panelState() return { phase = self.phase } end
  function game:lobbyFields() return { phase = self.phase } end
  function game:roundFinished()
    self.phase, laps = "results", {}
  end
  function game:settingsChanged(keys) end
  function game:rulesChanged() end
  return game
end

return race
