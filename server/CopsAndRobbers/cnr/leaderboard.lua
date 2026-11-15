local M = {}

M.FORMAT = 2

function M.load(decoded)
  local runs = type(decoded) == "table" and type(decoded.runs) == "table" and decoded.runs or {}
  return { format = M.FORMAT, runs = runs }
end

function M.isCurrent(decoded)
  return decoded == nil or (type(decoded) == "table" and decoded.format == M.FORMAT)
end

function M.add(board, run)
  board.runs[#board.runs + 1] = run
end

function M.validShape(decoded)
  if decoded == nil then return true end
  return type(decoded) == "table" and type(decoded.runs) == "table"
end

local function matches(r, filter)
  local map, mode = filter, nil
  if type(filter) == "table" then map, mode = filter.map, filter.mode end
  if map ~= nil and r.map ~= map then return false end
  if mode ~= nil and (r.mode or "random") ~= mode then return false end
  return true
end

function M.best(board, limit, map)
  limit = limit or 10
  local byKey = {}
  for _, r in ipairs(board.runs) do
    if type(r) == "table" and type(r.player) == "string" and type(r.survivedSeconds) == "number"
      and matches(r, map) then
      local key = type(r.key) == "string" and r.key or r.player
      local cur = byKey[key]
      local at = tonumber(r.endedAt) or 0
      if not cur then
        cur = { key = key, player = r.player, survivedSeconds = r.survivedSeconds, map = r.map, model = r.model, nameAt = at }
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

local function validRun(r, filter)
  return type(r) == "table" and type(r.survivedSeconds) == "number" and matches(r, filter)
end

local function catcherList(r)
  local list = {}
  if r.endReason ~= "caught" or type(r.catchers) ~= "table" then return list end
  local keys = type(r.catcherKeys) == "table" and r.catcherKeys or {}
  for i, name in ipairs(r.catchers) do
    if type(name) == "string" then list[#list + 1] = { key = type(keys[i]) == "string" and keys[i] or name, name = name } end
  end
  return list
end

local function copList(r)
  local list = {}
  local names = type(r.copNames) == "table" and r.copNames or {}
  local sight = type(r.copSightSeconds) == "table" and r.copSightSeconds or {}
  for i, key in ipairs(type(r.cops) == "table" and r.cops or {}) do
    if type(key) == "string" then
      list[#list + 1] = { key = key, name = type(names[i]) == "string" and names[i] or key, sight = tonumber(sight[i]) or 0 }
    end
  end
  return list
end

local function runnerKey(r)
  return type(r.key) == "string" and r.key or r.player
end

local function latestNames(board)
  local names, at = {}, {}
  local function note(key, name, t)
    if type(key) == "string" and type(name) == "string" and (not at[key] or t >= at[key]) then names[key], at[key] = name, t end
  end
  for _, r in ipairs(board.runs) do
    if validRun(r) then
      local t = tonumber(r.endedAt) or 0
      if type(r.player) == "string" then note(runnerKey(r), r.player, t) end
      for _, c in ipairs(catcherList(r)) do note(c.key, c.name, t) end
      for _, c in ipairs(copList(r)) do note(c.key, c.name, t) end
    end
  end
  return names
end

function M.runners(board, map, limit)
  local names = latestNames(board)
  local list = M.best(board, limit, map)
  for _, e in ipairs(list) do e.player = names[e.key] or e.player end
  return list
end

function M.maps(board)
  local seen, list = {}, {}
  for _, r in ipairs(board.runs) do
    if validRun(r) and type(r.map) == "string" and not seen[r.map] then
      seen[r.map] = true
      list[#list + 1] = r.map
    end
  end
  table.sort(list)
  return list
end

function M.cops(board, map, limit)
  local byKey, list = {}, {}
  for _, r in ipairs(board.runs) do
    if validRun(r, map) then
      local at = tonumber(r.endedAt) or 0
      for _, c in ipairs(catcherList(r)) do
        local s = byKey[c.key]
        if not s then
          s = { key = c.key, name = c.name, catches = 0, fastest = math.huge, nameAt = at }
          byKey[c.key] = s
          list[#list + 1] = s
        end
        s.catches = s.catches + 1
        s.fastest = math.min(s.fastest, r.survivedSeconds)
        if at >= s.nameAt then s.name, s.nameAt = c.name, at end
      end
    end
  end
  local names = latestNames(board)
  for _, s in ipairs(list) do s.name = names[s.key] or s.name end
  table.sort(list, function(a, b)
    if a.catches ~= b.catches then return a.catches > b.catches end
    if a.fastest ~= b.fastest then return a.fastest < b.fastest end
    return a.name < b.name
  end)
  for _, s in ipairs(list) do s.nameAt, s.key = nil, nil end
  while limit and #list > limit do table.remove(list) end
  return list
end

function M.players(board, map, assistPercent)
  assistPercent = tonumber(assistPercent) or 20
  local byKey, list = {}, {}
  local function entry(key, name, at)
    local p = byKey[key]
    if not p then
      p = { key = key, name = name, nameAt = at, runs = 0, total = 0, escapes = 0, catches = 0, assists = 0 }
      byKey[key] = p
      list[#list + 1] = p
    elseif at >= p.nameAt then
      p.name, p.nameAt = name, at
    end
    return p
  end
  for _, r in ipairs(board.runs) do
    if validRun(r, map) and type(r.player) == "string" then
      local at = tonumber(r.endedAt) or 0
      local runner = entry(type(r.key) == "string" and r.key or r.player, r.player, at)
      runner.runs = runner.runs + 1
      runner.total = runner.total + r.survivedSeconds
      runner.best = math.max(runner.best or 0, r.survivedSeconds)
      if r.endReason == "escaped" then runner.escapes = runner.escapes + 1 end
      if type(r.hiddenSeconds) == "number" then
        runner.hiddenSum = (runner.hiddenSum or 0) + r.hiddenSeconds
        runner.chaseSum = (runner.chaseSum or 0) + (tonumber(r.chaseSeconds) or r.survivedSeconds)
      end
      if type(r.lostCount) == "number" then runner.lostThem = (runner.lostThem or 0) + r.lostCount end
      local catchers = {}
      for _, c in ipairs(catcherList(r)) do
        catchers[c.key] = true
        local p = entry(c.key, c.name, at)
        p.catches = p.catches + 1
      end
      local chase = tonumber(r.chaseSeconds) or r.survivedSeconds
      for _, c in ipairs(copList(r)) do
        local p = entry(c.key, c.name, at)
        if r.endReason == "caught" and not catchers[c.key] and chase > 0 and c.sight / chase * 100 >= assistPercent - 1e-9 then
          p.assists = p.assists + 1
        end
      end
    end
  end
  local names = latestNames(board)
  for _, p in ipairs(list) do
    p.name = names[p.key] or p.name
    p.average = p.runs > 0 and p.total / p.runs or nil
    p.hiddenPct = p.chaseSum and p.chaseSum > 0 and p.hiddenSum / p.chaseSum * 100 or nil
    p.total, p.hiddenSum, p.chaseSum, p.nameAt = nil, nil, nil, nil
  end
  table.sort(list, function(a, b)
    if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
    return a.key < b.key
  end)
  return list
end

function M.formatTime(seconds)
  local total = math.floor(seconds)
  return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

function M.formatTop(board, limit, map)
  local best = M.runners(board, map, limit)
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
