local units = require("copsAndRobbers/units")

local M = {}

local EXTRAPOLATE_MAX = 0.3
local CHANGE_LINES = 4
local COUNTDOWNS = {
  ["Runner starts in"] = { label = "RUNNER STARTS IN", tone = "runner" },
  ["Cops released in"] = { label = "COPS RELEASED IN", tone = "cop" },
  ["Crash penalty"] = { label = "CRASH PENALTY", tone = "warn" },
}
local WAITING_GO = "Waiting for the host to press GO"
local LOBBY_WAITING, LOBBY_RUNNING = "Waiting for the host to start a round", "A round is running"

function M.new()
  return { samples = {} }
end

function M.formatTime(seconds)
  local total = math.floor(seconds or 0)
  return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

function M.catchSample(state, now, progress)
  local s = state.samples
  s[#s + 1] = { t = now, p = progress }
  while #s > 2 do table.remove(s, 1) end
end

function M.catchAt(state, now)
  local s = state.samples
  local last = s[#s]
  if not last then return 0 end
  local value = last.p
  local prev = s[#s - 1]
  if prev and last.t > prev.t then
    local step = last.p - prev.p
    local delta = step / (last.t - prev.t) * math.min(math.max(now - last.t, 0), EXTRAPOLATE_MAX)
    if math.abs(delta) > math.abs(step) then delta = step end
    value = last.p + delta
  end
  return math.max(0, math.min(1, value))
end

local function knownName(name)
  return type(name) == "string" and name ~= "" and name or nil
end

local function waitingText(prep, applying)
  if applying or prep.waiting ~= "change" then return WAITING_GO end
  if prep.role == "runner" then return "Make your change, then press Apply" end
  return string.format("Waiting for %s's change", prep.runner or "the runner")
end

local function resetText(info)
  if info.penalty then return "Penalty" end
  if info.resetAllowed then return "Reset ready" end
  return info.resetHint or ""
end

local function remaining(untilT, now)
  if type(untilT) ~= "number" or untilT <= now then return nil end
  return math.ceil(untilT - now - 1e-9)
end

local function center(info, now)
  local flash = info.flash
  if flash and type(flash.untilT) == "number" and now < flash.untilT then
    return { kind = "flash", text = flash.text }
  end
  if info.applying then return { kind = "applying", text = "APPLYING CHANGES" } end
  local timer = info.timer
  local left = timer and remaining(timer.endsAt, now)
  if left then
    local c = COUNTDOWNS[timer.label] or { label = string.upper(tostring(timer.label)), tone = "warn" }
    return { kind = "countdown", label = c.label, number = left, tone = c.tone }
  end
  local prep = info.prep
  if not prep then return nil end
  local runner = prep.role == "runner"
  local car
  if prep.car and prep.sky then car = prep.car .. " · " .. prep.sky else car = prep.car or prep.sky end
  return {
    kind = "role", role = runner and "runner" or "cop", car = car,
    title = runner and "YOU'RE THE RUNNER" or "YOU'RE A COP",
    runner = not runner and knownName(prep.runner) or nil,
  }
end

local function notices(events, now)
  local list = {}
  for i = #(events or {}), 1, -1 do
    local e = events[i]
    if type(e.untilT) == "number" and now < e.untilT then
      list[#list + 1] = { text = e.text, tone = e.tone == "warn" and "warn" or "info" }
      if #list == 2 then break end
    end
  end
  return list
end

local function catchBlock(state, now, info)
  local p = M.catchAt(state, now)
  local isRunner = info.role == "runner"
  local catch = {
    visible = p > 0,
    percent = math.floor(p * 100 + 1e-9),
    label = isRunner and "BEING CAUGHT" or "HOLDING RUNNER",
    tone = isRunner and "runner" or "cop",
  }
  local last = state.samples[#state.samples]
  if catch.percent >= 100 and not (last and last.p >= 1) then catch.percent = 99 end
  return catch
end

local function changeBlock(change, role)
  local changes = type(change.changes) == "table" and change.changes or {}
  local title = "The runner's change"
  if change.canApply == true or role == "runner" then
    title = "Your change"
  elseif knownName(change.runner) then
    title = change.runner .. "'s change"
  end
  local lines = {}
  for i = 1, math.min(#changes, CHANGE_LINES) do lines[i] = changes[i] end
  return {
    title = title,
    count = #changes,
    lines = lines,
    more = #changes > CHANGE_LINES and (#changes - CHANGE_LINES) or nil,
    canApply = change.canApply == true or nil,
  }
end

local HELI_TEXTS = {
  arriving = "HELICOPTER IN", tracking = "HELICOPTER", searching = "HELICOPTER SEARCHING", refuelling = "HELICOPTER REFUELLING",
}
local HELI_TIMED = { arriving = true, tracking = true, searching = true, refuelling = true }

function M.heliItem(heli, now)
  if type(heli) ~= "table" then return nil end
  local phase = heli.phase
  if phase == "grounded" then
    local reason = type(heli.reason) == "string" and heli.reason ~= "" and (" (" .. heli.reason:upper() .. ")") or ""
    return { text = "HELICOPTER GROUNDED" .. reason }
  end
  local text = HELI_TEXTS[phase]
  if not text then return nil end
  local time
  if HELI_TIMED[phase] and type(heli.endsAt) == "number" then
    time = M.formatTime(math.max(0, math.ceil(heli.endsAt - now - 1e-9)))
  end
  return { text = text, time = time }
end

local function statusBlock(info, now)
  local isRunner = info.role == "runner"
  local status
  if info.chaseStart then
    status = { time = M.formatTime(now - info.chaseStart) }
  elseif isRunner and info.releaseAt then
    status = { time = M.formatTime(0), releaseIn = remaining(info.releaseAt, now) }
  else
    return nil
  end
  local limit = tonumber(type(info.rules) == "table" and info.rules.roundTimeLimitSeconds)
  status.role = isRunner and "runner" or "cop"
  status.limit = limit and limit > 0 and M.formatTime(limit) or nil
  status.reset = resetText(info)
  status.resetFlash = type(info.resetFlashUntil) == "number" and now < info.resetFlashUntil
  local p = info.infoParts
  if type(p) == "table" then
    status.info = { before = p.before, dist = p.meters and units.distance(p.meters, info.units) or nil, after = p.after }
  end
  status.tag = info.infoTag
  status.heli = M.heliItem(info.heli, now)
  return status
end

local function lobbyBlock(info)
  local lobby = type(info.lobby) == "table" and info.lobby or {}
  local status = LOBBY_WAITING
  if type(lobby.practice) == "string" and lobby.practice ~= "" then
    status = "Practice round: " .. lobby.practice
  elseif lobby.active then
    status = LOBBY_RUNNING
  end
  local apps = type(info.apps) == "table" and info.apps or {}
  return {
    online = tonumber(lobby.online) or 1, status = status, color = info.color,
    warnings = info.warnings or {}, apps = { panel = apps.panel == true, board = apps.board == true },
  }
end

local function resultBlock(result, now)
  local rows = {}
  for i, r in ipairs(type(result.rows) == "table" and result.rows or {}) do
    rows[i] = { rank = r.rank, player = r.player, time = r.time, me = r.me == true }
  end
  return {
    title = result.title, runner = result.runner, time = result.time, message = result.message,
    catchers = result.catchers, rows = rows, nextIn = remaining(result.nextAt, now),
  }
end

local function helpBlock(open, rules, unit)
  local help = { open = open == true, units = units.unit(unit) }
  if help.open and type(rules) == "table" then
    local r = {}
    for k, v in pairs(rules) do r[k] = v end
    r.noLimit = not ((tonumber(rules.roundTimeLimitSeconds) or 0) > 0)
    r.sightOff = not ((tonumber(rules.sightMaxMeters) or 0) > 0)
    r.heliOn = rules.helicopter == true
    r.refuelNever = (tonumber(rules.helicopterRefuelSeconds) or 0) <= 0
    r.trafficOn = (tonumber(rules.trafficPerPlayer) or 0) > 0
    help.rules = r
  end
  return help
end

function M.payload(state, now, info)
  info = info or {}
  local result = info.result
  local showResult = result and type(result.untilT) == "number" and now < result.untilT
  local mode = showResult and "result" or (info.active and "round" or "lobby")
  local payload = {
    visible = true,
    mode = mode,
    driving = mode == "round" and info.prep == nil,
    catch = mode == "result" and { visible = false, percent = 0 } or catchBlock(state, now, info),
    notices = notices(info.events, now),
    help = helpBlock(info.helpOpen, info.rules, info.units),
  }
  local prefs = type(info.settings) == "table" and info.settings or {}
  local settings = {
    color = info.color,
    headlights = prefs.headlights == true,
    siren = prefs.siren == true,
    beam = prefs.beam ~= false,
    sound = prefs.sound ~= false,
    route = (prefs.route == "always" or prefs.route == "never") and prefs.route or "sight",
    sirensAllowed = not (type(info.rules) == "table" and info.rules.sirensAllowed == false),
  }
  if mode ~= "result" then payload.settings = settings end
  if mode == "result" then
    payload.result = resultBlock(result, now)
  elseif mode == "lobby" then
    payload.lobby = lobbyBlock(info)
  else
    payload.center = center(info, now)
    if info.prep then payload.prep = { waiting = waitingText(info.prep, info.applying), color = info.color } end
    if type(info.change) == "table" then payload.change = changeBlock(info.change, info.role) end
    payload.status = statusBlock(info, now)
  end
  return payload
end

return M
