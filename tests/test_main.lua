local sent, chats, events, timers = {}, {}, {}, {}
local tmp = os.tmpname(); os.remove(tmp)
local dir = tmp .. "_cnr/"
os.execute("mkdir -p '" .. dir .. "' && cp server/CopsAndRobbers/config.json '" .. dir .. "'")

local function encode(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(x)) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local clock = 0
local positions = {}
local vehicles = {[1]={[0]="x"}, [2]={[0]="x"}}
_G.MP = {
  Settings = {Map = 4},
  Get = function() return "/levels/west_coast_usa/info.json" end,
  GetServerTimeMS = function() return clock * 1000 end,
  SendChatMessage = function(pid, msg) chats[#chats + 1] = {pid, msg} end,
  TriggerClientEvent = function(pid, ev, data) sent[#sent + 1] = {pid=pid, ev=ev, data=data} end,
  GetPlayers = function() return {[1]="Reinder", [2]="Bob"} end,
  GetPlayerName = function(pid) return ({"Reinder","Bob"})[pid] end,
  GetPlayerVehicles = function(pid) return vehicles[pid] end,
  GetPositionRaw = function(pid, vid)
    local p = positions[pid]
    if not p then return nil, "Vehicle not found" end
    return {pos={p,0,0}, vel={0,0,0}}, ""
  end,
  RegisterEvent = function(ev, fn) events[ev] = fn end,
  CreateEventTimer = function(ev, ms) timers[ev] = ms end,
}
_G.Util = {
  JsonEncode = encode,
  JsonDecode = function(s)
    if not s:match("^%s*{") then error("bad json") end
    local t = {}
    for k, v in s:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do t[k] = v end
    return t
  end,
  JsonPrettify = function(s) return s end,
}
_G.FS = {
  CreateDirectory = function(p) os.execute("mkdir -p '" .. p .. "'") end,
  Remove = function(p) os.remove(p) end,
  Rename = function(a, b) os.rename(a, b) end,
}

local src = assert(io.open("server/CopsAndRobbers/main.lua")):read("*a")
local chunk = assert(load(src, "@" .. dir .. "main.lua"))
chunk()

local function call(ev, ...) return _G[events[ev]](...) end
local function lastSent(ev) for i = #sent, 1, -1 do if sent[i].ev == ev then return sent[i] end end end
local function chatHas(text) for _, c in ipairs(chats) do if c[2]:find(text, 1, true) then return true end end return false end

test("main registers events and timer", function()
  assertEq(events.onChatMessage ~= nil, true)
  assertEq(events.cnr_vehiclePicked ~= nil, true)
  assertEq(timers.cnr_tick, 250)
end)

test("non-command chat passes through", function()
  assertEq(call("onChatMessage", 1, "Reinder", "hello"), 0)
end)

test("full round over main wiring", function()
  assertEq(call("onChatMessage", 2, "Bob", "/cnr start rein"), 1)
  assertEq(lastSent("cnr_pickVehicle").pid, 2)
  positions[1], positions[2] = 0, 5
  call("cnr_vehiclePicked", 2, '{"model":"pickup","config":"vehicles/pickup/base.pc"}')
  local setup = lastSent("cnr_roundSetup")
  assertEq(setup ~= nil, true)
  assertEq(setup.data:find('"runnerId":1', 1, true) ~= nil, true)
  assertEq(call("onVehicleSpawn", 1, 3, '1:Reinder:1-3:{"jbm":"etk800"}'), 1)
  assertEq(call("onVehicleEdited", 1, 0, '1:Reinder:1-0:{"jbm":"pickup"}'), 0)
  for i = 1, 70 do clock = clock + 0.25; call("cnr_tick") end
  assertEq(lastSent("cnr_release") ~= nil, true)
  assertEq(lastSent("cnr_roundEnd") ~= nil, true)
  assertEq(chatHas("Runner caught! Reinder survived"), true)
  assertEq(chatHas("1. Reinder"), true)
  local f = io.open(dir .. "data/leaderboard.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
end)

test("stop while idle replies", function()
  call("onChatMessage", 1, "Reinder", "/cnr stop")
  assertEq(chatHas("No round running"), true)
end)

test("addstation saves file", function()
  call("onChatMessage", 1, "Reinder", "/cnr addstation")
  assertEq(chatHas("Gas station added (1 on west_coast_usa)"), true)
  local f = io.open(dir .. "data/stations/west_coast_usa.json")
  assertEq(f ~= nil, true)
  if f then f:close() end
end)

os.execute("rm -rf '" .. dir .. "'")
