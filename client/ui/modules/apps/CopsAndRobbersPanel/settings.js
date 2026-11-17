import { ref } from "vue"
import { formatTime } from "../../copsAndRobbers/format.js"

export const GROUPS = [
  { title: "Round", items: [
    { key: "headStartSeconds", label: "Head start", unit: "s", step: 1, min: 0, common: true,
      help: "Cops stay frozen this long after the runner goes" },
    { key: "roundTimeLimitSeconds", label: "Time limit", unit: "s", step: 60, min: 0, common: true, offAtZero: true, duration: true,
      help: "The runner escapes after this long in the chase; off means no limit" },
    { key: "runnerCountdownSeconds", label: "Runner countdown", unit: "s", step: 1, min: 0,
      help: "Countdown after GO before the runner may drive" },
    { key: "autoNextDelaySeconds", label: "Next round delay", unit: "s", step: 5, min: 0,
      help: "With automatic rounds on, the wait before the next round" },
  ] },
  { title: "Sky", noEarth: true, items: [
    { key: "timeOfDay", label: "Time of day", kind: "choice", common: true,
      options: [["sunrise", "Sunrise"], ["morning", "Morning"], ["noon", "Noon"], ["afternoon", "Afternoon"], ["sunset", "Sunset"], ["night", "Night"], ["random", "Random"]],
      help: "The time the chase is played at (with a moving clock it starts just before); random follows the night chance" },
    { key: "nightChancePercent", label: "Night chance", unit: "%", step: 5, min: 0, max: 100, common: true, when: v => v("timeOfDay") === "random",
      help: "How often a random time of day is night" },
    { key: "dayLength", label: "Day length", kind: "choice",
      options: [["off", "Off"], ["fast", "Fast (15 min)"], ["moderate", "Moderate (30 min)"], ["slow", "Slow (2 h)"], ["realtime", "Realtime (24 h)"]],
      help: "How long a full day lasts once the chase starts" },
    { key: "weather", label: "Weather", kind: "choice", common: true,
      options: [["clear", "Clear"], ["cloudy", "Cloudy"], ["rain", "Rain"], ["storm", "Storm"], ["fog", "Fog"], ["snow", "Snow"], ["random", "Random"]],
      help: "Random follows the bad weather chance" },
    { key: "badWeatherChancePercent", label: "Bad weather chance", unit: "%", step: 5, min: 0, max: 100, common: true, when: v => v("weather") === "random",
      help: "How often random weather is rain, storm, fog or snow" },
    { key: "weatherDriving", label: "Weather affects driving", kind: "bool",
      help: "Rain, storm and snow change grip and bring gusty wind" },
    { key: "weatherChanges", label: "Weather changes", kind: "bool",
      help: "The weather changes during the chase when the day allows it" },
    { key: "weatherChangeMinMinutes", label: "Shortest between changes", unit: "min", step: 1, min: 1, when: v => v("weatherChanges"),
      help: "The least time between two weather changes" },
    { key: "weatherChangeMaxMinutes", label: "Longest between changes", unit: "min", step: 1, min: 1, when: v => v("weatherChanges"),
      help: "The most time between two weather changes; never below the shortest" },
  ] },
  { title: "Traffic", noEarth: true, items: [
    { key: "trafficPerPlayer", label: "Traffic", unit: "per player", step: 1, min: 0, max: 20, common: true, offAtZero: true,
      help: "AI traffic cars around each player during a round",
      vary: v => v("trafficRunnerOnly") === true && { unit: "for the runner", help: "AI traffic cars around the runner during a round" } },
    { key: "trafficRunnerOnly", label: "Traffic for the runner only", kind: "bool", common: true, when: v => Number(v("trafficPerPlayer")) > 0,
      help: "Only the runner's game spawns traffic; cops see it as the chase gets close. Fewer AI cars, better performance" },
  ] },
  { title: "Catching", items: [
    { key: "catchHoldSeconds", label: "Hold time", unit: "s", step: 1, min: 1, common: true,
      help: "How long cops must hold the runner to catch them" },
    { key: "catchRadiusMeters", label: "Catch distance", unit: "m", step: 1, min: 1, common: true,
      help: "A cop this close to the runner counts as holding" },
    { key: "catchMaxSpeedKmh", label: "Catch speed", unit: "km/h", step: 1, min: 1,
      help: "The runner counts as held below this speed, or when they rock back and forth within 3 m in 4 s" },
    { key: "explodeOnCatch", label: "Explode on catch", kind: "bool",
      help: "The runner's car blows up when they are caught" },
  ] },
  { title: "Resets", items: [
    { key: "resetWaitSeconds", label: "Reset wait", unit: "s", step: 1, min: 0, common: true,
      help: "Stand still this long and a reset is allowed anywhere" },
    { key: "stillMaxSpeedKmh", label: "Still speed", unit: "km/h", step: 0.5, min: 0.5,
      help: "Slower than this counts as standing still" },
    { key: "copResetMinDistanceMeters", label: "Cop reset distance", unit: "m", step: 100, min: 0,
      help: "Cops this far from the runner may always reset and get no crash penalty" },
    { key: "gasStationRadiusMeters", label: "Gas station size", unit: "m", step: 5, min: 0,
      help: "How close to a gas station counts as being at it" },
  ] },
  { title: "Crashes", items: [
    { key: "crashPenaltySeconds", label: "Crash penalty", unit: "s", step: 1, min: 0, common: true,
      help: "A cop who crashes into someone closer to the runner than the cop reset distance is frozen this long" },
    { key: "crashSpeedLossKmh", label: "Crash speed loss", unit: "km/h", step: 5, min: 5,
      help: "Losing this much speed in half a second counts as a crash" },
  ] },
  { title: "Cops", items: [
    { key: "copSpawnMinMeters", label: "Start distance min", unit: "m", step: 10, min: 0,
      help: "Cops start at least this far from the runner, by road" },
    { key: "copSpawnMaxMeters", label: "Start distance max", unit: "m", step: 10, min: 0,
      help: "Cops start at most this far from the runner, by road" },
    { key: "sightMaxMeters", label: "Sight range", unit: "m", step: 50, min: 0, offAtZero: true,
      help: "How far cops can see the runner; off means no sight" },
    { key: "sightLiveIntervalSeconds", label: "Live position every", unit: "s", step: 1, min: 1,
      help: "How often cops get the runner's position while one sees them" },
    { key: "sightGraceSeconds", label: "Sight grace", unit: "s", step: 0.5, min: 0,
      help: "Sight still counts this long after a cop loses it" },
    { key: "sightNoRouteSeconds", label: "No route within", unit: "s", step: 1, min: 0,
      help: "No route for a cop who sees the runner within this many seconds of driving" },
    { key: "sightNoRouteMinMeters", label: "No route minimum", unit: "m", step: 10, min: 0,
      help: "No route for a cop who sees the runner this close" },
    { key: "assistMinSightPercent", label: "Assist needs sight", unit: "%", step: 5, min: 0, max: 100,
      help: "Share of the chase a cop needs the runner in sight for an assist" },
    { key: "sirensAllowed", label: "Cop sirens", kind: "bool",
      help: "Cops may turn a siren on in their settings; off keeps every cop silent" },
  ] },
  { title: "Helicopter", items: [
    { key: "helicopter", label: "Police helicopter", kind: "bool",
      help: "Searches for the runner and tracks them while it sees them; grounded in storm, fog and snow" },
    { key: "helicopterArrivalSeconds", label: "Arrives after", unit: "s", step: 15, min: 0, duration: true, zeroText: "at release",
      when: v => v("helicopter"), help: "How long after the cops are released the helicopter arrives" },
    { key: "helicopterUpSeconds", label: "Time up", unit: "s", step: 15, min: 15, duration: true,
      when: v => v("helicopter"), help: "How long the helicopter flies before it must refuel" },
    { key: "helicopterRefuelSeconds", label: "Refuel", unit: "s", step: 15, min: 0, duration: true, zeroText: "stays up",
      when: v => v("helicopter"), help: "How long it is away refuelling; 0 means it stays up once it has arrived" },
  ] },
  { title: "Cars", items: [
    { key: "includeModVehicles", label: "Include mod cars", kind: "bool",
      help: "Cars from mods can be picked too" },
    { key: "excludedModels", label: "Excluded cars", kind: "list",
      help: "Model names that are never picked, separated by commas" },
  ] },
]

export const MODE_ITEM = { key: "carMode", label: "Car mode", kind: "mode" }

const KNOWN = new Set(GROUPS.flatMap(g => g.items.map(i => i.key)).concat(["autoNextRound", "carMode"]))
const SAVE_DELAY_MS = 500

function norm(v) {
  return v && typeof v === "object" && !Array.isArray(v) && !Object.keys(v).length ? [] : v
}

export function same(a, b) {
  return JSON.stringify(norm(a)) === JSON.stringify(norm(b))
}

export function listText(v) {
  return Array.isArray(v) ? v.join(", ") : ""
}

export function shown(item, v) {
  if (item.kind === "mode") return v === "evolving" ? "evolving build" : "random car"
  if (item.kind === "bool") return v ? "on" : "off"
  if (item.kind === "list") return listText(v) || "none"
  if (item.kind === "choice") {
    const o = item.options.find(p => p[0] === v)
    return o ? o[1] : "–"
  }
  const n = Number(v)
  if (v === undefined || v === null || !Number.isFinite(n)) return "–"
  if (item.zeroText && n === 0) return item.zeroText
  if (item.offAtZero && n === 0) return "off"
  if (item.duration) return n % 60 === 0 ? `${n / 60} min` : formatTime(n)
  return `${n} ${item.unit || ""}`.trim()
}

export function liveItem(item, valueOf) {
  const change = item.vary && item.vary(valueOf)
  return change ? { ...item, ...change } : item
}

export function settingGroups(settings) {
  const other = Object.keys(settings || {})
    .filter(k => !KNOWN.has(k))
    .sort()
    .map(k => {
      const v = settings[k]
      const help = "A setting this panel doesn't know yet"
      if (typeof v === "boolean") return { key: k, label: k, kind: "bool", help }
      if (typeof v === "object") return { key: k, label: k, kind: "list", help }
      return { key: k, label: k, unit: "", step: 1, min: 0, help }
    })
  return other.length ? [...GROUPS, { title: "Other", items: other }] : GROUPS
}

function stepped(item, current, dir) {
  if (item.kind === "choice") {
    const i = item.options.findIndex(p => p[0] === current)
    return item.options[(Math.max(i, 0) + dir + item.options.length) % item.options.length][0]
  }
  const q = (Number(current) || 0) / item.step
  const onGrid = Math.abs(q - Math.round(q)) < 1e-6
  const n = onGrid ? Math.round(q) + dir : dir > 0 ? Math.ceil(q) : Math.floor(q)
  const value = Math.max(item.min, Math.round(n * item.step * 10000) / 10000)
  return item.max === undefined ? value : Math.min(item.max, value)
}

export function useSettings(state, send, beforeSend) {
  const pending = ref({})
  const drafts = ref({})
  let inFlight = []
  let nextRequestId = Date.now() % 1000000000
  let saveTimer = null

  const settings = () => state.value.settings || {}
  const defaults = () => state.value.defaults || {}

  function valueOf(key) {
    return key in pending.value ? pending.value[key] : settings()[key]
  }

  function hasDefault(key) {
    return key in defaults()
  }

  function defaultOf(key) {
    return defaults()[key]
  }

  function changed(key) {
    return hasDefault(key) && valueOf(key) !== undefined && !same(valueOf(key), defaultOf(key))
  }

  function itemFor(key) {
    if (key === MODE_ITEM.key) return MODE_ITEM
    for (const g of settingGroups(settings())) {
      const item = g.items.find(i => i.key === key)
      if (item) return item
    }
    return { key, label: key, unit: "" }
  }

  function save(values, reset) {
    const id = nextRequestId++
    inFlight.push({ id, keys: Object.keys(values), values, reset })
    beforeSend()
    send({ action: "settings", id, values })
  }

  function flush() {
    clearTimeout(saveTimer)
    saveTimer = null
    const values = { ...pending.value }
    if (!Object.keys(values).length) return
    save(values, false)
  }

  function change(key, value) {
    pending.value = { ...pending.value, [key]: value }
    clearTimeout(saveTimer)
    saveTimer = setTimeout(flush, SAVE_DELAY_MS)
  }

  function step(item, dir) {
    change(item.key, stepped(item, valueOf(item.key), dir))
  }

  function draftOf(key) {
    return key in drafts.value ? drafts.value[key] : listText(norm(valueOf(key)))
  }

  function setDraft(key, text) {
    drafts.value = { ...drafts.value, [key]: text }
  }

  function dropDraft(key) {
    if (!(key in drafts.value)) return
    const d = { ...drafts.value }
    delete d[key]
    drafts.value = d
  }

  function commitList(key) {
    const draft = drafts.value[key]
    if (draft === undefined) return
    dropDraft(key)
    const list = draft.split(/[\s,]+/).filter(Boolean)
    if (same(list, valueOf(key))) return
    pending.value = { ...pending.value, [key]: list }
    flush()
  }

  function resetOne(key) {
    dropDraft(key)
    change(key, defaultOf(key))
  }

  function resetAll() {
    clearTimeout(saveTimer)
    saveTimer = null
    pending.value = {}
    drafts.value = {}
    const values = {}
    for (const [k, v] of Object.entries(defaults())) {
      if (k !== "autoNextRound" && k !== "carMode") values[k] = v
    }
    if (!Object.keys(values).length) return
    save(values, true)
  }

  function onReply(data) {
    const idx = data.id === undefined ? 0 : inFlight.findIndex(r => r.id === data.id)
    if (idx < 0) return null
    const req = inFlight.splice(idx, 1)[0]
    if (req) {
      const p = { ...pending.value }
      for (const k of req.keys) {
        if (k in p && same(p[k], req.values[k])) delete p[k]
      }
      pending.value = p
    }
    if (!data.ok) return { text: data.text || "Not saved", tone: "warn" }
    if (req && req.reset) return { text: "Reset to defaults", tone: "good" }
    if (req && req.keys.length === 1) {
      const item = liveItem(itemFor(req.keys[0]), valueOf)
      return { text: `Saved: ${item.label.toLowerCase()} ${shown(item, req.values[item.key])}`, tone: "good" }
    }
    return { text: `Saved ${req ? req.keys.length + " " : ""}settings`, tone: "good" }
  }

  function clear() {
    clearTimeout(saveTimer)
    saveTimer = null
    pending.value = {}
    drafts.value = {}
    inFlight = []
  }

  function commitDrafts() {
    for (const key of Object.keys(drafts.value)) commitList(key)
  }

  function dispose() {
    commitDrafts()
    if (saveTimer) flush()
    clearTimeout(saveTimer)
  }

  return {
    pending, drafts, valueOf, defaultOf, changed, save, change, step,
    draftOf, setDraft, commitList, commitDrafts, resetOne, resetAll, onReply, clear, dispose,
  }
}
