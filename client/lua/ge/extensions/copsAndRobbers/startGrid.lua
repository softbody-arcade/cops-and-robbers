local roads = require("copsAndRobbers/roads")
local geo = require("copsAndRobbers/geo")

local M = { timeout = 5 }

local function point(p)
  return { x = p.x, y = p.y, z = p.z }
end

local function earthPoint(p)
  local lat, lon, h = geo.toGeo(p)
  if lat then return { lat = lat, lon = lon, h = h } end
end

local function encode(pos, dir, earth)
  if not pos then return false end
  dir = dir and dir.x * dir.x + dir.y * dir.y > 1e-6 and dir:normalized() or vec3(0, 1, 0)
  if earth then
    local at, toward = earthPoint(pos), earthPoint(pos + dir)
    if at and toward then return { geo = at, toward = toward } end
    return nil
  end
  return { pos = point(pos), dir = point(dir) }
end

local function earthReady()
  local api = geo.api()
  return api and not (api.rebasing and api.rebasing())
end

local function direction(p)
  if not p then return end
  if p.geo then
    if not earthReady() then return end
    local at, toward = geo.toGame(p.geo), geo.toGame(p.toward)
    if at and toward then return at, (toward - at):normalized() end
  else
    return vec3(p.pos.x, p.pos.y, p.pos.z), vec3(p.dir.x, p.dir.y, p.dir.z)
  end
end

function M.pose(p)
  local pos, dir = direction(p)
  if pos then return pos, quatFromDir(dir, vec3(0, 0, 1)) end
end

function M.plan(d, pos, heading)
  if d.geo and not earthReady() then return end
  local slots = {}
  if d.anchor ~= nil then
    slots[1] = d.anchor
    pos, heading = direction(d.anchor)
    if d.anchor and not pos then return end
  elseif pos then
    local road, _, dir = roads.nearestRoad(pos, heading, true)
    pos, heading = road or pos, dir or heading
    slots[1] = encode(pos, heading, d.geo)
    if not slots[1] then return end
    slots[1].offRoad = not road or nil
  else
    slots[1] = false
  end
  local find = d.count > 1 and pos and roads.copSpotFinder(pos, d.copSpawnMin, d.copSpawnMax, heading)
  for i = 2, d.count do
    local at, dir
    if find then at, dir = find(i - 1) end
    slots[i] = encode(at, dir, d.geo)
    if slots[i] == nil then return end
  end
  return slots
end

return M
