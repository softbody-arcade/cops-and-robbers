local M = {}

local function whole(v)
  local n = tonumber(v) or 0
  return math.max(0, math.floor(n))
end

function M.perPlayer(setting, maxCars, geo, practice)
  if geo then return 0 end
  local n = whole(setting)
  local cars = tonumber(maxCars)
  if cars then n = math.min(n, math.max(0, math.floor(cars) - (practice and 3 or 1))) end
  return n
end

function M.note(setting, maxCars, geo, players)
  local wanted = whole(setting)
  if wanted <= 0 or geo then return nil end
  local n = M.perPlayer(setting, maxCars, false, false)
  if n < wanted then
    if n == 0 then return string.format("MaxCars is %d on this server: no room for traffic", math.floor(tonumber(maxCars))) end
    return string.format("MaxCars is %d on this server: %d per player", math.floor(tonumber(maxCars)), n)
  end
  local count = whole(players)
  return string.format("%d each · %d cars with %d %s", n, n * count, count, count == 1 and "player" or "players")
end

return M
