local climate = require("cnr.climate")
local GROUNDS = require("cnr.groundingWeather")

local M = {}

M.DAY_SECONDS = { fast = 900, moderate = 1800, slow = 7200, realtime = 86400 }
M.KEY_TIME = { sunrise = 0.775, morning = 0.825, noon = 0, afternoon = 0.175, sunset = 0.245, night = 0.5 }
M.START_LEAD = 1 / 24
M.LEAD_SECONDS = 75
M.HORIZON_SECONDS = 10800
M.CHANGE_SECONDS = 60
M.WINDOW_SECONDS = 120
M.BAD = { "rain", "storm", "fog", "snow", "thunderstorm" }

local HIGH_AT = 2 / 24
local LOW_AT = 0.75
local LIFT_AT = 0.875
local DUSK_AT = 0.25

local BAD = {}
for _, kind in ipairs(M.BAD) do BAD[kind] = true end
local NEXT = {
  clear = { { "cloudy" }, { "fog", "foggy" } },
  cloudy = { { "clear" }, { "rain", "wet" }, { "snow", "cold" }, { "fog", "foggy" }, { "thunderstorm", "hot", 0.5 } },
  rain = { { "cloudy" }, { "storm", "warm" }, { "snow", "cold" }, { "thunderstorm", "hot" } },
  storm = { { "rain" } },
  snow = { { "cloudy" }, { "rain", "wet" } },
  fog = { { "cloudy" }, { "clear" } },
  thunderstorm = { { "rain" }, { "cloudy" } },
}
local CROSS = { snow = "rain", rain = "snow", storm = "rain", thunderstorm = "rain" }
local CAN_STOP = { snow = true, rain = true, storm = true, fog = true, thunderstorm = true }
local LIFT = { "cloudy", "clear" }

function M.seeded(seed)
  local n = tonumber(seed) or 1
  if n ~= n or n == math.huge or n == -math.huge then n = 1 end
  n = math.floor(n)
  if n < 1 or n > 2147483646 then n = n % 2147483646 + 1 end
  local x = n
  return function()
    x = x * 16807 % 2147483647
    return x / 2147483647
  end
end

function M.releaseAt(cfg)
  return cfg.runnerCountdownSeconds + cfg.headStartSeconds
end

function M.endAt(cfg)
  local limit = cfg.roundTimeLimitSeconds
  return M.releaseAt(cfg) + math.min((limit and limit > 0) and limit or M.HORIZON_SECONDS, M.HORIZON_SECONDS)
end

function M.gameStart(s, cfg)
  local key = M.KEY_TIME[s.time]
  if not key then return nil end
  local ds = M.DAY_SECONDS[cfg.dayLength]
  local lead = 0
  if ds then lead = math.min(M.START_LEAD, M.LEAD_SECONDS / ds) end
  return (key - lead) % 1
end

local function lastAtOrBefore(at, start)
  local a = (at - start) % 1
  if a > 1e-12 then a = a - 1 end
  return a
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

function M.climate(s, cfg, random)
  if not s or not s.time or not s.weather or not climate.normal(s.month) then return nil end
  local start = M.gameStart(s, cfg)
  if not start then return nil end
  local ds = M.DAY_SECONDS[cfg.dayLength]
  local c = { gameStart = start, daySeconds = ds, month = s.month, start = s.weather, points = {} }
  local points = c.points

  local tHigh = lastAtOrBefore(HIGH_AT, start)
  local tLow = lastAtOrBefore(LOW_AT, start)
  local hour, t = 14, tHigh
  if tLow > tHigh then hour, t = 6, tLow end
  local limit = ds and (M.endAt(cfg) / ds + 0.25) or nil
  local n = 0
  while true do
    n = n + 1
    local day = 0
    if n > 2 then day = points[n - 1].day + (hour == 6 and 1 or 0) end
    points[n] = { t = t, hour = hour, day = day }
    if n >= 2 and (not limit or t >= limit) then break end
    if hour == 6 then
      hour, t = 14, t + 1 / 3
    else
      hour, t = 6, t + 2 / 3
    end
  end

  local shifts = {}
  shifts[0] = -4 + 8 * random()
  if s.weather == "snow" then shifts[0] = math.min(shifts[0], 0) end
  for d = 1, points[n].day do
    shifts[d] = clamp(shifts[d - 1] - 3 + 6 * random(), -6, 6)
  end
  c.shifts = shifts

  local low, high = climate.range(s.weather, s.month)
  if not low then return nil end
  for j = 1, 2 do
    local p = points[j]
    p.c = (p.hour == 6 and low or high) + shifts[0]
  end
  return c
end

function M.fill(c, j, before)
  local p = c.points[j]
  local nLow, nHigh = climate.normal(c.month)
  local oLow, oHigh = climate.offset(before)
  local shift = c.shifts[p.day]
  if p.hour == 6 then return nLow + oLow + shift end
  return math.max(nHigh + oHigh + shift, c.points[j - 1].c + 2)
end

local function lerp(a, b, u)
  if not b then return a and a.c or nil end
  if not a then return b.c end
  return a.c + (b.c - a.c) * (u - a.t) / (b.t - a.t)
end

function M.temperature(points, daySeconds, seconds)
  local u = daySeconds and (seconds / daySeconds) or 0
  local prev
  for _, p in ipairs(points) do
    if p.c ~= nil then
      if u <= p.t then return lerp(prev, p, u) end
      prev = p
    end
  end
  return lerp(prev, nil, u)
end

local function fits(w, T, tod)
  if w == "snow" then return T < 2 end
  if w == "rain" or w == "storm" or w == "thunderstorm" then return T > 1 end
  if w == "fog" then return T <= 12 and tod >= DUSK_AT and tod < LIFT_AT end
  return true
end

local function stops(w, u, v, Tu, Tv, lift)
  local x
  if w == "snow" and Tv >= 2 then
    x = u + (v - u) * (2 - Tu) / (Tv - Tu)
  elseif (w == "rain" or w == "storm" or w == "thunderstorm") and Tv <= 1 then
    x = u + (v - u) * (Tu - 1) / (Tu - Tv)
  elseif w == "fog" then
    if Tv > 12 then x = u + (v - u) * (12 - Tu) / (Tv - Tu) end
    if lift and lift <= v and (not x or lift < x) then x = lift end
  end
  return x
end

local function pickUniform(random, list)
  return list[math.min(#list, math.floor(random() * #list) + 1)]
end

local function pick(random, list, badPercent)
  local calm, bad = {}, {}
  for _, option in ipairs(list) do
    local group = BAD[option[1]] and bad or calm
    group[#group + 1] = option
  end

  local group = calm
  if #calm == 0 or (#bad > 0 and random() * 100 < badPercent) then group = bad end

  local total = 0
  for _, option in ipairs(group) do total = total + (option[3] or 1) end
  local roll = random() * total
  local cumulative = 0
  for _, option in ipairs(group) do
    cumulative = cumulative + (option[3] or 1)
    if roll < cumulative then return option[1] end
  end
  return group[#group][1]
end

local function options(from, T, foggy, warm, hot)
  local ok = { wet = T >= 2, cold = T <= 1, foggy = foggy, warm = warm, hot = hot }
  local list = { { from } }
  for _, o in ipairs(NEXT[from]) do
    if not o[2] or ok[o[2]] then list[#list + 1] = o end
  end
  return list
end

local function schedule(c, cfg, random, releaseAt, endAt)
  local points, ds = c.points, c.daySeconds
  local lo, hi = cfg.weatherChangeMinMinutes, cfg.weatherChangeMaxMinutes
  local changes = {}
  local cur, running, fitted, slot = c.start, nil, false, nil
  local lastStayAt
  local nextFill = 3

  local function day(x) return ds and x / ds or 0 end
  local function tempAt(x) return lerp(points[nextFill - 2], points[nextFill - 1], day(x)) end
  local function todAt(x) return (c.gameStart + day(x)) % 1 end
  local function interval() return 60 * (lo + (hi - lo) * random()) end

  local function reach(x)
    while points[nextFill] and points[nextFill - 1].t * ds <= x do
      points[nextFill].c = M.fill(c, nextFill, cur)
      nextFill = nextFill + 1
    end
  end

  local function add(x, to, cross)
    local forecastFrom = x - M.WINDOW_SECONDS * random()
    local afterStay = lastStayAt and true
    if afterStay then
      forecastFrom = math.max(lastStayAt, forecastFrom)
      lastStayAt = nil
    end
    changes[#changes + 1] = { at = x, to = to, forecastFrom = forecastFrom, cross = cross, afterStay = afterStay }
    slot = x + interval()
    cur, running, fitted = to, x + M.CHANGE_SECONDS, false
  end

  local function crossAt(x)
    add(x, CROSS[cur] or pickUniform(random, LIFT), true)
    if nextFill > 3 and points[nextFill - 2].t * ds >= x - 1e-9 then
      points[nextFill - 1].c = M.fill(c, nextFill - 1, cur)
    end
  end

  local function slotAt(x)
    local T = tempAt(x)
    local high = math.max(points[nextFill - 2].c, points[nextFill - 1].c)
    local warm, hot = high >= 15, high >= 20
    local to = pick(random, options(cur, T, fits("fog", T, todAt(x)), warm, hot), cfg.badWeatherChancePercent)
    if to == cur then
      lastStayAt = x
      slot = x + interval()
    else
      add(x, to)
    end
  end

  local function fitsAt(x)
    return not CAN_STOP[cur] or fits(cur, tempAt(x), todAt(x))
  end

  local function settle(x)
    if running and x >= running then running, fitted = nil, true end
    if not running and fitted and not fitsAt(x) then crossAt(x) end
    if not running and x >= slot then slotAt(x) end
    reach(x)
    if not running and not fitted and fitsAt(x) then fitted = true end
  end

  local function crossing(u, v)
    local lift = cur == "fog" and u + (LIFT_AT - todAt(u)) * ds or nil
    return stops(cur, u, v, tempAt(u), tempAt(v), lift)
  end

  reach(releaseAt)
  fitted = fitsAt(releaseAt)
  slot = releaseAt + interval()
  local u = releaseAt
  while u < endAt do
    local scan = ds and not running and CAN_STOP[cur]
    local v = math.min(endAt, slot, running or math.huge)
    if ds then v = math.min(v, points[nextFill - 1].t * ds) end
    if scan then
      if fitted then
        local boundary = crossing(u, v) or v
        local beforeBoundary = releaseAt + math.floor(boundary - releaseAt) - 1
        u = math.max(u, beforeBoundary)
      end
      local nextSecond = releaseAt + math.floor(u - releaseAt) + 1
      v = math.min(v, nextSecond)
    end
    local x
    if scan and fitted then x = crossing(u, v) end
    if x then
      if x >= endAt then break end
      u = x
      crossAt(u)
      reach(u)
    else
      u = v
      if u >= endAt then break end
      settle(u)
    end
  end
  return changes, cur
end

function M.build(s, cfg, random)
  local out = { changes = {}, gameStart = s and M.gameStart(s, cfg), releaseAt = M.releaseAt(cfg) }
  if not s then return out end
  random = random or M.seeded(s.weatherSeed)
  local c = M.climate(s, cfg, random)
  if not c then return out end
  local last = c.start
  if cfg.weatherChanges then out.changes, last = schedule(c, cfg, random, out.releaseAt, M.endAt(cfg)) end
  local temps = {}
  for j, p in ipairs(c.points) do
    if p.c == nil then p.c = M.fill(c, j, last) end
    temps[j] = { t = p.t, hour = p.hour, c = p.c }
  end
  out.temps = temps
  return out
end

local function started(s, t)
  local n = 0
  for i, ch in ipairs(s.changes or {}) do
    if ch.at > t then break end
    n = i
  end
  return n
end

function M.at(s, t)
  if not s then return nil end
  local n = started(s, t)
  if n == 0 then return s.weather end
  return s.changes[n].to
end

function M.groundedAt(s, t)
  if not s then return nil end
  local n = started(s, t)
  local now = M.at(s, t)
  if GROUNDS[now] then return now end
  if n > 0 and t < s.changes[n].at + M.CHANGE_SECONDS then
    local old = n > 1 and s.changes[n - 1].to or s.weather
    if GROUNDS[old] then return old end
  end
  return nil
end

return M
