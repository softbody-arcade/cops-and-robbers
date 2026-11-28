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
  assertEq(store.write(path, "new content"), true)
  assertEq(FS.Exists(path .. ".bak"), false)
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

local function failingFile(step)
  return function(real)
    if step == "write" then
      return { write = function() return nil, "No space left on device" end, close = function() return real:close() end }
    end
    return { write = function(_, bytes) return real:write(bytes) end, close = function() real:close() return nil, "No space left on device" end }
  end
end

local function withOpen(target, wrap, fn)
  local realOpen = io.open
  io.open = function(path, mode)
    if path == target then return wrap(realOpen(path, mode)) end
    return realOpen(path, mode)
  end
  local ok, a, b = pcall(fn)
  io.open = realOpen
  assert(ok, a)
  return a, b
end

for _, step in ipairs({ "write", "close" }) do
  test("copy removes only its own temporary file when the " .. step .. " fails", function()
    local src = fixture("[1")
    local dst = fixture(nil)
    local copied, err = withOpen(dst .. ".tmp", failingFile(step), function() return store.copy(src, dst) end)
    assertEq(copied, nil)
    assertEq(err, "No space left on device")
    assertEq(FS.Exists(dst), false)
    assertEq(FS.Exists(dst .. ".tmp"), false)
    assertEq(store.read(src), "[1")
  end)
end

test("copy leaves a temp file it could not open untouched", function()
  local src, dst = fixture("source"), fixture(nil)
  local tmp = dst .. ".tmp"
  paths[#paths + 1] = tmp
  local file = assert(io.open(tmp, "wb"))
  assert(file:write("keep"))
  assert(file:close())
  local open = io.open
  io.open = function(path, mode)
    if path == tmp then return nil, "permission denied" end
    return open(path, mode)
  end
  local called, ok, err = pcall(store.copy, src, dst)
  io.open = open
  assert(called, ok)
  assertEq(ok, nil)
  assertEq(err, "permission denied")
  assertEq(store.read(tmp), "keep")
end)

test("copy refuses an existing destination and leaves it untouched", function()
  local src, dst = fixture("[1"), fixture("keep")
  local copied, err = store.copy(src, dst)
  assertEq(copied, nil)
  assertEq(type(err), "string")
  assertEq(store.read(dst), "keep")
  assertEq(FS.Exists(dst .. ".tmp"), false)
end)

test("copy does not replace a destination that appears while it writes", function()
  local src, dst = fixture("[1"), fixture(nil)
  local copied, err = withOpen(dst .. ".tmp", function(real)
    return { write = function(_, bytes) return real:write(bytes) end, close = function()
      local other = assert(io.open(dst, "wb"))
      other:write("other")
      other:close()
      return real:close()
    end }
  end, function() return store.copy(src, dst) end)
  assertEq(copied, nil)
  assertEq(type(err), "string")
  assertEq(store.read(dst), "other")
  assertEq(FS.Exists(dst .. ".tmp"), false)
end)

for _, step in ipairs({ "write", "close" }) do
  test("a failed temp " .. step .. " preserves the original", function()
    local path = fixture("old")
    local ok, err = withOpen(path .. ".tmp", failingFile(step), function() return store.write(path, "new") end)
    assertEq(ok, nil)
    assertEq(err, "No space left on device")
    assertEq(store.read(path), "old")
    assertEq(FS.Exists(path .. ".tmp"), false)
  end)
end

local function failedRename(fn)
  local rename = FS.Rename
  FS.Rename = function() return false, "rename denied" end
  local called, ok, err = pcall(fn)
  FS.Rename = rename
  assert(called, ok)
  return ok, err
end

test("a failed temp open returns an error without removing the original", function()
  local path = fixture("old")
  local ok, err = withOpen(path .. ".tmp", function(real)
    if real then real:close() end
    return nil, "open denied"
  end, function() return store.write(path, "new") end)
  assertEq(ok, nil)
  assertEq(err, "open denied")
  assertEq(store.read(path), "old")
  assertEq(FS.Exists(path .. ".tmp"), false)
end)

test("a refused removal aborts the replacement", function()
  local path = fixture("old")
  local remove = FS.Remove
  FS.Remove = function() return false, "remove denied" end
  local called, ok, err = pcall(store.write, path, "new")
  FS.Remove = remove
  assert(called, ok)
  assertEq(ok, nil)
  assertEq(err, "remove denied")
  assertEq(store.read(path), "old")
  assertEq(FS.Exists(path .. ".tmp"), false)
  assertEq(FS.Exists(path .. ".bak"), false)
end)

test("a failed rename restores the original bytes and cleans up", function()
  local path = fixture("old\0bytes\r\n")
  local ok, err = failedRename(function() return store.write(path, "new") end)
  assertEq(ok, nil)
  assertEq(err, "rename denied")
  assertEq(store.read(path), "old\0bytes\r\n")
  assertEq(FS.Exists(path .. ".tmp"), false)
  assertEq(FS.Exists(path .. ".bak"), false)
end)

test("a failed rename and a failed restore leave the original in <path>.bak", function()
  local path = fixture("old")
  paths[#paths + 1] = path .. ".bak"
  local open = io.open
  io.open = function(name, mode)
    if name == path and mode:match("^w") then return failingFile("write")(open(name, mode)) end
    return open(name, mode)
  end
  local called, ok, err = pcall(failedRename, function() return store.write(path, "new") end)
  io.open = open
  assert(called, ok)
  assertEq(ok, nil)
  assert(type(err) == "string" and err:find(path .. ".bak", 1, true))
  assertEq(store.read(path .. ".bak"), "old")
  assertEq(FS.Exists(path .. ".tmp"), false)
  assertEq(store.write(path, "retry"), nil)
  assertEq(store.read(path .. ".bak"), "old")
end)

test("an unreadable original stops the save before anything is removed", function()
  local path = fixture("old")
  local ok, err = withOpen(path, function(real)
    if real then real:close() end
    return nil, "permission denied", 13
  end, function() return store.write(path, "new") end)
  assertEq(ok, nil)
  assertEq(err, "permission denied")
  assertEq(store.read(path), "old")
  assertEq(FS.Exists(path .. ".tmp"), false)
end)

test("a failed backup close preserves the original", function()
  local path = fixture("old")
  local ok, err = withOpen(path .. ".bak", function(real)
    if real then return failingFile("close")(real) end
    return nil, "missing", 2
  end, function() return store.write(path, "new") end)
  assertEq(ok, nil)
  assertEq(err, "No space left on device")
  assertEq(store.read(path), "old")
  assertEq(FS.Exists(path .. ".tmp"), false)
  assertEq(FS.Exists(path .. ".bak"), false)
end)

test("a save records fs remove then fs write", function()
  dofile("tests/server_boot.lua")
  local env = serverBoot.boot({ files = { ["game.json"] = "old" } })
  local path = env.dir .. "game.json"
  env.stream = {}
  local ok = store.write(path, "new")
  env.cleanup()
  assertEq(#env.stream, 2)
  assertEq(env.stream[1].text, "0.000 fs remove " .. path)
  assertEq(env.stream[2].text, "0.000 fs write " .. path .. " new")
  assertEq(ok, true)
end)

FS, Util = originalFS, originalUtil
for _, path in ipairs(paths) do os.remove(path) end
