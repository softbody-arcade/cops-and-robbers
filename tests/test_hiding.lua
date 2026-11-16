local hiding

local saved = {}
local seen
local vehicles

local function iterator(ctx)
  local ids = { 1, 2, 3 }
  local i = 0
  return function()
    i = i + 1
    if ids[i] then return ids[i], { id = ids[i] } end
  end, ctx
end

local function draw()
  seen = {}
  for id in activeVehiclesIterator({}) do seen[#seen + 1] = id end
end

local function setup()
  package.loaded["copsAndRobbers/hiding"] = nil
  hiding = require("copsAndRobbers/hiding")
  for _, k in ipairs({ "MPVehicleGE", "activeVehiclesIterator", "ui_apps_minimap_vehicles" }) do saved[k] = _G[k] end
  vehicles = { ["2-0"] = {} }
  MPVehicleGE = { getVehicles = function() return vehicles end }
  activeVehiclesIterator = iterator
  ui_apps_minimap_vehicles = { drawOtherVehicles = draw }
  seen = nil
end

local function teardown()
  hiding.unload()
  _G.MPVehicleGE = saved.MPVehicleGE
  _G.activeVehiclesIterator = saved.activeVehiclesIterator
  _G.ui_apps_minimap_vehicles = saved.ui_apps_minimap_vehicles
end

local function run(fn)
  setup()
  local ok, err = pcall(fn)
  teardown()
  if not ok then error(err, 0) end
end

local function ids()
  return table.concat(seen, ",")
end

test("a hidden runner has no name tag and no minimap marker", function()
  run(function()
    hiding.set({ vid = 2, key = "2-0", minimap = true })
    hiding.tick(0)
    assertEq(vehicles["2-0"].hideNametag, true)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "1,3")
    assertEq(activeVehiclesIterator, iterator)
  end)
end)

test("an error in the draw still restores the iterator and does not escape", function()
  run(function()
    ui_apps_minimap_vehicles.drawOtherVehicles = function() error("boom") end
    hiding.set({ vid = 2, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(activeVehiclesIterator, iterator)
  end)
end)

test("with no target the draw sees every vehicle", function()
  run(function()
    hiding.set(nil)
    hiding.tick(0)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "1,2,3")
  end)
end)

test("without minimap hiding the name tag is hidden and the draw is untouched", function()
  run(function()
    hiding.set({ vid = 2, key = "2-0", minimap = false })
    hiding.tick(0)
    assertEq(vehicles["2-0"].hideNametag, true)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "1,2,3")
  end)
end)

test("clear shows the name tag again", function()
  run(function()
    hiding.set({ key = "2-0", minimap = false })
    hiding.tick(0)
    hiding.clear()
    assertEq(vehicles["2-0"].hideNametag, nil)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "1,2,3")
  end)
end)

test("a changed key clears the old name tag", function()
  run(function()
    vehicles["2-1"] = {}
    hiding.set({ key = "2-0" })
    hiding.set({ key = "2-1" })
    assertEq(vehicles["2-0"].hideNametag, nil)
    assertEq(vehicles["2-1"].hideNametag, true)
  end)
end)

test("a rebuilt vehicle table gets the flag back within a second", function()
  run(function()
    hiding.set({ key = "2-0" })
    hiding.tick(0)
    vehicles = { ["2-0"] = {} }
    hiding.set({ key = "2-0" })
    hiding.tick(0.5)
    hiding.tick(1.0)
    assertEq(vehicles["2-0"].hideNametag, true)
  end)
end)

test("the minimap is wrapped lazily and again after a reload", function()
  run(function()
    local original = ui_apps_minimap_vehicles
    ui_apps_minimap_vehicles = nil
    hiding.set({ vid = 2, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles = original
    assertEq(original.drawOtherVehicles, draw)
    hiding.tick(1)
    assert(original.drawOtherVehicles ~= draw)
    local fresh = { drawOtherVehicles = draw }
    ui_apps_minimap_vehicles = fresh
    hiding.tick(2)
    assert(fresh.drawOtherVehicles ~= draw)
    fresh.drawOtherVehicles()
    assertEq(ids(), "1,3")
  end)
end)

test("unload restores the original and leaves a foreign replacement", function()
  run(function()
    hiding.tick(0)
    hiding.unload()
    assertEq(ui_apps_minimap_vehicles.drawOtherVehicles, draw)
    hiding.tick(1)
    local foreign = function() end
    ui_apps_minimap_vehicles.drawOtherVehicles = foreign
    hiding.unload()
    assertEq(ui_apps_minimap_vehicles.drawOtherVehicles, foreign)
  end)
end)

test("an older wrapped table coming back never makes the wrapper call itself", function()
  run(function()
    local calls = 0
    local extA = { drawOtherVehicles = function()
      calls = calls + 1
      if calls > 5 then error("recursed") end
      draw()
    end }
    local extB = { drawOtherVehicles = draw }
    ui_apps_minimap_vehicles = extA
    hiding.set({ vid = 2, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles = extB
    hiding.tick(1)
    ui_apps_minimap_vehicles = extA
    hiding.tick(2)
    debug.sethook(function() error("draw did not return") end, "", 1000000)
    local ok1, e1 = pcall(extA.drawOtherVehicles)
    hiding.set(nil)
    local ok2, e2 = pcall(extA.drawOtherVehicles)
    debug.sethook()
    assert(ok1, e1)
    assert(ok2, e2)
    assert(calls <= 5)
    assertEq(ids(), "1,2,3")
  end)
end)

test("after unload a leftover wrapper is a pure pass-through", function()
  run(function()
    hiding.set({ vid = 2, minimap = true })
    hiding.tick(0)
    local wrapper = ui_apps_minimap_vehicles.drawOtherVehicles
    hiding.unload()
    wrapper()
    assertEq(ids(), "1,2,3")
  end)
end)
