local spectators = require("arcade.spectators")
local roster = require("arcade.roster")

test("only delivered parks are remembered and each parked player is released once", function()
  local sent = {}
  local r = roster.new()
  local k = spectators.new(r, { send = function(pid, event, payload)
    assertEq(event, "cnr_parkBystanderCars")
    sent[#sent + 1] = { pid = pid, on = payload.on }
    return pid ~= 3
  end })
  for _, pid in ipairs({ 1, 2, 3, 4, 2 }) do k:park(pid) end
  assertEq(#sent, 4)
  assertEq(k:isParked(2), true)
  assertEq(k:isParked(3), false)
  r:leaveEarly(4)
  k:releaseAll()
  k:releaseAll()
  assertEq(#sent, 6)
  local released = {}
  for i = 5, 6 do
    assertEq(sent[i].on, false)
    released[sent[i].pid] = true
  end
  assertEq(released[1], true)
  assertEq(released[2], true)
  assertEq(k:isParked(2), false)
end)
