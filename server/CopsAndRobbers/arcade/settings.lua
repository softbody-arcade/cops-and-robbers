local store = require("arcade.store")

local M = {}

M.GLOBAL = {
  DEFAULTS = {
    includeModVehicles = false,
    excludedModels = {},
    autoNextRound = false,
    autoNextDelaySeconds = 15,
    timeOfDay = "random",
    nightChancePercent = 25,
    dayLength = "moderate",
    weather = "random",
    badWeatherChancePercent = 25,
    weatherDriving = true,
    weatherChanges = true,
    weatherChangeMinMinutes = 3,
    weatherChangeMaxMinutes = 8,
    lightningMinSeconds = 5,
    lightningMaxSeconds = 20,
    trafficPerPlayer = 0,
  },
  CHOICES = {
    timeOfDay = { sunrise = true, morning = true, noon = true, afternoon = true, sunset = true, night = true, random = true },
    weather = { clear = true, cloudy = true, rain = true, storm = true, fog = true, snow = true, thunderstorm = true, random = true },
    dayLength = { off = true, fast = true, moderate = true, slow = true, realtime = true },
  },
  TIMING_RANGES = {
    weatherChangeMinMinutes = "weatherChangeMaxMinutes",
    lightningMinSeconds = "lightningMaxSeconds",
  },
  POSITIVE = {},
  MAXIMA = { nightChancePercent = 100, badWeatherChancePercent = 100, trafficPerPlayer = 20 },
  WHOLE = { trafficPerPlayer = true },
  RETIRED_KEYS = { clockSpeed = true },
  RETIRED_VALUES = { timeOfDay = "map", weather = "map" },
}

function M.combine(global, game)
  local decl = { fix = game.fix }
  for _, field in ipairs({ "DEFAULTS", "CHOICES", "POSITIVE", "MAXIMA", "WHOLE", "TIMING_RANGES", "RETIRED_KEYS", "RETIRED_VALUES" }) do
    local combined = {}
    for key, value in pairs(global[field] or {}) do combined[key] = value end
    for key, value in pairs(game[field] or {}) do
      assert(combined[key] == nil, "Duplicate setting " .. key .. " in " .. field)
      combined[key] = value
    end
    decl[field] = combined
  end
  for minKey, maxKey in pairs(decl.TIMING_RANGES) do
    decl.WHOLE[minKey], decl.WHOLE[maxKey] = true, true
    decl.POSITIVE[minKey], decl.POSITIVE[maxKey] = true, true
  end
  for key, default in pairs(game.OVERRIDES or {}) do
    assert(global.DEFAULTS[key] ~= nil, "Cannot override unknown global setting " .. key)
    assert(type(default) == type(global.DEFAULTS[key]), "Invalid override type for " .. key)
    local choices = global.CHOICES and global.CHOICES[key]
    assert(not choices or choices[default], "Invalid override choice for " .. key)
    decl.DEFAULTS[key] = default
  end
  return decl
end

local function copyList(t)
  local c = {}
  for i, v in ipairs(t) do c[i] = v end
  return c
end

local function validList(v)
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n ~= #v then return false end
  for _, item in ipairs(v) do
    if type(item) ~= "string" then return false end
  end
  return true
end

local function validNumber(key, v, decl)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false end
  if decl.MAXIMA[key] and v > decl.MAXIMA[key] then return false end
  if decl.WHOLE[key] and v % 1 ~= 0 then return false end
  if decl.POSITIVE[key] then return v > 0 end
  return v >= 0
end

function M.merge(raw, decl)
  local cfg, warnings = {}, {}
  raw = type(raw) == "table" and raw or {}
  for key, default in pairs(decl.DEFAULTS) do
    local v = raw[key]
    if v == nil then
      cfg[key] = type(default) == "table" and copyList(default) or default
    elseif type(default) == "table" then
      if validList(v) then
        cfg[key] = copyList(v)
      else
        cfg[key] = copyList(default)
        warnings[#warnings + 1] = string.format("%s must be a list of names, using the default", key)
      end
    elseif type(default) == "string" then
      if type(v) == "string" and (not decl.CHOICES[key] or decl.CHOICES[key][v]) then
        cfg[key] = v
      else
        cfg[key] = default
        warnings[#warnings + 1] = string.format("%s has invalid value %s, using %s", key, tostring(v), default)
      end
    elseif type(default) == "boolean" then
      if type(v) == "boolean" then
        cfg[key] = v
      else
        cfg[key] = default
        warnings[#warnings + 1] = string.format("%s must be true or false, using %s", key, tostring(default))
      end
    elseif validNumber(key, v, decl) then
      cfg[key] = v
    else
      cfg[key] = default
      warnings[#warnings + 1] = string.format("%s has invalid value %s, using %s", key, tostring(v), tostring(default))
    end
  end
  local unknown = {}
  for key in pairs(raw) do
    if decl.DEFAULTS[key] == nil then unknown[#unknown + 1] = tostring(key) end
  end
  table.sort(unknown)
  for _, key in ipairs(unknown) do
    warnings[#warnings + 1] = string.format("unknown setting %s ignored", key)
  end
  if decl.fix then decl.fix(cfg, warnings) end
  for minKey, maxKey in pairs(decl.TIMING_RANGES) do
    if cfg[maxKey] < cfg[minKey] then
      warnings[#warnings + 1] = string.format("%s (%s) is below %s, using %s", maxKey, tostring(cfg[maxKey]), minKey, tostring(cfg[minKey]))
      cfg[maxKey] = cfg[minKey]
    end
  end
  return cfg, warnings
end

local function parseValue(default, text)
  if type(default) == "boolean" then
    local t = text:lower()
    if t == "true" or t == "on" or t == "yes" then return true end
    if t == "false" or t == "off" or t == "no" then return false end
    return nil
  elseif type(default) == "string" then
    return text
  elseif type(default) == "table" then
    local list = {}
    for item in text:gmatch("[^,%s]+") do list[#list + 1] = item end
    return list
  end
  return tonumber(text)
end

function M.setValue(raw, key, text, decl)
  local default = decl.DEFAULTS[key]
  if default == nil then return nil, "Unknown setting " .. tostring(key) end
  local value = parseValue(default, tostring(text or ""))
  local invalid = "Invalid value for " .. key .. ": " .. tostring(text)
  if value == nil then return nil, invalid end
  local updated = {}
  for k, v in pairs(raw or {}) do
    if not decl.RETIRED_KEYS[k] and decl.RETIRED_VALUES[k] ~= v then updated[k] = v end
  end
  updated[key] = value
  for minKey, maxKey in pairs(decl.TIMING_RANGES) do
    if key == minKey or key == maxKey then
      if not validNumber(key, value, decl) then return nil, invalid end
      local minV = updated[minKey]
      local maxV = updated[maxKey]
      if not validNumber(minKey, minV, decl) then minV = decl.DEFAULTS[minKey] end
      if not validNumber(maxKey, maxV, decl) then maxV = decl.DEFAULTS[maxKey] end
      if maxV < minV then updated[maxKey] = minV end
    end
  end
  local _, warnings = M.merge(updated, decl)
  for _, w in ipairs(warnings) do
    if w:find(key .. " ", 1, true) == 1 then return nil, invalid end
  end
  return updated
end

local function validListValue(v)
  if type(v) == "string" then return true end
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n ~= #v then return false end
  for _, item in ipairs(v) do
    if type(item) ~= "string" and type(item) ~= "number" then return false end
  end
  return true
end

local function toText(v)
  if type(v) == "number" then return string.format("%.10g", v) end
  if type(v) == "table" then
    local items = {}
    for _, item in ipairs(v) do items[#items + 1] = tostring(item) end
    return table.concat(items, ", ")
  end
  return tostring(v)
end

function M.applyValues(raw, values, decl)
  if type(values) ~= "table" then return nil, "Nothing to save" end
  local keys = {}
  for k in pairs(values) do
    if type(k) ~= "string" then return nil, "Nothing to save" end
    keys[#keys + 1] = k
  end
  if #keys == 0 then return nil, "Nothing to save" end
  table.sort(keys, function(a, b)
    local am, bm = decl.TIMING_RANGES[a] ~= nil, decl.TIMING_RANGES[b] ~= nil
    if am ~= bm then return am end
    return a < b
  end)
  for _, key in ipairs(keys) do
    if type(decl.DEFAULTS[key]) == "table" and not validListValue(values[key]) then
      return nil, "Invalid value for " .. key
    end
  end
  local updated, pending = raw or {}, keys
  while #pending > 0 do
    local failed, firstErr = {}, nil
    for _, key in ipairs(pending) do
      local nextCfg, err = M.setValue(updated, key, toText(values[key]), decl)
      if nextCfg then
        updated = nextCfg
      else
        failed[#failed + 1] = key
        firstErr = firstErr or err
      end
    end
    if #failed == #pending then return nil, firstErr end
    pending = failed
  end
  local _, warnings = M.merge(updated, decl)
  for _, w in ipairs(warnings) do
    for _, key in ipairs(keys) do
      if w:find(key .. " ", 1, true) == 1 then return nil, "Invalid value for " .. key .. ": " .. toText(values[key]) end
    end
  end
  return updated, keys
end

local function keepBrokenFile(path, bytes)
  local prefix = path .. ".corrupt-" .. os.date("%Y%m%d-%H%M%S")
  local dest, index = prefix, 1
  while FS.Exists(dest) do
    if store.read(dest) == bytes then return dest end
    index = index + 1
    dest = prefix .. "-" .. index
  end
  local ok, err = store.copy(path, dest)
  if not ok then return nil, err end
  return dest
end

function M.new(path, decl, log)
  local s = {}
  log = log or print

  function s:load()
    local raw, corrupt, bytes = store.decode(path)
    if corrupt or bytes == "" then
      local basename = path:match("[^/\\]+$")
      local warning = basename .. " is not valid JSON, using defaults; "
      local copy, err = keepBrokenFile(path, bytes)
      if copy then
        log(warning .. "kept a copy as " .. copy:match("[^/\\]+$"))
      else
        log(warning .. "could not keep a copy: " .. err)
      end
    end
    raw = raw or {}
    local cfg, warnings = M.merge(raw, decl)
    for _, w in ipairs(warnings) do log("config: " .. w) end
    return cfg, warnings, raw
  end

  function s:save(raw)
    store.write(path, Util.JsonPrettify(Util.JsonEncode(raw)))
  end

  return s
end

return M
