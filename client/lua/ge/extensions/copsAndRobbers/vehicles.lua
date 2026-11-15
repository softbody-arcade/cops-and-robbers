local lightbar = require("copsAndRobbers/lightbar")

local M = {}

local ALLOWED_TYPES = { Car = true, Truck = true }

local function vehicleType(config)
  if config.Type then return config.Type end
  local model = core_vehicles.getModel(config.model_key)
  return model and model.model and model.model.Type
end

function M.pick(includeMods, excludedModels)
  local excluded = { unicycle = true }
  for _, m in ipairs(excludedModels or {}) do excluded[m] = true end
  local list = core_vehicles.getConfigList(true).configs or {}
  local candidates = {}
  for _, c in ipairs(list) do
    local official = c.Source == "BeamNG - Official"
    if (official or includeMods) and ALLOWED_TYPES[vehicleType(c)] and not excluded[c.model_key] then
      candidates[#candidates + 1] = c
    end
  end
  if #candidates == 0 then return nil end
  local c = candidates[math.random(#candidates)]
  local path = c.pcFilename or ("vehicles/" .. c.model_key .. "/" .. c.key .. ".pc")
  return c.model_key, (path:gsub("^/", ""))
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

function M.hasPart(model, id)
  if type(id) ~= "string" or id == "" then return true end
  local env = envFor(model)
  if not env then return true end
  return env.getPart(id) ~= nil
end

function M.currentSetup()
  local data = core_vehicle_manager and core_vehicle_manager.getPlayerVehicleData and core_vehicle_manager.getPlayerVehicleData()
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
  return { model = data.model or cfg.model, parts = clean, vars = deepcopy(type(cfg.vars) == "table" and cfg.vars or {}) }
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
