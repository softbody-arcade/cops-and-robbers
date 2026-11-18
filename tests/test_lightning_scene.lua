local MODULE = "copsAndRobbers/lightningScene"
local MATERIAL = "cnrLightningBoltRod"
local SHAPE = "/art/shapes/cnrLightning/cnrLightningRod.dae"
local MATERIALS = "/art/shapes/cnrLightning/main.materials.json"

local function point(x, y, z)
  return {x = x, y = y, z = z}
end

local shape = {
  main = {point(0, 0, 900), point(0, 0, 750), point(0, 0, 500), point(0, 0, 250), point(0, 0, 0)},
  branches = {{point(0, 0, 500), point(60, 80, 450)}},
}

local function withScene(fn)
  local env, saved = {objects = {}, created = {}, triangles = {}, logs = {}, materialLoads = 0}, {}
  local loadedScene, loadedDraw = package.loaded[MODULE], package.loaded["utils/debugDraw"]
  local stubs = {
    vec3 = point,
    quatFromDir = function(dir, up)
      env.direction, env.up = dir, up
      return {x = 0, y = 0, z = 0, w = 1}
    end,
    core_camera = {getFovDeg = function() return env.fov or 90 end},
    GFXDevice = {getVideoMode = function() return {height = env.height or 1000} end},
    FS = {fileExists = function(_, path)
      local f = io.open("client" .. path, "r")
      if not f then return false end
      f:close()
      return true
    end},
    core_environment = {
      getCloudCover = function() return env.cloudCover end,
      getCloudAltitudeKm = function() return env.cloudBase end,
      getFogDensity = function() return env.fog end,
      getFogAtmosphereHeight = function() return env.fogHeight end,
    },
    CloudLayer = {volumetricEnabled = true},
    scenetree = {
      findObject = function(name) return env.objects[name] end,
      MissionGroup = {addObject = function(_, obj) obj.inMission = true end},
    },
    loadJsonMaterialsFile = function(path)
      assertEq(path, MATERIALS)
      env.materialLoads = env.materialLoads + 1
      env.objects[MATERIAL] = {}
    end,
    color = function(r, g, b, a) return {r, g, b, a} end,
    log = function(level, tag, message) env.logs[#env.logs + 1] = {level, tag, message} end,
    createObject = function(class)
      local obj = {class = class, fields = {}, ordinal = #env.created + 1}
      env.created[obj.ordinal] = obj
      function obj:setField(field, _, value) self.fields[field] = value end
      function obj:registerObject(name)
        if env.failRegister == self.ordinal then return false end
        self.name = name
        env.objects[name] = self
      end
      function obj:setScale(scale) self.scale = point(scale.x, scale.y, scale.z) end
      function obj:setPosRot(x, y, z)
        if env.failPosition == self.ordinal then error("position failed") end
        self.pos = point(x, y, z)
      end
      function obj:delete()
        self.deletes = (self.deletes or 0) + 1
        if self.name then env.objects[self.name] = nil end
      end
      return obj
    end,
  }
  for name, value in pairs(stubs) do
    saved[name], _G[name] = _G[name], value
  end
  package.loaded[MODULE] = nil
  package.loaded["utils/debugDraw"] = {
    drawTriSolid = function(a, b, c, packed, depthTest)
      if env.failGlow then error("triangle drawing failed") end
      env.triangles[#env.triangles + 1] = {point(a.x, a.y, a.z), point(b.x, b.y, b.z), point(c.x, c.y, c.z), packed, depthTest}
    end,
  }
  local ok, err = pcall(function() fn(env, require(MODULE)) end)
  for name in pairs(stubs) do _G[name] = saved[name] end
  package.loaded[MODULE], package.loaded["utils/debugDraw"] = loadedScene, loadedDraw
  assert(ok, err)
end

test("native rods use strike-time widths and can coexist through pulse gaps", function()
  withScene(function(e, renderer)
    local landing, cam = point(10, 20, 30), point(-1000, 0, 30)
    local scene = renderer.create(shape, landing, 1000, 12, 47)
    local second = renderer.create(shape, landing, 2000, 13, 47)
    assertEq(e.materialLoads, 1)
    assertEq(#e.created, 10)
    local first, branch, neighbor = e.created[1], e.created[5], e.created[6]
    assertEq(first.name, "cnr_lightning_bolt_12_1")
    assertEq(neighbor.name, "cnr_lightning_bolt_13_1")
    for _, rod in ipairs(e.created) do
      assertEq(rod.class, "TSStatic")
      assertEq(rod.fields.shapeName, SHAPE)
      assertEq(rod.fields.collisionType, "None")
      assertEq(rod.fields.decalType, "None")
      assertEq(rod.inMission, true)
      assertEq(rod.canSave, false)
      assertEq(rod.hidden, true)
    end
    assertEq(first.pos.x, 10)
    assertEq(first.pos.y, 20)
    assertEq(first.pos.z, 855)
    assertNear(first.scale.x, 8, 1e-8)
    assertNear(first.scale.y, 157.2, 1e-8)
    assertNear(branch.scale.x, 4, 1e-8)
    assertNear(neighbor.scale.x, 16, 1e-8)
    renderer.render(scene, cam, 1, 1)
    assertEq(first.hidden, false)
    assertEq(branch.hidden, false)
    assertEq(neighbor.hidden, true)
    assertEq(#e.triangles, 500)
    local triangle = e.triangles[1]
    assertEq(triangle[4][1], 190)
    assertEq(triangle[4][2], 207)
    assertEq(triangle[4][3], 255)
    assertEq(triangle[4][4], 1)
    assertEq(triangle[5], true)

    renderer.render(scene, nil, nil)
    assertEq(#e.triangles, 500)
    assertEq(first.hidden, true)
    assertEq(branch.hidden, true)
    e.fov, e.height = 30, 2500
    renderer.render(scene, point(-900, 200, 40), 2, 0.5)
    assertEq(first.hidden, false)
    assertNear(first.scale.x, 8, 1e-8)
    assertNear(branch.scale.x, 4 * 210 / 255, 1e-8)
    assert(#e.triangles > 500 and #e.triangles < 1000)
    renderer.remove(scene)
    renderer.remove(scene)
    renderer.remove(nil)
    assertEq(first.deletes, 1)
    assertEq(branch.deletes, 1)
    assertEq(e.objects[neighbor.name], neighbor)
    assert(e.objects[MATERIAL])
    renderer.remove(second)
    assertEq(neighbor.deletes, 1)
  end)
end)

test("dense overcast buries the upper core and current camera and fog refresh the bolt and glow", function()
  withScene(function(e, renderer)
    local landing = point(0, 0, 100)
    local raisedShape = {
      main = {point(0, 0, 900), point(0, 0, 800), point(0, 0, 600), point(0, 0, 400), point(0, 0, 350), point(0, 0, 0)},
      branches = {},
    }
    local cam = point(-3000, 0, 0)
    local scene = renderer.create(raisedShape, landing, 3000, 21, 547)
    local tip, middle, foot = e.created[1], e.created[3], e.created[5]
    local width = tip.scale.x
    e.cloudCover, e.cloudBase = 3, 0.25
    renderer.render(scene, cam, 1, 1)
    assertEq(tip.hidden, true)
    assertEq(middle.hidden, false)
    assert(middle.scale.x < width and middle.scale.x > 0)
    assertEq(foot.hidden, false)
    assertNear(foot.scale.x, width, 1e-8)

    renderer.render(scene, point(-500, 0, 0), 1, 1)
    assertEq(tip.hidden, false)
    assert(tip.scale.x < width and tip.scale.x > 0)
    e.cloudCover = 0
    e.triangles = {}
    renderer.render(scene, cam, 1, 1)
    assertNear(tip.scale.x, width, 1e-8)
    assertEq(#e.triangles, 500)
    local clearCenter = e.triangles[1][1]

    e.triangles = {}
    renderer.render(scene, point(0, -3000, 0), 1, 1)
    assertEq(#e.triangles, 500)
    local movedCenter = e.triangles[1][1]
    assert(math.abs(clearCenter.x - movedCenter.x) > 1)
    assert(math.abs(clearCenter.y - movedCenter.y) > 1)

    e.fog = 1
    e.triangles = {}
    renderer.render(scene, cam, 1, 1)
    assertEq(tip.hidden, false)
    assertEq(#e.triangles, 0)
    renderer.remove(scene)
  end)
end)

test("failed native allocation cleans unregistered and registered rods while preserving other strikes", function()
  withScene(function(e, renderer)
    local landing = point(0, 0, 0)
    local first = renderer.create(shape, landing, 1000, 1, 47)
    local foreign = {ownedElsewhere = true}
    e.objects["cnr_lightning_bolt_2_2"] = foreign
    local ok, err = pcall(renderer.create, shape, landing, 1000, 2, 47)
    assertEq(ok, false)
    assert(tostring(err):find("already in use", 1, true))
    assertEq(e.objects["cnr_lightning_bolt_2_2"], foreign)
    assertEq(e.created[6].deletes, 1)

    e.failRegister = 8
    ok = pcall(renderer.create, shape, landing, 1000, 3, 47)
    assertEq(ok, false)
    assertEq(e.created[7].deletes, 1)
    assertEq(e.created[8].deletes, 1)
    assertEq(e.objects["cnr_lightning_bolt_3_1"], nil)

    e.failPosition = 10
    ok, err = pcall(renderer.create, shape, landing, 1000, 4, 47)
    assertEq(ok, false)
    assert(tostring(err):find("position failed", 1, true))
    assertEq(e.created[9].deletes, 1)
    assertEq(e.created[10].deletes, 1)
    assertEq(e.objects["cnr_lightning_bolt_4_2"], nil)
    assertEq(e.objects["cnr_lightning_bolt_1_1"], e.created[1])
    renderer.remove(first)
  end)
end)

test("a failed glow draw leaves the core available through gaps and later pulses", function()
  withScene(function(e, renderer)
    local landing, cam = point(0, 0, 0), point(-1000, 0, 0)
    local scene = renderer.create(shape, landing, 1000, 1, 47)
    e.failGlow = true
    renderer.render(scene, cam, 1, 1)
    assertEq(e.created[1].hidden, false)
    assertEq(#e.logs, 1)
    assert(e.logs[1][3]:find("triangle drawing failed", 1, true))
    renderer.render(scene, nil, nil)
    assertEq(e.created[1].hidden, true)
    e.failGlow = false
    renderer.render(scene, cam, 2, 0.5)
    assertEq(e.created[1].hidden, false)
    assertEq(#e.triangles, 0)
    renderer.remove(scene)
  end)
end)
