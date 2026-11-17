local M = {}

M.MAX_ROAD_DISTANCE = 15
M.AHEAD_LENGTH = 2500
M.ALT_LENGTH = 1500
M.ALT_WITHIN = 500
M.BACK_LENGTH = 1000
M.MAX_NODES = 200
M.SEARCH_SPEED = 45
M.WAIT_RADIUS = 150
M.AIM_AHEAD = 60
M.AIM_SIDE = 15
M.AIM_PERIOD = 3
M.MIN_ROUTE = 1
M.BEHIND_MARGIN = 1

local TIE = 1e-6
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

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

local function continuations(links, nodes, id, x, y, dx, dy, from, visited, seed)
  local around = links[id]
  local group = {}
  if around == nil then return group end
  for otherId in pairs(around) do
    if otherId ~= from and not visited[otherId] then
      local ox, oy = nodePos(nodes, otherId)
      if ox ~= nil then
        local ex, ey = ox - x, oy - y
        local turn = 0
        if (dx ~= 0 or dy ~= 0) and (ex ~= 0 or ey ~= 0) then
          turn = math.abs(atan2(dx * ey - dy * ex, dx * ex + dy * ey))
        end
        group[#group + 1] = { id = otherId, turn = turn }
      end
    end
  end
  return order(group, seed)
end

local function addPoint(route, x, y, z)
  local points, dist = route.points, route.dist
  local last = points[#points]
  local step = math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2 + (z - last.z) ^ 2)
  points[#points + 1] = vec3(x, y, z)
  dist[#dist + 1] = dist[#dist] + step
  route.length = dist[#dist]
  return step
end

local function newRoute(x, y, z)
  return { points = { vec3(x, y, z) }, dist = { 0 }, length = 0 }
end

local function walk(roads, route, start, from, visited, dx, dy, cap, seed, junctions)
  local links, nodes = roads.links, roads.nodes
  local id = start
  local px, py, pz = route.points[#route.points].x, route.points[#route.points].y, route.points[#route.points].z
  local x, y, z = nodePos(nodes, id)
  if x == nil then return end
  while true do
    local edge = math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
    if route.length + edge >= cap then
      local t = edge > 0 and (cap - route.length) / edge or 0
      addPoint(route, px + (x - px) * t, py + (y - py) * t, pz + (z - pz) * t)
      return
    end
    if #route.points >= M.MAX_NODES then return end
    addPoint(route, x, y, z)
    visited[id] = true
    if x ~= px or y ~= py then dx, dy = x - px, y - py end
    local list = continuations(links, nodes, id, x, y, dx, dy, from, visited, seed)
    if junctions ~= nil then
      junctions[#junctions + 1] = { at = route.length, list = list, id = id, from = from, x = x, y = y, z = z }
    end
    local pick = list[1]
    if pick == nil then return end
    local nx, ny, nz = nodePos(nodes, pick.id)
    from = id
    px, py, pz = x, y, z
    id, x, y, z = pick.id, nx, ny, nz
  end
end

function M.routes(origin, dirX, dirY, roads, seed, noBack)
  local out = {}
  if origin == nil or roads == nil or roads.closest == nil or roads.links == nil or roads.nodes == nil then return out end
  local ox, oy, oz = origin.x, origin.y, origin.z
  if not (isNumber(ox) and isNumber(oy) and isNumber(oz) and isNumber(dirX) and isNumber(dirY)) then return out end
  local nodes = roads.nodes
  local n1, n2, dist = roads.closest(origin)
  if n1 == nil or not isNumber(dist) or dist > M.MAX_ROAD_DISTANCE then return out end
  local x1, y1 = nodePos(nodes, n1)
  if x1 == nil then return out end
  local forward, other = n1, nil
  if n2 ~= nil and n2 ~= n1 then
    local x2, y2 = nodePos(nodes, n2)
    if x2 == nil then return out end
    local d1 = (x1 - ox) * dirX + (y1 - oy) * dirY
    local d2 = (x2 - ox) * dirX + (y2 - oy) * dirY
    if d2 > d1 then forward, other = n2, n1 else other = n2 end
  end

  local function heading(id)
    local x, y = nodePos(nodes, id)
    local dx, dy = x - ox, y - oy
    if dx == 0 and dy == 0 then return dirX, dirY end
    return dx, dy
  end

  local blocked = {}
  if noBack then
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    if len > 0 then
      for id in pairs(nodes) do
        local x, y = nodePos(nodes, id)
        if x ~= nil and ((x - ox) * dirX + (y - oy) * dirY) / len < -M.BEHIND_MARGIN then blocked[id] = true end
      end
    end
  end
  local function fresh()
    local set = {}
    for id in pairs(blocked) do set[id] = true end
    return set
  end

  local junctions = {}
  local visited = fresh()
  visited[forward] = true
  if other ~= nil then visited[other] = true end
  local ahead = newRoute(ox, oy, oz)
  local dx, dy = heading(forward)
  walk(roads, ahead, forward, other, visited, dx, dy, M.AHEAD_LENGTH, seed, junctions)
  out[1] = ahead

  for _, junction in ipairs(junctions) do
    if junction.at > M.ALT_WITHIN then break end
    if #junction.list >= 2 then
      local alt = newRoute(junction.x, junction.y, junction.z)
      local pick = junction.list[2]
      local ax, ay = nodePos(nodes, pick.id)
      local altVisited = fresh()
      altVisited[junction.id] = true
      if junction.from ~= nil then altVisited[junction.from] = true end
      walk(roads, alt, pick.id, junction.id, altVisited, ax - junction.x, ay - junction.y, M.ALT_LENGTH, seed)
      out[#out + 1] = alt
      break
    end
  end

  if other ~= nil and not noBack then
    local back = newRoute(ox, oy, oz)
    local bx, by = heading(other)
    walk(roads, back, other, forward, { [other] = true, [forward] = true }, bx, by, M.BACK_LENGTH, seed)
    out[#out + 1] = back
  end
  return out
end

function M.newRun(routes)
  local list = {}
  for _, route in ipairs(routes or {}) do
    if route.length >= M.MIN_ROUTE then list[#list + 1] = route end
  end
  return { routes = list, index = 1, s = 0, waiting = false }
end

local function pointAt(route, s)
  local dist, points = route.dist, route.points
  if s <= 0 then
    local a, b = points[1], points[2]
    local len = dist[2] - dist[1]
    if len > 0 then return a.x, a.y, a.z, (b.x - a.x) / len, (b.y - a.y) / len, (b.z - a.z) / len end
    return a.x, a.y, a.z, 0, 0, 0
  end
  local n = #points
  for i = 2, n do
    if s <= dist[i] or i == n then
      local a, b = points[i - 1], points[i]
      local len = dist[i] - dist[i - 1]
      local t = len > 0 and math.min(1, (s - dist[i - 1]) / len) or 0
      local ux, uy, uz = 0, 0, 0
      if len > 0 then ux, uy, uz = (b.x - a.x) / len, (b.y - a.y) / len, (b.z - a.z) / len end
      return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, ux, uy, uz
    end
  end
end

function M.step(run, heliPos, dt)
  local route = run.routes[run.index]
  if route == nil then return nil end
  if run.s >= route.length and run.moved then
    run.index = run.index + 1
    route = run.routes[run.index]
    if route == nil then return nil end
    run.s = 0
    run.waiting = true
  end
  if run.waiting then
    local start = route.points[1]
    local near = false
    if heliPos ~= nil and isNumber(heliPos.x) and isNumber(heliPos.y) then
      local dx, dy = heliPos.x - start.x, heliPos.y - start.y
      near = math.sqrt(dx * dx + dy * dy) <= M.WAIT_RADIUS
    end
    if not near then return vec3(start.x, start.y, start.z), vec3(0, 0, 0) end
    run.waiting = false
  end
  run.moved = true
  run.s = math.min(route.length, run.s + M.SEARCH_SPEED * dt)
  local x, y, z, ux, uy, uz = pointAt(route, run.s)
  local sp = M.SEARCH_SPEED
  return vec3(x, y, z), vec3(ux * sp, uy * sp, uz * sp)
end

function M.aimPoint(run, t, from)
  local route = run.routes[run.index] or run.routes[#run.routes]
  if route == nil then return nil end
  local x, y, z, ux, uy
  if run.waiting and from ~= nil then
    local start = route.points[1]
    ux, uy = start.x - from.x, start.y - from.y
    local d = math.sqrt(ux * ux + uy * uy)
    local k = d > 0 and math.min(d, M.AIM_AHEAD) / d or 0
    x, y, z = from.x + ux * k, from.y + uy * k, from.z
  else
    local s = run.routes[run.index] and run.s or route.length
    x, y, z, ux, uy = pointAt(route, math.min(route.length, s + M.AIM_AHEAD))
  end
  local side = M.AIM_SIDE * math.sin(2 * math.pi * t / M.AIM_PERIOD)
  local len = math.sqrt(ux * ux + uy * uy)
  if len > 0 then
    x = x - uy / len * side
    y = y + ux / len * side
  end
  return x, y, z
end

function M.shift(run, jx, jy, jz)
  for _, route in ipairs(run.routes) do
    for i, p in ipairs(route.points) do
      route.points[i] = vec3(p.x + jx, p.y + jy, p.z + jz)
    end
  end
end

return M
