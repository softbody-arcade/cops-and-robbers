local lightbar = require("copsAndRobbers/lightbar")

local function slot(name, allow, default)
  return { name = name, allowTypes = { allow or name }, denyTypes = {}, default = default or "" }
end

local function fakeEnv(defs)
  local env = { calls = 0 }
  function env.getPart(name)
    env.calls = env.calls + 1
    return defs[name]
  end
  function env.compatible(s)
    local out = {}
    for name, d in pairs(defs) do
      for _, t in ipairs(s.allowTypes) do
        if d.slotType == t then out[#out + 1] = name end
      end
    end
    table.sort(out)
    return out
  end
  return env
end

local function light(slotType, electric, extra)
  local d = { slotType = slotType, props = { { "func", "mesh" }, { "$electric", "bulb" } }, slots2 = {} }
  d.slots2[1] = slot("bulb", "bulb_" .. slotType, nil)
  d.slots2[1].variables = { ["$electric"] = electric }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

test("plan adds the beacon that fits an existing empty slot, not a light bar for a missing slot", function()
  local env = fakeEnv({
    etki = { slots2 = { slot("etki_roof_accessory"), slot("etki_rollcage") } },
    etki_beaconlight = light("etki_roof_accessory", "beaconSpin"),
    etki_rollcage_lightbar = light("etki_rollcage_lightbar", "highbeam"),
    etki_rollcage_police_lightbar = light("etki_rollcage_lightbar", "lightbar"),
  })
  local add = lightbar.plan("etki", {}, env)
  assertEq(add.etki_roof_accessory, "etki_beaconlight")
  assertEq(add.etki_rollcage_lightbar, nil)
end)

test("plan ignores work light bars", function()
  local env = fakeEnv({
    pickup = { slots2 = { slot("pickup_roof") } },
    pickup_desert_lightbar = light("pickup_roof", "foglight_filament"),
  })
  assertEq(lightbar.plan("pickup", {}, env), nil)
end)

test("plan returns nil when the car already has an emergency light", function()
  local env = fakeEnv({
    van = { slots2 = { slot("van_roof"), slot("van_rear") } },
    van_lightbar_c = light("van_roof", "L1_b"),
    van_lightbar_rear_c = light("van_rear", "L1_r"),
  })
  assertEq(lightbar.plan("van", { van_roof = "van_lightbar_c" }, env), nil)
end)

test("plan counts a light installed through a slot default", function()
  local env = fakeEnv({
    car = { slots2 = { slot("car_roof", nil, "car_lightbar") } },
    car_lightbar = light("car_roof", "lightbar"),
  })
  assertEq(lightbar.plan("car", {}, env), nil)
end)

test("plan walks into installed parts to find nested empty slots", function()
  local env = fakeEnv({
    car = { slots2 = { slot("car_body") } },
    car_body_sedan = { slotType = "car_body", slots2 = { slot("car_roof_accessory") } },
    car_lightbar = light("car_roof_accessory", "lightbar"),
  })
  assertEq(lightbar.plan("car", { car_body = "" }, env), nil)
  assertEq(lightbar.plan("car", { car_body = "car_body_sedan" }, env).car_roof_accessory, "car_lightbar")
end)

test("plan prefers light bars, then police names, then alphabetical", function()
  local env = fakeEnv({
    car = { slots2 = { slot("roof") } },
    car_beaconlight = light("roof", "beaconSpin"),
    car_lightbar_b = light("roof", "lightbar"),
    car_lightbar_police = light("roof", "lightbar"),
  })
  assertEq(lightbar.plan("car", {}, env).roof, "car_lightbar_police")
end)

test("plan fills every empty emergency slot", function()
  local env = fakeEnv({
    midtruck = { slots2 = { slot("beacon_FL"), slot("beacon_FR"), slot("bumper") } },
    midtruck_beaconlight_FL = light("beacon_FL", "beaconSpin"),
    midtruck_beaconlight_FR = light("beacon_FR", "beaconSpin"),
  })
  local add = lightbar.plan("midtruck", {}, env)
  assertEq(add.beacon_FL, "midtruck_beaconlight_FL"); assertEq(add.beacon_FR, "midtruck_beaconlight_FR"); assertEq(add.bumper, nil)
end)

test("plan never adds colors, patterns or bulbs as the light", function()
  local env = fakeEnv({
    car = { slots2 = { slot("beacon_color") } },
    beacon_color_red = light("beacon_color", "beaconSpin"),
  })
  assertEq(lightbar.plan("car", {}, env), nil)
end)

test("plan survives missing parts and cycles", function()
  local env = fakeEnv({
    car = { slots2 = { slot("a", nil, "loop"), slot("b", nil, "ghost") } },
    loop = { slotType = "a", slots2 = { slot("back", "a", "car") } },
  })
  assertEq(lightbar.plan("car", {}, env), nil)
  assertEq(lightbar.plan("missing", {}, env), nil)
end)

test("isEmergency finds emergency electrics in the part and its default sub-parts", function()
  local defs = {
    mount = { slots2 = { slot("unit", "unit", "unit_b") } },
    unit_b = { variables = { ["$electric"] = "R2_b" } },
    spin = light("x", "beaconSpin"),
    work = light("x", "highbeam"),
    direct = { props = { { "func" }, { "lightbar_L", "mesh", { electric = "lightbar" } } } },
  }
  local get = function(n) return defs[n] end
  assertEq(lightbar.isEmergency("mount", get), true)
  assertEq(lightbar.isEmergency("spin", get), true)
  assertEq(lightbar.isEmergency("direct", get), true)
  assertEq(lightbar.isEmergency("work", get), false)
  assertEq(lightbar.isEmergency("nope", get), false)
end)

test("isMainLight counts the light itself, not its bulbs, colors or patterns", function()
  assertEq(lightbar.isMainLight("burnside_beaconlight_red"), true)
  assertEq(lightbar.isMainLight("miramar_lightbar"), true)
  assertEq(lightbar.isMainLight("beaconLightBulb_incandescent_80W_1"), false)
  assertEq(lightbar.isMainLight("beacon_color_amber"), false)
  assertEq(lightbar.isMainLight("lightbar_pattern_police"), false)
  assertEq(lightbar.isMainLight(""), false)
  assertEq(lightbar.isMainLight(nil), false)
end)
