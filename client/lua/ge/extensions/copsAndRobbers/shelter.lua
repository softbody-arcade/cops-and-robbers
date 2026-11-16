local M = {}

M.RANGE = 12
M.SPREAD = 3
M.SIDES_NEEDED = 2
M.CHECKS_TO_SWITCH = 2

local OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function M.roofed(pos, castUp)
  local function hit(p)
    local d = castUp(p, M.RANGE)
    return d ~= nil and d < M.RANGE
  end
  if not hit(pos) then return false end
  local sides = 0
  for _, o in ipairs(OFFSETS) do
    if hit(vec3(pos.x + o[1] * M.SPREAD, pos.y + o[2] * M.SPREAD, pos.z)) then sides = sides + 1 end
  end
  return sides >= M.SIDES_NEEDED
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
