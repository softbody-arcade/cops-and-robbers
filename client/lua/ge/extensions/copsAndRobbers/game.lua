local M = {}

function M.sendServer(event, payload)
  if TriggerServerEvent then TriggerServerEvent(event, jsonEncode(payload or {})) end
end

function M.ownVehicle()
  local veh = getPlayerVehicle(0)
  if veh and MPVehicleGE and MPVehicleGE.isOwn(veh:getID()) then return veh end
  return nil
end

function M.serverVid(veh)
  local v = MPVehicleGE and MPVehicleGE.getVehicleByGameID and MPVehicleGE.getVehicleByGameID(veh:getID())
  local s = v and v.serverVehicleString
  return s and tonumber(s:match("%-(%d+)$"))
end

function M.uprightRotation(veh)
  local dir = veh:getDirectionVector()
  dir = vec3(dir.x, dir.y, 0)
  if dir:length() < 1e-3 then dir = vec3(0, 1, 0) end
  return quatFromDir(dir:normalized(), vec3(0, 0, 1))
end

function M.carName(model)
  local ok, m = pcall(core_vehicles.getModel, model)
  local info = ok and type(m) == "table" and m.model
  if type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
    local brand = type(info.Brand) == "string" and info.Brand ~= "" and (info.Brand .. " ") or ""
    return brand .. info.Name
  end
  return tostring(model)
end

function M.mapTitle(id)
  local title
  if core_levels and core_levels.getLevelTitle then
    local ok, t = pcall(core_levels.getLevelTitle, id)
    if ok and type(t) == "string" and t ~= "" then title = t end
  end
  local pretty
  if id == "beamng_earth" then
    pretty = "BeamNG.Earth"
  else
    local words = {}
    for word in tostring(id):gmatch("[^_]+") do
      words[#words + 1] = (word == "usa" or word == "uk") and word:upper() or (word:sub(1, 1):upper() .. word:sub(2))
    end
    pretty = table.concat(words, " ")
  end
  return { id = id, title = title, pretty = pretty }
end

return M
