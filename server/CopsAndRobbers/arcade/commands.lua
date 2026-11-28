local M = {}

function M.parseText(text)
  if type(text) ~= "string" then return nil end
  local name, rest = text:match("^%s*(%S+)%s*(.-)%s*$")
  if not name then return { name = "help", args = {}, rest = "" } end
  local args = {}
  for word in rest:gmatch("%S+") do args[#args + 1] = word end
  return { name = name:lower(), args = args, rest = rest }
end

function M.parse(msg, prefix)
  if type(msg) ~= "string" or type(prefix) ~= "string" then return nil end
  local token, tail = msg:match("^%s*(%S+)%s*(.*)$")
  if not token or token:lower() ~= prefix:lower() then return nil end
  return M.parseText(tail)
end

return M
