local lightningScene = require("copsAndRobbers/lightningScene")
local rain = require("copsAndRobbers/rain")
local strikes = require("copsAndRobbers/strikes")

local M = {}
local LIGHT_NAME = "cnr_lightning_flash"
local SOUND_SLOTS = 3
local BOLT_RANGE = 4000
local LIGHT_DISTANCE = 300
local serial = 0

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
  for _, visual in ipairs(s.visuals) do lightningScene.remove(visual.scene) end
  remove(s.light)
  s.light, s.enabled = nil, nil
  s.visuals = {}
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
    assert(not scenetree.findObject(name), name .. " is already in use")
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
  obj:setField("isEnabled", 0, "0")
end

local function updateLight(s, cam, winner, strength)
  if winner then
    if not s.light then s.light = create(s, "PointLight", LIGHT_NAME, lightFields) end
    if not s.light then return end
    s.light:setPosition(winner.shadowPos or vec3(cam.x, cam.y, cam.z + LIGHT_DISTANCE))
    s.light:setField("castShadows", 0, winner.shadowPos and "1" or "0")
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
    serial = serial + 1
    s.visuals[#s.visuals + 1] = {
      event = event, endsAt = endsAt, landing = landing, distance = distance, serial = serial,
      strength = strikes.strength(distance), bolt = distance <= BOLT_RANGE,
    }
  end
end

local function pulseAt(visual, now)
  local elapsed = now - visual.event.at
  for i, pulse in ipairs(visual.event.pulses) do
    if elapsed >= pulse.start and elapsed < pulse.start + pulse.length then return i, pulse.level end
  end
end

local function renderBolt(visual, cam, pulseIndex, pulseLevel)
  if pulseIndex and not visual.scene then
    local shapeSeed = visual.event.shapeSeed
    local shape = strikes.bolt(shapeSeed)
    local midpoint = shape.main[math.floor(#shape.main / 2) + 1]
    local landing = visual.landing
    visual.shadowPos = vec3(landing.x + midpoint.x, landing.y + midpoint.y, landing.z + midpoint.z)
    visual.strength = strikes.strength(0)
    visual.scene = lightningScene.create(shape, landing, visual.distance, visual.serial, shapeSeed)
  end
  if visual.scene then lightningScene.render(visual.scene, cam, pulseIndex, pulseLevel) end
end

local function render(s, now, cam)
  cam = cam or getCamera()
  if not cam or rain.covered(cam) ~= false then M.hide(s); return end
  local strongest = 0
  local winner
  for i = #s.visuals, 1, -1 do
    local visual = s.visuals[i]
    if now >= visual.endsAt then
      lightningScene.remove(visual.scene)
      table.remove(s.visuals, i)
    else
      local pulseIndex, pulseLevel = pulseAt(visual, now)
      if visual.bolt then
        local ok, err = pcall(renderBolt, visual, cam, pulseIndex, pulseLevel)
        if not ok then
          lightningScene.remove(visual.scene)
          visual.scene, visual.bolt = nil, false
          report(s, "bolt", err)
        end
      end
      if pulseLevel then
        local strength = visual.strength * pulseLevel
        if strength > strongest then strongest, winner = strength, visual end
      end
    end
  end
  if not M.hasVisualTail(s) then M.hide(s); return end
  local ok, err = pcall(updateLight, s, cam, winner, strongest)
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
