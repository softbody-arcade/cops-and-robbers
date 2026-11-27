local PLACES = {
  { "client/lua/ge/extensions/copsAndRobbers.lua", '\nlocal CLIENT_VERSION = "([^"]+)"' },
  { "client/mod_info/CopsAndRobbers/info.json", '"version_string"%s*:%s*"([^"]+)"' },
  { "docs/FEATURES.md", "^# Cops and Robbers (%S+): features" },
}

test("the server version is x.y.z", function()
  assertEq(CNR_VERSION:match("^%d+%.%d+%.%d+$") ~= nil, true, CNR_VERSION)
end)

test("client, mod info and FEATURES carry the server version", function()
  for _, place in ipairs(PLACES) do
    assertEq(versionIn(place[1], place[2]), CNR_VERSION, place[1])
  end
end)

test("invalid release versions print usage before checking git", function()
  for _, version in ipairs({ "1.2-beta", "01.2.3", "1.02.3", "1.2.03" }) do
    local output = assert(io.popen("./scripts/version.sh " .. version .. " 2>&1"))
    local message = output:read("*a")
    local ok = output:close()
    assertEq(ok, nil)
    assertEq(message, "usage: make version V=x.y.z\n")
  end
end)
