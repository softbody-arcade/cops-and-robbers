local M = {}

local function isNum(v)
  return type(v) == "number" and v == v
end

function M.toVec(t)
  if type(t) ~= "table" then return nil end
  local x, y, z = t.x, t.y, t.z
  if x == nil then x, y, z = t[1], t[2], t[3] end
  if not (isNum(x) and isNum(y) and isNum(z)) then return nil end
  return { x = x, y = y, z = z }
end

function M.dist(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.speedKmh(vel)
  return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) * 3.6
end

return M
