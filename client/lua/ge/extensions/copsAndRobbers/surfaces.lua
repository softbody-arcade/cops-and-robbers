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

M.STEP = 0.05
M.KINDS = { "dry", "rain", "storm", "snow" }

local saved = {}
local pushed = nil

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
  saved, pushed = {}, nil
end

function M.drop()
  saved, pushed = {}, nil
end

local function ruleFor(kind, name)
  local found
  for _, rule in ipairs(M.RULES[kind] or {}) do
    for _, target in ipairs(rule.targets) do
      if target == name then found = rule end
    end
  end
  return found
end

local function saveTargets(models)
  for _, rules in pairs(M.RULES) do
    for _, rule in ipairs(rules) do
      local source = rule.become and models[rule.become]
      if source then save(rule.become, source.cdata) end
      for _, name in ipairs(rule.targets) do
        if models[name] then save(name, models[name].cdata) end
      end
    end
  end
end

local function valueOf(kind, name, field)
  local dry = saved[name][field]
  local rule = kind ~= "dry" and ruleFor(kind, name)
  if not rule then return dry end
  if rule.become then
    local source = saved[rule.become]
    return source and source[field] or dry
  end
  if field == "staticFrictionCoefficient" then return dry * rule.static end
  if field == "slidingFrictionCoefficient" then return dry * rule.sliding end
  return dry
end

local function mustPush(weights)
  if not pushed then return true end
  local ones, differs = 0, false
  for _, kind in ipairs(M.KINDS) do
    local w = weights[kind] or 0
    if math.abs(w - pushed[kind]) >= M.STEP - 1e-9 then return true end
    if w >= 1 - 1e-9 then ones = ones + 1 end
    if w ~= pushed[kind] then differs = true end
  end
  return ones > 0 and differs
end

function M.blend(weights)
  if not weights then return end
  local models = core_environment.groundModels
  if not next(saved) then saveTargets(models) end
  if not mustPush(weights) then return end
  local names = {}
  for name in pairs(saved) do
    if ruleFor("rain", name) or ruleFor("storm", name) or ruleFor("snow", name) then names[#names + 1] = name end
  end
  table.sort(names)
  local snapshot = {}
  for _, kind in ipairs(M.KINDS) do snapshot[kind] = weights[kind] or 0 end
  for _, name in ipairs(names) do
    local model = models[name]
    if model then
      for _, field in ipairs(FIELDS) do
        local sum = 0
        for _, kind in ipairs(M.KINDS) do
          local w = snapshot[kind]
          if w ~= 0 then sum = sum + w * valueOf(kind, name, field) end
        end
        model.cdata[field] = sum
      end
      pushModels(name)
    end
  end
  pushed = snapshot
end

function M.apply(weather)
  if not M.RULES[weather] then
    M.restore()
    return
  end
  local weights = { dry = 0, rain = 0, storm = 0, snow = 0 }
  weights[weather] = 1
  M.blend(weights)
end

return M
