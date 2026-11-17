local M = {}

function M.parse(msg)
  if type(msg) ~= "string" then return nil end
  local trimmed = msg:match("^%s*(.-)%s*$")
  local prefix, tail = trimmed:match("^(%S+)%s*(.*)$")
  if not prefix or prefix:lower() ~= "/cnr" then return nil end
  local args = {}
  for word in tail:gmatch("%S+") do args[#args + 1] = word end
  if #args == 0 then return { name = "help", args = {}, rest = "" } end
  local name = table.remove(args, 1):lower()
  local rest = tail:match("^%S+%s*(.*)$") or ""
  return { name = name, args = args, rest = rest }
end

function M.eligibleNext(players, runCounts, lastName)
  local pids = {}
  for pid in pairs(players) do pids[#pids + 1] = pid end
  table.sort(pids)
  local pool = pids
  if lastName ~= nil and #pids > 1 then
    pool = {}
    for _, pid in ipairs(pids) do
      if players[pid] ~= lastName then pool[#pool + 1] = pid end
    end
  end
  local fewest
  for _, pid in ipairs(pool) do
    local count = (runCounts or {})[players[pid]] or 0
    if not fewest or count < fewest then fewest = count end
  end
  local eligible = {}
  for _, pid in ipairs(pool) do
    if ((runCounts or {})[players[pid]] or 0) == fewest then eligible[#eligible + 1] = pid end
  end
  return eligible
end

function M.matchPlayer(query, players, random, runCounts, lastName)
  random = random or math.random
  if query == nil or query == "" then return nil, "Pick a runner" end
  local pids = {}
  for pid in pairs(players) do pids[#pids + 1] = pid end
  table.sort(pids)
  if query:sub(1, 1) == "=" then
    local want = query:sub(2):lower()
    for _, pid in ipairs(pids) do
      if players[pid]:lower() == want then return pid end
    end
    return nil, string.format("No player named '%s'", query:sub(2))
  end
  local q = query:lower()
  if q == "next" then
    if #pids == 0 then return nil, "No players online" end
    local eligible = M.eligibleNext(players, runCounts, lastName)
    return eligible[random(#eligible)]
  end
  if q == "random" then
    if #pids == 0 then return nil, "No players online" end
    return pids[random(#pids)]
  end
  local prefixed = {}
  for _, pid in ipairs(pids) do
    local name = players[pid]:lower()
    if name == q then return pid end
    if name:sub(1, #q) == q then prefixed[#prefixed + 1] = pid end
  end
  if #prefixed == 1 then return prefixed[1] end
  if #prefixed == 0 then return nil, string.format("No player matching '%s'", query) end
  local names = {}
  for _, pid in ipairs(prefixed) do names[#names + 1] = players[pid] end
  table.sort(names)
  return nil, string.format("'%s' matches several players: %s", query, table.concat(names, ", "))
end

return M
