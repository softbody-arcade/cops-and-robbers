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

return M
