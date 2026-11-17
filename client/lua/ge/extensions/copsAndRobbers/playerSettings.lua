local M = {}

M.FILE = "settings/cnr_settings.json"

local KEYS = { "headlights", "siren", "beam", "sound" }
local DEFAULTS = { headlights = true, siren = false, beam = true, sound = true, route = "sight" }
local CHOICES = { route = { always = true, sight = true, never = true } }

function M.load(decoded)
  local prefs = {}
  for _, k in ipairs(KEYS) do
    local v
    if type(decoded) == "table" then v = decoded[k] end
    if type(v) == "boolean" then prefs[k] = v else prefs[k] = DEFAULTS[k] end
  end
  for k, choices in pairs(CHOICES) do
    local v = type(decoded) == "table" and decoded[k]
    prefs[k] = type(v) == "string" and choices[v] and v or DEFAULTS[k]
  end
  return prefs
end

function M.set(prefs, key, value)
  local choices = CHOICES[key]
  if choices then
    if type(value) ~= "string" or not choices[value] or prefs[key] == value then return false end
    prefs[key] = value
    return true
  end
  local known = false
  for _, k in ipairs(KEYS) do
    if k == key then known = true end
  end
  if not known or type(value) ~= "boolean" or prefs[key] == value then return false end
  prefs[key] = value
  return true
end

return M
