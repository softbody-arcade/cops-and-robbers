local store = {}

function store.read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function store.write(path, content)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  f:write(content)
  f:close()
  FS.Remove(path)
  FS.Rename(tmp, path)
end

function store.decode(path)
  local s = store.read(path)
  if not s or s == "" then return nil, false end
  local ok, value = pcall(Util.JsonDecode, s)
  if not ok or type(value) ~= "table" then return nil, true end
  return value, false
end

return store
