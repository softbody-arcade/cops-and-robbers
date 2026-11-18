dofile("tests/env_stubs.lua")

local strikes = require("copsAndRobbers/strikes")
local LIGHT = "cnr_lightning_flash"
local MATERIAL = "cnrLightningBoltRod"
local function strike(at, range, roll)
  return {at = at, range = range, bearing = 0, soundRoll = roll or 0, shapeSeed = 47,
    pulses = {{start = 0, length = 0.18, level = 1}, {start = 0.25, length = 0.22, level = 0.5}}}
end

local function scene(fn)
  local globals = {"castRayStatic", "core_camera", "color", "quatFromDir", "FS", "loadJsonMaterialsFile"}
  local saved = {}
  for _, name in ipairs(globals) do saved[name] = _G[name] end
  local draw = package.loaded["utils/debugDraw"]
  local savedLightning = package.loaded["copsAndRobbers/lightning"]
  local savedScene = package.loaded["copsAndRobbers/lightningScene"]
  local savedRain, savedSky = package.loaded["copsAndRobbers/rain"], package.loaded["copsAndRobbers/sky"]
  local between, bolt = strikes.between, strikes.bolt
  local ok, err = pcall(function()
    local e = fakeEnvironment()
    local pos = vec3(0, 0, 0)
    e.camera, e.events, e.rays, e.queries, e.shapes, e.reads, e.glow = pos, {}, {}, 0, 0, 0, 0
    function e.rodCount(hidden)
      local count = 0
      for _, obj in pairs(e.objects) do
        if obj.class == "TSStatic" and (hidden == nil or obj.hidden == hidden) then count = count + 1 end
      end
      return count
    end
    _G.core_camera = {getPosition = function() e.reads = e.reads + 1; return e.camera end}
    _G.castRayStatic = function(origin, dir, len)
      if dir.z > 0 then
        if e.roofError then error("roof check failed") end
        return e.roof
      end
      e.rays[#e.rays + 1] = {origin, dir, len}
      return e.hit
    end
    _G.color = function(r, g, b, a) return {r, g, b, a} end
    _G.quatFromDir = function() return {x = 0, y = 0, z = 0, w = 1} end
    _G.FS = {fileExists = function() return true end}
    local material, find = nil, scenetree.findObject
    _G.loadJsonMaterialsFile = function() material = {} end
    scenetree.findObject = function(name) return name == MATERIAL and material or find(name) end
    package.loaded["utils/debugDraw"] = {drawTriSolid = function() e.glow = e.glow + 1 end}
    strikes.between = function(cursor, p, lo, hi)
      assertEq(cursor.seed, p.lightningSeed)
      if e.cursor and e.cursor.seed == cursor.seed then assertEq(cursor, e.cursor) end
      e.cursor, e.queries = cursor, e.queries + 1
      local events = {}
      for _, event in ipairs(e.events) do
        if event.at > lo and event.at <= hi then events[#events + 1] = event end
      end
      return events
    end
    strikes.bolt = function(seed) e.shapes = e.shapes + 1; return bolt(seed) end
    package.loaded["copsAndRobbers/rain"], package.loaded["copsAndRobbers/sky"] = nil, nil
    package.loaded["copsAndRobbers/lightning"], package.loaded["copsAndRobbers/lightningScene"] = nil, nil
    local lightning = require("copsAndRobbers/lightning")
    local s = lightning.new()
    e.p, e.clock, e.flashes, e.cover, e.storm = {weather = "thunderstorm", lightningSeed = 7}, 0, true, false, true
    function e.tick(hi)
      lightning.tick(s, e.p, e.clock, hi, e.runner, e.flashes, e.cover, e.storm)
      e.clock = hi
    end
    fn(e, lightning, s)
  end)
  for _, name in ipairs(globals) do _G[name] = saved[name] end
  package.loaded["utils/debugDraw"] = draw
  package.loaded["copsAndRobbers/lightningScene"] = savedScene
  package.loaded["copsAndRobbers/rain"], package.loaded["copsAndRobbers/sky"] = savedRain, savedSky
  package.loaded["copsAndRobbers/lightning"] = savedLightning
  strikes.between, strikes.bolt = between, bolt
  assert(ok, err)
end

local function assertLightPosition(light, x, y, z)
  assertNear(light.pos.x, x, 1e-6)
  assertNear(light.pos.y, y, 1e-6)
  assertNear(light.pos.z, z, 1e-6)
end

test("light uses the seeded midpoint and sound uses strike-time camera distance", function()
  scene(function(e, lightning, s)
    e.runner = {getPosition = function() return vec3(20, 30, 45) end}
    e.camera, e.hit, e.events = vec3(20, 30, 400), 2400, {strike(1, 1200)}
    e.tick(1)
    assertEq(#e.rays, 1)
    local ray = e.rays[1]
    assertEq(ray[1].x, 20); assertEq(ray[1].y, 1230); assertEq(ray[1].z, 2500)
    assertEq(ray[2].z, -1); assertEq(ray[3], 5000)
    local light = assert(e.objects[LIGHT])
    assertEq(light.class, "PointLight"); assertEq(light.inMission, true); assertEq(light.canSave, false)
    assertEq(light.fields.color, "0.75 0.82 1 1"); assertEq(light.fields.castShadows, "1")
    assertEq(tonumber(light.fields.radius), 1500)
    assertEq(tonumber(light.fields.brightness), 1e10); assertEq(tonumber(light.fields.intensity), 1e10)
    assertEq(light.fields.isEnabled, "1")
    assertLightPosition(light, 226.7140505098, 1023.0469187759, 550)
    local n, glow = e.rodCount(false), e.glow
    assert(n > 64 and glow > 0)
    e.p = {weather = "clear", lightningSeed = 7}
    e.camera = vec3(8000, 9100, 9)
    e.tick(1.2)
    assertEq(light.fields.isEnabled, "0")
    assertEq(e.rodCount(true), n)
    assertEq(e.glow, glow)
    assertEq(lightning.hasVisualTail(s), true)
    e.tick(1.3)
    assertEq(e.objects[LIGHT], light)
    assertLightPosition(light, 226.7140505098, 1023.0469187759, 550)
    assertEq(tonumber(light.fields.intensity), 5e9)
    assertEq(e.rodCount(false), n)
    assert(e.glow > glow)
    assertEq(e.shapes, 1); assertEq(#e.rays, 1)
    e.storm = false
    e.tick(1.5)
    assertEq(e.objects[LIGHT], nil); assertEq(lightning.hasVisualTail(s), false)
    assertEq(e.rodCount(), 0)
    local dist = math.sqrt(1200^2 + 300^2)
    local due = 1 + dist / 343
    e.tick(due - 0.001)
    assertEq(#e.played, 0)
    e.tick(due + 0.001)
    local snd = assert(e.objects.cnr_thunder_1)
    assertEq(snd.fields.fileName, "/art/sound/cnr/thunder_medium_1.ogg")
    assertEq(snd.fields.is3D, "0"); assertEq(snd.fields.isLooping, "0")
    assertEq(snd.inMission, true); assertEq(snd.canSave, false); assertEq(snd.playing, true)
    assertNear(snd.volume, 1 - 0.65 * (dist - 500) / 5500, 1e-8)
  end)
end)

test("the inclusive bolt cutoff uses 3D distance and overhead flashes follow the camera", function()
  for _, height in ipairs({2400, 2400.1}) do
    scene(function(e)
      e.runner = {getPosition = function() return vec3(0, 0, 0) end}
      e.camera, e.hit, e.events = vec3(0, 0, height), 2500, {strike(1, 3200)}
      e.tick(1)
      local light = assert(e.objects[LIGHT])
      if height == 2400 then
        assertEq(light.fields.castShadows, "1")
        assertLightPosition(light, 206.7140505098, 2993.0469187759, 450)
        assertEq(tonumber(light.fields.intensity), 1e10)
        assert(e.rodCount(false) > 64)
      else
        assertEq(light.fields.castShadows, "0")
        assertLightPosition(light, 0, 0, height + 300)
        local distanceSquared = 3200^2 + height^2
        assertNear(tonumber(light.fields.intensity), 1e10 * 300^2 / distanceSquared, 0.001)
        e.camera = vec3(-30, 80, 10)
        e.tick(1.3)
        assertLightPosition(light, -30, 80, 310)
        assertNear(tonumber(light.fields.intensity), 5e9 * 300^2 / distanceSquared, 0.001)
        assertEq(e.shapes, 0); assertEq(e.rodCount(), 0); assertEq(e.glow, 0)
      end
    end)
  end
end)

test("missing ground uses the reference position and height", function()
  for _, hit in ipairs({false, 5000}) do
    scene(function(e)
      e.runner = {getPosition = function() return vec3(-100, 72, -20) end}
      e.hit, e.events = hit or nil, {strike(1, 3200)}
      e.tick(1)
      assertEq(e.rays[1][1].x, -100); assertEq(e.rays[1][1].y, 3272)
      assertLightPosition(assert(e.objects[LIGHT]), 106.7140505098, 3065.0469187759, 430)
      assert(e.rodCount(false) > 64)
    end)
  end
end)

test("cover, the preference and hide remove visual objects in a dark gap and keep thunder", function()
  for _, mode in ipairs({"cover", "unconfirmed", "off", "hide"}) do
    scene(function(e, lightning, s)
      e.events = {strike(1, 343)}
      e.tick(1)
      local glow = e.glow
      e.tick(1.2)
      assert(e.rodCount(true) > 0)
      if mode == "hide" then lightning.hide(s)
      elseif mode == "off" then e.flashes = false
      elseif mode == "unconfirmed" then e.cover = nil
      else e.cover = true end
      e.tick(1.21)
      assertEq(e.objects[LIGHT], nil); assertEq(lightning.hasVisualTail(s), false)
      assertEq(e.rodCount(), 0)
      e.cover, e.flashes = false, true
      e.tick(1.3)
      assertEq(e.glow, glow)
      e.tick(2)
      assertEq(#e.played, 1)
    end)
  end
end)

test("overlapping bolts render independently while their strongest pulse controls the light", function()
  scene(function(e)
    local older, newer = strike(1, 900), strike(1.12, 1050)
    newer.bearing = 180
    e.events = {older, newer}
    e.tick(1.15)
    local light = assert(e.objects[LIGHT])
    assertEq(light.fields.castShadows, "1")
    assertLightPosition(light, 206.7140505098, -1256.9530812241, 450)
    assertEq(tonumber(light.fields.intensity), 1e10)
    assertEq(e.shapes, 2)
    local n = e.rodCount(false)
    assert(n >= 160)
    e.tick(1.26)
    assertLightPosition(light, 206.7140505098, -1256.9530812241, 450)
    assertEq(tonumber(light.fields.intensity), 1e10)
    assertEq(e.rodCount(false), n)
    e.tick(1.32)
    assertEq(e.objects[LIGHT], light)
    assertLightPosition(light, 206.7140505098, 693.0469187759, 450)
    assertEq(tonumber(light.fields.intensity), 5e9)
    assertEq(e.rodCount(true), n / 2)
    assertEq(e.rodCount(false), n / 2)
    e.tick(1.48)
    assertEq(e.rodCount(), n / 2)
    assertLightPosition(light, 206.7140505098, -1256.9530812241, 450)
    e.tick(9)
    assertEq(e.rodCount(), 0)
    assertEq(#e.played, 2)
  end)
end)

test("an overlapping distant flash takes over when the native bolt enters its gap", function()
  scene(function(e)
    e.events = {strike(1, 3000), strike(1.12, 4500)}
    e.tick(1.15)
    local light = assert(e.objects[LIGHT])
    assertEq(light.fields.castShadows, "1")
    local rods = e.rodCount(false)
    assert(rods > 0)
    e.camera = vec3(-30, 80, 10)
    e.tick(1.2)
    assertEq(e.objects[LIGHT], light)
    assertEq(light.fields.castShadows, "0")
    assertLightPosition(light, -30, 80, 310)
    assertNear(tonumber(light.fields.intensity), 1e10 * (300 / 4500)^2, 0.001)
    assertEq(e.rodCount(true), rods)
    e.tick(1.26)
    assertEq(light.fields.castShadows, "1")
    assertLightPosition(light, 206.7140505098, 2793.0469187759, 450)
    assertEq(tonumber(light.fields.intensity), 5e9)
    assertEq(e.rodCount(false), rods)
  end)
end)

test("a late frame renders the current round pulse and keeps the scheduled thunder arrival", function()
  scene(function(e)
    e.clock = 50
    e.events = {strike(49.9, 343), strike(50.01, 343), strike(50.55, 343)}
    e.tick(50.83)
    assertEq(e.shapes, 1)
    assertEq(tonumber(assert(e.objects[LIGHT]).fields.intensity), 5e9)
    assert(e.glow > 0)
    e.tick(51)
    assertEq(#e.played, 0)
    e.tick(51.03)
    assertEq(e.rodCount(), 0)
    assertEq(#e.played, 1)
    e.tick(51.56)
    assertEq(#e.played, 2)
  end)
end)

test("deadlines sort by arrival and strike order, three playing slots drop the fourth and reap from actual play", function()
  scene(function(e)
    e.flashes = false
    e.events = {strike(1, 686, 0), strike(1.5, 343, 0.9), strike(2, 343, 0.9), strike(2.5, 343, 0),
      strike(18.9, 343, 0), strike(19, 343, 0.9)}
    e.tick(5)
    assertEq(#e.played, 3)
    local close = "/art/sound/cnr/thunder_close_"
    for i, file in ipairs({"2", "1", "2"}) do
      assertEq(e.played[i].fields.fileName, close .. file .. ".ogg")
      assertEq(e.played[i].name, "cnr_thunder_" .. i)
    end
    e.tick(19.8)
    assertEq(#e.played, 3)
    e.tick(20.1)
    assertEq(#e.played, 4); assertEq(e.played[4].name, "cnr_thunder_2")
    assertEq(e.played[4].fields.fileName, close .. "2.ogg")
    e.tick(100)
    assertEq(#e.played, 4); assertEq(next(e.objects), nil)
  end)
end)

test("a missing camera loses only that strike and idle seeded frames do no scene work", function()
  scene(function(e)
    e.p.weather, e.storm = "storm", false
    local finds = 0
    local find = scenetree.findObject
    scenetree.findObject = function(name) finds = finds + 1; return find(name) end
    e.tick(1)
    assertEq(finds, 0); assertEq(e.queries, 0); assertEq(e.reads, 0); assertEq(#e.rays, 0); assertEq(e.glow, 0)
    e.events, e.camera, e.storm = {strike(2, 343), strike(3, 343)}, nil, true
    e.tick(2)
    assertEq(#e.rays, 0); assertEq(next(e.objects), nil)
    e.camera = vec3(0, 0, 0)
    e.tick(3); e.tick(4)
    assertEq(#e.rays, 1); assertEq(#e.played, 1)
  end)
end)

test("clear, absent payload and seed replacement each remove pending, playing and visible effects", function()
  for _, mode in ipairs({"clear", "payload", "seed", "invalid seed"}) do
    scene(function(e, lightning, s)
      e.events = {strike(1, 343), strike(2, 2000)}
      e.tick(1); e.tick(2)
      assertEq(#e.played, 1); assertEq(e.objects[LIGHT] ~= nil, true)
      if mode == "clear" then lightning.clear(s); lightning.clear(s)
      elseif mode == "payload" then e.p = nil; e.tick(2.01)
      elseif mode == "invalid seed" then e.p = {lightningSeed = "7"}; e.tick(2.01)
      else e.p = {lightningSeed = 12}; e.tick(2.01) end
      assertEq(next(e.objects), nil); assertEq(lightning.hasVisualTail(s), false)
      local glow = e.glow
      e.p = {lightningSeed = 12}
      e.tick(10)
      assertEq(e.glow, glow); assertEq(#e.played, 1)
    end)
  end
end)

test("failed native registration discards partial rods but keeps the flash and thunder", function()
  scene(function(e)
    local add = scenetree.MissionGroup.addObject
    local rods = 0
    scenetree.MissionGroup.addObject = function(g, obj)
      if obj.class == "TSStatic" then
        rods = rods + 1
        if rods == 3 then error("registration failed") end
      end
      return add(g, obj)
    end
    e.events = {strike(1, 343)}
    e.tick(1)
    assertEq(e.rodCount(), 0)
    assertEq(e.glow, 0)
    assertEq(#e.deleted, 3)
    local light = assert(e.objects[LIGHT])
    assertLightPosition(light, 206.7140505098, 136.0469187759, 450)
    assertEq(tonumber(light.fields.intensity), 1e10)
    e.tick(1.3)
    assertEq(tonumber(light.fields.intensity), 5e9)
    assertEq(rods, 3)
    e.tick(2)
    assertEq(e.objects[LIGHT], nil)
    assertEq(#e.played, 1)
  end)
end)

test("failed light or emitter registration releases the partial object", function()
  for _, class in ipairs({"PointLight", "SFXEmitter"}) do
    scene(function(e)
      local add = scenetree.MissionGroup.addObject
      scenetree.MissionGroup.addObject = function(g, obj)
        if obj.class == class then error("registration failed") end
        return add(g, obj)
      end
      e.events = {strike(1, 343)}
      e.tick(1); e.tick(2)
      if class == "PointLight" then
        assertEq(e.objects[LIGHT], nil)
        assertEq(#e.played, 1)
        assertEq(e.deleted[1], LIGHT)
      else
        assertEq(e.objects.cnr_thunder_1, nil)
        assertEq(e.deleted[1], "cnr_thunder_1")
      end
    end)
  end
end)

test("crossing the end of thunderstorm easing shares roof clearance until the last visual ends", function()
  for _, mode in ipairs({"roof", "camera", "ray", "open"}) do
    scene(function(e, lightning, s)
      local sky = require("copsAndRobbers/sky")
      local rain = require("copsAndRobbers/rain")
      local p = {weather = "thunderstorm", lightningSeed = 8, changes = {{at = 100, to = "clear"}}}
      sky.apply(p)
      sky.startClock(159.9)
      rain.target(nil, 0)
      e.roof, e.roofError = mode == "roof" and 3 or nil, mode == "ray"
      if mode == "camera" then e.camera = nil end
      sky.update(0.2, false)
      local frame, lo, hi, covered, storm = sky.lightningFrame()
      assertEq(frame, p); assertNear(lo, 159.9, 1e-8); assertNear(hi, 160.1, 1e-8); assertEq(storm, true)
      if mode == "open" then assertEq(covered, false)
      elseif mode == "roof" then assertEq(covered, true)
      else assertEq(covered, nil) end
      e.camera, e.events = vec3(0, 0, 0), {strike(159.95, 343)}
      lightning.tick(s, frame, lo, hi, nil, true, covered, storm)
      assertEq(e.objects[LIGHT] ~= nil, mode == "open")
      assertEq(e.rodCount(false) > 0, mode == "open")
      assertEq(e.glow > 0, mode == "open")
      e.roof, e.roofError = 3, false
      sky.update(0.25, lightning.hasVisualTail(s))
      frame, lo, hi, covered, storm = sky.lightningFrame()
      assertEq(storm, false)
      if mode == "open" then assertEq(covered, true) end
      lightning.tick(s, frame, lo, hi, nil, true, covered, storm)
      assertEq(e.objects[LIGHT], nil); assertEq(e.rodCount(), 0)
      lightning.tick(s, frame, hi, 161, nil, true, covered, false)
      assertEq(#e.played, 1)
    end)
  end
end)
