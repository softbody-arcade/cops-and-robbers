local strikes = require("copsAndRobbers/strikes")
local clips = require("copsAndRobbers/thunderClips")

local function storm(seed, minimum, maximum)
  return {weather = "thunderstorm", lightningSeed = seed,
          lightningMinSeconds = minimum, lightningMaxSeconds = maximum}
end

local function signature(s)
  local fields = {}
  local function add(...)
    for i = 1, select("#", ...) do
      fields[#fields + 1] = string.format("%.17g", (select(i, ...)))
    end
  end
  add(s.at, s.range, s.bearing, s.soundRoll, s.shapeSeed, #s.pulses)
  for _, p in ipairs(s.pulses) do add(p.start, p.length, p.level) end
  local shape = strikes.bolt(s.shapeSeed)
  local function sample(line)
    for _, i in ipairs({1, math.floor(#line / 2), #line}) do
      local pt = line[i]
      add(pt.x, pt.y, pt.z)
    end
  end
  sample(shape.main)
  for _, line in ipairs(shape.branches) do sample(line) end
  return table.concat(fields, ",")
end

local function signatures(events, after)
  local values = {}
  for _, s in ipairs(events) do
    if not after or s.at > after then values[#values + 1] = signature(s) end
  end
  return table.concat(values, "\n")
end

test("frames, late joins, sky reapplication and backward seeks reconstruct the same strikes", function()
  local p = storm(31415, 3, 17)
  p.changes = {{at = 200, to = "rain"}, {at = 515, to = "thunderstorm"}, {at = 800, to = "cloudy"},
               {at = 950, to = "thunderstorm"}}
  local cursor = strikes.new(p.lightningSeed)
  local all = strikes.between(cursor, p, 0, 1200)
  local suffix = signatures(all, 613.4)
  assert(#all > 4 and suffix ~= "")
  assert(all[1].at < 60 and all[#all].at > 1140)
  local frames = {}
  local framed = strikes.new(p.lightningSeed)
  local lo = 0
  while lo < 1200 do
    local hi = math.min(lo + 0.17, 1200)
    for _, s in ipairs(strikes.between(framed, p, lo, hi)) do
      strikes.sound(s.soundRoll, hi * 5)
      frames[#frames + 1] = signature(s)
    end
    lo = hi
  end
  assertEq(table.concat(frames, "\n"), signatures(all))
  for _, c in ipairs({strikes.new(p.lightningSeed), framed, cursor}) do
    assertEq(signatures(strikes.between(c, p, 613.4, 1200)), suffix)
  end
  local split = all[3].at
  assertEq(signatures(strikes.between(cursor, p, 0, split)) .. "\n" ..
           signatures(strikes.between(cursor, p, split, 1200)), signatures(all))
  p.lightningSeed = 31416
  assert(signatures(strikes.between(strikes.new(p.lightningSeed), p, 613.4, 1200)) ~= suffix)
end)

test("only a seeded thunderstorm after GO emits strikes", function()
  local cursor = strikes.new(1)
  assertEq(#strikes.between(cursor, nil, 0, 2000), 0)
  assertEq(#strikes.between(cursor, storm(nil), 0, 2000), 0)
  for _, seed in ipairs({0, -1, 1.5, 2147483647, "1"}) do
    assertEq(#strikes.between(strikes.new(seed), storm(seed), 0, 2000), 0)
  end
  assertEq(#strikes.between(cursor, storm(1), -360, 0), 0)
  for _, w in ipairs({"storm", "rain", "fog", "snow", "cloudy", "clear"}) do
    assertEq(#strikes.between(cursor, {lightningSeed = 1, weather = w}, 0, 2000), 0)
  end
end)

test("storm weight follows the smoothed weather blend in both directions", function()
  local p = {weather = "rain", changes = {{at = 100, to = "thunderstorm"}, {at = 200, to = "rain"}}}
  for _, row in ipairs({{0, 0}, {15, 0.15625}, {30, 0.5}, {60, 1}}) do
    assertEq(strikes.weight(p, 100 + row[1]), row[2])
    assertEq(strikes.weight(p, 200 + row[1]), 1 - row[2])
  end
  p = {weather = "thunderstorm", changes = {{at = 100, to = "thunderstorm"}}}
  assertEq(strikes.weight(p, 115), 1)
end)

test("thinning at each candidate time retains its original details", function()
  for _, row in ipairs({{1, {5, 6}}, {42, {6, 7}}, {4242, {5}}, {5333, {4, 5}}}) do
    local seed = row[1]
    local p = storm(seed, 10, 40)
    local full = strikes.between(strikes.new(seed), p, 0, 160)
    p.weather, p.changes = "rain", {{at = 100, to = "thunderstorm"}}
    local partial = strikes.between(strikes.new(seed), p, 0, 160)
    assertEq(#partial, #row[2])
    for i, index in ipairs(row[2]) do assertEq(signature(partial[i]), signature(full[index])) end
  end
end)

test("fixed waits deliver a strike once at each frame and window boundary", function()
  local p, cursor = storm(55, 5, 5), strikes.new(55)
  assertEq(#strikes.between(cursor, p, -3, 4.99), 0)
  local expectedShapes = {3876417, 1336741714, 901101044, 1370660142}
  for at = 5, 125, 5 do
    local events = strikes.between(cursor, p, at - 0.01, at)
    assertEq(#events, 1)
    assertEq(events[1].at, at)
    if at <= 20 then assertEq(events[1].shapeSeed, expectedShapes[at / 5]) end
    assertEq(#strikes.between(cursor, p, at, at + 4.99), 0)
  end
  local late = strikes.between(strikes.new(55), p, 60, 125)
  assertEq(#late, 13)
  assertEq(late[1].at, 65)
end)

test("old and malformed sky intervals use the default 5 to 20 seconds", function()
  local expected = strikes.between(strikes.new(4242), storm(4242, 5, 20), 0, 150)
  assertNear(expected[1].at, 5 + 15 * (4242 * 16807 / 2147483647), 1e-10)
  for _, bounds in ipairs({{}, {5}, {nil, 5}, {0, 0}, {-1, 5}, {1.5, 9}, {1, 2.5},
                           {3, 2}, {"5", 10}, {1, true}, {0/0, 9}, {1, math.huge}}) do
    local p = storm(4242, bounds[1], bounds[2])
    assertEq(signatures(strikes.between(strikes.new(4242), p, 0, 150)), signatures(expected))
  end
end)

test("full storms draw uniformly within configured waits and retain the distance bands", function()
  local p, cursor = storm(4242, 8, 36), strikes.new(4242)
  local quartiles = {0, 0, 0, 0}
  local count, close, medium, last = 0, 0, 0, 0
  for lo = 0, 249999, 100 do
    for _, s in ipairs(strikes.between(cursor, p, lo, lo + 100)) do
      local wait = s.at - last
      assert(wait >= 8 and wait <= 36 and s.at > lo and s.at <= lo + 100)
      local quartile = math.min(4, 1 + math.floor((wait - 8) / 7))
      quartiles[quartile] = quartiles[quartile] + 1
      assert(s.range >= 300 and s.range <= 6000 and s.bearing >= 0 and s.bearing < 360)
      assert(s.soundRoll >= 0 and s.soundRoll < 1 and s.shapeSeed % 1 == 0)
      if s.range < 1000 then close = close + 1 elseif s.range < 3000 then medium = medium + 1 end
      last, count = s.at, count + 1
    end
  end
  for _, n in ipairs(quartiles) do assertNear(n / count, 0.25, 0.02) end
  assertNear(close / count, 0.10, 0.02)
  assertNear(medium / count, 0.35, 0.02)
  assertNear((count - close - medium) / count, 0.55, 0.02)
end)

test("a strike's distance leaves the next wait and keep roll independent", function()
  local p = storm(4242, 10, 40)
  local all = strikes.between(strikes.new(4242), p, 0, 125000)
  local blend = storm(4242, 10, 40)
  blend.weather, blend.changes = "rain", {{to = "thunderstorm"}}
  local cursor = strikes.new(4242)
  local waits = {{n = 0, long = 0}, {n = 0, long = 0}, {n = 0, long = 0}}
  local kept = {{n = 0, yes = 0}, {n = 0, yes = 0}}
  for i = 2, #all do
    local previous, following = all[i - 1], all[i]
    local band, midpoint = 3, 4500
    if previous.range < 1000 then band, midpoint = 1, 650
    elseif previous.range < 3000 then band, midpoint = 2, 2000 end
    local w = waits[band]
    w.n = w.n + 1
    if following.at - previous.at > 25 then w.long = w.long + 1 end
    blend.changes[1].at = following.at - 30
    local k = kept[previous.range < midpoint and 1 or 2]
    k.n = k.n + 1
    k.yes = k.yes + #strikes.between(cursor, blend, previous.at, following.at)
  end
  for _, w in ipairs(waits) do assertNear(w.long / w.n, 0.5, 0.06, "wait by distance band") end
  for _, k in ipairs(kept) do assertNear(k.yes / k.n, 0.5, 0.08, "keep roll by within-band distance") end
end)

test("pulse count leaves the bolt free to bend in either direction", function()
  local sides = {{}, {}, {}}
  for _, s in ipairs(strikes.between(strikes.new(42), storm(42), 0, 6000)) do
    local midpoint = strikes.bolt(s.shapeSeed).main[33]
    sides[#s.pulses - 1][midpoint.x > 0] = true
  end
  for _, bends in ipairs(sides) do assert(bends[true] and bends[false], "one-sided bend for a pulse count") end
end)

test("every pulse fits the half-second flash with a dark gap before each return", function()
  local p = storm(101)
  local sizes = {}
  for _, s in ipairs(strikes.between(strikes.new(101), p, 0, 3000)) do
    local pulses = s.pulses
    assert(#pulses >= 2 and #pulses <= 4)
    sizes[#pulses] = true
    assertEq(pulses[1].start, 0)
    assertEq(pulses[1].level, 1)
    assert(pulses[1].length >= 0.05 and pulses[1].length <= 0.07)
    local finish = pulses[1].length
    for i = 2, #pulses do
      local pulse = pulses[i]
      assert(pulse.start - finish >= 0.04 and pulse.start - finish <= 0.07)
      assert(pulse.length >= 0.04 and pulse.length <= 0.07)
      assert(pulse.level >= 0.5 and pulse.level <= 1)
      finish = pulse.start + pulse.length
    end
    assert(finish <= 0.5)
  end
  assert(sizes[2] and sizes[3] and sizes[4])
end)

test("jagged bolt channels descend from the cloud and branch out from interior points", function()
  local sizes = {}
  for seed = 1, 80 do
    local shape = strikes.bolt(seed)
    assertEq(#shape.main, 65)
    assertEq(shape.main[1].z, 900)
    local foot = shape.main[65]
    assert(foot.x == 0 and foot.y == 0 and foot.z == 0)
    local function descending(line)
      for i = 2, #line do assert(line[i].z < line[i - 1].z) end
    end
    descending(shape.main)
    assert(shape.main[33].x ~= 0 or shape.main[33].y ~= 0)
    assert(#shape.branches >= 1 and #shape.branches <= 3)
    sizes[#shape.branches] = true
    for _, line in ipairs(shape.branches) do
      assertEq(#line, 17)
      descending(line)
      local root, tip = line[1], line[17]
      local attached = false
      for i = 2, 64 do
        local pt = shape.main[i]
        if pt.x == root.x and pt.y == root.y and pt.z == root.z then attached = true end
      end
      assert(attached)
      local dx, dy, dz = tip.x - root.x, tip.y - root.y, tip.z - root.z
      local length = math.sqrt(dx * dx + dy * dy + dz * dz)
      assert(length >= 150 and length <= 350)
      assert(tip.x ^ 2 + tip.y ^ 2 > root.x ^ 2 + root.y ^ 2 and tip.z >= 0)
    end
  end
  assert(sizes[1] and sizes[2] and sizes[3])
end)

test("the listener distance selects thunder, delay, gain and flash intensity", function()
  for _, row in ipairs({{999.9, clips.close}, {1000, clips.medium}, {3000, clips.medium}, {3000.1, clips.far}}) do
    local d, group = row[1], row[2]
    assertEq(strikes.sound(0, d), group[1])
    assertEq(strikes.sound(0.999999999, d), group[#group])
  end
  for _, row in ipairs({{343, 1}, {3430, 10}}) do
    local _, delay = strikes.sound(0.5, row[1])
    assertEq(delay, row[2])
  end
  for _, row in ipairs({{0, 1}, {500, 1}, {3250, 0.675}, {6000, 0.35}, {7000, 0.35}}) do
    local _, _, volume = strikes.sound(0.5, row[1])
    assertNear(volume, row[2], 1e-12)
  end
  for _, row in ipairs({{0, 1e10}, {300, 1e10}, {3000, 1e8}, {6000, 2.5e7}}) do
    assertNear(strikes.strength(row[1]), row[2], 1e-6)
  end
end)
