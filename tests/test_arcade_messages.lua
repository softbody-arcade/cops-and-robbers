local messages = require("arcade.messages")
dofile("tests/server_boot.lua")

local oldMP, oldUtil = MP, Util
local sent
MP = {
  TriggerClientEvent = function(pid, event, data)
    sent[#sent + 1] = { pid = pid, event = event, data = data }
    return "engine result"
  end,
}
Util = { JsonEncode = function(value) return serverBoot.encode(value, true) end }

local function service()
  sent = {}
  return messages.new({ prefix = "[CnR] " })
end

local function assertSend(index, pid, event, data)
  assertEq(sent[index].pid, pid)
  assertEq(sent[index].event, event)
  assertEq(sent[index].data, data)
end

test("messages require a prefix at construction", function()
  local ok, err = pcall(messages.new, {})
  assertEq(ok, false)
  assert(err:find("prefix", 1, true), err)
end)

test("log prints the configured prefix and text", function()
  local m = messages.new({ prefix = "[Test] " })
  local oldPrint, lines = print, {}
  print = function(...) lines[#lines + 1] = table.concat({...}, "\t") end
  local ok, err = pcall(m.log, "x")
  print = oldPrint
  assert(ok, err)
  assertEq(#lines, 1)
  assertEq(lines[1], "[Test] x")
end)

test("send ignores invalid player IDs and returns the engine result for player zero", function()
  local m = service()
  m.send(-2, "cnr_test")
  m.send("1", "cnr_test")
  assertEq(#sent, 0)
  assertEq(m.send(0, "cnr_test"), "engine result")
  assertSend(1, 0, "cnr_test", "{}")
end)

test("notices default to info and broadcasts send to all players", function()
  local m = service()
  m.notify(3, "hi")
  m.broadcast("hi all", "warn")
  assertSend(1, 3, "cnr_notice", '{"msg":"hi","tone":"info"}')
  assertSend(2, -1, "cnr_notice", '{"msg":"hi all","tone":"warn"}')
end)

test("only replies for the mirrored player and service go to the panel during a callback", function()
  local m = service()
  local other = messages.new({ prefix = "[Other] " })
  local ok, err = m.mirrored(3, function(pid, text)
    m.reply(pid, text)
    m.refuse(pid, text)
    m.reply(4, text)
    other.reply(pid, text)
  end, 3, "x")
  assertEq(ok, true)
  assertEq(err, nil)
  m.reply(3, "x")
  assertSend(1, 3, "cnr_panelReply", '{"text":"x"}')
  assertSend(2, 3, "cnr_panelReply", '{"text":"x","tone":"warn"}')
  assertSend(3, 4, "cnr_notice", '{"msg":"x","tone":"info"}')
  assertSend(4, 3, "cnr_notice", '{"msg":"x","tone":"info"}')
  assertSend(5, 3, "cnr_notice", '{"msg":"x","tone":"info"}')
end)

test("a failed callback returns its error and clears the mirror", function()
  local m = service()
  local ok, err = m.mirrored(3, error, "failed", 0)
  assertEq(ok, false)
  assertEq(err, "failed")
  m.reply(3, "x")
  assertSend(1, 3, "cnr_notice", '{"msg":"x","tone":"info"}')
end)

MP, Util = oldMP, oldUtil
