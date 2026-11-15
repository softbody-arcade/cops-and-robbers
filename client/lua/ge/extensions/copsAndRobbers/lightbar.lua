local M = {}

local MAX_DEFAULT_DEPTH = 4

local function isMain(n, word)
  return n:find(word, 1, true) ~= nil and not n:find("color", 1, true) and not n:find("pattern", 1, true)
    and not n:find("bulb", 1, true)
end

function M.isMainLight(name)
  if type(name) ~= "string" then return false end
  local n = name:lower()
  return isMain(n, "lightbar") or isMain(n, "beacon")
end

local function emergencyElectric(e)
  local n = e:lower()
  return n:find("lightbar", 1, true) or n:find("beacon", 1, true) or n:find("flash", 1, true)
    or n:find("siren", 1, true) or e:match("^[LR]%d+_%a") ~= nil
end

local function hasEmergencyElectric(t, seen)
  if seen[t] then return false end
  seen[t] = true
  for k, v in pairs(t) do
    if (k == "$electric" or k == "electric") and type(v) == "string" then
      if emergencyElectric(v) then return true end
    elseif type(v) == "table" and hasEmergencyElectric(v, seen) then
      return true
    end
  end
  return false
end

function M.isEmergency(name, getPart, depth, seenParts)
  depth, seenParts = depth or 0, seenParts or {}
  if type(name) ~= "string" or depth > MAX_DEFAULT_DEPTH or seenParts[name] then return false end
  seenParts[name] = true
  local part = getPart(name)
  if type(part) ~= "table" then return false end
  if hasEmergencyElectric(part, {}) then return true end
  for _, s in ipairs(type(part.slots2) == "table" and part.slots2 or {}) do
    if type(s) == "table" and type(s.default) == "string" and s.default ~= ""
      and M.isEmergency(s.default, getPart, depth + 1, seenParts) then
      return true
    end
  end
  return false
end

local function rankKey(name)
  local n = name:lower()
  return (n:find("lightbar", 1, true) and 0 or 2) + (n:find("police", 1, true) and 0 or 1), n
end

local function better(a, b)
  local ka, na = rankKey(a)
  local kb, nb = rankKey(b)
  if ka ~= kb then return ka < kb end
  return na < nb
end

function M.plan(mainPart, parts, env)
  parts = type(parts) == "table" and parts or {}
  local cache = {}
  local function emergency(name)
    if cache[name] == nil then cache[name] = M.isMainLight(name) and M.isEmergency(name, env.getPart) end
    return cache[name]
  end
  local additions, seen, stack = {}, {}, { mainPart }
  while #stack > 0 do
    local name = table.remove(stack)
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      if emergency(name) then return nil end
      local part = env.getPart(name)
      local slots = type(part) == "table" and type(part.slots2) == "table" and part.slots2 or {}
      for _, s in ipairs(slots) do
        if type(s) == "table" and type(s.name) == "string" then
          local chosen = parts[s.name]
          if chosen == nil then chosen = s.default end
          if type(chosen) == "string" and chosen ~= "" then
            stack[#stack + 1] = chosen
          else
            local lights = {}
            for _, c in ipairs(env.compatible(s) or {}) do
              if emergency(c) then lights[#lights + 1] = c end
            end
            if #lights > 0 then
              table.sort(lights, better)
              additions[s.name] = lights[1]
            end
          end
        end
      end
    end
  end
  return next(additions) and additions or nil
end

return M
