local store = {}

function store.read(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local s, readErr = f:read("*a")
  local closed, closeErr = f:close()
  if not s then return nil, readErr end
  if not closed then return nil, closeErr end
  return s
end

function store.copy(src, dst)
  if src == dst then return nil, "source and destination are the same" end
  local bytes, readErr = store.read(src)
  if not bytes then return nil, readErr end
  local f, err = io.open(dst, "wb")
  if not f then return nil, err end
  local written, writeErr = f:write(bytes)
  local closed, closeErr = f:close()
  if not written then return nil, writeErr end
  if not closed then return nil, closeErr end
  return true
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
  if not s or s == "" then return nil, false, s end
  local ok, value = pcall(Util.JsonDecode, s)
  if not ok or type(value) ~= "table" then return nil, true, s end
  return value, false
end

return store
