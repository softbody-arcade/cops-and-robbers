local game = require("copsAndRobbers/game")
local M = {}
local RETRY_SECONDS = 2
local REFRESH_SECONDS = 30
local serial = 0

function M.new(seed)
  return {seed = seed, nextProbe = 0}
end

function M.frame(clock)
  local now = Engine.Platform.getRuntime()
  if now >= clock.nextProbe then
    serial = serial + 1
    clock.id, clock.sentAt, clock.nextProbe = serial, now, now + RETRY_SECONDS
    game.sendServer("cnr_lightningClock", {seed = clock.seed, id = serial})
  end
  if not clock.offset then return end
  local previous = clock.previous
  clock.previous = math.max(previous, now + clock.offset)
  return previous, clock.previous
end

function M.receive(clock, reply)
  if not (clock and clock.id and type(reply) == "table" and reply.id == clock.id and reply.seed == clock.seed) then return end
  local elapsed = reply.elapsed
  if type(elapsed) ~= "number" or not (elapsed >= 0 and elapsed < math.huge) then return end
  local now = Engine.Platform.getRuntime()
  local roundTrip = now - clock.sentAt
  clock.id = nil
  if clock.offset then clock.nextProbe = now + REFRESH_SECONDS end
  if roundTrip < 0 or roundTrip >= RETRY_SECONDS then return end
  if clock.bestRoundTrip and roundTrip > clock.bestRoundTrip + 0.05 then return end
  clock.bestRoundTrip = math.min(roundTrip, clock.bestRoundTrip or roundTrip)
  local estimate = elapsed + roundTrip / 2
  clock.offset = estimate - now
  clock.previous = clock.previous or estimate
end

return M
