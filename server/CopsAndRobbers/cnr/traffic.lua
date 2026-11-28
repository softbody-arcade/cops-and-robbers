local traffic = require("arcade.traffic")
local M = {}

function M.note(setting, maxCars, players, runnerOnly)
  local wanted = traffic.whole(setting)
  if wanted <= 0 then return nil end
  local n = traffic.perPlayer(setting, maxCars, 1)
  if n < wanted then
    if n == 0 then return string.format("MaxCars is %d on this server: no room for traffic", math.floor(tonumber(maxCars))) end
    return string.format("MaxCars is %d on this server: %d %s", math.floor(tonumber(maxCars)), n, runnerOnly and "for the runner" or "per player")
  end
  local count = traffic.whole(players)
  local who = string.format("%d %s", count, count == 1 and "player" or "players")
  if runnerOnly then return string.format("%d cars in all with %s", n, who) end
  return string.format("%d each · %d cars with %s", n, n * count, who)
end

return M
