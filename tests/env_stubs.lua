local function v3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end

local function model(static, sliding, roughness, depth)
  local cdata = {
    staticFrictionCoefficient = static, slidingFrictionCoefficient = sliding,
    roughnessCoefficient = roughness, defaultDepth = depth or 0,
    hydrodynamicFriction = 0.1 + roughness / 10, stribeckVelocity = 4 + roughness,
    strength = 1 + roughness, fluidDensity = 100 * roughness, flowConsistencyIndex = 10 * roughness,
    flowBehaviorIndex = 1 - roughness / 2, dragAnisotropy = roughness / 4, shearStrength = 1000 * roughness,
  }
  return { cdata = cdata }
end

local function alias(parent, name)
  return { cdata = parent.cdata, isAlias = true, parent = name }
end

local TIMES = { sunrise = 0.775, morning = 0.825, noon = 0, afternoon = 0.175, sunset = 0.245, night = 0.5 }

function fakeEnvironment(opts)
  opts = opts or {}
  _G.vec3 = _G.vec3 or v3
  _G.log = _G.log or function() end
  local fake = {
    locked = opts.locked or false,
    setStates = {}, profiles = {}, modelSets = {}, queued = {}, groundWinds = {},
    objects = {}, deleted = {}, lerps = {}, resets = 0, resetAt = {},
  }
  fake.state = {
    time = 0.1, play = true, dayLength = 1800, cloudCover = 0.3, fogDensity = 1,
    windSpeed = 1, groundWind = v3(0, 0, 0), temperatureCurveOverrideC = false,
    latitude = 37.77, year = 2025, month = 6, day = 20,
  }
  fake.init = {}
  for k, v in pairs(fake.state) do fake.init[k] = v end

  local models = {}
  models.ASPHALT = model(0.98, 0.70, 0)
  models.CONCRETE = alias(models.ASPHALT, "ASPHALT")
  models.ASPHALT_WET = model(0.92, 0.55, 0.2)
  models.RUMBLE_STRIP = model(0.98, 0.70, 0.5)
  models.GRAVEL = model(0.69, 0.74, 0.44)
  models.GRAVEL_WET = model(0.62, 0.60, 0.38)
  models.DIRT = model(0.70, 0.73, 0.42)
  models.DIRT_GRASS = alias(models.DIRT, "DIRT")
  models.MUD = model(0.55, 0.55, 0.5, 0.15)
  models.GRASS = model(0.61, 0.65, 0.43)
  models.SNOW = model(0.65, 0.40, 0.3)
  models.SAND = model(0.6, 0.6, 0.5)
  fake.models = models

  local env = { groundModels = models, timeOfDayKeyToTime = TIMES }
  function env.getState()
    local copy = {}
    for k, v in pairs(fake.state) do copy[k] = v end
    return copy
  end
  function env.getInitState() return fake.init end
  function env.setState(s, seconds)
    if s == nil then
      fake.resets = fake.resets + 1
      fake.resetAt[fake.resets] = #fake.setStates
      return
    end
    if fake.locked then return end
    fake.lerps[#fake.setStates + 1] = seconds
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    if s.groundWind then
      fake.state.groundWind.x, fake.state.groundWind.y, fake.state.groundWind.z = s.groundWind.x, s.groundWind.y, s.groundWind.z
    end
    for k, v in pairs(s) do
      if k ~= "groundWind" then fake.state[k] = v end
    end
    fake.setStates[#fake.setStates + 1] = copy
  end
  function env.enableChanges(b) fake.locked = not b end
  function env.canChange() return not fake.locked end
  function env.getSolarTimeOfDayValue(key, state)
    fake.solarState = state
    return TIMES[key]
  end
  function env.setTemperatureProfile(p)
    if fake.locked then return end
    fake.profiles[#fake.profiles + 1] = p
  end
  function env.getLightState() return { isNight = fake.state.time > 0.25 and fake.state.time < 0.75 } end
  _G.core_environment = env

  fake.init.groundWind = fake.state.groundWind

  _G.be = {
    setGroundModel = function(_, name, cdata)
      fake.modelSets[#fake.modelSets + 1] = {
        name = name, static = cdata.staticFrictionCoefficient, sliding = cdata.slidingFrictionCoefficient,
      }
    end,
    queueAllObjectLua = function(_, cmd) fake.queued[#fake.queued + 1] = cmd end,
    setGroundWind = function(_, v) fake.groundWinds[#fake.groundWinds + 1] = v end,
  }

  _G.createObject = function()
    local obj = { fields = {}, name = nil }
    function obj:setField(name, _, value) self.fields[name] = value end
    function obj:getField(name)
      if name == "numDrops" and self.numDrops then return tostring(self.numDrops) end
      return self.fields[name]
    end
    function obj:play() self.playing = true end
    function obj:stop() self.playing = false end
    function obj:setVolumePitchCT(v) self.volume = v end
    function obj:setTransform() end
    function obj:registerObject(name) self.name = name; fake.objects[name] = self end
    function obj:delete()
      if self.name then
        fake.objects[self.name] = nil
        fake.deleted[#fake.deleted + 1] = self.name
      end
    end
    return obj
  end
  _G.scenetree = {
    findObject = function(name) return fake.objects[name] end,
    MissionGroup = { addObject = function() end },
  }
  return fake
end
