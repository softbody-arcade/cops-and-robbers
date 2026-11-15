local M = {}

local function isLightbar(name)
  local n = name:lower()
  return n:find("lightbar", 1, true) ~= nil and not n:find("color", 1, true) and not n:find("pattern", 1, true)
end

function M.choose(candidates)
  local list = {}
  for _, c in ipairs(candidates or {}) do
    if type(c.name) == "string" and isLightbar(c.name) then list[#list + 1] = c end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  local chosen, found = {}, false
  for _, c in ipairs(list) do
    local slots = type(c.slots) == "table" and c.slots or { c.slots }
    for _, slot in ipairs(slots) do
      if type(slot) == "string" and not chosen[slot] then
        chosen[slot] = c.name
        found = true
      end
    end
  end
  return found and chosen or nil
end

function M.apply(parts, chosen)
  local added = false
  for slot, name in pairs(chosen or {}) do
    if parts[slot] == nil or parts[slot] == "" then
      parts[slot] = name
      added = true
    end
  end
  return added
end

return M
