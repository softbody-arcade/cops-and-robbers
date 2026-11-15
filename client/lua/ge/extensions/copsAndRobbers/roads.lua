local M = {}

local COP_SPACING = 8
local LINK_STEP = 15
local MAX_SPAWN_RING = 2000
local ROAD_SEARCH_MAX = 2000

local function roadSpots(center, minD, maxD)
  local nodes = map.getMap().nodes or {}
  local candidates = {}
  local function consider(pos, dir)
    local d = pos:distance(center)
    if d >= minD and d <= maxD then candidates[#candidates + 1] = { pos = pos, d = d, dir = dir } end
  end
  for id, n in pairs(nodes) do
    for linkId in pairs(n.links or {}) do
      local other = nodes[linkId]
      if other and tostring(id) < tostring(linkId) then
        local delta = other.pos - n.pos
        local len = delta:length()
        if len > 1e-3 then
          local dir = delta / len
          local steps = math.max(1, math.floor(len / LINK_STEP))
          for i = 0, steps do consider(n.pos + dir * (len * i / steps), dir) end
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
    local spot = pickSpot(roadSpots(center, lo, hi), index)
    if spot then return spot.pos, quatFromDir(spot.dir, vec3(0, 0, 1)) end
    if hi >= MAX_SPAWN_RING then return nil end
    lo, hi = 0, hi * 2
  end
end

local function closestNodeFallback(pos)
  local nodes = map.getMap().nodes or {}
  local best, bestDist, bestLink
  for id, n in pairs(nodes) do
    local d = n.pos:distance(pos)
    if d <= ROAD_SEARCH_MAX and (not bestDist or d < bestDist) then
      for linkId in pairs(n.links or {}) do
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
