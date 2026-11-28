local store = require("arcade.store")
dofile("tests/server_boot.lua")

local env = serverBoot.boot({ files = {
  ["empty.json"] = "",
  ["malformed.json"] = "[1",
  ["scalar.json"] = "1",
  ["object.json"] = '{"a":1}',
  ["replace.json"] = "old content",
} })

for _, case in ipairs({
  { file = "missing.json", corrupt = false },
  { file = "empty.json", corrupt = false },
  { file = "malformed.json", corrupt = true },
  { file = "scalar.json", corrupt = true },
}) do
  test("decode returns nil and the corruption flag for " .. case.file, function()
    local value, corrupt = store.decode(env.dir .. case.file)
    assertEq(value, nil)
    assertEq(corrupt, case.corrupt)
  end)
end

test("decode returns the JSON object", function()
  local value, corrupt = store.decode(env.dir .. "object.json")
  assertEq(type(value), "table")
  assertEq(value.a, 1)
  assertEq(corrupt, false)
end)

test("write replaces the content and leaves no temporary file", function()
  local path = env.dir .. "replace.json"
  store.write(path, "new content")
  assertEq(store.read(path), "new content")
  assertEq(FS.Exists(path .. ".tmp"), false)
end)

test("copy preserves binary bytes in both files", function()
  local bytes = "a\0b\r\n"
  local src, dst = env.dir .. "source", env.dir .. "copy"
  local f = assert(io.open(src, "wb"))
  assert(f:write(bytes))
  assert(f:close())
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
  local src = env.dir .. "malformed.json"
  local ok, err = store.copy(src, env.dir)
  assertEq(ok, nil)
  assertEq(type(err), "string")
  assertEq(store.read(src), "[1")
end)

env.cleanup()
