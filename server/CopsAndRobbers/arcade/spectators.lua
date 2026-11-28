local spectators = {}

function spectators.new(roster, messages)
  local k = {}
  local parked = roster:perPlayer("parkedBystanders", "early")

  function k:spectate(pid, payload, label)
    messages.log(string.format("%s spectates (%s)", roster:name(pid) or tostring(pid), tostring(label)))
    return messages.send(pid, "cnr_spectate", payload)
  end

  function k:isParked(pid)
    return parked[pid] == true
  end

  function k:park(pid)
    if parked[pid] then return end
    if messages.send(pid, "cnr_parkBystanderCars", { on = true }) ~= false then parked[pid] = true end
  end

  function k:releaseAll()
    for pid in pairs(parked) do messages.send(pid, "cnr_parkBystanderCars", { on = false }) end
    roster:clear("parkedBystanders")
  end

  return k
end

return spectators
