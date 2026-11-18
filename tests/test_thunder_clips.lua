test("thunder bank lists the shipped Oggs", function()
  local bank = require("copsAndRobbers/thunderClips")
  local durations = {
    close = { 15, 16.304 },
    medium = { 18.4 },
    far = { 6, 12.5, 5.3, 4.5, 13.3, 9.8, 14.3 },
  }

  for group, expected in pairs(durations) do
    local clips = bank[group]
    assertEq(#clips, #expected, group)
    for i, seconds in ipairs(expected) do
      local clip = clips[i]
      local path = string.format("/art/sound/cnr/thunder_%s_%d.ogg", group, i)
      assertEq(clip.file, path)
      assertNear(clip.seconds, seconds, 0.02, path)
      assert(clip.seconds > 0, path)
      local file = assert(io.open("client" .. clip.file, "rb"))
      local signature = file:read(4)
      file:close()
      assertEq(signature, "OggS", path)
    end
  end
end)
