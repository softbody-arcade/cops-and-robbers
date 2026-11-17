local hud = require("copsAndRobbers/hud")
local apps = require("copsAndRobbers/apps")
local units = require("copsAndRobbers/units")

local M = {}

local PUSH_INTERVAL = 0.1
local APPS_CHECK_INTERVAL = 2
local RESULT_TITLES = { caught = "RUNNER CAUGHT", called = "ROUND ENDED", escaped = "ESCAPED", disconnect = "RUNNER LEFT", cancelled = "ROUND CANCELLED" }
local FLASH_SECONDS, EVENT_SECONDS, RESET_FLASH_SECONDS, RESULT_SECONDS = 2, 4, 1.5, 10

local state = hud.new()
local flash, prep, resetFlashUntil, result, change, applying, releaseAt, heli
local events = {}
local visibleSent = false
local lastPush = 0
local warningKeys, warningTexts = {}, {}
local connected, helpOpen = false, false
local rules, lobby, color, prefs
local sitOut = false
local appsOpen, appsCheckedAt = {}, -math.huge
local lastClock, lastInfo = 0, {}
local lobbyCheck

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
  flash, prep, resetFlashUntil, change, applying, releaseAt, heli = nil, nil, nil, nil, nil, nil, nil
end

function M.heli(h)
  heli = h
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
      if tone == "warn" then e.tone = "warn" end
      return
    end
  end
  events[#events + 1] = { text = text, tone = tone == "warn" and "warn" or "info", untilT = clock + EVENT_SECONDS }
  while #events > 5 do table.remove(events, 1) end
end

function M.prep(role, car, waiting, runner, skyLabel)
  prep = role and { role = role, car = car, waiting = waiting or "go", runner = runner, sky = skyLabel } or nil
end

function M.prepSky(skyLabel)
  if prep then prep.sky = skyLabel end
end

function M.prepWaiting(waiting)
  if prep then prep.waiting = waiting end
end

function M.headStart(untilT)
  releaseAt = untilT
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
  local title = RESULT_TITLES[d.reason] or RESULT_TITLES.cancelled
  local message = cancelled and type(d.message) == "string" and d.message ~= "" and d.message:lower() ~= title:lower() and d.message or nil
  result = {
    title = title,
    runner = (not cancelled and d.runnerName) and tostring(d.runnerName) or nil,
    time = not cancelled and hud.formatTime(d.survivedSeconds) or nil,
    catchers = catchers,
    message = message,
    untilT = math.max(clock + RESULT_SECONDS, nextAt or 0),
    nextAt = nextAt,
    shownAt = clock,
  }
end

function M.top(rows)
  if result and type(rows) == "table" then result.rows = rows end
end

function M.cancelNext()
  if not result then return end
  result.nextAt = nil
  result.untilT = math.min(result.untilT, result.shownAt + RESULT_SECONDS)
end

function M.rules(r)
  rules = type(r) == "table" and r or nil
end

function M.lobby(l)
  lobby = type(l) == "table" and l or nil
end

function M.color(hex)
  color = type(hex) == "string" and hex ~= "" and hex or nil
end

function M.settings(p)
  prefs = p
end

function M.sitOut(on)
  sitOut = on == true
end

function M.help(open)
  helpOpen = open == true
end

function M.onLobbyRefresh(fn)
  lobbyCheck = fn
end

local function hide()
  visibleSent = false
  guihooks.trigger("CnRHud", { visible = false })
end

function M.connect(on)
  local was = connected
  connected = on == true
  if not connected and (was or visibleSent) then hide() end
end

function M.leave()
  events = {}
  warningKeys, warningTexts = {}, {}
  rules, lobby, color, helpOpen, sitOut = nil, nil, nil, false, false
  appsOpen, appsCheckedAt = {}, -math.huge
  lastInfo = {}
end

local function showing(clock, info)
  return connected or info.active or (result ~= nil and clock < result.untilT)
end

local function push(clock, info)
  lastPush = clock
  visibleSent = true
  if helpOpen and apps.dismissed("howto") then
    helpOpen = false
    apps.close("howto")
  end
  if not info.active and clock - appsCheckedAt >= APPS_CHECK_INTERVAL then
    appsCheckedAt = clock
    appsOpen = { panel = apps.isOpen("panel"), board = apps.isOpen("board") }
    if lobbyCheck then lobbyCheck() end
  end
  guihooks.trigger("CnRHud", hud.payload(state, clock, {
    active = info.active, role = info.role, chaseStart = info.chaseStart,
    resetAllowed = info.resetAllowed, resetHint = info.resetHint, penalty = info.penalty, infoParts = info.infoParts, infoSeenAt = info.infoSeenAt, units = units.read(), infoTag = info.infoTag,
    timer = info.timer, flash = flash, prep = prep, events = events, resetFlashUntil = resetFlashUntil,
    change = change, applying = applying, releaseAt = releaseAt, heli = heli,
    result = result, rules = rules, lobby = lobby, color = color, settings = prefs, warnings = M.warnings(), apps = appsOpen, helpOpen = helpOpen,
    spectate = info.spectate, sitOut = sitOut,
  }))
end

function M.pushNow()
  appsCheckedAt = -math.huge
  if showing(lastClock, lastInfo) then push(lastClock, lastInfo) end
end

function M.update(clock, info)
  lastClock, lastInfo = clock, info
  if showing(clock, info) then
    if clock - lastPush >= PUSH_INTERVAL then push(clock, info) end
  elseif visibleSent then
    hide()
  end
  apps.update(clock)
end

return M
