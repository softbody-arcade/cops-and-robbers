local M = {}

local ASSET_DIR = "/art/shapes/cnrLightning"
local SHAPE = ASSET_DIR .. "/cnrLightningRod.dae"
local MATERIALS = ASSET_DIR .. "/main.materials.json"
local MATERIAL = "cnrLightningBoltRod"
local OBJECT_PREFIX = "cnr_lightning_bolt_"
local MAIN_WIDTH, BRANCH_WIDTH, BRANCH_FADE = 4, 2, 45
local JOINT_WIDTH = 0.9
local CLOUD_LAYER_HEIGHT = 4200
local CLOUD_EXTINCTION = 0.006
local CORE_OVERCAST_START, CORE_OVERCAST_FULL = 2.65, 2.95
local CORE_BURIAL_BLEND = 120
local CORE_TAPER_DEPTH, CORE_CUT_DEPTH = 0.3, 2.0
local GLOW_SIDES = 10
local GLOW_BODY_LOBES, GLOW_WISP_LOBES = 36, 14
local MODULUS = 2147483647

local drawTriSolid, glowColors, glowErrorLogged

local function glowRandom(shapeSeed)
  local parentSeed = shapeSeed * 16807 % MODULUS
  local reversed = 0
  for _ = 1, 31 do
    reversed = 2 * reversed + parentSeed % 2
    parentSeed = math.floor(parentSeed / 2)
  end
  local seed = MODULUS - reversed
  return function()
    seed = seed * 16807 % MODULUS
    return seed / MODULUS
  end
end

local function smoothstep(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end

local function readAirNumber(getter)
  if not getter then return end
  local ok, value = pcall(getter)
  if ok then
    local number = tonumber(value)
    if number and math.abs(number) < math.huge then return number end
  end
end

local function sampleAir(air)
  local env = core_environment
  air.fogDensity = math.max(0, readAirNumber(env and env.getFogDensity) or 0)
  air.fogHeight = math.max(0, readAirNumber(env and env.getFogAtmosphereHeight) or 0)
  local cloudCoverage = math.max(0, readAirNumber(env and env.getCloudCover) or 0)
  local baseKm = readAirNumber(env and env.getCloudAltitudeKm)
  air.cloudBase = baseKm and baseKm * 1000
  local cloudEnabled = not CloudLayer or CloudLayer.volumetricEnabled ~= false
  local coverage = math.min(1, cloudCoverage / 3)
  air.cloudExtinction = cloudEnabled and air.cloudBase and CLOUD_EXTINCTION * coverage ^ 2 or 0
  air.coreCloudWeight = 0
  if air.cloudExtinction > 0 then
    air.coreCloudWeight = smoothstep((cloudCoverage - CORE_OVERCAST_START) / (CORE_OVERCAST_FULL - CORE_OVERCAST_START))
  end
end

local function fogOpticalDepth(air, lowZ, highZ, distance)
  if air.fogDensity == 0 then return 0 end
  local height = air.fogHeight
  local uniformDepth = air.fogDensity * distance
  if height <= 0 or height >= 1e6 then return uniformDepth end
  local heightDelta = (highZ - lowZ) / height
  if heightDelta <= 1e-4 then
    return uniformDepth * math.exp(-(lowZ + highZ) / (2 * height))
  end
  return uniformDepth * math.exp(-lowZ / height) * (1 - math.exp(-heightDelta)) / heightDelta
end

local function cloudOpticalDepth(air, lowZ, highZ, distance)
  if air.cloudExtinction == 0 then return 0 end
  local lower = math.max(lowZ, air.cloudBase)
  local upper = math.min(highZ, air.cloudBase + CLOUD_LAYER_HEIGHT)
  if upper < lower then return 0 end
  local fraction = 1
  if highZ > lowZ then fraction = (upper - lower) / (highZ - lowZ) end
  local a = (lower - air.cloudBase) / CLOUD_LAYER_HEIGHT
  local b = (upper - air.cloudBase) / CLOUD_LAYER_HEIGHT
  local middle, halfWidth = (a + b) / 2, (b - a) / 2
  local relativeDensity = math.max(0, 4 * (middle * (1 - middle) - halfWidth * halfWidth / 3))
  return air.cloudExtinction * relativeDensity * fraction * distance
end

local function airTransmittance(air, cam, x, y, z)
  if air.fogDensity == 0 and air.cloudExtinction == 0 then return 1 end
  local dx, dy, dz = x - cam.x, y - cam.y, z - cam.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  if distance <= 1e-4 then return 1 end
  local lowZ, highZ = math.min(cam.z, z), math.max(cam.z, z)
  return math.exp(-fogOpticalDepth(air, lowZ, highZ, distance) - cloudOpticalDepth(air, lowZ, highZ, distance))
end

local function coreWidth(air, cam, segment)
  if air.coreCloudWeight == 0 or segment.z <= air.cloudBase then return 1 end
  local dx, dy, dz = segment.x - cam.x, segment.y - cam.y, segment.z - cam.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  local lowZ, highZ = math.min(cam.z, segment.z), math.max(cam.z, segment.z)
  local burial = smoothstep((segment.z - air.cloudBase) / CORE_BURIAL_BLEND)
  local depth = cloudOpticalDepth(air, lowZ, highZ, distance) * air.coreCloudWeight * burial
  return 1 - smoothstep((depth - CORE_TAPER_DEPTH) / (CORE_CUT_DEPTH - CORE_TAPER_DEPTH))
end

local function nativeWidths(distance)
  local height, fov = 1080, 60
  if GFXDevice and GFXDevice.getVideoMode then
    local mode = GFXDevice.getVideoMode()
    local h = mode and tonumber(mode.height)
    if h and h > 0 then height = h end
  end
  if core_camera and core_camera.getFovDeg then
    local value = core_camera.getFovDeg()
    if type(value) == "number" and value > 0 and value < 175 then fov = value end
  end
  local metresPerPixel = math.max(0.025, 2 * distance * math.tan(math.rad(fov / 2)) / height)
  return MAIN_WIDTH * metresPerPixel, BRANCH_WIDTH * metresPerPixel
end

local function addChannel(scene, prefix, points, landing, diameter, isBranch)
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    local up = math.abs(dz) > 0.9 * length and vec3(1, 0, 0) or vec3(0, 0, 1)
    local rot = quatFromDir(vec3(dx / length, dy / length, dz / length), up)
    local name = prefix .. (#scene.segments + 1)
    local scale = vec3(diameter, length + JOINT_WIDTH * diameter, diameter)
    local segment = {
      x = landing.x + (a.x + b.x) / 2,
      y = landing.y + (a.y + b.y) / 2,
      z = landing.z + (a.z + b.z) / 2,
      scale = scale, length = length, diameter = diameter, branch = isBranch,
      cloudWidth = 1, hidden = true,
    }
    assert(not scenetree.findObject(name), name .. " is already in use")
    scene.segments[#scene.segments + 1] = segment
    local obj = assert(createObject("TSStatic"))
    segment.obj = obj
    obj:setField("shapeName", 0, SHAPE)
    obj:setField("collisionType", 0, "None")
    obj:setField("decalType", 0, "None")
    obj.hidden, obj.canSave = true, false
    assert(obj:registerObject(name) ~= false and scenetree.findObject(name), name .. " did not register")
    assert(scenetree.MissionGroup:addObject(obj) ~= false, name .. " could not join MissionGroup")
    obj:setScale(scale)
    obj:setPosRot(segment.x, segment.y, segment.z, rot.x, rot.y, rot.z, rot.w)
  end
end

local function setPulse(scene, cam, pulseIndex)
  local air = scene.air
  local weight = air.coreCloudWeight
  local airChanged = pulseIndex and (scene.cloudWeight ~= weight or (weight > 0 and
    (scene.cloudBase ~= air.cloudBase or scene.cloudExtinction ~= air.cloudExtinction or
      scene.camX ~= cam.x or scene.camY ~= cam.y or scene.camZ ~= cam.z)))
  if not airChanged and scene.pulse == pulseIndex then return end
  if airChanged then
    scene.cloudWeight, scene.cloudBase, scene.cloudExtinction = weight, air.cloudBase, air.cloudExtinction
    scene.camX, scene.camY, scene.camZ = cam.x, cam.y, cam.z
  end
  local branchLevel = pulseIndex and (255 - (pulseIndex - 1) * BRANCH_FADE) / 255 or 1
  for _, segment in ipairs(scene.segments) do
    if airChanged then segment.cloudWidth = coreWidth(air, cam, segment) end
    local hidden = not pulseIndex or segment.cloudWidth == 0
    if not hidden then
      local scale = segment.scale
      local diameter = segment.diameter * segment.cloudWidth
      local width = diameter * (segment.branch and branchLevel or 1)
      local length = segment.length + JOINT_WIDTH * diameter
      if scale.x ~= width or scale.y ~= length then
        scale.x, scale.y, scale.z = width, length, width
        segment.obj:setScale(scale)
      end
    end
    if segment.hidden ~= hidden then
      segment.obj.hidden = hidden
      segment.hidden = hidden
    end
  end
  scene.pulse = pulseIndex
end

local function glowLobe(draw, x, y, width, height, alpha)
  local tilt = 0.50 * (draw() - 0.5)
  local c, s = math.cos(tilt), math.sin(tilt)
  local phase, outline = 2 * math.pi * draw(), 2 * math.pi * draw()
  local points = {{x = x, y = y, world = vec3(0, 0, 0)}}
  for i = 1, GLOW_SIDES do
    local angle = phase + 2 * math.pi * (i - 1) / GLOW_SIDES
    local radius = 1 + 0.11 * math.cos(2 * angle + outline)
      + 0.10 * math.sin(3 * angle + outline) + 0.05 * math.cos(5 * angle + phase)
    local u, v = width * radius * math.cos(angle), height * radius * math.sin(angle)
    points[i + 1] = {x = x + c * u - s * v, y = y + s * u + c * v, world = vec3(0, 0, 0)}
  end
  return {points = points, alpha = alpha, rounding = draw()}
end

local function prepareGlow(landing, shape, shapeSeed)
  local top = shape.main[5]
  local origin = vec3(landing.x + top.x, landing.y + top.y, landing.z + top.z)
  local draw = glowRandom(shapeSeed)
  local lobes = {}
  for i = 1, GLOW_BODY_LOBES do
    local scale = (i - 1 + draw()) / GLOW_BODY_LOBES
    local x = (2 * draw() - 1) * (90 + 55 * scale)
    local y = 12 + (2 * draw() - 1) * (20 + 27 * scale)
    local width = 55 + 255 * scale
    local height = width * (0.32 + 0.19 * draw())
    lobes[#lobes + 1] = glowLobe(draw, x, y, width, height, 1)
  end
  for i = 1, GLOW_WISP_LOBES do
    local side = i % 2 == 0 and 1 or -1
    local x = side * (20 + 138 * draw())
    local y = 12 + (2 * draw() - 1) * 45
    local width = 78 + 73 * draw()
    local height = 23 + 37 * draw()
    lobes[#lobes + 1] = glowLobe(draw, x, y, width, height, 2)
  end
  return {position = origin, lobes = lobes}
end

local function projectGlow(glow, dx, dy, dz, distance)
  if dx == glow.dx and dy == glow.dy and dz == glow.dz then return end
  glow.dx, glow.dy, glow.dz = dx, dy, dz
  local nx, ny, nz = dx / distance, dy / distance, dz / distance
  local rightX, rightY = 1, 0
  local horizontal = math.sqrt(nx * nx + ny * ny)
  if horizontal > 1e-6 then rightX, rightY = -ny / horizontal, nx / horizontal end
  local upX, upY, upZ = -nz * rightY, nz * rightX, nx * rightY - ny * rightX
  local origin = glow.position
  for _, lobe in ipairs(glow.lobes) do
    for _, point in ipairs(lobe.points) do
      local x, y, world = point.x, point.y, point.world
      world.x = origin.x + rightX * x + upX * y
      world.y = origin.y + rightY * x + upY * y
      world.z = origin.z + upZ * y
    end
  end
end

local function drawGlow(glow, cam, level, air)
  local origin = glow.position
  local dx, dy, dz = cam.x - origin.x, cam.y - origin.y, cam.z - origin.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  if distance <= 20 then return end
  level = level * math.min(1, (distance - 20) / 120)
  drawTriSolid = drawTriSolid or assert(require("utils/debugDraw").drawTriSolid, "triangle drawing unavailable")
  glowColors = glowColors or {color(190, 207, 255, 1), color(190, 207, 255, 2)}
  projectGlow(glow, dx, dy, dz, distance)
  for _, lobe in ipairs(glow.lobes) do
    local points = lobe.points
    local center = points[1].world
    local transmission = airTransmittance(air, cam, center.x, center.y, center.z)
    local alpha = math.floor(lobe.alpha * level * transmission + lobe.rounding)
    if alpha > 0 then
      local packed, previous = glowColors[alpha], points[#points].world
      for i = 2, #points do
        local vertex = points[i].world
        drawTriSolid(center, vertex, previous, packed, true)
        previous = vertex
      end
    end
  end
end

function M.remove(scene)
  if not scene then return end
  for _, segment in ipairs(scene.segments) do
    local obj = segment.obj
    if obj then pcall(function() obj:delete() end) end
  end
  scene.segments, scene.glow = {}, nil
end

local function build(scene, shape, landing, distance, serial, shapeSeed)
  assert(FS and FS:fileExists(SHAPE), "missing " .. SHAPE)
  if not scenetree.findObject(MATERIAL) then
    assert(FS:fileExists(MATERIALS), "missing " .. MATERIALS)
    loadJsonMaterialsFile(MATERIALS)
    assert(scenetree.findObject(MATERIAL), "missing material binding " .. MATERIAL)
  end
  local mainWidth, branchWidth = nativeWidths(distance)
  local prefix = OBJECT_PREFIX .. serial .. "_"
  addChannel(scene, prefix, shape.main, landing, mainWidth, false)
  for _, branch in ipairs(shape.branches) do
    addChannel(scene, prefix, branch, landing, branchWidth, true)
  end
  scene.glow = prepareGlow(landing, shape, shapeSeed)
end

function M.create(shape, landing, distance, serial, shapeSeed)
  local scene = {segments = {}, air = {}, cloudWeight = 0}
  local ok, err = pcall(build, scene, shape, landing, distance, serial, shapeSeed or 1)
  if not ok then
    M.remove(scene)
    error(err, 0)
  end
  return scene
end

function M.render(scene, cam, pulseIndex, pulseLevel)
  if pulseIndex then sampleAir(scene.air) end
  setPulse(scene, cam, pulseIndex)
  if pulseIndex and scene.glow then
    local ok, err = pcall(drawGlow, scene.glow, cam, pulseLevel, scene.air)
    if not ok then
      scene.glow = nil
      if not glowErrorLogged then
        glowErrorLogged = true
        log("E", "cnr_lightning", "cloud glow: " .. tostring(err))
      end
    end
  end
end

return M
