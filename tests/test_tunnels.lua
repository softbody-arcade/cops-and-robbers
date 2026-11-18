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

local CAR = v(150, 0, 0)

local function probeAbove(pos, ground)
  return pos.x == ground.x and pos.y == ground.y and pos.z == ground.z + 1.5
end

local function roofedIds(nodes, set)
  return function(pos)
    if probeAbove(pos, CAR) then return true end
    for id, node in pairs(nodes) do
      if set[id] and probeAbove(pos, node.pos) then return true end
    end
    return false
  end
end

local function roofedRange(nodes, from, to)
  local set = {}
  for i = from, to do set[i] = true end
  return roofedIds(nodes, set)
end

local function ids(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.id end
  return out
end

local function assertIds(list, want)
  assertEq(list ~= nil, true)
  local got = ids(list)
  assertEq(#got, #want)
  for i = 1, #want do assertEq(got[i], want[i]) end
end

local function near(a, b) assertEq(math.abs(a - b) < 1e-6, true) end

test("a straight tunnel gives the exit ahead, then the one behind", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local list = tunnels.watch(CAR, 1, 0, roads, roofedRange(nodes, 2, 4))
  assertIds(list, { 5, 1 })
  near(list[1].length, 250)
  near(list[2].length, 150)
  assertEq(list[1].behind, nil)
  assertEq(list[2].behind, true)
  assertEq(list[1].pos.x, 400)
  assertEq(list[1].from, 4)
  assertEq(list[2].from, 2)
  near(list[1].turn, 0)
end)

test("turning around in a tunnel puts the exit behind first", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local list = tunnels.watch(CAR, -1, 0, roads, roofedRange(nodes, 2, 4))
  assertIds(list, { 1, 5 })
  assertEq(list[1].behind, nil)
  assertEq(list[2].behind, true)
end)

local function fork(angle)
  local a = angle or math.rad(30)
  local nodes = {
    [1] = { pos = v(0, 0, 0) },
    [2] = { pos = v(100, 0, 0) },
    [3] = { pos = v(100 + 100 * math.cos(a), 100 * math.sin(a), 0) },
    [4] = { pos = v(100 + 100 * math.cos(a), -100 * math.sin(a), 0) },
  }
  local links = { [1] = { [2] = {} }, [2] = { [1] = {}, [3] = {}, [4] = {} }, [3] = { [2] = {} }, [4] = { [2] = {} } }
  return nodes, links
end

test("a fork gives the straighter branch first", function()
  local nodes, links = fork()
  nodes[4].pos = v(200, -10, 0)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  local list = tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, 0)
  assertEq(list[1].id, 4)
  assertEq(list[2].id, 3)
  assertEq(list[1].turn < list[2].turn, true)
end)

test("a symmetric fork is rotated by the seed", function()
  local nodes, links = fork()
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  local car = v(0, 0, 0)
  assertEq(tunnels.watch(car, 1, 0, roads, roofed, 0)[1].id, 3)
  assertEq(tunnels.watch(car, 1, 0, roads, roofed, 1)[1].id, 4)
  assertEq(tunnels.watch(car, 1, 0, roads, roofed, 2)[1].id, 3)
  assertEq(tunnels.watch(car, 1, 0, roads, roofed)[1].id, 3)
end)

test("equal exits behind the car measure their turn from the reverse heading and rotate within that group", function()
  local nodes, links = fork(math.pi / 4)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local car = v(50, 0, 0)
  local function roofed(p) return p.x == 50 or p.x == 100 end
  for seed = 0, 1 do
    local list = tunnels.watch(car, -1, 0, roads, roofed, seed)
    assertIds(list, seed == 0 and { 1, 3, 4 } or { 1, 4, 3 })
    assertEq(list[1].behind, nil)
    for i = 2, 3 do
      assertEq(list[i].behind, true)
      near(list[i].turn, math.pi / 4)
    end
  end
end)

test("ids in a tie are ordered as strings", function()
  local nodes = {
    [1] = { pos = v(0, 0, 0) },
    [2] = { pos = v(10, 0, 0) },
    [10] = { pos = v(20, 10, 0) },
    ["9"] = { pos = v(20, -10, 0) },
  }
  local links = { [1] = { [2] = {} }, [2] = { [1] = {}, [10] = {}, ["9"] = {} }, [10] = { [2] = {} }, ["9"] = { [2] = {} } }
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  assertEq(tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, 0)[1].id, 10)
  assertEq(tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, 1)[1].id, "9")
end)

test("a single closest node lets the walk reach both mouths without duplicating them", function()
  local nodes, links = line(3, 100)
  local roofed = roofedRange(nodes, 2, 2)
  local function check(second)
    local list = tunnels.watch(nodes[2].pos, 1, 0, roadsOf(nodes, links, 2, second, 0), roofed)
    assertIds(list, { 3, 1 })
    for _, exit in ipairs(list) do
      near(exit.length, 100)
      assertEq(exit.behind, nil)
    end
  end
  check(2)
  check(nil)
end)

test("on a road node the exit ahead is measured from the car and the other mouth stays behind", function()
  local nodes, links = line(4, 100)
  local list = tunnels.watch(nodes[3].pos, -1, 0, roadsOf(nodes, links, 2, 3, 0), roofedRange(nodes, 2, 3))
  assertIds(list, { 1, 4 })
  near(list[1].length, 200)
  near(list[2].length, 100)
  assertEq(list[1].behind, nil)
  assertEq(list[2].behind, true)
end)

test("a roofed node with no links yields an empty watch", function()
  local nodes, links = line(1, 100)
  local roads = roadsOf(nodes, links, 1, nil, 0)
  local roofed = roofedRange(nodes, 1, 1)
  assertIds(tunnels.watch(nodes[1].pos, 1, 0, roads, roofed), {})
  links[1] = nil
  assertIds(tunnels.watch(nodes[1].pos, 1, 0, roads, roofed), {})
end)

test("a helicopter follows a listed tunnel link even against one-way traffic", function()
  local nodes, links = line(4, 100)
  local link = { inNode = 4, outNode = 3, oneWay = true }
  links[3][4], links[4][3] = link, link
  local roads, roofed = roadsOf(nodes, links, 2, 3, 0), roofedRange(nodes, 2, 3)
  local list = tunnels.watch(CAR, 1, 0, roads, roofed)
  assertIds(list, { 4, 1 })
  assertEq(list[1].from, 3)
  links[3][4] = nil
  assertIds(tunnels.watch(CAR, 1, 0, roads, roofed), { 1 })
end)

test("stacked road nodes can have a roof over the lower deck and open sky above", function()
  local nodes, links = line(4, 100)
  nodes[4].pos = v(200, 0, 12)
  local list = tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 0), roofedRange(nodes, 2, 3))
  assertIds(list, { 4, 1 })
  near(list[1].length, 62)
  assertEq(list[1].pos.z, 12)
end)

test("the 3 km walk budget is shared by branches on the same side of the car", function()
  local nodes, links = fork()
  nodes[3].pos, nodes[4].pos = v(100, 1100, 0), v(100, -1100, 0)
  nodes[5], nodes[6] = { pos = v(1100, 1100, 0) }, { pos = v(1100, -1100, 0) }
  links[3][5], links[4][6] = {}, {}
  local roads = roadsOf(nodes, links, 1, 2, 0)
  local function exits()
    return tunnels.watch(nodes[1].pos, 1, 0, roads, roofedRange(nodes, 1, 4))
  end
  assertIds(exits(), {})
  links[2][4] = nil
  assertIds(exits(), { 5 })
  links[2][3], links[2][4] = nil, {}
  assertIds(exits(), { 6 })
end)

test("a tunnel over 3 km gives an empty list", function()
  local nodes, links = line(43, 100)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local list = tunnels.watch(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 41))
  assertEq(list ~= nil, true)
  assertEq(#list, 0)
end)

test("a ring of 600 roofed nodes is stopped by the node cap", function()
  local nodes, links = {}, {}
  for i = 1, 600 do
    nodes[i] = { pos = v(i * 10, 0, 0) }
    links[i] = {}
  end
  for i = 1, 600 do
    local j = i % 600 + 1
    links[i][j] = {}
    links[j][i] = {}
  end
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = function(pos) return pos.x ~= 3000 end
  local list = tunnels.watch(v(10, 0, 0), 1, 0, roads, roofed)
  assertEq(list ~= nil, true)
  assertEq(#list, 0)
end)

test("lengths come from node positions, not link len", function()
  local nodes, links = line(43, 100, 1)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  assertEq(#tunnels.watch(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 41)), 0)
  local shortNodes, shortLinks = line(5, 100, 5000)
  local shortRoads = roadsOf(shortNodes, shortLinks, 2, 3, 2)
  local list = tunnels.watch(CAR, 1, 0, shortRoads, roofedRange(shortNodes, 2, 4))
  assertEq(list[1].pos.x, 400)
  near(list[1].length, 250)
end)

test("the nearest road must be within 15 m, including exactly 15 m", function()
  local nodes, links = line(5, 100)
  local roofed = roofedRange(nodes, 2, 4)
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 16), roofed), nil)
  assertIds(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 15), roofed), { 5, 1 })
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, nil), roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, "2"), roofed), nil)
end)

test("a car with no roof gives nil without asking the road", function()
  local nodes, links = line(5, 100)
  local calls = { n = 0 }
  local roads = roadsOf(nodes, links, 2, 3, 2, calls)
  assertEq(tunnels.watch(CAR, 1, 0, roads, function() return false end), nil)
  assertEq(calls.n, 0)
end)

test("the roof is tested ROOF_HEIGHT above the car and the nodes", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local seen = {}
  local list = tunnels.watch(v(150, 0, 7), 1, 0, roads, function(pos)
    seen[#seen + 1] = pos.z
    return pos.x >= 100 and pos.x <= 300
  end)
  assertEq(list[1].pos.x, 400)
  assertEq(seen[1], 7 + tunnels.ROOF_HEIGHT)
  assertEq(seen[2], tunnels.ROOF_HEIGHT)
end)

test("missing data gives nil without an error", function()
  local nodes, links = line(5, 100)
  local roofed = roofedRange(nodes, 2, 4)
  assertEq(tunnels.watch(CAR, 1, 0, nil, roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, { closest = function() return 2, 3, 2 end, nodes = nodes }, roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, { links = links, nodes = nodes }, roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, { closest = function() return 2, 3, 2 end, links = links }, roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, nil, nil, nil), roofed), nil)
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(nodes, links, 2, 3, 2), nil), nil)
  assertEq(tunnels.watch(nil, 1, 0, roadsOf(nodes, links, 2, 3, 2), roofed), nil)
  assertEq(tunnels.watch(v(0 / 0, 0, 0), 1, 0, roadsOf(nodes, links, 2, 3, 2), function() return true end), nil)
  local holes = {}
  for k, n in pairs(nodes) do holes[k] = n end
  holes[3] = nil
  holes[5] = nil
  assertEq(tunnels.watch(CAR, 1, 0, roadsOf(holes, links, 2, 3, 2), roofed), nil)
  local h4 = {}
  for k, n in pairs(nodes) do h4[k] = n end
  h4[5] = nil
  local list = tunnels.watch(CAR, 1, 0, roadsOf(h4, links, 2, 3, 2), roofed)
  assertIds(list, { 1 })
end)

test("just under a bridge the forward node is the exit", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local list = tunnels.watch(CAR, 1, 0, roads, roofedRange(nodes, 1, 2))
  assertEq(list[1].pos.x, 200)
  near(list[1].length, 50)
  assertEq(list[1].from, nil)
end)

test("a zero direction has no turn and walks from n1 first", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local list = tunnels.watch(CAR, 0, 0, roads, roofedRange(nodes, 2, 4))
  assertIds(list, { 1, 5 })
  near(list[1].turn, 0)
  near(list[2].turn, 0)
end)

test("the node behind the car is not walked ahead", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local list = tunnels.watch(CAR, 1, 0, roads, roofedRange(nodes, 2, 4))
  local ahead = 0
  for _, e in ipairs(list) do
    if not e.behind then ahead = ahead + 1 end
  end
  assertEq(ahead, 1)
end)

test("a tunnel just under 3 km still gives its exit", function()
  local nodes, links = line(32, 99)
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local list = tunnels.watch(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 31))
  assertEq(list[1].pos.x, 31 * 99)
end)

test("a non-finite seed does not rotate", function()
  local nodes, links = fork()
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local roofed = roofedRange(nodes, 1, 2)
  assertEq(tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, math.huge)[1].id, 3)
  assertEq(tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, -math.huge)[1].id, 3)
  assertEq(tunnels.watch(v(0, 0, 0), 1, 0, roads, roofed, 0 / 0)[1].id, 3)
end)

test("a turn sums the angles along the path", function()
  local nodes = {
    [1] = { pos = v(0, 0, 0) },
    [2] = { pos = v(100, 0, 0) },
    [3] = { pos = v(200, 0, 0) },
    [4] = { pos = v(200, 100, 0) },
  }
  local links = { [1] = { [2] = {} }, [2] = { [1] = {}, [3] = {} }, [3] = { [2] = {}, [4] = {} }, [4] = { [3] = {} } }
  local roads = roadsOf(nodes, links, 1, 2, 2)
  local list = tunnels.watch(v(0, 0, 0), 1, 0, roads, roofedRange(nodes, 1, 3))
  assertEq(list[1].id, 4)
  near(list[1].turn, math.pi / 2)
  near(list[1].length, 300)
  assertEq(list[1].from, 3)
end)

test("a second walk with the same cache tests only the car's roof", function()
  local nodes, links = line(5, 100)
  local roads = roadsOf(nodes, links, 2, 3, 2)
  local set = { [2] = true, [3] = true, [4] = true }
  local inner = roofedIds(nodes, set)
  local n = 0
  local function roofed(pos)
    n = n + 1
    return inner(pos) or (pos.x >= 150 and pos.x <= 170)
  end
  local cache = {}
  assertEq(#tunnels.watch(v(150, 0, 0), 1, 0, roads, roofed, 0, cache), 2)
  assertEq(n, 1 + 5)
  n = 0
  assertEq(#tunnels.watch(v(160, 0, 0), 1, 0, roads, roofed, 0, cache), 2)
  assertEq(n, 1)
end)
