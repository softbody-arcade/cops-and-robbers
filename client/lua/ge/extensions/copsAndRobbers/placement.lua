local M = {}

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepCopy(v) end
  return c
end

local function appIndex(layout, appName)
  for i, app in ipairs(type(layout) == "table" and layout.apps or {}) do
    if app.appName == appName then return i end
  end
  return nil
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function M.new(appName, placement)
  return { appName = appName, placement = placement, active = false, placed = {}, optedOut = {}, createdCopy = {}, hidMod = {} }
end

function M.activate(state)
  state.active = true
end

function M.leave(state, env)
  local createdCopy, hidMod = state.createdCopy or {}, state.hidMod or {}
  state.active = false
  state.placed, state.optedOut, state.createdCopy, state.hidMod = {}, {}, {}, {}
  local api = env.api
  for _, layout in ipairs(api.getAvailableLayouts() or {}) do
    local fresh = env.readLayout(layout.filename) or layout
    local idx = appIndex(fresh, state.appName)
    while idx do
      api.removeApp(layout.filename, idx - 1)
      table.remove(fresh.apps, idx)
      idx = appIndex(fresh, state.appName)
    end
    if createdCopy[layout.filename] and api.resetLayout and env.readOriginal then
      local original = env.readOriginal(layout.filename)
      if type(original) == "table" and same(original.apps or {}, fresh.apps or {}) then api.resetLayout(layout.filename) end
    end
    local modApps = hidMod[layout.filename]
    if modApps and env.removeUserFile and same(modApps, fresh.apps or {}) then env.removeUserFile(layout.filename) end
  end
  local current = api.getCurrentLayout()
  if type(current) == "table" and current.filename then api.setCurrentLayout(current.filename) end
end

function M.tick(state, env)
  if not state.active then return false end
  if not env.appExists then
    M.leave(state, env)
    return false
  end
  local api = env.api
  local current = api.getCurrentLayout()
  if type(current) ~= "table" or not current.filename then return false end
  local name = current.filename
  local fresh = env.readLayout(name) or current
  if appIndex(fresh, state.appName) then
    state.placed[name] = true
    return true
  end
  if state.placed[name] then
    state.placed[name] = nil
    state.optedOut[name] = true
    return false
  end
  if state.optedOut[name] then return false end
  local makesCopy = current.userFileExists == false
  local modApps = not makesCopy and env.fromMod and env.fromMod(name) and deepCopy(fresh.apps or {})
  if api.addApp(name, state.appName, copy(state.placement)) then
    state.placed[name] = true
    if makesCopy then state.createdCopy[name] = true end
    if modApps then state.hidMod[name] = modApps end
    api.setCurrentLayout(name)
    return true
  end
  return false
end

return M
