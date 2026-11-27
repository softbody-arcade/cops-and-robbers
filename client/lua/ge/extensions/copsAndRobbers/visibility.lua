local M = {}
local twilightWidth = 30 / 1440

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clamp(value, lower, upper)
  return math.max(lower, math.min(upper, value))
end

local function smoothstep(value)
  return value * value * (3 - 2 * value)
end

local function normalizedXY(vector)
  if not vector then return nil end
  local x, y = vector.x, vector.y
  if not finite(x) or not finite(y) then return nil end

  local scale = math.max(math.abs(x + 0.0), math.abs(y + 0.0))
  if scale == 0 then return nil end
  x, y = x / scale, y / scale
  local length = math.sqrt(x * x + y * y)
  if scale <= 0.001 / length then return nil end
  return x / length, y / length
end

function M.bearing(axis, delta)
  local axisX, axisY = normalizedXY(axis)
  local deltaX, deltaY = normalizedXY(delta)
  if not axisX or not deltaX then return nil end
  return clamp(axisX * deltaX + axisY * deltaY, -1, 1)
end

function M.daylight(time, sunrise, sunset)
  if not finite(time) or not finite(sunrise) or not finite(sunset) then return nil end
  time, sunrise, sunset = time % 1, sunrise % 1, sunset % 1
  if sunrise == sunset then return nil end

  local sinceSunrise = (time - sunrise) % 1
  local sinceSunset = (time - sunset) % 1
  local distance = math.min(sinceSunrise, 1 - sinceSunrise, sinceSunset, 1 - sinceSunset)
  if sinceSunrise >= (sunset - sunrise) % 1 then
    distance = -distance
  end
  return smoothstep(clamp((distance + twilightWidth) / (2 * twilightWidth), 0, 1))
end

function M.range(maxMeters, gazeCos, carForwardCos, daylight, lampsOn, streetStrength, rawFog, precipitationFactor)
  if not finite(maxMeters) or maxMeters <= 0 then return 0 end

  local gaze = finite(gazeCos) and clamp(gazeCos, -1, 1) or -1
  local directional = 2 ^ (gaze - 1)
  if finite(carForwardCos) then
    local rearAngle = math.deg(math.acos(-clamp(carForwardCos, -1, 1)))
    local mirror = 0.25 + 0.25 * smoothstep(clamp(1 - rearAngle / 30, 0, 1))
    directional = math.max(directional, mirror)
  end

  local day = finite(daylight) and clamp(daylight, 0, 1) or 0
  local street = finite(streetStrength) and clamp(streetStrength, 0, 1) or 0
  local night = 0.30 + (lampsOn == true and 0.25 or 0) + 0.20 * street
  local lighting = day + (1 - day) * night

  local fog = finite(rawFog) and clamp(rawFog, 0.0004, 0.015) or 0.015
  local fogFactor = 1 - 0.60 * ((fog - 0.0004) / 0.0146)
  local precipitation = finite(precipitationFactor) and clamp(precipitationFactor, 0.70, 1) or 0.70
  return maxMeters * directional * lighting * fogFactor * precipitation
end

return M
