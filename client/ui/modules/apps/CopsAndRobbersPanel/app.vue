<template>
  <div class="cnr-panel" :class="{ collapsed }">
    <div class="cnr-head">
      <button class="cnr-toggle" :title="collapsed ? 'Show panel' : 'Hide panel'" @click="collapsed = !collapsed">{{ collapsed ? "▸" : "▾" }}</button>
      <template v-if="collapsed">
        <span class="cnr-mini" @click="collapsed = false">{{ connected ? statusLine : "Cops and Robbers" }}</span>
      </template>
      <template v-else>
        <button class="cnr-tab" :class="{ active: tab === 'round' }" @click="tab = 'round'">ROUND</button>
        <button class="cnr-tab" :class="{ active: tab === 'settings' }" @click="tab = 'settings'">SETTINGS</button>
        <span v-if="state.version" class="cnr-version">v{{ state.version }}</span>
      </template>
    </div>

    <div v-if="collapsed"></div>
    <div v-else-if="!connected" class="cnr-empty">Not on a Cops and Robbers server</div>

    <div v-else-if="tab === 'round'" class="cnr-body">
      <div class="cnr-status">{{ statusLine }}</div>
      <div v-if="state.runner" class="cnr-runner">Runner: {{ state.runner }}<span v-if="state.test"> (practice)</span></div>

      <div class="cnr-row">
        <span class="cnr-label">Runner</span>
        <BngDropdown v-model="choice" :items="runnerItems" class="cnr-grow" />
      </div>

      <div class="cnr-buttons">
        <BngButton :disabled="!can.start" @click="command(`start ${choice}`)">Start round</BngButton>
        <BngButton :disabled="!can.reroll" accent="secondary" @click="command('reroll')">New car</BngButton>
        <BngButton :disabled="!can.go" @click="command('go')">GO</BngButton>
      </div>
      <div class="cnr-buttons">
        <BngButton :disabled="!can.end" accent="secondary" @click="command('end')">End chase</BngButton>
        <BngButton :disabled="!can.stop" accent="destructive" @click="command('stop')">Cancel</BngButton>
      </div>

      <div class="cnr-row">
        <BngSwitch :model-value="state.auto === true" label-before :inline="false" class="cnr-grow" @update:modelValue="v => command(v ? 'auto on' : 'auto off')">Automatic rounds</BngSwitch>
      </div>

      <div class="cnr-row">
        <span class="cnr-label">Practice</span>
        <BngButton :disabled="!can.test" accent="outlined" @click="command('test runner')">as runner</BngButton>
        <BngButton :disabled="!can.test" accent="outlined" @click="command('test cop')">as cop</BngButton>
      </div>
    </div>

    <div v-else class="cnr-body">
      <div v-if="!can.settings" class="cnr-locked">Stop the round first</div>
      <div v-for="group in groups" :key="group.title" class="cnr-group">
        <div class="cnr-group-title">{{ group.title }}</div>
        <div v-for="item in group.items" :key="item.key" class="cnr-setting">
          <span class="cnr-setting-label">{{ item.label }}</span>
          <template v-if="item.kind === 'bool'">
            <BngSwitch :model-value="valueOf(item.key) === true" :disabled="!can.settings" @update:modelValue="v => change(item.key, v)" />
          </template>
          <template v-else-if="item.kind === 'list'">
            <input
              v-bng-text-input
              class="cnr-text"
              :disabled="!can.settings"
              :value="drafts[item.key] ?? listText(valueOf(item.key))"
              @input="e => (drafts[item.key] = e.target.value)"
              @keydown.enter="e => e.target.blur()"
              @blur="commitList(item.key)"
            />
          </template>
          <template v-else>
            <span class="cnr-stepper">
              <button class="cnr-step" :disabled="!can.settings" @click="stepBy(item, -1)">−</button>
              <span class="cnr-value" :class="{ pending: item.key in pending }">{{ valueOf(item.key) }} {{ item.unit }}</span>
              <button class="cnr-step" :disabled="!can.settings" @click="stepBy(item, 1)">+</button>
            </span>
          </template>
        </div>
      </div>
      <div class="cnr-row cnr-end">
        <BngButton :disabled="!can.settings" accent="attention" @click="resetClick">{{ resetArmed ? "Click again to reset" : "Reset to default" }}</BngButton>
      </div>
    </div>

    <div v-if="!collapsed && connected && replyText" class="cnr-reply">{{ replyText }}</div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"
import { BngButton, BngSwitch, BngDropdown } from "@/common/components/base"
import { vBngTextInput } from "@/common/directives"

const GROUPS = [
  { title: "Round", items: [
    { key: "headStartSeconds", label: "Head start", unit: "s", step: 1, min: 0 },
    { key: "runnerCountdownSeconds", label: "Runner countdown", unit: "s", step: 1, min: 0 },
    { key: "roundTimeLimitSeconds", label: "Time limit (0 = off)", unit: "s", step: 60, min: 0 },
    { key: "autoNextDelaySeconds", label: "Next round delay", unit: "s", step: 5, min: 0 },
  ] },
  { title: "Catching", items: [
    { key: "catchHoldSeconds", label: "Hold time", unit: "s", step: 1, min: 1 },
    { key: "catchRadiusMeters", label: "Radius", unit: "m", step: 1, min: 1 },
    { key: "catchMaxSpeedKmh", label: "Max speed", unit: "km/h", step: 1, min: 1 },
    { key: "explodeOnCatch", label: "Explode on catch", kind: "bool" },
  ] },
  { title: "Resets", items: [
    { key: "resetWaitSeconds", label: "Wait time", unit: "s", step: 1, min: 0 },
    { key: "stillMaxSpeedKmh", label: "Still speed", unit: "km/h", step: 0.5, min: 0.5 },
    { key: "copResetMinDistanceMeters", label: "Cop min distance", unit: "m", step: 100, min: 0 },
    { key: "gasStationRadiusMeters", label: "Gas station radius", unit: "m", step: 5, min: 0 },
  ] },
  { title: "Crashes", items: [
    { key: "crashSpeedLossKmh", label: "Speed loss", unit: "km/h", step: 5, min: 5 },
    { key: "crashPenaltySeconds", label: "Penalty", unit: "s", step: 1, min: 0 },
  ] },
  { title: "Cops", items: [
    { key: "copSpawnMinMeters", label: "Spawn min", unit: "m", step: 10, min: 0 },
    { key: "copSpawnMaxMeters", label: "Spawn max", unit: "m", step: 10, min: 0 },
    { key: "lastSeenIntervalSeconds", label: "Last seen every", unit: "s", step: 5, min: 0 },
    { key: "sightMaxMeters", label: "Sight range (0 = off)", unit: "m", step: 50, min: 0 },
    { key: "sightLiveIntervalSeconds", label: "Live update every", unit: "s", step: 1, min: 1 },
    { key: "sightNoRouteSeconds", label: "No route within", unit: "s", step: 1, min: 0 },
    { key: "sightNoRouteMinMeters", label: "No route at least", unit: "m", step: 10, min: 0 },
    { key: "sightGraceSeconds", label: "Sight grace", unit: "s", step: 0.5, min: 0 },
    { key: "assistMinSightPercent", label: "Assist needs sight", unit: "%", step: 5, min: 0 },
  ] },
  { title: "Cars", items: [
    { key: "includeModVehicles", label: "Include mod cars", kind: "bool" },
    { key: "excludedModels", label: "Excluded cars", kind: "list" },
  ] },
]
const KNOWN = new Set(GROUPS.flatMap(g => g.items.map(i => i.key)).concat(["autoNextRound"]))
const DRIVING = new Set(["countdown", "headstart", "running"])
const PHASES = {
  idle: "No round",
  picking: "Picking cars",
  prep: "Prep: waiting for GO",
  countdown: "Countdown",
  headstart: "Runner head start",
}
const SAVE_DELAY_MS = 500
const OPEN_RETRY_MS = 2000
const RESET_CONFIRM_MS = 3000

const { api } = useBridge()
const events = useEvents()

const state = ref({})
const tab = ref("round")
const choice = ref("next")
const replyText = ref("")
const pending = ref({})
const drafts = ref({})
const resetArmed = ref(false)
const collapsed = ref(false)
let inFlight = []
let nextRequestId = 1
let saveTimer = null
let openTimer = null
let resetTimer = null

const connected = computed(() => !!state.value.phase)
const can = computed(() => state.value.can || {})
const players = computed(() => (Array.isArray(state.value.players) ? state.value.players : []))

const runnerItems = computed(() => [
  { value: "next", label: "Next (fewest runs)" },
  { value: "again", label: "Same as last" },
  { value: "random", label: "Random" },
  ...players.value.map(n => ({ value: `=${n}`, label: n })),
])

watch(
  () => state.value.phase,
  (phase, prev) => {
    if (DRIVING.has(phase) && !DRIVING.has(prev)) collapsed.value = true
    else if (phase === "idle" && prev && prev !== "idle") collapsed.value = false
  }
)

watch(runnerItems, items => {
  if (!items.some(i => i.value === choice.value)) choice.value = "next"
})

function formatTime(s) {
  const m = Math.floor(s / 60)
  const r = Math.floor(s % 60)
  return `${m}:${r < 10 ? "0" : ""}${r}`
}

const statusLine = computed(() => {
  const phase = state.value.phase
  const label = phase === "running" ? `Chase ${formatTime(state.value.elapsed || 0)}` : PHASES[phase] || phase
  return `${label} · ${state.value.map} · ${players.value.length} players`
})

const groups = computed(() => {
  const settings = state.value.settings || {}
  const other = Object.keys(settings)
    .filter(k => !KNOWN.has(k))
    .sort()
    .map(k => {
      const v = settings[k]
      if (typeof v === "boolean") return { key: k, label: k, kind: "bool" }
      if (typeof v === "object") return { key: k, label: k, kind: "list" }
      return { key: k, label: k, unit: "", step: 1, min: 0 }
    })
  return other.length ? [...GROUPS, { title: "Other", items: other }] : GROUPS
})

function send(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.panel(${api.serializeToLua(msg)}) end`)
}

function command(text) {
  replyText.value = ""
  send({ action: "command", text })
}

function valueOf(key) {
  return key in pending.value ? pending.value[key] : (state.value.settings || {})[key]
}

function listText(v) {
  return Array.isArray(v) ? v.join(", ") : ""
}

function itemFor(key) {
  for (const g of groups.value) {
    const item = g.items.find(i => i.key === key)
    if (item) return item
  }
  return { key, label: key, unit: "" }
}

function shown(item, v) {
  if (item.kind === "bool") return v ? "on" : "off"
  if (item.kind === "list") return listText(v) || "none"
  return `${v} ${item.unit || ""}`.trim()
}

function same(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

function saveSettings(values, reset) {
  const id = nextRequestId++
  inFlight.push({ id, keys: Object.keys(values), values, reset })
  replyText.value = ""
  send({ action: "settings", id, values })
}

function flush() {
  clearTimeout(saveTimer)
  saveTimer = null
  const values = { ...pending.value }
  const keys = Object.keys(values)
  if (!keys.length) return
  saveSettings(values, false)
}

function change(key, value) {
  pending.value = { ...pending.value, [key]: value }
  clearTimeout(saveTimer)
  saveTimer = setTimeout(flush, SAVE_DELAY_MS)
}

function stepBy(item, dir) {
  const q = (Number(valueOf(item.key)) || 0) / item.step
  const onGrid = Math.abs(q - Math.round(q)) < 1e-6
  const n = onGrid ? Math.round(q) + dir : dir > 0 ? Math.ceil(q) : Math.floor(q)
  change(item.key, Math.max(item.min, Math.round(n * item.step * 10000) / 10000))
}

function commitList(key) {
  const draft = drafts.value[key]
  if (draft === undefined) return
  const d = { ...drafts.value }
  delete d[key]
  drafts.value = d
  const list = draft.split(/[\s,]+/).filter(Boolean)
  if (same(list, valueOf(key))) return
  pending.value = { ...pending.value, [key]: list }
  flush()
}

function resetClick() {
  if (!resetArmed.value) {
    resetArmed.value = true
    resetTimer = setTimeout(() => (resetArmed.value = false), RESET_CONFIRM_MS)
    return
  }
  clearTimeout(resetTimer)
  resetArmed.value = false
  clearTimeout(saveTimer)
  saveTimer = null
  pending.value = {}
  drafts.value = {}
  const values = {}
  for (const [k, v] of Object.entries(state.value.defaults || {})) {
    if (k !== "autoNextRound") values[k] = v
  }
  if (!Object.keys(values).length) return
  saveSettings(values, true)
}

events.on("CnRPanel", data => {
  state.value = data && typeof data === "object" && data.phase ? data : {}
  if (!state.value.phase) {
    pending.value = {}
    drafts.value = {}
    inFlight = []
  }
})

events.on("CnRPanelReply", data => {
  if (!data || typeof data !== "object") return
  if (data.ok === undefined) {
    replyText.value = data.text || ""
    return
  }
  const idx = data.id === undefined ? 0 : inFlight.findIndex(r => r.id === data.id)
  if (idx < 0) return
  const req = inFlight.splice(idx, 1)[0]
  if (req) {
    const p = { ...pending.value }
    for (const k of req.keys) {
      if (k in p && same(p[k], req.values[k])) delete p[k]
    }
    pending.value = p
  }
  if (!data.ok) {
    replyText.value = data.text || "Not saved"
  } else if (req && req.reset) {
    replyText.value = "Reset to defaults"
  } else if (req && req.keys.length === 1) {
    const item = itemFor(req.keys[0])
    replyText.value = `Saved: ${item.label} ${shown(item, req.values[item.key])}`
  } else {
    replyText.value = `Saved ${req ? req.keys.length + " " : ""}settings`
  }
})

onMounted(() => {
  send({ action: "open" })
  openTimer = setInterval(() => {
    if (!connected.value) send({ action: "open" })
  }, OPEN_RETRY_MS)
})

onUnmounted(() => {
  for (const key of Object.keys(drafts.value)) commitList(key)
  flush()
  send({ action: "close" })
  clearInterval(openTimer)
  clearTimeout(saveTimer)
  clearTimeout(resetTimer)
})
</script>

<style scoped>
.cnr-panel {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  padding: 0.625rem 0.75rem;
  border-radius: 0.5rem;
  background: rgba(10, 12, 18, 0.72);
  color: #fff;
  font-family: sans-serif;
  font-size: 0.875rem;
  overflow: hidden;
}
.cnr-panel.collapsed {
  height: auto;
  padding: 0.375rem 0.625rem;
}
.cnr-head {
  display: flex;
  align-items: center;
  gap: 0.375rem;
  margin-bottom: 0.5rem;
}
.cnr-panel.collapsed .cnr-head {
  margin-bottom: 0;
}
.cnr-toggle {
  width: 1.5rem;
  height: 1.5rem;
  border: 0;
  border-radius: 0.25rem;
  background: rgba(255, 255, 255, 0.12);
  color: #fff;
  font-size: 0.8125rem;
  cursor: pointer;
}
.cnr-mini {
  flex: 1;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  font-weight: 700;
  cursor: pointer;
}
.cnr-tab {
  background: transparent;
  border: 0;
  border-bottom: 2px solid transparent;
  color: rgba(255, 255, 255, 0.6);
  font-size: 0.875rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  padding: 0.25rem 0.5rem;
  cursor: pointer;
}
.cnr-tab.active {
  color: #fff;
  border-bottom-color: #ff6600;
}
.cnr-version {
  margin-left: auto;
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.5);
}
.cnr-empty {
  margin: auto;
  color: rgba(255, 255, 255, 0.7);
}
.cnr-body {
  flex: 1;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
.cnr-status {
  font-size: 1rem;
  font-weight: 700;
}
.cnr-runner {
  color: rgba(255, 255, 255, 0.85);
}
.cnr-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.cnr-end {
  justify-content: flex-end;
  margin-top: 0.25rem;
}
.cnr-label {
  min-width: 4rem;
  color: rgba(255, 255, 255, 0.7);
}
.cnr-grow {
  flex: 1;
}
.cnr-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.375rem;
}
.cnr-locked {
  padding: 0.375rem 0.5rem;
  border-radius: 0.25rem;
  background: rgba(255, 102, 0, 0.25);
  font-weight: 700;
}
.cnr-group-title {
  margin: 0.25rem 0 2px;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: #ff9a4d;
}
.cnr-setting {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  min-height: 1.875rem;
}
.cnr-setting-label {
  color: rgba(255, 255, 255, 0.85);
}
.cnr-stepper {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
}
.cnr-step {
  width: 1.625rem;
  height: 1.625rem;
  border: 0;
  border-radius: 0.25rem;
  background: rgba(255, 255, 255, 0.15);
  color: #fff;
  font-size: 1rem;
  cursor: pointer;
}
.cnr-step:disabled {
  opacity: 0.4;
  cursor: default;
}
.cnr-value {
  min-width: 4.75rem;
  text-align: center;
  font-variant-numeric: tabular-nums;
}
.cnr-value.pending {
  color: #ffcc66;
}
.cnr-text {
  flex: 1;
  max-width: 14.375rem;
  padding: 0.25rem 0.375rem;
  border: 1px solid rgba(255, 255, 255, 0.25);
  border-radius: 0.25rem;
  background: rgba(0, 0, 0, 0.35);
  color: #fff;
  font-size: 0.8125rem;
}
.cnr-reply {
  margin-top: 0.5rem;
  padding-top: 0.375rem;
  border-top: 1px solid rgba(255, 255, 255, 0.15);
  color: rgba(255, 255, 255, 0.85);
  font-size: 0.8125rem;
}
</style>
