local placement = require("copsAndRobbers/placement")

local M = {}

M.APPS = {
  hud = { app = "copsAndRobbersHud", dir = "CopsAndRobbersHud", sticky = true,
    placement = { left = "0", top = "0", right = "", bottom = "", width = "100%", height = "100%" } },
  panel = { app = "copsAndRobbersPanel", dir = "CopsAndRobbersPanel",
    placement = { left = "", right = "1em", top = "6em", width = "27.5em", height = "34em" } },
  board = { app = "copsAndRobbersLeaderboard", dir = "CopsAndRobbersLeaderboard",
    placement = { left = "1em", top = "6em", width = "25em", height = "32em" } },
}

local ORDER = { "hud", "panel", "board" }
local PLACEMENT_INTERVAL = 2
local PLACED_INTERVAL = 10
local LAYOUT_SETTLE_SECONDS = 0.5
local USER_LAYOUTS, ORIGINAL_LAYOUTS = "/settings/ui_apps/layouts/", "/settings/ui_apps/originalLayouts/"
local PLACEMENT_DELAY = 3

local states = {}
for _, name in ipairs(ORDER) do
  local def = M.APPS[name]
  def.files = { "/ui/modules/apps/" .. def.dir .. "/app.json", "/ui/modules/apps/" .. def.dir .. "/app.vue" }
  states[name] = placement.new(def.app, def.placement, { sticky = def.sticky })
end

local placed = false
local lastPlacementCheck = 0
local forcedCheckAt
local loadedAt

local function layoutsApi()
  return rawget(_G, "ui_appLayouts") or (extensions and extensions.ui_appLayouts)
end

local function readJson(filename)
  local ok, data = pcall(jsonReadFile, filename)
  return ok and type(data) == "table" and data or nil
end

local function placementEnv(name)
  local api = layoutsApi()
  if not api or not api.getCurrentLayout or not api.addApp or not api.removeApp
    or not api.setCurrentLayout or not api.getAvailableLayouts then
    return nil
  end
  return {
    api = api,
    appExists = FS:fileExists(M.APPS[name].files[1]),
    readLayout = function(filename)
      local data = readJson(filename)
      if data then data.filename = filename end
      return data
    end,
    readOriginal = function(filename)
      if type(filename) ~= "string" or filename:sub(1, #USER_LAYOUTS) ~= USER_LAYOUTS then return nil end
      return readJson(ORIGINAL_LAYOUTS .. filename:sub(#USER_LAYOUTS + 1))
    end,
    fromMod = function(filename)
      if type(filename) ~= "string" or not FS.getFileOriginInfo then return false end
      local ok, origin = pcall(FS.getFileOriginInfo, FS, filename)
      local archive = ok and type(origin) == "table" and origin.archivePath
      return type(archive) == "string" and archive ~= ""
    end,
    removeUserFile = function(filename)
      if type(filename) == "string" and filename:sub(1, #USER_LAYOUTS) == USER_LAYOUTS then pcall(FS.removeFile, FS, filename) end
    end,
  }
end

local function tickApp(name)
  local env = placementEnv(name)
  if not env then return false end
  local ok, isPlaced = pcall(placement.tick, states[name], env)
  return ok and isPlaced == true
end

local function inLayout(env, appName)
  local current = env.api.getCurrentLayout()
  if type(current) ~= "table" or not current.filename then return false end
  local fresh = env.readLayout(current.filename) or current
  for _, app in ipairs(fresh.apps or {}) do
    if app.appName == appName then return true end
  end
  return false
end

function M.placed()
  return placed
end

function M.isOpen(name)
  local def = M.APPS[name]
  local env = def and placementEnv(name)
  if not env then return false end
  local ok, open = pcall(inLayout, env, def.app)
  return ok and open == true
end

function M.toggle(name)
  local def = M.APPS[name]
  if not def or def.sticky then return end
  local env = placementEnv(name)
  if not env then return end
  if M.isOpen(name) then
    pcall(placement.leave, states[name], env)
  else
    local state = states[name]
    state.placed, state.optedOut = {}, {}
    placement.activate(state)
    tickApp(name)
  end
end

function M.refreshApps()
  local files = {}
  for _, name in ipairs(ORDER) do
    for _, f in ipairs(M.APPS[name].files) do files[#files + 1] = { filename = f, type = "added" } end
  end
  pcall(extensions.hook, "onFilesChanged", files)
end

function M.start(clock)
  loadedAt = clock
  placement.activate(states.hud)
end

function M.layoutChanged(clock)
  forcedCheckAt = clock + LAYOUT_SETTLE_SECONDS
end

function M.leave()
  loadedAt = nil
  placed = false
  for _, name in ipairs(ORDER) do
    local state = states[name]
    if state.active then
      local env = placementEnv(name)
      if env then pcall(placement.leave, state, env) end
      state.active = false
    end
  end
end

function M.update(clock)
  local interval = placed and PLACED_INTERVAL or PLACEMENT_INTERVAL
  local due = clock - lastPlacementCheck >= interval or (forcedCheckAt and clock >= forcedCheckAt)
  if loadedAt and clock - loadedAt >= PLACEMENT_DELAY and due then
    lastPlacementCheck = clock
    forcedCheckAt = nil
    placed = tickApp("hud")
    for _, name in ipairs(ORDER) do
      if name ~= "hud" and states[name].active then tickApp(name) end
    end
  end
end

return M
