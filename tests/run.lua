package.path = "server/CopsAndRobbers/?.lua;client/lua/ge/extensions/?.lua;" .. package.path

local passed, failed = 0, 0
local current

function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL %s: %s", current .. " :: " .. name, tostring(err)))
  end
end

function assertEq(a, b, msg)
  if a ~= b then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(b), tostring(a)), 2)
  end
end

function assertNear(a, b, eps, msg)
  if type(a) ~= "number" or math.abs(a - b) > eps then
    error(string.format("%sexpected %s ±%s, got %s", msg and (msg .. ": ") or "", tostring(b), tostring(eps), tostring(a)), 2)
  end
end

for _, file in ipairs(arg) do
  current = file
  local chunk, err = loadfile(file)
  if not chunk then
    failed = failed + 1
    print("FAIL " .. file .. ": " .. err)
  else
    local ok, runErr = pcall(chunk)
    if not ok then
      failed = failed + 1
      print("FAIL " .. file .. ": " .. tostring(runErr))
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
