local schedule = require("copsAndRobbers/strikeSchedule")
local clips = require("copsAndRobbers/thunderClips")
local M = {new = schedule.new, between = schedule.between, weight = schedule.weight}

local function channel(top, foot, levels, roughness, draw)
  local line = {top, foot}
  for _ = 1, levels do
    local finer = {}
    for i = 2, #line do
      local a, b = line[i - 1], line[i]
      local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
      local spread = roughness * math.sqrt(dx * dx + dy * dy + dz * dz)
      finer[#finer + 1] = a
      finer[#finer + 1] = {
        x = (a.x + b.x) / 2 + (2 * draw() - 1) * spread,
        y = (a.y + b.y) / 2 + (2 * draw() - 1) * spread,
        z = (a.z + b.z) / 2,
      }
    end
    finer[#finer + 1] = foot
    line = finer
  end
  return line
end

function M.bolt(shapeSeed)
  local draw = schedule.generator(shapeSeed)
  local main = channel({x = 0, y = 0, z = 900}, {x = 0, y = 0, z = 0}, 6, 0.35, draw)
  local branches = {}
  local count = 1 + math.floor(3 * draw())
  for i = 1, count do
    local root = main[2 + math.floor(44 * draw())]
    local length = 150 + 200 * draw()
    local drop = length * (0.35 + 0.4 * draw())
    local reach = math.sqrt(length * length - drop * drop)
    local angle = 2 * math.pi * draw()
    local dx, dy = reach * math.cos(angle), reach * math.sin(angle)
    if dx * root.x + dy * root.y < 0 then dx, dy = -dx, -dy end
    local tip = {x = root.x + dx, y = root.y + dy, z = root.z - drop}
    branches[i] = channel(root, tip, 4, 0.4, draw)
  end
  return {main = main, branches = branches}
end

function M.sound(soundRoll, d)
  local group = clips.far
  if d < 1000 then group = clips.close elseif d <= 3000 then group = clips.medium end
  local fade = math.min(1, math.max(0, (d - 500) / 5500))
  return group[1 + math.floor(soundRoll * #group)], d / 343, 1 - 0.65 * fade
end

function M.strength(d)
  return 1e10 * (300 / math.max(300, d)) ^ 2
end

return M
