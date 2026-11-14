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

function M.matchPlayer(query, players, random)
  random = random or math.random
  if query == nil or query == "" then return nil, "Usage: /cnr start <name|random>" end
  local pids = {}
  for pid in pairs(players) do pids[#pids + 1] = pid end
  table.sort(pids)
  local q = query:lower()
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
