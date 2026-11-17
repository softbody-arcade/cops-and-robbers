local tunnels = require("copsAndRobbers/tunnels")

local function v(x, y, z) return { x = x, y = y, z = z } end
_G.vec3 = _G.vec3 or v

local function line(count, spacing, linkLen)
  local nodes, links = {}, {}
  for i = 1, count do
    nodes[i] = { pos = v((i - 1) * spacing, 0, 0) }
    links[i] = {}
  end
  for i = 1, count - 1 do
    links[i][i + 1] = { len = linkLen or spacing }
    links[i + 1][i] = { len = linkLen or spacing }
  end
  return nodes, links
end

local function roadsOf(nodes, links, n1, n2, dist, calls)
  return {
    nodes = nodes,
    links = links,
    closest = function()
      if calls then calls.n = calls.n + 1 end
      return n1, n2, dist
    end,
  }
end

local function roofedIds(nodes, set)
  return function(pos)
    if pos.x == 150 and pos.y == 0 then return true end
    for id, node in pairs(nodes) do
      if set[id] and node.pos.x == pos.x and node.pos.y == pos.y then return true end
    end
    return false
  end
end

local function roofedRange(nodes, from, to)
  local set = {}
  for i = from, to do set[i] = true end
  return roofedIds(nodes, set)
end

local function allRoofed(pos) return true end

local CAR = v(150, 0, 0)

test("a straight tunnel gives the exit ahead", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local p = tunnels.exit(CAR, 1, 0, roads, roofedRange(nodes, 2, 4))
  assertEq(p.x, 400)
  assertEq(p.y, 0)
end)

test("turning around in a tunnel gives the exit behind", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local p = tunnels.exit(CAR, -1, 0, roads, roofedRange(nodes, 2, 4))
  assertEq(p.x, 0)
end)

local function fork()
  local nodes = {
    [1] = { pos = v(0, 0, 0) },
    [2] = { pos = v(100, 0, 0) },
    [3] = { pos = v(200, 50, 0) },
    [4] = { pos = v(200, -50, 0) },
  }
  local links = { [1] = { [2] = {} }, [2] = { [1] = {}, [3] = {}, [4] = {} }, [3] = { [2] = {} }, [4] = { [2] = {} } }
  return nodes, links
end

test("a fork picks the exit by seed, ordered by node id", function()
  local nodes, links = fork()
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  local car = v(0, 0, 0)
  assertEq(tunnels.exit(car, 1, 0, roads, roofed, 0).y, 50)
  assertEq(tunnels.exit(car, 1, 0, roads, roofed, 1).y, -50)
  assertEq(tunnels.exit(car, 1, 0, roads, roofed, 2).y, 50)
  assertEq(tunnels.exit(car, 1, 0, roads, roofed).y, 50)
end)

test("exit ids are ordered as strings", function()
  local nodes = {
    [1] = { pos = v(0, 0, 0) },
    [2] = { pos = v(10, 0, 0) },
    [10] = { pos = v(20, 10, 0) },
    ["9"] = { pos = v(20, -10, 0) },
  }
  local links = { [1] = { [2] = {} }, [2] = { [1] = {}, [10] = {}, ["9"] = {} }, [10] = { [2] = {} }, ["9"] = { [2] = {} } }
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  assertEq(tunnels.exit(v(0, 0, 0), 1, 0, roads, roofed, 0).y, 10)
  assertEq(tunnels.exit(v(0, 0, 0), 1, 0, roads, roofed, 1).y, -10)
end)

test("a tunnel over 3 km gives nil", function()
  local nodes, links = line(43, 100)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  assertEq(tunnels.exit(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 41)), nil)
end)

test("a ring of 250 roofed nodes is stopped by the node cap", function()
  local nodes, links = {}, {}
  for i = 1, 250 do
    nodes[i] = { pos = v(i * 10, 0, 0) }
    links[i] = {}
  end
  for i = 1, 250 do
    local j = i % 250 + 1
    links[i][j] = {}
    links[j][i] = {}
  end
  local roads = roadsOf(nodes, links, 1, 2, 2)
  assertEq(tunnels.exit(v(10, 0, 0), 1, 0, roads, allRoofed), nil)
end)

test("lengths come from node positions, not link len", function()
  local nodes, links = line(43, 100, 1)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  assertEq(tunnels.exit(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 41)), nil)
  local shortNodes, shortLinks = line(5, 100, 5000)
  local shortRoads = roadsOf(shortNodes, shortLinks, 2, 3, 2)
  assertEq(tunnels.exit(CAR, 1, 0, shortRoads, roofedRange(shortNodes, 2, 4)).x, 400)
end)

test("a road too far gives nil", function()
  local nodes, links = line(5, 100)
  local roofed = roofedRange(nodes, 2, 4)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 16), roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 14), roofed).x, 400)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, 2, 3, nil), roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, 2, 3, "2"), roofed), nil)
end)

test("a car with no roof gives nil without asking the road", function()
  local nodes, links = line(5, 100)
  local calls = { n = 0 }
  local roads = roadsOf(nodes, links, 2, 3, 2, calls)
  assertEq(tunnels.exit(CAR, 1, 0, roads, function() return false end), nil)
  assertEq(calls.n, 0)
end)

test("the roof is tested ROOF_HEIGHT above the car and the nodes", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local seen = {}
  local p = tunnels.exit(v(150, 0, 7), 1, 0, roads, function(pos)
    seen[#seen + 1] = pos.z
    return pos.x >= 100 and pos.x <= 300
  end)
  assertEq(p.x, 400)
  assertEq(seen[1], 7 + tunnels.ROOF_HEIGHT)
  assertEq(seen[2], tunnels.ROOF_HEIGHT)
end)

test("missing data gives nil without an error", function()
  local nodes, links = line(5, 100)
  local roofed = roofedRange(nodes, 2, 4)
  assertEq(tunnels.exit(CAR, 1, 0, nil, roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, { closest = function() return 2, 3, 2 end, nodes = nodes }, roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, { links = links, nodes = nodes }, roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, { closest = function() return 2, 3, 2 end, links = links }, roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, nil, nil, nil), roofed), nil)
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 2), nil), nil)
  local holes = {}
  for k, n in pairs(nodes) do holes[k] = n end
  holes[3] = nil
  holes[5] = nil
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(holes, links, 2, 3, 2), roofed), nil)
  local h4 = {}
  for k, n in pairs(nodes) do h4[k] = n end
  h4[5] = nil
  assertEq(tunnels.exit(CAR, 1, 0, roadsOf(h4, links, 2, 3, 2), roofed), nil)
end)

test("just under a bridge the forward node is the exit", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local p = tunnels.exit(CAR, 1, 0, roads, roofedRange(nodes, 1, 2))
  assertEq(p.x, 200)
end)

test("a zero direction walks from n1", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local p = tunnels.exit(CAR, 0, 0, roads, roofedRange(nodes, 2, 4))
  assertEq(p.x, 0)
end)

test("the node behind the car is never visited", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local visited = {}
  tunnels.exit(CAR, 1, 0, roads, function(pos)
    visited[pos.x] = true
    return pos.x >= 100 and pos.x <= 300
  end)
  assertEq(visited[100], nil)
end)
