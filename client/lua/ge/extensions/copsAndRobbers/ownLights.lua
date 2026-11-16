local M = {}

M.HEADLIGHTS_ON = "if (electrics.values.lights_state or 0) == 0 then electrics.setLightsState(1) end"
M.HEADLIGHTS_OFF = "electrics.setLightsState(0)"

function M.new(enabled)
  return { enabled = enabled == true, dark = nil }
end

function M.step(state, enabled, dark, placed)
  local wasEnabled, wasDark = state.enabled, state.dark
  state.enabled, state.dark = enabled, dark
  if not enabled then return nil end
  if placed or not wasEnabled or wasDark == nil then return dark and "on" or nil end
  if wasDark == dark then return nil end
  return dark and "on" or "off"
end

function M.lightbarSignal(role, released, sirenOn, allowed)
  if role ~= "cop" then return nil end
  if released and sirenOn and allowed then return 2 end
  return 1
end

return M
