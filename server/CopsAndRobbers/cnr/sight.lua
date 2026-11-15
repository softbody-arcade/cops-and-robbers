local M = {}

function M.new()
  return { seen = {}, lostAt = {} }
end

function M.report(state, pid, seen, now)
  if seen then
    state.seen[pid] = true
    state.lostAt[pid] = nil
  elseif state.seen[pid] then
    state.seen[pid] = nil
    state.lostAt[pid] = now
  end
end

function M.forget(state, pid)
  state.seen[pid] = nil
  state.lostAt[pid] = nil
end

function M.sees(state, pid, now, grace)
  if state.seen[pid] then return true end
  local lost = state.lostAt[pid]
  return lost ~= nil and now - lost < grace - 1e-9
end

function M.any(state, pids, now, grace)
  for _, pid in ipairs(pids) do
    if M.sees(state, pid, now, grace) then return true end
  end
  return false
end

function M.noRouteDistance(speedMs, seconds, minMeters)
  return math.max(minMeters, speedMs * seconds)
end

return M
