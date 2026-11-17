local M = {}

M.SOURCE = "/vehicles/pigeon/pigeon.dae"
M.MATERIAL_FILES = {
  "/vehicles/pigeon/main.materials.json",
  "/vehicles/pigeon/dynamicDecals/main.materials.json",
  "/vehicles/pigeon/skin.materials.json",
}
M.HIDE = {
  "pigeon_pickup_axle_R", "pigeon_pickup_axlemounts_R_4link", "pigeon_pickup_brakedrum_RL", "pigeon_pickup_brakedrum_RR",
  "pigeon_pickup_brakedrum_shield_R", "pigeon_pickup_coilover_R_4link", "pigeon_pickup_hub_R", "pigeon_pickup_lowerlink_R_4link",
  "pigeon_pickup_lowermounts_R_4link_upfit", "pigeon_pickup_trackbar_R_4link", "pigeon_pickup_trackbarmount_R_4link",
  "pigeon_pickup_upperlink_R_4link", "pigeon_pickup_uppermounts_R_4link", "pigeon_snorkel_t_engine", "pigeon_snorkel_t_engine_i4",
  "pigeon_snorkel_t", "pigeon_bed_t_fenderflare_R", "pigeon_bed_t_fenderflare_L", "pigeon_bumper_t_R", "pigeon_bed_t_chain_plate",
  "pigeon_bed_t_chain", "pigeon_bumper_t_F", "pigeon_bed_t", "pigeon_tailgate", "pigeon_case", "pigeon_bed", "pigeon_lettering_F_alt",
  "pigeon_windshield_dmg", "pigeon_airdam_F", "pigeon_bedcover", "pigeon_rollcage_bed", "pigeon_rollcage",
  "pigeon_bintop", "pigeon_binarm", "pigeon_bin", "pigeon_body_4w", "pigeon_flare_F_4w", "pigeon_stabilizer_L", "pigeon_stabwheel_R",
  "pigeon_stabwheel_L", "pigeon_stabilizer_R", "pigeon_steering_wheel_B", "pigeon_shifter_knob_3spd",
  "pigeon_jumpseats", "pigeon_flare_R", "pigeon_bumper_R", "pigeon_taillight_L", "pigeon_taillight_R",
  "pigeon_seat_FL", "pigeon_seat_FR", "pigeon_dash", "pigeon_gauges", "pigeon_needle_fuel", "pigeon_needle_temp",
  "pigeon_needle_speedo", "pigeon_pedal_brake", "pigeon_pedal_gas", "pigeon_pedal_clutch", "pigeon_steering_wheel",
  "pigeon_steeringcolumn", "pigeon_sunvisor_L", "pigeon_sunvisor_R", "pigeon_intermirror", "pigeon_doorglass_L_int",
  "pigeon_doorglass_R_int", "pigeon_windshield_int", "pigeon_backlight_int", "pigeon_shifter_knob_5spd", "pigeon_shifter_boot",
  "pigeon_pbrake", "pigeon_signalstalk", "pigeon_interiormisc",
}
M.BODY_MATERIAL = "pigeon-material"
M.SKIN = "pigeon.skin.birdabduction"
M.LAMP = "pigeon_lights"
M.LAMP_MATERIALS = {
  "pigeon_headlights-material", "pigeon_foglights-material", "pigeon_signal_L-material", "pigeon_signal_R-material",
  "pigeon_taillight_L-material", "pigeon_taillight_R-material", "pigeon_reverselight-material",
}

M.SCALE = 3
M.ANCHOR_Y = 0.1
M.ANCHOR_Z = 0.1
M.HEADING_SPEED = 2
M.TURN_SECONDS = 0.5
M.TILT_SECONDS = 0.6
M.PITCH_PER_ACCEL = 1.25
M.PITCH_MAX = 10
M.BANK_PER_ACCEL = 3
M.BANK_MAX = 12
M.MAX_STEP = 0.1

M.LIGHTS = {
  { x = 0.8, y = -0.47, z = 0.95, r = 255, g = 40, b = 30 },
  { x = -0.8, y = -0.47, z = 0.95, r = 40, g = 255, b = 90 },
  { x = 0, y = 1.8, z = 1, r = 255, g = 245, b = 230 },
  { x = 0, y = 1, z = 1.6, r = 255, g = 30, b = 20, beacon = true },
  { x = 0, y = 1.05, z = 0.7, r = 255, g = 30, b = 20, beacon = true },
}
M.BEACON_PERIOD = 1
M.BEACON_ON = 0.15

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

function M.trim(src, names)
  local cuts, seen = {}, {}
  for _, name in ipairs(names) do
    if not seen[name] then
      seen[name] = true
      local s = src:find('<node id="' .. name .. '"', 1, true)
      local e = s and src:find("</node>", s, true)
      if e then cuts[#cuts + 1] = { s, e + 6 } end
    end
  end
  table.sort(cuts, function(a, b) return a[1] < b[1] end)
  local parts, at, removed = {}, 1, 0
  for _, c in ipairs(cuts) do
    if c[1] >= at then
      parts[#parts + 1] = src:sub(at, c[1] - 1)
      at = c[2] + 1
      removed = removed + 1
    end
  end
  parts[#parts + 1] = src:sub(at)
  return table.concat(parts), removed
end

function M.rename(text, names)
  local stop = text:find("</library_materials>", 1, true)
  local head = stop and text:sub(1, stop) or text
  local parts, done, at, from = {}, {}, 1, 1
  while true do
    local s, e, id = head:find('<material id="([^"]+)" name="', from)
    if not s then break end
    local close = head:find('"', e + 1, true)
    if not close then break end
    local name = names[id]
    if name and not done[id] then
      parts[#parts + 1] = text:sub(at, e)
      parts[#parts + 1] = name
      at = close
      done[id] = true
    end
    from = close + 1
  end
  if at == 1 then return text, done end
  parts[#parts + 1] = text:sub(at)
  return table.concat(parts), done
end

function M.newPose()
  return {
    yaw = nil, settled = false, pitch = 0, bank = 0, ax = 0, ay = 0, vx = nil, vy = nil,
    fx = 1, fy = 0, fz = 0, ux = 0, uy = 0, uz = 1, lx = 0, ly = 1, lz = 0,
  }
end

local function wrap(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

local function cap(v, limit)
  return math.max(-limit, math.min(limit, v))
end

local function frame(p, hx, hy)
  local pr, br = math.rad(p.pitch), math.rad(p.bank)
  local cp, sp, cb, sb = math.cos(pr), math.sin(pr), math.cos(br), math.sin(br)
  local fx, fy, fz = hx * cp, hy * cp, -sp
  local ux, uy, uz = hx * sp * cb - hy * sb, hy * sp * cb + hx * sb, cp * cb
  p.fx, p.fy, p.fz = fx, fy, fz
  p.ux, p.uy, p.uz = ux, uy, uz
  p.lx, p.ly, p.lz = uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
end

local function turn(p, vx, vy, speed, dt)
  if not p.settled then
    if speed > 0 then p.yaw = atan2(vy, vx) end
    p.yaw = p.yaw or 0
    p.settled = speed > M.HEADING_SPEED
  elseif speed > M.HEADING_SPEED and dt > 0 then
    local d = wrap(atan2(vy, vx) - p.yaw)
    p.yaw = wrap(p.yaw + d * (1 - math.exp(-dt / M.TURN_SECONDS)))
  end
end

function M.step(p, vel, dt)
  local vx, vy = vel.x, vel.y
  if vx - vx ~= 0 or vy - vy ~= 0 then return end
  dt = math.max(0, math.min(dt or 0, M.MAX_STEP))
  turn(p, vx, vy, math.sqrt(vx * vx + vy * vy), dt)
  if p.vx and dt > 0 then
    local k = 1 - math.exp(-dt / M.TILT_SECONDS)
    p.ax = p.ax + ((vx - p.vx) / dt - p.ax) * k
    p.ay = p.ay + ((vy - p.vy) / dt - p.ay) * k
  end
  if dt > 0 or not p.vx then p.vx, p.vy = vx, vy end
  local hx, hy = math.cos(p.yaw), math.sin(p.yaw)
  p.pitch = cap((p.ax * hx + p.ay * hy) * M.PITCH_PER_ACCEL, M.PITCH_MAX)
  p.bank = cap((p.ay * hx - p.ax * hy) * M.BANK_PER_ACCEL, M.BANK_MAX)
  frame(p, hx, hy)
end

function M.place(p, pos, mx, my, mz)
  local s = M.SCALE
  local a, b, c = mx * s, (M.ANCHOR_Y - my) * s, (mz - M.ANCHOR_Z) * s
  return pos.x + a * p.lx + b * p.fx + c * p.ux,
    pos.y + a * p.ly + b * p.fy + c * p.uy,
    pos.z + a * p.lz + b * p.fz + c * p.uz
end

function M.beaconOn(clock)
  return clock % M.BEACON_PERIOD < M.BEACON_ON
end

return M
