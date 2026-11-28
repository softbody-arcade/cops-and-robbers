local messages = {}

function messages.new(options)
  local m = {}
  local prefix = assert(options and options.prefix, "messages require a prefix")
  local panelMirror

  function m.log(text)
    print(prefix .. text)
  end

  function m.send(pid, event, payload)
    if type(pid) ~= "number" or (pid < 0 and pid ~= -1) then return end
    return MP.TriggerClientEvent(pid, event, Util.JsonEncode(payload or {}))
  end

  function m.notify(pid, text, tone)
    m.send(pid, "cnr_notice", { msg = text, tone = tone or "info" })
  end

  function m.reply(pid, text, tone)
    if panelMirror and pid == panelMirror then
      m.send(pid, "cnr_panelReply", { text = text, tone = tone })
    else
      m.notify(pid, text, tone)
    end
  end

  function m.refuse(pid, text)
    m.reply(pid, text, "warn")
  end

  function m.broadcast(text, tone)
    m.notify(-1, text, tone)
  end

  function m.mirrored(pid, fn, ...)
    panelMirror = pid
    local ok, err = pcall(fn, ...)
    panelMirror = nil
    return ok, err
  end

  return m
end

return messages
