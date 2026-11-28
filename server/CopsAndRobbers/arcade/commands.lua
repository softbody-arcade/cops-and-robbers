local M = {}

function M.parseText(text)
  if type(text) ~= "string" then return nil end
  local name, rest = text:match("^%s*(%S+)%s*(.-)%s*$")
  if not name then return { name = "help", args = {}, rest = "" } end
  local args = {}
  for word in rest:gmatch("%S+") do args[#args + 1] = word end
  return { name = name:lower(), args = args, rest = rest }
end

return M
