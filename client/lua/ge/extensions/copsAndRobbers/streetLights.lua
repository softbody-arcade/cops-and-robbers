local M = {}

local CELL_SIZE = 32
local CELL_LIMIT = 16
local INDEX_LIMIT = 128
local CANDIDATE_LIMIT = 8
local CHILD_FIELD_LIMIT = 256
local CLEAR_MARGIN = 0.5
local extentFields = {PointLight = "radius", SpotLight = "range"}
local classes = {"PointLight", "SpotLight", "TSStatic"}
local booleanStrings = {
  ["1"] = true, ["true"] = true, yes = true, on = true,
  ["0"] = false, ["false"] = false, no = false, off = false,
}

local started, queue, nextName, lastSceneName, indexed
local cells = {}

local function read(getter, ...)
  if type(getter) ~= "function" then return nil end
  local ok, value = pcall(getter, ...)
  if ok then return value end
end

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validVector(value)
  local kind = type(value)
  return (kind == "table" or kind == "userdata" or kind == "cdata")
    and finite(value.x) and finite(value.y) and finite(value.z)
end

local function classOf(object)
  return object.className or read(object.getClassName, object)
end

local function idOf(object)
  return read(object.getID, object) or read(object.getId, object)
end

local function fieldAt(object, field, index)
  local value = read(object.getDynDataFieldbyName, object, field, index)
  if value ~= nil and value ~= "" then return value end
  value = read(object.getField, object, field, index)
  if value ~= "" then return value end
end

local function numberField(object, field)
  local value = object[field]
  if value == nil or value == "" then value = fieldAt(object, field, 0) end
  local number = tonumber(value)
  if finite(number) then return number end
end

local function parseBool(value)
  local kind = type(value)
  if kind == "boolean" then return value end
  if kind == "number" and finite(value) then return value ~= 0 end
  if kind == "string" then return booleanStrings[value:lower()] end
end

local function boolField(object, field)
  local value = parseBool(object[field])
  if value ~= nil then return value end
  return parseBool(fieldAt(object, field, 0))
end

local function queueChildren(fixture)
  for index = 0, CHILD_FIELD_LIMIT - 1 do
    local value = fieldAt(fixture, "child", index)
    if value == nil then break end
    for name in tostring(value):gmatch("[^,%s]+") do
      queue[#queue + 1] = name
    end
  end
end

local function indexEmitter(object, class)
  local id = idOf(object)
  if not finite(id) or indexed[id] then return end
  local name = read(object.getName, object)
  local position = read(object.getPosition, object)
  if type(name) ~= "string" or name == "" or not validVector(position) then return end

  indexed[id] = true
  local x, y = math.floor(position.x / CELL_SIZE), math.floor(position.y / CELL_SIZE)
  cells[x] = cells[x] or {}
  local column = cells[x]
  column[y] = column[y] or {}
  local cell = column[y]
  local insertAt = #cell + 1
  while insertAt > 1 and cell[insertAt - 1].id > id do
    insertAt = insertAt - 1
  end
  if insertAt > CELL_LIMIT then return end
  table.insert(cell, insertAt, {id = id, name = name, class = class})
  cell[CELL_LIMIT + 1] = nil
end

function M.beginMissionIndex()
  if started then return end
  started, queue, nextName, indexed = true, {}, 1, {}
  for _, class in ipairs(classes) do
    local names = read(scenetree and scenetree.findClassObjects, class)
    for _, name in ipairs(names or {}) do queue[#queue + 1] = name end
  end
  lastSceneName = #queue
end

function M.advance()
  if not queue then return end
  for _ = 1, INDEX_LIMIT do
    local name = queue[nextName]
    if not name then
      queue, nextName, lastSceneName, indexed = nil, nil, nil, nil
      return
    end
    local linked = nextName > lastSceneName
    nextName = nextName + 1
    local object = read(scenetree and scenetree.findObject, name)
    if object then
      local class = classOf(object)
      if class == "TSStatic" and not linked then
        queueChildren(object)
      elseif extentFields[class] and (linked or boolField(object, "nightLight")
          or (numberField(object, "nightIntensity") or 0) > 0) then
        indexEmitter(object, class)
      end
    end
  end
end

local function candidate(entry, target)
  local object = read(scenetree and scenetree.findObjectById, entry.id)
  if not object or idOf(object) ~= entry.id or read(object.getName, object) ~= entry.name
      or classOf(object) ~= entry.class then return nil end
  local position = read(object.getPosition, object)
  if not validVector(position) then return nil end
  local dx, dy, dz = target.x - position.x, target.y - position.y, target.z - position.z
  local distanceSquared = dx * dx + dy * dy + dz * dz
  if distanceSquared >= CELL_SIZE * CELL_SIZE then return nil end
  return {
    id = entry.id, class = entry.class, object = object, position = position,
    dx = dx, dy = dy, dz = dz, distanceSquared = distanceSquared,
  }
end

local function nearestFirst(a, b)
  if a.distanceSquared == b.distanceSquared then return a.id < b.id end
  return a.distanceSquared < b.distanceSquared
end

local function insideCone(object, dx, dy, dz, distance)
  local angle = numberField(object, "outerAngle")
  if not angle or angle <= 0 or angle > 180 then return false end
  local transform = read(object.getTransform, object)
  local axis = read(transform and transform.getColumn, transform, 1)
  if not validVector(axis) then return false end
  local length = math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
  if not finite(length) or length == 0 then return false end
  if distance == 0 then return true end
  local cosine = (dx * axis.x + dy * axis.y + dz * axis.z) / (distance * length)
  return cosine >= math.cos(math.rad(angle * 0.5))
end

local function clearStrength(light, cast)
  local object = light.object
  local enabled = parseBool(read(object.getLightEnabled, object))
  if enabled == nil then enabled = boolField(object, "isEnabled") end
  if not enabled or (numberField(object, "intensity") or 0) <= 0 then return 0 end
  local extent = numberField(object, extentFields[light.class])
  if not extent or extent <= 0 then return 0 end
  extent = math.min(extent, CELL_SIZE)
  local distance = math.sqrt(light.distanceSquared)
  if distance >= extent then return 0 end
  local dx, dy, dz = light.dx, light.dy, light.dz
  if light.class == "SpotLight" and not insideCone(object, dx, dy, dz, distance) then return 0 end

  local position = light.position
  local origin = vec3(position.x, position.y, position.z)
  local direction = distance > 0 and vec3(dx / distance, dy / distance, dz / distance) or vec3(0, 0, 1)
  local hit = read(cast, origin, direction, distance)
  if not finite(hit) or hit < 0 or hit < distance - CLEAR_MARGIN then return 0 end
  return math.min(1, 2 * (1 - distance / extent))
end

function M.strength(targetCenter, cast)
  if not validVector(targetCenter) or type(cast) ~= "function" then return 0 end
  local cellX, cellY = math.floor(targetCenter.x / CELL_SIZE), math.floor(targetCenter.y / CELL_SIZE)
  local candidates = {}
  for offsetX = -1, 1 do
    local column = cells[cellX + offsetX]
    if column then
      for offsetY = -1, 1 do
        for _, entry in ipairs(column[cellY + offsetY] or {}) do
          local light = candidate(entry, targetCenter)
          if light then candidates[#candidates + 1] = light end
        end
      end
    end
  end
  table.sort(candidates, nearestFirst)
  local strongest = 0
  for i = 1, math.min(#candidates, CANDIDATE_LIMIT) do
    strongest = math.max(strongest, clearStrength(candidates[i], cast))
  end
  return strongest
end

function M.clear()
  started, queue, nextName, lastSceneName, indexed = nil, nil, nil, nil, nil
  cells = {}
end

return M
