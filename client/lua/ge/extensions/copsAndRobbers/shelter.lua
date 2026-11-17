local M = {}

M.RANGE = 12
M.SPREAD = 3
M.CHECKS_TO_SWITCH = 2

local OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function M.roofed(pos, castUp)
  local function hit(p)
    local d = castUp(p, M.RANGE)
    return d ~= nil and d < M.RANGE
  end
  if not hit(pos) then return false end
  local function side(o)
    return hit(vec3(pos.x + o[1] * M.SPREAD, pos.y + o[2] * M.SPREAD, pos.z))
  end
  local across = side(OFFSETS[1]) or side(OFFSETS[2])
  local along = side(OFFSETS[3]) or side(OFFSETS[4])
  return across and along
end

local SIGHT_HEIGHT = 1.5
local SIGHT_REACH = 2
local SIGHT_SLACK = 0.5

function M.inSight(from, carPos, dirX, dirY, castRay)
  local z = carPos.z + SIGHT_HEIGHT
  local xs, ys = { carPos.x }, { carPos.y }
  local len = math.sqrt(dirX * dirX + dirY * dirY)
  if len >= 1e-6 then
    local ux, uy = dirX / len, dirY / len
    xs[2], ys[2] = carPos.x + ux * SIGHT_REACH, carPos.y + uy * SIGHT_REACH
    xs[3], ys[3] = carPos.x - ux * SIGHT_REACH, carPos.y - uy * SIGHT_REACH
  end
  for i = 1, #xs do
    local dx, dy, dz = xs[i] - from.x, ys[i] - from.y, z - from.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d <= SIGHT_SLACK then return true end
    local hit = tonumber(castRay(from, vec3(dx / d, dy / d, dz / d), d))
    if not (hit and hit < d - SIGHT_SLACK) then return true end
  end
  return false
end

function M.new()
  return { covered = false, pending = nil, count = 0 }
end

function M.step(state, now)
  if now == state.covered then
    state.pending, state.count = nil, 0
    return false
  end
  if state.pending ~= now then state.pending, state.count = now, 0 end
  state.count = state.count + 1
  if state.count < M.CHECKS_TO_SWITCH then return false end
  state.covered, state.pending, state.count = now, nil, 0
  return true
end

return M
