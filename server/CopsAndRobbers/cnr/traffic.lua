local M = {}

local function whole(v)
  local n = tonumber(v) or 0
  return math.max(0, math.floor(n))
end

function M.perPlayer(setting, maxCars, practice)
  local n = whole(setting)
  local cars = tonumber(maxCars)
  if cars then n = math.min(n, math.max(0, math.floor(cars) - (practice and 3 or 1))) end
  return n
end

function M.note(setting, maxCars, players, runnerOnly)
  local wanted = whole(setting)
  if wanted <= 0 then return nil end
  local n = M.perPlayer(setting, maxCars, false)
  if n < wanted then
    if n == 0 then return string.format("MaxCars is %d on this server: no room for traffic", math.floor(tonumber(maxCars))) end
    return string.format("MaxCars is %d on this server: %d %s", math.floor(tonumber(maxCars)), n, runnerOnly and "for the runner" or "per player")
  end
  local count = whole(players)
  local who = string.format("%d %s", count, count == 1 and "player" or "players")
  if runnerOnly then return string.format("%d cars in all with %s", n, who) end
  return string.format("%d each · %d cars with %s", n, n * count, who)
end

return M
