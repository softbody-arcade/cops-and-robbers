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
  g.resets = {}
  g.api.resetLayout = function(name) g.resets[#g.resets + 1] = name; return name end
  g.originals = deepcopy(g.disk)
  g.env = {
    api = g.api,
    appExists = true,
    readLayout = function(name) return deepcopy(g.disk[name]) end,
    readOriginal = function(name) return deepcopy(g.originals[name]) end,
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
  local g = fakeGame({ beammp = {}, alternateMP = {} }, "beammp")
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  g.api.setCurrentLayout("alternateMP")
  assertEq(placement.tick(s, g.env), true)
  assertEq(count(g, "alternateMP"), 1)
  placement.leave(s, g.env)
  assertEq(count(g, "beammp"), 0); assertEq(count(g, "alternateMP"), 0)
end)

test("no current layout means not placed", function()
  local g = fakeGame({ beammp = {} }, "beammp")
  g.cache = nil
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  assertEq(placement.tick(s, g.env), false)
end)

test("leave resets a stock layout copy that only existed because the app was added", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  g.cache.userFileExists = false
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  placement.leave(s, g.env)
  assertEq(#g.resets, 1); assertEq(g.resets[1], "beammp")
end)

test("leave keeps a layout copy the player changed meanwhile", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  g.cache.userFileExists = false
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  table.insert(g.disk.beammp.apps, { appName = "speedo" })
  placement.leave(s, g.env)
  assertEq(#g.resets, 0)
end)

test("leave never resets a layout that already had a user file", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  g.cache.userFileExists = true
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  placement.leave(s, g.env)
  assertEq(#g.resets, 0)
end)

local function modLayout()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  g.cache.userFileExists = true
  g.deleted = {}
  g.env.fromMod = function(name) return name == "beammp" end
  g.env.removeUserFile = function(name) g.deleted[#g.deleted + 1] = name end
  return g
end

test("leave deletes the copy that hides a mod's layout when only the app was added", function()
  local g = modLayout()
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  placement.leave(s, g.env)
  assertEq(#g.deleted, 1); assertEq(g.deleted[1], "beammp")
  assertEq(#g.resets, 0)
end)

test("leave keeps a copy of a mod's layout the player changed meanwhile", function()
  local g = modLayout()
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  table.insert(g.disk.beammp.apps, { appName = "speedo" })
  placement.leave(s, g.env)
  assertEq(#g.deleted, 0)
end)

test("leave never deletes a layout file that was already the player's own", function()
  local g = modLayout()
  g.env.fromMod = function() return false end
  local s = placement.new("hud", PLACE)
  placement.activate(s)
  placement.tick(s, g.env)
  placement.leave(s, g.env)
  assertEq(#g.deleted, 0)
end)

test("a sticky app comes back after the player removes it", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  local s = placement.new("hud", PLACE, { sticky = true })
  placement.activate(s)
  placement.tick(s, g.env)
  g.disk.beammp.apps = { { appName = "chat" } }
  assertEq(placement.tick(s, g.env), true)
  assertEq(count(g, "beammp"), 1); assertEq(g.adds, 2)
end)

test("apps that share a group reset a stock layout copy once the last of them leaves", function()
  local g = fakeGame({ beammp = { { appName = "chat" } } }, "beammp")
  g.cache.userFileExists = false
  local group = placement.group()
  local a = placement.new("hud", PLACE, { sticky = true, group = group })
  local b = placement.new("announce", PLACE, { sticky = true, group = group })
  placement.activate(a); placement.activate(b)
  placement.tick(a, g.env); placement.tick(b, g.env)
  placement.leave(a, g.env)
  assertEq(#g.resets, 0)
  placement.leave(b, g.env)
  assertEq(#g.resets, 1); assertEq(g.resets[1], "beammp")
end)

test("apps that share a group delete a mod layout's copy once, after the last of them leaves", function()
  local g = modLayout()
  local group = placement.group()
  local a = placement.new("hud", PLACE, { sticky = true, group = group })
  local b = placement.new("announce", PLACE, { sticky = true, group = group })
  local c = placement.new("board", PLACE, { group = group })
  placement.activate(a); placement.activate(b); placement.activate(c)
  placement.tick(a, g.env); placement.tick(b, g.env); placement.tick(c, g.env)
  placement.leave(c, g.env)
  assertEq(#g.deleted, 0)
  placement.leave(a, g.env)
  placement.leave(b, g.env)
  assertEq(#g.deleted, 1); assertEq(g.deleted[1], "beammp")
end)
