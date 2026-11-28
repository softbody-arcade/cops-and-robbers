local store = {}

function store.read(path)
  local f, err, code = io.open(path, "rb")
  if not f then return nil, err, code end
  local s, readErr = f:read("*a")
  local closed, closeErr = f:close()
  if not s then return nil, readErr end
  if not closed then return nil, closeErr end
  return s
end

local function writeAndClose(f, bytes)
  local written, writeErr = f:write(bytes)
  local closed, closeErr = f:close()
  if not written then return nil, writeErr end
  if not closed then return nil, closeErr end
  return true
end

local function writeBytes(path, bytes)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  return writeAndClose(f, bytes)
end

function store.copy(src, dst)
  if src == dst then return nil, "source and destination are the same" end
  local bytes, readErr = store.read(src)
  if not bytes then return nil, readErr end
  if FS.Exists(dst) then return nil, "destination exists" end
  local tmp = dst .. ".tmp"
  local f, openErr = io.open(tmp, "wb")
  if not f then return nil, openErr end
  local written, err = writeAndClose(f, bytes)
  if not written then
    os.remove(tmp)
    return nil, err
  end
  if FS.Exists(dst) then
    os.remove(tmp)
    return nil, "destination exists"
  end
  local moved, moveErr = FS.Rename(tmp, dst)
  if not moved then
    os.remove(tmp)
    return nil, moveErr or "rename failed"
  end
  return true
end

function store.write(path, content)
  local tmp, backup = path .. ".tmp", path .. ".bak"
  local function failed(err)
    os.remove(tmp)
    return nil, err
  end
  local written, err = writeBytes(tmp, content)
  if not written then return failed(err) end

  local previous, backupErr, backupCode = io.open(backup, "rb")
  if previous then
    previous:close()
    return failed("recovery file exists: " .. backup)
  end
  if backupCode ~= 2 then return failed(backupErr) end
  local original, readErr, code = store.read(path)
  if not original and code ~= 2 then return failed(readErr) end
  if original then
    local copied, copyErr = writeBytes(backup, original)
    if not copied then
      os.remove(backup)
      return failed(copyErr)
    end
  end

  local removed, removeErr = FS.Remove(path)
  if original and (removed == false or (removed == nil and removeErr ~= nil)) then
    os.remove(backup)
    return failed(removeErr or "remove failed")
  end
  local moved, moveErr = FS.Rename(tmp, path)
  if not moved then
    if original then
      local bytes, restoreErr = store.read(backup)
      local restored
      if bytes then restored, restoreErr = writeBytes(path, bytes) end
      if not restored then
        return failed(string.format("%s; restore failed (%s), original kept at %s", moveErr or "rename failed", tostring(restoreErr), backup))
      end
      os.remove(backup)
    end
    return failed(moveErr or "rename failed")
  end
  if original then os.remove(backup) end
  return true
end

function store.writeJson(path, value)
  local ok, saved, err = pcall(function()
    return store.write(path, Util.JsonPrettify(Util.JsonEncode(value)))
  end)
  if not ok then return nil, tostring(saved) end
  return saved, err
end

function store.decode(path)
  local s, err, code = store.read(path)
  if not s or s == "" then return nil, false, s, err, code end
  local ok, value = pcall(Util.JsonDecode, s)
  if not ok or type(value) ~= "table" then return nil, true, s end
  return value, false
end

return store
