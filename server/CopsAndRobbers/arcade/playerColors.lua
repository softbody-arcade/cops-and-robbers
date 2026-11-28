local colors = require("arcade.colors")
local store = require("arcade.store")

local playerColors = {}

function playerColors.new(path, r, m)
  local c = {}
  local entries = {}
  local basename = path:match("[^/\\]+$")

  local function save(pid, hex)
    local updated = {}
    for key, value in pairs(entries) do updated[key] = value end
    updated[r:key(pid)] = hex
    local ok, err = store.writeJson(path, updated)
    if not ok then
      m.log("could not save " .. basename .. ": " .. tostring(err))
      return false, "Could not save " .. basename
    end
    entries = updated
    return true
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
    return save(pid, color.hex)
  end

  function c:clear(pid)
    return save(pid, nil)
  end

  function c:sendMine(pid, err)
    local color = self:get(pid)
    m.send(pid, "cnr_myColor", { hex = color and color.hex, error = err })
  end

  return c
end

return playerColors
