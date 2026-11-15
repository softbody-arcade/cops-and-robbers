package.path = "client/lua/ge/extensions/?.lua;" .. package.path
local function decodeJson(str)
  local pos = 1
  local function ws() pos = str:find("%S", pos) or #str + 1 end
  local value
  local function stringValue()
    local out = {}
    pos = pos + 1
    while true do
      local c = str:sub(pos, pos)
      if c == "" then error("bad json") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then pos = pos + 1; c = str:sub(pos, pos) end
      out[#out + 1] = c
      pos = pos + 1
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = str:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1; ws()
      if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        ws()
        if str:sub(pos, pos) ~= '"' then error("bad json") end
        local k = stringValue()
        ws()
        if str:sub(pos, pos) ~= ":" then error("bad json") end
        pos = pos + 1
        t[k] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then error("bad json") end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1; ws()
      if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
        if d ~= "," then error("bad json") end
      end
    elseif c == '"' then
      return stringValue()
    elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("bad json") end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local v = value()
  ws()
  if pos <= #str then error("bad json") end
  return v
end
local lightbar = require("copsAndRobbers/lightbar")

local dir = arg[1] or ".lightcheck"
local models = {}
for i = 2, #arg do models[#models + 1] = arg[i] end
if #models == 0 then
  for name in io.popen('ls "' .. dir .. '"'):lines() do models[#models + 1] = name:match("^(.*)%.json$") end
end

for _, model in ipairs(models) do
  local f = io.open(dir .. "/" .. model .. ".json")
  if f then
    local data = decodeJson(f:read("*a"))
    f:close()
    local parts, byType = data.parts, {}
    for name, d in pairs(parts) do
      local st = d.slotType
      for _, t in ipairs(type(st) == "table" and st or { st }) do
        if type(t) == "string" then byType[t] = byType[t] or {}; table.insert(byType[t], name) end
      end
    end
    local env = {
      getPart = function(n) return parts[n] end,
      compatible = function(s)
        local out, seen, deny = {}, {}, {}
        for _, d in ipairs(s.denyTypes or {}) do deny[d] = true end
        for _, t in ipairs(s.allowTypes or {}) do
          for _, n in ipairs(byType[t] or {}) do
            local st, ok = parts[n].slotType, true
            for _, x in ipairs(type(st) == "table" and st or { st }) do if deny[x] then ok = false end end
            if ok and not seen[n] then seen[n] = true; out[#out + 1] = n end
          end
        end
        return out
      end,
    }
    local names, counts, none = {}, {}, {}
    for k in pairs(data.configs) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
      local c = data.configs[k]
      local add = lightbar.plan(c.main, c.parts, env)
      if add then
        for slot, p in pairs(add) do counts[slot .. "=" .. p] = (counts[slot .. "=" .. p] or 0) + 1 end
      else
        none[#none + 1] = k
      end
    end
    local list = {}
    for k, v in pairs(counts) do list[#list + 1] = k .. " x" .. v end
    table.sort(list)
    print(string.format("%s: %d configs | adds: %s | nothing added: %s", model, #names, table.concat(list, ", "), table.concat(none, ", ")))
  end
end
