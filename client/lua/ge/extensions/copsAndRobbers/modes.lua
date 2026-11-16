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

local function withoutCouplers(data)
  if type(data) ~= "table" or type(data.controller) ~= "table" then return data end
  local controller = {}
  for k, v in pairs(data.controller) do
    if not (type(k) == "string" and k:find("_groupState$")) then controller[k] = v end
  end
  local out = {}
  for k, v in pairs(data) do out[k] = v end
  out.controller = next(controller) and controller or nil
  return out
end

function M.remember(state, model, data)
  data = withoutCouplers(data)
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
  data = withoutCouplers(data)
  if type(data) ~= "table" or (data.controller == nil and data.powertrain == nil) then return nil end
  return "local m = " .. literal(data) ..
    " if m.controller and controller.setState then controller.setState(m.controller) end" ..
    " if m.powertrain and powertrain and powertrain.setState then powertrain.setState(m.powertrain) end"
end

return M
