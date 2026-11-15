local M = {}

local WINDOW = 8

local armedUntil

local function realEnv()
  return {
    router = extensions and extensions.ui_router or ui_router,
    levelLoaded = function() return type(getMissionFilename) == "function" and getMissionFilename() ~= "" end,
  }
end

function M.start(clock)
  armedUntil = clock + WINDOW
end

function M.stop()
  armedUntil = nil
end

function M.update(clock, env)
  if not armedUntil then return end
  if clock >= armedUntil then armedUntil = nil return end
  env = env or realEnv()
  local router = env.router
  if not router then return end
  local ok, route = pcall(router.getCurrent)
  if not ok or type(route) ~= "table" or type(route.resolved) ~= "table" or route.resolved.name ~= "menu" then return end
  local loaded, level = pcall(env.levelLoaded)
  if not loaded or not level then return end
  armedUntil = nil
  log("I", "cnr_joinguard", "landed on the main menu after loading, sending to play")
  pcall(router.navigate, "play")
end

return M
