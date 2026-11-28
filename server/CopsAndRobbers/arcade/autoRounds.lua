local autoRounds = {}

function autoRounds.new()
  local a = {}
  local nextAt

  function a:schedule(at)
    nextAt = at
  end

  function a:cancel()
    nextAt = nil
  end

  function a:pending()
    return nextAt
  end

  function a:due(now)
    return nextAt ~= nil and now >= nextAt
  end

  return a
end

function autoRounds.register(p, ctx)
  p:command("auto", function(pid, cmd, m)
    local arg = cmd.args[1] and cmd.args[1]:lower()
    if arg ~= "on" and arg ~= "off" then arg = ctx.settings.get("autoNextRound") and "off" or "on" end
    ctx.settings.set("autoNextRound", arg)
    ctx.refreshConfig()
    ctx.pushRules()
    if arg == "off" then
      ctx.a:cancel()
      ctx.send(-1, "cnr_autoNext", {})
    end
    m.reply(pid, "Automatic next round: " .. arg)
  end)

  local function startScheduled()
    ctx.a:cancel()
    if not ctx.isActive() then ctx.startNext() end
  end

  p:command("next", function(pid, cmd, m)
    if not ctx.a:pending() then return m.refuse(pid, "No round is scheduled") end
    startScheduled()
  end)

  p:command("reload", function(pid, cmd, m)
    if ctx.isActive() then return m.refuse(pid, "Stop the round before reloading") end
    ctx.reloadRound()
    ctx.pushRules()
    m.reply(pid, "Config reloaded")
  end)

  return startScheduled
end

return autoRounds
