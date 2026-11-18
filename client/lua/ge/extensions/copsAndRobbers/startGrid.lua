local roads = require("copsAndRobbers/roads")

local M = {}

local function point(p)
  return { x = p.x, y = p.y, z = p.z }
end

local function encode(pos, dir)
  if not pos then return false end
  dir = dir and dir.x * dir.x + dir.y * dir.y > 1e-6 and dir:normalized() or vec3(0, 1, 0)
  return { pos = point(pos), dir = point(dir) }
end

local function direction(p)
  if not p then return end
  return vec3(p.pos.x, p.pos.y, p.pos.z), vec3(p.dir.x, p.dir.y, p.dir.z)
end

function M.pose(p)
  local pos, dir = direction(p)
  if pos then return pos, quatFromDir(dir, vec3(0, 0, 1)) end
end

function M.plan(d, pos, heading)
  local slots = {}
  if d.anchor ~= nil then
    slots[1] = d.anchor
    pos, heading = direction(d.anchor)
  elseif pos then
    local road, _, dir = roads.nearestRoad(pos, heading, true)
    pos, heading = road or pos, dir or heading
    slots[1] = encode(pos, heading)
    slots[1].offRoad = not road or nil
  else
    slots[1] = false
  end
  local find = d.count > 1 and pos and roads.copSpotFinder(pos, d.copSpawnMin, d.copSpawnMax, heading)
  for i = 2, d.count do
    local at, dir
    if find then at, dir = find(i - 1) end
    slots[i] = encode(at, dir)
  end
  return slots
end

return M
