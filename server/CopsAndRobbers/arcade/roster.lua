local roster = {}

function roster.new()
  local r = {}
  local groupByName = {}
  local groups = { early = {}, late = {} }

  function r:perPlayer(name, group)
    local existingGroup = groupByName[name]
    if existingGroup and existingGroup ~= group then
      error(string.format("per-player table %s belongs to group %s, requested %s", name, existingGroup, group), 2)
    end
    if not existingGroup then
      groups[group][name] = {}
      groupByName[name] = group
    end
    return groups[group][name]
  end

  function r:clear(name)
    local group = groupByName[name]
    if not group then error("unknown per-player table " .. tostring(name), 2) end
    local entries = groups[group][name]
    for pid in pairs(entries) do entries[pid] = nil end
  end

  function r:leaveEarly(pid)
    for _, entries in pairs(groups.early) do entries[pid] = nil end
  end

  function r:leaveLate(pid)
    for _, entries in pairs(groups.late) do entries[pid] = nil end
  end

  function r:key(pid)
    local ids = MP.GetPlayerIdentifiers and MP.GetPlayerIdentifiers(pid)
    if type(ids) == "table" and ids.beammp and tostring(ids.beammp) ~= "" then
      return "beammp:" .. tostring(ids.beammp)
    end
    return "name:" .. tostring(MP.GetPlayerName(pid) or pid)
  end

  function r:pidForKey(key)
    for pid in pairs(MP.GetPlayers() or {}) do
      if self:key(pid) == key then return pid end
    end
    return nil
  end

  local sitOut = r:perPlayer("sitOut", "early")

  function r:setSitOut(pid, on)
    sitOut[pid] = on or nil
  end

  function r:sittingOut(pid)
    return sitOut[pid] == true
  end

  function r:playing(players)
    local list, count = {}, 0
    for pid, name in pairs(players) do
      if not self:sittingOut(pid) then
        list[pid] = name
        count = count + 1
      end
    end
    return list, count
  end

  return r
end

return roster
