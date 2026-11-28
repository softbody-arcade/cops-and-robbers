local store = require("arcade.store")
local originalFS, originalUtil = FS, Util
local paths = {}

local function fixture(content)
  local path = os.tmpname()
  paths[#paths + 1] = path
  if content == nil then
    assert(os.remove(path))
  else
    local file = assert(io.open(path, "wb"))
    assert(file:write(content))
    assert(file:close())
  end
  return path
end

FS = {
  Exists = function(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
  end,
  Remove = os.remove,
  Rename = function(src, dst)
    if FS.Exists(dst) then return false end
    return os.rename(src, dst)
  end,
}
Util = {
  JsonDecode = function(text)
    if text == '{"a":1}' then return { a = 1 } end
    if text == "1" then return 1 end
    error("invalid JSON")
  end,
}

for _, case in ipairs({
  { file = "missing.json", corrupt = false },
  { file = "empty.json", content = "", corrupt = false },
  { file = "malformed.json", content = "[1", corrupt = true },
  { file = "scalar.json", content = "1", corrupt = true },
}) do
  test("decode returns nil and the corruption flag for " .. case.file, function()
    local value, corrupt = store.decode(fixture(case.content))
    assertEq(value, nil)
    assertEq(corrupt, case.corrupt)
  end)
end

test("decode returns the JSON object", function()
  local value, corrupt = store.decode(fixture('{"a":1}'))
  assertEq(type(value), "table")
  assertEq(value.a, 1)
  assertEq(corrupt, false)
end)

test("write replaces the content and leaves no temporary file", function()
  local path = fixture("old content")
  paths[#paths + 1] = path .. ".tmp"
  store.write(path, "new content")
  assertEq(store.read(path), "new content")
  assertEq(FS.Exists(path .. ".tmp"), false)
end)

test("copy preserves binary bytes in both files", function()
  local bytes = "a\0b\r\n"
  local src, dst = fixture(bytes), fixture(nil)
  assertEq(type(store.copy), "function")
  assertEq(store.copy(src, dst), true)
  for _, path in ipairs({ src, dst }) do
    local file = assert(io.open(path, "rb"))
    assertEq(file:read("*a"), bytes)
    file:close()
  end
end)

test("copy reports a destination open failure and preserves the source", function()
  assertEq(type(store.copy), "function")
  local src = fixture("[1")
  local ok, err = store.copy(src, src .. "/copy")
  assertEq(ok, nil)
  assertEq(type(err), "string")
  assertEq(store.read(src), "[1")
end)

for _, case in ipairs({
  { step = "write", file = function(real) return { write = function() return nil, "No space left on device" end, close = function() return real:close() end } end },
  { step = "close", file = function(real) return { write = function(_, bytes) return real:write(bytes) end, close = function() real:close() return nil, "No space left on device" end } end },
}) do
  test("copy removes a partial destination when the " .. case.step .. " fails", function()
    local src = fixture("[1")
    local dst = fixture(nil)
    local realOpen = io.open
    io.open = function(path, mode)
      if path == dst then return case.file(realOpen(path, mode)) end
      return realOpen(path, mode)
    end
    local ran, copied, copyErr = pcall(store.copy, src, dst)
    io.open = realOpen
    assertEq(ran, true)
    assertEq(copied, nil)
    assertEq(copyErr, "No space left on device")
    assertEq(FS.Exists(dst), false)
    assertEq(store.read(src), "[1")
  end)
end

FS, Util = originalFS, originalUtil
for _, path in ipairs(paths) do os.remove(path) end
