local M = {}

M.WEATHER = {
  rain = { steady = 5, peak = 8, every = { 10, 25 }, length = { 2, 5 }, turn = 15 },
  storm = { steady = 17, peak = 26, every = { 5, 15 }, length = { 2, 6 }, turn = 30 },
  snow = { steady = 4, peak = 6, every = { 10, 25 }, length = { 2, 5 }, turn = 15 },
}

local MODULUS = 2147483647
local MULTIPLIER = 16807

local cache = {}

local function validSeed(seed)
  if type(seed) ~= "number" or seed ~= math.floor(seed) or seed < 1 or seed > MODULUS - 1 then return 1 end
  return seed
end

local function newSchedule(cfg, seed)
  return { cfg = cfg, state = seed, gusts = {}, horizon = 0 }
end

local function draw(schedule)
  schedule.state = schedule.state * MULTIPLIER % MODULUS
  return schedule.state / MODULUS
end

local function between(range, r)
  return range[1] + (range[2] - range[1]) * r
end

local function extend(schedule, t)
  local cfg = schedule.cfg
  while schedule.horizon <= t do
    local start = schedule.horizon + between(cfg.every, draw(schedule))
    local length = between(cfg.length, draw(schedule))
    local strength = cfg.steady + (cfg.peak - cfg.steady) * (0.5 + 0.5 * draw(schedule))
    local turn = between({ -cfg.turn, cfg.turn }, draw(schedule))
    schedule.gusts[#schedule.gusts + 1] = { start = start, length = length, strength = strength, turn = turn }
    schedule.horizon = start + length
  end
end

local function scheduleFor(weather, seed, cfg)
  local key = weather .. ":" .. seed
  local schedule = cache[key]
  if not schedule then
    schedule = newSchedule(cfg, seed)
    cache[key] = schedule
  end
  return schedule
end

function M.reset()
  cache = {}
end

function M.at(weather, seed, dirDeg, t)
  local cfg = M.WEATHER[weather]
  if not cfg then return 0, 0, 0 end
  t = t or 0
  local schedule = scheduleFor(weather, validSeed(seed), cfg)
  extend(schedule, t)
  local speed, turn = cfg.steady, 0
  for _, gust in ipairs(schedule.gusts) do
    if t >= gust.start and t < gust.start + gust.length then
      local s = math.sin(math.pi * (t - gust.start) / gust.length)
      speed = cfg.steady + (gust.strength - cfg.steady) * s
      turn = gust.turn * s
      break
    end
  end
  local rad = math.rad((dirDeg or 0) + turn)
  return speed * math.sin(rad), speed * math.cos(rad), 0
end

return M
