local function encode(v, canonical)
  if type(v) == "table" then
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and n == #v then
      local items = {}
      for i, x in ipairs(v) do items[i] = encode(x, canonical) end
      return "[" .. table.concat(items, ",") .. "]"
    end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(x, canonical)) end
    if canonical then table.sort(parts) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  if canonical and type(v) == "number" then return string.format("%.10g", v) end
  return tostring(v)
end

function decodeJson(str)
  local pos = 1
  local function ws() pos = str:find("%S", pos) or #str + 1 end
  local value
  local function stringValue()
    local out = {}
    pos = pos + 1
    while true do
      local c = str:sub(pos, pos)
      if c == "" then error("bad json") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then pos = pos + 1; c = str:sub(pos, pos) end
      out[#out + 1] = c
      pos = pos + 1
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = str:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1; ws()
      if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        ws()
        if str:sub(pos, pos) ~= '"' then error("bad json") end
        local k = stringValue()
        ws()
        if str:sub(pos, pos) ~= ":" then error("bad json") end
        pos = pos + 1
        t[k] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then error("bad json") end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1; ws()
      if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then error("bad json") end
      end
    elseif c == '"' then
      return stringValue()
    elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("bad json") end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local v = value()
  ws()
  if pos <= #str then error("bad json") end
  return v
end

local function fakes(env, opts)
  opts = opts or {}
  env.sent, env.chats, env.events, env.timers = {}, {}, {}, {}
  env.removed, env.logs, env.stream, env.timerOps = {}, {}, {}, {}
  env.clock, env.positions, env.vidPositions = 0, {}, {}
  env.vehicles = opts.vehicles or { [1] = { [0] = "x" }, [2] = { [0] = "x" } }

  local function recordOp(detail)
    env.stream[#env.stream + 1] = { kind = "op", t = env.clock, text = string.format("%.3f %s", env.clock, detail) }
  end

  _G.MP = {
    Settings = { Map = 4, MaxCars = 2 },
    Get = function(key)
      if key == 2 then return opts.maxCars or 1 end
      return opts.map or "/levels/west_coast_usa/info.json"
    end,
    CreateTimer = function()
      local start = env.clock
      return { GetCurrent = function()
        local elapsed = env.clock - start
        if opts.floatTimer then return (string.unpack("f", string.pack("f", elapsed))) end
        return elapsed
      end, Start = function() start = env.clock end }
    end,
    SendChatMessage = function(pid, msg)
      recordOp("chat " .. pid .. " " .. msg)
      env.chats[#env.chats + 1] = { pid, msg }
    end,
    TriggerClientEvent = function(pid, ev, data)
      env.stream[#env.stream + 1] = { kind = "send", t = env.clock, to = pid, ev = ev, data = data }
      if env.loading and env.loading[pid] then return false, "Player hasn't joined yet" end
      env.sent[#env.sent + 1] = { pid = pid, ev = ev, data = data }
      return true, ""
    end,
    GetPlayers = function()
      local t = {}
      for pid, name in pairs(env.names or { "Reinder", "Bob" }) do t[pid] = name end
      return t
    end,
    GetPlayerName = function(pid) return (env.names or { "Reinder", "Bob" })[pid] end,
    GetPlayerIdentifiers = function(pid) return (env.ids or {})[pid] or {} end,
    GetPlayerVehicles = function(pid) return env.vehicles[pid] end,
    GetPositionRaw = function(pid, vid)
      local byVid = env.vidPositions[pid .. "-" .. tostring(vid)]
      if byVid then return byVid, "" end
      local p = env.positions[pid]
      if not p then return nil, "Vehicle not found" end
      return { pos = { p, 0, 0 }, vel = { 0, 0, 0 } }, ""
    end,
    RemoveVehicle = function(pid, vid)
      local vehicle = pid .. "-" .. vid
      recordOp("remove " .. vehicle)
      env.removed[#env.removed + 1] = vehicle
    end,
    RegisterEvent = function(ev, fn) env.events[ev] = fn end,
    CreateEventTimer = function(ev, ms)
      recordOp("timer create " .. ev .. " " .. ms)
      env.timerOps[#env.timerOps + 1] = { op = "create", name = ev, ms = ms }
      env.timers[ev] = ms
    end,
    CancelEventTimer = function(ev)
      recordOp("timer cancel " .. ev)
      env.timerOps[#env.timerOps + 1] = { op = "cancel", name = ev }
      env.timers[ev] = nil
    end,
  }
  _G.Util = {
    JsonEncode = encode,
    JsonDecode = function(s) return decodeJson(s) end,
    JsonPrettify = function(s) return s end,
  }
  _G.FS = {
    CreateDirectory = function(p)
      recordOp("fs mkdir " .. p)
      os.execute("mkdir -p '" .. p .. "'")
    end,
    Remove = function(p)
      recordOp("fs remove " .. p)
      os.remove(p)
    end,
    Rename = function(a, b)
      local file = io.open(a, "rb")
      local content = ""
      if file then
        content = file:read("*a") or ""
        file:close()
        local ok, value = pcall(decodeJson, content)
        if ok then content = encode(value, true) end
      end
      recordOp("fs write " .. b .. " " .. content)
      if opts.renameFails and a:find("leaderboard.json$") then return false, "denied" end
      return os.rename(a, b) ~= nil
    end,
    Exists = function(p)
      local f = io.open(p)
      if f then f:close() end
      return f ~= nil
    end,
  }

  function env.lastSent(ev)
    for i = #env.sent, 1, -1 do if env.sent[i].ev == ev then return env.sent[i] end end
  end
end

local function initialize(env, opts)
  os.execute("mkdir -p '" .. env.dir .. "'")
  for name, text in pairs(opts.files or {}) do
    os.execute("mkdir -p '" .. env.dir .. "data'")
    local ef = assert(io.open(env.dir .. name, "w"))
    ef:write(text)
    ef:close()
  end
  if opts.leaderboard then
    os.execute("mkdir -p '" .. env.dir .. "data'")
    local lf = assert(io.open(env.dir .. "data/leaderboard.json", "w"))
    lf:write(opts.leaderboard)
    lf:close()
  end
  local f = assert(io.open(env.dir .. "config.json", "w"))
  f:write(opts.config or assert(io.open("server/CopsAndRobbers/config.json")):read("*a"))
  f:close()
  fakes(env, opts)

  local realPrint = print
  local function capture(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local text = table.concat(parts, " ")
    env.logs[#env.logs + 1] = text
    env.stream[#env.stream + 1] = { kind = "log", t = env.clock, text = text }
  end

  local src = assert(io.open("server/CopsAndRobbers/main.lua")):read("*a")
  local chunk = assert(load(src, env.dir .. "main.lua"))
  function env.reload()
    local outer = print
    print = capture
    local ok, err = pcall(chunk)
    print = outer
    assert(ok, err)
  end

  function env.call(ev, ...)
    local outer = print
    print = function(...)
      capture(...)
      if outer ~= realPrint then outer(...) end
    end
    local results = table.pack(xpcall(_G[env.events[ev]], debug.traceback, ...))
    print = outer
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
  end
  function env.noticeHas(text, tone)
    for _, m in ipairs(env.sent) do
      if m.ev == "cnr_notice" then
        local d = decodeJson(m.data)
        if d.msg:find(text, 1, true) and (tone == nil or d.tone == tone) then return true end
      end
    end
    return false
  end
  function env.replyHas(text)
    local r = env.lastSent("cnr_panelReply")
    return r ~= nil and decodeJson(r.data).text:find(text, 1, true) ~= nil
  end
  function env.caught()
    local r = env.lastSent("cnr_roundEnd")
    return r ~= nil and r.data:find('"reason":"caught"', 1, true) ~= nil
  end
  function env.logHas(text)
    for _, l in ipairs(env.logs) do if l:find(text, 1, true) then return true end end
    return false
  end
  function env.startRound()
    env.panel(2, "start rein")
    env.positions[1], env.positions[2] = 0, 5
    env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  end
  function env.panel(pid, text)
    env.call("cnr_panel", pid, '{"action":"command","text":"' .. text .. '"}')
  end
  function env.go() env.panel(1, "go") end
  env.reload()
end

local function boot(opts)
  opts = opts or {}
  local env = {}
  local tmp = os.tmpname(); os.remove(tmp)
  env.dir = tmp .. "_cnr/"
  function env.cleanup() os.execute("rm -rf '" .. env.dir .. "'") end
  local ok, err = pcall(initialize, env, opts)
  if not ok then env.cleanup(); error(err, 0) end
  return env
end

serverBoot = { boot = boot, fakes = fakes, encode = encode }
