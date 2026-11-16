local M = {}

M.FILE = "/settings/cnr_vehicle_modes.json"

M.CAPTURE = table.concat({
  "local s = {controller = controller.getState and controller.getState() or nil,",
  " powertrain = powertrain and powertrain.getState and powertrain.getState() or nil}",
  " obj:queueGameEngineLua('if copsAndRobbers then copsAndRobbers.vehicleModes(' .. serialize(s) .. ') end')",
})

local function literal(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do
    if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and string.format("[%q]", k) or string.format("[%s]", tostring(k))
    parts[#parts + 1] = key .. "=" .. literal(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

M.literal = literal

function M.new(saved)
  saved = type(saved) == "table" and saved or {}
  return { byModel = type(saved.byModel) == "table" and saved.byModel or {}, last = type(saved.last) == "table" and saved.last or nil }
end

local SETTING_SUFFIXES = {
  "ConfigKey", "Mode", "_mode", "_modeIndex", "LevelIndex", "_settingIndex", "_hillAssistCoef", "_frontLockOutEnabled",
  "_enabled", "_rpm", "_manualIdleRaise", "_maximumSupplyPressure", "_pressureChangeRate", "_targetLength", "_adjustmentRate",
}
local SETTING_KEYS = { grb_bhv = true, grb_mde = true }

local function isSetting(key)
  if type(key) ~= "string" then return false end
  if SETTING_KEYS[key] or key:find("ompressionBrakeCoef$") then return true end
  for _, suffix in ipairs(SETTING_SUFFIXES) do
    if key:sub(-#suffix) == suffix then return true end
  end
  return false
end

local function settingsOf(part)
  if type(part) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(part) do
    if isSetting(k) then out[k] = v end
  end
  return next(out) and out or nil
end

local function settingsOnly(data)
  if type(data) ~= "table" then return data end
  return { controller = settingsOf(data.controller), powertrain = settingsOf(data.powertrain) }
end

function M.remember(state, model, data)
  data = settingsOnly(data)
  if type(data) ~= "table" or (data.controller == nil and data.powertrain == nil) then return false end
  local key = tostring(model)
  if state.byModel[key] and literal(state.byModel[key]) == literal(data) then return false end
  state.byModel[key] = data
  state.last = data
  return true
end

function M.forModel(state, model)
  return state.byModel[tostring(model)] or state.last
end

function M.restoreCommand(data)
  data = settingsOnly(data)
  if type(data) ~= "table" or (data.controller == nil and data.powertrain == nil) then return nil end
  return "local m = " .. literal(data) ..
    " if m.controller and controller.setState then controller.setState(m.controller) end" ..
    " if m.powertrain and powertrain and powertrain.setState then powertrain.setState(m.powertrain) end"
end

return M
