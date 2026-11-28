local M = {}

local ERR = "Use a hex color like #ff0000"

function M.parseHex(input)
  if type(input) ~= "string" then return nil, ERR end
  local h = input:lower():gsub("^#", "")
  if #h == 3 and h:match("^%x+$") then
    h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
  end
  if #h ~= 6 or not h:match("^%x+$") then return nil, ERR end
  return {
    hex = "#" .. h,
    r = tonumber(h:sub(1, 2), 16) / 255,
    g = tonumber(h:sub(3, 4), 16) / 255,
    b = tonumber(h:sub(5, 6), 16) / 255,
  }
end

function M.load(decoded)
  local store = {}
  if type(decoded) == "table" then
    for name, hex in pairs(decoded) do
      if type(name) == "string" and M.parseHex(hex) then store[name] = M.parseHex(hex).hex end
    end
  end
  return store
end

function M.set(store, name, hex) store[name] = hex end
function M.clear(store, name) store[name] = nil end

function M.get(store, name)
  local hex = store[name]
  return hex and M.parseHex(hex) or nil
end

return M
