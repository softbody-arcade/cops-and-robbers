local flight = require("copsAndRobbers/heliFlight")

local M = {}

M.TARGET_MISSING_SECONDS = 2

function M.drop(state)
  state.flight, state.leftAt, state.flightRandom = nil, nil, nil
end

function M.clear(state)
  state.flight, state.leftAt, state.lastClock, state.lastCar, state.carVel = nil, nil, nil, nil, nil
  state.flightRandom, state.lastKnown, state.wasGuided, state.sweepAt, state.retargetAt = nil, nil, nil, nil, nil
  state.missingSince, state.tunnelLogged, state.flightFailed, state.jumpAt = nil, nil, nil, nil
end

local function carVelocity(state, target, car, dt, clock)
  local last, kept = state.lastCar, state.carVel
  local jx, jy, jz = flight.jumpOf(last, car)
  local jumped = jx ~= nil
  if jumped then
    local k = state.lastKnown
    if k then state.lastKnown = vec3(k.x + jx, k.y + jy, k.z + jz) end
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
      local fresh = last == "arriving" or last == "refuelling"
      local known = not state.guided and state.lastKnown or car
      if phase == "searching" then
        if fresh then
          local spot = last == "refuelling" and known or car
          f = flight.arrive(car, random, carVel, spot)
          flight.search(f, spot)
        else
          f = flight.at(car, carVel, random, known)
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
  elseif phase == "refuelling" then
    if f and not f.leaving then
      flight.leave(f, f.spot or car, state.flightRandom or random)
      state.leftAt = clock
    end
  elseif f then
    M.drop(state)
  end
end

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function exitAhead(state, car, target, carVel, tunnelExit)
  local dirX, dirY = 0, 0
  if carVel.x * carVel.x + carVel.y * carVel.y > 1 then
    dirX, dirY = carVel.x, carVel.y
  elseif target.getDirectionVector then
    local d = target:getDirectionVector()
    if d then dirX, dirY = d.x, d.y end
  end
  local r = tunnelExit(car, dirX, dirY, state.seed)
  if not r then return nil end
  return r.x, r.y, r.z
end

local function spotFor(state, car, target, carVel, opts)
  local tunnelExit = opts and opts.tunnelExit
  if tunnelExit then
    local ok, x, y, z = pcall(exitAhead, state, car, target, carVel, tunnelExit)
    if not ok then
      if not state.tunnelLogged then
        state.tunnelLogged = true
        log("E", "cnr_heli", "tunnel exit failed: " .. tostring(x))
      end
    elseif finite(x) and finite(y) and finite(z) then
      return vec3(x, y, z)
    end
  end
  return vec3(car.x, car.y, car.z)
end

local function retarget(state, f, phase, last, car, target, carVel, clock, opts)
  if phase == "tracking" then
    if f.spot then
      flight.follow(f, car, carVel)
      state.retargetAt = clock
    end
    state.lastKnown = vec3(car.x, car.y, car.z)
    return
  end
  if phase ~= "searching" then return end
  local spot
  if last == "tracking" then
    spot = state.guided and car or spotFor(state, car, target, carVel, opts)
  elseif state.guided and not state.wasGuided then
    spot = car
  elseif state.wasGuided and not state.guided then
    spot = spotFor(state, car, target, carVel, opts)
  elseif f.spot == nil then
    spot = state.lastKnown or car
  end
  if spot then
    flight.search(f, spot)
    state.sweepAt, state.retargetAt = clock, clock
  end
  if state.guided then
    f.spot = vec3(car.x, car.y, car.z)
    f.spotVel = vec3(carVel.x, carVel.y, carVel.z)
    state.lastKnown = vec3(car.x, car.y, car.z)
  else
    f.spotVel = vec3(0, 0, 0)
  end
end

function M.tick(state, target, phase, last, clock, opts)
  if not target then
    state.missingSince = state.missingSince or clock
    if phase == "refuelling" then state.lightPhase = phase end
    local f = state.flight
    local ref = f and (f.spot or state.lastCar)
    if phase == "refuelling" and ref and not f.leaving then
      flight.leave(f, ref, state.flightRandom or state.random or math.random)
      state.leftAt = clock
    end
    local up = phase == "tracking" or phase == "searching" or phase == "refuelling"
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
  if f and not f.leaving then retarget(state, f, phase, last, car, target, carVel, clock, opts) end
  if state.leftAt and clock - state.leftAt >= flight.DEPART_SECONDS then M.drop(state) end
  state.wasGuided = state.guided
end

function M.soundLevel(state, clock)
  if not state.flight then return 0 end
  local since = state.missingSince
  if since and clock - since > M.TARGET_MISSING_SECONDS then return 0 end
  local left = state.leftAt
  if left then return math.min(1, math.max(0, (flight.DEPART_SECONDS - (clock - left)) / flight.DEPART_FADE_SECONDS)) end
  return 1
end

return M
