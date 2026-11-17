package.loaded["copsAndRobbers/heliModel"] = nil
local model = require("copsAndRobbers/heliModel")

local HEAD = '<?xml version="1.0"?>\n<COLLADA>\n  <library_materials>\n' ..
  '    <material id="pigeon-material" name="pigeon">\n      <instance_effect url="#pigeon-effect"/>\n    </material>\n' ..
  '    <material id="glass-material" name="pigeon">\n    </material>\n  </library_materials>\n  <library_visual_scenes>\n'
local NODE_A = '      <node id="a" name="a" type="NODE">\n        <instance_geometry url="#a-mesh"/>\n      </node>\n'
local NODE_AB = '      <node id="a_b" name="a_b" type="NODE">\n        <instance_material symbol="pigeon-material" target="#pigeon-material"/>\n      </node>\n'
local NODE_C = '      <node id="c" name="c" type="NODE">\n        <instance_geometry url="#c-mesh"/>\n      </node>\n'
local TAIL = '  </library_visual_scenes>\n  <library_geometries><geometry id="a-mesh"/></library_geometries>\n</COLLADA>\n'

local function contains(text, part) return text:find(part, 1, true) ~= nil end

local function step(p, vx, vy, dt) model.step(p, { x = vx, y = vy, z = 0 }, dt) end

local function wrap(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

local function light(r, g, b)
  for _, l in ipairs(model.LIGHTS) do
    if l.r == r and l.g == g and l.b == b and not l.beacon then return l end
  end
end

test("trim removes the listed flat nodes and keeps the rest", function()
  local src = HEAD .. NODE_A .. NODE_AB .. NODE_C .. TAIL
  local text, removed = model.trim(src, { "a", "c", "missing", "a" })
  assertEq(removed, 2)
  assertEq(contains(text, '<node id="a" '), false)
  assertEq(contains(text, '<node id="c" '), false)
  assertEq(contains(text, NODE_AB), true)
  assertEq(contains(text, "#a-mesh"), false)
  assertEq(text:sub(1, #HEAD), HEAD)
  assertEq(text:sub(-#TAIL), TAIL)
  local same, none = model.trim(src, {})
  assertEq(same, src)
  assertEq(none, 0)
  local nothing, zero = model.trim(src, { "b", "a_" })
  assertEq(nothing, src)
  assertEq(zero, 0)
end)

test("the hide list is the probe's list plus the tail lights and the cab's interior", function()
  local seen = {}
  for _, n in ipairs(model.HIDE) do
    assertEq(seen[n], nil, n)
    seen[n] = true
  end
  assertEq(#model.HIDE, 72)
  for _, n in ipairs({ "pigeon_taillight_L", "pigeon_taillight_R", "pigeon_bed", "pigeon_seat_FL", "pigeon_seat_FR", "pigeon_dash",
    "pigeon_gauges", "pigeon_needle_speedo", "pigeon_pedal_gas", "pigeon_steering_wheel", "pigeon_steeringcolumn", "pigeon_sunvisor_L",
    "pigeon_intermirror", "pigeon_windshield_int", "pigeon_doorglass_L_int", "pigeon_backlight_int", "pigeon_interiormisc" }) do
    assertEq(seen[n], true, n)
  end
  for _, n in ipairs({ "pigeon_box", "pigeon_boxdoor", "pigeon_body_3w", "pigeon_windshield", "pigeon_doorglass_L", "pigeon_backlight",
    "pigeon_headlight_L", "pigeon_signal_R", "pigeon_lightbar_L", "pigeon_mirror_L", "pigeon_hood", "pigeon_door_R" }) do
    assertEq(seen[n], nil, n)
  end
  assertEq(model.SOURCE, "/vehicles/pigeon/pigeon.dae")
  assertEq(#model.MATERIAL_FILES, 3)
  assertEq(model.MATERIAL_FILES[3], "/vehicles/pigeon/skin.materials.json")
end)

local LAMPS = '    <material id="pigeon_headlights-material" name="pigeon_headlights">\n    </material>\n' ..
  '    <material id="pigeon_signal_L-material" name="pigeon_signal_L">\n    </material>\n'

test("rename gives the listed materials new names and leaves the rest", function()
  local src = HEAD:gsub("  </library_materials>", LAMPS .. "  </library_materials>") .. NODE_AB ..
    '<material id="pigeon-material" name="pigeon">' .. TAIL
  local names = { [model.BODY_MATERIAL] = model.SKIN, ["pigeon_headlights-material"] = model.LAMP, ["pigeon_signal_L-material"] = model.LAMP,
    ["missing-material"] = "x" }
  local text, done = model.rename(src, names)
  assertEq(model.SKIN, "pigeon.skin.birdabduction")
  assertEq(model.LAMP, "pigeon_lights")
  assertEq(contains(text, '<material id="pigeon-material" name="pigeon.skin.birdabduction">'), true)
  assertEq(contains(text, '<material id="pigeon_headlights-material" name="pigeon_lights">'), true)
  assertEq(contains(text, '<material id="pigeon_signal_L-material" name="pigeon_lights">'), true)
  assertEq(contains(text, '<material id="glass-material" name="pigeon">'), true)
  assertEq(contains(text, 'target="#pigeon-material"'), true)
  assertEq(contains(text, '<material id="pigeon-material" name="pigeon">' .. TAIL), true)
  assertEq(#text, #src + #".skin.birdabduction" + #"pigeon_lights" * 2 - #"pigeon_headlights" - #"pigeon_signal_L")
  assertEq(done[model.BODY_MATERIAL], true)
  assertEq(done["pigeon_headlights-material"], true)
  assertEq(done["missing-material"], nil)
  local bare = NODE_AB .. TAIL
  local same, none = model.rename(bare, names)
  assertEq(same, bare)
  assertEq(next(none), nil)
end)

test("every lamp material the van keeps is a glow-map name of the Pigeon", function()
  local ids = {}
  for _, id in ipairs(model.LAMP_MATERIALS) do ids[id] = true end
  assertEq(#model.LAMP_MATERIALS, 7)
  for _, n in ipairs({ "pigeon_headlights", "pigeon_foglights", "pigeon_signal_L", "pigeon_signal_R", "pigeon_taillight_L",
    "pigeon_taillight_R", "pigeon_reverselight" }) do
    assertEq(ids[n .. "-material"], true, n)
  end
end)

test("the pose points along the flight and holds the heading when slow", function()
  local p = model.newPose()
  step(p, 10, 0, 0)
  assertNear(p.yaw, 0, 1e-9)
  for _ = 1, 20 do step(p, 10, 0, 0.05) end
  local prev = p.yaw
  for i = 1, 40 do
    step(p, 0, 10, 0.05)
    assertEq(math.abs(wrap(p.yaw - prev)) < 0.16, true, i .. ": " .. prev .. " -> " .. p.yaw)
    prev = p.yaw
    if i == 20 then assertEq(p.yaw > 1.2 and p.yaw < math.pi / 2, true, tostring(p.yaw)) end
  end
  assertNear(p.yaw, math.pi / 2, 0.05)
  for _ = 1, 40 do step(p, 0.5, 0.5, 0.05) end
  assertNear(p.yaw, math.pi / 2, 0.05)
  assertNear(p.fx, 0, 0.05); assertNear(p.fy, 1, 0.05)
end)

test("a slow start takes the heading once it moves, without a swing", function()
  local p = model.newPose()
  step(p, 0, 0, 0)
  step(p, 0, -0.5, 0.05)
  step(p, 0, -3, 0.05)
  assertNear(p.yaw, -math.pi / 2, 1e-9)
end)

test("speeding up pitches the nose down, slowing pitches it up, capped and smoothed", function()
  local p = model.newPose()
  local v = 0
  step(p, v, 0, 0)
  v = v + 4 * 0.05
  step(p, v, 0, 0.05)
  assertEq(p.pitch > 0 and p.pitch < 4 * model.PITCH_PER_ACCEL / 3, true, tostring(p.pitch))
  for _ = 1, 100 do
    v = v + 4 * 0.05
    step(p, v, 0, 0.05)
  end
  assertNear(p.pitch, 4 * model.PITCH_PER_ACCEL, 0.01)
  assertEq(p.pitch > 0 and p.pitch <= model.PITCH_MAX, true)
  assertEq(p.fz < 0, true)
  assertNear(p.bank, 0, 1e-9)
  for _ = 1, 100 do
    v = v - 4 * 0.05
    step(p, v, 0, 0.05)
  end
  assertNear(p.pitch, -4 * model.PITCH_PER_ACCEL, 0.01)
  assertEq(p.fz > 0, true)
  for _ = 1, 100 do
    v = v + 30 * 0.05
    step(p, v, 0, 0.05)
  end
  assertEq(p.pitch, model.PITCH_MAX)
end)

test("a left turn banks the roof to the left, a right turn to the right, capped", function()
  for _, turn in ipairs({ 0.15, -0.15, 2, -2 }) do
    local p = model.newPose()
    local t = 0
    for _ = 1, 200 do
      step(p, 15 * math.cos(turn * t), 15 * math.sin(turn * t), 0.05)
      t = t + 0.05
    end
    local lx, ly = -math.sin(p.yaw), math.cos(p.yaw)
    local lean = p.ux * lx + p.uy * ly
    if turn > 0 then
      assertEq(p.bank > 0 and lean > 0, true, turn .. " " .. p.bank)
    else
      assertEq(p.bank < 0 and lean < 0, true, turn .. " " .. p.bank)
    end
    if math.abs(turn) < 1 then
      assertNear(math.abs(p.bank), 15 * 0.15 * model.BANK_PER_ACCEL, 0.3, tostring(turn))
    else
      assertEq(math.abs(p.bank), model.BANK_MAX, tostring(turn))
    end
    if math.abs(turn) < 1 then assertNear(p.pitch, 0, 0.2, tostring(turn)) end
    assertNear(p.fx * p.ux + p.fy * p.uy + p.fz * p.uz, 0, 1e-9)
    assertNear(p.lx * p.fx + p.ly * p.fy + p.lz * p.fz, 0, 1e-9)
    assertNear(p.lx * p.lx + p.ly * p.ly + p.lz * p.lz, 1, 1e-9)
  end
end)

test("a velocity that is not finite leaves the pose as it was", function()
  local p = model.newPose()
  for _ = 1, 20 do step(p, 10, 2, 0.05) end
  local before = {}
  for k, v in pairs(p) do before[k] = v end
  for _, bad in ipairs({ 0 / 0, math.huge, -math.huge }) do
    step(p, bad, 2, 0.05)
    step(p, 10, bad, 0.05)
    for k, v in pairs(before) do assertEq(p[k], v, k) end
  end
  for _ = 1, 20 do step(p, 10, 2, 0.05) end
  for _, k in ipairs({ "yaw", "pitch", "bank", "ax", "ay", "fx", "ux", "lx" }) do
    assertEq(p[k] == p[k], true, k)
  end
end)

test("a long frame is capped and a zero frame changes nothing", function()
  local p = model.newPose()
  step(p, 10, 0, 0.05)
  step(p, 10, 0, 0.05)
  local yaw, pitch = p.yaw, p.pitch
  step(p, 10, 0, 0)
  assertEq(p.yaw, yaw); assertEq(p.pitch, pitch)
  step(p, 0, 10, 5)
  assertEq(p.yaw < math.pi / 4, true, tostring(p.yaw))
end)

test("place keeps the port light on the left as the van turns", function()
  local port, starboard, tail = light(255, 40, 30), light(40, 255, 90), light(255, 245, 230)
  assertEq(port ~= nil and starboard ~= nil and tail ~= nil, true)
  local pos = { x = 100, y = -50, z = 120 }
  for _, deg in ipairs({ 0, 90, 200, -45 }) do
    local yaw = math.rad(deg)
    local p = model.newPose()
    for _ = 1, 3 do step(p, 20 * math.cos(yaw), 20 * math.sin(yaw), 0.05) end
    local hx, hy = math.cos(yaw), math.sin(yaw)
    local function side(l)
      local x, y = model.place(p, pos, l.x, l.y, l.z)
      return (x - pos.x) * -hy + (y - pos.y) * hx, (x - pos.x) * hx + (y - pos.y) * hy
    end
    local portLeft = side(port)
    local starLeft = side(starboard)
    local _, tailAhead = side(tail)
    assertEq(portLeft > 1, true, deg .. " port " .. portLeft)
    assertEq(starLeft < -1, true, deg .. " starboard " .. starLeft)
    assertEq(tailAhead < -3, true, deg .. " tail " .. tailAhead)
    local ax, ay, az = model.place(p, pos, 0, model.ANCHOR_Y, model.ANCHOR_Z)
    assertNear(ax, pos.x, 1e-9); assertNear(ay, pos.y, 1e-9); assertNear(az, pos.z, 1e-9)
    local ox, oy, oz = model.place(p, pos, 0, 0, 0)
    assertNear(ox - pos.x, model.SCALE * model.ANCHOR_Y * hx, 1e-6)
    assertNear(oy - pos.y, model.SCALE * model.ANCHOR_Y * hy, 1e-6)
    assertNear(oz - pos.z, -model.SCALE * model.ANCHOR_Z, 1e-6)
  end
end)

test("the van is three times the Pigeon and the lights sit outside its body", function()
  assertEq(model.SCALE, 3)
  local p = model.newPose()
  local pos = { x = 0, y = 0, z = 0 }
  local x1 = model.place(p, pos, 0, -1, model.ANCHOR_Z)
  local x2 = model.place(p, pos, 0, 1, model.ANCHOR_Z)
  assertNear(x1 - x2, 2 * model.SCALE, 1e-9)
  local BOX = { x = 0.63, y1 = 0.38, y2 = 1.74, z1 = 0.78, z2 = 1.51 }
  local MIRROR_X = 0.77
  local port, starboard, tail = light(255, 40, 30), light(40, 255, 90), light(255, 245, 230)
  assertEq(port.x > MIRROR_X, true, tostring(port.x))
  assertEq(starboard.x < -MIRROR_X, true, tostring(starboard.x))
  assertEq(port.y < BOX.y1 and starboard.y < BOX.y1, true)
  assertEq(tail.y > BOX.y2, true, tostring(tail.y))
  assertEq(math.abs(tail.x) < BOX.x and tail.z > BOX.z1 and tail.z < BOX.z2, true)
  local top, bottom
  for _, l in ipairs(model.LIGHTS) do
    if l.beacon then
      assertEq(l.r, 255); assertEq(l.g < 80, true); assertEq(l.b < 80, true)
      if l.z > 1 then top = l else bottom = l end
    end
  end
  assertEq(top.z > BOX.z2, true, tostring(top.z))
  assertEq(bottom.z < BOX.z1, true, tostring(bottom.z))
  for _, l in ipairs({ top, bottom }) do
    assertEq(math.abs(l.x) < BOX.x and l.y > BOX.y1 and l.y < BOX.y2, true)
  end
  assertEq(#model.LIGHTS, 5)
  assertEq(model.ANCHOR_Z < 0.24, true)
end)

test("the beacon flashes 0.15 s each second", function()
  assertEq(model.BEACON_PERIOD, 1)
  assertEq(model.BEACON_ON, 0.15)
  for _, c in ipairs({ 0, 0.1, 1.05, 7.14 }) do assertEq(model.beaconOn(c), true, tostring(c)) end
  for _, c in ipairs({ 0.2, 0.9, 1.5, 7.16 }) do assertEq(model.beaconOn(c), false, tostring(c)) end
end)
