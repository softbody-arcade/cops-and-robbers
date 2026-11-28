local commands = require("arcade.commands")

test("parseText reads a command without a prefix", function()
  local cmd = commands.parseText("start rein")
  assertEq(cmd.name, "start")
  assertEq(cmd.args[1], "rein")
  assertEq(cmd.rest, "rein")
end)

test("parseText treats empty and blank input as help", function()
  for _, text in ipairs({ "", " \t " }) do
    local cmd = commands.parseText(text)
    assertEq(cmd.name, "help")
    assertEq(#cmd.args, 0)
    assertEq(cmd.rest, "")
  end
end)
