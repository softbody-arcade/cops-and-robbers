local M = {}

local TICK_INTERVAL = 1

local target
local hiddenKeys = {}
local lastTick = -math.huge
local wrapped
local lastOriginal

local function vehicleEntry(key)
  if not key or not MPVehicleGE or not MPVehicleGE.getVehicles then return nil end
  local v = (MPVehicleGE.getVehicles() or {})[key]
  return type(v) == "table" and v or nil
end

local function clearTag(key)
  local v = vehicleEntry(key)
  if v then v.hideNametag = nil end
  hiddenKeys[key] = nil
end

local function clearTags()
  for key in pairs(hiddenKeys) do clearTag(key) end
end

local function drawWrapper(...)
  local original = wrapped and wrapped.original or lastOriginal
  if not original then return end
  local vids = target and target.minimap and target.vids
  if not vids or not next(vids) then return original(...) end
  local realIterator = activeVehiclesIterator
  activeVehiclesIterator = function(ctx)
    local iterate, state = realIterator(ctx)
    local function skip(s, control)
      local id, veh = iterate(s, control)
      while id ~= nil and vids[id] do
        id, veh = iterate(s, id)
      end
      return id, veh
    end
    return skip, state
  end
  pcall(original, ...)
  activeVehiclesIterator = realIterator
end

local function wrap()
  local ext = ui_apps_minimap_vehicles
  if type(ext) ~= "table" or type(ext.drawOtherVehicles) ~= "function" then return end
  if ext.drawOtherVehicles == drawWrapper then
    if wrapped then
      wrapped.ext = ext
    elseif lastOriginal then
      wrapped = { ext = ext, original = lastOriginal }
    end
    return
  end
  wrapped = { ext = ext, original = ext.drawOtherVehicles }
  lastOriginal = wrapped.original
  ext.drawOtherVehicles = drawWrapper
end

function M.set(newTarget)
  target = newTarget
  local keys = newTarget and newTarget.keys or {}
  for key in pairs(hiddenKeys) do
    if not keys[key] then clearTag(key) end
  end
  for key in pairs(keys) do
    if not hiddenKeys[key] then
      local v = vehicleEntry(key)
      if v then
        v.hideNametag = true
        hiddenKeys[key] = true
      end
    end
  end
end

function M.tick(clock)
  if clock - lastTick < TICK_INTERVAL then return end
  lastTick = clock
  for key in pairs(hiddenKeys) do
    local v = vehicleEntry(key)
    if v then v.hideNametag = true end
  end
  if target and target.keys then
    for key in pairs(target.keys) do
      if not hiddenKeys[key] then
        local v = vehicleEntry(key)
        if v then
          v.hideNametag = true
          hiddenKeys[key] = true
        end
      end
    end
  end
  wrap()
end

function M.clear()
  clearTags()
  target = nil
end

function M.unload()
  M.clear()
  if wrapped and wrapped.ext.drawOtherVehicles == drawWrapper then
    wrapped.ext.drawOtherVehicles = wrapped.original
  end
  wrapped = nil
end

return M
