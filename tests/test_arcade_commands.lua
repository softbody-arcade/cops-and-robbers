local commands = require("arcade.commands")

test("parseText reads a command without a prefix", function()
  local cmd = commands.parseText("start rein")
  assertEq(cmd.name, "start")
  assertEq(cmd.args[1], "rein")
  assertEq(cmd.rest, "rein")
end)

test("parseText lower-cases the name, tolerates extra spaces and keeps a multi-word rest", function()
  local cmd = commands.parseText("  START   Big Bob  ")
  assertEq(cmd.name, "start")
  assertEq(cmd.args[1], "Big")
  assertEq(cmd.args[2], "Bob")
  assertEq(cmd.rest, "Big Bob")
end)

test("parseText returns nil for a non-string", function()
  assertEq(commands.parseText(nil), nil)
  assertEq(commands.parseText(5), nil)
end)

test("parseText treats empty and blank input as help", function()
  for _, text in ipairs({ "", " \t " }) do
    local cmd = commands.parseText(text)
    assertEq(cmd.name, "help")
    assertEq(#cmd.args, 0)
    assertEq(cmd.rest, "")
  end
end)
