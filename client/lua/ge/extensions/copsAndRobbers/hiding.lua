local M = {}

local TICK_INTERVAL = 1

local target
local hiddenKey
local lastTick = -math.huge
local wrapped

local function vehicleEntry(key)
  if not key or not MPVehicleGE or not MPVehicleGE.getVehicles then return nil end
  local v = (MPVehicleGE.getVehicles() or {})[key]
  return type(v) == "table" and v or nil
end

local function clearTag()
  if not hiddenKey then return end
  local v = vehicleEntry(hiddenKey)
  if v then v.hideNametag = nil end
  hiddenKey = nil
end

local function drawWrapper(...)
  local original = wrapped and wrapped.original
  if not original then return end
  local vid = target and target.minimap and target.vid
  if not vid then return original(...) end
  local realIterator = activeVehiclesIterator
  activeVehiclesIterator = function(ctx)
    local iterate, state = realIterator(ctx)
    local function skip(s, control)
      local id, veh = iterate(s, control)
      while id ~= nil and id == vid do
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
  if wrapped and wrapped.ext == ext and ext.drawOtherVehicles == drawWrapper then return end
  wrapped = { ext = ext, original = ext.drawOtherVehicles }
  ext.drawOtherVehicles = drawWrapper
end

function M.set(newTarget)
  target = newTarget
  local key = newTarget and newTarget.key or nil
  if key ~= hiddenKey then
    clearTag()
    local v = vehicleEntry(key)
    if v then
      v.hideNametag = true
      hiddenKey = key
    end
  end
end

function M.tick(clock)
  if clock - lastTick < TICK_INTERVAL then return end
  lastTick = clock
  if hiddenKey then
    local v = vehicleEntry(hiddenKey)
    if v then v.hideNametag = true end
  end
  wrap()
end

function M.clear()
  clearTag()
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
