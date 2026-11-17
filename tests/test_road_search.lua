local roadSearch = require("copsAndRobbers/roadSearch")

local function v(x, y, z) return { x = x, y = y, z = z } end
_G.vec3 = _G.vec3 or v

local function near(a, b) assertEq(math.abs(a - b) < 1e-6, true, tostring(a) .. " vs " .. tostring(b)) end

local function graph()
  local g = { nodes = {}, links = {} }
  function g.node(id, x, y, z)
    g.nodes[id] = { pos = v(x, y, z or 0) }
    g.links[id] = g.links[id] or {}
  end
  function g.link(a, b)
    g.links[a][b] = { len = 1 }
    g.links[b][a] = { len = 1 }
  end
  return g
end

local function lineGraph(count, spacing)
  local g = graph()
  for i = 1, count do g.node(i, (i - 1) * spacing, 0) end
  for i = 1, count - 1 do g.link(i, i + 1) end
  return g
end

local function roadsOf(g, n1, n2, dist)
  return { nodes = g.nodes, links = g.links, closest = function() return n1, n2, dist end }
end

local function lastPoint(route) return route.points[#route.points] end

test("the ahead route goes straight through a crossroads", function()
  local g = lineGraph(5, 100)
  g.node(10, 200, 100)
  g.node(11, 200, -100)
  g.link(3, 10)
  g.link(3, 11)
  local routes = roadSearch.routes(v(50, 0, 0), 1, 0, roadsOf(g, 1, 2, 0), 0)
  local r = routes[1]
  assertEq(r.points[1].x, 50)
  assertEq(r.points[2].x, 100)
  assertEq(r.points[3].x, 200)
  assertEq(r.points[4].x, 300)
  assertEq(r.points[4].y, 0)
  near(r.length, 350)
  near(r.dist[4], 250)
end)

test("ties at a symmetric fork go by id, then the seed", function()
  local g = graph()
  g.node(1, 0, 0)
  g.node(2, 100, 0)
  g.node("a", 200, 100)
  g.node("b", 200, -100)
  g.link(1, 2)
  g.link(2, "a")
  g.link(2, "b")
  local function third(seed)
    local routes = roadsOf(g, 1, 2, 0)
    local r = roadSearch.routes(v(0, 0, 0), 1, 0, routes, seed)
    return r[1].points[3].y, r[2] and r[2].points[2].y
  end
  local a0, alt0 = third(0)
  local a1, alt1 = third(1)
  assertEq(a0, 100)
  assertEq(alt0, -100)
  assertEq(a1, -100)
  assertEq(alt1, 100)
  assertEq((third(2)), 100)
end)

test("the alternative is the other branch at the first junction within 500 m", function()
  local function build(junction)
    local g = lineGraph(30, 100)
    g.node(100, junction * 100, 100)
    g.node(101, junction * 100, 200)
    g.link(junction + 1, 100)
    g.link(100, 101)
    return g
  end
  local g = build(3)
  local routes = roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, 1, 2, 0), 0)
  local alt = routes[2]
  assertEq(alt.points[1].x, 300)
  assertEq(alt.points[1].y, 0)
  assertEq(alt.points[2].y, 100)
  assertEq(alt.points[3].y, 200)
  local far = build(6)
  local list = roadSearch.routes(v(50, 0, 0), 1, 0, roadsOf(far, 1, 2, 0), 0)
  assertEq(#list, 2)
  assertEq(list[2].points[2].x, 0)
end)

test("the back route walks the other way", function()
  local g = lineGraph(9, 100)
  local routes = roadSearch.routes(v(450, 0, 0), 1, 0, roadsOf(g, 5, 6, 0), 0)
  assertEq(routes[1].points[2].x, 500)
  local back = routes[#routes]
  assertEq(back.points[1].x, 450)
  assertEq(back.points[2].x, 400)
  assertEq(back.points[3].x, 300)
end)

test("without the back route only ahead and the alternative are built", function()
  local g = lineGraph(30, 100)
  g.node(100, 300, 100)
  g.link(4, 100)
  local routes = roadSearch.routes(v(150, 0, 0), 1, 0, roadsOf(g, 2, 3, 0), 0, true)
  assertEq(#routes, 2)
  assertEq(routes[1].points[2].x, 200)
  assertEq(routes[2].points[2].y, 100)
  assertEq(#roadSearch.routes(v(150, 0, 0), 1, 0, roadsOf(g, 2, 3, 0), 0), 3)
end)

test("the caps", function()
  local g = lineGraph(51, 100)
  g.node(100, 2600, 100)
  g.link(27, 100)
  for i = 1, 20 do
    g.node(100 + i, 2600, 100 + i * 100)
    g.link(99 + i, 100 + i)
  end
  local routes = roadSearch.routes(v(2500, 0, 0), 1, 0, roadsOf(g, 26, 27, 0), 0)
  assertEq(#routes, 3)
  near(routes[1].length, 2500)
  near(lastPoint(routes[1]).x, 5000)
  near(routes[2].length, 1500)
  near(routes[3].length, 1000)
  near(lastPoint(routes[3]).x, 1500)

  local dense = lineGraph(400, 10)
  local list = roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(dense, 2, 1, 0), 0)
  assertEq(#list[1].points, 200)
  near(list[1].length, 1990)
end)

test("no road within 15 m means no routes", function()
  local g = lineGraph(5, 100)
  assertEq(#roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, 1, 2, 16), 0), 0)
  assertEq(#roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, 1, 2, nil), 0), 0)
  assertEq(#roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, nil, nil, 0), 0), 0)
  assertEq(#roadSearch.routes(v(0, 0, 0), 1, 0, nil, 0), 0)
  assertEq(#roadSearch.routes(v(0, 0, 0), 1, 0, { closest = function() return 1, 2, 0 end }, 0), 0)
end)

test("the same input gives the same routes", function()
  local g = lineGraph(30, 100)
  g.node(100, 500, 100)
  g.link(6, 100)
  local a = roadSearch.routes(v(120, 0, 0), 1, 0, roadsOf(g, 1, 2, 0), 3)
  local b = roadSearch.routes(v(120, 0, 0), 1, 0, roadsOf(g, 1, 2, 0), 3)
  assertEq(#a, #b)
  for i = 1, #a do
    assertEq(#a[i].points, #b[i].points)
    for j = 1, #a[i].points do
      assertEq(a[i].points[j].x, b[i].points[j].x)
      assertEq(a[i].points[j].y, b[i].points[j].y)
      assertEq(a[i].dist[j], b[i].dist[j])
    end
  end
end)

test("a ring road ends", function()
  local g = graph()
  for i = 1, 20 do
    local a = 2 * math.pi * i / 20
    g.node(i, 300 * math.cos(a), 300 * math.sin(a))
  end
  for i = 1, 20 do g.link(i, i % 20 + 1) end
  local routes = roadSearch.routes(g.nodes[1].pos, 0, 1, roadsOf(g, 1, 2, 0), 0)
  assertEq(#routes[1].points <= 20, true)
end)

local function straightRun(length)
  local route = { points = { v(0, 0, 5), v(length, 0, 5) }, dist = { 0, length }, length = length }
  return route
end

test("the search point moves at 45 m/s and waits within 150 m", function()
  local run = roadSearch.newRun({ straightRun(100), straightRun(200) })
  local pos, vel = roadSearch.step(run, v(0, 0, 100), 1)
  near(pos.x, 45)
  near(vel.x, 45)
  pos = roadSearch.step(run, v(0, 0, 100), 1)
  near(pos.x, 90)
  pos = roadSearch.step(run, v(0, 0, 100), 1)
  near(pos.x, 100)
  pos, vel = roadSearch.step(run, v(300, 0, 100), 1)
  near(pos.x, 0)
  near(vel.x, 0)
  pos, vel = roadSearch.step(run, v(300, 0, 100), 1)
  near(pos.x, 0)
  near(vel.x, 0)
  pos, vel = roadSearch.step(run, v(-140, 0, 400), 1)
  near(pos.x, 45)
  near(vel.x, 45)
  roadSearch.step(run, v(0, 0, 0), 5)
  assertEq(roadSearch.step(run, v(0, 0, 0), 1), nil)
end)

test("routes under 1 m are dropped", function()
  local run = roadSearch.newRun({ straightRun(0.5), straightRun(100) })
  local pos = roadSearch.step(run, v(0, 0, 0), 1)
  near(pos.x, 45)
  assertEq(roadSearch.step(roadSearch.newRun({}), v(0, 0, 0), 1), nil)
end)

test("aimPoint is 60 m ahead with a 15 m sweep across", function()
  local run = roadSearch.newRun({ straightRun(1000) })
  roadSearch.step(run, v(0, 0, 0), 100 / 45)
  local x, y, z = roadSearch.aimPoint(run, 0.75)
  near(x, 160)
  near(y, 15)
  near(z, 5)
  x, y = roadSearch.aimPoint(run, 0)
  near(x, 160)
  near(y, 0)
end)

test("while it waits, aimPoint is 60 m from the given point toward the next start, with the sweep across", function()
  local run = roadSearch.newRun({ straightRun(100), straightRun(200) })
  roadSearch.step(run, v(0, 0, 100), 3)
  roadSearch.step(run, v(0, 1000, 100), 1)
  assertEq(run.index, 2)
  assertEq(run.waiting, true)
  local x, y, z = roadSearch.aimPoint(run, 0, v(0, 1000, 7))
  near(x, 0)
  near(y, 940)
  near(z, 7)
  x, y, z = roadSearch.aimPoint(run, 0.75, v(0, 1000, 7))
  near(x, 15)
  near(y, 940)
  near(z, 7)
  x, y, z = roadSearch.aimPoint(run, 0.75, v(0, 0, 7))
  for _, n in ipairs({ x, y, z }) do
    assertEq(n == n and n ~= math.huge and n ~= -math.huge, true, tostring(n))
  end
end)

test("aimPoint clamps at the route end", function()
  local run = roadSearch.newRun({ straightRun(100) })
  roadSearch.step(run, v(0, 0, 0), 2)
  local x = roadSearch.aimPoint(run, 0)
  near(x, 100)
end)

test("shift moves the routes", function()
  local run = roadSearch.newRun({ straightRun(100) })
  roadSearch.shift(run, 10, 20, 30)
  local pos = roadSearch.step(run, v(0, 0, 0), 1)
  near(pos.x, 55)
  near(pos.y, 20)
  near(pos.z, 35)
end)

test("a first step of 0 s from an origin on a node gives finite numbers", function()
  local g = lineGraph(5, 100)
  local routes = roadSearch.routes(v(100, 0, 0), -1, 0, roadsOf(g, 2, 3, 0), 0)
  assertEq(routes[1].dist[2], 0)
  local run = roadSearch.newRun(routes)
  local pos, vel = roadSearch.step(run, v(0, 0, 100), 0)
  for _, n in ipairs({ pos.x, pos.y, pos.z, vel.x, vel.y, vel.z }) do
    assertEq(n == n and n ~= math.huge and n ~= -math.huge, true, tostring(n))
  end
  near(pos.x, 100)
  pos = roadSearch.step(run, v(0, 0, 100), 1)
  near(pos.x, 55)
end)

test("noBack never walks into the road behind the origin when closest is a side road", function()
  local g = graph()
  g.node("t0", -200, 0)
  g.node("t1", -100, 0)
  g.node("p", 0, 0)
  g.node("s1", 10, -50)
  g.node("s2", 10, 50)
  g.link("t0", "t1")
  g.link("t1", "p")
  g.link("p", "s1")
  g.link("s1", "s2")
  local routes = roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, "s1", "s2", 5), 0, true)
  assertEq(#routes > 0, true)
  for _, route in ipairs(routes) do
    for _, p in ipairs(route.points) do assertEq(p.x >= -1, true, "x " .. tostring(p.x)) end
  end
  local back = roadSearch.routes(v(0, 0, 0), 1, 0, roadsOf(g, "s1", "s2", 5), 0)
  local reaches = false
  for _, route in ipairs(back) do
    for _, p in ipairs(route.points) do if p.x < -1 then reaches = true end end
  end
  assertEq(reaches, true)
end)
