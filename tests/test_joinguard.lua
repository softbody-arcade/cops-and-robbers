local jg = require("copsAndRobbers/joinguard")

local function fakeEnv(name, loaded)
  local e = { navigated = {}, name = name, loaded = loaded ~= false }
  e.levelLoaded = function() return e.loaded end
  e.router = {
    getCurrent = function() return e.name and { resolved = { name = e.name } } or nil end,
    navigate = function(n) e.navigated[#e.navigated + 1] = n end,
  }
  return e
end

test("joinguard sends the main menu on to play once", function()
  local e = fakeEnv("menu")
  jg.start(100)
  jg.update(101, e)
  jg.update(102, e)
  assertEq(#e.navigated, 1)
  assertEq(e.navigated[1], "play")
end)

test("joinguard leaves other routes alone", function()
  for _, n in ipairs({ "play", "pause", "menu.beammp" }) do
    local e = fakeEnv(n)
    jg.start(100)
    jg.update(101, e)
    assertEq(#e.navigated, 0)
  end
end)

test("joinguard does nothing after the window", function()
  local e = fakeEnv("menu")
  jg.start(100)
  jg.update(108.5, e)
  jg.update(109, fakeEnv("menu"))
  assertEq(#e.navigated, 0)
end)

test("joinguard does nothing without a loaded level", function()
  local e = fakeEnv("menu", false)
  jg.start(100)
  jg.update(101, e)
  assertEq(#e.navigated, 0)
end)

test("joinguard does nothing when not started or stopped", function()
  jg.stop()
  local e = fakeEnv("menu")
  jg.update(1, e)
  jg.start(1)
  jg.stop()
  jg.update(2, e)
  assertEq(#e.navigated, 0)
end)

test("joinguard survives a failing or missing router", function()
  local e = fakeEnv("menu")
  e.router.getCurrent = function() error("boom") end
  jg.start(100)
  jg.update(101, e)
  jg.update(102, { levelLoaded = function() return true end })
  assertEq(#e.navigated, 0)
end)
