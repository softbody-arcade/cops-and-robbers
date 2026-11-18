local M = {CHANGE_SECONDS = 60}

local MODULUS = 2147483647
local WINDOW = 60

local function nextSeed(seed)
  return seed * 16807 % MODULUS
end

function M.generator(parentSeed)
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

local function validInterval(seconds)
  return type(seconds) == "number" and seconds >= 1 and seconds < math.huge and seconds == math.floor(seconds)
end

local function candidate(cursor, previousAt, seed)
  local waitSeed = nextSeed(seed)
  local keepSeed = nextSeed(waitSeed)
  return {
    at = previousAt + (cursor.minimum + cursor.span * (waitSeed / MODULUS)),
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
  if not pending or start < cursor.start then pending = candidate(cursor, 0, cursor.seed) end
  local events = {}
  while pending.at < start + WINDOW do
    if pending.at >= start then events[#events + 1] = pending end
    pending = candidate(cursor, pending.at, pending.detailSeed)
  end
  cursor.start, cursor.events, cursor.pending = start, events, pending
end

function M.weatherAt(p, t)
  local list = p.changes or {}
  local n = 0
  for i, ch in ipairs(list) do
    if ch.at <= t then n = i else break end
  end
  if n == 0 then return p.weather, p.weather, 1, 0 end
  local from = n > 1 and list[n - 1].to or p.weather
  return from, list[n].to, math.min(1, (t - list[n].at) / M.CHANGE_SECONDS), n
end

function M.smooth(x)
  return x * x * (3 - 2 * x)
end

function M.weight(p, t)
  if not p or t < 0 then return 0 end
  local from, to, progress = M.weatherAt(p, t)
  local start = from == "thunderstorm" and 1 or 0
  local finish = to == "thunderstorm" and 1 or 0
  return start + (finish - start) * M.smooth(progress)
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
  local draw = M.generator(event.detailSeed)
  local band = draw()
  local near, far = 3000, 6000
  if band < 0.10 then near, far = 300, 1000
  elseif band < 0.45 then near, far = 1000, 3000 end
  local range = near + (far - near) * draw()
  local bearing = 360 * draw()
  local soundRoll = draw()
  local _, shapeSeed = draw()
  return {
    at = event.at, id = event.detailSeed, range = range, bearing = bearing,
    soundRoll = soundRoll, shapeSeed = shapeSeed, pulses = pulses(draw),
  }
end

function M.between(cursor, p, lo, hi)
  local events = {}
  if not cursor or not p or cursor.seed ~= p.lightningSeed or hi <= lo or hi <= 0 then return events end
  if not cursor.minimum then
    local minimum, maximum = p.lightningMinSeconds, p.lightningMaxSeconds
    if not validInterval(minimum) or not validInterval(maximum) or maximum < minimum then
      minimum, maximum = 10, 40
    end
    cursor.minimum, cursor.span = minimum, maximum - minimum
  end
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

return M
