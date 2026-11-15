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

local function same(a, b, step)
  if type(a) == "number" and type(b) == "number" then
    return math.abs(a - b) <= math.max(1e-6, (tonumber(step) or 0) / 2)
  end
  return a == b
end

function M.varsDiff(baseline, current, steps)
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
    if not same(from, to, (steps or {})[name]) then list[#list + 1] = { name = name, from = from, to = to } end
  end
  return list
end

function M.group(changes, slotsOf)
  local parent = {}
  for i, c in ipairs(changes) do
    for j, p in ipairs(changes) do
      if i ~= j then
        local a, b = slotsOf(p.from), slotsOf(p.to)
        if (type(a) == "table" and a[c.slot] ~= nil) or (type(b) == "table" and b[c.slot] ~= nil) then
          parent[i] = j
          break
        end
      end
    end
  end
  local function root(i)
    local start, seen = i, {}
    while parent[i] do
      if seen[i] then return start end
      seen[i] = true
      i = parent[i]
    end
    return i
  end
  local extra, roots, byRoot = {}, {}, {}
  for i in ipairs(changes) do
    local r = root(i)
    if r ~= i then extra[r] = (extra[r] or 0) + 1 end
  end
  for i, c in ipairs(changes) do
    if root(i) == i then
      local entry = { slot = c.slot, from = c.from, to = c.to, extra = extra[i] or 0, parts = {} }
      if c.to ~= "" then entry.parts[1] = c.to end
      roots[#roots + 1] = entry
      byRoot[i] = entry
    end
  end
  for i, c in ipairs(changes) do
    local entry = byRoot[root(i)]
    if root(i) ~= i and entry and c.to ~= "" then entry.parts[#entry.parts + 1] = c.to end
  end
  return roots
end

function M.formatValue(v)
  if type(v) ~= "number" then return v == nil and "(default)" or tostring(v) end
  return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function words(text)
  local s = text:gsub("_", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("^%l", string.upper))
end

function M.label(slot, model)
  local text = tostring(slot)
  if text:sub(1, 1) == "/" then
    local last
    for segment in text:gmatch("[^/]+") do last = segment end
    text = last or text
  end
  if model and text:sub(1, #model + 1) == model .. "_" then text = text:sub(#model + 2) end
  return words(text)
end

function M.varLabel(name)
  return words((tostring(name):gsub("^%$", "")))
end

return M
