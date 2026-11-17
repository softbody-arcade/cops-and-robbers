dofile("tests/env_stubs.lua")
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
    assertEq(toCam * beam.FRONT <= 0, true, tostring(i))
  end
end)

test("with FRONT = -1 every drawn quad faces the other way", function()
  local light, aim = slanted(45, 50)
  local cam = vec3(aim.x - 30, aim.y + 80, aim.z + 10)
  beam.FRONT = -1
  local ok, err = pcall(function()
    local out = {}
    local n = beam.quads(light, aim, STRENGTH, nil, cam, out)
    assertEq(n > 0, true)
    for i = 1, n do
      local q = out[i]
      local ex, ey, ez = q.c.x - q.a.x, q.c.y - q.a.y, q.c.z - q.a.z
      local fx, fy, fz = q.d.x - q.b.x, q.d.y - q.b.y, q.d.z - q.b.z
      local nx, ny, nz = ey * fz - ez * fy, ez * fx - ex * fz, ex * fy - ey * fx
      local toCam = (cam.x - q.a.x) * nx + (cam.y - q.a.y) * ny + (cam.z - q.a.z) * nz
      assertEq(toCam >= 0, true, tostring(i))
    end
  end)
  beam.FRONT = 1
  if not ok then error(err, 0) end
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

local function triangleDist2(p, a, b, c)
  local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
  local acx, acy, acz = c.x - a.x, c.y - a.y, c.z - a.z
  local function at(v, w)
    local x, y, z = a.x + abx * v + acx * w - p.x, a.y + aby * v + acy * w - p.y, a.z + abz * v + acz * w - p.z
    return x * x + y * y + z * z
  end
  local apx, apy, apz = p.x - a.x, p.y - a.y, p.z - a.z
  local d1, d2 = abx * apx + aby * apy + abz * apz, acx * apx + acy * apy + acz * apz
  if d1 <= 0 and d2 <= 0 then return at(0, 0) end
  local bpx, bpy, bpz = p.x - b.x, p.y - b.y, p.z - b.z
  local d3, d4 = abx * bpx + aby * bpy + abz * bpz, acx * bpx + acy * bpy + acz * bpz
  if d3 >= 0 and d4 <= d3 then return at(1, 0) end
  local vc = d1 * d4 - d3 * d2
  if vc <= 0 and d1 >= 0 and d3 <= 0 then return at(d1 / (d1 - d3), 0) end
  local cpx, cpy, cpz = p.x - c.x, p.y - c.y, p.z - c.z
  local d5, d6 = abx * cpx + aby * cpy + abz * cpz, acx * cpx + acy * cpy + acz * cpz
  if d6 >= 0 and d5 <= d6 then return at(0, 1) end
  local vb = d5 * d2 - d1 * d6
  if vb <= 0 and d2 >= 0 and d6 <= 0 then return at(0, d2 / (d2 - d6)) end
  local va = d3 * d6 - d5 * d4
  if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0 then
    local w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
    return at(1 - w, w)
  end
  local sum = va + vb + vc
  return at(vb / sum, vc / sum)
end

local function surfaceDist(p, q)
  return math.sqrt(math.min(triangleDist2(p, q.a, q.b, q.c), triangleDist2(p, q.a, q.c, q.d)))
end

local function boxReaches(p, q, r)
  local a, b, c, d = q.a, q.b, q.c, q.d
  local lo, hi = p.z - r, p.z + r
  if (a.z > hi and b.z > hi and c.z > hi and d.z > hi) or (a.z < lo and b.z < lo and c.z < lo and d.z < lo) then return false end
  lo, hi = p.x - r, p.x + r
  if (a.x > hi and b.x > hi and c.x > hi and d.x > hi) or (a.x < lo and b.x < lo and c.x < lo and d.x < lo) then return false end
  lo, hi = p.y - r, p.y + r
  return not ((a.y > hi and b.y > hi and c.y > hi and d.y > hi) or (a.y < lo and b.y < lo and c.y < lo and d.y < lo))
end

local function nearestDrawn(light, aim, cam, out)
  local n = beam.quads(light, aim, STRENGTH, nil, cam, out)
  local nearest = math.huge
  for i = 1, n do
    local q = out[i]
    if boxReaches(cam, q, beam.NEAR) then nearest = math.min(nearest, surfaceDist(cam, q)) end
  end
  return nearest, n
end

test("no drawn quad's surface comes within 6 m of a camera at the aim point", function()
  local light, aim = slanted(60, 50)
  local nearest, n = nearestDrawn(light, aim, aim, {})
  assertEq(n > 0, true)
  assertEq(nearest >= beam.NEAR, true, tostring(nearest))
  assertEq(n < beam.LAYERS * beam.SEGMENTS * beam.SIDES, true)
end)

local function centre(q)
  return vec3((q.a.x + q.b.x + q.c.x + q.d.x) / 4, (q.a.y + q.b.y + q.c.y + q.d.y) / 4, (q.a.z + q.b.z + q.c.z + q.d.z) / 4)
end

local function widestNearGround(out, n, groundZ)
  local best, found = -1, nil
  for i = 1, n do
    local q = out[i]
    if math.min(q.a.z, q.b.z, q.c.z, q.d.z) < groundZ + 1e-6 then
      local c = centre(q)
      local m = math.min(dist(c, q.a), dist(c, q.b), dist(c, q.c), dist(c, q.d))
      if m > best then best, found = m, q end
    end
  end
  return found, best
end

local function longestSideLine(out, n)
  local best, found = -1, nil
  for i = 1, n do
    local q = out[i]
    if dist(q.a, q.d) > best then best, found = dist(q.a, q.d), q end
  end
  return found, best
end

test("no drawn quad's surface comes within 6 m of a camera inside a long or sheared low-beam quad", function()
  for _, beamCase in ipairs({ { 11, 60 }, { 8, 400 * math.sin(math.rad(8)) } }) do
    local light, aim = slanted(beamCase[1], beamCase[2])
    local plain = {}
    local all = beam.quads(light, aim, STRENGTH, nil, nil, plain)
    local wide, wideReach = widestNearGround(plain, all, aim.z)
    local long, longReach = longestSideLine(plain, all)
    assertEq(wideReach > 18 and longReach > 36, true, beamCase[1] .. " " .. wideReach .. " " .. longReach)
    local wc = centre(wide)
    local la, ld = long.a, long.d
    for _, cam in ipairs({
      vec3(wc.x, wc.y, wc.z + 0.5),
      vec3((la.x + ld.x) / 2, (la.y + ld.y) / 2, (la.z + ld.z) / 2 + 0.5),
    }) do
      local nearest, n = nearestDrawn(light, aim, cam, {})
      assertEq(n > 0, true)
      assertEq(nearest >= beam.NEAR - 1e-6, true, beamCase[1] .. " " .. nearest)
    end
  end
end)

test("no drawn quad's surface comes within 6 m of a camera on the road anywhere under the beam, up to 380 m past the spot", function()
  local grid = 16
  for _, beamCase in ipairs({ { 13, 80 }, { 18, 80 }, { 16, 70 }, { 11.3, 78 }, { 60, 50 } }) do
    local light, aim = slanted(beamCase[1], beamCase[2])
    local plain = {}
    local all = beam.quads(light, aim, STRENGTH, nil, nil, plain)
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    eachVertex(plain, all, function(v)
      if v.z < aim.z + 1e-6 then
        minX, maxX = math.min(minX, v.x), math.max(maxX, v.x)
        minY, maxY = math.min(minY, v.y), math.max(maxY, v.y)
      end
    end)
    if beamCase[1] < 20 then assertEq(maxX - aim.x > 200, true, beamCase[1] .. " " .. (maxX - aim.x)) end
    local out = {}
    for _, height in ipairs({ 0.5, 2 }) do
      for gx = 0, grid do
        for gy = 0, grid do
          local cam = vec3(minX + (maxX - minX) * gx / grid, minY + (maxY - minY) * gy / grid, aim.z + height)
          local nearest = nearestDrawn(light, aim, cam, out)
          assertEq(nearest >= beam.NEAR - 1e-6, true,
            string.format("%s/%s at (%.1f, %.1f, %.1f): %.2f", beamCase[1], beamCase[2], cam.x, cam.y, cam.z, nearest))
        end
      end
    end
  end
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
