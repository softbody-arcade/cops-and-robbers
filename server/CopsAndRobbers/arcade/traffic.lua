local traffic = {}

local function whole(v)
  local n = tonumber(v) or 0
  return math.max(0, math.floor(n))
end

function traffic.perPlayer(setting, maxCars, practice)
  local n = whole(setting)
  local cars = tonumber(maxCars)
  if cars then n = math.min(n, math.max(0, math.floor(cars) - (practice and 3 or 1))) end
  return n
end

function traffic.maxCars()
  if not MP.Settings or MP.Settings.MaxCars == nil then return nil end
  local ok, value = pcall(MP.Get, MP.Settings.MaxCars)
  return ok and tonumber(value) or nil
end

local function isNum(v)
  return type(v) == "number" and v == v
end

local function toVec(t)
  if type(t) ~= "table" then return nil end
  local x, y, z = t.x, t.y, t.z
  if x == nil then x, y, z = t[1], t[2], t[3] end
  if not (isNum(x) and isNum(y) and isNum(z)) then return nil end
  return { x = x, y = y, z = z }
end

function traffic.new(r, m)
  local t = {}
  local trafficOpen = r:perPlayer("trafficOpen", "late")
  local trafficVids = r:perPlayer("trafficVids", "late")

  function t:allowance(pid, cfg, practice, eligible)
    if not eligible then return 0 end
    return traffic.perPlayer(cfg.trafficPerPlayer, traffic.maxCars(), practice)
  end

  function t:open(pid, count)
    if count <= 0 or trafficOpen[pid] then return end
    trafficOpen[pid] = count
    m.send(pid, "cnr_trafficStart", { count = count })
  end

  function t:openCount(pid)
    return trafficOpen[pid]
  end

  function t:report(pid, vids, ownVid, isAI)
    local limit = trafficOpen[pid]
    if not limit then return end
    local set, n = {}, 0
    for _, raw in ipairs(vids) do
      if n >= limit then break end
      local vid = tonumber(raw)
      if vid and vid ~= ownVid and not set[vid] and not isAI(vid) then
        set[vid] = true
        n = n + 1
      end
    end
    trafficVids[pid] = set
  end

  function t:extraCars(pid, ownVid)
    local vehicles = MP.GetPlayerVehicles(pid)
    local n = 0
    if type(vehicles) ~= "table" then return n end
    for vid in pairs(vehicles) do
      if vid ~= ownVid then n = n + 1 end
    end
    return n
  end

  function t:cars()
    local list = {}
    for pid, set in pairs(trafficVids) do
      for vid in pairs(set) do
        local raw, err = MP.GetPositionRaw(pid, vid)
        if not (err and err ~= "") and type(raw) == "table" then
          local pos, vel = toVec(raw.pos), toVec(raw.vel)
          if pos and vel then list[#list + 1] = { pos = pos, vel = vel, traffic = true } end
        end
      end
    end
    return list
  end

  return t
end

return traffic
