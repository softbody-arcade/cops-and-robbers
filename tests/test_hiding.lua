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
  for _, k in ipairs({ "MPVehicleGE", "activeVehiclesIterator", "ui_apps_minimap_vehicles", "log" }) do saved[k] = _G[k] end
  _G.log = function() end
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
  _G.log = saved.log
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
    hiding.set({ vids = { [2] = true }, keys = { ["2-0"] = true }, minimap = true })
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
    hiding.set({ vids = { [2] = true }, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(activeVehiclesIterator, iterator)
  end)
end)

test("a draw error is logged once per load", function()
  run(function()
    local logs = {}
    _G.log = function(level, tag, msg) logs[#logs + 1] = { level = level, tag = tag, msg = msg } end
    local ok, err = pcall(function()
      local function failing() error("boom") end
      ui_apps_minimap_vehicles.drawOtherVehicles = failing
      hiding.set({ vids = { [2] = true }, minimap = true })
      hiding.tick(0)
      ui_apps_minimap_vehicles.drawOtherVehicles()
      ui_apps_minimap_vehicles.drawOtherVehicles()
      hiding.unload()
      package.loaded["copsAndRobbers/hiding"] = nil
      hiding = require("copsAndRobbers/hiding")
      hiding.set({ vids = { [2] = true }, minimap = true })
      hiding.tick(0)
      assert(ui_apps_minimap_vehicles.drawOtherVehicles ~= failing)
      ui_apps_minimap_vehicles.drawOtherVehicles()
    end)
    assert(ok, err)
    assertEq(#logs, 2)
    assertEq(logs[1].level, "E"); assertEq(logs[1].tag, "cnr_hiding")
    assertEq(logs[1].msg:find("boom", 1, true) ~= nil, true)
  end)
end)

test("a draw error is logged again after unload without reloading the module", function()
  run(function()
    local logs = {}
    _G.log = function(level, tag, msg) logs[#logs + 1] = msg end
    local ok, err = pcall(function()
      ui_apps_minimap_vehicles.drawOtherVehicles = function() error("boom") end
      hiding.set({ vids = { [2] = true }, minimap = true })
      hiding.tick(0)
      ui_apps_minimap_vehicles.drawOtherVehicles()
      hiding.unload()
      ui_apps_minimap_vehicles.drawOtherVehicles = function() error("boom") end
      hiding.set({ vids = { [2] = true }, minimap = true })
      hiding.tick(10)
      ui_apps_minimap_vehicles.drawOtherVehicles()
    end)
    assert(ok, err)
    assertEq(#logs, 2)
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
    hiding.set({ vids = { [2] = true }, keys = { ["2-0"] = true }, minimap = false })
    hiding.tick(0)
    assertEq(vehicles["2-0"].hideNametag, true)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "1,2,3")
  end)
end)

test("clear shows the name tag again", function()
  run(function()
    hiding.set({ keys = { ["2-0"] = true }, minimap = false })
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
    hiding.set({ keys = { ["2-0"] = true } })
    hiding.set({ keys = { ["2-1"] = true } })
    assertEq(vehicles["2-0"].hideNametag, nil)
    assertEq(vehicles["2-1"].hideNametag, true)
  end)
end)

test("a rebuilt vehicle table gets the flag back within a second", function()
  run(function()
    hiding.set({ keys = { ["2-0"] = true } })
    hiding.tick(0)
    vehicles = { ["2-0"] = {} }
    hiding.set({ keys = { ["2-0"] = true } })
    hiding.tick(0.5)
    hiding.tick(1.0)
    assertEq(vehicles["2-0"].hideNametag, true)
  end)
end)

test("the minimap is wrapped lazily and again after a reload", function()
  run(function()
    local original = ui_apps_minimap_vehicles
    ui_apps_minimap_vehicles = nil
    hiding.set({ vids = { [2] = true }, minimap = true })
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
    hiding.set({ vids = { [2] = true }, minimap = true })
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
    hiding.set({ vids = { [2] = true }, minimap = true })
    hiding.tick(0)
    local wrapper = ui_apps_minimap_vehicles.drawOtherVehicles
    hiding.unload()
    wrapper()
    assertEq(ids(), "1,2,3")
  end)
end)

test("several keys are hidden together and cleared together", function()
  run(function()
    vehicles["3-0"] = {}
    vehicles["4-0"] = {}
    hiding.set({ keys = { ["3-0"] = true, ["4-0"] = true } })
    assertEq(vehicles["3-0"].hideNametag, true)
    assertEq(vehicles["4-0"].hideNametag, true)
    assertEq(vehicles["2-0"].hideNametag, nil)
    hiding.clear()
    assertEq(vehicles["3-0"].hideNametag, nil)
    assertEq(vehicles["4-0"].hideNametag, nil)
  end)
end)

test("a key leaving the target gets its name tag back", function()
  run(function()
    vehicles["3-0"] = {}
    hiding.set({ keys = { ["2-0"] = true, ["3-0"] = true } })
    hiding.set({ keys = { ["3-0"] = true } })
    assertEq(vehicles["2-0"].hideNametag, nil)
    assertEq(vehicles["3-0"].hideNametag, true)
    hiding.set(nil)
    assertEq(vehicles["3-0"].hideNametag, nil)
  end)
end)

test("the wrapper skips several vids", function()
  run(function()
    hiding.set({ vids = { [1] = true, [3] = true }, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles.drawOtherVehicles()
    assertEq(ids(), "2")
    assertEq(activeVehiclesIterator, iterator)
  end)
end)

test("the re-assert restores every hidden key after a rebuilt vehicle table", function()
  run(function()
    vehicles["3-0"] = {}
    hiding.set({ keys = { ["2-0"] = true, ["3-0"] = true } })
    hiding.tick(0)
    vehicles = { ["2-0"] = {}, ["3-0"] = {} }
    hiding.tick(1)
    assertEq(vehicles["2-0"].hideNametag, true)
    assertEq(vehicles["3-0"].hideNametag, true)
  end)
end)

local function namedDraw(name, calls)
  return function()
    calls[#calls + 1] = name
    draw()
  end
end

test("an older minimap table coming back draws with its own original, and unload gives each table its own", function()
  run(function()
    local calls = {}
    local drawA, drawB = namedDraw("A", calls), namedDraw("B", calls)
    local extA, extB = { drawOtherVehicles = drawA }, { drawOtherVehicles = drawB }
    ui_apps_minimap_vehicles = extA
    hiding.set({ vids = { [2] = true }, minimap = true })
    hiding.tick(0)
    ui_apps_minimap_vehicles = extB
    hiding.tick(1)
    ui_apps_minimap_vehicles = extA
    hiding.tick(2)
    extA.drawOtherVehicles()
    assertEq(table.concat(calls, ","), "A")
    assertEq(ids(), "1,3")
    hiding.unload()
    assertEq(extA.drawOtherVehicles, drawA)
    assertEq(extB.drawOtherVehicles, drawB)
  end)
end)

test("after the minimap reloads, the old table gets its original back and its old wrapper keeps to it", function()
  run(function()
    local calls = {}
    local drawA, drawB = namedDraw("A", calls), namedDraw("B", calls)
    local extA, extB = { drawOtherVehicles = drawA }, { drawOtherVehicles = drawB }
    ui_apps_minimap_vehicles = extA
    hiding.set({ vids = { [2] = true }, minimap = true })
    hiding.tick(0)
    local oldWrapper = extA.drawOtherVehicles
    ui_apps_minimap_vehicles = extB
    hiding.tick(1)
    assertEq(extA.drawOtherVehicles, drawA)
    assert(extB.drawOtherVehicles ~= drawB)
    oldWrapper()
    assertEq(table.concat(calls, ","), "A")
    extB.drawOtherVehicles()
    assertEq(table.concat(calls, ","), "A,B")
    assertEq(ids(), "1,3")
  end)
end)
