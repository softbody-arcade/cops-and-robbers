local M = {}

local COP_SPACING = 8
local LINK_STEP = 15
local MAX_SPAWN_RING = 2000
local ROAD_SEARCH_MAX = 2000

local function graph()
  local gp = map.getGraphpath and map.getGraphpath()
  local nodes = map.getMap().nodes
  if not gp or not gp.graph or not nodes then return nil end
  return gp.graph, nodes
end

local function canDrive(link, x)
  return not link.oneWay or link.inNode == x
end

local function dot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

local function lineSpots(center, minD, maxD)
  local links, nodes = graph()
  local candidates = {}
  if not links then return candidates end
  for id, neighbours in pairs(links) do
    for linkId, link in pairs(neighbours) do
      local n, other = nodes[id], nodes[linkId]
      if n and other and tostring(id) < tostring(linkId) then
        local delta = other.pos - n.pos
        local len = delta:length()
        if len > 1e-3 then
          local dir = delta / len
          local steps = math.max(1, math.floor(len / LINK_STEP))
          for i = 0, steps do
            local pos = n.pos + dir * (len * i / steps)
            local d = pos:distance(center)
            if d >= minD and d <= maxD then
              local facing = dir
              if link.oneWay then
                facing = link.inNode == id and dir or dir * -1
              elseif dot(dir, center - pos) < 0 then
                facing = dir * -1
              end
              candidates[#candidates + 1] = { pos = pos, d = d, dir = facing }
            end
          end
        end
      end
    end
  end
  table.sort(candidates, function(a, b) return a.d < b.d end)
  return candidates
end

local function pickSpot(candidates, index)
  local chosen = {}
  for _, c in ipairs(candidates) do
    local free = true
    for _, prev in ipairs(chosen) do
      if prev.pos:distance(c.pos) < COP_SPACING then free = false break end
    end
    if free then
      chosen[#chosen + 1] = c
      if #chosen == index then return c end
    end
  end
  return nil
end

function M.findCopSpot(center, minD, maxD, index)
  local lo, hi = minD, maxD
  while true do
    local spot = pickSpot(lineSpots(center, lo, hi), index)
    if spot then return spot.pos, quatFromDir(spot.dir, vec3(0, 0, 1)) end
    if hi >= MAX_SPAWN_RING then return nil end
    lo, hi = 0, hi * 2
  end
end

local function closestNodeFallback(pos)
  local links, nodes = graph()
  if not links then return nil end
  local best, bestDist, bestLink
  for id, neighbours in pairs(links) do
    local n = nodes[id]
    local d = n and n.pos:distance(pos)
    if d and d <= ROAD_SEARCH_MAX and (not bestDist or d < bestDist) then
      for linkId in pairs(neighbours) do
        if nodes[linkId] then best, bestDist, bestLink = id, d, linkId break end
      end
    end
  end
  return best, bestLink
end

function M.nearestRoad(pos)
  local n1, n2 = map.findClosestRoad(pos)
  if not n1 then n1, n2 = closestNodeFallback(pos) end
  if not n1 then return nil end
  local nodes = map.getMap().nodes
  local a, b = nodes[n1], nodes[n2]
  if not a or not b then return nil end
  return a.pos, quatFromDir((b.pos - a.pos):normalized(), vec3(0, 0, 1))
end

return M
