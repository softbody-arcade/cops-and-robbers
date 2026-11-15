local M = {}

function M.load(decoded)
  local runs = type(decoded) == "table" and type(decoded.runs) == "table" and decoded.runs or {}
  return { runs = runs }
end

function M.add(board, run)
  board.runs[#board.runs + 1] = run
end

function M.validShape(decoded)
  if decoded == nil then return true end
  return type(decoded) == "table" and type(decoded.runs) == "table"
end

function M.best(board, limit, map)
  limit = limit or 10
  local byKey = {}
  for _, r in ipairs(board.runs) do
    if type(r) == "table" and type(r.player) == "string" and type(r.survivedSeconds) == "number"
      and (map == nil or r.map == map) then
      local key = type(r.key) == "string" and r.key or r.player
      local cur = byKey[key]
      local at = tonumber(r.endedAt) or 0
      if not cur then
        cur = { player = r.player, survivedSeconds = r.survivedSeconds, map = r.map, model = r.model, nameAt = at }
        byKey[key] = cur
      elseif r.survivedSeconds > cur.survivedSeconds then
        cur.survivedSeconds, cur.map, cur.model = r.survivedSeconds, r.map, r.model
      end
      if at >= cur.nameAt then cur.player, cur.nameAt = r.player, at end
    end
  end
  local list = {}
  for _, entry in pairs(byKey) do
    entry.nameAt = nil
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b)
    if a.survivedSeconds ~= b.survivedSeconds then return a.survivedSeconds > b.survivedSeconds end
    return a.player < b.player
  end)
  while #list > limit do table.remove(list) end
  return list
end

function M.formatTime(seconds)
  local total = math.floor(seconds)
  return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

function M.formatTop(board, limit, map)
  local best = M.best(board, limit, map)
  if #best == 0 then return { "No runs yet" } end
  local lines = {}
  for i, e in ipairs(best) do
    lines[i] = string.format("%d. %s %s (%s, %s)", i, e.player, M.formatTime(e.survivedSeconds), tostring(e.model), tostring(e.map))
  end
  return lines
end

function M.formatTopCops(board, limit)
  limit = limit or 10
  local stats = {}
  for _, r in ipairs(board.runs) do
    if type(r) == "table" and r.endReason == "caught" and type(r.catchers) == "table" and type(r.survivedSeconds) == "number" then
      local keys = type(r.catcherKeys) == "table" and r.catcherKeys or {}
      local at = tonumber(r.endedAt) or 0
      for i, name in ipairs(r.catchers) do
        if type(name) == "string" then
          local key = type(keys[i]) == "string" and keys[i] or name
          local s = stats[key] or { name = name, catches = 0, fastest = math.huge, nameAt = at }
          s.catches = s.catches + 1
          s.fastest = math.min(s.fastest, r.survivedSeconds)
          if at >= s.nameAt then s.name, s.nameAt = name, at end
          stats[key] = s
        end
      end
    end
  end
  local list = {}
  for _, s in pairs(stats) do list[#list + 1] = s end
  if #list == 0 then return { "No catches yet" } end
  table.sort(list, function(a, b)
    if a.catches ~= b.catches then return a.catches > b.catches end
    if a.fastest ~= b.fastest then return a.fastest < b.fastest end
    return a.name < b.name
  end)
  local lines = {}
  for i, s in ipairs(list) do
    if i > limit then break end
    lines[i] = string.format("%d. %s %d %s, fastest %s", i, s.name, s.catches, s.catches == 1 and "catch" or "catches", M.formatTime(s.fastest))
  end
  return lines
end

return M
