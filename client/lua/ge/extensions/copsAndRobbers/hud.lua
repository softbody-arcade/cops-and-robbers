local M = {}

local EXTRAPOLATE_MAX = 0.3

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

local function resetText(info)
  if info.penalty then return "Penalty" end
  if info.resetAllowed then return "Reset OK" end
  return info.resetHint or ""
end

local function remaining(untilT, now)
  if type(untilT) ~= "number" or untilT <= now then return nil end
  return math.ceil(untilT - now - 1e-9)
end

local CHANGE_LINES = 4

local function banner(info, now)
  local flash = info.flash
  if flash and type(flash.untilT) == "number" and now < flash.untilT then
    return { label = flash.text, big = true }
  end
  if info.applying then return { label = "APPLYING CHANGES", big = true } end
  local timer = info.timer
  local left = timer and remaining(timer.endsAt, now)
  if left then return { label = timer.label, number = left, big = true } end
  return nil
end

local function activeEvents(events, now)
  local list = {}
  for i = #(events or {}), 1, -1 do
    local e = events[i]
    if type(e.untilT) == "number" and now < e.untilT then
      list[#list + 1] = e.text
      if #list == 2 then break end
    end
  end
  return list
end

function M.payload(state, now, info)
  info = info or {}
  local result = info.result
  if result and type(result.untilT) == "number" and now < result.untilT then
    return {
      visible = true,
      catch = { visible = false, percent = 0 },
      result = {
        title = result.title, runner = result.runner, time = result.time,
        catchers = result.catchers, top = result.top, nextIn = remaining(result.nextAt, now),
      },
    }
  end
  local p = M.catchAt(state, now)
  local isRunner = info.role == "runner"
  local payload = {
    visible = info.active == true,
    catch = {
      visible = p > 0,
      percent = math.floor(p * 100 + 1e-9),
      label = isRunner and "BEING CAUGHT" or "HOLDING RUNNER",
      tone = isRunner and "runner" or "cop",
    },
    banner = banner(info, now),
    events = activeEvents(info.events, now),
  }
  local last = state.samples[#state.samples]
  if payload.catch.percent >= 100 and not (last and last.p >= 1) then payload.catch.percent = 99 end
  if type(info.change) == "table" then
    local changes = type(info.change.changes) == "table" and info.change.changes or {}
    local who = string.upper(tostring(info.change.runner or "RUNNER")) .. "'S CHANGE"
    local lines = {}
    for i = 1, math.min(#changes, CHANGE_LINES) do lines[i] = changes[i] end
    payload.change = {
      title = #changes == 0 and (who .. ": none yet") or string.format("%s (%d)", who, #changes),
      lines = lines,
      more = #changes > CHANGE_LINES and (#changes - CHANGE_LINES) or nil,
      canApply = info.change.canApply == true or nil,
    }
  elseif info.prep then
    payload.prep = { role = info.prep.role == "runner" and "RUNNER" or "COP", car = info.prep.car }
  end
  if info.chaseStart then
    payload.status = {
      role = isRunner and "RUNNER" or "COP",
      time = M.formatTime(now - info.chaseStart),
      reset = resetText(info),
      resetFlash = type(info.resetFlashUntil) == "number" and now < info.resetFlashUntil,
      info = info.infoText,
      tag = info.infoTag,
    }
  end
  return payload
end

return M
