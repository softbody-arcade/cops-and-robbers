local M = {}

local EYE_HEIGHT = 1.2
local TARGET_HEIGHT = 1.0
local TARGET_SPREAD = 2
local CLEAR_MARGIN = 0.5
local KEEPALIVE_SECONDS = 5

local function read(getter, ...)
  if type(getter) ~= "function" then return nil end
  local ok, value = pcall(getter, ...)
  if ok then return value end
end

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function vector(value)
  local kind = type(value)
  if (kind == "table" or kind == "userdata" or kind == "cdata") and finite(value.x) and finite(value.y) and finite(value.z) then
    return vec3(value.x, value.y, value.z)
  end
end

function M.position(car)
  return vector(car and read(car.getPosition, car))
end

function M.heading(car)
  return vector(car and read(car.getDirectionVector, car))
end

function M.lookDirection(cop, useAttachedCamera)
  local forward = M.heading(cop)
  if useAttachedCamera and cop and read(commands and commands.isFreeCamera) == false then
    local seat = read(getPlayerVehicle, 0)
    if seat and seat:getID() == cop:getID() then
      local mode = read(core_camera and core_camera.getActiveCamName, 0)
      if type(mode) == "string" and (mode == "orbit" or mode == "chase" or mode == "driver"
          or mode:match("^occupant%.") or mode:match("^onboard%.")) then
        local look = vector(read(core_camera.getForward))
        if look and look.x * look.x + look.y * look.y > 1e-6 then return look, forward end
      end
    end
  end
  return forward, forward
end

function M.targetCenter(runnerPos)
  return runnerPos + vec3(0, 0, TARGET_HEIGHT)
end

function M.distance(eyePos, center)
  return (center - (eyePos + vec3(0, 0, EYE_HEIGHT))):length()
end

local function clear(cast, origin, direction, length)
  local hit = read(cast, origin, direction, length)
  return finite(hit) and hit >= 0 and hit >= length - CLEAR_MARGIN
end

function M.visible(eyePos, runnerPos, runnerDir, maxMeters, cast)
  eyePos, runnerPos = vector(eyePos), vector(runnerPos)
  if not eyePos or not runnerPos or not finite(maxMeters) or type(cast) ~= "function" then return false end
  local eye = eyePos + vec3(0, 0, EYE_HEIGHT)
  local center = M.targetCenter(runnerPos)
  local dist = M.distance(eyePos, center)
  if maxMeters <= 0 or not finite(dist) or dist > maxMeters then return false, dist end
  local heading = vector(runnerDir)
  local along = heading and vec3(heading.x, heading.y, 0) or vec3(0, 0, 0)
  if along:length() > 1e-3 then along = along:normalized() * TARGET_SPREAD end
  for _, target in ipairs({ center, center + along, center - along }) do
    local delta = target - eye
    local len = delta:length()
    local dir = len > 0 and delta / len or vec3(0, 0, 1)
    if clear(cast, eye, dir, len) and clear(cast, target, dir * -1, len) then return true, dist end
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
