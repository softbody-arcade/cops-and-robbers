local rules = require("cnr.rules")
local config = require("cnr.config")

test("rules payload has exactly the 14 keys with the config values", function()
  local cfg = {}
  for k, v in pairs(config.DEFAULTS) do cfg[k] = v end
  cfg.headStartSeconds = 9
  local p = rules.payload(cfg)
  local n = 0
  for k, v in pairs(p) do
    n = n + 1
    assertEq(v, cfg[k])
  end
  assertEq(n, 14)
  assertEq(#rules.KEYS, 14)
  assertEq(p.headStartSeconds, 9)
  assertEq(p.autoNextRound, nil)
end)
