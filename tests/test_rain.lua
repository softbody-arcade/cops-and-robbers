dofile("tests/env_stubs.lua")
local fake, rain
local function load()
  fake = fakeEnvironment()
  for _, n in ipairs({ "copsAndRobbers/rain", "copsAndRobbers/shelter" }) do package.loaded[n] = nil end
  rain = require("copsAndRobbers/rain")
end

local RAIN = { dataBlock = "rain_medium", numDrops = 3000, dropSize = 1, minSpeed = 0.4, maxSpeed = 0.5, volume = 1.0 }
local STORM = { dataBlock = "rain_medium", numDrops = 7000, dropSize = 1.3, minSpeed = 0.6, maxSpeed = 0.8, volume = 2.0 }
local SNOW = { dataBlock = "Snow_menu", numDrops = 5000, dropSize = 0.2, minSpeed = 0.1, maxSpeed = 0.3 }

local function run(seconds)
  for _ = 1, math.floor(seconds * 10 + 0.5) do rain.update(0.1) end
end

local function full(spec)
  rain.target(spec, 3)
  run(3.1)
end

test("rain fades in over the blend with its sound", function()
  load()
  rain.target(RAIN, 3)
  rain.update(0.1)
  local obj = fake.objects.cnr_precipitation
  assertEq(obj:getField("dataBlock"), "rain_medium"); assertEq(obj:getField("splashSize"), "0.25"); assertEq(obj:getField("hitVehicles"), nil)
  assertEq(obj:getField("minSpeed"), "0.4"); assertEq(obj.canSave, false)
  for _ = 1, 14 do rain.update(0.1) end
  assertNear(tonumber(obj:getField("numDrops")), 1500, 120)
  for _ = 1, 20 do rain.update(0.1) end
  assertEq(obj:getField("numDrops"), "3000")
  local snd = fake.objects.cnr_rain_sound
  assertEq(snd:getField("track"), "amb_rain_medium"); assertNear(snd.volume, 1.0, 1e-6)
  assertEq(snd.playing, true); assertEq(snd.canSave, false)
end)

test("rain to clear fades out, then removes rain and sound", function()
  load()
  full(RAIN)
  rain.target(nil, 3)
  run(1.5)
  assertNear(tonumber(fake.objects.cnr_precipitation:getField("numDrops")), 1500, 220)
  run(1.6)
  assertEq(fake.objects.cnr_precipitation, nil); assertEq(fake.objects.cnr_rain_sound, nil)
  assertEq(rain.active(), false)
end)

test("rain to storm moves the count and raises the volume", function()
  load()
  full(RAIN)
  rain.target(STORM, 3)
  run(3.1)
  local obj = fake.objects.cnr_precipitation
  assertEq(obj:getField("numDrops"), "7000"); assertEq(obj:getField("minSpeed"), "0.6")
  assertNear(fake.objects.cnr_rain_sound.volume, 2.0, 1e-6)
  local created = 0
  for _, n in ipairs(fake.deleted) do if n == "cnr_precipitation" then created = created + 1 end end
  assertEq(created, 0)
end)

test("rain to snow fades out, then snow fades in without a sound", function()
  load()
  full(RAIN)
  rain.target(SNOW, 3)
  run(1.4)
  assertEq(fake.objects.cnr_precipitation:getField("dataBlock"), "rain_medium")
  run(0.2)
  local obj = fake.objects.cnr_precipitation
  assertEq(obj:getField("dataBlock"), "Snow_menu")
  local drops = tonumber(obj:getField("numDrops"))
  assertEq(drops > 0 and drops < 2000, true, tostring(drops))
  assertEq(fake.objects.cnr_rain_sound, nil)
  run(1.5)
  obj = fake.objects.cnr_precipitation
  assertEq(obj:getField("dataBlock"), "Snow_menu"); assertEq(obj:getField("numDrops"), "5000")
  assertEq(fake.objects.cnr_rain_sound, nil)
end)

test("a second target mid-fade heads for the newest one and never makes two objects", function()
  load()
  local made, make = 0, _G.createObject
  _G.createObject = function(kind)
    if kind == "Precipitation" then made = made + 1 end
    return make(kind)
  end
  rain.target(RAIN, 3); run(1)
  rain.target(STORM, 3); run(1)
  rain.target(nil, 3); run(3.1)
  assertEq(fake.objects.cnr_precipitation, nil); assertEq(fake.objects.cnr_rain_sound, nil)
  local n = 0
  for _, name in ipairs(fake.deleted) do if name == "cnr_precipitation" then n = n + 1 end end
  assertEq(n, 1)
  assertEq(made, 1)
  _G.createObject = make
end)

local function volumes(seconds, snd)
  local list = {}
  for _ = 1, math.floor(seconds * 10 + 0.5) do
    rain.update(0.1)
    local s = fake.objects.cnr_rain_sound
    list[#list + 1] = s and s.volume or 0
  end
  return list
end

local function assertFalling(list)
  for i = 2, #list do assertEq(list[i] <= list[i - 1] + 1e-6, true) end
  assertNear(list[#list], 0, 1e-6)
end

test("a same-weather re-apply leaves no ramp, so the round end fades the sound", function()
  load()
  full(RAIN); rain.target(RAIN, 3); run(0.5)
  rain.target(nil, 3); run(1.5)
  assertNear(fake.objects.cnr_rain_sound.volume, 0.5, 0.1)
end)

test("rain to storm then clear: the volume falls steadily to nothing", function()
  load()
  full(RAIN); rain.target(STORM, 3); run(1)
  rain.target(nil, 3)
  assertFalling(volumes(3.2))
end)

test("rain to snow: the rain sound falls steadily to nothing before the rain goes", function()
  load()
  full(RAIN); rain.target(SNOW, 3)
  local list = volumes(1.5)
  assertFalling(list)
  assertEq(fake.objects.cnr_precipitation ~= nil, true)
end)

test("a zero length target lands at once", function()
  load()
  rain.target(STORM, 0)
  assertEq(fake.objects.cnr_precipitation:getField("numDrops"), "7000")
  rain.clear()
  assertEq(fake.objects.cnr_precipitation, nil); assertEq(fake.objects.cnr_rain_sound, nil)
  assertEq(rain.active(), false)
end)

local function withRoof(height, fn)
  local oldCast, oldCamera = _G.castRayStatic, _G.core_camera
  local roof = { height = height }
  _G.core_camera = { getPosition = function() return vec3(0, 0, 0) end }
  _G.castRayStatic = function(pos, dir, len)
    if roof.height and roof.height < len then return roof.height end
    return len + 1
  end
  local ok, err = pcall(fn, roof)
  _G.castRayStatic, _G.core_camera = oldCast, oldCamera
  if not ok then error(err, 0) end
end

test("the roof lowers the sound to half and hides the rain", function()
  withRoof(nil, function(roof)
    load()
    full(RAIN)
    assertEq(fake.objects.cnr_precipitation:getField("hidden"), nil)
    assertNear(fake.objects.cnr_rain_sound.volume, 1.0, 1e-6)
    roof.height = 3
    rain.update(0.25)
    assertEq(fake.objects.cnr_precipitation:getField("hidden"), nil)
    rain.update(0.25); rain.update(0.25); rain.update(0.25)
    assertEq(fake.objects.cnr_precipitation:getField("hidden"), "1")
    assertNear(fake.objects.cnr_rain_sound.volume, 0.5, 1e-6)
  end)
end)

test("the roof does not carry over from a round's faded rain to the next round's rain", function()
  withRoof(3, function(roof)
    load()
    full(RAIN)
    run(1)
    assertEq(fake.objects.cnr_precipitation:getField("hidden"), "1")
    rain.target(nil, 3)
    run(3.1)
    assertEq(rain.active(), false)
    roof.height = nil
    rain.target(RAIN, 3)
    run(0.3)
    local obj = fake.objects.cnr_precipitation
    assertEq(obj:getField("hidden"), nil)
    assertNear(fake.objects.cnr_rain_sound.volume, tonumber(obj:getField("numDrops")) / RAIN.numDrops, 0.01)
  end)
end)

local function countWrites()
  local obj = fake.objects.cnr_precipitation
  local snd = fake.objects.cnr_rain_sound
  local drops, vols = 0, 0
  setmetatable(obj, { __newindex = function(t, k, v) if k == "numDrops" then drops = drops + 1 end rawset(t, k, v) end })
  if snd then
    local old = snd.setVolumePitchCT
    snd.setVolumePitchCT = function(...) vols = vols + 1; return old(...) end
  end
  for _ = 1, 60 do rain.update(1 / 60) end
  return drops, vols
end

test("at rest rain writes nothing", function()
  load()
  full(RAIN)
  local drops, vols = countWrites()
  assertEq(drops, 0); assertEq(vols, 0)
end)

test("at rest snow writes nothing", function()
  load()
  full(SNOW)
  local drops = countWrites()
  assertEq(drops, 0)
end)

local function sampleVolume(spec, from)
  load()
  full(from)
  rain.target(spec, 3)
  local lo, hi = math.huge, -math.huge
  for _ = 1, 190 do
    rain.update(1 / 60)
    local v = fake.objects.cnr_rain_sound.volume
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  return lo, hi, fake.objects.cnr_rain_sound.volume
end

test("rain to storm never dips below 1.0 and ends at 2.0", function()
  local lo, _, last = sampleVolume(STORM, RAIN)
  assertEq(lo >= 1.0 - 1e-6, true); assertNear(last, 2.0, 1e-6)
end)

test("storm to rain never rises above 2.0 and ends at 1.0", function()
  local _, hi, last = sampleVolume(RAIN, STORM)
  assertEq(hi <= 2.0 + 1e-6, true); assertNear(last, 1.0, 1e-6)
end)

test("the roof halves the volume after a rain to storm change", function()
  withRoof(3, function()
    load()
    full(RAIN)
    rain.target(STORM, 3)
    run(3.1)
    rain.update(0.25); rain.update(0.25); rain.update(0.25); rain.update(0.25)
    assertNear(fake.objects.cnr_rain_sound.volume, 1.0, 1e-6)
  end)
end)
