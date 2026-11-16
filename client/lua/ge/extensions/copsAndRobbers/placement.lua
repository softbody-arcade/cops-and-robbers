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

M.appIndex = appIndex

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

function M.group()
  return { createdCopy = {}, hidMod = {} }
end

function M.new(appName, placement, opts)
  opts = opts or {}
  return { appName = appName, placement = placement, sticky = opts.sticky or false, active = false, placed = {}, optedOut = {}, group = opts.group or M.group() }
end

function M.activate(state)
  state.active = true
end

function M.leave(state, env)
  local group = state.group
  state.active = false
  state.placed, state.optedOut = {}, {}
  local api = env.api
  for _, layout in ipairs(api.getAvailableLayouts() or {}) do
    local name = layout.filename
    local fresh = env.readLayout(name) or layout
    local idx = appIndex(fresh, state.appName)
    while idx do
      api.removeApp(name, idx - 1)
      table.remove(fresh.apps, idx)
      idx = appIndex(fresh, state.appName)
    end
    if group.createdCopy[name] and api.resetLayout and env.readOriginal then
      local original = env.readOriginal(name)
      if type(original) == "table" and same(original.apps or {}, fresh.apps or {}) then
        api.resetLayout(name)
        group.createdCopy[name] = nil
      end
    end
    local modApps = group.hidMod[name]
    if modApps and env.removeUserFile and same(modApps, fresh.apps or {}) then
      env.removeUserFile(name)
      group.hidMod[name] = nil
    end
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
    if not state.sticky then
      state.optedOut[name] = true
      return false
    end
  end
  if state.optedOut[name] then return false end
  local makesCopy = current.userFileExists == false
  local modApps = not makesCopy and env.fromMod and env.fromMod(name) and deepCopy(fresh.apps or {})
  if api.addApp(name, state.appName, copy(state.placement)) then
    state.placed[name] = true
    if makesCopy then state.group.createdCopy[name] = true end
    if modApps and not state.group.hidMod[name] then state.group.hidMod[name] = modApps end
    api.setCurrentLayout(name)
    return true
  end
  return false
end

return M
