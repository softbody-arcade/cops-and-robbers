local M = {}

local function ignored(slot)
  return slot:find("paint_design", 1, true) ~= nil
end

local function value(v)
  return type(v) == "string" and v or ""
end

function M.diff(baseline, current)
  local slots, seen = {}, {}
  for _, t in ipairs({ baseline or {}, current or {} }) do
    for slot in pairs(t) do
      if type(slot) == "string" and not seen[slot] and not ignored(slot) then
        seen[slot] = true
        slots[#slots + 1] = slot
      end
    end
  end
  table.sort(slots)
  local list = {}
  for _, slot in ipairs(slots) do
    local from, to = value((baseline or {})[slot]), value((current or {})[slot])
    if from ~= to then list[#list + 1] = { slot = slot, from = from, to = to } end
  end
  return list
end

function M.varsDiff(baseline, current)
  local names, seen = {}, {}
  for _, t in ipairs({ baseline or {}, current or {} }) do
    for name in pairs(t) do
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = tostring(name)
      end
    end
  end
  table.sort(names)
  local list = {}
  for _, name in ipairs(names) do
    local from, to = (baseline or {})[name], (current or {})[name]
    if from ~= to then list[#list + 1] = { name = name, from = from, to = to } end
  end
  return list
end

local function words(text)
  local s = text:gsub("_", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("^%l", string.upper))
end

function M.label(slot, model)
  local text = tostring(slot)
  if model and text:sub(1, #model + 1) == model .. "_" then text = text:sub(#model + 2) end
  return words(text)
end

function M.varLabel(name)
  return words((tostring(name):gsub("^%$", "")))
end

return M
