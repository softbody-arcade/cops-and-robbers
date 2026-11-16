local M = {}

M.KEYS = {
  "runnerCountdownSeconds", "headStartSeconds", "catchHoldSeconds", "catchRadiusMeters", "catchMaxSpeedKmh",
  "resetWaitSeconds", "copResetMinDistanceMeters", "crashSpeedLossKmh", "crashPenaltySeconds",
  "sightMaxMeters", "roundTimeLimitSeconds", "carMode", "trafficPerPlayer", "trafficRunnerOnly",
  "sirensAllowed", "helicopter", "helicopterArrivalSeconds", "helicopterUpSeconds", "helicopterRefuelSeconds",
}

function M.payload(cfg, trafficPerPlayer)
  local p = {}
  for _, k in ipairs(M.KEYS) do p[k] = cfg[k] end
  if trafficPerPlayer ~= nil then p.trafficPerPlayer = trafficPerPlayer end
  return p
end

return M
