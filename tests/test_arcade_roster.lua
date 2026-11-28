local roster = require("arcade.roster")

local oldMP = MP
local function mockPlayers()
  local players = { [2] = "Alice", [5] = "Bob", [7] = "Casey" }
  local ids = { [2] = { beammp = 123 }, [7] = { beammp = "" } }
  MP = {
    GetPlayers = function() return players end,
    GetPlayerName = function(pid) return players[pid] end,
    GetPlayerIdentifiers = function(pid) return ids[pid] end,
  }
  return players, ids
end

test("keys prefer the BeamMP id and fall back to name or pid", function()
  mockPlayers()
  local r = roster.new()
  assertEq(r:key(2), "beammp:123")
  assertEq(r:key(5), "name:Bob")
  assertEq(r:key(7), "name:Casey")
  assertEq(r:key(9), "name:9")
end)

test("key lookup follows the player to their current pid", function()
  local players, ids = mockPlayers()
  local r = roster.new()
  assertEq(r:pidForKey("name:Bob"), 5)
  assertEq(r:pidForKey("beammp:123"), 2)
  players[2], ids[2] = nil, nil
  assertEq(r:pidForKey("beammp:123"), nil)
  players[9], ids[9] = "Alice", { beammp = 123 }
  assertEq(r:pidForKey("beammp:123"), 9)
end)

test("player lookup reads the current names from BeamMP", function()
  mockPlayers()
  local r = roster.new()
  assertEq(r:players()[5], "Bob")
  assertEq(r:name(7), "Casey")
  assertEq(r:name(9), nil)
  MP.GetPlayers = function() return nil end
  assertEq(next(r:players()), nil)
end)

test("sit out snapshots are independent of roster changes", function()
  local r = roster.new()
  r:setSitOut(2, true)
  local snapshot = r:sitOutSnapshot()
  assertEq(snapshot[2], true)
  r:setSitOut(7, true)
  assertEq(snapshot[7], nil)
  snapshot[2] = nil
  assertEq(next(snapshot), nil)
  assertEq(r:sittingOut(2), true)
end)

test("playingList returns a dense sorted list of participating pids", function()
  local r = roster.new()
  local list = r:playingList({ [7] = "Kim" })
  assertEq(#list, 1)
  assertEq(list[1], 7)
  r:setSitOut(5, true)
  list = r:playingList({ [7] = "Kim", [2] = "Alice", [5] = "Bob" })
  assertEq(#list, 2)
  assertEq(list[1], 2)
  assertEq(list[2], 7)
end)

test("playing preserves sparse pids and respects sit out changes", function()
  local r = roster.new()
  local online = { [2] = "Alice", [5] = "Bob", [7] = "Casey" }
  r:setSitOut(5, true)
  assertEq(r:sittingOut(5), true)
  local playing, count = r:playing(online)
  assertEq(count, 2)
  assertEq(playing[2], "Alice")
  assertEq(playing[5], nil)
  assertEq(playing[7], "Casey")
  r:setSitOut(5, false)
  assertEq(r:sittingOut(5), false)
  playing, count = r:playing(online)
  assertEq(count, 3)
  assertEq(playing[5], "Bob")
end)

test("each disconnect phase clears only its tables for the departing pid", function()
  local r = roster.new()
  local early = r:perPlayer("subscribers", "early")
  local late = r:perPlayer("vehicles", "late")
  early[2], early[7] = true, true
  late[2], late[7] = 11, 12
  r:setSitOut(2, true)
  r:leaveEarly(2)
  assertEq(early[2], nil)
  assertEq(r:sittingOut(2), false)
  assertEq(late[2], 11)
  early[2] = true
  r:leaveLate(2)
  assertEq(late[2], nil)
  assertEq(early[2], true)
  assertEq(early[7], true)
  assertEq(late[7], 12)
end)

test("clear empties the named table in place", function()
  local r = roster.new()
  local cars = r:perPlayer("cars", "late")
  local subs = r:perPlayer("subs", "early")
  cars[2], cars[7], subs[2] = 11, 12, true
  r:clear("cars")
  assertEq(next(cars), nil)
  assertEq(r:perPlayer("cars", "late"), cars)
  assertEq(subs[2], true)
end)

test("clear identifies an unknown table", function()
  local r = roster.new()
  local ok, err = pcall(r.clear, r, "nope")
  assertEq(ok, false)
  assert(err:find("nope", 1, true), err)
end)

test("registering a table in a different group names both groups", function()
  local r = roster.new()
  local entries = r:perPlayer("a", "early")
  assertEq(r:perPlayer("a", "early"), entries)
  local ok, err = pcall(r.perPlayer, r, "a", "late")
  assertEq(ok, false)
  assert(err:find("early", 1, true), err)
  assert(err:find("late", 1, true), err)
end)

test("rosters have independent sit out and per-player state", function()
  local a, b = roster.new(), roster.new()
  a:setSitOut(5, true)
  a:perPlayer("cars", "late")[5] = 11
  assertEq(b:sittingOut(5), false)
  assertEq(b:perPlayer("cars", "late")[5], nil)
end)

MP = oldMP
