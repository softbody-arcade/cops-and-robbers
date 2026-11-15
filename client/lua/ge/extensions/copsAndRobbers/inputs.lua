local M = {}

local LOCKED_ACTIONS = {
  "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road", "loadHome", "saveHome",
  "reload_vehicle", "reload_all_vehicles", "reset_all_physics", "vehicle_selector",
  "dropPlayerAtCamera", "dropPlayerAtCameraNoReset", "nodegrabberGrab", "switch_next_vehicle",
  "switch_previous_vehicle", "toggleWalkingMode",
}
local EXTRA_LOCKED_ACTIONS = {
  "toggleWalkingMode", "photomode", "toggleTrackBuilder", "toggleConsoleNG", "cefdev_console_toggle", "lua_reload",
  "toggleTraffic", "toggleAITraffic", "debugmode_reset",
}
local RESET_BUTTONS = { reset_physics = true, recover_vehicle = true, recover_vehicle_alt = true, recover_to_last_road = true, loadHome = true }
local GATED_ACTIONS = { reset_physics = true, parts_selector = true, recover_vehicle = true, recover_vehicle_alt = true, recover_to_last_road = true, loadHome = true }
local RESET_ACTIONS = { "reset_physics" }
local PARTS_ACTIONS = { "parts_selector" }
local VEHICLE_PATCH_INTERVAL = 2
local VEHICLE_UNPATCH = "if cnrOrig then recovery.startRecovering, recovery.stopRecovering, recovery.loadHome = cnrOrig.s, cnrOrig.t, cnrOrig.h; cnrOrig = nil end"

M.VEHICLE_PATCH = table.concat({
  "if not cnrOrig then cnrOrig = { s = recovery.startRecovering, t = recovery.stopRecovering, h = recovery.loadHome } end",
  "recovery.startRecovering = function() obj:queueGameEngineLua('if copsAndRobbers then copsAndRobbers.requestReset(\"place\") end') end",
  "recovery.stopRecovering = function() end",
  "recovery.loadHome = function() obj:queueGameEngineLua('if copsAndRobbers then copsAndRobbers.requestReset(\"road\") end') end",
}, " ")

local originalBigMapTeleport, originalResetGameplay, originalLastRoad
local lastVehiclePatch = -math.huge

local function lockedActions()
  local seen, list = {}, {}
  local function add(name)
    if type(name) == "string" and not seen[name] and not GATED_ACTIONS[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  local templates = core_input_actionFilter.getActionTemplates and core_input_actionFilter.getActionTemplates()
  for _, name in ipairs(templates and templates.competitive or {}) do add(name) end
  for _, name in ipairs(LOCKED_ACTIONS) do add(name) end
  for _, name in ipairs(EXTRA_LOCKED_ACTIONS) do add(name) end
  return list
end

local function guardBigMapTeleport(on)
  local bigMap = rawget(_G, "freeroam_bigMapMode")
  if not bigMap then return end
  if on and not originalBigMapTeleport then
    originalBigMapTeleport = bigMap.teleportToPoi
    bigMap.teleportToPoi = function()
      ui_message("Teleporting is disabled during a Cops and Robbers round", 4, "cnr_reset", "directions_car")
    end
  elseif not on and originalBigMapTeleport then
    bigMap.teleportToPoi = originalBigMapTeleport
    originalBigMapTeleport = nil
  end
end

local function hookResetButtons(on, requestReset)
  if on then
    if not originalResetGameplay then
      originalResetGameplay = rawget(_G, "resetGameplay")
      rawset(_G, "resetGameplay", function() requestReset("place") end)
    end
    if spawn and not originalLastRoad then
      originalLastRoad = spawn.teleportToLastRoad
      spawn.teleportToLastRoad = function() requestReset("road") end
    end
    lastVehiclePatch = -math.huge
  else
    if originalResetGameplay then
      rawset(_G, "resetGameplay", originalResetGameplay)
      originalResetGameplay = nil
    end
    if originalLastRoad then
      spawn.teleportToLastRoad = originalLastRoad
      originalLastRoad = nil
    end
    local veh = getPlayerVehicle(0)
    if veh then veh:queueLuaCommand(VEHICLE_UNPATCH) end
  end
end

function M.lock(on, requestReset)
  core_input_actionFilter.setGroup("cnr_locked", lockedActions())
  core_input_actionFilter.addAction(0, "cnr_locked", on)
  guardBigMapTeleport(on)
  hookResetButtons(on, requestReset)
end

function M.setResetKey()
  core_input_actionFilter.setGroup("cnr_resetKey", RESET_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_resetKey", false)
end

function M.setPartsMenu(allowed)
  core_input_actionFilter.setGroup("cnr_parts", PARTS_ACTIONS)
  core_input_actionFilter.addAction(0, "cnr_parts", not allowed)
end

function M.unlockAll()
  M.lock(false)
  M.setResetKey()
  M.setPartsMenu(true)
end

function M.resetIsBound()
  for _, device in ipairs(core_input_bindings and core_input_bindings.bindings or {}) do
    for _, b in ipairs(device.contents and device.contents.bindings or {}) do
      if RESET_BUTTONS[b.action] and not b.unused then return true end
    end
  end
  return false
end

function M.patchDue(clock)
  if clock - lastVehiclePatch < VEHICLE_PATCH_INTERVAL then return false end
  lastVehiclePatch = clock
  return true
end

return M
