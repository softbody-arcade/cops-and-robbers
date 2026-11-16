package.path = "client/lua/ge/extensions/?.lua;" .. package.path

local vecMeta = {}
vecMeta.__index = vecMeta
local function v3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vecMeta) end
vecMeta.__add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end
vecMeta.__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end
vecMeta.__mul = function(a, b)
  if type(a) == "number" then a, b = b, a end
  return v3(a.x * b, a.y * b, a.z * b)
end
vecMeta.__div = function(a, b) return v3(a.x / b, a.y / b, a.z / b) end
function vecMeta:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function vecMeta:distance(o) return (self - o):length() end
function vecMeta:normalized()
  local l = self:length()
  return l > 0 and self / l or v3(0, 0, 0)
end

local function segmentDistance(p, a, b)
  local ab = b - a
  local len2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
  local t = 0
  if len2 > 0 then
    t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y + (p.z - a.z) * ab.z) / len2
    t = math.max(0, math.min(1, t))
  end
  return p:distance(a + ab * t)
end

function useMap(nodeList, links, opts)
  opts = opts or {}
  _G.vec3 = v3
  _G.quatFromDir = function(dir) return { dir = dir } end
  local nodes, graph = {}, {}
  for id, p in pairs(nodeList) do
    nodes[id] = { pos = v3(p[1], p[2], 0), links = {} }
    graph[id] = {}
  end
  for _, l in ipairs(links) do
    local from, to = l[1], l[2]
    local data = { inNode = from, outNode = to, oneWay = l.oneWay or false, gated = l.gated or 0, len = 1 }
    nodes[to].links[from] = data
    graph[from][to] = data
    graph[to][from] = data
  end
  _G.map = {
    getMap = function() return { nodes = nodes } end,
    getGraphpath = function() return { graph = graph } end,
    findClosestRoad = function(pos, radius)
      if opts.noKdTree then return nil end
      if opts.closest then return opts.closest[1], opts.closest[2], 0 end
      radius = radius or 200
      local best, bestD
      for _, l in ipairs(links) do
        local d = segmentDistance(pos, nodes[l[1]].pos, nodes[l[2]].pos)
        if d <= radius and (not bestD or d < bestD) then best, bestD = l, d end
      end
      if not best then return nil end
      return best[1], best[2], bestD
    end,
  }
  return nodes, graph
end

package.loaded["copsAndRobbers/roads"] = nil
local roads = require("copsAndRobbers/roads")

test("straight line: links stored at the node with the larger id are seen", function()
  useMap({ a = { 0, 100 }, z = { 0, 200 } }, { { "a", "z" } })
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertEq(pos ~= nil, true)
  assertEq(pos.x, 0)
end)

test("straight line: a two-way spot faces toward the runner", function()
  useMap({ a = { 100, 0 }, b = { 300, 0 } }, { { "b", "a" } }, { noKdTree = true })
  local pos, rot = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertNear(pos.x, 100, 0.01)
  assertNear(rot.dir.x, -1, 1e-6)
end)

test("straight line: a one-way spot faces with the flow", function()
  useMap({ a = { 100, 0 }, b = { 300, 0 } }, { { "a", "b", oneWay = true } }, { noKdTree = true })
  local _, rot = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertNear(rot.dir.x, 1, 1e-6)
end)

test("nearest road backup finds a node whose links are stored elsewhere", function()
  useMap({ a = { 10, 0 }, b = { 500, 0 } }, { { "a", "b" } }, { noKdTree = true })
  local pos = roads.nearestRoad(vec3(0, 0, 0))
  assertEq(pos.x, 10)
end)

local function road(nodes, links, prefix, points, oneWay, flip)
  local ids = {}
  for i, p in ipairs(points) do
    ids[i] = prefix .. i
    nodes[ids[i]] = p
  end
  for i = 2, #ids do
    local from, to = ids[i - 1], ids[i]
    if flip and not oneWay and i % 2 == 0 then from, to = to, from end
    links[#links + 1] = { from, to, oneWay = oneWay }
  end
  return ids
end

local function line(x1, x2, y)
  local points = {}
  local step = x2 >= x1 and 100 or -100
  for x = x1, x2, step do points[#points + 1] = { x, y or 0 } end
  return points
end

test("hairpin: the other leg is close in a straight line but not by road", function()
  useMap({ a = { 0, -100 }, b = { 0, 0 }, c = { 0, 150 }, d = { 30, 150 }, e = { 30, 0 }, f = { 30, -100 } },
    { { "a", "b" }, { "b", "c" }, { "c", "d" }, { "d", "e" }, { "e", "f" } })
  for i = 1, 4 do
    local pos = roads.findCopSpot(vec3(0, 10, 0), 50, 150, i)
    assertEq(pos.x, 0, "spot " .. i)
  end
end)

test("divided highway: cops start behind the runner on its own carriageway, facing it", function()
  local nodes, links = {}, {}
  local north, south = {}, {}
  for y = -500, 500, 100 do north[#north + 1] = { 0, y } end
  for y = 500, -500, -100 do south[#south + 1] = { 20, y } end
  local n = road(nodes, links, "n", north, true)
  local s = road(nodes, links, "s", south, true)
  links[#links + 1] = { n[#n], s[1], oneWay = true }
  links[#links + 1] = { s[#s], n[1], oneWay = true }
  useMap(nodes, links)
  for i = 1, 3 do
    local pos, rot = roads.findCopSpot(vec3(0, 10, 0), 50, 150, i)
    assertEq(pos.x, 0, "spot " .. i)
    assertEq(pos.y < 10, true, "spot " .. i)
    assertNear(rot.dir.y, 1, 1e-6, "spot " .. i)
  end
end)

test("two-way: spots on both sides face toward the runner", function()
  local nodes, links = {}, {}
  road(nodes, links, "n", line(-1000, 1000), false, true)
  useMap(nodes, links)
  local p1, r1 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  local p2, r2 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 2)
  assertNear(math.abs(p1.x), 50, 0.01)
  assertNear(p2.x, -p1.x, 0.01)
  assertEq(r1.dir.x * p1.x < 0, true)
  assertEq(r2.dir.x * p2.x < 0, true)
end)

test("ties sort the same whatever order the graph was built in", function()
  local results = {}
  for run, points in ipairs({ line(-1000, 1000), line(1000, -1000) }) do
    local nodes, links = {}, {}
    road(nodes, links, run == 1 and "n" or "m", points, false, run == 2)
    useMap(nodes, links)
    local p1 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
    local p2 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 2)
    results[run] = { p1, p2 }
  end
  assertNear(results[1][1].x, results[2][1].x, 1e-6)
  assertNear(results[1][2].x, results[2][2].x, 1e-6)
  assertEq(math.abs(results[1][1].x - results[1][2].x) > 8, true)
end)

test("cops stay 8 m apart and later indexes are not closer", function()
  local nodes, links = {}, {}
  road(nodes, links, "n", line(-1000, 1000))
  useMap(nodes, links)
  local spots = {}
  for i = 1, 6 do spots[i] = roads.findCopSpot(vec3(0, 0, 0), 50, 150, i) end
  for i = 1, 6 do
    for j = i + 1, 6 do assertEq(spots[i]:distance(spots[j]) >= 8, true, i .. "-" .. j) end
    if i > 1 then assertEq(math.abs(spots[i].x) >= math.abs(spots[i - 1].x) - 1e-6, true, "order " .. i) end
  end
end)

test("too few spots widens by road but keeps the minimum", function()
  local nodes, links = {}, {}
  road(nodes, links, "n", line(0, 1000))
  useMap(nodes, links)
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 8)
  assertEq(pos.x > 150 and pos.x <= 300, true, "x " .. tostring(pos.x))
end)

test("runner on a node at a dead end still gets spots", function()
  local nodes, links = {}, {}
  road(nodes, links, "n", line(0, 400))
  useMap(nodes, links)
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertNear(pos.x, 50, 0.01)
end)

test("a dead-end island falls back to the straight-line search", function()
  useMap({ a = { 0, 0 }, b = { 20, 0 }, c = { -500, 100 }, d = { 500, 100 } }, { { "a", "b" }, { "c", "d" } })
  local pos = roads.findCopSpot(vec3(10, 0, 0), 50, 150, 1)
  assertEq(pos.y, 100)
end)

test("closest road ids missing from the graph fall back without an error", function()
  local nodes, links = {}, {}
  road(nodes, links, "n", line(-1000, 1000))
  useMap(nodes, links, { closest = { "x", "y" } })
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertEq(pos.y, 0)
  assertNear(math.abs(pos.x), 50, 0.01)
end)

test("a gated link is neither walked nor used for spots", function()
  local nodes, links = {}, {}
  road(nodes, links, "m", line(-500, 500))
  local branch = road(nodes, links, "g", { { 0, 30 }, { 0, 100 }, { 0, 200 }, { 0, 300 }, { 0, 400 }, { 0, 500 } })
  links[#links + 1] = { "m6", branch[1], gated = 10000 }
  useMap(nodes, links)
  for i = 1, 6 do
    local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, i)
    assertEq(pos.y, 0, "spot " .. i)
  end
end)

test("a zero-length link gives no NaN", function()
  local nodes, links = {}, {}
  links[1] = { "m6", "z" }
  road(nodes, links, "m", line(-500, 500))
  nodes.z = { 0, 0 }
  links[#links + 1] = { "z", "m7" }
  useMap(nodes, links)
  for i = 1, 4 do
    local pos, rot = roads.findCopSpot(vec3(0, 0, 0), 50, 150, i)
    assertEq(pos ~= nil, true, "spot " .. i)
    assertEq(rot.dir.x == rot.dir.x and rot.dir.y == rot.dir.y, true, "spot " .. i)
  end
end)

test("a max above 2 km is still searched by road", function()
  local points = line(0, 1500)
  for y = 100, 1500, 100 do points[#points + 1] = { 1500, y } end
  local nodes, links = {}, {}
  road(nodes, links, "n", points)
  useMap(nodes, links)
  local pos = roads.findCopSpot(vec3(0, 0, 0), 2400, 3000, 1)
  assertEq(pos.x, 1500)
  assertNear(pos.y, 900, 0.01)
end)
