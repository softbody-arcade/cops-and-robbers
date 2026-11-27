local panel = require("arcade.panel")
local roster = require("arcade.roster")

local function setup()
  local sent, logs = {}, {}
  local p = panel.new({
    send = function(pid, event, state)
      sent[#sent + 1] = { pid = pid, event = event, state = state }
    end,
    log = function(text) logs[#logs + 1] = text end,
  }, roster.new())
  return p, sent, logs
end

test("a closed panel skips building its state", function()
  local p = setup()
  local function unused() error("built state without subscribers") end
  p:push(unused)
  p:push(function() return {} end, 2)
  p:close(2)
  p:push(unused)
end)

test("a panel opener receives one copy after the other subscribers", function()
  local p, sent = setup()
  local state = { round = 1 }
  local function snapshot() return state end
  for _, pid in ipairs({ 4, 5, 2 }) do p:push(snapshot, pid) end

  local before = #sent
  state = { round = 2 }
  p:push(snapshot, 2)
  assertEq(#sent, before + 3)
  local first, second = sent[before + 1].pid, sent[before + 2].pid
  assertEq((first == 4 and second == 5) or (first == 5 and second == 4), true)
  assertEq(sent[before + 3].pid, 2)
  for i = before + 1, before + 3 do
    assertEq(sent[i].event, "cnr_panelState")
    assertEq(sent[i].state.round, 2)
  end

  p:push(snapshot, 2)
  assertEq(#sent, before + 4)
  assertEq(sent[#sent].pid, 2)
end)

test("targeted lobby updates leave the broadcast signature alone", function()
  local p, sent = setup()
  local online = 1
  local function snapshot() return { online = online } end
  p:pushLobby(snapshot)
  online = 2
  p:pushLobby(snapshot, 4)
  p:pushLobby(snapshot, 4)
  p:pushLobby(snapshot)
  p:pushLobby(snapshot)
  assertEq(#sent, 4)
  for i, pid in ipairs({ -1, 4, 4, -1 }) do
    assertEq(sent[i].pid, pid)
    assertEq(sent[i].event, "cnr_lobby")
    assertEq(sent[i].state.online, i == 1 and 1 or 2)
  end
end)

test("tick logs changed panel and lobby errors independently and resets after recovery", function()
  local p, _, logs = setup()
  local function good() return {} end
  p:push(good, 2)
  local problem = "first"
  local function badPanel() error(problem, 0) end
  local function badLobby() error("offline", 0) end
  p:tick(badPanel, badLobby)
  p:tick(badPanel, badLobby)
  problem = "second"
  p:tick(badPanel, badLobby)
  p:tick(good, good)
  p:tick(badPanel, badLobby)
  assertEq(#logs, 5)
  assertEq(logs[1], "panel update failed: first")
  assertEq(logs[2], "lobby update failed: offline")
  assertEq(logs[3], "panel update failed: second")
  assertEq(logs[4], "panel update failed: second")
  assertEq(logs[5], "lobby update failed: offline")
end)

test("panel commands dispatch the parsed arguments to the registered handler", function()
  local p = setup()
  local player, cmd
  p:command("start", function(pid, parsed) player, cmd = pid, parsed end)
  p:run(4, "start next")
  assertEq(player, 4)
  assertEq(cmd.name, "start")
  assertEq(#cmd.args, 1)
  assertEq(cmd.args[1], "next")
  assertEq(cmd.rest, "next")
end)
