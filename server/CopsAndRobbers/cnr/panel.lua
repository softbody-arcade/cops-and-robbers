local config = require("cnr.config")

local M = {}

M.COMMANDS = {
  ["go"] = true, ["reroll"] = true, ["end"] = true, ["stop"] = true, ["auto on"] = true, ["auto off"] = true,
  ["test runner"] = true, ["test cop"] = true, ["reload"] = true, ["next"] = true, ["sky"] = true,
}

local MAX_COMMAND_LENGTH = 64

function M.allow(text)
  if type(text) ~= "string" then return nil end
  local t = text:match("^%s*(.-)%s*$")
  if #t > MAX_COMMAND_LENGTH then return nil end
  local lower = t:lower()
  if M.COMMANDS[lower] then return lower end
  if lower:match("^start %S") then return "start " .. t:sub(7) end
  return nil
end

function M.can(state, test, evolving, skyRandom)
  return {
    start = state == "idle" or test == true,
    reroll = state == "prep" and not evolving,
    sky = (state == "prep" or state == "ready") and skyRandom == true,
    go = (state == "prep" and not evolving) or state == "ready",
    apply = state == "prep" and evolving == true,
    build = state == "idle",
    ["end"] = state == "running",
    stop = state ~= "idle",
    test = state == "idle",
    settings = state == "idle",
  }
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end

function M.playerRows(entries, nextName, lastName)
  local rows = {}
  for _, e in ipairs(entries or {}) do
    rows[#rows + 1] = {
      name = e.name, runs = e.runs or 0, next = e.name == nextName, last = e.name == lastName,
      role = e.role, state = e.state, change = e.change, missing = e.missing, sitOut = e.sitOut,
    }
  end
  table.sort(rows, function(a, b)
    local la, lb = tostring(a.name):lower(), tostring(b.name):lower()
    if la ~= lb then return la < lb end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

function M.goBlocked(phase, evolving, runnerName, loading)
  if not evolving then return nil end
  if phase == "prep" then return "Waiting for " .. (runnerName or "the runner") .. " to apply the change" end
  if phase == "applying" then
    if loading and loading > 0 then return string.format("Applying the change: %d %s still loading", loading, loading == 1 and "car" or "cars") end
    return "Applying the change"
  end
  return nil
end

function M.snapshot(info)
  local cfg = info.cfg or {}
  return {
    version = info.version,
    map = info.map,
    phase = info.phase,
    runner = info.runner,
    car = info.car,
    test = info.test == true,
    elapsed = info.elapsed and math.floor(info.elapsed) or nil,
    players = M.playerRows(info.players, info.nextRunner, info.lastRunner),
    settings = copy(cfg),
    defaults = copy(info.defaults or {}),
    auto = cfg.autoNextRound == true,
    can = M.can(info.phase, info.test, info.evolving, info.skyRandom),
    evolving = info.evolving == true,
    build = info.build,
    nextRunner = info.nextRunner,
    lastRunner = info.lastRunner,
    goBlocked = M.goBlocked(info.phase, info.evolving, info.runner, info.loading),
    autoNext = info.autoNext,
    lastResult = info.lastResult,
    stationCount = info.stationCount or 0,
    trafficNote = info.trafficNote,
  }
end

function M.signature(t)
  if type(t) ~= "table" then
    return type(t) == "string" and string.format("%q", t) or tostring(t)
  end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. M.signature(t[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function validListValue(v)
  if type(v) == "string" then return true end
  if type(v) ~= "table" then return false end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n ~= #v then return false end
  for _, item in ipairs(v) do
    if type(item) ~= "string" and type(item) ~= "number" then return false end
  end
  return true
end

local function toText(v)
  if type(v) == "number" then return string.format("%.10g", v) end
  if type(v) == "table" then
    local items = {}
    for _, item in ipairs(v) do items[#items + 1] = tostring(item) end
    return table.concat(items, ", ")
  end
  return tostring(v)
end

function M.applyValues(raw, values)
  if type(values) ~= "table" then return nil, "Nothing to save" end
  local keys = {}
  for k in pairs(values) do
    if type(k) ~= "string" then return nil, "Nothing to save" end
    keys[#keys + 1] = k
  end
  if #keys == 0 then return nil, "Nothing to save" end
  table.sort(keys, function(a, b)
    local am, bm = a == "weatherChangeMinMinutes", b == "weatherChangeMinMinutes"
    if am ~= bm then return am end
    return a < b
  end)
  for _, key in ipairs(keys) do
    if type(config.DEFAULTS[key]) == "table" and not validListValue(values[key]) then
      return nil, "Invalid value for " .. key
    end
  end
  local updated, pending = raw or {}, keys
  while #pending > 0 do
    local failed, firstErr = {}, nil
    for _, key in ipairs(pending) do
      local nextCfg, err = config.setValue(updated, key, toText(values[key]))
      if nextCfg then
        updated = nextCfg
      else
        failed[#failed + 1] = key
        firstErr = firstErr or err
      end
    end
    if #failed == #pending then return nil, firstErr end
    pending = failed
  end
  local _, warnings = config.merge(updated)
  for _, w in ipairs(warnings) do
    for _, key in ipairs(keys) do
      if w:find(key .. " ", 1, true) == 1 then return nil, "Invalid value for " .. key .. ": " .. toText(values[key]) end
    end
  end
  return updated, keys
end

return M
