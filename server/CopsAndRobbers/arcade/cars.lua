local vec = require("arcade.vec")
local cars = {}

function cars.new(roster, messages, traffic)
  local c = {}
  local entries = roster:perPlayer("roundCarEntries", "late")
  local publishing = false
  local lastSignature

  local function entryFor(pid)
    if not entries[pid] then entries[pid] = {} end
    return entries[pid]
  end

  function c:vehicles(owner)
    local vehicles = MP.GetPlayerVehicles(owner)
    return type(vehicles) == "table" and vehicles or {}
  end

  function c:rawPosition(owner, vid)
    local raw, err = MP.GetPositionRaw(owner, vid)
    if (err and err ~= "") or type(raw) ~= "table" then return nil, err end
    return raw, err
  end

  function c:position(owner, vid)
    if owner == nil or vid == nil then return nil end
    local raw = self:rawPosition(owner, vid)
    if not raw then return nil end
    local pos, vel = vec.toVec(raw.pos), vec.toVec(raw.vel)
    if pos and vel then return { pos = pos, vel = vel } end
  end

  function c:firstVid(pid)
    local best
    for vid in pairs(self:vehicles(pid)) do
      if not best or vid < best then best = vid end
    end
    return best
  end

  function c:activeVid(pid)
    return entries[pid] and entries[pid].vid
  end

  function c:confirmed(pid)
    return entries[pid] ~= nil and entries[pid].confirmed == true
  end

  function c:confirmedVid(pid)
    if self:confirmed(pid) then return entries[pid].vid end
  end

  function c:vidFor(pid)
    local vid = self:activeVid(pid)
    if vid or self:confirmed(pid) or traffic:openCount(pid) then return vid end
    vid = self:firstVid(pid)
    if vid then entryFor(pid).vid = vid end
    return vid
  end

  function c:setActive(pid, vid)
    local entry = entryFor(pid)
    local replaced = entry.confirmed == true and entry.vid ~= vid
    entry.vid = vid
    return replaced
  end

  function c:rememberPreRound(pid)
    local entry = entryFor(pid)
    if entry.confirmed or entry.preRound then return end
    entry.preRound = {}
    for vid in pairs(self:vehicles(pid)) do entry.preRound[vid] = true end
  end

  function c:isPreRound(pid, vid)
    local preRound = entries[pid] and entries[pid].preRound
    return preRound ~= nil and preRound[vid] == true
  end

  function c:forgetPreRound(pid, vid)
    local preRound = entries[pid] and entries[pid].preRound
    if preRound then preRound[vid] = nil end
  end

  function c:setup(pid, payload)
    local entry = entryFor(pid)
    entry.participant = true
    local delivered, reason = messages.send(pid, "cnr_roundSetup", payload)
    if delivered ~= false then
      entry.permitted = true
      entry.placementPending = true
      self:rememberPreRound(pid)
    end
    return delivered, reason
  end

  function c:requestPick(pid, payload)
    return messages.send(pid, "cnr_pickVehicle", payload)
  end

  function c:rebuild(targets, payload, id)
    local delivery = {}
    for _, pid in ipairs(targets) do
      delivery[pid] = messages.send(pid, "cnr_rebuild", payload) ~= false
      if delivery[pid] then entryFor(pid).rebuild = id end
    end
    return delivery
  end

  function c:acknowledgeRebuild(pid, id)
    if id == nil or not entries[pid] or entries[pid].rebuild ~= id then return false end
    entries[pid].rebuild = nil
    return true
  end

  function c:pendingRebuild(pid)
    return entries[pid] ~= nil and entries[pid].rebuild ~= nil
  end

  function c:permitted(pid)
    return entries[pid] ~= nil and entries[pid].permitted == true
  end

  function c:placementPending(pid)
    return entries[pid] ~= nil and entries[pid].placementPending == true
  end

  function c:replacementAllowed(pid)
    return self:confirmed(pid) and entries[pid].vid == nil
  end

  function c:claim(pid, vid)
    local right
    if self:permitted(pid) then
      right = "permit"
    elseif self:replacementAllowed(pid) then
      right = "replacement"
    else
      return nil
    end
    local replaced = self:setActive(pid, vid)
    entries[pid].permitted = nil
    entries[pid].placementPending = true
    if self:confirmed(pid) then self:publish() end
    return right, replaced
  end

  function c:confirm(pid, vid)
    local replaced = self:setActive(pid, vid)
    local entry = entries[pid]
    entry.confirmed = true
    entry.placementPending = nil
    entry.permitted = nil
    entry.preRound = nil
    return replaced
  end

  function c:removeParticipant(pid)
    entries[pid] = nil
  end

  function c:setPublishing(on)
    publishing = on
  end

  function c:publish(pid)
    if not publishing then return end
    local keys = {}
    for owner, entry in pairs(entries) do
      if entry.participant and entry.confirmed and entry.vid then
        keys[#keys + 1] = owner .. "-" .. entry.vid
      end
    end
    table.sort(keys)
    if pid then return messages.send(pid, "cnr_roundCars", { keys = keys }) end
    local signature = table.concat(keys, ",")
    if signature == lastSignature then return end
    lastSignature = signature
    messages.send(-1, "cnr_roundCars", { keys = keys })
  end

  function c:clearPublished()
    if lastSignature and lastSignature ~= "" then messages.send(-1, "cnr_roundCars", { keys = {} }) end
    lastSignature = nil
  end

  function c:clearRound()
    roster:clear("roundCarEntries")
  end

  return c
end

return cars
