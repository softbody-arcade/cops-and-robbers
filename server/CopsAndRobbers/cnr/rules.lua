local M = {}

M.KEYS = {
  "runnerCountdownSeconds", "headStartSeconds", "catchHoldSeconds", "catchRadiusMeters", "catchMaxSpeedKmh",
  "resetWaitSeconds", "copResetMinDistanceMeters", "crashSpeedLossKmh", "crashPenaltySeconds",
  "sightMaxMeters", "lastSeenIntervalSeconds", "roundTimeLimitSeconds", "carMode", "trafficPerPlayer", "trafficRunnerOnly",
  "sirensAllowed",
}

function M.payload(cfg, trafficPerPlayer)
  local p = {}
  for _, k in ipairs(M.KEYS) do p[k] = cfg[k] end
  if trafficPerPlayer ~= nil then p.trafficPerPlayer = trafficPerPlayer end
  return p
end

return M
