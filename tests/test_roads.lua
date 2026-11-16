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
