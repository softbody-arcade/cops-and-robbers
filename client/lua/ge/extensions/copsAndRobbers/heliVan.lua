local model = require("copsAndRobbers/heliModel")

local M = {}

M.NAME = "cnr_heli_van"
M.DIR = "/temp/cnr"
M.CACHE_DIR = "/temp/temp/cnr"
M.PREFIX = "pigeon_heli_"
M.LEFTOVER_INTERVAL = 1
M.MAX_STEP = model.MAX_STEP
M.PAINT = {
  { "instanceColor", "0.9 0.9 0.92 1" },
  { "instanceColor1", "0.12 0.47 0.74 1" },
  { "instanceColor2", "0.12 0.47 0.74 1" },
}
M.LIGHT_RADIUS = 0.25
M.GLOW_PER_METER = 0.004
M.GLOW_MAX = 1.2
M.NIGHT = { core = 235, glow = 70 }
M.DAY = { core = 110, glow = 0 }

local sphere
local palettes = {}

local function reset(s)
  s.made, s.flight, s.pose, s.clock, s.leftoverAt = nil, nil, nil, nil, nil
  s.failed, s.logged, s.lightsFailed = nil, nil, nil
  return s
end

function M.new()
  return reset({})
end

local function loadMaterials()
  if not loadJsonMaterialsFile then return end
  for _, f in ipairs(model.MATERIAL_FILES) do pcall(loadJsonMaterialsFile, f) end
end

local function sweepIn(dir, ext, keep)
  local pattern = "^" .. M.PREFIX .. "[%d_]+%." .. ext .. "$"
  for _, path in ipairs(FS:findFiles(dir .. "/", M.PREFIX .. "*." .. ext, 0, true, false) or {}) do
    local parent, name = path:match("^(.*)/([^/]+)$")
    if parent == dir and name ~= keep and name:find(pattern) then FS:removeFile(path) end
  end
end

local function sweep(base)
  if not (FS and FS.findFiles and FS.removeFile) then return end
  pcall(sweepIn, M.DIR, "dae", base .. ".dae")
  pcall(sweepIn, M.CACHE_DIR, "cdae", base .. ".cdae")
end

local function loaded(name)
  return scenetree ~= nil and scenetree.findObject ~= nil and scenetree.findObject(name) ~= nil
end

local function renames()
  local names = {}
  local livery = loaded(model.SKIN)
  if livery then names[model.BODY_MATERIAL] = model.SKIN end
  if loaded(model.LAMP) then
    for _, id in ipairs(model.LAMP_MATERIALS) do names[id] = model.LAMP end
  end
  return names, livery
end

local function makeCopy()
  if not (readFile and writeFile) then error("no file access", 0) end
  local src = readFile(model.SOURCE)
  if type(src) ~= "string" or src == "" then error("no Pigeon at " .. model.SOURCE, 0) end
  local text, removed = model.trim(src, model.HIDE)
  if removed == 0 then error("no known Pigeon part in " .. model.SOURCE, 0) end
  local names, livery = renames()
  local done
  text, done = model.rename(text, names)
  local lamps = 0
  for _, id in ipairs(model.LAMP_MATERIALS) do
    if done[id] then lamps = lamps + 1 end
  end
  local base = M.PREFIX .. #text
  local path = M.DIR .. "/" .. base .. ".dae"
  if readFile(path) ~= text then
    if FS and FS.directoryCreate then pcall(FS.directoryCreate, FS, M.DIR) end
    if not writeFile(path, text) then error("could not write " .. path, 0) end
  end
  pcall(sweep, base)
  local skin = done[model.BODY_MATERIAL] and "on" or (livery and "not found" or "not loaded")
  return path, removed, skin, lamps
end

local function warm(path)
  local obj = createObject("TSStatic")
  if not obj then return end
  pcall(function()
    obj:setField("shapeName", 0, path)
    obj:setField("collisionType", 0, "None")
    obj:setField("decalType", 0, "None")
    obj.canSave = false
    obj:registerObject(M.NAME .. "_warm")
  end)
  pcall(function() obj:delete() end)
end

function M.prepare(s)
  if s.file or s.copyFailed then return s.file end
  loadMaterials()
  local ok, path, removed, skin, lamps = pcall(makeCopy)
  if not ok then
    s.copyFailed = true
    log("W", "cnr_heli", "helicopter model unavailable: " .. tostring(path))
    return nil
  end
  s.file = path
  local whole = removed == #model.HIDE and skin == "on" and lamps == #model.LAMP_MATERIALS
  log(whole and "I" or "W", "cnr_heli", string.format("helicopter model %s: %d of %d parts removed, livery %s, %d of %d lamp materials",
    path, removed, #model.HIDE, skin, lamps, #model.LAMP_MATERIALS))
  pcall(warm, path)
  return path
end

local function remove()
  local obj = scenetree.findObject(M.NAME)
  if obj then obj:delete() end
end

local function leftover(s, clock)
  local at = s.leftoverAt
  if at and clock >= at and clock - at < M.LEFTOVER_INTERVAL then return end
  s.leftoverAt = clock
  remove()
end

local function create(s)
  if FS and FS.fileExists and not FS:fileExists(s.file) then
    s.file = nil
    error("helicopter model copy is gone", 0)
  end
  loadMaterials()
  local obj = createObject("TSStatic")
  if not obj then error("no TSStatic", 0) end
  local ok, err = pcall(function()
    obj:setField("shapeName", 0, s.file)
    for _, f in ipairs(M.PAINT) do obj:setField(f[1], 0, f[2]) end
    obj:setField("collisionType", 0, "None")
    obj:setField("decalType", 0, "None")
    obj.canSave = false
    obj:registerObject(M.NAME)
  end)
  if not ok then
    pcall(function() obj:delete() end)
    error(err, 0)
  end
  if not scenetree.findObject(M.NAME) then
    obj:delete()
    error("helicopter model did not register", 0)
  end
  scenetree.MissionGroup:addObject(obj)
  local k = model.SCALE
  obj:setScale(vec3(k, k, k))
  return obj
end

local function orient(s, p)
  local d, u = s.dir, s.up
  if not d then
    d, u = vec3(0, 0, 0), vec3(0, 0, 0)
    s.dir, s.up = d, u
  end
  d.x, d.y, d.z = -p.fx, -p.fy, -p.fz
  u.x, u.y, u.z = p.ux, p.uy, p.uz
  local q = s.quat
  if q then
    q:setFromDir(d, u)
  else
    q = quatFromDir(d, u)
    s.quat = q
  end
  return q
end

local function palette(night)
  local pal = palettes[night]
  if pal then return pal end
  local a = night and M.NIGHT or M.DAY
  pal = { core = {}, glow = {} }
  for i, l in ipairs(model.LIGHTS) do
    pal.core[i] = color(l.r, l.g, l.b, a.core)
    if a.glow > 0 then pal.glow[i] = color(l.r, l.g, l.b, a.glow) end
  end
  palettes[night] = pal
  return pal
end

local function glowRadius(pos, camPos)
  if not camPos then return M.LIGHT_RADIUS end
  local dx, dy, dz = pos.x - camPos.x, pos.y - camPos.y, pos.z - camPos.z
  return math.min(M.GLOW_MAX, M.LIGHT_RADIUS + M.GLOW_PER_METER * math.sqrt(dx * dx + dy * dy + dz * dz))
end

local function drawLights(s, pos, clock, night, camPos)
  if not color then return end
  sphere = sphere or require("utils/debugDraw").Sphere
  local p, pal = s.pose, palette(night == true)
  local glow = glowRadius(pos, camPos)
  local beacon = model.beaconOn(clock)
  for i, l in ipairs(model.LIGHTS) do
    if beacon or not l.beacon then
      local x, y, z = model.place(p, pos, l.x, l.y, l.z)
      sphere(x, y, z, M.LIGHT_RADIUS, pal.core[i], true)
      local g = pal.glow[i]
      if g then sphere(x, y, z, glow, g, true) end
    end
  end
end

local function finite(v)
  return v ~= nil and v.x - v.x == 0 and v.y - v.y == 0 and v.z - v.z == 0
end

local function step(s, f, clock, dt, night, camPos)
  if f and not (finite(f.pos) and finite(f.vel)) then f = nil end
  if not f then
    if s.made then
      s.made, s.flight, s.pose = nil, nil, nil
      s.leftoverAt = clock
      remove()
    else
      leftover(s, clock)
    end
    return
  end
  if not M.prepare(s) then
    leftover(s, clock)
    return
  end
  if s.flight ~= f or not s.pose then
    s.flight, s.pose = f, model.newPose()
  end
  local p = s.pose
  model.step(p, f.vel, dt)
  local obj = scenetree.findObject(M.NAME)
  if not obj then obj = create(s) end
  s.made = true
  local pos = f.pos
  local x, y, z = model.place(p, pos, 0, 0, 0)
  local q = orient(s, p)
  obj:setPosRot(x, y, z, q.x, q.y, q.z, q.w)
  if s.lightsFailed then return end
  local ok, err = pcall(drawLights, s, pos, clock, night, camPos)
  if not ok then
    s.lightsFailed = true
    log("E", "cnr_heli", "helicopter lights stopped: " .. tostring(err))
  end
end

function M.tick(s, f, clock, night, camPos)
  clock = clock or 0
  local dt = s.clock and math.min(M.MAX_STEP, math.max(0, clock - s.clock)) or 0
  s.clock = clock
  if s.failed then
    pcall(leftover, s, clock)
    return
  end
  local ok, err = pcall(step, s, f, clock, dt, night, camPos)
  if ok then return end
  pcall(remove)
  s.failed, s.made, s.flight, s.pose = true, nil, nil, nil
  if not s.logged then
    s.logged = true
    log("E", "cnr_heli", "helicopter model stopped: " .. tostring(err))
  end
end

function M.clear(s)
  pcall(remove)
  reset(s)
end

return M
