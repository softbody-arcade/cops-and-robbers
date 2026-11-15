local function encode(v)
  if type(v) == "table" then
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and n == #v then
      local items = {}
      for i, x in ipairs(v) do items[i] = encode(x) end
      return "[" .. table.concat(items, ",") .. "]"
    end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(x)) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
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

local function boot(opts)
  opts = opts or {}
  local env = { sent = {}, chats = {}, events = {}, timers = {}, removed = {}, logs = {}, clock = 0, positions = {} }
  local tmp = os.tmpname(); os.remove(tmp)
  env.dir = tmp .. "_cnr/"
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
  env.vehicles = opts.vehicles or { [1] = { [0] = "x" }, [2] = { [0] = "x" } }

  _G.MP = {
    Settings = { Map = 4 },
    Get = function() return opts.map or "/levels/west_coast_usa/info.json" end,
    CreateTimer = function()
      return { GetCurrent = function() return env.clock end, Start = function() end }
    end,
    SendChatMessage = function(pid, msg) env.chats[#env.chats + 1] = { pid, msg } end,
    TriggerClientEvent = function(pid, ev, data) env.sent[#env.sent + 1] = { pid = pid, ev = ev, data = data } end,
    GetPlayers = function() return env.names and { [1] = env.names[1], [2] = env.names[2] } or { [1] = "Reinder", [2] = "Bob" } end,
    GetPlayerName = function(pid) return (env.names or { "Reinder", "Bob" })[pid] end,
    GetPlayerIdentifiers = function(pid) return (env.ids or {})[pid] or {} end,
    GetPlayerVehicles = function(pid) return env.vehicles[pid] end,
    GetPositionRaw = function(pid, vid)
      local p = env.positions[pid]
      if not p then return nil, "Vehicle not found" end
      return { pos = { p, 0, 0 }, vel = { 0, 0, 0 } }, ""
    end,
    RemoveVehicle = function(pid, vid) env.removed[#env.removed + 1] = pid .. "-" .. vid end,
    RegisterEvent = function(ev, fn) env.events[ev] = fn end,
    CreateEventTimer = function(ev, ms) env.timers[ev] = ms end,
    CancelEventTimer = function(ev) env.timers[ev] = nil end,
  }
  _G.Util = {
    JsonEncode = encode,
    JsonDecode = function(s) return decodeJson(s) end,
    JsonPrettify = function(s) return s end,
  }
  _G.FS = {
    CreateDirectory = function(p) os.execute("mkdir -p '" .. p .. "'") end,
    Remove = function(p) os.remove(p) end,
    Rename = function(a, b)
      if opts.renameFails and a:find("leaderboard.json$") then return false, "denied" end
      return os.rename(a, b) ~= nil
    end,
    Exists = function(p)
      local f = io.open(p)
      if f then f:close() end
      return f ~= nil
    end,
  }

  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    env.logs[#env.logs + 1] = table.concat(parts, " ")
  end
  local src = assert(io.open("server/CopsAndRobbers/main.lua")):read("*a")
  local chunk = assert(load(src, env.dir .. "main.lua"))
  local ok, err = pcall(chunk)
  print = realPrint
  assert(ok, err)

  function env.call(ev, ...) return _G[env.events[ev]](...) end
  function env.lastSent(ev)
    for i = #env.sent, 1, -1 do if env.sent[i].ev == ev then return env.sent[i] end end
  end
  function env.chatHas(text)
    for _, c in ipairs(env.chats) do if c[2]:find(text, 1, true) then return true end end
    return false
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
  function env.cleanup() os.execute("rm -rf '" .. env.dir .. "'") end
  return env
end

test("main registers events and timer", function()
  local env = boot()
  assertEq(env.events.onChatMessage ~= nil, true)
  assertEq(env.events.cnr_vehiclePicked ~= nil, true)
  assertEq(env.timers.cnr_tick, 250)
  env.cleanup()
end)

test("plugin dir resolves without @ chunk name, so config.json is read", function()
  local env = boot({ config = '{"headStartSeconds": 3}' })
  env.call("cnr_panel", 1, '{"action":"open"}')
  assertEq(env.lastSent("cnr_panelState").data:find('"headStartSeconds":3', 1, true) ~= nil, true)
  env.cleanup()
end)

test("corrupt config.json logs a warning", function()
  local env = boot({ config = '{"headStartSeconds": 3,}' })
  assertEq(env.logHas("config.json is not valid JSON"), true)
  env.cleanup()
end)

test("plugin load unlocks any client left in a round", function()
  local env = boot()
  local e = env.lastSent("cnr_roundEnd")
  assertEq(e ~= nil, true)
  assertEq(e.pid, -1)
  assertEq(e.data:find('"reason":"cancelled"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("non-command chat passes through", function()
  local env = boot()
  assertEq(env.call("onChatMessage", 1, "Reinder", "hello"), 0)
  env.cleanup()
end)

test("full round over main wiring", function()
  local env = boot()
  env.startRound()
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  local setup = env.lastSent("cnr_roundSetup")
  assertEq(setup.data:find('"runnerId":1', 1, true) ~= nil, true)
  assertEq(env.call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}'), 1)
  env.go()
  assertEq(env.lastSent("cnr_countdown") ~= nil, true)
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_runnerGo") ~= nil, true)
  assertEq(env.lastSent("cnr_release") ~= nil, true)
  assertEq(env.chatHas("Runner caught by Bob! Reinder survived"), true)
  assertEq(env.chatHas("1. Reinder"), true)
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("edit in real pid-vid format with round car is allowed", function()
  local env = boot()
  env.startRound()
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"a":"b"}},"pro":"0"}'), 0)
  assertEq(env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"etk800","vcf":{"parts":{}}}'), 1)
  env.cleanup()
end)

test("parts changes never replace the car and are only logged once per round", function()
  local env = boot()
  env.startRound()
  local base = '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"engine":"v8"}}}'
  local tuned = '1-0:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc","parts":{"engine":"v12"}}}'
  env.call("onVehicleEdited", 1, 0, base)
  env.sent = {}
  env.chats = {}
  for _ = 1, 10 do
    assertEq(env.call("onVehicleEdited", 1, 0, tuned), 0)
    assertEq(env.call("onVehicleEdited", 1, 0, base), 0)
  end
  assertEq(env.lastSent("cnr_restoreConfig"), nil)
  for _, c in ipairs(env.chats) do assertEq(c[2]:find("changed parts", 1, true), nil, c[2]) end
  env.cleanup()
end)

test("spawn in real roles:name:pid-vid format is parsed", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.startRound()
  assertEq(env.call("onVehicleSpawn", 2, 0, 'USER:Bob:2-0:{"jbm":"pickup","vcf":{"partConfigFilename":"/vehicles/pickup/base.pc"}}'), 0)
  env.cleanup()
end)

test("client reports its vehicle, extras are removed", function()
  local env = boot({ vehicles = { [1] = { [0] = "x", [1] = "y", [2] = "z" }, [2] = { [0] = "x" } } })
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":1}')
  assertEq(#env.removed, 2)
  assertEq(env.removed[1] == "1-0" or env.removed[2] == "1-0", true)
  assertEq(env.removed[1] == "1-2" or env.removed[2] == "1-2", true)
  env.cleanup()
end)

test("reset of a non-active vehicle is ignored", function()
  local env = boot({ vehicles = { [1] = { [0] = "x", [1] = "y" }, [2] = { [0] = "x" } } })
  env.startRound()
  env.call("cnr_myVehicle", 1, '{"vid":1}')
  env.go()
  for _ = 1, 34 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.call("onVehicleReset", 1, 0, "")
  assertEq(env.chatHas("reset illegally"), false)
  env.call("onVehicleReset", 1, 1, "")
  assertEq(env.chatHas("Reinder reset illegally"), true)
  env.cleanup()
end)

test("stop while idle replies and still unlocks clients", function()
  local env = boot()
  env.sent = {}
  env.panel(1, "stop")
  assertEq(env.chatHas("No round running"), true)
  assertEq(env.lastSent("cnr_roundEnd") ~= nil, true)
  env.cleanup()
end)

test("addstation saves file", function()
  local env = boot()
  env.positions[1] = 0
  env.call("onChatMessage", 1, "Reinder", "/cnr addstation")
  assertEq(env.chatHas("Gas station added (1 on west_coast_usa)"), true)
  local f = io.open(env.dir .. "data/stations/west_coast_usa.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("/cnr color saves per player and goes into setup", function()
  local env = boot()
  env.call("onChatMessage", 1, "Reinder", "/cnr color #ff0000")
  assertEq(env.chatHas("Your car color is now #ff0000"), true)
  env.call("onChatMessage", 1, "Reinder", "/cnr color #zz")
  assertEq(env.chatHas("Use a hex color like #ff0000"), true)
  env.startRound()
  local setups = {}
  for _, m in ipairs(env.sent) do if m.ev == "cnr_roundSetup" then setups[m.pid] = m.data end end
  assertEq(setups[1]:find('"hex":"#ff0000"', 1, true) ~= nil, true)
  assertEq(setups[2]:find('"hex"', 1, true), nil)
  local f = io.open(env.dir .. "data/colors.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("/cnr color during prep repaints right away", function()
  local env = boot()
  env.startRound()
  env.call("onChatMessage", 2, "Bob", "/cnr color 00ff00")
  local m = env.lastSent("cnr_paint")
  assertEq(m.pid, 2)
  assertEq(m.data:find('"hex":"#00ff00"', 1, true) ~= nil, true)
  env.call("onChatMessage", 2, "Bob", "/cnr color off")
  assertEq(env.chatHas("Car color cleared"), true)
  env.cleanup()
end)

test("/cnr test runner: AI vehicles are tracked as cops", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 1)
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.lastSent("cnr_roundSetup").data:find('"role":"runner"', 1, true) ~= nil, true)
  assertEq(env.lastSent("cnr_roundSetup").data:find('"hex":"#1f5fff"', 1, true) ~= nil, true)
  assertEq(env.lastSent("cnr_setupAI").pid, 1)
  assertEq(env.call("onVehicleSpawn", 1, 1, 'USER:Reinder:1-1:{"jbm":"pickup","vcf":{"partConfigFilename":"vehicles/pickup/base.pc"}}'), 0)
  env.vehicles[1][1] = "y"
  env.call("cnr_myVehicle", 1, '{"vid":0}')
  assertEq(#env.removed, 0)
  env.call("cnr_aiVehicles", 1, '{"ai":[{"id":-10,"vid":1}]}')
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 1 and vid == 1 then return { pos = { 5, 0, 0 }, vel = { 0, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_roundEnd").data:find('"reason":"caught"', 1, true) ~= nil, true)
  for _, m in ipairs(env.sent) do assertEq(m.pid >= -1, true) end
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f, nil)
  env.cleanup()
end)

test("penalty is shown on everyone's screen", function()
  local env = boot()
  env.startRound()
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local raw = MP.GetPositionRaw
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 then return { pos = { 200, 0, 0 }, vel = { 120 / 3.6, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  MP.GetPositionRaw = function(pid, vid)
    if pid == 2 then return { pos = { 201, 0, 0 }, vel = { 0, 0, 0 } }, "" end
    return raw(pid, vid)
  end
  env.clock = env.clock + 0.25; env.call("cnr_tick")
  local n = env.lastSent("cnr_notice")
  assertEq(n.pid, -1)
  assertEq(n.data:find('"msg":"Bob: crash penalty 10s"', 1, true) ~= nil, true)
  assertEq(n.data:find('"about":2', 1, true) ~= nil, true)
  env.cleanup()
end)

local function runToChase(env)
  env.startRound()
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.positions[2] = 900; env.call("cnr_tick") end
end

test("color during the chase does not repaint", function()
  local env = boot()
  runToChase(env)
  env.sent = {}
  env.call("onChatMessage", 1, "Reinder", "/cnr color #ff0000")
  assertEq(env.lastSent("cnr_paint"), nil)
  assertEq(env.chatHas("applies from the next round"), true)
  env.cleanup()
end)

test("test round events reach only the issuer", function()
  local env = boot({ vehicles = { [1] = { [0] = "x" } } })
  env.sent = {}
  env.chats = {}
  env.panel(1, "test cop")
  env.positions[1] = 0
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 50 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "stop")
  for _, m in ipairs(env.sent) do
    if m.ev ~= "cnr_roundEnd" or not m.data:find("cancelled") then assertEq(m.pid, 1, m.ev) end
  end
  for _, c in ipairs(env.chats) do assertEq(c[1], 1, c[2]) end
  env.cleanup()
end)

test("/cnr start cancels a running test round", function()
  local env = boot()
  env.panel(1, "test cop")
  env.panel(2, "start bob")
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  env.cleanup()
end)

test("/cnr end records the run", function()
  local env = boot()
  runToChase(env)
  env.panel(2, "end")
  assertEq(env.chatHas("Round ended: Reinder survived"), true)
  local f = io.open(env.dir .. "data/leaderboard.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
  env.cleanup()
end)

test("/cnr start next and again", function()
  local env = boot()
  env.panel(1, "start next")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.chatHas("Bob is the runner"), true)
  env.panel(1, "stop")
  env.panel(1, "start next")
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.chatHas("Reinder is the runner"), true)
  env.panel(1, "stop")
  env.chats = {}
  env.panel(2, "start again")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.chatHas("Reinder is the runner"), true)
  env.cleanup()
end)

test("last seen goes to cops, nearest cop to the runner", function()
  local env = boot({ config = '{"lastSeenIntervalSeconds": 5}' })
  runToChase(env)
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local seen, nearest = env.lastSent("cnr_lastSeen"), env.lastSent("cnr_nearestCop")
  assertEq(seen.pid, 2)
  assertEq(nearest.pid, 1)
  env.cleanup()
end)

test("pick request carries the excluded models", function()
  local env = boot()
  env.panel(2, "start rein")
  assertEq(env.lastSent("cnr_pickVehicle").data:find("citybus", 1, true) ~= nil, true)
  env.cleanup()
end)

local EARTH = "/levels/beamng_earth/info.json"
local LAT, LON = 52.0, 5.0
local M_PER_DEG = 111250

local function geoCar(northMeters, kmh, id)
  local c = string.format('{"lat":%.9f,"lon":%.9f,"h":0,"ve":0,"vn":%.4f,"vu":0', LAT + northMeters / M_PER_DEG, LON, (kmh or 0) / 3.6)
  if id then c = c .. string.format(',"id":%d', id) end
  return c .. "}"
end

local function report(env, pid, ...)
  env.call("cnr_geo", pid, '{"cars":[' .. table.concat({ ... }, ",") .. ']}')
end

test("earth mode is announced on load and join", function()
  local env = boot({ map = EARTH })
  local m = env.lastSent("cnr_mode")
  assertEq(m.pid, -1); assertEq(m.data:find('"geo":true', 1, true) ~= nil, true)
  env.sent = {}
  env.call("onPlayerJoin", 2)
  assertEq(env.lastSent("cnr_mode").pid, 2)
  env.cleanup()
  local wc = boot()
  assertEq(wc.lastSent("cnr_mode").data:find('"geo":false', 1, true) ~= nil, true)
  wc.cleanup()
end)

test("earth catch uses geo reports, not raw positions", function()
  local env = boot({ map = EARTH })
  env.positions[1], env.positions[2] = 0, 5000
  env.panel(2, "start rein")
  report(env, 1, geoCar(0)); report(env, 2, geoCar(5))
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local setup
  for _, m in ipairs(env.sent) do if m.ev == "cnr_roundSetup" and m.pid == 2 then setup = m.data end end
  assertEq(setup:find('"geo":true', 1, true) ~= nil, true)
  assertEq(setup:find('"runnerGeo"', 1, true) ~= nil, true)
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25
    report(env, 1, geoCar(0)); report(env, 2, geoCar(5))
    env.call("cnr_tick")
  end
  assertEq(env.chatHas("Runner caught by Bob!"), true)
  env.cleanup()
end)

test("stale geo reports do not count", function()
  local env = boot({ map = EARTH })
  env.panel(2, "start rein")
  report(env, 1, geoCar(0)); report(env, 2, geoCar(5))
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.chatHas("Runner caught"), false)
  env.cleanup()
end)

test("earth stations merge and dedupe", function()
  local env = boot({ map = EARTH })
  local function st(north, name) return string.format('{"lat":%.9f,"lon":%.9f,"name":"%s"}', LAT + north / M_PER_DEG, LON, name) end
  env.call("cnr_stations", 1, '{"map":"beamng_earth","geo":true,"stations":[' .. st(0, "Shell") .. "," .. st(2000, "BP") .. ']}')
  env.call("cnr_stations", 2, '{"map":"beamng_earth","geo":true,"stations":[' .. st(20, "Shell") .. "," .. st(4000, "Esso") .. ']}')
  local saved = assert(io.open(env.dir .. "data/stations/beamng_earth.json")):read("*a")
  local n = 0
  for _ in saved:gmatch('"lat"') do n = n + 1 end
  assertEq(n, 3)
  env.cleanup()
end)

test("earth gas station reset uses geo positions", function()
  local env = boot({ map = EARTH })
  env.call("cnr_stations", 1, string.format('{"map":"beamng_earth","geo":true,"stations":[{"lat":%.9f,"lon":%.9f}]}', LAT + 400 / M_PER_DEG, LON))
  env.panel(2, "start rein")
  report(env, 1, geoCar(0)); report(env, 2, geoCar(900))
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0)); report(env, 2, geoCar(900)); env.call("cnr_tick") end
  env.sent = {}
  env.clock = env.clock + 0.25; report(env, 1, geoCar(400)); report(env, 2, geoCar(900)); env.call("cnr_tick")
  local st
  for _, m in ipairs(env.sent) do if m.ev == "cnr_state" and m.pid == 1 then st = m.data end end
  assertEq(st:find("gas station", 1, true) ~= nil, true)
  env.cleanup()
end)

test("earth AI cars are reported by the test issuer", function()
  local env = boot({ map = EARTH, vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  report(env, 1, geoCar(0))
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25
    report(env, 1, geoCar(0), geoCar(5, 0, -10), geoCar(900, 0, -11))
    env.call("cnr_tick")
  end
  assertEq(env.chatHas("Test round: ReinderN caught") or env.chatHas("Test round: Reinder caught"), true)
  env.cleanup()
end)

test("earth last seen carries lat/lon", function()
  local env = boot({ map = EARTH, config = '{"lastSeenIntervalSeconds": 5}' })
  env.panel(2, "start rein")
  report(env, 1, geoCar(0)); report(env, 2, geoCar(900))
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 70 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick") end
  local seen = env.lastSent("cnr_lastSeen")
  assertEq(seen.pid, 2)
  assertEq(seen.data:find('"lat"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("earth relocations grant grace for own car and test AI", function()
  local env = boot({ map = EARTH, vehicles = { [1] = { [0] = "x" } } })
  env.panel(1, "test runner")
  report(env, 1, geoCar(0))
  env.call("cnr_vehiclePicked", 1, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0), geoCar(300, 0, -10), geoCar(900, 0, -11)); env.call("cnr_tick") end
  env.chats = {}
  env.call("cnr_relocated", 1, '{"ids":[-10]}')
  env.call("cnr_relocated", 1, '{}')
  env.call("onVehicleReset", 1, 0, "")
  env.clock = env.clock + 0.25
  report(env, 1, geoCar(5000), geoCar(5300, 0, -10), geoCar(900, 0, -11))
  env.call("cnr_tick")
  for _, c in ipairs(env.chats) do
    assertEq(c[2]:find("illegally", 1, true), nil, c[2])
    assertEq(c[2]:find("ReinderN teleported", 1, true) or c[2]:find("Reinder teleported", 1, true) or c[2]:find("AI green teleported", 1, true), nil, c[2])
  end
  env.cleanup()
end)

test("earth: an illegal reset waits a second for a relocation report", function()
  local env = boot({ map = EARTH })
  env.panel(2, "start rein")
  report(env, 1, geoCar(0)); report(env, 2, geoCar(900))
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick") end
  env.chats = {}
  env.call("onVehicleReset", 1, 0, "")
  env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick")
  env.call("cnr_relocated", 1, "{}")
  for _ = 1, 8 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick") end
  assertEq(env.chatHas("reset illegally"), false)
  for _ = 1, 8 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick") end
  env.call("onVehicleReset", 1, 0, "")
  for _ = 1, 8 do env.clock = env.clock + 0.25; report(env, 1, geoCar(0, 60)); report(env, 2, geoCar(900, 60)); env.call("cnr_tick") end
  assertEq(env.chatHas("Reinder reset illegally") or env.chatHas("ReinderN reset illegally"), true)
  env.cleanup()
end)

test("players are recognised by BeamMP account across name changes", function()
  local env = boot()
  env.ids = { [1] = { beammp = "7" }, [2] = { beammp = "9" } }
  env.call("onChatMessage", 1, "Reinder", "/cnr color #ff0000")
  env.names = { "guest555", "Bob" }
  env.panel(2, "start guest")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local setup
  for _, m in ipairs(env.sent) do if m.ev == "cnr_roundSetup" and m.pid == 1 then setup = m.data end end
  assertEq(setup:find('"hex":"#ff0000"', 1, true) ~= nil, true)
  env.go()
  env.positions[1], env.positions[2] = 0, 5
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local saved = assert(io.open(env.dir .. "data/leaderboard.json")):read("*a")
  assertEq(saved:find('"key":"beammp:7"', 1, true) ~= nil, true)
  assertEq(saved:find('"catcherKeys"', 1, true) ~= nil, true)
  env.names = { "Reinder", "Bob" }
  env.chats = {}
  env.panel(2, "start again")
  env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.chatHas("Reinder is the runner"), true)
  env.cleanup()
end)

test("guests fall back to their name", function()
  local env = boot()
  env.call("onChatMessage", 1, "Reinder", "/cnr color #00ff00")
  local saved = assert(io.open(env.dir .. "data/colors.json")):read("*a")
  assertEq(saved:find('"name:Reinder"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("auto next round prepares a new round but waits for go", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.chatHas("Next round in 5s") then break end
  end
  assertEq(env.chatHas("Next round in 5s"), true)
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local pick = env.lastSent("cnr_pickVehicle")
  assertEq(pick ~= nil, true)
  env.call("cnr_vehiclePicked", pick.pid, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  assertEq(env.chatHas("Bob is the runner"), true)
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_countdown"), nil)
  env.cleanup()
end)

test("/cnr auto toggles and saves the setting", function()
  local env = boot()
  env.panel(1, "auto on")
  assertEq(env.chatHas("Automatic next round: on"), true)
  local saved = assert(io.open(env.dir .. "config.json")):read("*a")
  assertEq(saved:find('"autoNextRound":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("manual start cancels a pending automatic round", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound()
  env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    if env.chatHas("Next round in 5s") then break end
  end
  env.panel(1, "start reinder")
  env.sent = {}
  for _ = 1, 24 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  env.cleanup()
end)

test("version is shown in help and the log", function()
  local env = boot()
  assertEq(env.logHas("Cops and Robbers 1.7.0 loaded"), true)
  env.call("onChatMessage", 1, "Reinder", "/cnr help")
  assertEq(env.chatHas("Cops and Robbers 1.7.0"), true)
  assertEq(env.lastSent("cnr_mode").data:find('"version":"1.7.0"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("leaderboard with a wrong shape is moved aside", function()
  local tmp = boot()
  local dir = tmp.dir
  tmp.cleanup()
  local env = boot()
  local f = assert(io.open(env.dir .. "data/leaderboard.json", "w")); f:write('{"runs":5}'); f:close()
  env.cleanup()
  env = boot()
  os.execute("mkdir -p '" .. env.dir .. "data'")
  f = assert(io.open(env.dir .. "data/leaderboard.json", "w")); f:write('{"runs":5}'); f:close()
  local src = assert(io.open("server/CopsAndRobbers/main.lua")):read("*a")
  local logs = {}
  local realPrint = print
  print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
  assert(load(src, env.dir .. "main.lua"))()
  print = realPrint
  local moved = false
  for _, l in ipairs(logs) do if l:find("moved to", 1, true) then moved = true end end
  assertEq(moved, true)
  env.cleanup()
end)

test("roundEnd carries autoNextSeconds when an auto round is scheduled", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound(); env.go()
  for _ = 1, 90 do
    env.clock = env.clock + 0.25; env.call("cnr_tick")
    local e = env.lastSent("cnr_roundEnd")
    if e and e.data:find("caught", 1, true) then break end
  end
  assertEq(env.lastSent("cnr_roundEnd").data:find('"autoNextSeconds":5', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a recorded run sends the top 3 for the map", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local top = env.lastSent("cnr_top")
  assertEq(top.pid, -1)
  assertEq(top.data:find("1. Reinder", 1, true) ~= nil, true)
  env.cleanup()
end)

test("a mid-chase join gets chaseElapsed in its setup", function()
  local env = boot()
  env.startRound(); env.go()
  env.positions[1], env.positions[2] = 0, 900
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.sent = {}
  env.names = { "Reinder", "Bob", "Cid" }
  env.call("onPlayerJoin", 3)
  local setup = env.lastSent("cnr_roundSetup")
  assertEq(setup.pid, 3)
  assertEq(setup.data:find('"chaseElapsed":5', 1, true) ~= nil, true)
  env.cleanup()
end)

local function countSent(env, ev, pid)
  local n = 0
  for _, s in ipairs(env.sent) do if s.ev == ev and (pid == nil or s.pid == pid) then n = n + 1 end end
  return n
end

local function chatLine(env, line)
  for _, c in ipairs(env.chats) do if c[2] == "[CnR] " .. line then return true end end
  return false
end

local function showConfig(env)
  env.chats = {}
  env.call("cnr_panel", 1, '{"action":"open"}')
  local st = decodeJson(env.lastSent("cnr_panelState").data)
  for k, v in pairs(st.settings) do
    if type(v) == "table" then v = table.concat(v, ", ") end
    env.chats[#env.chats + 1] = { 1, "[CnR] " .. k .. " = " .. tostring(v) }
  end
end

test("panel open sends state to the opener", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  local s = env.lastSent("cnr_panelState")
  assertEq(s.pid, 1)
  assertEq(s.data:find('"phase":"idle"', 1, true) ~= nil, true)
  assertEq(s.data:find('"map":"west_coast_usa"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("panel state is pushed on change, not every tick", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  local n = countSent(env, "cnr_panelState", 1)
  env.call("cnr_tick"); env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), n)
  env.startRound()
  env.call("cnr_tick")
  local m = countSent(env, "cnr_panelState", 1)
  assertEq(m > n, true)
  assertEq(env.lastSent("cnr_panelState").data:find('"phase":"prep"', 1, true) ~= nil, true)
  env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), m)
  env.cleanup()
end)

test("chat change is pushed to panel subscribers", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.panel(2, "auto on")
  env.call("cnr_tick")
  local s = env.lastSent("cnr_panelState")
  assertEq(s.pid, 1)
  assertEq(s.data:find('"autoNextRound":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("panel command runs handlers and mirrors replies", function()
  local env = boot()
  env.call("cnr_panel", 2, '{"action":"command","text":"go"}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 2)
  assertEq(r.data:find("No round set up", 1, true) ~= nil, true)
  assertEq(env.chatHas("No round set up"), true)
  env.call("cnr_panel", 2, '{"action":"command","text":"start Reinder"}')
  assertEq(env.lastSent("cnr_pickVehicle").pid, 2)
  env.cleanup()
end)

test("panel command outside the allowlist does nothing", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"set headStartSeconds 1"}')
  showConfig(env)
  assertEq(chatLine(env, "headStartSeconds = 7"), true)
  env.cleanup()
end)

test("panel settings save several values in one write", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9,"explodeOnCatch":true,"excludedModels":["citybus"]}}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 1)
  assertEq(r.data:find('"ok":true', 1, true) ~= nil, true)
  assertEq(env.chatHas("Saved"), false)
  showConfig(env)
  assertEq(chatLine(env, "headStartSeconds = 9"), true)
  assertEq(chatLine(env, "explodeOnCatch = true"), true)
  assertEq(chatLine(env, "excludedModels = citybus"), true)
  env.cleanup()
end)

test("empty excluded list saves", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"excludedModels":[]}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"ok":true', 1, true) ~= nil, true)
  showConfig(env)
  assertEq(chatLine(env, "excludedModels = "), true)
  env.cleanup()
end)

test("panel settings with one invalid value save nothing", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9,"catchHoldSeconds":0}}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.data:find('"ok":false', 1, true) ~= nil, true)
  assertEq(r.data:find("catchHoldSeconds", 1, true) ~= nil, true)
  showConfig(env)
  assertEq(chatLine(env, "headStartSeconds = 7"), true)
  env.cleanup()
end)

test("panel settings are refused during a round", function()
  local env = boot()
  env.startRound()
  env.call("cnr_panel", 1, '{"action":"settings","values":{"headStartSeconds":9}}')
  assertEq(env.lastSent("cnr_panelReply").data:find("Stop the round first", 1, true) ~= nil, true)
  env.panel(1, "stop")
  showConfig(env)
  assertEq(chatLine(env, "headStartSeconds = 7"), true)
  env.cleanup()
end)

test("disconnect drops the panel subscriber", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.call("onPlayerDisconnect", 1)
  local n = countSent(env, "cnr_panelState", 1)
  env.panel(2, "auto on")
  env.call("cnr_tick")
  assertEq(countSent(env, "cnr_panelState", 1), n)
  env.cleanup()
end)

test("malformed panel data is ignored", function()
  local env = boot()
  env.call("cnr_panel", 1, "not json")
  env.call("cnr_panel", 1, '{"nope":1}')
  env.call("cnr_panel", 1, '{"action":"settings","values":"x"}')
  assertEq(env.lastSent("cnr_panelReply").data:find("Nothing to save", 1, true) ~= nil, true)
  env.cleanup()
end)

local function capturingLogs(fn)
  local logs, realPrint = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  print = realPrint
  if not ok then error(err, 0) end
  return function(text)
    for _, l in ipairs(logs) do if l:find(text, 1, true) then return true end end
    return false
  end
end

test("settings replies echo the request id", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"settings","id":7,"values":{"headStartSeconds":9}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"id":7', 1, true) ~= nil, true)
  env.call("cnr_panel", 1, '{"action":"settings","id":8,"values":{"catchHoldSeconds":0}}')
  assertEq(env.lastSent("cnr_panelReply").data:find('"id":8', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a command the panel may not send gets a reply", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"set headStartSeconds 1"}')
  local r = env.lastSent("cnr_panelReply")
  assertEq(r.pid, 1)
  assertEq(r.data:find("Not available from the panel", 1, true) ~= nil, true)
  env.cleanup()
end)

test("panel start keeps the name's case in replies", function()
  local env = boot()
  env.call("cnr_panel", 1, '{"action":"command","text":"start Zed"}')
  assertEq(env.lastSent("cnr_panelReply").data:find("No player matching 'Zed'", 1, true) ~= nil, true)
  env.cleanup()
end)

test("a panel error does not stop the round tick", function()
  local env = boot()
  env.startRound()
  env.call("cnr_panel", 1, '{"action":"open"}')
  env.go()
  MP.GetPlayers = function() error("boom") end
  local logged = capturingLogs(function()
    for _ = 1, 20 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  end)
  assertEq(env.lastSent("cnr_runnerGo") ~= nil, true)
  assertEq(logged("panel update failed"), true)
  env.cleanup()
end)

test("auto off tells clients to drop the next round countdown", function()
  local env = boot()
  env.panel(1, "auto off")
  local s = env.lastSent("cnr_autoNext")
  assertEq(s ~= nil and s.pid, -1)
  env.cleanup()
end)

test("parts change log names the differing slots", function()
  local env = boot()
  env.startRound()
  local logged = capturingLogs(function()
    env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"engine":"v8","tires":"a"}}}')
    env.call("onVehicleEdited", 1, 0, '1-0:{"jbm":"pickup","vcf":{"parts":{"engine":"v12","tires":"a","wing":"big"}}}')
  end)
  assertEq(logged("slots: engine, wing"), true)
  env.cleanup()
end)

local function runningRound(env)
  env.startRound()
  env.go()
  for _ = 1, 44 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
end

test("a cop's sight report makes cops get live updates and the runner spotted", function()
  local env = boot()
  runningRound(env)
  env.sent = {}
  env.call("cnr_sight", 2, '{"seen":true}')
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  local live = env.lastSent("cnr_lastSeen")
  assertEq(live.pid, 2)
  assertEq(live.data:find('"live":true', 1, true) ~= nil, true)
  assertEq(live.data:find('"route":', 1, true) ~= nil, true)
  local spotted = env.lastSent("cnr_spotted")
  assertEq(spotted.pid, 1)
  assertEq(spotted.data:find('"spotted":true', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a sight report from the runner is ignored", function()
  local env = boot()
  runningRound(env)
  env.sent = {}
  env.call("cnr_sight", 1, '{"seen":true}')
  env.call("cnr_sight", 1, "not json")
  env.clock = env.clock + 0.25
  env.call("cnr_tick")
  assertEq(env.lastSent("cnr_lastSeen"), nil)
  assertEq(env.lastSent("cnr_spotted"), nil)
  env.cleanup()
end)

test("round setup tells clients the sight range", function()
  local env = boot()
  env.startRound()
  assertEq(env.lastSent("cnr_roundSetup").data:find('"sightMaxMeters":400', 1, true) ~= nil, true)
  env.cleanup()
end)

local function readFileAt(path)
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

test("an old leaderboard is moved aside and the board starts fresh", function()
  local env = boot({ leaderboard = '{"runs":[{"player":"Old","survivedSeconds":999,"map":"west_coast_usa","endedAt":1}]}' })
  assertEq(readFileAt(env.dir .. "data/leaderboard-1.6.json"):find("Old", 1, true) ~= nil, true)
  env.call("onChatMessage", 1, "Reinder", "/cnr top")
  assertEq(env.chatHas("Old"), false)
  env.cleanup()
end)

test("the board app gets state on open, after a run and on a filter change", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  local s = env.lastSent("cnr_boardState")
  assertEq(s.pid, 2)
  assertEq(s.data:find('"filter":"west_coast_usa"', 1, true) ~= nil, true)
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.sent = {}
  env.panel(1, "end")
  s = env.lastSent("cnr_boardState")
  assertEq(s.pid, 2)
  assertEq(s.data:find("Reinder", 1, true) ~= nil, true)
  env.call("cnr_board", 2, '{"action":"filter","map":"all"}')
  assertEq(env.lastSent("cnr_boardState").data:find('"filter":"all"', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a board subscriber who leaves gets no more pushes", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.call("onPlayerDisconnect", 2)
  env.sent = {}
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  assertEq(env.lastSent("cnr_boardState"), nil)
  env.cleanup()
end)

test("a recorded run stores cops by key with their sight time", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  local text = readFileAt(env.dir .. "data/leaderboard.json")
  assertEq(text:find('"format":2', 1, true) ~= nil, true)
  assertEq(text:find('"cops":["name:Bob"]', 1, true) ~= nil, true)
  assertEq(text:find('"copSightSeconds":%[0') ~= nil, true)
  assertEq(text:find('"copIds"', 1, true), nil)
  env.cleanup()
end)

test("if the old leaderboard can't be moved aside, it is never overwritten", function()
  local env = boot({ leaderboard = '{"runs":[{"player":"Old","survivedSeconds":999,"map":"west_coast_usa","endedAt":1}]}', renameFails = true })
  env.startRound(); env.go()
  for _ = 1, 60 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  env.panel(1, "end")
  assertEq(readFileAt(env.dir .. "data/leaderboard.json"):find("Old", 1, true) ~= nil, true)
  env.cleanup()
end)

test("an existing backup name is never reused", function()
  local env = boot({ leaderboard = '{"runs":[{"player":"Second","survivedSeconds":5,"map":"x","endedAt":1}]}',
    files = { ["data/leaderboard-1.6.json"] = "first backup" } })
  assertEq(readFileAt(env.dir .. "data/leaderboard-1.6.json"), "first backup")
  local found = false
  for name in io.popen('ls "' .. env.dir .. 'data"'):lines() do
    if name:match("^leaderboard%-1%.6%-%d+%.json$") then found = true end
  end
  assertEq(found, true)
  env.cleanup()
end)

test("changing a setting refreshes open leaderboards", function()
  local env = boot()
  env.call("cnr_board", 2, '{"action":"open"}')
  env.sent = {}
  env.call("cnr_panel", 1, '{"action":"settings","id":1,"values":{"assistMinSightPercent":40}}')
  assertEq(env.lastSent("cnr_boardState") ~= nil, true)
  env.cleanup()
end)

test("chat commands other than the five point to the panel", function()
  local env = boot()
  assertEq(env.call("onChatMessage", 1, "Reinder", "/cnr go"), 1)
  assertEq(env.chatHas("Use the Cops and Robbers Panel (Esc > UI Apps)"), true)
  env.chats = {}
  env.call("onChatMessage", 1, "Reinder", "/cnr start bob")
  assertEq(env.lastSent("cnr_pickVehicle"), nil)
  assertEq(env.chatHas("Use the Cops and Robbers Panel"), true)
  env.cleanup()
end)

test("chat keeps color, help, version, addstation and removestation", function()
  local env = boot()
  env.call("onChatMessage", 1, "Reinder", "/cnr color #ff0000")
  assertEq(env.chatHas("Your car color is now"), true)
  env.chats = {}
  env.call("onChatMessage", 1, "Reinder", "/cnr help")
  for _, c in ipairs(env.chats) do
    local text = c[2]
    for word in text:gmatch('"/cnr (%a+)') do
      assertEq(word == "color" or word == "addstation" or word == "removestation" or word == "help" or word == "version", true, text)
    end
  end
  assertEq(env.chatHas("Panel"), true)
  env.cleanup()
end)

test("key binding commands are gone", function()
  local env = boot()
  assertEq(env.events.cnr_command, nil)
  env.cleanup()
end)

test("the panel can reload config.json, but not during a round", function()
  local env = boot()
  env.panel(1, "reload")
  assertEq(env.lastSent("cnr_panelReply").data:find("Config reloaded", 1, true) ~= nil, true)
  env.startRound()
  env.panel(1, "reload")
  assertEq(env.lastSent("cnr_panelReply").data:find("Stop the round before reloading", 1, true) ~= nil, true)
  env.cleanup()
end)

test("no player-facing text tells people to type a removed command", function()
  local files = { "server/CopsAndRobbers/main.lua", "server/CopsAndRobbers/cnr/round.lua", "server/CopsAndRobbers/cnr/commands.lua",
    "client/lua/ge/extensions/copsAndRobbers.lua", "client/ui/modules/apps/CopsAndRobbersHud/app.vue" }
  for _, f in ipairs(files) do
    local text = assert(io.open(f)):read("*a")
    for _, removed in ipairs({ '"/cnr go"', '"/cnr start', '"/cnr auto', '"/cnr stop"', '"/cnr test', '"/cnr set', '"/cnr top', '"/cnr continue', '"/cnr reload', '"/cnr config' }) do
      assertEq(text:find(removed, 1, true), nil, f .. " " .. removed)
    end
  end
end)

test("a saved build is loaded at startup", function()
  local env = boot({ files = { ["data/build.json"] = '{"model":"pickup","name":"Gavril D-Series","parts":{"pickup_engine":"v8"},"vars":null,"step":3,"history":null}' } })
  assertEq(env.logHas("Build: Gavril D-Series · change 3"), true)
  env.cleanup()
end)

test("a broken build file is moved aside and there is no build", function()
  local env = boot({ files = { ["data/build.json"] = '{"model":' } })
  assertEq(env.logHas("no build"), true)
  assertEq(readFileAt(env.dir .. "data/build.json"), nil)
  env.cleanup()
end)
