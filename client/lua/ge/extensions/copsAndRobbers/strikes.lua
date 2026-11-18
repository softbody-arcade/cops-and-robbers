local skyChanges = require("copsAndRobbers/skyChanges")
local clips = require("copsAndRobbers/thunderClips")
local M = {}

local MODULUS = 2147483647
local WINDOW = 60

local function nextSeed(seed)
  return seed * 16807 % MODULUS
end

local function forkGenerator(parentSeed)
  local reversed = 0
  for _ = 1, 31 do
    reversed = 2 * reversed + parentSeed % 2
    parentSeed = math.floor(parentSeed / 2)
  end
  local seed = MODULUS - reversed
  return function()
    seed = nextSeed(seed)
    return seed / MODULUS, seed
  end
end

local function candidate(previousAt, seed)
  local waitSeed = nextSeed(seed)
  local keepSeed = nextSeed(waitSeed)
  return {
    at = previousAt - 25 * math.log(1 - waitSeed / MODULUS),
    keep = keepSeed / MODULUS,
    detailSeed = nextSeed(keepSeed),
  }
end

function M.new(seed)
  if type(seed) ~= "number" or seed < 1 or seed >= MODULUS or seed ~= math.floor(seed) then return nil end
  return { seed = seed }
end

local function loadWindow(cursor, start)
  if cursor.start == start then return end
  local pending = cursor.pending
  if not pending or start < cursor.start then pending = candidate(0, cursor.seed) end
  local events = {}
  while pending.at < start + WINDOW do
    if pending.at >= start then events[#events + 1] = pending end
    pending = candidate(pending.at, pending.detailSeed)
  end
  cursor.start, cursor.events, cursor.pending = start, events, pending
end

function M.weight(p, t)
  if not p or t < 0 then return 0 end
  local from, to, progress = skyChanges.at(p, t)
  local start = from == "thunderstorm" and 1 or 0
  local finish = to == "thunderstorm" and 1 or 0
  return start + (finish - start) * skyChanges.smooth(progress)
end

local function pulses(draw)
  local count = 2 + math.floor(3 * draw())
  local result = {{ start = 0, length = 0.05 + 0.02 * draw(), level = 1 }}
  for i = 2, count do
    local previous = result[i - 1]
    result[i] = {
      start = previous.start + previous.length + 0.04 + 0.03 * draw(),
      length = 0.04 + 0.03 * draw(),
      level = 0.5 + 0.5 * draw(),
    }
  end
  return result
end

local function strike(event)
  local draw = forkGenerator(event.detailSeed)
  local band = draw()
  local near, far = 3000, 6000
  if band < 0.10 then near, far = 300, 1000
  elseif band < 0.45 then near, far = 1000, 3000 end
  local range = near + (far - near) * draw()
  local bearing = 360 * draw()
  local soundRoll = draw()
  local _, shapeSeed = draw()
  return {
    at = event.at, range = range, bearing = bearing,
    soundRoll = soundRoll, shapeSeed = shapeSeed, pulses = pulses(draw),
  }
end

function M.between(cursor, p, lo, hi)
  local events = {}
  if not cursor or not p or cursor.seed ~= p.lightningSeed or hi <= lo or hi <= 0 then return events end
  local first = math.floor(math.max(lo, 0) / WINDOW) * WINDOW
  local last = math.floor(hi / WINDOW) * WINDOW
  for start = first, last, WINDOW do
    loadWindow(cursor, start)
    for _, event in ipairs(cursor.events) do
      if event.at > lo and event.at <= hi and event.keep < M.weight(p, event.at) then
        events[#events + 1] = strike(event)
      end
    end
  end
  return events
end

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
  local draw = forkGenerator(shapeSeed)
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
