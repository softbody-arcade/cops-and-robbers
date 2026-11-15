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

function M.payload(state, now, info)
  info = info or {}
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
  }
  local last = state.samples[#state.samples]
  if payload.catch.percent >= 100 and not (last and last.p >= 1) then payload.catch.percent = 99 end
  if info.chaseStart then
    payload.status = {
      role = isRunner and "RUNNER" or "COP",
      time = M.formatTime(now - info.chaseStart),
      reset = resetText(info),
      info = info.infoText,
    }
  end
  return payload
end

return M
