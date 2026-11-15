local hud = require("copsAndRobbers/hud")
local placement = require("copsAndRobbers/placement")
local game = require("copsAndRobbers/game")

local M = {}

local HUD_APP = "copsAndRobbersHud"
local HUD_PLACEMENT = { left = "50%", right = "", bottom = "4.375em", width = "32.5em", height = "14.375em" }
local HUD_FILES = { "/ui/modules/apps/CopsAndRobbersHud/app.json", "/ui/modules/apps/CopsAndRobbersHud/app.vue" }
local PUSH_INTERVAL = 0.1
local PLACEMENT_INTERVAL = 2
local PLACED_INTERVAL = 10
local USER_LAYOUTS, ORIGINAL_LAYOUTS = "/settings/ui_apps/layouts/", "/settings/ui_apps/originalLayouts/"
local PLACEMENT_DELAY = 3
local BANNER_LABELS = { ["Runner starts in"] = "RUNNER STARTS IN", ["Cops released in"] = "COPS RELEASED IN", ["Crash penalty"] = "CRASH PENALTY" }
local RESULT_TITLES = { caught = "RUNNER CAUGHT", called = "ROUND ENDED", escaped = "ESCAPED", disconnect = "RUNNER LEFT", cancelled = "ROUND CANCELLED" }
local FLASH_SECONDS, EVENT_SECONDS, RESET_FLASH_SECONDS, RESULT_SECONDS = 2, 4, 1.5, 10

local state = hud.new()
local flash, prep, resetFlashUntil, result
local events = {}
local placed = false
local visibleSent = false
local lastPush = 0
local lastPlacementCheck = 0
local loadedAt
local placementState = placement.new(HUD_APP, HUD_PLACEMENT)

function M.placed()
  return placed
end

function M.notify(msg, ttl, category)
  if not placed then game.toast(msg, ttl, category) end
end

function M.clearRound()
  state = hud.new()
  flash, prep, resetFlashUntil = nil, nil, nil
  events = {}
end

function M.clearResult()
  result = nil
end

function M.flash(text, clock)
  flash = { text = text, untilT = clock + FLASH_SECONDS }
end

function M.event(text, clock)
  events[#events + 1] = { text = text, untilT = clock + EVENT_SECONDS }
  while #events > 5 do table.remove(events, 1) end
end

function M.prep(role, car)
  prep = role and { role = role, car = car } or nil
end

function M.resetFlash(clock)
  resetFlashUntil = clock + RESET_FLASH_SECONDS
end

function M.catchSample(clock, p)
  hud.catchSample(state, clock, p)
end

function M.isResultReason(reason)
  return RESULT_TITLES[reason] ~= nil
end

function M.showResult(d, clock)
  local cancelled = d.reason == "cancelled" or not RESULT_TITLES[d.reason]
  local catchers = (type(d.catchers) == "table" and #d.catchers > 0) and table.concat(d.catchers, ", ") or nil
  local nextAt = tonumber(d.autoNextSeconds) and (clock + tonumber(d.autoNextSeconds)) or nil
  result = {
    title = RESULT_TITLES[d.reason] or RESULT_TITLES.cancelled,
    runner = (not cancelled and d.runnerName) and tostring(d.runnerName) or nil,
    time = not cancelled and hud.formatTime(d.survivedSeconds) or nil,
    catchers = catchers,
    untilT = math.max(clock + RESULT_SECONDS, nextAt or 0),
    nextAt = nextAt,
    shownAt = clock,
  }
end

function M.top(lines)
  if result and type(lines) == "table" then result.top = lines end
end

function M.cancelNext()
  if not result then return end
  result.nextAt = nil
  result.untilT = math.min(result.untilT, result.shownAt + RESULT_SECONDS)
end

local function layoutsApi()
  return rawget(_G, "ui_appLayouts") or (extensions and extensions.ui_appLayouts)
end

local function readJson(filename)
  local ok, data = pcall(jsonReadFile, filename)
  return ok and type(data) == "table" and data or nil
end

local function placementEnv()
  local api = layoutsApi()
  if not api or not api.getCurrentLayout or not api.addApp or not api.removeApp
    or not api.setCurrentLayout or not api.getAvailableLayouts then
    return nil
  end
  return {
    api = api,
    appExists = FS:fileExists(HUD_FILES[1]),
    readLayout = function(filename)
      local data = readJson(filename)
      if data then data.filename = filename end
      return data
    end,
    readOriginal = function(filename)
      if type(filename) ~= "string" or filename:sub(1, #USER_LAYOUTS) ~= USER_LAYOUTS then return nil end
      return readJson(ORIGINAL_LAYOUTS .. filename:sub(#USER_LAYOUTS + 1))
    end,
  }
end

local function placementTick()
  local env = placementEnv()
  if not env then placed = false return end
  local ok, isPlaced = pcall(placement.tick, placementState, env)
  placed = ok and isPlaced == true
end

function M.refreshApps()
  local files = {}
  for _, f in ipairs(HUD_FILES) do files[#files + 1] = { filename = f, type = "added" } end
  pcall(extensions.hook, "onFilesChanged", files)
end

function M.start(clock)
  loadedAt = clock
  placement.activate(placementState)
end

function M.leave()
  loadedAt = nil
  placed = false
  local env = placementEnv()
  if env then pcall(placement.leave, placementState, env) end
  placementState.active = false
end

function M.update(clock, info)
  local resultShowing = result and clock < result.untilT
  if (info.active or resultShowing) and clock - lastPush >= PUSH_INTERVAL then
    lastPush = clock
    visibleSent = true
    local timer = info.timer and { label = BANNER_LABELS[info.timer.label] or info.timer.label, endsAt = info.timer.endsAt } or nil
    guihooks.trigger("CnRHud", hud.payload(state, clock, {
      active = info.active, role = info.role, chaseStart = info.chaseStart,
      resetAllowed = info.resetAllowed, resetHint = info.resetHint, penalty = info.penalty, infoText = info.infoText,
      timer = timer, flash = flash, prep = prep, events = events, resetFlashUntil = resetFlashUntil,
      result = result,
    }))
  elseif not info.active and not resultShowing and visibleSent then
    visibleSent = false
    guihooks.trigger("CnRHud", { visible = false })
  end
  local interval = placed and PLACED_INTERVAL or PLACEMENT_INTERVAL
  if loadedAt and clock - loadedAt >= PLACEMENT_DELAY and clock - lastPlacementCheck >= interval then
    lastPlacementCheck = clock
    placementTick()
  end
end

return M
