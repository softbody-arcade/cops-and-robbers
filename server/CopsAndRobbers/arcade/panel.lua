local commands = require("arcade.commands")

local M = {}

function M.signature(t)
  if type(t) ~= "table" then
    return type(t) == "string" and string.format("%q", t) or tostring(t)
  end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. M.signature(t[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.new(m, r)
  local p = {}
  local subs = r:perPlayer("panelSubs", "early")
  local handlers = {}
  local lastPanelSig, lastLobbySig
  local lastPanelError, lastLobbyError

  function p:push(panelState, opener)
    if opener then subs[opener] = nil end
    if not next(subs) and not opener then return end
    local state = panelState()
    local sig = M.signature(state)
    if sig ~= lastPanelSig then
      for pid in pairs(subs) do m.send(pid, "cnr_panelState", state) end
      lastPanelSig = sig
    end
    if opener then
      subs[opener] = true
      m.send(opener, "cnr_panelState", state)
    end
  end

  function p:pushLobby(lobbyState, pid)
    local state = lobbyState()
    if pid then return m.send(pid, "cnr_lobby", state) end
    local sig = M.signature(state)
    if sig ~= lastLobbySig then
      lastLobbySig = sig
      m.send(-1, "cnr_lobby", state)
    end
  end

  function p:close(pid)
    subs[pid] = nil
  end

  function p:command(name, handler)
    handlers[name] = handler
  end

  function p:run(pid, text)
    local cmd = commands.parseText(text)
    local handler = cmd and handlers[cmd.name]
    if handler then handler(pid, cmd, m) end
  end

  local function update(push, stateFn, name, previousError)
    local ok, err = pcall(push, p, stateFn)
    if not ok then
      if err ~= previousError then m.log(name .. " update failed: " .. tostring(err)) end
      return err or nil
    end
  end

  function p:tick(panelStateFn, lobbyStateFn)
    lastPanelError = update(self.push, panelStateFn, "panel", lastPanelError)
    lastLobbyError = update(self.pushLobby, lobbyStateFn, "lobby", lastLobbyError)
  end

  return p
end

return M
