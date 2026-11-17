local sc = require("copsAndRobbers/skyChanges")

local function payload(changes, extra)
  local p = { weather = "clear", changes = changes, releaseAt = 10, driving = true }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

test("at", function()
  local p = payload({ { at = 100, to = "cloudy", forecastFrom = 0 }, { at = 400, to = "rain", forecastFrom = 280 } })
  local from, to, progress, index = sc.at(p, 50)
  assertEq(from, "clear"); assertEq(to, "clear"); assertEq(progress, 1); assertEq(index, 0)
  from, to, progress, index = sc.at(p, 130)
  assertEq(from, "clear"); assertEq(to, "cloudy"); assertNear(progress, 0.5, 1e-9); assertEq(index, 1)
  from, to, progress, index = sc.at(p, 200)
  assertEq(to, "cloudy"); assertEq(progress, 1); assertEq(index, 1)
  from, to, progress, index = sc.at(p, 430)
  assertEq(from, "cloudy"); assertEq(to, "rain"); assertNear(progress, 0.5, 1e-9); assertEq(index, 2)
  assertEq(sc.current(p, 430), "rain")
  assertEq(sc.current(payload({}), 99), "clear")
  assertEq(sc.at(payload(nil), 5), "clear")
  assertEq(sc.smooth(0), 0); assertEq(sc.smooth(1), 1); assertEq(sc.smooth(0.5), 0.5)
end)

test("the notices", function()
  local cases = {
    { "clear", "cloudy", "Weather: clouds coming in" },
    { "clear", "fog", "Weather: fog rolling in" },
    { "cloudy", "fog", "Weather: fog rolling in" },
    { "cloudy", "clear", "Weather: clearing up" },
    { "cloudy", "rain", "Weather: rain coming" },
    { "cloudy", "snow", "Weather: snow coming" },
    { "rain", "cloudy", "Weather: clearing up" },
    { "rain", "storm", "Weather: the rain is getting heavier" },
    { "rain", "snow", "Weather: the rain is turning to snow" },
    { "storm", "rain", "Weather: the storm is easing" },
    { "snow", "cloudy", "Weather: clearing up" },
    { "snow", "rain", "Weather: the snow is turning to rain" },
    { "fog", "cloudy", "Weather: clearing up" },
    { "fog", "clear", "Weather: clearing up" },
  }
  for _, c in ipairs(cases) do assertEq(sc.notice(c[1], c[2]), c[3], c[1] .. ">" .. c[2]) end
end)

test("the forecast before, inside and after its window", function()
  local p = payload({ { at = 400, to = "rain", forecastFrom = 300 } })
  p.weather = "cloudy"
  assertEq(sc.forecast(p, 120).text, "Forecast: rain in 3-5 min")
  assertEq(sc.forecast(p, 150).text, "Forecast: rain in 2-5 min")
  assertEq(sc.forecast(p, 280).text, "Forecast: rain within 3 min")
  assertEq(sc.forecast(p, 310).text, "Forecast: rain any minute")
  assertEq(sc.forecast(p, 410), nil)
end)

test("the forecast words", function()
  local function word(from, to)
    local p = payload({ { at = 400, to = to, forecastFrom = 300 } }, { weather = from })
    return sc.forecast(p, 310).text
  end
  assertEq(word("clear", "cloudy"), "Forecast: clouds any minute")
  assertEq(word("cloudy", "clear"), "Forecast: clear skies any minute")
  assertEq(word("rain", "storm"), "Forecast: a storm any minute")
  assertEq(word("cloudy", "fog"), "Forecast: fog any minute")
  assertEq(word("cloudy", "snow"), "Forecast: snow any minute")
  assertEq(word("rain", "cloudy"), "Forecast: clearing up any minute")
  assertEq(word("fog", "clear"), "Forecast: clearing up any minute")
  assertEq(word("snow", "cloudy"), "Forecast: clearing up any minute")
end)

test("the shown minutes always cover the window", function()
  local from = 437
  local p = payload({ { at = 500, to = "rain", forecastFrom = from } })
  p.weather = "cloudy"
  for t = 0, 499 do
    local text = sc.forecast(p, t).text
    if t >= from then
      assertEq(text, "Forecast: rain any minute")
    else
      local lo, hi = text:match("in (%d+)-(%d+) min")
      if not lo then
        lo, hi = 0, text:match("within (%d+) min")
      end
      assertEq(tonumber(lo) * 60 <= from - t, true, "lo at " .. t)
      assertEq(tonumber(hi) * 60 >= from + 120 - t, true, "hi at " .. t)
    end
  end
end)

test("the helicopter line only when it is on and the change grounds it or brings it back", function()
  local function line(from, to, on)
    local p = payload({ { at = 400, to = to, forecastFrom = 300 } }, { weather = from })
    return sc.forecast(p, 100, on).heli
  end
  assertEq(line("rain", "storm", true), "(helicopter grounded)")
  assertEq(line("cloudy", "fog", true), "(helicopter grounded)")
  assertEq(line("cloudy", "snow", true), "(helicopter grounded)")
  assertEq(line("fog", "clear", true), "(helicopter returns)")
  assertEq(line("storm", "rain", true), "(helicopter returns)")
  assertEq(line("clear", "cloudy", true), nil)
  assertEq(line("rain", "storm", false), nil)
  assertEq(line("fog", "clear", false), nil)
end)

test("the prep text for the first change", function()
  local p = payload({ { at = 500, to = "rain", forecastFrom = 310 } }, { weather = "cloudy" })
  assertEq(sc.prepForecast(p), "Forecast: rain 5-7 min after release")
  p.changes[1].forecastFrom = 0
  assertEq(sc.prepForecast(p), "Forecast: rain within 2 min after release")
end)

test("nothing without changes", function()
  assertEq(sc.forecast(payload({}), 5), nil)
  assertEq(sc.forecast(payload(nil), 5), nil)
  assertEq(sc.prepForecast(payload({})), nil)
  assertEq(sc.prepForecast(payload(nil)), nil)
end)

test("grip", function()
  local p = payload({ { at = 20, to = "rain", forecastFrom = 0 }, { at = 200, to = "cloudy", forecastFrom = 100 } }, { weather = "cloudy" })
  local g = sc.grip(p, 10)
  assertEq(g.dry, 1); assertEq(g.rain, 0)
  g = sc.grip(p, 50)
  assertNear(g.rain, 0.5, 1e-9); assertNear(g.dry, 0.5, 1e-9)
  g = sc.grip(p, 80)
  assertNear(g.rain, 1, 1e-9)
  assertNear(sc.grip(p, 260).rain, 1, 1e-9)
  assertNear(sc.grip(p, 350).rain, 0.5, 1e-9)
  assertNear(sc.grip(p, 440).rain, 0, 1e-9)
  assertNear(sc.grip(p, 440).dry, 1, 1e-9)

  local s = payload({ { at = 20, to = "storm", forecastFrom = 0 } }, { weather = "rain" })
  g = sc.grip(s, 50)
  assertNear(g.rain, 0.5, 1e-9); assertNear(g.storm, 0.5, 1e-9)
  local sum = 0
  for _, v in pairs(g) do sum = sum + v end
  assertNear(sum, 1, 1e-9)

  local q = payload({ { at = 200, to = "cloudy", forecastFrom = 100 }, { at = 300, to = "rain", forecastFrom = 200 } }, { weather = "rain" })
  g = sc.grip(q, 350)
  assertEq(sc.grip(q, 300).rain > 0.5, true)
  assertNear(sc.grip(q, 300).rain, 1 - 40 / 180, 1e-9)
  assertNear(g.rain, (1 - 40 / 180) + (1 - (1 - 40 / 180)) * (50 / 60), 1e-9)

  local dry = payload({ { at = 20, to = "rain", forecastFrom = 0 } })
  dry.driving = nil
  assertEq(sc.grip(dry, 50), nil)
end)

test("the curve", function()
  local gs = 0.95833
  local p = {
    gameStart = gs, daySeconds = 1800,
    temps = {
      { t = -0.20833, hour = 6, c = 8 },
      { t = 0.125, hour = 14, c = 18 },
      { t = 0.79167, hour = 6, c = 9 },
      { t = 1.125, hour = 14, c = 20 },
    },
  }
  local c1, i = sc.curve(p, gs, 0)
  assertEq(i, 1)
  assertEq(c1[1][1], 2 / 24); assertEq(c1[1][2], 18)
  assertEq(c1[2][1], 0.75); assertEq(c1[2][2], 8)
  assertEq(select(2, sc.curve(p, gs, 224)), 1)
  local c2
  c2, i = sc.curve(p, gs, 225)
  assertEq(i, 2)
  assertEq(c2[1][1], 2 / 24); assertEq(c2[1][2], c1[1][2])
  assertEq(c2[2][1], 0.75); assertEq(c2[2][2], 9)
  assertEq(select(2, sc.curve(p, gs + 0.02, 188)), 1)
  local c3
  c3, i = sc.curve(p, gs + 0.02, 189)
  assertEq(i, 2)
  assertEq(c3[1][2], c1[1][2])
  local c4
  c4, i = sc.curve(p, gs, 1e6)
  assertEq(i, 3)
  assertEq(c4[2][2], c2[2][2])
  assertEq(c4[1][2], 20)
  assertEq(sc.curve({ gameStart = gs }, gs, 0), nil)
  assertEq(select(2, sc.curve({ gameStart = gs, temps = p.temps }, gs, 1e6)), 1)
end)

test("the minute range at its boundary", function()
  local p = payload({ { at = 500, to = "rain", forecastFrom = 300 } }, { weather = "cloudy" })
  assertEq(sc.forecast(p, 240).text, "Forecast: rain in 1-3 min")
  assertEq(sc.forecast(p, 210).text, "Forecast: rain in 1-4 min")
  assertEq(sc.forecast(p, 241).text, "Forecast: rain within 3 min")
end)

test("the prep text never says within 0 min", function()
  local p = payload({ { at = 500, to = "rain", forecastFrom = 0 } }, { weather = "cloudy", releaseAt = 300 })
  assertEq(sc.prepForecast(p), "Forecast: rain within 1 min after release")
end)
