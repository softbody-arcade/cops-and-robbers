local function payload(entry)
  local ok, value = pcall(decodeJson, entry.data)
  if not ok then return "raw:" .. entry.data end
  return serverBoot.encode(value, true)
end

local function sendLine(entry, data)
  return string.format("%.3f %s %s %s", entry.t, entry.to, entry.ev, data)
end

function traceLine(entry)
  if entry.kind == "log" then
    return string.format("%.3f log %s", entry.t, entry.text)
  end
  return sendLine(entry, payload(entry))
end

local function render(stream)
  local lines, group, recipients = {}, {}, {}
  local function flush()
    table.sort(group, function(a, b) return a.to < b.to end)
    for _, send in ipairs(group) do lines[#lines + 1] = send.line end
    group, recipients = {}, {}
  end
  for _, entry in ipairs(stream) do
    if entry.kind == "send" then
      local data = payload(entry)
      local last = group[#group]
      if last and (last.ev ~= entry.ev or last.data ~= data or last.t ~= entry.t or recipients[entry.to]) then
        flush()
      end
      group[#group + 1] = { to = entry.to, ev = entry.ev, data = data, t = entry.t,
        line = sendLine(entry, data) }
      recipients[entry.to] = true
    else
      flush()
      lines[#lines + 1] = entry.kind == "log" and traceLine(entry) or entry.text
    end
  end
  flush()
  return table.concat(lines, "\n") .. "\n"
end

local function clearModules()
  for name in pairs(package.loaded) do
    if name:match("^cnr%.") or name:match("^arcade%.") then package.loaded[name] = nil end
  end
end

local function literalPattern(text)
  return (text:gsub("(%W)", "%%%1"))
end

function traceRun(scenario)
  local globals = {}
  for key, value in pairs(_G) do globals[key] = value end
  local time, date, random, seed, path = os.time, os.date, math.random, math.randomseed, package.path
  local env, call
  local ok, result = xpcall(function()
    local epoch, state = 1795000000, 1
    os.time = function(t) if t == nil then return epoch end return time(t) end
    os.date = function(format, t) return date(format, t or epoch) end
    math.randomseed = function() end
    math.random = function(m, n)
      state = (state * 1103515245 + 12345) % 2147483648
      local fraction = state / 2147483648
      if m == nil then return fraction end
      if n == nil then m, n = 1, m end
      assert(m <= n, "empty random interval")
      return m + math.floor(fraction * (n - m + 1))
    end
    clearModules()
    env = serverBoot.boot(scenario.boot)
    call = env.call
    env.call = function(event, ...)
      env.stream[#env.stream + 1] = { kind = "call", text = "call " .. event }
      local values = table.pack(call(event, ...))
      local parts = { "ret" }
      for i = 1, values.n do parts[i + 1] = tostring(values[i]) end
      env.stream[#env.stream + 1] = { kind = "ret", text = table.concat(parts, " ") }
      return table.unpack(values, 1, values.n)
    end
    scenario.steps(env)
    local versionToken = "%f[%w.]" .. literalPattern(CNR_VERSION) .. "%f[^%w.]"
    return render(env.stream):gsub(literalPattern(env.dir), "<dir>"):gsub(versionToken, "<version>")
  end, debug.traceback)

  clearModules()
  os.time, os.date, math.random, math.randomseed, package.path = time, date, random, seed, path
  for key in pairs(_G) do if globals[key] == nil then _G[key] = nil end end
  for key, value in pairs(globals) do _G[key] = value end
  if env then
    env.call = call
    env.cleanup()
  end
  if not ok then error(result, 0) end
  return result
end

function traceCheck(name, scenario)
  local actual = traceRun(scenario)
  local path = "tests/traces/" .. name .. ".txt"
  if os.getenv("UPDATE_TRACES") == "1" then
    local file = assert(io.open(path, "wb"))
    assert(file:write(actual))
    assert(file:close())
    return
  end
  local file = assert(io.open(path, "rb"))
  local expected = file:read("*a")
  file:close()
  if actual == expected then return end
  local want = (expected .. "\n"):gmatch("(.-)\n")
  local got = (actual .. "\n"):gmatch("(.-)\n")
  local line = 1
  local a, b = want(), got()
  while a == b do
    a, b = want(), got()
    line = line + 1
  end
  error(string.format("%s line %d\nexpected %s\nactual   %s", name, line, a or "<EOF>", b or "<EOF>"), 2)
end
