dofile("tests/env_stubs.lua")
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
_G.vec3 = _G.vec3 or function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
package.loaded["copsAndRobbers/beam"] = nil
local beam = require("copsAndRobbers/beam")

local STRENGTH = 0.2

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

local function finite(x) return x == x and x > -math.huge and x < math.huge end

local function slanted(elevation, height)
  local light = vec3(10, 20, 5 + height)
  local aim = vec3(10 + height / math.tan(math.rad(elevation)), 20, 5)
  return light, aim
end

local function axis(light, aim) return dist(light, aim) end

local function eachVertex(out, n, fn)
  for i = 1, n do
    local q = out[i]
    fn(q.a, q); fn(q.b, q); fn(q.c, q); fn(q.d, q)
  end
end

local function farthest(out, n, from)
  local worst = 0
  eachVertex(out, n, function(v) worst = math.max(worst, dist(v, from)) end)
  return worst
end

local function countCalls(out, n)
  local calls = 0
  beam.draw(out, n, function() calls = calls + 1 end, function(r, g, b, a) return { r, g, b, a } end)
  return calls
end

local function key(v) return string.format("%.6f %.6f %.6f", v.x, v.y, v.z) end

test("strength follows the round's weather, scaled by the light's brightness", function()
  assertNear(beam.strength("clear", 1), 0.06, 1e-12)
  assertNear(beam.strength("cloudy", 1), 0.12, 1e-12)
  assertNear(beam.strength("rain", 1), 0.2, 1e-12)
  assertNear(beam.strength(nil, 1), 0.06, 1e-12)
  assertNear(beam.strength("storm", 1), 0.06, 1e-12)
  assertNear(beam.strength("rain", 0.5), 0.1, 1e-12)
  assertNear(beam.strength("cloudy", 0.5), 0.06, 1e-12)
  assertEq(beam.strength("rain", -1), 0)
  assertNear(beam.strength("rain", 2), 0.2, 1e-12)
end)

test("one call per quad facing the camera, both windings without a camera", function()
  local light, aim = slanted(60, 50)
  local mid = vec3((light.x + aim.x) / 2, (light.y + aim.y) / 2, (light.z + aim.z) / 2)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, vec3(mid.x, mid.y + 100, mid.z), out)
  assertEq(n, beam.LAYERS * beam.SEGMENTS * beam.SIDES)
  assertEq(countCalls(out, n), 1200)
  for i = 1, n do assertEq(out[i].both, false) end
  n = beam.quads(light, aim, STRENGTH, nil, nil, out)
  assertEq(countCalls(out, n), 2400)
  for i = 1, n do assertEq(out[i].both, true) end
end)

test("with a camera every quad winds clockwise as seen from the camera, the side drawn", function()
  local light, aim = slanted(45, 50)
  local cam = vec3(aim.x - 30, aim.y + 80, aim.z + 10)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, cam, out)
  assertEq(n > 0, true)
  for i = 1, n do
    local q = out[i]
    local ex, ey, ez = q.c.x - q.a.x, q.c.y - q.a.y, q.c.z - q.a.z
    local fx, fy, fz = q.d.x - q.b.x, q.d.y - q.b.y, q.d.z - q.b.z
    local nx, ny, nz = ey * fz - ez * fy, ez * fx - ex * fz, ex * fy - ey * fx
    local toCam = (cam.x - q.a.x) * nx + (cam.y - q.a.y) * ny + (cam.z - q.a.z) * nz
    assertEq(toCam <= 0, true, tostring(i))
  end
end)

test("a vertical beam draws only finite vertices", function()
  local out = {}
  local n = beam.quads(vec3(10, 20, 55), vec3(10, 20, 5), STRENGTH, nil, nil, out)
  assertEq(countCalls(out, n), 2400)
  eachVertex(out, n, function(v)
    assertEq(finite(v.x) and finite(v.y) and finite(v.z), true)
  end)
end)

test("a 60 degree beam's far ring lies on the aim point's plane", function()
  local light, aim = slanted(60, 50)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, nil, out)
  local starts = {}
  for i = 1, n do
    starts[key(out[i].a)] = true
    starts[key(out[i].b)] = true
  end
  local far = 0
  for i = 1, n do
    for _, v in ipairs({ out[i].c, out[i].d }) do
      if not starts[key(v)] then
        far = far + 1
        assertNear(v.z, aim.z, 1e-6)
      end
    end
  end
  assertEq(far, 2 * beam.LAYERS * beam.SIDES)
end)

test("a low beam ends within twice the axis length", function()
  local light, aim = slanted(11, 60)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, nil, out)
  assertEq(n > 0, true)
  local worst = farthest(out, n, light)
  assertEq(worst <= 2 * axis(light, aim) + 1e-6, true, tostring(worst))
  assertEq(worst > 1.5 * axis(light, aim), true, tostring(worst))
end)

test("no drawn quad has a vertex within 6 m of the camera", function()
  local light, aim = slanted(60, 50)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, aim, out)
  assertEq(n > 0, true)
  eachVertex(out, n, function(v)
    assertEq(dist(v, aim) >= beam.NEAR, true, tostring(dist(v, aim)))
  end)
  assertEq(n < beam.LAYERS * beam.SEGMENTS * beam.SIDES, true)
end)

test("an occlusion hit at half the axis ends every side line there", function()
  for _, elevation in ipairs({ 60, 30, 11 }) do
    local light, aim = slanted(elevation, 50)
    local half = axis(light, aim) / 2
    local out = {}
    local n = beam.quads(light, aim, STRENGTH, half, nil, out)
    assertEq(n, beam.LAYERS * beam.SEGMENTS * beam.SIDES, tostring(elevation))
    local worst = farthest(out, n, light)
    assertEq(worst <= half + 1e-6, true, elevation .. " " .. worst)
    assertEq(worst > half - 0.01, true, elevation .. " " .. worst)
  end
end)

test("nothing to draw at strength 0 or with the light on the aim point", function()
  local light, aim = slanted(60, 50)
  local out = {}
  assertEq(beam.quads(light, aim, 0, nil, nil, out), 0)
  assertEq(beam.quads(aim, vec3(aim.x, aim.y, aim.z), STRENGTH, nil, nil, out), 0)
  assertEq(countCalls(out, 0), 0)
end)

test("one colour per alpha value in a draw", function()
  local light, aim = slanted(45, 50)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, vec3(aim.x - 10, aim.y + 12, aim.z + 20), out)
  local alphas, distinct = {}, 0
  for i = 1, n do
    if not alphas[out[i].alpha] then
      alphas[out[i].alpha] = true
      distinct = distinct + 1
    end
  end
  assertEq(distinct > 3, true, tostring(distinct))
  local made = 0
  local calls = beam.draw(out, n, function() end, function(r, g, b, a)
    made = made + 1
    assertEq(r, 217); assertEq(g, 235); assertEq(b, 255)
    return { a = a }
  end)
  assertEq(calls, n)
  assertEq(made, distinct)
  assertEq(made <= 11, true, tostring(made))
end)

test("a second call reuses the list's entry tables", function()
  local light, aim = slanted(30, 50)
  local out = {}
  local n = beam.quads(light, aim, STRENGTH, nil, vec3(aim.x, aim.y + 100, aim.z), out)
  local before, size = {}, #out
  for i = 1, size do before[i] = out[i] end
  local again = beam.quads(light, aim, STRENGTH, nil, vec3(aim.x, aim.y + 100, aim.z), out)
  assertEq(again, n)
  assertEq(#out, size)
  for i = 1, size do assertEq(out[i], before[i]) end
end)

test("a hit right at the light gives no beam and no NaN", function()
  local light, aim = slanted(60, 50)
  local out = {}
  assertEq(beam.quads(light, aim, STRENGTH, 0.1, nil, out), 0)
  assertEq(beam.quads(light, aim, STRENGTH, 1, nil, out), 0)
  assertEq(#out, 0)
end)
