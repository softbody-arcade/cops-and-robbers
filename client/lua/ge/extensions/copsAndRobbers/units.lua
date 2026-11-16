local M = {}

function M.unit(value)
  return value == "imperial" and "imperial" or "metric"
end

function M.read()
  if type(settings) ~= "table" or type(settings.getValue) ~= "function" then return "metric" end
  local ok, value = pcall(settings.getValue, "uiUnitLength")
  return ok and M.unit(value) or "metric"
end

function M.distance(meters, unit)
  if unit == "imperial" then
    local feet = math.floor(meters * 3.28084 / 10 + 0.5) * 10
    if feet >= 1000 then return string.format("%.1f mi", meters / 1609.344) end
    return string.format("%d ft", feet)
  end
  local rounded = math.floor(meters + 0.5)
  if rounded >= 1000 then return string.format("%.1f km", meters / 1000) end
  return string.format("%d m", rounded)
end

return M
