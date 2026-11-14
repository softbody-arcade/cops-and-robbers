local function encode(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(x)) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local function boot(opts)
  opts = opts or {}
  local env = { sent = {}, chats = {}, events = {}, timers = {}, removed = {}, logs = {}, clock = 0, positions = {} }
  local tmp = os.tmpname(); os.remove(tmp)
  env.dir = tmp .. "_cnr/"
  os.execute("mkdir -p '" .. env.dir .. "'")
  local f = assert(io.open(env.dir .. "config.json", "w"))
  f:write(opts.config or assert(io.open("server/CopsAndRobbers/config.json")):read("*a"))
  f:close()
  env.vehicles = opts.vehicles or { [1] = { [0] = "x" }, [2] = { [0] = "x" } }

  _G.MP = {
    Settings = { Map = 4 },
    Get = function() return "/levels/west_coast_usa/info.json" end,
    CreateTimer = function()
      return { GetCurrent = function() return env.clock end, Start = function() end }
    end,
    SendChatMessage = function(pid, msg) env.chats[#env.chats + 1] = { pid, msg } end,
    TriggerClientEvent = function(pid, ev, data) env.sent[#env.sent + 1] = { pid = pid, ev = ev, data = data } end,
    GetPlayers = function() return { [1] = "Reinder", [2] = "Bob" } end,
    GetPlayerName = function(pid) return ({ "Reinder", "Bob" })[pid] end,
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
    JsonDecode = function(s)
      if not s:match("^%s*[{%[]") or s:find(",%s*}") then error("bad json") end
      local t = {}
      for k, v in s:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do t[k] = v end
      for k, v in s:gmatch('"([%w_]+)"%s*:%s*(%-?[%d%.]+)') do t[k] = tonumber(v) end
      return t
    end,
    JsonPrettify = function(s) return s end,
  }
  _G.FS = {
    CreateDirectory = function(p) os.execute("mkdir -p '" .. p .. "'") end,
    Remove = function(p) os.remove(p) end,
    Rename = function(a, b) os.rename(a, b) end,
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
    env.call("onChatMessage", 2, "Bob", "/cnr start rein")
    env.positions[1], env.positions[2] = 0, 5
    env.call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  end
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
  env.call("onChatMessage", 1, "Reinder", "/cnr config")
  assertEq(env.chatHas("headStartSeconds = 3"), true)
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
  for _ = 1, 70 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  assertEq(env.lastSent("cnr_release") ~= nil, true)
  assertEq(env.chatHas("Runner caught! Reinder survived"), true)
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
  env.clock = 10
  env.call("onVehicleReset", 1, 0, "")
  assertEq(env.chatHas("reset illegally"), false)
  env.call("onVehicleReset", 1, 1, "")
  assertEq(env.chatHas("Reinder reset illegally"), true)
  env.cleanup()
end)

test("stop while idle replies and still unlocks clients", function()
  local env = boot()
  env.sent = {}
  env.call("onChatMessage", 1, "Reinder", "/cnr stop")
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
