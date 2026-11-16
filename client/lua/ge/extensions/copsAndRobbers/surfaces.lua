local M = {}

local FIELDS = {
  "staticFrictionCoefficient", "slidingFrictionCoefficient", "hydrodynamicFriction", "stribeckVelocity",
  "roughnessCoefficient", "defaultDepth", "strength", "fluidDensity", "flowConsistencyIndex",
  "flowBehaviorIndex", "dragAnisotropy", "shearStrength",
}

local PAVED = { "ASPHALT", "ASPHALT_OLD", "ASPHALT_PREPPED", "COBBLESTONE" }
local DIRT = { "DIRT", "DIRT_DUSTY", "DIRT_DUSTY_LOOSE" }

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, name in ipairs(list) do out[#out + 1] = name end
  end
  return out
end

local RUMBLE_STEP = { targets = { "RUMBLE_STRIP" }, static = 0.94, sliding = 0.79 }
local SNOW_RULE = {
  targets = join(PAVED, { "RUMBLE_STRIP", "GRAVEL" }, DIRT, { "GRASS", "GRAVEL_WET", "MUD" }),
  become = "SNOW",
}

M.RULES = {
  rain = {
    { targets = PAVED, become = "ASPHALT_WET" },
    RUMBLE_STEP,
    { targets = { "GRAVEL" }, become = "GRAVEL_WET" },
    { targets = DIRT, become = "GRAVEL_WET" },
    { targets = { "GRASS" }, static = 0.85, sliding = 0.85 },
  },
  storm = {
    { targets = PAVED, become = "ASPHALT_WET" },
    RUMBLE_STEP,
    { targets = { "GRAVEL" }, become = "GRAVEL_WET" },
    { targets = DIRT, become = "MUD" },
    { targets = { "GRASS" }, static = 0.75, sliding = 0.75 },
  },
  snow = { SNOW_RULE },
}

local saved = {}

local function pushModels(name)
  local models = core_environment.groundModels
  be:setGroundModel(name, models[name].cdata)
  for alias, model in pairs(models) do
    if model.isAlias and model.parent == name then
      be:setGroundModel(alias, model.cdata)
    end
  end
end

local function save(name, cdata)
  if saved[name] then return end
  local values = {}
  for _, field in ipairs(FIELDS) do values[field] = cdata[field] end
  saved[name] = values
end

function M.restore()
  local models = core_environment.groundModels
  for name, values in pairs(saved) do
    local model = models[name]
    if model then
      for _, field in ipairs(FIELDS) do model.cdata[field] = values[field] end
      pushModels(name)
    end
  end
  saved = {}
end

function M.drop()
  saved = {}
end

function M.apply(weather)
  M.restore()
  local rules = M.RULES[weather]
  if not rules then return end
  local models = core_environment.groundModels
  for _, rule in ipairs(rules) do
    local source = rule.become and models[rule.become]
    if not rule.become or source then
      local copy = {}
      if source then
        for _, field in ipairs(FIELDS) do copy[field] = source.cdata[field] end
      end
      for _, name in ipairs(rule.targets) do
        local model = models[name]
        if model then
          local cdata = model.cdata
          save(name, cdata)
          if source then
            for _, field in ipairs(FIELDS) do cdata[field] = copy[field] end
          else
            cdata.staticFrictionCoefficient = cdata.staticFrictionCoefficient * rule.static
            cdata.slidingFrictionCoefficient = cdata.slidingFrictionCoefficient * rule.sliding
          end
          pushModels(name)
        end
      end
    end
  end
end

return M
