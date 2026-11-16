dofile("tests/env_stubs.lua")
local vecMeta = {}
vecMeta.__index = vecMeta
local function v3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vecMeta) end
vecMeta.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
vecMeta.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
vecMeta.__mul = function(a, b)
  if type(a) == "number" then a, b = b, a end
  return v3(a.x * b, a.y * b, a.z * b)
end
vecMeta.__div = function(a, b) return v3(a.x / b, a.y / b, a.z / b) end
function vecMeta:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function vecMeta:distance(o) return (self - o):length() end
function vecMeta:normalized()
  local l = self:length()
  return l > 0 and self / l or v3(0, 0, 0)
end

local function fakeVehicle(env, id, pos)
  local veh = { id = id, pos = pos or v3(0, 0, 0), commands = {} }
  function veh:getID() return self.id end
  function veh:getPosition() return self.pos end
  function veh:getVelocity() return v3(0, 0, 0) end
  function veh:getDirectionVector() return v3(0, 1, 0) end
  function veh:queueLuaCommand(cmd) self.commands[#self.commands + 1] = cmd end
  function veh:delete() env.objects[self.id] = nil end
  env.objects[id] = veh
  return veh
end

function bootClient(opts)
  opts = opts or {}
  local env = { actionFilter = {}, handlers = {}, sent = {}, triggers = {}, toasts = {}, objects = {}, replaced = {}, spawned = {}, nextId = 200, removedFiles = {} }
  for name in pairs(package.loaded) do
    if name:find("^copsAndRobbers") then package.loaded[name] = nil end
  end
  math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  _G.vec3 = v3
  _G.quatFromDir = function(dir, up) return { dir = dir, up = up } end
  _G.jsonEncode = function(t) return t end
  _G.jsonDecode = function(d)
    if type(d) == "table" then return d end
    if d == "{}" then return {} end
    return nil
  end
  env.reads = {}
  env.written = {}
  _G.jsonWriteFile = function(path, data) env.written[path] = deepcopy(data) return true end
  _G.jsonReadFile = function(path)
    env.reads[path] = (env.reads[path] or 0) + 1
    if opts.layouts and opts.layouts.disk[path] then return deepcopy(opts.layouts.disk[path]) end
    return (opts.files or {})[path]
  end
  _G.deepcopy = function(t)
    local function cp(x)
      if type(x) ~= "table" then return x end
      local c = {}
      for k, v in pairs(x) do c[k] = cp(v) end
      return c
    end
    return cp(t)
  end
  _G.guihooks = { trigger = function(name, data) env.triggers[#env.triggers + 1] = { name = name, data = data } end }
  _G.ui_message = function(msg) env.toasts[#env.toasts + 1] = msg end
  env.veh = fakeVehicle(env, 100, v3(0, 0, 0))
  _G.getPlayerVehicle = function() return env.veh end
  _G.getObjectByID = function(id) return env.objects[id] end
  env.mpVehicles = {}
  env.mpPlayers = {}
  _G.castRayStatic = function(origin, dir, len)
    if env.blockFrom and origin:distance(env.blockFrom) < 5 then return 1 end
    return env.blockAt or (len + 100)
  end
  _G.log = function() end
  _G.MPVehicleGE = {
    getVehicles = function() return env.mpVehicles end,
    getPlayers = function() return env.mpPlayers end,
    isOwn = function(id) return (env.veh and id == env.veh.id) or env.gameTraffic[id] ~= nil end,
    getVehicleByGameID = function(id) return { serverVehicleString = "1-" .. tostring(id) } end,
  }
  _G.MPConfig = { getPlayerServerID = function() return 1 end }
  _G.core_vehicles = {
    getModel = function() return { model = { Name = "Pickup", Brand = "Gavril", Type = "Car" }, configs = {} } end,
    replaceVehicle = function(model, opt) env.replaced[#env.replaced + 1] = { model = model, opt = opt } end,
    spawnNewVehicle = function(model, opt)
      env.nextId = env.nextId + 1
      local veh = fakeVehicle(env, env.nextId, opt and opt.pos)
      env.spawned[#env.spawned + 1] = { model = model, opt = opt, veh = veh }
      return veh
    end,
    getConfigList = function() return { configs = opts.configs or {
      { model_key = "pickup", key = "d15_4wd_A", Source = "BeamNG - Official", ["Config Type"] = "Factory", Name = "D15 4WD" },
      { model_key = "fullsize", key = "police", Source = "BeamNG - Official", ["Config Type"] = "Police", Name = "Police" },
    } } end,
  }
  _G.core_input_actionFilter = {
    getActionTemplates = function() return { competitive = {} } end,
    setGroup = function() end,
    addAction = function(_, group, blocked) env.actionFilter[group] = blocked end,
  }
  _G.core_input_bindings = { bindings = { { contents = { bindings = { { action = "reset_physics" } } } } } }
  local nodes = {
    a = { pos = v3(0, 60, 0), links = { b = true } },
    b = { pos = v3(0, 200, 0), links = { a = true } },
  }
  local link = { inNode = "a", outNode = "b", oneWay = false, gated = 0, len = 1 }
  local graph = { a = { b = link }, b = { a = link } }
  _G.map = {
    getMap = function() return { nodes = nodes } end,
    getGraphpath = function() return { graph = graph } end,
    findClosestRoad = function() return "a", "b" end,
  }
  _G.spawn = {
    safeTeleport = function(veh, pos) veh.pos = pos; env.teleported = (env.teleported or 0) + 1 end,
    teleportToLastRoad = function() end,
  }
  _G.createVehiclePaint = function(c) return c end
  env.liveConfig = { partsTree = { tree = true }, vars = { gear1 = 3.1 } }
  env.liveParts = { pickup_engine = "v8", pickup_paint_design = "stripes" }
  env.liveVars = nil
  local function vehicleData()
    local data = { model = "pickup", config = env.liveConfig }
    if env.liveVars then
      local variables = {}
      for name, v in pairs(env.liveVars) do variables[name] = { name = name, val = v.val, step = v.step, title = v.title } end
      data.vdata = { variables = variables }
    end
    return data
  end
  _G.core_vehicle_manager = { getPlayerVehicleData = vehicleData, getVehicleData = function(id) return id == env.veh.id and vehicleData() or nil end }
  env.edits = {}
  local function edit(name) return function() env.edits[#env.edits + 1] = name end end
  _G.core_vehicle_partmgmt = {
    partsTreeToPartsMap = function() return deepcopy(env.liveParts) end,
    setNewParts = edit("setNewParts"), setConfig = edit("setConfig"), setConfigOfVehicle = edit("setConfigOfVehicle"),
    setConfigPaints = edit("setConfigPaints"), setConfigVars = edit("setConfigVars"), setPartsConfig = edit("setPartsConfig"),
    setPartsTreeConfig = edit("setPartsTreeConfig"), resetConfig = edit("resetConfig"), reset = edit("reset"), loadLocal = edit("loadLocal"),
  }
  _G.core_vehicle_colors = { setVehicleColor = edit("setVehicleColor"), setVehiclePaint = edit("setVehiclePaint") }
  env.jbeamParts = opts.jbeamParts or { v8 = { information = { name = "4.5L V8" } }, v8_60 = { information = { name = "6.0L V8" } } }
  package.loaded["jbeam/io"] = {
    startLoading = function() return {} end,
    getAvailableSlotNameMap = function() return {} end,
    getPart = function(_, name) return env.jbeamParts[name] end,
    getCompatiblePartNamesForSlot = function() return {} end,
  }
  _G.extensions = { hook = function() end, load = function() end }
  _G.FS = {
    fileExists = function() return true end,
    removeFile = function(_, path) env.removedFiles[#env.removedFiles + 1] = path end,
    getFileOriginInfo = function(_, path) return { archivePath = (opts.origins or {})[path] } end,
  }
  _G.TriggerServerEvent = function(ev, data) env.sent[#env.sent + 1] = { ev = ev, data = data } end
  _G.AddEventHandler = function(ev, fn) env.handlers[ev] = fn end
  _G.getCurrentLevelIdentifier = function() return "west_coast_usa" end
  _G.ui_appLayouts = opts.layouts and opts.layouts.api or nil
  _G.beamngEarth_api = nil
  _G.freeroam_facilities, _G.freeroam_gasStations, _G.freeroam_bigMapMode = nil, nil, nil
  _G.core_groundMarkers = nil
  _G.resetGameplay = function() end

  function env.addObject(id, pos) return fakeVehicle(env, id, pos) end
  env.gameTraffic, env.trafficSpawns, env.trafficDeletes, env.pendingTraffic = {}, {}, 0, 0
  local function addTraffic(amount)
    for _ = 1, amount do
      env.nextId = env.nextId + 1
      fakeVehicle(env, env.nextId, v3(0, 50, 0))
      env.gameTraffic[env.nextId] = { isAi = true }
    end
  end
  function env.finishTraffic()
    addTraffic(env.pendingTraffic)
    env.pendingTraffic = 0
  end
  _G.gameplay_traffic = {
    spawnTraffic = function(amount, group)
      env.trafficSpawns[#env.trafficSpawns + 1] = { amount = amount, group = group }
      if env.deferTraffic then env.pendingTraffic = env.pendingTraffic + amount else addTraffic(amount) end
      return true
    end,
    deleteVehicles = function()
      env.trafficDeletes = env.trafficDeletes + 1
      for id in pairs(env.gameTraffic) do env.objects[id] = nil end
      env.gameTraffic = {}
    end,
    getTrafficData = function() return env.gameTraffic end,
    removeTraffic = function(id) env.gameTraffic[id] = nil end,
    setTrafficVars = function(v) env.trafficVars = v end,
  }
  _G.gameplay_traffic_trafficUtils = {
    createTrafficGroup = function(n)
      local group = {}
      for i = 1, n do
        group[i] = i % 2 == 1 and { model = "pickup", config = "d15_4wd_A" } or { model = "fullsize", config = "police" }
      end
      return group
    end,
  }
  env.sky = fakeEnvironment()
  env.M = assert(loadfile("client/lua/ge/extensions/copsAndRobbers.lua"))()
  function env.fire(ev, data) return env.handlers[ev](data) end
  function env.tick(seconds, step)
    step = step or 0.1
    for _ = 1, math.max(1, math.floor(seconds / step + 0.5)) do env.M.onUpdate(step) end
  end
  function env.lastTrigger(name)
    for i = #env.triggers, 1, -1 do
      if env.triggers[i].name == name then return env.triggers[i].data end
    end
  end
  function env.lastSent(ev)
    for i = #env.sent, 1, -1 do
      if env.sent[i].ev == ev then return env.sent[i].data end
    end
  end
  function env.hud() return env.lastTrigger("CnRHud") end
  env.M.onExtensionLoaded()
  return env
end
