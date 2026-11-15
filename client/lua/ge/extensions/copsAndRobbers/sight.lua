local M = {}

local EYE_HEIGHT = 1.2
local TARGET_HEIGHT = 1.0
local TARGET_SPREAD = 2
local CLEAR_MARGIN = 0.5
local KEEPALIVE_SECONDS = 5

function M.visible(eyePos, runnerPos, runnerDir, maxMeters, cast)
  local eye = eyePos + vec3(0, 0, EYE_HEIGHT)
  local center = runnerPos + vec3(0, 0, TARGET_HEIGHT)
  local dist = (center - eye):length()
  if maxMeters <= 0 or dist > maxMeters then return false, dist end
  local along = runnerDir and vec3(runnerDir.x, runnerDir.y, 0) or vec3(0, 0, 0)
  if along:length() > 1e-3 then along = along:normalized() * TARGET_SPREAD end
  for _, target in ipairs({ center, center + along, center - along }) do
    local delta = target - eye
    local len = delta:length()
    if len < 1e-3 or cast(eye, delta / len, len) >= len - CLEAR_MARGIN then return true, dist end
  end
  return false, dist
end

function M.new()
  return { seen = nil, sentAt = -math.huge }
end

function M.step(state, clock, seen)
  if seen == state.seen and clock - state.sentAt < KEEPALIVE_SECONDS then return false end
  state.seen = seen
  state.sentAt = clock
  return true
end

return M
