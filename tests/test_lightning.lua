dofile("tests/env_stubs.lua")

local strikes = require("copsAndRobbers/strikes")
local LIGHT = "cnr_lightning_flash"
local function strike(at, range, roll)
  return {at = at, range = range, bearing = 0, soundRoll = roll or 0, shapeSeed = 47,
    pulses = {{start = 0, length = 0.18, level = 1}, {start = 0.25, length = 0.22, level = 0.5}}}
end

local function scene(fn)
  local cast, camera, pack, draw = castRayStatic, core_camera, color, package.loaded["utils/debugDraw"]
  local savedLightning = package.loaded["copsAndRobbers/lightning"]
  local savedRain, savedSky = package.loaded["copsAndRobbers/rain"], package.loaded["copsAndRobbers/sky"]
  local between, bolt = strikes.between, strikes.bolt
  local ok, err = pcall(function()
    local e = fakeEnvironment()
    local pos = vec3(0, 0, 0)
    e.camera, e.lines, e.events, e.rays, e.queries, e.shapes, e.reads = pos, {}, {}, {}, 0, 0, 0
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
    package.loaded["utils/debugDraw"] = {LineInstance_MinArg = function(...) e.lines[#e.lines + 1] = {...} end}
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
    package.loaded["copsAndRobbers/lightning"] = nil
    local lightning = require("copsAndRobbers/lightning")
    local s = lightning.new()
    e.p, e.clock, e.flashes, e.cover, e.storm = {weather = "thunderstorm", lightningSeed = 7}, 0, true, false, true
    function e.tick(hi)
      lightning.tick(s, e.p, e.clock, hi, e.runner, e.flashes, e.cover, e.storm)
      e.clock = hi
    end
    fn(e, lightning, s)
  end)
  _G.castRayStatic, _G.core_camera, _G.color, package.loaded["utils/debugDraw"] = cast, camera, pack, draw
  package.loaded["copsAndRobbers/rain"], package.loaded["copsAndRobbers/sky"] = savedRain, savedSky
  package.loaded["copsAndRobbers/lightning"] = savedLightning
  strikes.between, strikes.bolt = between, bolt
  assert(ok, err)
end

test("landing and sound use the runner and strike-time 3D camera distance through both pulses", function()
  scene(function(e, lightning, s)
    e.runner = {getPosition = function() return vec3(20, 30, 45) end}
    e.camera, e.hit, e.events = vec3(20, 30, 400), 2400, {strike(1, 1200)}
    e.tick(1)
    assertEq(#e.rays, 1)
    local ray = e.rays[1]
    assertEq(ray[1].x, 20); assertEq(ray[1].y, 1230); assertEq(ray[1].z, 2500)
    assertEq(ray[2].z, -1); assertEq(ray[3], 5000)
    local l = assert(e.objects[LIGHT])
    assertEq(l.class, "PointLight"); assertEq(l.inMission, true); assertEq(l.canSave, false)
    assertEq(l.fields.color, "0.75 0.82 1 1"); assertEq(l.fields.castShadows, "0")
    assertEq(tonumber(l.fields.radius), 1500)
    local str = 1e10 * 300^2 / (1200^2 + 300^2)
    assertNear(tonumber(l.fields.brightness), str, 0.001); assertNear(tonumber(l.fields.intensity), str, 0.001)
    assertEq(l.fields.isEnabled, "1")
    assertEq(table.concat(l.writes, ",", #l.writes - 3), "isEnabled,brightness,intensity,postApply")
    assertEq(l.pos.z, 700)
    local n = #e.lines
    local mainFoot = e.lines[64]
    assertEq(#mainFoot, 8)
    assertEq(mainFoot[4], 20); assertEq(mainFoot[5], 1230); assertEq(mainFoot[6], 100)
    assertEq(mainFoot[7], 4); assertEq(table.concat(mainFoot[8], ","), "235,240,255,255")
    assertEq(e.lines[65][7], 2)
    e.p = {weather = "clear", lightningSeed = 7}
    e.camera = vec3(8000, 9100, 9)
    e.tick(1.2)
    assertEq(#e.lines, n); assertEq(e.shapes, 1); assertEq(l.fields.isEnabled, "0")
    assertEq(lightning.hasVisualTail(s), true)
    e.tick(1.3)
    assertEq(e.objects[LIGHT], l); assertEq(l.pos.x, 8000); assertEq(l.pos.z, 309)
    assertNear(tonumber(l.fields.intensity), str / 2, 0.001)
    assertEq(#e.lines, 2 * n); assertEq(e.shapes, 1); assertEq(#e.rays, 1)
    assertEq(e.lines[n + 65][8][4] < e.lines[65][8][4], true)
    e.storm = false
    e.tick(1.5)
    assertEq(e.objects[LIGHT], nil); assertEq(lightning.hasVisualTail(s), false)
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

local function assertLightPosition(light, x, y, z)
  assertNear(light.pos.x, x, 1e-6)
  assertNear(light.pos.y, y, 1e-6)
  assertNear(light.pos.z, z, 1e-6)
end

test("a close strike keeps its side light fixed while the camera moves between pulses", function()
  scene(function(e)
    e.events = {strike(1, 600)}
    e.tick(1)
    local light = assert(e.objects[LIGHT])
    assertEq(light.fields.castShadows, "1")
    assertEq(tonumber(light.fields.radius), 1500)
    assertLightPosition(light, 0, 240, 180)
    assertNear(tonumber(light.fields.intensity), 2.5e9, 0.001)
    local foot = e.lines[64]
    assertEq(foot[4], 0); assertEq(foot[5], 600); assertEq(foot[6], 0)
    e.camera = vec3(2000, -900, 75)
    e.tick(1.2)
    assertEq(light.fields.isEnabled, "0")
    e.tick(1.3)
    assertEq(e.objects[LIGHT], light); assertEq(light.fields.castShadows, "1")
    assertLightPosition(light, 0, 240, 180)
    assertNear(tonumber(light.fields.intensity), 1.25e9, 0.001)
    local due = 1 + 600 / 343
    e.tick(due - 0.001)
    assertEq(#e.played, 0)
    e.tick(due + 0.001)
    assertEq(#e.played, 1); assertEq(e.played[1].fields.fileName, "/art/sound/cnr/thunder_close_1.ogg")
  end)
end)

test("the shadow cutoff uses the 3D landing distance and excludes exactly 1 km", function()
  for _, case in ipairs({{1000, 0, "0"}, {800, 601, "0"}, {800, 599, "1"}}) do
    scene(function(e)
      local range, height, shadows = case[1], case[2], case[3]
      e.camera, e.hit, e.events = vec3(0, 0, height), 2500, {strike(1, range)}
      e.tick(1)
      local light = assert(e.objects[LIGHT])
      assertEq(light.fields.castShadows, shadows)
      if shadows == "0" then
        assertLightPosition(light, 0, 0, height + 300)
      else
        assertEq(light.pos.y > 0 and light.pos.z < height, true)
      end
    end)
  end
end)

test("a close strike whose channel midpoint coincides with the camera lights from overhead", function()
  scene(function(e)
    e.runner = {getPosition = function() return vec3(10, -600, 0) end}
    e.camera, e.events = vec3(10, 0, 450), {strike(1, 600)}
    e.tick(1)
    local light = assert(e.objects[LIGHT])
    assertEq(light.fields.castShadows, "1")
    assertEq(light.pos.x, 10); assertEq(light.pos.y, 0); assertEq(light.pos.z, 750)
  end)
end)

test("nil and full-length ground misses use reference height, with the bolt cutoff inclusive", function()
  for i, range in ipairs({4000, 4000.01}) do
    scene(function(e)
      e.camera, e.events = vec3(-100, 72, -20), {strike(1, range)}
      if i == 2 then e.hit = 5000 end
      e.tick(1)
      assertEq(e.objects[LIGHT] ~= nil, true)
      assertEq(e.rays[1][1].x, -100); assertEq(e.rays[1][1].y, 72 + range)
      assertNear(tonumber(e.objects[LIGHT].fields.intensity), 1e10 * (300 / range)^2, 0.001)
      assertEq(e.shapes, i == 1 and 1 or 0)
      if i == 1 then assertEq(e.lines[64][6], -20) else assertEq(#e.lines, 0) end
    end)
  end
end)

test("cover, the preference and hide cancel the remaining flash and keep thunder", function()
  for _, mode in ipairs({"cover", "unconfirmed", "off", "hide"}) do
    scene(function(e, lightning, s)
      e.events = {strike(1, 343)}
      e.tick(1)
      local n = #e.lines
      if mode == "hide" then lightning.hide(s)
      elseif mode == "off" then e.flashes = false
      elseif mode == "unconfirmed" then e.cover = nil
      else e.cover = true end
      e.tick(1.05)
      assertEq(e.objects[LIGHT], nil); assertEq(lightning.hasVisualTail(s), false)
      e.cover, e.flashes = false, true
      e.tick(1.3)
      assertEq(#e.lines, n)
      e.tick(2)
      assertEq(#e.played, 1)
    end)
  end
end)

test("overlapping close and distant bolts share one light as their pulse strengths change", function()
  scene(function(e)
    e.events = {strike(1, 900), strike(1.12, 1050)}
    e.tick(1.15)
    local light = assert(e.objects[LIGHT])
    assertEq(light.fields.castShadows, "1")
    assertLightPosition(light, 0, 268.328157, 134.164079)
    assertNear(tonumber(light.fields.intensity), 1e10 * (300 / 900)^2, 0.001)
    assertEq(e.shapes, 2)
    e.camera = vec3(-30, 80, 10)
    e.tick(1.26)
    assertEq(e.objects[LIGHT], light); assertEq(light.fields.castShadows, "0")
    assertLightPosition(light, -30, 80, 310)
    assertNear(tonumber(light.fields.intensity), 1e10 * (300 / 1050)^2, 0.001)
    e.tick(9)
    assertEq(#e.played, 2)
  end)
end)

test("the newer of two equally bright close bolts controls the light direction", function()
  scene(function(e)
    local older, newer = strike(1, 600), strike(1.05, 600)
    newer.bearing = 180
    e.events = {older, newer}
    e.tick(1.1)
    local light = assert(e.objects[LIGHT])
    assertLightPosition(light, 0, -240, 180)
    assertEq(light.fields.castShadows, "1"); assertEq(e.shapes, 2)
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
    scenetree.findObject = function(name) finds = finds + 1; return e.objects[name] end
    e.tick(1)
    assertEq(finds, 0); assertEq(e.queries, 0); assertEq(e.reads, 0); assertEq(#e.rays, 0); assertEq(#e.lines, 0)
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
      local n = #e.lines
      e.p = {lightningSeed = 12}
      e.tick(10)
      assertEq(#e.lines, n); assertEq(#e.played, 1)
    end)
  end
end)

test("a failed scene registration cleans the partial object and a light failure still allows thunder", function()
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
        assertEq(e.objects[LIGHT], nil); assertEq(#e.played, 1)
      else assertEq(e.objects.cnr_thunder_1, nil) end
      assertEq(#e.deleted > 0, true)
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
      assertEq(#e.lines > 0, mode == "open")
      e.roof, e.roofError = 3, false
      sky.update(0.25, lightning.hasVisualTail(s))
      frame, lo, hi, covered, storm = sky.lightningFrame()
      assertEq(storm, false)
      if mode == "open" then assertEq(covered, true) end
      lightning.tick(s, frame, lo, hi, nil, true, covered, storm)
      assertEq(e.objects[LIGHT], nil)
      lightning.tick(s, frame, hi, 161, nil, true, covered, false)
      assertEq(#e.played, 1)
    end)
  end
end)
