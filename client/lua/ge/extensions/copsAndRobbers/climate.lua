local M = {}

local LOW = { 0, 1, 4, 8, 12, 17, 20, 19, 15, 10, 5, 1 }
local HIGH = { 8, 10, 14, 18, 23, 28, 31, 30, 26, 20, 13, 9 }
local OFFSET = {
  clear = { 0, 0 },
  cloudy = { 2, -3 },
  rain = { 2, -5 },
  storm = { 1, -7 },
  fog = { 0, -6 },
}

function M.range(weather, month)
  if type(weather) ~= "string" or not LOW[month] then return nil end
  local low, high = LOW[month], HIGH[month]
  if weather == "snow" then
    high = math.min(high - 9, 0)
    low = math.min(low, high - 4)
    return low, high
  end
  local offset = OFFSET[weather]
  if not offset then return nil end
  low, high = low + offset[1], high + offset[2]
  if high < low + 2 then high = low + 2 end
  return low, high
end

return M
