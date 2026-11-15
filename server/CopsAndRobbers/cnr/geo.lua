local M = {}

local A = 6378137.0
local F = 1 / 298.257223563
local E2 = F * (2 - F)

local function ecef(latDeg, lonDeg, h)
  local lat, lon = math.rad(latDeg), math.rad(lonDeg)
  local sinLat, cosLat = math.sin(lat), math.cos(lat)
  local n = A / math.sqrt(1 - E2 * sinLat * sinLat)
  return (n + h) * cosLat * math.cos(lon), (n + h) * cosLat * math.sin(lon), (n * (1 - E2) + h) * sinLat
end

function M.valid(lat, lon)
  return type(lat) == "number" and type(lon) == "number" and lat == lat and lon == lon
    and math.abs(lat) <= 90 and math.abs(lon) <= 180
end

function M.newRef(latDeg, lonDeg)
  local lat, lon = math.rad(latDeg), math.rad(lonDeg)
  local x, y, z = ecef(latDeg, lonDeg, 0)
  return {
    x = x, y = y, z = z,
    sinLat = math.sin(lat), cosLat = math.cos(lat), sinLon = math.sin(lon), cosLon = math.cos(lon),
  }
end

function M.toLocal(ref, latDeg, lonDeg, h)
  local x, y, z = ecef(latDeg, lonDeg, h or 0)
  local dx, dy, dz = x - ref.x, y - ref.y, z - ref.z
  local e = -ref.sinLon * dx + ref.cosLon * dy
  local n = -ref.sinLat * ref.cosLon * dx - ref.sinLat * ref.sinLon * dy + ref.cosLat * dz
  local u = ref.cosLat * ref.cosLon * dx + ref.cosLat * ref.sinLon * dy + ref.sinLat * dz
  return { x = e, y = n, z = u }
end

return M
