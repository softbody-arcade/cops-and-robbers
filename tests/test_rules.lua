local rules = require("cnr.rules")
local config = require("cnr.config")

test("rules payload has exactly the 19 keys with the config values", function()
  local cfg = {}
  for k, v in pairs(config.DEFAULTS) do cfg[k] = v end
  cfg.headStartSeconds = 9
  local p = rules.payload(cfg)
  local n = 0
  for k, v in pairs(p) do
    n = n + 1
    assertEq(v, cfg[k])
  end
  assertEq(n, 19)
  assertEq(#rules.KEYS, 19)
  assertEq(p.headStartSeconds, 9)
  assertEq(p.sirensAllowed, true)
  assertEq(p.autoNextRound, nil)
  assertEq(p.helicopter, true)
  assertEq(p.helicopterUpSeconds, 120)
  assertEq(p.lastSeenIntervalSeconds, nil)
end)
