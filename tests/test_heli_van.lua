local GLOBALS = { "vec3", "log", "createObject", "scenetree", "readFile", "writeFile", "FS", "loadJsonMaterialsFile", "quatFromDir", "color" }
local saved = {}
for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
local savedDraw = package.loaded["utils/debugDraw"]

local NAME = "cnr_heli_van"
local SOURCE = "/vehicles/pigeon/pigeon.dae"
local FAKE = '<?xml version="1.0"?>\n<COLLADA>\n  <library_materials>\n' ..
  '    <material id="pigeon-material" name="pigeon">\n    </material>\n  </library_materials>\n' ..
  '      <node id="pigeon_bed" name="pigeon_bed" type="NODE">\n      </node>\n' ..
  '      <node id="pigeon_box" name="pigeon_box" type="NODE">\n        <instance_material target="#pigeon-material"/>\n      </node>\n' ..
  '      <node id="pigeon_taillight_L" name="pigeon_taillight_L" type="NODE">\n      </node>\n</COLLADA>\n'

local van, model
local objects, logs, files, written, reads, events, draws, removed, dirs
local finds = 0
local noRegister, failWrite, failRead

local function contains(text, part) return text:find(part, 1, true) ~= nil end

local function newStatic(class)
  local obj = { class = class, fields = {}, posrots = {} }
  function obj:setField(name, _, value) self.fields[name] = value end
  function obj:registerObject(name)
    self.name = name
    events[#events + 1] = "register " .. tostring(name)
    if not noRegister then objects[name] = self end
  end
  function obj:setPosRot(x, y, z, qx, qy, qz, qw)
    self.posrots[#self.posrots + 1] = { x = x, y = y, z = z, qx = qx, qy = qy, qz = qz, qw = qw }
  end
  function obj:setScale(v) self.scale = { x = v.x, y = v.y, z = v.z } end
  function obj:delete()
    self.deleted = true
    if self.name and objects[self.name] == self then objects[self.name] = nil end
  end
  return obj
end

local function load(opts)
  opts = opts or {}
  objects, logs, written, reads, events, draws, removed, dirs = {}, {}, {}, {}, {}, {}, {}, {}
  if not opts.keepFiles then files = { [SOURCE] = FAKE } end
  finds, noRegister, failWrite, failRead = 0, false, false, false
  _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
  _G.log = function(level, tag, msg) logs[#logs + 1] = { level = level, tag = tag, msg = msg } end
  _G.createObject = function(class)
    events[#events + 1] = "create " .. class
    return newStatic(class)
  end
  _G.scenetree = {
    findObject = function(name)
      finds = finds + 1
      return objects[name]
    end,
    MissionGroup = { addObject = function(_, obj) obj.inMission = true end },
  }
  _G.readFile = function(path)
    reads[#reads + 1] = path
    if failRead then error("read failed") end
    return files[path]
  end
  _G.writeFile = function(path, data)
    written[#written + 1] = path
    if failWrite then return nil end
    files[path] = data
    return true
  end
  _G.FS = {
    directoryCreate = function(_, dir) dirs[#dirs + 1] = dir end,
    findFiles = function(_, dir, pattern)
      assertEq(dir, "/temp/cnr/")
      assertEq(pattern, "pigeon_heli_*.dae")
      local out = {}
      for path in pairs(files) do
        if path:find("^/temp/cnr/pigeon_heli_.*%.dae$") then out[#out + 1] = path end
      end
      return out
    end,
    removeFile = function(_, path)
      removed[#removed + 1] = path
      files[path] = nil
    end,
  }
  _G.loadJsonMaterialsFile = function(path) events[#events + 1] = "materials " .. path end
  _G.quatFromDir = function(d, u)
    local q = {}
    function q:setFromDir(dir, up)
      self.dir = { x = dir.x, y = dir.y, z = dir.z }
      self.up = { x = up.x, y = up.y, z = up.z }
      self.x, self.y, self.z, self.w = dir.x + 10, dir.y + 20, dir.z + 30, up.z
    end
    q:setFromDir(d, u)
    return q
  end
  _G.color = function(r, g, b, a) return r .. "," .. g .. "," .. b .. "," .. a end
  package.loaded["utils/debugDraw"] = {
    Sphere = function(x, y, z, r, c, useZ) draws[#draws + 1] = { x = x, y = y, z = z, r = r, c = c, useZ = useZ } end,
  }
  package.loaded["copsAndRobbers/heliVan"] = nil
  package.loaded["copsAndRobbers/heliModel"] = nil
  van = require("copsAndRobbers/heliVan")
  model = require("copsAndRobbers/heliModel")
end

local function flight(x, y, z, vx, vy)
  return { pos = vec3(x, y, z), vel = vec3(vx or 10, vy or 0, 0) }
end

local function plant()
  local obj = newStatic("TSStatic")
  obj.name = NAME
  objects[NAME] = obj
  return obj
end

local function created()
  local n = 0
  for _, e in ipairs(events) do
    if e == "register " .. NAME then n = n + 1 end
  end
  return n
end

local function sameDir(a, x, y, z, msg)
  assertNear(a.x, x, 1e-9, msg); assertNear(a.y, y, 1e-9, msg); assertNear(a.z, z, 1e-9, msg)
end

test("prepare loads the materials, trims, renames the livery and writes one copy per session", function()
  load()
  local s = van.new()
  local path = van.prepare(s)
  assertEq(path ~= nil, true)
  assertEq(path:match("^/temp/cnr/pigeon_heli_(%d+)%.dae$") ~= nil, true, path)
  assertEq(#written, 1)
  assertEq(written[1], path)
  local text = files[path]
  assertEq(path, "/temp/cnr/pigeon_heli_" .. #text .. ".dae")
  assertEq(contains(text, '<node id="pigeon_box"'), true)
  assertEq(contains(text, '<node id="pigeon_bed"'), false)
  assertEq(contains(text, '<node id="pigeon_taillight_L"'), false)
  assertEq(contains(text, '<material id="pigeon-material" name="pigeon.skin.birdabduction">'), true)
  assertEq(contains(text, 'target="#pigeon-material"'), true)
  assertEq(dirs[1], "/temp/cnr")
  assertEq(events[1], "materials /vehicles/pigeon/main.materials.json")
  assertEq(events[2], "materials /vehicles/pigeon/dynamicDecals/main.materials.json")
  assertEq(events[3], "materials /vehicles/pigeon/skin.materials.json")
  assertEq(events[4], "create TSStatic")
  assertEq(events[5], "register " .. NAME .. "_warm")
  assertEq(objects[NAME .. "_warm"], nil)
  assertEq(objects[NAME], nil)
  assertEq(#logs, 1)
  assertEq(logs[1].level, "I")
  assertEq(contains(logs[1].msg, "2 of 48"), true, logs[1].msg)
  local n = #reads
  assertEq(van.prepare(s), path)
  assertEq(#reads, n)
  assertEq(#written, 1)
  assertEq(#logs, 1)
end)

test("an unchanged copy is not rewritten on a later session and older copies are removed", function()
  load()
  local path = van.prepare(van.new())
  files["/temp/cnr/pigeon_heli_123.dae"] = "old"
  files["/temp/cnr/notes.txt"] = "keep"
  load({ keepFiles = true })
  local s = van.new()
  assertEq(van.prepare(s), path)
  assertEq(#written, 0)
  assertEq(#removed, 1)
  assertEq(removed[1], "/temp/cnr/pigeon_heli_123.dae")
  assertEq(files[path] ~= nil, true)
  assertEq(files["/temp/cnr/notes.txt"], "keep")
  files[path] = "broken"
  load({ keepFiles = true })
  assertEq(van.prepare(van.new()), path)
  assertEq(#written, 1)
  assertEq(files[path] ~= "broken", true)
end)

test("no Pigeon, a read or write error or no known part means no van and one log line", function()
  local cases = {
    none = function() files[SOURCE] = nil end,
    empty = function() files[SOURCE] = "" end,
    read = function() failRead = true end,
    write = function() failWrite = true end,
    parts = function() files[SOURCE] = '<COLLADA><node id="other"></node></COLLADA>' end,
    api = function() _G.readFile = nil end,
  }
  for name, setUp in pairs(cases) do
    load()
    setUp()
    local s = van.new()
    for i = 0, 30 do van.tick(s, flight(0, 0, 100), i * 0.1, true) end
    assertEq(created(), 0, name)
    assertEq(objects[NAME], nil, name)
    assertEq(#logs, 1, name)
    assertEq(logs[1].level, "W", name)
    assertEq(#draws, 0, name)
    local n = #reads
    assertEq(van.prepare(s), nil, name)
    van.clear(s)
    for i = 31, 40 do van.tick(s, flight(0, 0, 100), i * 0.1, true) end
    assertEq(#reads, n, name)
    assertEq(created(), 0, name)
    assertEq(#logs, 1, name)
  end
end)

test("the van is made with the shape, livery paint, scale and no collision, then follows the flight", function()
  load()
  local s = van.new()
  local path = van.prepare(s)
  local f = flight(100, 200, 120, 10, 0)
  events = {}
  van.tick(s, f, 0, true)
  local obj = objects[NAME]
  assertEq(obj ~= nil, true)
  assertEq(obj.class, "TSStatic")
  assertEq(obj.fields.shapeName, path)
  assertEq(obj.fields.instanceColor, "0.9 0.9 0.92 1")
  assertEq(obj.fields.instanceColor1, "0.12 0.47 0.74 1")
  assertEq(obj.fields.instanceColor2, "0.12 0.47 0.74 1")
  assertEq(obj.fields.collisionType, "None")
  assertEq(obj.fields.decalType, "None")
  assertEq(obj.canSave, false)
  assertEq(obj.inMission, true)
  assertEq(obj.scale.x, 3); assertEq(obj.scale.y, 3); assertEq(obj.scale.z, 3)
  assertEq(events[1], "materials /vehicles/pigeon/main.materials.json")
  assertEq(events[3], "materials /vehicles/pigeon/skin.materials.json")
  assertEq(events[4], "create TSStatic")
  local twin = model.newPose()
  local clock, x, vx, vy = 0, 100, 10, 0
  for i = 0, 60 do
    if i > 0 then
      clock = clock + 0.05
      if i > 20 then vx, vy = vx - 0.3, vy + 0.4 end
      x = x + vx * 0.05
      f.pos, f.vel = vec3(x, 200 + i, 120), vec3(vx, vy, 0)
      van.tick(s, f, clock, true)
    end
    model.step(twin, f.vel, i > 0 and 0.05 or 0)
    assertEq(#obj.posrots, i + 1)
    local pr = obj.posrots[i + 1]
    local ex, ey, ez = model.place(twin, f.pos, 0, 0, 0)
    assertNear(pr.x, ex, 1e-9, tostring(i)); assertNear(pr.y, ey, 1e-9, tostring(i)); assertNear(pr.z, ez, 1e-9, tostring(i))
    sameDir(s.quat.dir, -twin.fx, -twin.fy, -twin.fz, tostring(i))
    sameDir(s.quat.up, twin.ux, twin.uy, twin.uz, tostring(i))
    assertNear(pr.qx, s.quat.x, 1e-9); assertNear(pr.qw, s.quat.w, 1e-9)
  end
  assertEq(math.abs(s.pose.bank) > 1, true, tostring(s.pose.bank))
  assertEq(created(), 1)
  assertEq(objects[NAME], obj)
end)

test("a new flight starts a fresh pose", function()
  load()
  local s = van.new()
  local f = flight(0, 0, 100, 0, 0)
  for i = 0, 40 do
    f.vel = vec3(i * 0.4, 0, 0)
    van.tick(s, f, i * 0.05, true)
  end
  assertEq(s.pose.pitch > 3, true, tostring(s.pose.pitch))
  van.tick(s, flight(0, 0, 100, 0, 10), 41 * 0.05, true)
  assertEq(s.pose.pitch, 0)
  assertNear(s.pose.yaw, math.pi / 2, 1e-9)
end)

test("no flight removes it at once, it is found by name and made again, a leftover is swept about once a second", function()
  load()
  local s = van.new()
  van.tick(s, flight(0, 0, 100), 0, true)
  local first = objects[NAME]
  van.tick(s, nil, 0.1, true)
  assertEq(first.deleted, true)
  assertEq(objects[NAME], nil)
  van.tick(s, flight(0, 0, 100), 0.2, true)
  local second = objects[NAME]
  assertEq(second ~= nil and second ~= first, true)
  objects[NAME] = nil
  van.tick(s, flight(0, 0, 100), 0.3, true)
  local third = objects[NAME]
  assertEq(third ~= nil and third ~= second, true)
  assertEq(#third.posrots, 1)
  assertEq(created(), 3)
  van.tick(s, nil, 0.4, true)
  finds = 0
  for i = 5, 44 do van.tick(s, nil, i * 0.1, true) end
  assertEq(finds >= 3 and finds <= 5, true, tostring(finds))
  local planted = plant()
  for i = 45, 56 do van.tick(s, nil, i * 0.1, true) end
  assertEq(planted.deleted, true)
  assertEq(created(), 3)
  local fresh = van.new()
  local leftover = plant()
  van.tick(fresh, nil, 0, true)
  assertEq(leftover.deleted, true)
end)

test("a failing call removes it and logs once; clear deletes it and resets", function()
  load()
  local s = van.new()
  van.tick(s, flight(0, 0, 100), 0, true)
  local obj = objects[NAME]
  obj.setPosRot = function() error("boom") end
  local before = #logs
  for i = 1, 10 do van.tick(s, flight(0, 0, 100), i * 0.1, true) end
  assertEq(obj.deleted, true)
  assertEq(objects[NAME], nil)
  assertEq(#logs, before + 1)
  assertEq(logs[#logs].level, "E")
  assertEq(created(), 1)
  local planted = plant()
  for i = 11, 25 do van.tick(s, flight(0, 0, 100), i * 0.1, true) end
  assertEq(planted.deleted, true)
  assertEq(created(), 1)
  van.clear(s)
  van.tick(s, flight(0, 0, 100), 3, true)
  assertEq(created(), 2)
  local again = objects[NAME]
  assertEq(#again.posrots, 1)
  van.clear(s)
  assertEq(again.deleted, true)
  assertEq(objects[NAME], nil)
  assertEq(s.pose, nil)
  assertEq(s.file ~= nil, true)
  van.tick(s, flight(0, 0, 100), 4, true)
  assertEq(created(), 3)
  assertEq(#logs, before + 1)
end)

local function drawnAt(i, l, s, pos)
  local x, y, z = model.place(s.pose, pos, l.x, l.y, l.z)
  local d = draws[i]
  assertNear(d.x, x, 1e-9); assertNear(d.y, y, 1e-9); assertNear(d.z, z, 1e-9)
  assertEq(d.useZ, true)
end

test("the lights follow the van, the beacons flash on their period, glow only at night", function()
  load()
  local s = van.new()
  local f = flight(50, 60, 120, 0, 12)
  local cam = vec3(50, 60, 20)
  van.tick(s, f, 0, true, cam)
  assertEq(#draws, 10)
  for i, l in ipairs(model.LIGHTS) do
    drawnAt(2 * i - 1, l, s, f.pos)
    drawnAt(2 * i, l, s, f.pos)
    assertEq(draws[2 * i - 1].r, van.LIGHT_RADIUS)
    assertEq(draws[2 * i - 1].c, l.r .. "," .. l.g .. "," .. l.b .. "," .. van.NIGHT.core)
    assertEq(draws[2 * i].c, l.r .. "," .. l.g .. "," .. l.b .. "," .. van.NIGHT.glow)
    assertNear(draws[2 * i].r, van.LIGHT_RADIUS + van.GLOW_PER_METER * 100, 1e-9)
  end
  local port = draws[1]
  assertEq(port.x < 50, true, tostring(port.x))
  draws = {}
  van.tick(s, f, 0.5, true, cam)
  assertEq(#draws, 6)
  for _, d in ipairs(draws) do assertEq(d.c:find("^255,30,20,") == nil, true, d.c) end
  local on = 0
  for i = 0, 99 do
    draws = {}
    van.tick(s, f, 1 + i * 0.01, true, cam)
    if #draws == 10 then on = on + 1 end
  end
  assertEq(on >= 14 and on <= 16, true, tostring(on))
  draws = {}
  van.tick(s, f, 3, false, vec3(50, 60, -5000))
  assertEq(#draws, 5)
  for i, l in ipairs(model.LIGHTS) do
    assertEq(draws[i].c, l.r .. "," .. l.g .. "," .. l.b .. "," .. van.DAY.core)
  end
  draws = {}
  van.tick(s, f, 3.1, true, vec3(50, 60, -5000))
  assertEq(draws[2].r, van.GLOW_MAX)
  f.vel = vec3(-12, 0, 0)
  for i = 1, 60 do van.tick(s, f, 3.1 + i * 0.05, true, cam) end
  draws = {}
  van.tick(s, f, 7, true, cam)
  assertEq(draws[1].y < 60, true, tostring(draws[1].y))
end)

test("nothing is drawn without a van", function()
  load()
  local s = van.new()
  van.tick(s, flight(0, 0, 100), 0, true)
  draws = {}
  van.tick(s, nil, 0.05, true)
  van.tick(s, nil, 0.1, true)
  assertEq(#draws, 0)
  load()
  files[SOURCE] = nil
  s = van.new()
  van.tick(s, flight(0, 0, 100), 0, true)
  assertEq(#draws, 0)
  load()
  _G.color = nil
  s = van.new()
  van.tick(s, flight(0, 0, 100), 0, true)
  assertEq(#draws, 0)
  assertEq(objects[NAME] ~= nil, true)
end)

test("a failing light draw stops the lights once and keeps the van", function()
  load()
  package.loaded["utils/debugDraw"] = { Sphere = function() error("no ffi") end }
  local s = van.new()
  van.prepare(s)
  local before = #logs
  for i = 0, 10 do van.tick(s, flight(0, 0, 100), i * 0.1, true) end
  local obj = objects[NAME]
  assertEq(obj ~= nil, true)
  assertEq(#obj.posrots, 11)
  assertEq(#logs, before + 1)
  assertEq(logs[#logs].level, "E")
end)

for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
package.loaded["utils/debugDraw"] = savedDraw
