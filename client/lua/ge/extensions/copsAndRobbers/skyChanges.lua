local schedule = require("copsAndRobbers/strikeSchedule")
local M = {}

M.CHANGE_SECONDS = schedule.CHANGE_SECONDS
M.DRY_SECONDS = 180
M.WINDOW_SECONDS = 120
M.GROUNDED = { storm = true, thunderstorm = true, fog = true, snow = true }

local WET = { rain = true, storm = true, thunderstorm = true, snow = true }
local CLEARING_FROM = { rain = true, thunderstorm = true, snow = true, fog = true }
local WORDS = {
  clear = "clear skies", cloudy = "clouds", rain = "rain", storm = "a storm",
  thunderstorm = "a thunderstorm", fog = "fog", snow = "snow",
}
local KINDS = { "dry", "rain", "storm", "snow" }

local function changesOf(p)
  return p and p.changes or {}
end

M.at = schedule.weatherAt
M.smooth = schedule.smooth

function M.current(p, t)
  local _, to = M.at(p, t)
  return to
end

function M.notice(from, to)
  if to == "fog" then return "Weather: fog rolling in" end
  if to == "thunderstorm" then return "Weather: a thunderstorm is coming" end
  if from == "clear" and to == "cloudy" then return "Weather: clouds coming in" end
  if from == "cloudy" and to == "rain" then return "Weather: rain coming" end
  if from == "cloudy" and to == "snow" then return "Weather: snow coming" end
  if from == "rain" and to == "storm" then return "Weather: the rain is getting heavier" end
  if from == "storm" and to == "rain" then return "Weather: the storm is easing" end
  if from == "thunderstorm" and to == "rain" then return "Weather: the thunderstorm is easing" end
  if from == "rain" and to == "snow" then return "Weather: the rain is turning to snow" end
  if from == "snow" and to == "rain" then return "Weather: the snow is turning to rain" end
  return "Weather: clearing up"
end

local function wordFor(from, to)
  if (to == "clear" or to == "cloudy") and CLEARING_FROM[from] then return "clearing up" end
  return WORDS[to] or tostring(to)
end

local function span(from, at, suffix)
  local a = (from - at) / 60
  local b = a + M.WINDOW_SECONDS / 60
  local lo, hi = math.floor(a), math.max(1, math.ceil(b))
  if lo >= 1 then return string.format("%s%d-%d min%s", suffix == "" and "in " or "", lo, hi, suffix) end
  return string.format("within %d min%s", hi, suffix)
end

function M.forecast(p, t, heliOn)
  local list = changesOf(p)
  local from, ch
  for i, c in ipairs(list) do
    if c.at > t then
      ch = c
      from = i > 1 and list[i - 1].to or p.weather
      break
    end
  end
  if not ch or (ch.afterStay and t < ch.forecastFrom) then return nil end
  local word = wordFor(from, ch.to)
  local text
  if t >= ch.forecastFrom then
    text = "Forecast: " .. word .. " any minute"
  else
    text = "Forecast: " .. word .. " " .. span(ch.forecastFrom, t, "")
  end
  local heli
  if heliOn then
    if M.GROUNDED[ch.to] then
      heli = "(helicopter grounded)"
    elseif M.GROUNDED[from] then
      heli = "(helicopter returns)"
    end
  end
  return { text = text, heli = heli }
end

function M.prepForecast(p)
  local ch = changesOf(p)[1]
  if not ch or ch.afterStay then return nil end
  return "Forecast: " .. wordFor(p.weather, ch.to) .. " " .. span(ch.forecastFrom, p.releaseAt or 0, " after release")
end

local function kindOf(w)
  if w == "thunderstorm" then return "storm" end
  if WET[w] then return w end
  return "dry"
end

local function weightsAt(seg, t)
  local k = seg.dur > 0 and math.min(1, math.max(0, (t - seg.start) / seg.dur)) or 1
  local out = {}
  for _, name in ipairs(KINDS) do
    local target = name == seg.target and 1 or 0
    out[name] = seg.from[name] + (target - seg.from[name]) * k
  end
  return out
end

function M.grip(p, t)
  if not p or not p.driving then return nil end
  local list = changesOf(p)
  local start = {}
  for _, name in ipairs(KINDS) do start[name] = name == kindOf(p.weather) and 1 or 0 end
  local seg = { start = 0, dur = 0, from = start, target = kindOf(p.weather) }
  local prev = p.weather
  for _, ch in ipairs(list) do
    local fk, tk = kindOf(prev), kindOf(ch.to)
    local s, dur, target
    if WET[ch.to] then
      s, dur, target = ch.at, M.CHANGE_SECONDS, tk
    elseif fk ~= "dry" and tk == "dry" then
      s, dur, target = ch.at + M.CHANGE_SECONDS, M.DRY_SECONDS, "dry"
    end
    if s then
      if s > t then break end
      seg = { start = s, dur = dur, from = weightsAt(seg, s), target = target }
    end
    prev = ch.to
  end
  return weightsAt(seg, t)
end

local function wrapHalf(x)
  return x - math.floor(x + 0.5)
end

local function tod(hour)
  if hour == 6 then return 0.75 end
  return 2 / 24
end

function M.curve(p, clockStart, t)
  local temps = p and p.temps
  if not temps or #temps < 2 then return nil end
  local u = wrapHalf((clockStart or 0) - (p.gameStart or 0))
  if p.daySeconds then u = u + t / p.daySeconds end
  local index = 1
  for j = 1, #temps do
    if temps[j].t <= u then index = j end
  end
  index = math.max(1, math.min(#temps - 1, index))
  local a, b = temps[index], temps[index + 1]
  local pa = { tod(a.hour), a.c }
  local pb = { tod(b.hour), b.c }
  if pb[1] < pa[1] then pa, pb = pb, pa end
  return { pa, pb }, index
end

return M
