local M = {}

M.GROUNDED = { storm = true, fog = true, snow = true }
M.LOSE_SECONDS = 2

function M.new(cfg, weather, now, random)
  local h = { cfg = cfg, tracking = false, coveredSince = nil, random = random or math.random }
  if weather and M.GROUNDED[weather] then
    h.phase = "grounded"
    h.reason = weather
    return h
  end
  h.phase = "arriving"
  h.phaseEnd = now + cfg.helicopterArrivalSeconds
  return h
end

local function enterUp(h, start, covered)
  h.phase = "up"
  h.seed = h.random(1, 2147483646)
  h.tracking = not covered
  h.coveredSince = nil
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
  if h.phase == "up" then
    s.seed = h.seed
    if h.guided then s.guided = true end
  end
  return s
end

function M.update(h, now, covered, guided)
  if h.phase == "grounded" then return false end
  local before, seedBefore, guidedBefore = phaseName(h), h.seed, h.guided == true
  h.guided = guided == true
  while h.phaseEnd and now >= h.phaseEnd do
    local ended = h.phaseEnd
    if h.phase == "up" then
      h.phase = "refuelling"
      h.tracking = false
      h.coveredSince = nil
      h.phaseEnd = ended + h.cfg.helicopterRefuelSeconds
    else
      enterUp(h, ended, covered)
    end
  end
  if h.phase == "up" then
    if not covered then
      h.tracking = true
      h.coveredSince = nil
    elseif h.tracking then
      h.coveredSince = h.coveredSince or now
      if now - h.coveredSince >= M.LOSE_SECONDS - 1e-9 then
        h.tracking = false
        h.coveredSince = nil
      end
    end
  end
  return phaseName(h) ~= before or h.seed ~= seedBefore or (h.phase == "up" and h.guided ~= guidedBefore)
end

function M.tracking(h)
  return h.phase == "up" and h.tracking
end

function M.flew(h)
  return h.phase ~= "grounded"
end

return M
