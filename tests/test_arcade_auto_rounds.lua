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

test("the scheduled callback cancels the countdown and starts only an idle round", function()
  local a = autoRounds.new()
  local active, starts, sent = true, 0, {}
  local startScheduled = autoRounds.register({ command = function() end }, {
    a = a,
    send = function(pid, event) sent[#sent + 1] = pid .. " " .. event end,
    isActive = function() return active end,
    startNext = function() starts = starts + 1; return true end,
  })
  assertEq(type(startScheduled), "function")
  a:schedule(12)
  startScheduled()
  assertEq(a:pending(), nil)
  assertEq(starts, 0)

  active = false
  a:schedule(14)
  startScheduled()
  assertEq(a:pending(), nil)
  assertEq(starts, 1)
  assertEq(#sent, 0)
end)

test("a refused scheduled start withdraws every client's countdown", function()
  local a = autoRounds.new()
  local sent = {}
  local startScheduled = autoRounds.register({ command = function() end }, {
    a = a,
    send = function(pid, event) sent[#sent + 1] = pid .. " " .. event end,
    isActive = function() return false end,
    startNext = function() return nil, "Not enough players" end,
  })
  a:schedule(12)
  startScheduled()
  assertEq(a:pending(), nil)
  assertEq(table.concat(sent, ","), "-1 cnr_autoNext")
end)

test("auto during a chase toggles the live setting and clears the client countdown", function()
  local a = autoRounds.new()
  local sent, replies = {}, {}
  local p = panel.new({
    reply = function(pid, text) replies[#replies + 1] = { pid = pid, text = text } end,
  }, roster.new())
  local saved, pushes = { autoNextRound = true }, 0
  autoRounds.register(p, {
    a = a,
    settings = {
      get = function(_, key) return saved[key] end,
      set = function(_, key, value) saved[key] = value; return true end,
    },
    isActive = function() return true end,
    reloadRound = function() error("replaced a running round") end,
    pushRules = function() pushes = pushes + 1 end,
    send = function(pid, event, data) sent[#sent + 1] = { pid = pid, event = event, data = data } end,
  })
  a:schedule(12)
  p:run(4, "auto")
  assertEq(saved.autoNextRound, "off")
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
