local lightbar = require("copsAndRobbers/lightbar")
local game = require("copsAndRobbers/game")

local M = {}

local ALLOWED_TYPES = { Car = true, Truck = true }

local function vehicleType(config)
  if config.Type then return config.Type end
  local model = core_vehicles.getModel(config.model_key)
  return model and model.model and model.model.Type
end

local function serverProvided(c)
  if c.Source == "BeamNG - Official" then return true end
  if type(c.pcFilename) ~= "string" or not FS or not FS.getFileOriginInfo then return false end
  local ok, origin = pcall(FS.getFileOriginInfo, FS, c.pcFilename)
  local archive = ok and type(origin) == "table" and origin.archivePath
  return type(archive) == "string" and archive:find("/mods/multiplayer/", 1, true) ~= nil
end

local function allowed(c, includeMods, excluded)
  return type(c.pcFilename) == "string" and ALLOWED_TYPES[vehicleType(c)] and not excluded[c.model_key]
    and (c.Source == "BeamNG - Official" or (includeMods and serverProvided(c)))
end

local function excludedSet(models)
  local excluded = { unicycle = true }
  for _, m in ipairs(type(models) == "table" and models or {}) do excluded[m] = true end
  return excluded
end

function M.pick(includeMods, excludedModels)
  local excluded = excludedSet(excludedModels)
  local byModel, keys = {}, {}
  for _, c in ipairs(core_vehicles.getConfigList(true).configs or {}) do
    if allowed(c, includeMods, excluded) then
      if not byModel[c.model_key] then
        byModel[c.model_key] = {}
        keys[#keys + 1] = c.model_key
      end
      local group = byModel[c.model_key]
      group[#group + 1] = c
    end
  end
  if #keys == 0 then return nil end
  table.sort(keys)
  local model = keys[math.random(#keys)]
  local group = byModel[model]
  local c = group[math.random(#group)]
  return model, (c.pcFilename:gsub("^/", ""))
end

function M.configList(opts)
  opts = type(opts) == "table" and opts or {}
  local excluded = excludedSet(opts.excludedModels)
  local list = {}
  for _, c in ipairs(core_vehicles.getConfigList(true).configs or {}) do
    if allowed(c, opts.includeMods, excluded) then
      list[#list + 1] = {
        model = c.model_key, config = (c.pcFilename:gsub("^/", "")),
        label = game.carName(c.model_key) .. " – " .. tostring(c.Configuration or c.Name or c.key),
      }
    end
  end
  table.sort(list, function(a, b) return a.label < b.label end)
  return list
end

function M.buildFrom(path)
  if type(path) ~= "string" then return nil end
  local ok, pc = pcall(jsonReadFile, "/" .. path:gsub("^/", ""))
  if not ok or type(pc) ~= "table" or pc.format ~= 2 or type(pc.parts) ~= "table" then return nil end
  local model = type(pc.model) == "string" and pc.model or path:match("^/?vehicles/([^/]+)/")
  if not model then return nil end
  return { model = model, name = game.carName(model), parts = pc.parts, vars = type(pc.vars) == "table" and pc.vars or {} }
end

function M.options(config, color)
  local opt = { config = config }
  if color and color.r then
    opt.paint = createVehiclePaint({ x = color.r, y = color.g, z = color.b, w = 1 })
  end
  return opt
end

local function jbeamEnv(model)
  local okIo, jbeamIO = pcall(require, "jbeam/io")
  if not okIo or type(jbeamIO) ~= "table" then return nil end
  local okCtx, ioCtx = pcall(jbeamIO.startLoading, { "/vehicles/" .. model .. "/", "/vehicles/common/" })
  if not okCtx or type(ioCtx) ~= "table" then return nil end
  local okMap, slotMap = pcall(jbeamIO.getAvailableSlotNameMap, ioCtx)
  if not okMap or type(slotMap) ~= "table" then return nil end
  local partsCache = {}
  return {
    getPart = function(name)
      if partsCache[name] == nil then
        local ok, part = pcall(jbeamIO.getPart, ioCtx, name)
        partsCache[name] = ok and type(part) == "table" and part or false
      end
      return partsCache[name] or nil
    end,
    compatible = function(slot)
      local ok, names = pcall(jbeamIO.getCompatiblePartNamesForSlot, ioCtx, slot, slotMap)
      return ok and type(names) == "table" and names or {}
    end,
  }
end

local envs = {}

local function envFor(model)
  if envs[model] == nil then envs[model] = jbeamEnv(model) or false end
  return envs[model] or nil
end

function M.partName(model, id)
  if type(id) ~= "string" or id == "" then return "(none)" end
  local env = envFor(model)
  local part = env and env.getPart(id)
  local info = type(part) == "table" and part.information
  return type(info) == "table" and type(info.name) == "string" and info.name or id
end

function M.slotsOf(model, id)
  if type(id) ~= "string" or id == "" then return nil end
  local env = envFor(model)
  local part = env and env.getPart(id)
  if type(part) ~= "table" or type(part.slots2) ~= "table" then return nil end
  local map = {}
  for _, s in ipairs(part.slots2) do
    if type(s) == "table" and type(s.name) == "string" then map[s.name] = type(s.description) == "string" and s.description or "" end
  end
  return map
end

local slotLabels = {}

function M.slotLabel(model, slot, parts)
  local key = tostring(model) .. "/" .. tostring(slot)
  if slotLabels[key] ~= nil then return slotLabels[key] or nil end
  local found = false
  local function look(id)
    local map = M.slotsOf(model, id)
    local desc = map and map[slot]
    if type(desc) == "string" and desc ~= "" then found = desc return true end
  end
  if not look(model) then
    for _, id in pairs(type(parts) == "table" and parts or {}) do
      if look(id) then break end
    end
  end
  slotLabels[key] = found
  return found or nil
end

function M.hasPart(model, id)
  if type(id) ~= "string" or id == "" then return true end
  local env = envFor(model)
  if not env then return true end
  return env.getPart(id) ~= nil
end

function M.currentSetup()
  local own = game.ownVehicle()
  if not own or not core_vehicle_manager then return nil end
  local data = core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(own:getID())
  local cfg = type(data) == "table" and data.config
  if type(cfg) ~= "table" then return nil end
  local parts = cfg.parts
  if type(parts) ~= "table" and cfg.partsTree and core_vehicle_partmgmt and core_vehicle_partmgmt.partsTreeToPartsMap then
    parts = core_vehicle_partmgmt.partsTreeToPartsMap(cfg.partsTree)
  end
  if type(parts) ~= "table" then return nil end
  local clean = {}
  for slot, part in pairs(parts) do
    if type(slot) == "string" and not slot:find("paint_design", 1, true) then clean[slot] = type(part) == "string" and part or "" end
  end
  local vars, steps, titles = {}, {}, {}
  local variables = type(data.vdata) == "table" and data.vdata.variables
  if type(variables) == "table" then
    for name, v in pairs(variables) do
      if type(v) == "table" and v.val ~= nil then
        vars[name] = v.val
        steps[name] = tonumber(v.step) or tonumber(v.stepDis)
        titles[name] = type(v.title) == "string" and v.title ~= "" and v.title or nil
      end
    end
  else
    vars = deepcopy(type(cfg.vars) == "table" and cfg.vars or {})
  end
  return { model = data.model or cfg.model, parts = clean, vars = vars, steps = steps, titles = titles }
end

function M.copConfig(model, configPath)
  local base
  if type(configPath) == "table" then
    base = configPath
  elseif type(configPath) == "string" then
    local ok, read = pcall(jsonReadFile, "/" .. configPath:gsub("^/", ""))
    base = ok and read or nil
  end
  if type(base) ~= "table" or type(base.parts) ~= "table" or base.format == 4 then return configPath end
  local env = envFor(model)
  if not env then return configPath end
  local okPlan, additions = pcall(lightbar.plan, base.mainPartName or model, base.parts, env)
  if not okPlan or not additions then return configPath end
  local cfg = deepcopy(base)
  for slot, part in pairs(additions) do cfg.parts[slot] = part end
  return cfg
end

return M
