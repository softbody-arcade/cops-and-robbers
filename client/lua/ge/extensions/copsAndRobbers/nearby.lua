local M = {}

function M.nearest(points, here, limit)
  local list = {}
  for i, p in ipairs(type(points) == "table" and points or {}) do
    local dx, dy, dz = p.x - here.x, p.y - here.y, (p.z or 0) - (here.z or 0)
    list[#list + 1] = { index = i, meters = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5) }
  end
  table.sort(list, function(a, b)
    if a.meters ~= b.meters then return a.meters < b.meters end
    return a.index < b.index
  end)
  for i = #list, (limit or #list) + 1, -1 do list[i] = nil end
  return list
end

return M
