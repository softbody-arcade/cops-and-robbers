local shelter = require("copsAndRobbers/shelter")

local M = {}

M.COVER_INTERVAL = 0.25
M.COVER_HEIGHT = 1.5
M.LIGHT_HEIGHT = 40
M.LIGHT_NAME = "cnr_heli_light"
M.ORBIT_RADIUS = 12
M.ORBIT_SPEED = 0.25
M.AIM_WOBBLE = 1.5

local FIELDS = {
  { "brightness", 80 }, { "range", 120 }, { "innerAngle", 24 }, { "outerAngle", 40 },
  { "color", "0.85 0.92 1 1" }, { "castShadows", "false" },
}

function M.new()
  return { phase = nil, reason = nil, endsAt = nil, cover = shelter.new(), sent = false, lastCheck = nil }
end

function M.set(state, d, clock)
  state.failed = nil
  if type(d) ~= "table" or type(d.phase) ~= "string" then
    state.phase, state.reason, state.endsAt = nil, nil, nil
    return
  end
  local seconds = tonumber(d.seconds)
  state.phase, state.reason = d.phase, d.reason
  state.endsAt = seconds and clock + seconds or nil
end

function M.tracking(state)
  return state.phase == "tracking"
end

function M.resetCover(state)
  state.cover, state.sent, state.lastCheck = shelter.new(), false, nil
end

function M.coverTick(state, clock, obj, castUp)
  if state.lastCheck and clock - state.lastCheck < M.COVER_INTERVAL then return nil end
  state.lastCheck = clock
  local p = obj:getPosition()
  local roofed = shelter.roofed(vec3(p.x, p.y, p.z + M.COVER_HEIGHT), castUp) and true or false
  if not state.sent then
    state.sent = true
    state.cover = { covered = roofed, pending = nil, count = 0 }
    return roofed
  end
  if shelter.step(state.cover, roofed) then return state.cover.covered end
  return nil
end

local function removeLight(state)
  local obj = scenetree.findObject(M.LIGHT_NAME)
  if obj then obj:delete() end
  state.light = nil
end

function M.lightPose(carPos, t)
  local a = M.ORBIT_SPEED * t
  local light = vec3(carPos.x + M.ORBIT_RADIUS * math.cos(a), carPos.y + M.ORBIT_RADIUS * math.sin(a), carPos.z + M.LIGHT_HEIGHT)
  local aim = vec3(carPos.x + M.AIM_WOBBLE * math.sin(1.3 * t), carPos.y + M.AIM_WOBBLE * math.cos(1.1 * t), carPos.z)
  return light, aim
end

local function aimLight(obj, lightPos, aimPos)
  if not quatFromDir then return end
  local q = quatFromDir(vec3(aimPos.x - lightPos.x, aimPos.y - lightPos.y, aimPos.z - lightPos.z), vec3(0, 0, 1))
  if q.toTorqueQuat then q = q:toTorqueQuat() end
  obj:setField("rotation", 0, q.x .. " " .. q.y .. " " .. q.z .. " " .. q.w)
end

local function createLight(state)
  local obj = createObject("SpotLight")
  if not obj then return false end
  for _, f in ipairs(FIELDS) do obj:setField(f[1], 0, tostring(f[2])) end
  obj.canSave = false
  obj:registerObject(M.LIGHT_NAME)
  if not scenetree.findObject(M.LIGHT_NAME) then
    obj:delete()
    log("E", "cnr_heli", "searchlight did not register")
    return false
  end
  scenetree.MissionGroup:addObject(obj)
  state.light = obj
  return true
end

local function placeLight(state, target, clock)
  local lightPos, aimPos = M.lightPose(target:getPosition(), clock or 0)
  state.light:setPosition(lightPos)
  pcall(aimLight, state.light, lightPos, aimPos)
end

function M.lightTick(state, target, night, clock)
  if M.tracking(state) and night and target and not state.failed then
    local ok = pcall(function()
      if not state.light or not scenetree.findObject(M.LIGHT_NAME) then
        if not createLight(state) then error("no light") end
      end
      placeLight(state, target, clock)
    end)
    if not ok then
      pcall(removeLight, state)
      state.failed = true
    end
  elseif state.light or scenetree.findObject(M.LIGHT_NAME) then
    pcall(removeLight, state)
  end
end

function M.clear(state)
  pcall(removeLight, state)
  state.phase, state.reason, state.endsAt, state.failed = nil, nil, nil, nil
  M.resetCover(state)
end

return M
