local game = require("copsAndRobbers/game")

local M = {}

local PLACES_INTERVAL = 60
local PLACES_MOVE_METERS = 1000
local PLACES_RADIUS = 3000
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local lastPlacesAt, lastPlacesGeo = -math.huge, nil
local gpsTarget

function M.api()
  local api = rawget(_G, "beamngEarth_api")
  if api and api.version and api.version() == 1 then return api end
  return nil
end

function M.toGame(g)
  local api = M.api()
  if not api or type(g) ~= "table" or not g.lat or not g.lon then return nil end
  local x, y, z = api.toGame(g.lat, g.lon, g.h or 0)
  if not x then return nil end
  return vec3(x, y, z)
end

function M.toGeo(pos)
  local api = M.api()
  if not api or not pos then return nil end
  local lat, lon, h = api.toGeo(pos.x, pos.y, pos.z)
  if not lat then return nil end
  return lat, lon, h
end

function M.compass(from, to)
  local angle = math.deg(math.atan2(to.x - from.x, to.y - from.y)) % 360
  return COMPASS[math.floor((angle + 22.5) / 45) % 8 + 1]
end

function M.clearRoute()
  if core_groundMarkers then pcall(core_groundMarkers.setPath, nil) end
  if gpsTarget then
    local api = M.api()
    if api and api.gpsClear then pcall(api.gpsClear) end
    gpsTarget = nil
  end
end

function M.hasTarget()
  return gpsTarget ~= nil
end

function M.setGpsTarget(g)
  local api = M.api()
  if not (api and api.has and api.has("gps") and type(g) == "table") then return false end
  if not pcall(api.gpsSet, g.lat, g.lon, "Runner last seen") then return false end
  gpsTarget = { lat = g.lat, lon = g.lon, h = g.h }
  return true
end

function M.gpsInfo()
  if not gpsTarget then return nil end
  local api = M.api()
  local veh = game.ownVehicle()
  local here = veh and veh:getPosition()
  local target = M.toGame(gpsTarget)
  local dir = (here and target) and (" " .. M.compass(here, target)) or ""
  local ok, g = pcall(function() return api and api.gps and api.gps() end)
  if ok and type(g) == "table" and type(g.remaining) == "number" and not g.planning then
    return { before = "Runner", meters = g.remaining, after = "by road" .. dir }
  end
  if here and target then return { before = "Runner", meters = here:distance(target), after = dir ~= "" and dir:sub(2) or nil } end
  return nil
end

function M.sendGeo(aiObjects)
  local api = M.api()
  if not api or (api.rebasing and api.rebasing()) then return end
  local cars = {}
  local function add(obj, id)
    local lat, lon, h = M.toGeo(obj:getPosition())
    if not lat then return end
    local v = obj:getVelocity()
    cars[#cars + 1] = { id = id, lat = lat, lon = lon, h = h, ve = v.x, vn = v.y, vu = v.z }
  end
  local veh = game.ownVehicle()
  if veh then add(veh, nil) end
  for _, entry in ipairs(aiObjects or {}) do add(entry.obj, entry.id) end
  if #cars > 0 then game.sendServer("cnr_geo", { cars = cars }) end
end

local function geoDistance(a, b)
  local dLat = (a.lat - b.lat) * 111320
  local dLon = (a.lon - b.lon) * 111320 * math.cos(math.rad(a.lat))
  return math.sqrt(dLat * dLat + dLon * dLon)
end

function M.resetPlaces()
  lastPlacesAt, lastPlacesGeo = -math.huge, nil
end

function M.lookupStations(clock)
  local api = M.api()
  if not api or not api.has or not api.has("places") then return end
  local veh = game.ownVehicle()
  local lat, lon = M.toGeo(veh and veh:getPosition())
  if not lat then return end
  local here = { lat = lat, lon = lon }
  if lastPlacesGeo and clock - lastPlacesAt < PLACES_INTERVAL and geoDistance(here, lastPlacesGeo) < PLACES_MOVE_METERS then return end
  lastPlacesAt, lastPlacesGeo = clock, here
  local level = getCurrentLevelIdentifier()
  api.places(lat, lon, { radius = PLACES_RADIUS, categories = { "gas_station" } }, function(r)
    if type(r) ~= "table" or type(r.places) ~= "table" then return end
    local list = {}
    for _, p in ipairs(r.places) do
      if p.lat and p.lon and p.open ~= "permanently_closed" then
        list[#list + 1] = { lat = p.lat, lon = p.lon, name = p.name }
      end
    end
    if #list > 0 then game.sendServer("cnr_stations", { map = level, geo = true, stations = list }) end
  end)
end

return M
