local M = {}

function M.load(decoded)
  local runs = type(decoded) == "table" and type(decoded.runs) == "table" and decoded.runs or {}
  return { runs = runs }
end

function M.add(board, run)
  board.runs[#board.runs + 1] = run
end

function M.best(board, limit)
  limit = limit or 10
  local byPlayer = {}
  for _, r in ipairs(board.runs) do
    if type(r.player) == "string" and type(r.survivedSeconds) == "number" then
      local cur = byPlayer[r.player]
      if not cur or r.survivedSeconds > cur.survivedSeconds then
        byPlayer[r.player] = { player = r.player, survivedSeconds = r.survivedSeconds, map = r.map, model = r.model }
      end
    end
  end
  local list = {}
  for _, entry in pairs(byPlayer) do list[#list + 1] = entry end
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

function M.formatTop(board, limit)
  local best = M.best(board, limit)
  if #best == 0 then return { "No runs yet" } end
  local lines = {}
  for i, e in ipairs(best) do
    lines[i] = string.format("%d. %s %s (%s, %s)", i, e.player, M.formatTime(e.survivedSeconds), tostring(e.model), tostring(e.map))
  end
  return lines
end

return M
