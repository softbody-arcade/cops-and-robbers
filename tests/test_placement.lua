local placement = require("copsAndRobbers/placement")

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function fakeGame(layoutApps, currentName)
  local g = { disk = {}, current = currentName, adds = 0, failAdd = false }
  for name, apps in pairs(layoutApps) do
    g.disk[name] = { filename = name, apps = apps }
  end
  g.cache = deepcopy(g.disk[currentName])
  g.api = {
    getCurrentLayout = function() return g.cache end,
    setCurrentLayout = function(name) g.current = name; g.cache = deepcopy(g.disk[name]) end,
    getAvailableLayouts = function()
      local list = {}
      for _, l in pairs(g.disk) do list[#list + 1] = deepcopy(l) end
      return list
    end,
    addApp = function(name, app, pl)
      if g.failAdd then return false end
      g.adds = g.adds + 1
      table.insert(g.disk[name].apps, { appName = app, placement = pl })
      return true
    end,
    removeApp = function(name, idx0) table.remove(g.disk[name].apps, idx0 + 1); return true end,
  }
  g.env = {
    api = g.api,
    appExists = true,
    readLayout = function(name) return deepcopy(g.disk[name]) end,
  }
  return g
end

local function count(g, name)
  local n = 0
  for _, a in ipairs(g.disk[name].apps) do if a.appName == "hud" then n = n + 1 end end
  return n
end

local PLACE = { bottom = "70px" }

test("adds the app once to the current layout", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  assertEq(placement.tick(s, g.env), true)
  assertEq(placement.tick(s, g.env), true)
  assertEq(count(g, "beammp"), 1); assertEq(g.adds, 1)
end)

test("does nothing before activation and after leaving", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  local s = placement.new("hud", PLACE)
  assertEq(placement.tick(s, g.env), false)
  placement.activate(s)
  placement.tick(s, g.env)
  placement.leave(s, g.env)
  assertEq(count(g, "beammp"), 0)
  assertEq(placement.tick(s, g.env), false)
  assertEq(count(g, "beammp"), 0)
end)

test("leave removes leftovers from every layout, also from earlier sessions", function()
  local g = fakeGame({ beammp = { { appName = "hud" } }, freeroam = { { appName = "hud" }, { appName = "x" } } }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  assertEq(placement.tick(s, g.env), true)
  placement.leave(s, g.env)
  assertEq(count(g, "beammp"), 0); assertEq(count(g, "freeroam"), 0)
  assertEq(#g.disk.freeroam.apps, 1)
end)

test("a player removing the app is respected (stale cache does not hide it)", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  g.disk.beammp.apps = {}
  assertEq(placement.tick(s, g.env), false)
  assertEq(placement.tick(s, g.env), false)
  assertEq(count(g, "beammp"), 0)
end)

test("a failing addApp reports not placed", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  g.failAdd = true
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  assertEq(placement.tick(s, g.env), false)
end)

test("missing app files mean the session is over: clean up and stop", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  g.env.appExists = false
  assertEq(placement.tick(s, g.env), false)
  assertEq(count(g, "beammp"), 0)
  g.env.appExists = true
  assertEq(placement.tick(s, g.env), false)
end)

test("a layout switch gets the app as well", function()
  local g = fakeGame({ beammp = {}, beamngEarthMP = {} }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  g.api.setCurrentLayout("beamngEarthMP")
  assertEq(placement.tick(s, g.env), true)
  assertEq(count(g, "beamngEarthMP"), 1)
  placement.leave(s, g.env)
  assertEq(count(g, "beammp"), 0); assertEq(count(g, "beamngEarthMP"), 0)
end)

test("no current layout means not placed", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  g.cache = nil
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  assertEq(placement.tick(s, g.env), false)
end)
