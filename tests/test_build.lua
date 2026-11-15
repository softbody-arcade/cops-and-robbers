local build = require("cnr.build")
local config = require("cnr.config")

local function sample()
  return build.new("pickup", "Gavril D-Series", { pickup_engine = "pickup_engine_v8", pickup_wheel_F = "steel" }, { gear1 = 3.1 }, "random", 100)
end

test("a new build starts at change 0", function()
  local b = sample()
  assertEq(b.step, 0); assertEq(b.model, "pickup"); assertEq(b.name, "Gavril D-Series"); assertEq(b.startedFrom, "random")
  assertEq(b.parts.pickup_engine, "pickup_engine_v8"); assertEq(b.vars.gear1, 3.1); assertEq(#b.history, 0)
end)

test("normalize accepts a saved build and fills empty lists BeamMP writes as null", function()
  local b = build.normalize({ model = "pickup", parts = { a = "b" }, step = 2 })
  assertEq(b.step, 2); assertEq(type(b.vars), "table"); assertEq(type(b.history), "table"); assertEq(b.name, "pickup")
  assertEq(build.normalize({ parts = { a = "b" } }), nil)
  assertEq(build.normalize({ model = "pickup", parts = { a = 1 } }), nil)
  assertEq(build.normalize("x"), nil)
end)

test("apply records a change and bumps the step", function()
  local b = sample()
  local setup = { parts = { pickup_engine = "pickup_engine_v8_60", pickup_wheel_F = "steel" }, vars = { gear1 = 3.1 } }
  local changes = { { label = "Engine", from = "4.5L V8", to = "6.0L V8" } }
  local nb, changed = build.apply(b, setup, changes, "Bob", 200)
  assertEq(changed, true); assertEq(nb.step, 1); assertEq(nb.parts.pickup_engine, "pickup_engine_v8_60")
  assertEq(nb.history[1].by, "Bob"); assertEq(nb.history[1].changes[1].label, "Engine")
  assertEq(b.step, 0); assertEq(b.parts.pickup_engine, "pickup_engine_v8")
end)

test("apply with no change keeps the build and its step", function()
  local b = sample()
  local nb, changed = build.apply(b, { parts = { pickup_engine = "pickup_engine_v8", pickup_wheel_F = "steel" }, vars = { gear1 = 3.1 } }, {}, "Bob", 200)
  assertEq(changed, false); assertEq(nb.step, 0)
end)

test("apply with an empty change list keeps the step but adopts the resolved parts", function()
  local b = sample()
  local resolved = { parts = { pickup_engine = "pickup_engine_v8", pickup_wheel_F = "steel", pickup_frame = "frame" }, vars = { gear1 = 3.1, arb = 40000 } }
  local nb, changed = build.apply(b, resolved, {}, "Bob", 200)
  assertEq(changed, false); assertEq(nb.step, 0); assertEq(#nb.history, 0)
  assertEq(nb.parts.pickup_frame, "frame"); assertEq(nb.vars.arb, 40000)
end)

test("label and change line", function()
  local b = sample()
  b.step = 7
  assertEq(build.label(b), "Gavril D-Series · change 7")
  local one = { { label = "Engine", from = "4.5L V8", to = "6.0L V8" } }
  assertEq(build.changeLine(7, "Bob", one), "Change 7 by Bob: Engine 4.5L V8 → 6.0L V8")
  local three = { one[1], { label = "Intake", from = "Stock", to = "Big" }, { label = "Gear 1", from = "3.1", to = "3.4" } }
  assertEq(build.changeLine(7, "Bob", three), "Change 7 by Bob: Engine 4.5L V8 → 6.0L V8 and 2 more changes")
  local swap = { { label = "Engine", from = "2.0L I4", to = "3.0L I6", extra = 12 } }
  assertEq(build.changeLine(3, "Gizmo", swap), "Change 3 by Gizmo: Engine 2.0L I4 → 3.0L I6 (+12 parts)")
end)

test("carMode accepts random and evolving only", function()
  assertEq(config.merge(nil).carMode, "random")
  assertEq(config.merge({ carMode = "evolving" }).carMode, "evolving")
  local cfg, warnings = config.merge({ carMode = "x" })
  assertEq(cfg.carMode, "random"); assertEq(#warnings, 1)
  assertEq(config.setValue({}, "carMode", "evolving").carMode, "evolving")
  assertEq(config.setValue({}, "carMode", "nope"), nil)
end)

test("lastChange summarises the newest change", function()
  local b = sample()
  assertEq(build.lastChange(b), nil)
  local one = { { label = "Engine", from = "4.5L V8", to = "6.0L V8" } }
  b = build.apply(b, { parts = { pickup_engine = "a" }, vars = {} }, one, "Bob", 200)
  local last = build.lastChange(b)
  assertEq(last.step, 1); assertEq(last.by, "Bob"); assertEq(last.text, "Engine 4.5L V8 → 6.0L V8")
  local three = { one[1], { label = "Intake", from = "Stock", to = "Big" }, { label = "Gear 1", from = "3.1", to = "3.4" } }
  b = build.apply(b, { parts = { pickup_engine = "b" }, vars = {} }, three, "Ann", 300)
  last = build.lastChange(b)
  assertEq(last.step, 2); assertEq(last.by, "Ann"); assertEq(last.text, "Engine 4.5L V8 → 6.0L V8 and 2 more")
end)
