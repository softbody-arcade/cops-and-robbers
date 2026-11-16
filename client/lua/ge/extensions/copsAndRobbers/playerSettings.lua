local M = {}

M.FILE = "settings/cnr_settings.json"

local KEYS = { "headlights", "siren" }

function M.load(decoded)
  local prefs = {}
  for _, k in ipairs(KEYS) do
    prefs[k] = type(decoded) == "table" and decoded[k] == true
  end
  return prefs
end

function M.set(prefs, key, value)
  local known = false
  for _, k in ipairs(KEYS) do
    if k == key then known = true end
  end
  if not known or type(value) ~= "boolean" or prefs[key] == value then return false end
  prefs[key] = value
  return true
end

return M
