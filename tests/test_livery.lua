dofile("tests/client_stubs.lua")

local PC = "vehicles/pickup/racing.pc"
local LIVERY = { format = 2, model = "pickup", parts = { pickup_engine = "v8", pickup_paint_design = "pickup_skin_stripes" }, vars = {} }
local RED = { r = 1, g = 0, b = 0 }

local function files()
  return { ["/" .. PC] = LIVERY }
end

local function setup(role, extra)
  local s = { role = role, runnerId = 2, model = "pickup", config = PC, phase = "prep", runnerPos = { x = 0, y = 0, z = 0 }, color = RED }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function cleared(opt)
  assertEq(type(opt.config), "table")
  assertEq(opt.config.parts.pickup_paint_design, "")
  assertEq(opt.config.parts.pickup_engine, "v8")
  assertEq(opt.paint.x, 1)
end

test("a runner's round car loses the config's livery when the player has a colour", function()
  local env = bootClient({ files = files() })
  env.fire("cnr_roundSetup", setup("runner"))
  env.tick(1)
  cleared(env.replaced[#env.replaced].opt)
end)

test("practice as a cop loses the livery too", function()
  local env = bootClient({ files = files() })
  env.fire("cnr_roundSetup", setup("cop", { practice = true }))
  env.tick(1)
  cleared(env.replaced[#env.replaced].opt)
end)

test("practice AI cars lose the livery in their colour", function()
  local env = bootClient({ files = files() })
  env.fire("cnr_roundSetup", setup("runner", { practice = true }))
  env.fire("cnr_setupAI", { model = "pickup", config = PC, runnerId = 1, ai = { { id = -10, role = "cop", name = "AI cop 1", index = 1, color = RED } } })
  env.tick(1)
  cleared(env.spawned[1].opt)
end)

test("a repaint in prep drops the livery", function()
  local env = bootClient({ files = files() })
  env.fire("cnr_roundSetup", setup("runner", { color = false }))
  env.tick(1)
  env.fire("cnr_paint", { color = RED })
  cleared(env.replaced[#env.replaced].opt)
end)

test("without a colour the livery stays and the config is passed as is", function()
  local env = bootClient({ files = files() })
  env.fire("cnr_roundSetup", setup("runner", { color = false }))
  env.tick(1)
  assertEq(env.replaced[#env.replaced].opt.config, PC)
end)

test("a car without a livery keeps its config path under a colour", function()
  local env = bootClient({ files = { ["/" .. PC] = { format = 2, model = "pickup", parts = { pickup_engine = "v8", pickup_paint_design = "" }, vars = {} } } })
  env.fire("cnr_roundSetup", setup("runner"))
  env.tick(1)
  assertEq(env.replaced[#env.replaced].opt.config, PC)
end)
