local saved = { vec3 = _G.vec3, log = _G.log, createObject = _G.createObject, Sim = _G.Sim, scenetree = _G.scenetree }
local NAME = "cnr_heli_sound"
local sound
local objects, made, logs
local finds = 0
local noRegister = false

local function newEmitter(class)
  local obj = { class = class, fields = {}, writes = {}, positions = 0, calls = {} }
  function obj:setField(name, _, value) self.fields[name] = value end
  function obj:setVolumePitchCT(v, pitch, cone, t)
    self.writes[#self.writes + 1] = { v = v, pitch = pitch, cone = cone, t = t }
  end
  function obj:setPosition(p)
    self.pos = { x = p.x, y = p.y, z = p.z }
    self.positions = self.positions + 1
    self.calls[#self.calls + 1] = "setPosition"
  end
  function obj:registerObject(name)
    self.name = name
    self.calls[#self.calls + 1] = "registerObject"
    if not noRegister then objects[name] = self end
  end
  function obj:play()
    self.playing = true
    self.calls[#self.calls + 1] = "play"
  end
  function obj:delete()
    self.deleted = true
    if self.name and objects[self.name] == self then objects[self.name] = nil end
  end
  return obj
end

local function load()
  objects, made, logs, finds, noRegister = {}, {}, {}, 0, false
  _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
  _G.log = function(level, tag, msg) logs[#logs + 1] = { level = level, tag = tag, msg = msg } end
  _G.createObject = function(class)
    local obj = newEmitter(class)
    made[#made + 1] = obj
    return obj
  end
  _G.Sim = { upcast = function(obj)
    obj.upcast = true
    return obj
  end }
  _G.scenetree = {
    findObject = function(name)
      finds = finds + 1
      return objects[name]
    end,
    MissionGroup = { addObject = function(_, obj)
      obj.inMission = true
      obj.calls[#obj.calls + 1] = "addObject"
    end },
  }
  package.loaded["copsAndRobbers/heliSound"] = nil
  sound = require("copsAndRobbers/heliSound")
end

local P = { x = 100, y = 200, z = 50 }
local STEP = 0.05

local function written(obj)
  local w = obj.writes[#obj.writes]
  if w then return w.v end
  return tonumber(obj.fields.volume)
end

local function run(s, from, to, pos, level, camPos, castRay, each)
  local i = from
  while i <= to do
    local c = i * STEP
    sound.tick(s, pos, level, c, camPos, castRay)
    if each then each(c, i) end
    i = i + 1
  end
  return to * STEP
end

test("the emitter is made with the file and fields, registered and played", function()
  load()
  local s = sound.new()
  sound.tick(s, P, 1, 0)
  local obj = objects[NAME]
  assertEq(obj ~= nil, true)
  assertEq(obj.class, "SFXEmitter")
  assertEq(obj.upcast, true)
  assertEq(obj.fields.fileName, "/art/sound/cnr/heli_rotor.ogg")
  assertEq(obj.fields.is3D, "1")
  assertEq(obj.fields.isLooping, "1")
  assertEq(obj.fields.referenceDistance, "40")
  assertEq(obj.fields.maxDistance, "800")
  assertEq(obj.fields.volume, "0")
  assertEq(obj.canSave, false)
  assertEq(obj.name, NAME)
  assertEq(obj.inMission, true)
  assertEq(obj.playing, true)
  assertEq(table.concat(obj.calls, ","), "registerObject,addObject,setPosition,play")
  assertEq(obj.pos.x, 100); assertEq(obj.pos.y, 200); assertEq(obj.pos.z, 50)
  for i = 1, 10 do
    local p = { x = 100 + i, y = 200 - i, z = 50 + i / 2 }
    sound.tick(s, p, 1, i * STEP)
    assertEq(obj.pos.x, p.x); assertEq(obj.pos.y, p.y); assertEq(obj.pos.z, p.z)
    assertEq(obj.positions, i + 1)
  end
  assertEq(#made, 1)
  for _, w in ipairs(obj.writes) do
    assertEq(w.pitch, 1); assertEq(w.cone, 0); assertEq(w.t, 0)
  end
end)

test("an emitter that doesn't register is deleted and logged", function()
  load()
  noRegister = true
  local s = sound.new()
  run(s, 0, 20, P, 1)
  assertEq(#made, 1)
  assertEq(made[1].deleted, true)
  assertEq(made[1].inMission, nil)
  assertEq(made[1].playing, nil)
  assertEq(objects[NAME], nil)
  assertEq(#logs, 1)
  assertEq(logs[1].level, "E")
end)

test("it fades in over 1 s", function()
  load()
  local s = sound.new()
  local prev = 0
  run(s, 0, 30, P, 1, nil, nil, function(c, i)
    local v = written(objects[NAME])
    assertEq(v - prev <= STEP / sound.FADE_IN_SECONDS + sound.VOLUME_STEP + 1e-9, true, c .. ": " .. prev .. " -> " .. v)
    prev = v
    if i == 10 then assertNear(v, 0.5, 0.05) end
    if i == 20 then assertNear(v, 1, 1e-9) end
  end)
  assertEq(written(objects[NAME]), 1)
end)

test("a long frame moves the volume and the muffle by at most one capped step", function()
  load()
  local s = sound.new()
  sound.tick(s, P, 1, 0)
  local obj = objects[NAME]
  assertEq(written(obj), 0)
  sound.tick(s, P, 1, 1.2)
  assertEq(written(obj) <= 0.1 + sound.VOLUME_STEP + 1e-9, true, tostring(written(obj)))
  assertEq(written(obj) > 0, true)
  run(s, 25, 60, P, 1)
  assertEq(written(obj), 1)
  sound.tick(s, P, 0, 60 * STEP + 1.2)
  assertEq(objects[NAME], obj)
  assertEq(written(obj) >= 1 - 0.1 - sound.VOLUME_STEP - 1e-9, true, tostring(written(obj)))
  load()
  s = sound.new()
  local cam = { x = 100, y = 100, z = 50 }
  run(s, 0, 30, P, 1, cam, function(_, _, len) return len + 100 end)
  obj = objects[NAME]
  assertEq(written(obj), 1)
  sound.tick(s, P, 1, 30 * STEP + 1.2, cam, function() return 10 end)
  assertEq(written(obj) >= 1 - 0.1 - sound.VOLUME_STEP - 1e-9, true, tostring(written(obj)))
end)

test("a level that rises at once is eased", function()
  load()
  local s = sound.new()
  local start = run(s, 0, 20, P, 0.3)
  local obj = objects[NAME]
  assertNear(written(obj), 0.3, 1e-9)
  local reached
  local prev = written(obj)
  run(s, 21, 60, P, 1, nil, nil, function(c)
    local v = written(obj)
    assertEq(v - prev <= STEP + sound.VOLUME_STEP + 1e-9, true, c .. ": " .. prev .. " -> " .. v)
    prev = v
    if not reached and v >= 1 - 1e-9 then reached = c end
  end)
  assertEq(reached ~= nil, true)
  assertNear(reached - start, 0.7, STEP + 1e-9)
end)

test("level 0 or a nil pos fades it out over 1 s and then removes it", function()
  for _, how in ipairs({ "level", "pos" }) do
    load()
    local s = sound.new()
    run(s, 0, 30, P, 1)
    local obj = objects[NAME]
    assertEq(written(obj), 1, how)
    local before = obj.positions
    run(s, 31, 52, how == "level" and P or nil, how == "level" and 0 or 1, nil, nil, function(_, i)
      if i == 40 then
        assertEq(objects[NAME], obj, how)
        assertNear(written(obj), 0.5, 0.05, how)
        assertEq(obj.positions, before + 10, how)
        assertEq(obj.pos.x, P.x, how); assertEq(obj.pos.y, P.y, how); assertEq(obj.pos.z, P.z, how)
      end
    end)
    assertEq(objects[NAME], nil, how)
    assertEq(obj.deleted, true, how)
    assertEq(written(obj), 0, how)
    assertEq(#made, 1, how)
  end
end)

test("the muffle eases to half behind a wall and back, with rays only every 0.25 s", function()
  load()
  local s = sound.new()
  local cam = { x = 100, y = 100, z = 50 }
  local wall, now = nil, 0
  local rays = {}
  local function ray(origin, dir, len)
    rays[#rays + 1] = now
    assertEq(origin.x, cam.x); assertEq(origin.y, cam.y); assertEq(origin.z, cam.z)
    assertNear(dir.x, 0, 1e-9); assertNear(dir.y, 1, 1e-9); assertNear(dir.z, 0, 1e-9)
    assertNear(len, 100, 1e-9)
    return wall or len + 100
  end
  local function tickAt(i, camPos)
    now = i * STEP
    sound.tick(s, P, 1, now, camPos, ray)
  end
  for i = 0, 30 do tickAt(i, cam) end
  local obj = objects[NAME]
  assertEq(written(obj), 1)
  wall = 98.5
  for i = 31, 50 do tickAt(i, cam) end
  assertEq(written(obj), 1)
  wall = 60
  local blockedAt
  for i = 51, 90 do
    tickAt(i, cam)
    if not blockedAt and written(obj) < 1 then blockedAt = i end
    assertEq(written(obj) >= 0.5 - 1e-9, true, tostring(written(obj)))
  end
  assertEq(blockedAt ~= nil and blockedAt <= 56, true, tostring(blockedAt))
  assertNear(written(obj), 0.5, 1e-9)
  wall = nil
  local clearAt
  for i = 91, 130 do
    tickAt(i, cam)
    if not clearAt and written(obj) > 0.5 then clearAt = i end
  end
  assertEq(clearAt ~= nil and clearAt <= 96, true, tostring(clearAt))
  assertEq(written(obj), 1)
  for k = 2, #rays do
    assertEq(rays[k] - rays[k - 1] >= sound.RAY_INTERVAL - 1e-9, true, rays[k - 1] .. " " .. rays[k])
  end
  assertEq(#rays >= 20 and #rays <= 27, true, tostring(#rays))
  wall = 60
  local n = #rays
  for i = 131, 160 do tickAt(i, nil) end
  assertEq(#rays, n)
  assertEq(written(obj), 1)
end)

test("the muffle takes half a second to reach half", function()
  load()
  local s = sound.new()
  local cam = { x = 100, y = 100, z = 50 }
  local blocked = false
  local function ray(_, _, len) return blocked and 10 or len + 100 end
  run(s, 0, 30, P, 1, cam, ray)
  local obj = objects[NAME]
  blocked = true
  local samples = {}
  run(s, 31, 60, P, 1, cam, ray, function(_, i) samples[i] = written(obj) end)
  local first
  for i = 31, 60 do
    if samples[i] < 1 then
      first = i
      break
    end
  end
  assertEq(first ~= nil, true)
  assertNear(samples[first + 4], 0.75, 0.05)
  assertNear(samples[first + 9], 0.5, 1e-9)
end)

test("the volume is only written on a change over 0.02, and when it reaches 0 or the target", function()
  load()
  local s = sound.new()
  local dt = 0.005
  for i = 0, 300 do sound.tick(s, P, 1, i * dt) end
  local obj = objects[NAME]
  local ws = obj.writes
  assertEq(#ws >= 30 and #ws <= 50, true, tostring(#ws))
  assertEq(ws[1].v > sound.VOLUME_STEP, true, tostring(ws[1].v))
  for k = 2, #ws do
    local d = ws[k].v - ws[k - 1].v
    assertEq(d > sound.VOLUME_STEP or ws[k].v == 1, true, ws[k - 1].v .. " -> " .. ws[k].v)
  end
  assertEq(ws[#ws].v, 1)
  local n = #ws
  for i = 301, 340 do sound.tick(s, P, 1, i * dt) end
  assertEq(#ws, n)
  for i = 341, 600 do sound.tick(s, P, 0.51, i * dt) end
  assertEq(ws[#ws].v, 0.51)
  for k = n + 1, #ws - 1 do
    assertEq(ws[k - 1].v - ws[k].v > sound.VOLUME_STEP, true, ws[k - 1].v .. " -> " .. ws[k].v)
  end
  n = #ws
  for i = 601, 1000 do sound.tick(s, P, 0, i * dt) end
  assertEq(obj.deleted, true)
  assertEq(ws[#ws].v, 0)
  for k = n + 1, #ws - 1 do
    assertEq(ws[k - 1].v - ws[k].v > sound.VOLUME_STEP, true, ws[k - 1].v .. " -> " .. ws[k].v)
  end
end)

test("it is always found by name", function()
  load()
  local s = sound.new()
  run(s, 0, 30, P, 1)
  local first = objects[NAME]
  assertEq(written(first), 1)
  objects[NAME] = nil
  local seen = first.positions
  local writes = #first.writes
  sound.tick(s, P, 1, 31 * STEP)
  local second = objects[NAME]
  assertEq(second ~= nil and second ~= first, true)
  assertEq(#made, 2)
  assertEq(second.fields.volume, "0")
  assertEq(written(second) <= STEP + sound.VOLUME_STEP + 1e-9, true, tostring(written(second)))
  run(s, 32, 40, P, 1)
  assertNear(written(second), 0.5, 0.05)
  assertEq(first.positions, seen)
  assertEq(#first.writes, writes)
end)

test("a leftover emitter is looked for about once a second and deleted while no sound is wanted", function()
  load()
  local s = sound.new()
  run(s, 1, 40, nil, 0)
  assertEq(finds >= 1 and finds <= 2, true, tostring(finds))
  assertEq(#made, 0)
  local lastFinds = finds
  local plantedAt, planted, goneAt
  run(s, 41, 120, nil, 0, nil, nil, function(c)
    if not planted and finds > lastFinds then
      planted = newEmitter("SFXEmitter")
      planted:registerObject(NAME)
      plantedAt = c
    end
    if planted and not goneAt and objects[NAME] == nil then goneAt = c end
  end)
  assertEq(planted ~= nil, true)
  assertEq(planted.deleted, true)
  assertEq(goneAt - plantedAt <= 1.1 + 1e-9, true, plantedAt .. " " .. goneAt)
  assertEq(#made, 0)
  local s2 = sound.new()
  local leftover = newEmitter("SFXEmitter")
  leftover:registerObject(NAME)
  sound.tick(s2, P, 0, 0)
  assertEq(objects[NAME], nil)
  assertEq(leftover.deleted, true)
end)

test("an error deletes the emitter, stops the sound and logs once", function()
  load()
  local s = sound.new()
  run(s, 0, 10, P, 1)
  local obj = objects[NAME]
  obj.setPosition = function() error("boom") end
  run(s, 11, 20, P, 1)
  assertEq(obj.deleted, true)
  assertEq(objects[NAME], nil)
  assertEq(#logs, 1)
  assertEq(logs[1].level, "E")
  assertEq(#made, 1)
  assertEq(s.failed, true)
  local planted = newEmitter("SFXEmitter")
  planted:registerObject(NAME)
  run(s, 21, 45, P, 1)
  assertEq(planted.deleted, true)
  assertEq(objects[NAME], nil)
  assertEq(#made, 1)
  assertEq(#logs, 1)
  sound.clear(s)
  sound.tick(s, P, 1, 46 * STEP)
  assertEq(#made, 2)
  assertEq(objects[NAME], made[2])
end)

test("clear deletes it at once and resets", function()
  load()
  local s = sound.new()
  local cam = { x = 100, y = 100, z = 50 }
  run(s, 0, 30, P, 1, cam, function() return 10 end)
  local obj = objects[NAME]
  assertEq(written(obj) < 1, true)
  assertEq(s.rayAt ~= nil, true)
  sound.clear(s)
  assertEq(obj.deleted, true)
  assertEq(objects[NAME], nil)
  local fresh = sound.new()
  for k, v in pairs(fresh) do assertEq(s[k], v, k) end
  for k, v in pairs(s) do assertEq(fresh[k], v, k) end
  run(s, 31, 40, P, 1)
  local again = objects[NAME]
  again.setPosition = function() error("boom") end
  run(s, 41, 42, P, 1)
  assertEq(s.failed, true)
  sound.clear(s)
  for k, v in pairs(fresh) do assertEq(s[k], v, k) end
  for k, v in pairs(s) do assertEq(fresh[k], v, k) end
  local logged = #logs
  run(s, 43, 44, P, 1)
  objects[NAME].setPosition = function() error("boom") end
  run(s, 45, 46, P, 1)
  assertEq(#logs, logged + 1)
end)

_G.vec3, _G.log, _G.createObject, _G.Sim, _G.scenetree = saved.vec3, saved.log, saved.createObject, saved.Sim, saved.scenetree
