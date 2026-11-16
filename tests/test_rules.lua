local rules = require("cnr.rules")
local config = require("cnr.config")

test("rules payload has exactly the 16 keys with the config values", function()
  local cfg = {}
  for k, v in pairs(config.DEFAULTS) do cfg[k] = v end
  cfg.headStartSeconds = 9
  local p = rules.payload(cfg)
  local n = 0
  for k, v in pairs(p) do
    n = n + 1
    assertEq(v, cfg[k])
  end
  assertEq(n, 16)
  assertEq(#rules.KEYS, 16)
  assertEq(p.headStartSeconds, 9)
  assertEq(p.sirensAllowed, true)
  assertEq(p.autoNextRound, nil)
end)
