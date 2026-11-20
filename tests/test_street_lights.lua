local streetLights = require("copsAndRobbers/streetLights")

local function point(x, y, z)
  return {x = x, y = y, z = z}
end

local function withScene(run)
  local oldTree, oldVec3 = scenetree, vec3
  local names, objects, ids = {PointLight = {}, SpotLight = {}, TSStatic = {}}, {}, {}
  local classReads, findNames, findIds, rays = {}, {}, {}, {}
  local scene = {ids = ids, classReads = classReads, findNames = findNames, findIds = findIds, rays = rays}

  vec3 = point
  scenetree = {
    findClassObjects = function(class)
      classReads[class] = (classReads[class] or 0) + 1
      return names[class]
    end,
    findObject = function(name)
      findNames[#findNames + 1] = name
      return objects[name]
    end,
    findObjectById = function(id)
      findIds[#findIds + 1] = id
      return ids[id]
    end,
  }

  function scene.add(id, name, class, position, direct, dynamic, persisted)
    local object = direct or {}
    object.position = position
    object.getID = function() return id end
    object.getName = function() return name end
    object.getClassName = function() return class end
    object.getPosition = function(self) return self.position end
    object.getDynDataFieldbyName = function(_, key, index)
      local field = dynamic and dynamic[key]
      if type(field) == "table" then return field[index] or "" end
      return index == 0 and field or ""
    end
    object.getField = function(_, key, index)
      local field = persisted and persisted[key]
      if type(field) == "table" then return field[index] or "" end
      return index == 0 and field or ""
    end
    if names[class] then table.insert(names[class], name) end
    objects[name], ids[id] = object, object
    return object
  end

  function scene.pointLight(id, name, position, radius)
    return scene.add(id, name, "PointLight", position, {nightLight = "1", isEnabled = true, intensity = 50, radius = radius})
  end

  function scene.spotLight(id, name, position, axis)
    local light = scene.add(id, name, "SpotLight", position, {isEnabled = true, intensity = 2500},
      {nightLight = "1"}, {range = "22", outerAngle = "160"})
    light.axis = axis
    light.getTransform = function(self)
      return {getColumn = function(_, index) return index == 1 and self.axis or nil end}
    end
    return light
  end

  function scene.cast(origin, direction, length)
    rays[#rays + 1] = {origin, direction, length}
    if scene.hit then return scene.hit(origin, direction, length) end
    return length
  end

  function scene.sample(x, y, z)
    return streetLights.strength(point(x, y, z), scene.cast)
  end

  streetLights.clear()
  local ok, err = pcall(run, scene)
  streetLights.clear()
  scenetree, vec3 = oldTree, oldVec3
  if not ok then error(err, 0) end
end

local function begin()
  streetLights.beginMissionIndex()
  streetLights.advance()
end

test("only authored light emitters can illuminate the runner", function()
  withScene(function(scene)
    local spots, points = point(0, 0, 10), point(80, 0, 5)
    scene.spotLight(1, "bridge_lightpole_light1111111", spots, point(0, 0, -1))
    scene.pointLight(2, "areaLight_cityWallLights_0360631", points, 10)
    scene.add(3, "fixture", "TSStatic", nil, nil, {child = {[0] = "linked"}})
    scene.add(4, "linked", "PointLight", point(160, 0, 5), {isEnabled = true, intensity = 1, radius = 10})
    local managed = scene.add(5, "managed", "PointLight", point(240, 0, 5), nil,
      {nightIntensity = "50"}, {isEnabled = "1", intensity = "50", radius = "10"})
    managed.getId, managed.getID = managed.getID, nil
    scene.add(6, "glowingMesh", "TSStatic", point(320, 0, 5), {nightEmissive = "1"})
    scene.add(7, "searchlight", "SpotLight", point(400, 0, 10),
      {isEnabled = true, intensity = 500, range = 22, outerAngle = 160,
        getTransform = function() return {getColumn = function() return point(0, 0, -1) end} end})
    scene.add(8, "zeroDirect", "PointLight", point(480, 0, 5),
      {nightLight = "0", isEnabled = true, intensity = 1, radius = 10})
    scene.add(9, "zeroDynamic", "PointLight", point(560, 0, 5),
      {isEnabled = true, intensity = 1, radius = 10}, {nightLight = "0", nightIntensity = "0"})
    scene.add(10, "dayOnly", "PointLight", point(640, 0, 5),
      {isEnabled = true, intensity = 1, radius = 10}, {dayIntensity = "50"})
    scene.add(11, "directIntensity", "PointLight", point(720, 0, 5),
      {nightIntensity = 50, isEnabled = true, intensity = 1, radius = 10})
    begin()

    for _, x in ipairs({0, 80, 160, 240, 720}) do assertEq(scene.sample(x, 0, 0), 1, "x=" .. x) end
    for _, x in ipairs({320, 400, 480, 560, 640}) do assertEq(scene.sample(x, 0, 0), 0, "x=" .. x) end
  end)
end)

test("a point light tapers beyond half radius and follows live enabled state and intensity", function()
  withScene(function(scene)
    local lamp = scene.pointLight(1, "point", point(0, 0, 10), 10)
    begin()
    assertEq(scene.sample(0, 0, 5), 1)
    assertEq(scene.sample(0, 0, 2.5), 0.5)
    assertEq(scene.sample(0, 0, 0), 0)
    lamp.isEnabled = false
    assertEq(scene.sample(0, 0, 5), 0)
    lamp.isEnabled = "0"
    assertEq(scene.sample(0, 0, 5), 0)
    lamp.isEnabled, lamp.intensity = "1", 0
    assertEq(scene.sample(0, 0, 5), 0)
    lamp.intensity = 5
    assertEq(scene.sample(0, 0, 5), 1)
  end)
end)

test("the live light getter overrides the saved enabled field in both directions", function()
  withScene(function(scene)
    local lamp = scene.pointLight(1, "point", point(0, 0, 5), 10)
    local live
    lamp.getLightEnabled = function() return live end
    begin()
    for _, row in ipairs({
      {true, false, 1},
      {false, true, 0},
      {"1", "0", 1},
      {"0", "1", 0},
    }) do
      live, lamp.isEnabled = row[1], row[2]
      assertEq(scene.sample(0, 0, 0), row[3], "live enabled value " .. tostring(live))
    end
  end)
end)

test("the saved enabled field is used when the live getter is unavailable", function()
  withScene(function(scene)
    local lamp = scene.add(1, "point", "PointLight", point(0, 0, 5), {nightLight = "1", intensity = 50, radius = 10},
      nil, {isEnabled = "1"})
    lamp.getLightEnabled = function() error("getter unavailable") end
    begin()
    assertEq(scene.sample(0, 0, 0), 1)
    lamp.getLightEnabled = function() return "unknown" end
    assertEq(scene.sample(0, 0, 0), 1)
  end)
end)

test("overlapping emitters contribute their strongest single clear strength", function()
  withScene(function(scene)
    scene.pointLight(1, "smaller", point(0, 0, 7.5), 10)
    scene.pointLight(2, "larger", point(0, 0, 9), 15)
    begin()
    local strength = scene.sample(0, 0, 0)
    assert(strength == strength)
    assertNear(strength, 0.8, 1e-9)
    scene.hit = function(origin, _, length) return origin.z == 9 and 0 or length end
    assertEq(scene.sample(0, 0, 0), 0.5)
  end)
end)

test("missing or non-finite light fields contribute no illumination", function()
  withScene(function(scene)
    local lamp = scene.pointLight(1, "point", point(0, 0, 5), 10)
    begin()
    for _, field in ipairs({"position", "intensity", "radius", "isEnabled"}) do
      local old = lamp[field]
      lamp[field] = nil
      assertEq(scene.sample(0, 0, 0), 0, field)
      lamp[field] = old
    end
    lamp.position = point(0, 0, math.huge)
    assertEq(scene.sample(0, 0, 0), 0)
    lamp.position = point(0, 0, 5)
    lamp.intensity = 0 / 0
    assertEq(scene.sample(0, 0, 0), 0)
    lamp.intensity, lamp.radius = 50, math.huge
    assertEq(scene.sample(0, 0, 0), 0)
    assertEq(#scene.rays, 0)
  end)
end)

test("a spotlight illuminates the runner inside the world-space outer half-angle", function()
  withScene(function(scene)
    local lamp = scene.spotLight(1, "spot", point(0, 0, 0), point(0, 0, -2))
    begin()
    assertEq(scene.sample(0, 0, -9), 1)
    assertEq(scene.rays[1][1].z, 0)
    assertEq(scene.rays[1][2].z, -1)
    assertEq(scene.rays[1][3], 9)
    lamp.axis = point(0, 0, 1)
    assertEq(scene.sample(0, 0, -9), 0)
    lamp.axis = point(0, 0, -1)
    local inner, outer = math.rad(79), math.rad(81)
    assertEq(scene.sample(9 * math.sin(inner), 0, -9 * math.cos(inner)), 1)
    assertEq(scene.sample(9 * math.sin(outer), 0, -9 * math.cos(outer)), 0)
    for _, axis in ipairs({point(0, 0, 0), point(0, 0, math.huge), point(0, nil, -1)}) do
      lamp.axis = axis
      assertEq(scene.sample(0, 0, -9), 0)
    end
    lamp.axis = nil
    assertEq(scene.sample(0, 0, -9), 0)
    assertEq(#scene.rays, 2)
  end)
end)

test("a spotlight requires a finite clearance ray within half a metre of the runner", function()
  withScene(function(scene)
    scene.spotLight(1, "spot", point(0, 0, 0), point(0, 0, -1))
    begin()
    scene.hit = function(_, _, length) return length - 0.51 end
    assertEq(scene.sample(0, 0, -9), 0)
    scene.hit = function(_, _, length) return length - 0.49 end
    assertEq(scene.sample(0, 0, -9), 1)
    scene.hit = function() return nil end
    assertEq(scene.sample(0, 0, -9), 0)
    scene.hit = function() error("cast unavailable") end
    assertEq(scene.sample(0, 0, -9), 0)
    scene.hit = function() return math.huge end
    assertEq(scene.sample(0, 0, -9), 0)
    assertEq(streetLights.strength(nil, scene.cast), 0)
    assertEq(streetLights.strength(point(0, 0, -9)), 0)
  end)
end)

test("mission discovery queues each class once and budgets child names with scene names", function()
  withScene(function(scene)
    for id = 1, 299 do
      scene.add(id, "lamp" .. id, "PointLight", point(0, 0, 5), {isEnabled = true, intensity = 50, radius = 10})
    end
    local missing = {}
    for i = 1, 45 do missing[i] = "missing" .. i end
    scene.add(300, "fixture", "TSStatic", nil, nil,
      {child = {[0] = table.concat(missing, ", ")}},
      {child = {[1] = table.concat(missing, " ") .. ", lamp299", [3] = "lamp1"}})
    streetLights.beginMissionIndex()
    streetLights.beginMissionIndex()
    for _, class in ipairs({"PointLight", "SpotLight", "TSStatic"}) do assertEq(scene.classReads[class], 1) end
    assertEq(#scene.findNames, 0)
    for frame = 1, 4 do
      local previous = #scene.findNames
      streetLights.advance()
      assert(#scene.findNames - previous <= 128)
      assertEq(scene.sample(0, 0, 0), frame == 4 and 1 or 0)
    end
    assertEq(#scene.findNames, 391)
    assertEq(scene.findNames[391], "lamp299")
    streetLights.advance()
    assertEq(#scene.findNames, 391)
    streetLights.clear()
    assertEq(scene.sample(0, 0, 0), 0)
    streetLights.beginMissionIndex()
    for _, class in ipairs({"PointLight", "SpotLight", "TSStatic"}) do assertEq(scene.classReads[class], 2) end
  end)
end)

test("a light across a cell boundary uses a maximum radius of 32 metres", function()
  withScene(function(scene)
    scene.pointLight(1, "point", point(-1, 0, 0), 80)
    begin()
    assertEq(scene.sample(15, 0, 0), 1)
    assertEq(scene.sample(23, 0, 0), 0.5)
    assertEq(scene.sample(31, 0, 0), 0)
  end)
end)

test("each of nine nearby cells retains the lowest sixteen distinct IDs", function()
  withScene(function(scene)
    local lastId = 0
    for _, x in ipairs({-1, 1, 32}) do
      for _, y in ipairs({-1, 1, 32}) do
        for id = lastId + 17, lastId + 1, -1 do
          scene.pointLight(id, "lamp" .. id, point(x, y, 5), 32)
        end
        lastId = lastId + 17
      end
    end
    scene.add(154, "fixture", "TSStatic", nil, nil, {child = {[0] = "lamp1 lamp17 lamp18"}})
    scene.hit = function() return 0 end
    begin()
    streetLights.advance()

    assertEq(scene.sample(0, 0, 0), 0)
    assertEq(#scene.findIds, 144)
    assertEq(#scene.rays, 8)
    local retained = {}
    for _, id in ipairs(scene.findIds) do
      assertEq(retained[id], nil, "duplicate ID " .. id)
      retained[id] = true
    end
    for id = 1, 153 do assertEq(retained[id] == true, id % 17 ~= 0, "ID " .. id) end
  end)
end)

test("the nearest eight candidates break equal 3D distances by ID before testing clearance", function()
  withScene(function(scene)
    scene.pointLight(9, "lamp9", point(24, 22, 0), 32)
    for id = 8, 1, -1 do scene.pointLight(id, "lamp" .. id, point(16, 16, 10), 32) end
    scene.hit = function(origin, _, length) return origin.x == 24 and length or 0 end
    begin()

    assertEq(scene.sample(16, 16, 0), 0)
    assertEq(#scene.rays, 8)
    scene.ids[9].position = point(24, 21, 0)
    assertEq(scene.sample(16, 16, 0), 1)
  end)
end)

test("a disabled near candidate still counts against the eight-candidate limit", function()
  withScene(function(scene)
    for id = 1, 8 do
      scene.pointLight(id, "lamp" .. id, point(0, 0, id), 32).isEnabled = false
    end
    scene.pointLight(9, "lamp9", point(0, 0, 9), 32)
    begin()
    assertEq(scene.sample(0, 0, 0), 0)
    assertEq(#scene.rays, 0)
  end)
end)

test("the index ignores removed emitters and IDs reused by a different name or class", function()
  withScene(function(scene)
    scene.pointLight(1, "original", point(0, 0, 5), 10)
    begin()
    assertEq(scene.sample(0, 0, 0), 1)
    scene.ids[1] = nil
    assertEq(scene.sample(0, 0, 0), 0)
    scene.pointLight(1, "replacement", point(0, 0, 5), 10)
    assertEq(scene.sample(0, 0, 0), 0)
    scene.spotLight(1, "original", point(0, 0, 5), point(0, 0, -1))
    assertEq(scene.sample(0, 0, 0), 0)
  end)
end)
