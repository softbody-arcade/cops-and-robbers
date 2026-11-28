local playerColors = require("arcade.playerColors")
local roster = require("arcade.roster")
local messages = require("arcade.messages")
dofile("tests/server_boot.lua")

local env = serverBoot.boot({ files = {
  ["legacy.json"] = '{"Reinder":"#0088ff"}',
  ["clear.json"] = '{"beammp:42":"#ff0000","Reinder":"#00ff00","name:Bob":"#0000ff"}',
} })
env.ids = { [1] = { beammp = 42 } }

local function loadColors(file)
  local c = playerColors.new(env.dir .. file, roster.new(), messages.new({ prefix = "[CnR] " }))
  c:load()
  return c
end

test("set saves the normalized colour under the roster key", function()
  local c = loadColors("set.json")
  local ok, err = c:set(1, "#F80")
  assertEq(ok, true)
  assertEq(err, nil)
  assertEq(c:get(1).hex, "#ff8800")
  local saved = require("arcade.store").decode(env.dir .. "set.json")
  assertEq(saved["beammp:42"], "#ff8800")
  local color = loadColors("set.json"):get(1)
  assertEq(color.hex, "#ff8800")
  assertEq(color.r, 1)
  assertNear(color.g, 136 / 255, 1e-9)
  assertEq(color.b, 0)
end)

test("get ignores a colour saved under the bare player name", function()
  assertEq(loadColors("legacy.json"):get(1), nil)
end)

test("clear removes only the identity-keyed colour across reloads", function()
  local c = loadColors("clear.json")
  assertEq(c:get(1).hex, "#ff0000")
  c:clear(1)
  local saved = require("arcade.store").decode(env.dir .. "clear.json")
  assertEq(saved["beammp:42"], nil)
  assertEq(saved.Reinder, "#00ff00")
  assertEq(c:get(1), nil)
  local reloaded = loadColors("clear.json")
  assertEq(reloaded:get(1), nil)
  assertEq(reloaded:get(2).hex, "#0000ff")
end)

test("an invalid hex reports the parse error with the current colour", function()
  local c = loadColors("invalid.json")
  c:set(2, "#abc")
  local ok, err = c:set(2, "#badhex")
  assertEq(ok, false)
  assertEq(err, "Use a hex color like #ff0000")
  c:sendMine(2, err)
  local event = env.lastSent("cnr_myColor")
  assertEq(event.pid, 2)
  local payload = Util.JsonDecode(event.data)
  assertEq(payload.hex, "#aabbcc")
  assertEq(payload.error, err)
end)

for _, method in ipairs({ "set", "clear" }) do
  test("a failed " .. method .. " reports the error and keeps the saved colour", function()
    local c = loadColors(method .. "-failed.json")
    assert(c:set(1, "#ff0000"))
    local rename = FS.Rename
    FS.Rename = function() return false, "denied" end
    local called, ok, err = pcall(c[method], c, 1, "#00ff00")
    FS.Rename = rename
    assert(called, ok)
    assertEq(ok, false)
    assertEq(err, "denied")
    assertEq(c:get(1).hex, "#ff0000")
    assertEq(loadColors(method .. "-failed.json"):get(1).hex, "#ff0000")
  end)
end

env.cleanup()
