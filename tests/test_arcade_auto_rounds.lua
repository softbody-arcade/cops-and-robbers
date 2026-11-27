local autoRounds = require("arcade.autoRounds")
local panel = require("arcade.panel")
local roster = require("arcade.roster")

test("a round is due from its scheduled time until cancelled", function()
  local a = autoRounds.new()
  assertEq(a:due(0), false)
  a:schedule(12)
  assertEq(a:pending(), 12)
  assertEq(a:due(11.9), false)
  assertEq(a:due(12), true)
  assertEq(a:due(13), true)
  a:cancel()
  assertEq(a:pending(), nil)
  assertEq(a:due(13), false)
end)

test("auto off during a chase refreshes the config and clears the client countdown", function()
  local a = autoRounds.new()
  local sent, replies = {}, {}
  local p = panel.new({
    reply = function(pid, text) replies[#replies + 1] = { pid = pid, text = text } end,
  }, roster.new())
  local saved, refreshes, pushes = {}, 0, 0
  autoRounds.register(p, {
    a = a,
    settings = { set = function(key, value) saved[key] = value end },
    isActive = function() return true end,
    refreshConfig = function() refreshes = refreshes + 1 end,
    reloadRound = function() error("replaced a running round") end,
    pushRules = function() pushes = pushes + 1 end,
    send = function(pid, event, data) sent[#sent + 1] = { pid = pid, event = event, data = data } end,
  })
  a:schedule(12)
  p:run(4, "auto off")
  assertEq(saved.autoNextRound, "off")
  assertEq(refreshes, 1)
  assertEq(pushes, 1)
  assertEq(a:pending(), nil)
  assertEq(#sent, 1)
  assertEq(sent[1].pid, -1)
  assertEq(sent[1].event, "cnr_autoNext")
  assertEq(next(sent[1].data), nil)
  assertEq(#replies, 1)
  assertEq(replies[1].pid, 4)
  assertEq(replies[1].text, "Automatic next round: off")
end)
