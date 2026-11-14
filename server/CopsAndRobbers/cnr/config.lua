local M = {}

M.DEFAULTS = {
  headStartSeconds = 7,
  runnerCountdownSeconds = 3,
  resetWaitSeconds = 7,
  catchHoldSeconds = 7,
  catchRadiusMeters = 10,
  catchMaxSpeedKmh = 3,
  stillMaxSpeedKmh = 1,
  copResetMinDistanceMeters = 1000,
  gasStationRadiusMeters = 25,
  copSpawnMinMeters = 50,
  copSpawnMaxMeters = 150,
  explodeOnCatch = false,
  includeModVehicles = false,
  crashSpeedLossKmh = 50,
  crashPenaltySeconds = 10,
}

local strictlyPositive = { catchHoldSeconds = true, catchRadiusMeters = true, crashSpeedLossKmh = true }

local function validNumber(key, v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false end
  if strictlyPositive[key] then return v > 0 end
  return v >= 0
end

function M.merge(raw)
  local cfg, warnings = {}, {}
  raw = type(raw) == "table" and raw or {}
  for key, default in pairs(M.DEFAULTS) do
    local v = raw[key]
    if v == nil then
      cfg[key] = default
    elseif type(default) == "boolean" then
      if type(v) == "boolean" then
        cfg[key] = v
      else
        cfg[key] = default
        warnings[#warnings + 1] = string.format("%s must be true or false, using %s", key, tostring(default))
      end
    elseif validNumber(key, v) then
      cfg[key] = v
    else
      cfg[key] = default
      warnings[#warnings + 1] = string.format("%s has invalid value %s, using %s", key, tostring(v), tostring(default))
    end
  end
  local unknown = {}
  for key in pairs(raw) do
    if M.DEFAULTS[key] == nil then unknown[#unknown + 1] = tostring(key) end
  end
  table.sort(unknown)
  for _, key in ipairs(unknown) do
    warnings[#warnings + 1] = string.format("unknown setting %s ignored", key)
  end
  if cfg.copSpawnMaxMeters < cfg.copSpawnMinMeters then
    warnings[#warnings + 1] = string.format("copSpawnMaxMeters (%s) is below copSpawnMinMeters, using %s", tostring(cfg.copSpawnMaxMeters), tostring(cfg.copSpawnMinMeters))
    cfg.copSpawnMaxMeters = cfg.copSpawnMinMeters
  end
  return cfg, warnings
end

return M
