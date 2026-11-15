local M = {}

M.KEYS = {
  "runnerCountdownSeconds", "headStartSeconds", "catchHoldSeconds", "catchRadiusMeters", "catchMaxSpeedKmh",
  "resetWaitSeconds", "copResetMinDistanceMeters", "crashSpeedLossKmh", "crashPenaltySeconds",
  "sightMaxMeters", "lastSeenIntervalSeconds", "roundTimeLimitSeconds", "carMode",
}

function M.payload(cfg)
  local p = {}
  for _, k in ipairs(M.KEYS) do p[k] = cfg[k] end
  return p
end

return M
