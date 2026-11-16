local M = {}

M.GROUNDED = { storm = true, fog = true, snow = true }
M.REFIND_SECONDS = 5
M.RAIN_REFIND_SECONDS = 10

function M.new(cfg, weather, now)
  local h = { cfg = cfg, tracking = false, openSince = nil }
  if weather and M.GROUNDED[weather] then
    h.phase = "grounded"
    h.reason = weather
    return h
  end
  h.refind = weather == "rain" and M.RAIN_REFIND_SECONDS or M.REFIND_SECONDS
  h.phase = "arriving"
  h.phaseEnd = now + cfg.helicopterArrivalSeconds
  return h
end

local function enterUp(h, start, covered)
  h.phase = "up"
  h.tracking = not covered
  h.openSince = nil
  if h.cfg.helicopterRefuelSeconds > 0 then
    h.phaseEnd = start + h.cfg.helicopterUpSeconds
  else
    h.phaseEnd = nil
  end
end

local function phaseName(h)
  if h.phase == "up" then return h.tracking and "tracking" or "searching" end
  return h.phase
end

function M.status(h, now)
  local s = { phase = phaseName(h) }
  if h.phase == "grounded" then
    s.reason = h.reason
  elseif h.phaseEnd then
    s.seconds = math.max(0, h.phaseEnd - now)
  end
  return s
end

function M.update(h, now, covered)
  if h.phase == "grounded" then return false end
  local before = phaseName(h)
  while h.phaseEnd and now >= h.phaseEnd do
    local ended = h.phaseEnd
    if h.phase == "up" then
      h.phase = "refuelling"
      h.tracking = false
      h.openSince = nil
      h.phaseEnd = ended + h.cfg.helicopterRefuelSeconds
    else
      enterUp(h, ended, covered)
    end
  end
  if h.phase == "up" then
    if h.tracking then
      if covered then
        h.tracking = false
        h.openSince = nil
      end
    elseif covered then
      h.openSince = nil
    else
      h.openSince = h.openSince or now
      if now - h.openSince >= h.refind then
        h.tracking = true
        h.openSince = nil
      end
    end
  end
  return phaseName(h) ~= before
end

function M.tracking(h)
  return h.phase == "up" and h.tracking
end

function M.flew(h)
  return h.phase ~= "grounded"
end

return M
