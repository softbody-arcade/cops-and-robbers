local commands = require("cnr.commands")

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
  assertEq(pid, nil); assertEq(err, 'Pick a runner')
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
  assertEq(commands.matchPlayer("next", {[1]="A"}, nil, {}), 1)
end)

local function drawNext(players, counts, last, draws)
  local seen = {}
  math.randomseed(11)
  for _ = 1, draws do
    local pid = commands.matchPlayer("next", players, nil, counts, last)
    seen[pid] = (seen[pid] or 0) + 1
  end
  return seen
end

test("matchPlayer next draws among everyone tied on the fewest runs", function()
  local seen = drawNext({[1]="A", [2]="B", [3]="C"}, {}, nil, 200)
  assertEq(seen[1] ~= nil and seen[2] ~= nil and seen[3] ~= nil, true)
end)

test("matchPlayer next never repeats the previous runner while another is eligible", function()
  local seen = drawNext({[1]="A", [2]="B", [3]="C"}, {}, "B", 200)
  assertEq(seen[2], nil)
  assertEq(seen[1] ~= nil and seen[3] ~= nil, true)
end)

test("matchPlayer next picks the previous runner in a solo round", function()
  assertEq(commands.matchPlayer("next", {[1]="A"}, nil, {A=3}, "A"), 1)
end)

test("matchPlayer next widens to the next-fewest when only the previous runner is lowest", function()
  local seen = drawNext({[1]="A", [2]="B", [3]="C"}, {A=0, B=1, C=2}, "A", 100)
  assertEq(seen[1], nil); assertEq(seen[3], nil)
  assertEq(seen[2], 100)
end)

test("matchPlayer next draws with the injected random", function()
  local pl = {[1]="A", [2]="B", [3]="C"}
  assertEq(commands.matchPlayer("next", pl, function() return 3 end, {}), 3)
  assertEq(commands.matchPlayer("next", pl, function() return 1 end, {}, "A"), 2)
end)

test("matchPlayer =name picks the exact player even when the name is a keyword", function()
  local players = { [1] = "next", [2] = "Bob", [3] = "Bobby" }
  assertEq(commands.matchPlayer("=next", players), 1)
  assertEq(commands.matchPlayer("=BOB", players), 2)
  local pid, err = commands.matchPlayer("=bo", players)
  assertEq(pid, nil); assertEq(err, "No player named 'bo'")
end)
