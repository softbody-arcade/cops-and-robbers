local M = {}

function M.deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not M.deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function M.diffKeys(a, b, limit)
  if type(a) ~= "table" or type(b) ~= "table" then return "(shape changed)" end
  local keys, seen = {}, {}
  for _, t in ipairs({ a, b }) do
    for k in pairs(t) do
      if not seen[k] and not M.deepEqual(a[k], b[k]) then
        seen[k] = true
        keys[#keys + 1] = tostring(k)
      end
    end
  end
  table.sort(keys)
  local shown = {}
  for i = 1, math.min(#keys, limit or #keys) do shown[i] = keys[i] end
  local text = table.concat(shown, ", ")
  if #keys > #shown then text = text .. string.format(" (+%d more)", #keys - #shown) end
  return text
end

return M
