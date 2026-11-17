local M = {}

M.STRENGTH = { clear = 0.06, cloudy = 0.12, rain = 0.2 }
M.DEFAULT_STRENGTH = 0.06
M.LAYERS = 5
M.SEGMENTS = 10
M.SIDES = 24
M.LAMP = 0.4
M.GROUND = 0.5
M.NEAR = 6
M.FAR = 18
M.HALF_ANGLE = 8
M.MAX_LENGTH_FACTOR = 2
M.MIN_LENGTH = 1
M.VERTICAL = 0.9
M.RAY_INTERVAL = 0.25
M.COLOR = { 217, 235, 255 }

local ringX, ringY, ringZ = {}, {}, {}
local verts, camDist = {}, {}

function M.strength(weather, bright)
  return (M.STRENGTH[weather] or M.DEFAULT_STRENGTH) * math.max(0, math.min(1, bright))
end

local function basis(wx, wy, wz)
  local hx, hz = 0, 1
  if math.abs(wz) > M.VERTICAL then hx, hz = 1, 0 end
  local ux, uy, uz = -hz * wy, hz * wx - hx * wz, hx * wy
  local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
  ux, uy, uz = ux / ul, uy / ul, uz / ul
  return ux, uy, uz, wy * uz - wz * uy, wz * ux - wx * uz, wx * uy - wy * ux
end

local function buildLayer(light, aimZ, wx, wy, wz, lamp, tan, reach, camPos)
  local sides, segments = M.SIDES, M.SEGMENTS
  local k = 1 + tan * tan
  local tReach = (math.sqrt(k * reach * reach - lamp * lamp) - lamp * tan) / k
  for side = 1, sides do
    local rx, ry, rz = ringX[side], ringY[side], ringZ[side]
    local sx, sy, sz = light.x + lamp * rx, light.y + lamp * ry, light.z + lamp * rz
    local dx, dy, dz = wx + tan * rx, wy + tan * ry, wz + tan * rz
    local tEnd = tReach
    if dz ~= 0 then
      local tPlane = (aimZ - sz) / dz
      if tPlane > 0 and tPlane < tEnd then tEnd = tPlane end
    end
    for j = 0, segments do
      local t = tEnd * j / segments
      local x, y, z = sx + dx * t, sy + dy * t, sz + dz * t
      local i = j * sides + side
      verts[i] = vec3(x, y, z)
      if camPos then
        local cx, cy, cz = x - camPos.x, y - camPos.y, z - camPos.z
        camDist[i] = math.sqrt(cx * cx + cy * cy + cz * cz)
      end
    end
  end
end

local function facesAway(a, b, c, d, camPos)
  local ex, ey, ez = c.x - a.x, c.y - a.y, c.z - a.z
  local fx, fy, fz = d.x - b.x, d.y - b.y, d.z - b.z
  local nx, ny, nz = ey * fz - ez * fy, ez * fx - ex * fz, ex * fy - ey * fx
  return (camPos.x - a.x) * nx + (camPos.y - a.y) * ny + (camPos.z - a.z) * nz > 0
end

local function addQuads(out, n, strength, camPos)
  local sides, segments, span = M.SIDES, M.SEGMENTS, M.FAR - M.NEAR
  for j = 0, segments - 1 do
    local full = 255 * strength * (1 - (1 - M.GROUND) * (j + 0.5) / segments) / M.LAYERS
    for side = 1, sides do
      local ia = j * sides + side
      local ib = j * sides + side % sides + 1
      local ic, id = ib + sides, ia + sides
      local near = 1
      if camPos then
        local m = math.min(camDist[ia], camDist[ib], camDist[ic], camDist[id])
        near = math.max(0, math.min(1, (m - M.NEAR) / span))
      end
      local alpha = math.floor(full * near + 0.5)
      if alpha >= 1 then
        local a, b, c, d = verts[ia], verts[ib], verts[ic], verts[id]
        if camPos and facesAway(a, b, c, d, camPos) then b, d = d, b end
        n = n + 1
        local e = out[n]
        if not e then
          e = {}
          out[n] = e
        end
        e.a, e.b, e.c, e.d, e.alpha, e.both = a, b, c, d, alpha, not camPos
      end
    end
  end
  return n
end

function M.quads(lightPos, aimPos, strength, hitDist, camPos, out)
  local ax, ay, az = aimPos.x - lightPos.x, aimPos.y - lightPos.y, aimPos.z - lightPos.z
  local axisLen = math.sqrt(ax * ax + ay * ay + az * az)
  if not (axisLen > 0) or not (strength > 0) then return 0 end
  local reach = M.MAX_LENGTH_FACTOR * axisLen
  if hitDist and hitDist < reach then reach = hitDist end
  if not (reach > M.MIN_LENGTH) then return 0 end
  local wx, wy, wz = ax / axisLen, ay / axisLen, az / axisLen
  local ux, uy, uz, vx, vy, vz = basis(wx, wy, wz)
  for side = 1, M.SIDES do
    local angle = 2 * math.pi * (side - 1) / M.SIDES
    local cs, sn = math.cos(angle), math.sin(angle)
    ringX[side], ringY[side], ringZ[side] = cs * ux + sn * vx, cs * uy + sn * vy, cs * uz + sn * vz
  end
  local n = 0
  for layer = 1, M.LAYERS do
    local share = layer / M.LAYERS
    buildLayer(lightPos, aimPos.z, wx, wy, wz, M.LAMP * share, math.tan(math.rad(M.HALF_ANGLE * share)), reach, camPos)
    n = addQuads(out, n, strength, camPos)
  end
  return n
end

function M.draw(list, n, drawQuad, colorFn)
  local colors, calls = {}, 0
  local r, g, b = M.COLOR[1], M.COLOR[2], M.COLOR[3]
  for i = 1, n do
    local q = list[i]
    local clr = colors[q.alpha]
    if not clr then
      clr = colorFn(r, g, b, q.alpha)
      colors[q.alpha] = clr
    end
    drawQuad(q.a, q.b, q.c, q.d, clr)
    calls = calls + 1
    if q.both then
      drawQuad(q.a, q.d, q.c, q.b, clr)
      calls = calls + 1
    end
  end
  return calls
end

return M
