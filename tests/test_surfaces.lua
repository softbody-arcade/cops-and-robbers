dofile("tests/env_stubs.lua")
local function load()
  package.loaded["copsAndRobbers/surfaces"] = nil
  return require("copsAndRobbers/surfaces")
end
local function cd(fake, name) return fake.models[name].cdata end

test("rain makes asphalt the game's wet asphalt, aliases included", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("rain")
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.92)
  assertEq(cd(fake, "ASPHALT").roughnessCoefficient, 0.2)
  local names = {}
  for _, m in ipairs(fake.modelSets) do names[m.name] = true end
  assertEq(names.ASPHALT, true); assertEq(names.CONCRETE, true)
end)

test("rain makes dirt wet gravel, a storm makes it mud", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("rain"); assertEq(cd(fake, "DIRT").staticFrictionCoefficient, 0.62)
  s.apply("storm"); assertEq(cd(fake, "DIRT").defaultDepth, 0.15)
  assertEq(cd(fake, "GRAVEL").staticFrictionCoefficient, 0.62)
end)

test("grass and rumble strips are scaled, not replaced", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("storm")
  assertNear(cd(fake, "GRASS").staticFrictionCoefficient, 0.61 * 0.75, 1e-9)
  assertNear(cd(fake, "GRASS").roughnessCoefficient, 0.43, 1e-9)
  assertNear(cd(fake, "RUMBLE_STRIP").slidingFrictionCoefficient, 0.70 * 0.79, 1e-9)
  assertNear(cd(fake, "RUMBLE_STRIP").roughnessCoefficient, 0.5, 1e-9)
end)

test("snow covers roads, dirt, grass and wet ground but not sand", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("snow")
  for _, n in ipairs({ "ASPHALT", "RUMBLE_STRIP", "GRAVEL", "DIRT", "GRASS", "GRAVEL_WET", "MUD" }) do
    assertEq(cd(fake, n).staticFrictionCoefficient, 0.65, n)
  end
  assertEq(cd(fake, "SAND").staticFrictionCoefficient, 0.6)
end)

test("a new weather first puts the old surfaces back", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("snow"); s.apply("rain")
  assertEq(cd(fake, "GRAVEL_WET").staticFrictionCoefficient, 0.62)
  assertEq(cd(fake, "DIRT").staticFrictionCoefficient, 0.62)
  s.apply("clear")
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.98)
end)

test("restore puts every surface back, drop leaves them", function()
  local fake = fakeEnvironment(); local s = load()
  s.apply("storm"); s.restore()
  assertEq(cd(fake, "ASPHALT").slidingFrictionCoefficient, 0.70)
  assertEq(cd(fake, "DIRT").defaultDepth, 0)
  s.apply("rain"); s.drop(); s.restore()
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.92)
end)

test("blend mixes dry and wet values", function()
  local fake = fakeEnvironment(); local s = load()
  s.blend({ dry = 0.5, rain = 0.5, storm = 0, snow = 0 })
  assertNear(cd(fake, "ASPHALT").staticFrictionCoefficient, (0.98 + 0.92) / 2, 1e-9)
  assertNear(cd(fake, "GRASS").staticFrictionCoefficient, 0.61 * (1 + 0.85) / 2, 1e-9)
  assertNear(cd(fake, "GRASS").roughnessCoefficient, 0.43, 1e-9)
end)

test("a rain and snow mix reads the wet models' dry values", function()
  local fake = fakeEnvironment(); local s = load()
  s.blend({ dry = 0, rain = 0.5, storm = 0, snow = 0.5 })
  assertNear(cd(fake, "DIRT").staticFrictionCoefficient, (0.62 + 0.65) / 2, 1e-9)
  s.blend({ dry = 0, rain = 0.5, storm = 0, snow = 0.5 })
  assertNear(cd(fake, "DIRT").staticFrictionCoefficient, (0.62 + 0.65) / 2, 1e-9)
end)

test("a model is pushed only when the blend moved 5 % or reached its end", function()
  local fake = fakeEnvironment(); local s = load()
  local batches = 0
  for i = 0, 100 do
    local r = i / 100
    local before = #fake.modelSets
    s.blend({ dry = 1 - r, rain = r, storm = 0, snow = 0 })
    if #fake.modelSets > before then batches = batches + 1 end
  end
  assertEq(batches, 21)
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.92)
end)

test("restore puts the dry values back after a blend", function()
  local fake = fakeEnvironment(); local s = load()
  s.blend({ dry = 0.3, rain = 0, storm = 0.7, snow = 0 })
  s.restore()
  assertEq(cd(fake, "ASPHALT").staticFrictionCoefficient, 0.98)
  assertEq(cd(fake, "DIRT").defaultDepth, 0)
  assertEq(cd(fake, "GRASS").staticFrictionCoefficient, 0.61)
end)
