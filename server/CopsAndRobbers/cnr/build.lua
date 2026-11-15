local M = {}

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end

local function isStringMap(t)
  if type(t) ~= "table" then return false end
  for k, v in pairs(t) do
    if type(k) ~= "string" or type(v) ~= "string" then return false end
  end
  return true
end

local function same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function M.new(model, name, parts, vars, startedFrom, now)
  return {
    model = model, name = name or model, parts = copy(parts), vars = copy(vars or {}),
    step = 0, startedFrom = startedFrom, startedAt = now, history = {},
  }
end

function M.normalize(t)
  if type(t) ~= "table" or type(t.model) ~= "string" or t.model == "" or not isStringMap(t.parts) then return nil end
  local b = copy(t)
  b.name = type(b.name) == "string" and b.name or b.model
  b.vars = type(b.vars) == "table" and b.vars or {}
  b.history = type(b.history) == "table" and b.history or {}
  b.step = tonumber(b.step) or 0
  return b
end

function M.apply(b, setup, changes, by, now)
  local parts, vars = setup.parts or {}, setup.vars or {}
  if same(b.parts, parts) and same(b.vars or {}, vars) then return b, false end
  local nb = copy(b)
  nb.parts, nb.vars = copy(parts), copy(vars)
  nb.step = (b.step or 0) + 1
  nb.history[#nb.history + 1] = { step = nb.step, by = by, at = now, changes = copy(changes or {}) }
  return nb, true
end

function M.label(b)
  return string.format("%s · change %d", b.name or b.model, b.step or 0)
end

function M.changeLine(step, by, changes)
  local first = changes and changes[1]
  local head = first and string.format("%s %s → %s", tostring(first.label), tostring(first.from), tostring(first.to)) or "no change"
  local parts = first and tonumber(first.extra) and first.extra > 0 and string.format(" (+%d parts)", first.extra) or ""
  local others = changes and #changes - 1 or 0
  local more = others > 0 and string.format(" and %d more change%s", others, others == 1 and "" or "s") or ""
  return string.format("Change %d by %s: %s%s%s", step, tostring(by), head, parts, more)
end

return M
