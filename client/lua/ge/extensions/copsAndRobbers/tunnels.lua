local M = {}

M.MAX_LENGTH = 3000
M.MAX_NODES = 200
M.MAX_ROAD_DISTANCE = 15
M.ROOF_HEIGHT = 1.5

local function isNumber(n)
  return type(n) == "number" and n == n
end

local function nodePos(nodes, id)
  local node = nodes[id]
  local pos = node and node.pos
  if pos == nil then return nil end
  local x, y, z = pos.x, pos.y, pos.z
  if not (isNumber(x) and isNumber(y) and isNumber(z)) then return nil end
  return x, y, z
end

local TIE = 1e-6
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function walk(links, nodes, cache, roofedAt, car, start, blocked, dirX, dirY, behind, exits)
  local sx, sy, sz = nodePos(nodes, start)
  if sx == nil then return false end
  local info = {
    [start] = {
      length = math.sqrt((sx - car[1]) ^ 2 + (sy - car[2]) ^ 2 + (sz - car[3]) ^ 2),
      turn = 0,
      dx = dirX,
      dy = dirY,
    },
  }
  local visited = { [start] = true }
  if blocked ~= nil then visited[blocked] = true end
  local count = 1
  local queue, head = { start }, 1
  local total = 0

  while head <= #queue do
    local id = queue[head]
    head = head + 1
    local x, y, z = nodePos(nodes, id)
    if x == nil then return false end
    local roofed = cache[id]
    if roofed == nil then
      roofed = roofedAt(vec3(x, y, z + M.ROOF_HEIGHT)) == true
      cache[id] = roofed
    end
    local here = info[id]
    if not roofed then
      exits[#exits + 1] = {
        id = id,
        pos = vec3(x, y, z),
        from = here.from,
        length = here.length,
        turn = here.turn,
        behind = behind or nil,
      }
    else
      local around = links[id]
      if around ~= nil then
        local ids = {}
        for otherId in pairs(around) do ids[#ids + 1] = otherId end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, otherId in ipairs(ids) do
          if not visited[otherId] then
            local ox, oy, oz = nodePos(nodes, otherId)
            if ox ~= nil then
              local edge = math.sqrt((ox - x) ^ 2 + (oy - y) ^ 2 + (oz - z) ^ 2)
              total = total + edge
              if total > M.MAX_LENGTH then
                head = #queue + 1
                break
              end
              visited[otherId] = true
              count = count + 1
              queue[#queue + 1] = otherId
              local ex, ey = ox - x, oy - y
              local elen = math.sqrt(ex * ex + ey * ey)
              local turn, dx, dy = here.turn, here.dx, here.dy
              if elen > 0 then
                local hlen = math.sqrt(dx * dx + dy * dy)
                if hlen > 0 then
                  local cross = dx * ey - dy * ex
                  local dot = dx * ex + dy * ey
                  turn = turn + math.abs(atan2(cross, dot))
                end
                dx, dy = ex, ey
              end
              info[otherId] = { from = id, length = here.length + edge, turn = turn, dx = dx, dy = dy }
              if count >= M.MAX_NODES then
                head = #queue + 1
                break
              end
            end
          end
        end
      end
    end
  end
  return true
end

local function order(group, seed)
  table.sort(group, function(a, b)
    if a.turn ~= b.turn then return a.turn < b.turn end
    return tostring(a.id) < tostring(b.id)
  end)
  local out = {}
  local i = 1
  while i <= #group do
    local j = i
    while j < #group and group[j + 1].turn - group[j].turn <= TIE do j = j + 1 end
    local tie = {}
    for k = i, j do tie[#tie + 1] = group[k] end
    table.sort(tie, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local shift = 0
    if isNumber(seed) and seed > -math.huge and seed < math.huge then
      shift = math.floor(seed) % #tie
    end
    for k = 1, #tie do out[#out + 1] = tie[(k - 1 + shift) % #tie + 1] end
    i = j + 1
  end
  return out
end

function M.watch(carPos, dirX, dirY, roads, roofedAt, seed, cache)
  if carPos == nil or roofedAt == nil then return nil end
  local cx, cy, cz = carPos.x, carPos.y, carPos.z
  if not (isNumber(cx) and isNumber(cy) and isNumber(cz)) then return nil end
  if not (isNumber(dirX) and isNumber(dirY)) then return nil end
  if roofedAt(vec3(cx, cy, cz + M.ROOF_HEIGHT)) ~= true then return nil end
  if roads == nil or roads.closest == nil or roads.links == nil or roads.nodes == nil then return nil end
  local links, nodes = roads.links, roads.nodes

  local n1, n2, dist = roads.closest(carPos)
  if n1 == nil then return nil end
  if not isNumber(dist) or dist > M.MAX_ROAD_DISTANCE then return nil end

  local x1, y1 = nodePos(nodes, n1)
  if x1 == nil then return nil end
  local start, other = n1, nil
  if n2 ~= nil and n2 ~= n1 then
    local x2, y2 = nodePos(nodes, n2)
    if x2 == nil then return nil end
    local d1 = (x1 - cx) * dirX + (y1 - cy) * dirY
    local d2 = (x2 - cx) * dirX + (y2 - cy) * dirY
    if d2 > d1 then start, other = n2, n1 else other = n2 end
  end

  cache = cache or {}
  local car = { cx, cy, cz }
  local ahead, behind = {}, {}
  if not walk(links, nodes, cache, roofedAt, car, start, other, dirX, dirY, false, ahead) then return nil end
  if other ~= nil then
    if not walk(links, nodes, cache, roofedAt, car, other, start, -dirX, -dirY, true, behind) then return nil end
  end

  local result = order(ahead, seed)
  for _, entry in ipairs(order(behind, seed)) do result[#result + 1] = entry end
  return result
end

return M
