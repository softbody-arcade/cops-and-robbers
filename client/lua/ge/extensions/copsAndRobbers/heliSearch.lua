local flight = require("copsAndRobbers/heliFlight")
local tunnels = require("copsAndRobbers/tunnels")
local roadSearch = require("copsAndRobbers/roadSearch")

local M = {}

M.TARGET_MISSING_SECONDS = 2
M.SEARCH_MOVING_SPEED = 5
M.WATCH_MIN_SPEED = 10
M.WATCH_FACTOR = 1.5
M.WATCH_MIN = 15
M.WATCH_MAX = 90
M.GUIDED_CHECK_SECONDS = 1

function M.watchSeconds(length, speed)
  local t = length / math.max(speed or 0, M.WATCH_MIN_SPEED) * M.WATCH_FACTOR
  return math.min(M.WATCH_MAX, math.max(M.WATCH_MIN, t))
end

function M.drop(state)
  state.flight, state.leftAt, state.flightRandom, state.search = nil, nil, nil, nil
end

function M.clear(state)
  state.flight, state.leftAt, state.lastClock, state.lastCar, state.carVel = nil, nil, nil, nil, nil
  state.flightRandom, state.lastKnown, state.wasGuided, state.sweepAt, state.retargetAt = nil, nil, nil, nil, nil
  state.missingSince, state.searchLogged, state.flightFailed, state.jumpAt = nil, nil, nil, nil
  state.lastKnownVel, state.roofCache, state.search = nil, nil, nil
  state.guidedCheckAt, state.guidedExit, state.guidedKey, state.guidedOn, state.guidedList = nil, nil, nil, nil, nil
end

local function copy(p)
  return vec3(p.x, p.y, p.z)
end

local function moved(p, jx, jy, jz)
  return vec3(p.x + jx, p.y + jy, p.z + jz)
end

local function shiftSearch(s, jx, jy, jz)
  if not s then return end
  s.origin = moved(s.origin, jx, jy, jz)
  if s.run then roadSearch.shift(s.run, jx, jy, jz) end
  for _, c in ipairs(s.list or {}) do c.pos = moved(c.pos, jx, jy, jz) end
end

local function carVelocity(state, target, car, dt, clock)
  local last, kept = state.lastCar, state.carVel
  local jx, jy, jz = flight.jumpOf(last, car)
  local jumped = jx ~= nil
  if jumped then
    local k = state.lastKnown
    if k then state.lastKnown = moved(k, jx, jy, jz) end
    shiftSearch(state.search, jx, jy, jz)
    if state.guidedExit then state.guidedExit = moved(state.guidedExit, jx, jy, jz) end
    for _, c in ipairs(state.guidedList or {}) do c.pos = moved(c.pos, jx, jy, jz) end
    state.jumpAt = clock
  end
  state.lastCar = vec3(car.x, car.y, car.z)
  if kept and (dt <= 0 or jumped) then return kept end
  local v
  if target.getVelocity then
    local tv = target:getVelocity()
    if tv then v = vec3(tv.x, tv.y, tv.z) end
  end
  if not v and last and dt > 0 then
    v = vec3((car.x - last.x) / dt, (car.y - last.y) / dt, (car.z - last.z) / dt)
  end
  v = v or vec3(0, 0, 0)
  state.carVel = v
  return v
end

local function fly(state, phase, last, car, carVel, dt, clock, random)
  local f = state.flight
  if f then flight.step(f, car, carVel, dt) end
  if phase == "tracking" or phase == "searching" then
    if not f then
      state.flightRandom = state.seed and flight.seeded(state.seed) or random
      random = state.flightRandom
      local fresh = last == "arriving" or last == "refuelling" or last == "grounded"
      if phase == "searching" then
        local origin = not state.guided and state.lastKnown or car
        if fresh then
          f = flight.arrive(car, random, carVel, origin)
        else
          f = flight.at(car, carVel, random, origin)
        end
        state.sweepAt, state.retargetAt = clock, clock
      elseif fresh then
        f = flight.arrive(car, random, carVel)
      else
        f = flight.at(car, carVel, random)
      end
      state.flight = f
    elseif f.leaving then
      flight.resume(f)
      state.leftAt = nil
    end
  elseif phase == "refuelling" or phase == "grounded" then
    if f and not f.leaving then
      flight.leave(f, f.spot or f.lead or car, state.flightRandom or random)
      state.leftAt = clock
    end
  elseif f then
    M.drop(state)
  end
end

local function failed(state, err)
  if not state.searchLogged then
    state.searchLogged = true
    log("E", "cnr_heli", "helicopter search failed: " .. tostring(err))
  end
end

local function circle(state, f, car, clock)
  flight.search(f, car)
  state.sweepAt, state.retargetAt = clock, clock
end

local function heading(vel, target)
  local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
  local dirX, dirY = 0, 0
  if speed > 1 then
    dirX, dirY = vel.x, vel.y
  elseif target and target.getDirectionVector then
    local d = target:getDirectionVector()
    if d then dirX, dirY = d.x, d.y end
  end
  return speed, dirX, dirY
end

local function decide(state, pos, vel, target, opts, cached)
  local speed, dirX, dirY = heading(vel, target)
  local roads = opts and opts.roads and opts.roads()
  state.roofCache = state.roofCache or {}
  local list = cached or tunnels.watch(pos, dirX, dirY, roads, opts and opts.roofedAt, state.seed, state.roofCache)
  local s = { mode = "contain", speed = speed, dirX = dirX, dirY = dirY }
  if list and #list > 0 then
    s.mode, s.list, s.i = "tunnel", list, 1
  elseif list == nil and speed >= M.SEARCH_MOVING_SPEED then
    local run = roadSearch.newRun(roadSearch.routes(pos, dirX, dirY, roads, state.seed))
    if #run.routes > 0 then s.mode, s.run = "road", run end
  end
  return s
end

local function choose(state, f, pos, vel, target, clock, opts, cached)
  local ok, s = pcall(decide, state, pos, vel, target, opts, cached)
  if not ok then
    failed(state, s)
    s = { mode = "contain" }
  end
  s.origin, s.since = copy(pos), clock
  state.search = s
  if s.mode == "tunnel" then
    flight.search(f, s.list[1].pos)
  elseif s.mode == "contain" then
    flight.search(f, pos)
  end
  state.sweepAt, state.retargetAt = clock, clock
end

local function roadOut(state, s, here, opts)
  local roads = opts and opts.roads and opts.roads()
  local dirX, dirY = s.dirX or 0, s.dirY or 0
  if here.behind then dirX, dirY = -dirX, -dirY end
  local nodes = roads and roads.nodes
  local a, b = nodes and here.from ~= nil and nodes[here.from], nodes and nodes[here.id]
  if a and b and a.pos and b.pos then
    local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y
    if dx ~= 0 or dy ~= 0 then dirX, dirY = dx, dy end
  end
  local run = roadSearch.newRun(roadSearch.routes(here.pos, dirX, dirY, roads, state.seed, true, here.from))
  if #run.routes > 0 then return run end
end

local function watchTick(state, f, s, clock, opts)
  local here = s.list[s.i]
  if clock - s.since < M.watchSeconds(here.length, s.speed) then return end
  if s.i < #s.list then
    s.i, s.since = s.i + 1, clock
    flight.search(f, s.list[s.i].pos)
    state.sweepAt, state.retargetAt = clock, clock
    return
  end
  local ok, run = pcall(roadOut, state, s, here, opts)
  if not ok then
    failed(state, run)
    run = nil
  end
  s.origin, s.list, s.i, s.since = copy(here.pos), nil, nil, clock
  if run then
    s.mode, s.run = "road", run
    state.sweepAt, state.retargetAt = clock, clock
  else
    s.mode = "contain"
  end
end

local function roadTick(state, f, s, dt, clock)
  local run = s.run
  local index, waiting = run.index, run.waiting
  local p, v = roadSearch.step(run, f.pos, dt)
  if run.index ~= index or run.waiting ~= waiting then state.sweepAt, state.retargetAt = clock, clock end
  if p then
    flight.lead(f, p, v)
    return
  end
  s.mode, s.run = "contain", nil
  s.returning = not roadSearch.withinWaitRadius(f.pos, s.origin)
  flight.search(f, s.origin)
  state.sweepAt, state.retargetAt = clock, clock
end

local function edgeKey(roads, car, dirX, dirY)
  if not (roads and roads.closest and roads.nodes) then return "none" end
  local n1, n2 = roads.closest(car)
  if n1 == nil then return "none" end
  if n2 == nil or n2 == n1 then return tostring(n1) end
  local a, b = tostring(n1), tostring(n2)
  local ida, idb = n1, n2
  if b < a then a, b, ida, idb = b, a, n2, n1 end
  local pa, pb = roads.nodes[ida], roads.nodes[idb]
  local sign = 0
  if pa and pb and pa.pos and pb.pos then
    local dot = (pb.pos.x - pa.pos.x) * dirX + (pb.pos.y - pa.pos.y) * dirY
    sign = dot > 0 and 1 or (dot < 0 and -1 or 0)
  end
  return a .. "|" .. b .. "|" .. sign
end

local function guidedCheck(state, car, vel, target, clock, opts)
  local at = state.guidedCheckAt
  if at and clock - at < M.GUIDED_CHECK_SECONDS then return end
  state.guidedCheckAt = clock
  local roofedAt = opts and opts.roofedAt
  if not roofedAt or roofedAt(vec3(car.x, car.y, car.z + tunnels.ROOF_HEIGHT)) ~= true then
    state.guidedExit, state.guidedKey, state.guidedList = nil, nil, nil
    return
  end
  local _, dirX, dirY = heading(vel, target)
  local roads = opts.roads and opts.roads()
  local key = edgeKey(roads, car, dirX, dirY)
  if key == state.guidedKey then return end
  state.roofCache = state.roofCache or {}
  local list = tunnels.watch(car, dirX, dirY, roads, roofedAt, state.seed, state.roofCache)
  state.guidedExit = list and list[1] and copy(list[1].pos) or nil
  state.guidedList = list
  state.guidedKey = key
end

local function guidedCached(state, car, vel, target, clock, opts)
  local list, at = state.guidedList, state.guidedCheckAt
  if not list or not at or clock - at >= M.GUIDED_CHECK_SECONDS then return nil end
  local ok, key = pcall(function()
    local _, dirX, dirY = heading(vel, target)
    return edgeKey(opts and opts.roads and opts.roads(), car, dirX, dirY)
  end)
  if not ok or key ~= state.guidedKey then return nil end
  local out = {}
  for i, e in ipairs(list) do
    out[i] = { id = e.id, pos = copy(e.pos), from = e.from, length = e.length, turn = e.turn, behind = e.behind }
  end
  return out
end

local function guidedApply(state, f, car, carVel, target, clock, opts)
  local ok, err = pcall(guidedCheck, state, car, carVel, target, clock, opts)
  if not ok then
    failed(state, err)
    state.guidedExit, state.guidedKey = nil, nil
  end
  local exit = state.guidedExit
  if exit then
    local s = f.spot
    if not (state.guidedOn and s and s.x == exit.x and s.y == exit.y and s.z == exit.z) then
      flight.search(f, exit)
      state.sweepAt, state.retargetAt = clock, clock
    end
    state.guidedOn = true
    return
  end
  if state.guidedOn then
    flight.search(f, car)
    state.sweepAt, state.retargetAt = clock, clock
    state.guidedOn = nil
  end
  f.spot, f.spotVel = state.lastCar, carVel
end

local function retarget(state, f, phase, last, car, target, carVel, dt, clock, opts)
  if phase == "tracking" then
    if f.spot or f.lead then
      flight.follow(f, car, carVel)
      state.retargetAt = clock
    end
    state.search = nil
    state.guidedCheckAt, state.guidedExit, state.guidedKey, state.guidedOn, state.guidedList = nil, nil, nil, nil, nil
    state.lastKnown, state.lastKnownVel = state.lastCar, carVel
    return
  end
  if phase ~= "searching" then return end
  local guided = state.guided
  if not guided then state.guidedOn = nil end
  if last == "tracking" then
    if guided then
      circle(state, f, car, clock)
    else
      choose(state, f, car, carVel, target, clock, opts)
    end
  elseif guided and (not state.wasGuided or not f.spot) then
    circle(state, f, car, clock)
  elseif state.wasGuided and not guided then
    choose(state, f, car, carVel, target, clock, opts, guidedCached(state, car, carVel, target, clock, opts))
  elseif not guided and not state.search then
    local k = state.lastKnown
    if k then
      choose(state, f, k, state.lastKnownVel or vec3(0, 0, 0), nil, clock, opts)
    else
      choose(state, f, car, carVel, target, clock, opts)
    end
  end
  if guided then
    state.search = nil
    guidedApply(state, f, car, carVel, target, clock, opts)
    state.lastKnown, state.lastKnownVel = state.lastCar, carVel
    return
  end
  local s = state.search
  if s and s.mode == "tunnel" then watchTick(state, f, s, clock, opts) end
  if s and s.mode == "road" then
    roadTick(state, f, s, dt, clock)
  elseif s and s.returning and roadSearch.withinWaitRadius(f.pos, s.origin) then
    s.returning = nil
    state.sweepAt, state.retargetAt = clock, clock
  end
end

local function flyingAway(phase)
  return phase == "refuelling" or phase == "grounded"
end

function M.tick(state, target, phase, last, clock, opts)
  if not target then
    state.missingSince = state.missingSince or clock
    local f = state.flight
    local ref = f and (f.spot or f.lead or state.lastCar or f.pos)
    if flyingAway(phase) and ref and not f.leaving then
      flight.leave(f, ref, state.flightRandom or state.random or math.random)
      state.leftAt = clock
    end
    local up = phase == "tracking" or phase == "searching" or phase == "refuelling" or phase == "grounded"
    if state.flight and (not up or (state.leftAt and clock - state.leftAt >= flight.DEPART_SECONDS)) then
      M.drop(state)
    end
    return
  end
  local car = target:getPosition()
  if state.missingSince then
    state.lastCar = nil
    if state.flight then state.flight.lastCar = vec3(car.x, car.y, car.z) end
  end
  state.missingSince = nil
  local dt = state.lastClock and clock - state.lastClock or 0
  state.lastClock = clock
  local carVel = carVelocity(state, target, car, dt, clock)
  fly(state, phase, last, car, carVel, dt, clock, state.random or math.random)
  local f = state.flight
  if f then flight.clearance(f, clock, dt) end
  if f and not f.leaving then retarget(state, f, phase, last, car, target, carVel, dt, clock, opts) end
  if state.leftAt and clock - state.leftAt >= flight.DEPART_SECONDS then M.drop(state) end
  state.wasGuided = state.guided
end

function M.roadAim(state, clock)
  local s, f = state.search, state.flight
  if not (f and s and (s.run or s.returning)) then return nil end
  local t = clock - (state.sweepAt or clock)
  local p = f.pos
  local from = s.aimFrom or vec3(0, 0, 0)
  from.x, from.y, from.z = p.x, p.y, (f.nominalZ or p.z) - flight.HELI_HEIGHT
  s.aimFrom = from
  if s.returning then return roadSearch.approachAim(from, s.origin, t) end
  return roadSearch.aimPoint(s.run, t, from)
end

function M.flying(state, clock)
  local f = state.flight
  if not f then return nil end
  local since = state.missingSince
  if since and clock - since > M.TARGET_MISSING_SECONDS then return nil end
  return f
end

function M.soundLevel(state, clock)
  if not M.flying(state, clock) then return 0 end
  local left = state.leftAt
  if left then return math.min(1, math.max(0, (flight.DEPART_SECONDS - (clock - left)) / flight.DEPART_FADE_SECONDS)) end
  return 1
end

return M
