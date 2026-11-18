local strikes = require("copsAndRobbers/strikes")

local M = {}
local LIGHT_NAME = "cnr_lightning_flash"
local SOUND_SLOTS = 3
local BOLT_RANGE = 4000
local MAIN_WIDTH, BRANCH_WIDTH, BRANCH_FADE = 4, 2, 45
local lineInstance

function M.new()
  return {visuals = {}, pending = {}, playing = {}, logged = {}}
end

local function remove(obj)
  if obj then pcall(function() obj:delete() end) end
end

function M.hasVisualTail(s)
  return #s.visuals > 0
end

function M.hide(s)
  remove(s.light)
  s.light, s.enabled = nil, nil
  if M.hasVisualTail(s) then s.visuals = {} end
end

function M.clear(s)
  M.hide(s)
  for _, slot in pairs(s.playing) do remove(slot.obj) end
  s.seed, s.cursor = nil, nil
  s.pending, s.playing, s.logged = {}, {}, {}
end

local function report(s, part, err)
  if s.logged[part] then return end
  s.logged[part] = true
  log("E", "cnr_lightning", part .. ": " .. tostring(err))
end

local function create(s, class, name, configure, arrival)
  local obj
  local ok, err = pcall(function()
    obj = createObject(class)
    if class == "SFXEmitter" then obj = assert(Sim.upcast(obj)) end
    configure(obj, arrival)
    obj.canSave = false
    obj:registerObject(name)
    assert(scenetree.findObject(name), name .. " did not register")
    scenetree.MissionGroup:addObject(obj)
    if arrival then
      obj:setVolumePitchCT(arrival.volume, 1, 0, 0)
      obj:play()
    end
  end)
  if ok then return obj end
  remove(obj)
  report(s, class, err)
end

local function emitterFields(obj, arrival)
  obj:setField("fileName", 0, arrival.clip.file)
  obj:setField("is3D", 0, "0")
  obj:setField("isLooping", 0, "0")
end

local function reapSounds(s, now)
  for index, slot in pairs(s.playing) do
    if now >= slot.endsAt then
      remove(slot.obj)
      s.playing[index] = nil
    end
  end
end

local function serviceSound(s, now)
  while s.pending[1] and s.pending[1].dueAt <= now do
    local arrival = table.remove(s.pending, 1)
    reapSounds(s, arrival.dueAt)
    for index = 1, SOUND_SLOTS do
      if not s.playing[index] then
        local obj = create(s, "SFXEmitter", "cnr_thunder_" .. index, emitterFields, arrival)
        if obj then s.playing[index] = {obj = obj, endsAt = now + arrival.clip.seconds} end
        break
      end
    end
  end
  reapSounds(s, now)
end

local function lightFields(obj)
  obj:setField("radius", 0, "1500")
  obj:setField("color", 0, "0.75 0.82 1 1")
  obj:setField("castShadows", 0, "0")
end

local function updateLight(s, cam, strength)
  if strength > 0 then
    if not s.light then s.light = create(s, "PointLight", LIGHT_NAME, lightFields) end
    if not s.light then return end
    s.light:setPosition(vec3(cam.x, cam.y, cam.z + 300))
  elseif not s.enabled then
    return
  end
  s.enabled = strength > 0
  s.light:setField("isEnabled", 0, s.enabled and "1" or "0")
  s.light:setField("brightness", 0, tostring(strength))
  s.light:setField("intensity", 0, tostring(strength))
  s.light:postApply()
end

local function getCamera()
  if not (core_camera and core_camera.getPosition) then return end
  local ok, pos = pcall(core_camera.getPosition)
  if ok then return pos end
end

local function landingAt(event, ref)
  local angle = math.rad(event.bearing)
  local x = ref.x + event.range * math.sin(angle)
  local y = ref.y + event.range * math.cos(angle)
  local z = ref.z
  if castRayStatic then
    local ok, hit = pcall(castRayStatic, vec3(x, y, 2500), vec3(0, 0, -1), 5000)
    if ok and type(hit) == "number" and hit >= 0 and hit < 5000 then z = 2500 - hit end
  end
  return vec3(x, y, z)
end

local function capture(s, event, ref, cam, visible, now)
  local landing = landingAt(event, ref)
  local dx, dy, dz = landing.x - cam.x, landing.y - cam.y, landing.z - cam.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  local clip, delay, volume = strikes.sound(event.soundRoll, distance)
  local arrival = {dueAt = event.at + delay, clip = clip, volume = volume, landing = landing}
  local index = #s.pending + 1
  while index > 1 and s.pending[index - 1].dueAt > arrival.dueAt do index = index - 1 end
  table.insert(s.pending, index, arrival)

  local last = event.pulses[#event.pulses]
  local endsAt = event.at + last.start + last.length
  if visible and now < endsAt then
    s.visuals[#s.visuals + 1] = {
      event = event, endsAt = endsAt, landing = landing, strength = strikes.strength(distance), bolt = distance <= BOLT_RANGE,
    }
  end
end

local function drawChannel(points, p, width, packed)
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    lineInstance(a.x + p.x, a.y + p.y, a.z + p.z, b.x + p.x, b.y + p.y, b.z + p.z, width, packed)
  end
end

local function drawBolt(visual, pulseIndex)
  lineInstance = lineInstance or require("utils/debugDraw").LineInstance_MinArg
  visual.shape = visual.shape or strikes.bolt(visual.event.shapeSeed)
  drawChannel(visual.shape.main, visual.landing, MAIN_WIDTH, color(235, 240, 255, 255))
  local packed = color(235, 240, 255, 255 - (pulseIndex - 1) * BRANCH_FADE)
  for _, branch in ipairs(visual.shape.branches) do drawChannel(branch, visual.landing, BRANCH_WIDTH, packed) end
end

local function render(s, now, cam)
  local strongest = 0
  for i = #s.visuals, 1, -1 do
    local visual = s.visuals[i]
    if now >= visual.endsAt then
      table.remove(s.visuals, i)
    else
      local elapsed = now - visual.event.at
      for j, pulse in ipairs(visual.event.pulses) do
        if elapsed >= pulse.start and elapsed < pulse.start + pulse.length then
          cam = cam or getCamera()
          if not cam then M.hide(s); return end
          strongest = math.max(strongest, visual.strength * pulse.level)
          if visual.bolt then
            local ok, err = pcall(drawBolt, visual, j)
            if not ok then visual.bolt = false; report(s, "bolt", err) end
          end
          break
        end
      end
    end
  end
  if not M.hasVisualTail(s) then M.hide(s); return end
  local ok, err = pcall(updateLight, s, cam, strongest)
  if not ok then
    remove(s.light)
    s.light, s.enabled = nil, nil
    report(s, "PointLight", err)
  end
end

function M.tick(s, p, lo, hi, runnerObj, flashes, covered, intersectsStorm)
  local seed = p and p.lightningSeed
  if seed ~= s.seed then
    if s.seed then M.clear(s) end
    if type(seed) ~= "number" or seed < 1 or seed > 2147483646 or seed ~= math.floor(seed) then return end
    s.seed = seed
  end
  if not s.seed then return end
  local visible = flashes and covered == false
  local cam
  if intersectsStorm then
    s.cursor = s.cursor or strikes.new(seed)
    local events = strikes.between(s.cursor, p, lo, hi)
    if #events > 0 then
      cam = getCamera()
      if cam then
        local ref
        if runnerObj then
          local ok, pos = pcall(function() return runnerObj:getPosition() end)
          if ok then ref = pos end
        end
        for _, event in ipairs(events) do capture(s, event, ref or cam, cam, visible, hi) end
      end
    end
  end
  if s.pending[1] or next(s.playing) then serviceSound(s, hi) end
  if M.hasVisualTail(s) then
    if visible then render(s, hi, cam) else M.hide(s) end
  end
end

return M
