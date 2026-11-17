local M = {}

local COP_SPACING = 8
local LINK_STEP = 15
local MAX_SPAWN_RING = 2000
local ROAD_SEARCH_MAX = 2000
local MEDIAN_WIDTH = 5
local HEADING_FIT = 0.7

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

local function before(a, b)
  local da, db = math.floor(a.d * 100 + 0.5), math.floor(b.d * 100 + 0.5)
  if da ~= db then return da < db end
  if a.pos.x ~= b.pos.x then return a.pos.x < b.pos.x end
  if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
  return a.pos.z < b.pos.z
end

local function sortSpots(list)
  table.sort(list, before)
  return list
end

local function gated(link)
  return (link.gated or 0) > 0
end

local function private(n, other, id, linkId)
  local a = n.links and n.links[linkId]
  local b = other.links and other.links[id]
  return (a and a.type == "private") or (b and b.type == "private") or false
end

local function lineSpots(center, minD, maxD)
  local links, nodes = graph()
  local candidates = {}
  if not links then return candidates end
  for id, neighbours in pairs(links) do
    for linkId, link in pairs(neighbours) do
      local n, other = nodes[id], nodes[linkId]
      if n and other and tostring(id) < tostring(linkId) and not gated(link) and not private(n, other, id, linkId) then
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
  return sortSpots(candidates)
end

local function heapPush(heap, d, id, from)
  local i = #heap + 1
  heap[i] = { d, id, from }
  while i > 1 do
    local parent = math.floor(i / 2)
    if heap[parent][1] <= heap[i][1] then break end
    heap[parent], heap[i] = heap[i], heap[parent]
    i = parent
  end
end

local function heapPop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    heap[1] = last
    local i = 1
    while true do
      local l, r, small = i * 2, i * 2 + 1, i
      if heap[l] and heap[l][1] < heap[small][1] then small = l end
      if heap[r] and heap[r][1] < heap[small][1] then small = r end
      if small == i then break end
      heap[small], heap[i] = heap[i], heap[small]
      i = small
    end
  end
  return top[1], top[2], top[3]
end

local function walk(links, nodes, seeds, limit, runnerPoint)
  local dist, facing, heap = {}, {}, {}
  for _, s in ipairs(seeds) do heapPush(heap, s[1], s[2], false) end
  while #heap > 0 do
    local d, u, from = heapPop(heap)
    if d > limit then break end
    if not dist[u] then
      dist[u] = d
      local toward = (from and nodes[from].pos or runnerPoint) - nodes[u].pos
      local len = toward:length()
      if len > 1e-3 then
        facing[u] = toward / len
      elseif from then
        facing[u] = facing[from]
      end
      for v, link in pairs(links[u] or {}) do
        if not dist[v] and nodes[v] and not gated(link) and canDrive(link, v) then
          heapPush(heap, d + nodes[u].pos:distance(nodes[v].pos), v, u)
        end
      end
    end
  end
  return dist, facing
end

local function closestOn(p, a, b)
  local ab = b - a
  local len2 = dot(ab, ab)
  local t = len2 > 0 and math.max(0, math.min(1, dot(p - a, ab) / len2)) or 0
  return a + ab * t, t
end

local function flatDir(v)
  local len = math.sqrt(v.x * v.x + v.y * v.y)
  if len < 1e-3 then return nil end
  return vec3(v.x / len, v.y / len, 0)
end

local function headingFit(link, nodes, u, v, heading)
  local along = flatDir(nodes[v].pos - nodes[u].pos)
  if not along then return -1 end
  local c = dot(along, heading)
  if not link.oneWay then return math.abs(c) end
  return link.inNode == u and c or -c
end

local function fittingRoad(links, nodes, center, n1, n2, heading)
  local h = heading and flatDir(heading)
  if not h or headingFit(links[n1][n2], nodes, n1, n2, h) >= HEADING_FIT then return n1, n2 end
  local reach = center:distance((closestOn(center, nodes[n1].pos, nodes[n2].pos))) + MEDIAN_WIDTH
  local best, bestU, bestV
  for u, neighbours in pairs(links) do
    for v, link in pairs(neighbours) do
      if tostring(u) < tostring(v) and nodes[u] and nodes[v] and not gated(link) and headingFit(link, nodes, u, v, h) >= HEADING_FIT then
        local d = center:distance((closestOn(center, nodes[u].pos, nodes[v].pos)))
        if d <= reach and (not best or d < best or (d == best and tostring(u) < tostring(bestU))) then
          best, bestU, bestV = d, u, v
        end
      end
    end
  end
  if bestU then return bestU, bestV end
  return n1, n2
end

local function roadSpots(center, limit, heading)
  local links, nodes = graph()
  if not links then return nil end
  local n1, n2 = map.findClosestRoad(center, ROAD_SEARCH_MAX)
  if not (n1 and links[n1] and links[n1][n2] and nodes[n1] and nodes[n2]) then return nil end
  n1, n2 = fittingRoad(links, nodes, center, n1, n2, heading)
  local own = links[n1][n2]
  local a, b = nodes[n1].pos, nodes[n2].pos
  local runnerPoint, t = closestOn(center, a, b)
  local seeds = {}
  if canDrive(own, n1) or t == 0 then seeds[#seeds + 1] = { runnerPoint:distance(a), n1 } end
  if canDrive(own, n2) or t == 1 then seeds[#seeds + 1] = { runnerPoint:distance(b), n2 } end
  local dist, facing = walk(links, nodes, seeds, limit, runnerPoint)
  local spots = {}
  for u, d in pairs(dist) do
    if facing[u] then spots[#spots + 1] = { pos = nodes[u].pos, d = d, dir = facing[u] } end
  end
  for u, neighbours in pairs(links) do
    for v, link in pairs(neighbours) do
      local isOwn = link == own
      if (dist[u] or dist[v] or isOwn) and tostring(u) < tostring(v) and nodes[u] and nodes[v] and not gated(link) then
        local pu = nodes[u].pos
        local delta = nodes[v].pos - pu
        local len = delta:length()
        if len > 1e-3 then
          local dir = delta / len
          local runnerAt = isOwn and runnerPoint:distance(pu)
          local steps = math.max(1, math.floor(len / LINK_STEP))
          for i = 1, steps - 1 do
            local along = len * i / steps
            local best, toward
            if dist[u] and canDrive(link, v) then best, toward = dist[u] + along, dir * -1 end
            if dist[v] and canDrive(link, u) and (not best or dist[v] + len - along < best) then
              best, toward = dist[v] + len - along, dir
            end
            if runnerAt then
              if along <= runnerAt and canDrive(link, u) and (not best or runnerAt - along <= best) then
                best, toward = runnerAt - along, dir
              elseif along > runnerAt and canDrive(link, v) and (not best or along - runnerAt <= best) then
                best, toward = along - runnerAt, dir * -1
              end
            end
            if best and best <= limit then
              spots[#spots + 1] = { pos = pu + dir * along, d = best, dir = toward }
            end
          end
        end
      end
    end
  end
  return sortSpots(spots)
end

local function pickSpot(candidates, lo, hi, index)
  local chosen = {}
  for _, c in ipairs(candidates) do
    if c.d > hi + 0.01 then break end
    if c.d >= lo and c.d <= hi then
      local free = true
      for _, prev in ipairs(chosen) do
        if prev.pos:distance(c.pos) < COP_SPACING then free = false break end
      end
      if free then
        chosen[#chosen + 1] = c
        if #chosen == index then return c end
      end
    end
  end
  return nil
end

local function rings(minD, maxD)
  local list = { { minD, maxD } }
  local hi = math.max(maxD, 1)
  while hi < MAX_SPAWN_RING do
    hi = hi * 2
    list[#list + 1] = { minD, hi }
  end
  return list
end

local function pickFrom(candidates, ringList, index)
  for _, ring in ipairs(ringList) do
    local spot = pickSpot(candidates, ring[1], ring[2], index)
    if spot then return spot.pos, quatFromDir(spot.dir, vec3(0, 0, 1)) end
  end
  return nil
end

local FORWARD_CONE = math.cos(math.rad(45))

local function outsideCone(spots, center, heading)
  local h = heading and flatDir(heading)
  if not h or not spots then return nil end
  local out = {}
  for _, spot in ipairs(spots) do
    local off = flatDir(spot.pos - center)
    if not off or dot(off, h) < FORWARD_CONE then out[#out + 1] = spot end
  end
  if #out == #spots then return nil end
  return out
end

function M.findCopSpot(center, minD, maxD, index, heading)
  local ringList = rings(minD, maxD)
  local limit = ringList[#ringList][2]
  local roadList = roadSpots(center, limit, heading)
  local roadOut = outsideCone(roadList, center, heading)
  if roadOut then
    local pos, rot = pickFrom(roadOut, ringList, index)
    if pos then return pos, rot end
  end
  if roadList then
    local pos, rot = pickFrom(roadList, ringList, index)
    if pos then return pos, rot end
  end
  local lineList = lineSpots(center, minD, limit)
  local lineOut = outsideCone(lineList, center, heading)
  if lineOut then
    local pos, rot = pickFrom(lineOut, ringList, index)
    if pos then return pos, rot end
  end
  return pickFrom(lineList, ringList, index)
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

function M.nearestRoad(pos, heading)
  local n1, n2 = map.findClosestRoad(pos)
  if not n1 then n1, n2 = closestNodeFallback(pos) end
  if not n1 then return nil end
  local nodes = map.getMap().nodes
  local a, b = nodes[n1], nodes[n2]
  if not a or not b then return nil end
  local dir = (b.pos - a.pos):normalized()
  if heading and dir.x * heading.x + dir.y * heading.y < 0 then dir = dir * -1 end
  return a.pos, quatFromDir(dir, vec3(0, 0, 1))
end

return M
