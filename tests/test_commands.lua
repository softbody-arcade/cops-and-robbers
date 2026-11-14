local commands = require("cnr.commands")

test("parse start with args", function()
  local c = commands.parse("/cnr start rei")
  assertEq(c.name, "start"); assertEq(c.args[1], "rei")
end)

test("parse is case-insensitive for prefix and name", function()
  assertEq(commands.parse("/CNR TOP").name, "top")
  assertEq(commands.parse("  /cnr   stop  ").name, "stop")
end)

test("parse ignores other chat", function()
  assertEq(commands.parse("hello"), nil)
  assertEq(commands.parse("/cnrx start"), nil)
  assertEq(commands.parse("/help"), nil)
end)

test("bare /cnr is help", function()
  assertEq(commands.parse("/cnr").name, "help")
end)

test("start keeps multi-word name", function()
  assertEq(commands.parse("/cnr start Big Bob").args[1], "Big")
  assertEq(commands.parse("/cnr start Big Bob").rest, "Big Bob")
end)

local players = {[1]="Reinder", [2]="Bob", [3]="ReinderAlt"}

test("matchPlayer unique prefix", function()
  local pid = commands.matchPlayer("bo", players)
  assertEq(pid, 2)
end)

test("matchPlayer exact beats prefix", function()
  assertEq(commands.matchPlayer("REINDER", players), 1)
end)

test("matchPlayer ambiguous", function()
  local pid, err = commands.matchPlayer("rei", players)
  assertEq(pid, nil); assertEq(err, "'rei' matches several players: Reinder, ReinderAlt")
end)

test("matchPlayer unknown", function()
  local pid, err = commands.matchPlayer("zed", players)
  assertEq(pid, nil); assertEq(err, "No player matching 'zed'")
end)

test("matchPlayer missing query", function()
  local pid, err = commands.matchPlayer(nil, players)
  assertEq(pid, nil); assertEq(err, 'Usage: "/cnr start <name|random|next|again>"')
end)

test("matchPlayer random returns a member", function()
  local pid = commands.matchPlayer("random", players, function(n) return n end)
  assertEq(players[pid] ~= nil, true)
end)

test("matchPlayer random with no players", function()
  local pid, err = commands.matchPlayer("random", {})
  assertEq(pid, nil); assertEq(err, "No players online")
end)

test("matchPlayer next picks whoever ran least", function()
  local counts = {Reinder=2, Bob=0, ReinderAlt=1}
  assertEq(commands.matchPlayer("next", players, nil, counts), 2)
  assertEq(commands.matchPlayer("next", {[1]="A", [2]="B"}, nil, {}), 1)
end)
