local hud = require("copsAndRobbers/hud")
local apps = require("copsAndRobbers/apps")

local M = {}

local PUSH_INTERVAL = 0.1
local BANNER_LABELS = { ["Runner starts in"] = "RUNNER STARTS IN", ["Cops released in"] = "COPS RELEASED IN", ["Crash penalty"] = "CRASH PENALTY" }
local RESULT_TITLES = { caught = "RUNNER CAUGHT", called = "ROUND ENDED", escaped = "ESCAPED", disconnect = "RUNNER LEFT", cancelled = "ROUND CANCELLED" }
local FLASH_SECONDS, EVENT_SECONDS, RESET_FLASH_SECONDS, RESULT_SECONDS = 2, 4, 1.5, 10

local state = hud.new()
local flash, prep, resetFlashUntil, result, change, applying
local events = {}
local visibleSent = false
local lastPush = 0
local warningKeys, warningTexts = {}, {}

function M.warning(key, text)
  if text == nil then
    warningTexts[key] = nil
    for i, k in ipairs(warningKeys) do
      if k == key then table.remove(warningKeys, i) break end
    end
  else
    if warningTexts[key] == nil then warningKeys[#warningKeys + 1] = key end
    warningTexts[key] = text
  end
end

function M.warnings()
  local list = {}
  for _, k in ipairs(warningKeys) do list[#list + 1] = warningTexts[k] end
  return list
end

function M.clearRound()
  state = hud.new()
  flash, prep, resetFlashUntil, change, applying = nil, nil, nil, nil, nil
  events = {}
end

function M.queued(runner, changes, canApply)
  change = runner and { runner = runner, changes = changes or {}, canApply = canApply } or nil
end

function M.applying(on)
  applying = on and true or nil
  if on then change = nil end
end

function M.clearResult()
  result = nil
end

function M.flash(text, clock)
  flash = { text = text, untilT = clock + FLASH_SECONDS }
end

function M.event(text, clock, tone)
  for _, e in ipairs(events) do
    if e.text == text and clock < e.untilT then
      e.untilT = clock + EVENT_SECONDS
      return
    end
  end
  events[#events + 1] = { text = text, tone = tone == "warn" and "warn" or "info", untilT = clock + EVENT_SECONDS }
  while #events > 5 do table.remove(events, 1) end
end

function M.prep(role, car, waiting)
  prep = role and { role = role, car = car, waiting = waiting or "waiting for GO" } or nil
end

function M.prepWaiting(text)
  if prep then prep.waiting = text end
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

function M.leave()
  warningKeys, warningTexts = {}, {}
end

function M.update(clock, info)
  local resultShowing = result and clock < result.untilT
  if (info.active or resultShowing) and clock - lastPush >= PUSH_INTERVAL then
    lastPush = clock
    visibleSent = true
    local timer = info.timer and { label = BANNER_LABELS[info.timer.label] or info.timer.label, endsAt = info.timer.endsAt } or nil
    guihooks.trigger("CnRHud", hud.payload(state, clock, {
      active = info.active, role = info.role, chaseStart = info.chaseStart,
      resetAllowed = info.resetAllowed, resetHint = info.resetHint, penalty = info.penalty, infoText = info.infoText, infoTag = info.infoTag,
      timer = timer, flash = flash, prep = prep, events = events, resetFlashUntil = resetFlashUntil,
      change = change, applying = applying,
      result = result,
    }))
  elseif not info.active and not resultShowing and visibleSent then
    visibleSent = false
    guihooks.trigger("CnRHud", { visible = false })
  end
  apps.update(clock)
end

return M
