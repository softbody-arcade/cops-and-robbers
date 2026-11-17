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

function M.exit(carPos, dirX, dirY, roads, roofedAt, seed)
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

  local visited = { [start] = true }
  if other ~= nil then visited[other] = true end
  local count = 1
  local queue, head = { start }, 1
  local exits = {}
  local total = 0

  while head <= #queue do
    local id = queue[head]
    head = head + 1
    local x, y, z = nodePos(nodes, id)
    if x == nil then return nil end
    if roofedAt(vec3(x, y, z + M.ROOF_HEIGHT)) ~= true then
      exits[#exits + 1] = id
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
              total = total + math.sqrt((ox - x) ^ 2 + (oy - y) ^ 2 + (oz - z) ^ 2)
              if total > M.MAX_LENGTH then
                head = #queue + 1
                break
              end
              visited[otherId] = true
              count = count + 1
              queue[#queue + 1] = otherId
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

  if #exits == 0 then return nil end
  table.sort(exits, function(a, b) return tostring(a) < tostring(b) end)
  local pick = 1
  if isNumber(seed) then pick = math.floor(seed) % #exits + 1 end
  local ex, ey, ez = nodePos(nodes, exits[pick])
  return vec3(ex, ey, ez)
end

return M
