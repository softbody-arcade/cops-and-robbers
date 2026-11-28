local colors = require("arcade.colors")
local store = require("arcade.store")

local playerColors = {}

function playerColors.new(path, r, m)
  local c = {}
  local entries = {}

  local function save()
    store.write(path, Util.JsonPrettify(Util.JsonEncode(entries)))
  end

  function c:load()
    entries = colors.load((store.decode(path)))
  end

  function c:get(pid)
    return colors.get(entries, r:key(pid))
  end

  function c:set(pid, hex)
    local color, err = colors.parseHex(hex)
    if not color then return false, err end
    colors.set(entries, r:key(pid), color.hex)
    save()
    return true
  end

  function c:clear(pid)
    colors.clear(entries, r:key(pid))
    save()
  end

  function c:sendMine(pid, err)
    local color = self:get(pid)
    m.send(pid, "cnr_myColor", { hex = color and color.hex, error = err })
  end

  return c
end

return playerColors
