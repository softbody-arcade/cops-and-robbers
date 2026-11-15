<template>
  <CnrRoot class="cnr-panel">
    <div v-if="barShown" class="p-bar">
      <span class="p-dot p-dot-runner"></span>
      <span class="bar-phase">{{ barPhase }} <span v-if="state.phase === 'running'" class="p-mono">{{ formatTime(state.elapsed || 0) }}</span></span>
      <span class="bar-runner">{{ barRunner }}</span>
      <BngButton v-if="can.end" class="p-btn p-fit" :accent="ACCENTS.main" @click="command('end')">End chase</BngButton>
      <BngButton v-if="can.stop" class="p-btn p-fit" :accent="ACCENTS.destructive" @click="cancelChase">
        {{ armed === "cancel" ? "Click again" : "Cancel" }}
      </BngButton>
      <BngButton v-bng-tooltip:top="'Open the panel'" class="p-icon-btn" :accent="ACCENTS.ghost" :icon="icons.arrowSmallDown" @click="unfold" />
    </div>
    <CnrCard v-else class="panel-card" title="Host panel" :sub="state.version ? `v${state.version}` : undefined" closable @close="close">
      <div v-if="!connected" class="p-empty">Not on a Cops and Robbers server</div>
      <template v-else>
        <BngTabs v-model="tab" class="panel-tabs" :show-arrows="false">
          <PanelRound
            v-model:pick="runnerPick"
            tab-heading="Round"
            :state="state"
            :map-label="mapLabel"
            @command="command"
            @fold="folded = true"
          />
          <PanelCar tab-heading="Car" :state="state" :store="store" @new-build="newBuild" @reset-build="resetBuild" />
          <PanelMap tab-heading="Map" :state="state" :map-label="mapLabel" @station="station" @refresh="refreshStations" />
          <PanelSettings tab-heading="Settings" :state="state" :store="store" @command="command" />
        </BngTabs>
        <div v-if="reply.text" class="p-reply" :class="reply.tone ? `p-reply-${reply.tone}` : null">
          <BngIcon :type="reply.tone === 'good' ? icons.checkmarkBold : reply.tone === 'warn' ? icons.caution : icons.info" />
          <span>{{ reply.text }}</span>
        </div>
      </template>
    </CnrCard>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, onErrorCaptured } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"
import { $translate } from "@/services"
import { BngButton, BngIcon, BngTabs, ACCENTS, icons } from "@/common/components/base"
import { vBngTooltip } from "@/common/directives"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import { formatTime, mapName } from "../../copsAndRobbers/format.js"
import PanelRound from "./PanelRound.vue"
import PanelCar from "./PanelCar.vue"
import PanelMap from "./PanelMap.vue"
import PanelSettings from "./PanelSettings.vue"
import { useSettings } from "./settings.js"
import { useConfirm } from "./confirm.js"

const DRIVING = new Set(["countdown", "headstart", "running"])
const BAR_PHASES = { countdown: "Countdown", headstart: "Head start", running: "Chase" }
const OPEN_RETRY_MS = 2000

const { api } = useBridge()
const events = useEvents()

const state = ref({})
const tab = ref(0)
const folded = ref(false)
const runnerPick = ref(null)
const reply = ref({ text: "", tone: "" })
let openTimer = null

const connected = computed(() => !!state.value.phase)
const can = computed(() => state.value.can || {})
const barShown = computed(() => folded.value && connected.value && DRIVING.has(state.value.phase))
const barPhase = computed(() => BAR_PHASES[state.value.phase] || "")
const barRunner = computed(() => {
  const r = state.value.runner
  if (!r) return ""
  return state.value.test ? `Practice round · ${r} runs` : `${r} running`
})
const mapLabel = computed(() => {
  const m = state.value.mapName
  const info = m && typeof m === "object" ? m : { id: state.value.map, pretty: state.value.map }
  return mapName(info, t => $translate.instant(t)) || ""
})

const { armed, confirm } = useConfirm()

function send(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.panel(${api.serializeToLua(msg)}) end`)
}

function clearReply() {
  reply.value = { text: "", tone: "" }
}

const store = useSettings(state, send, clearReply)

function command(text) {
  clearReply()
  send({ action: "command", text })
}

function cancelChase() {
  confirm("cancel", true, () => command("stop"))
}

function newBuild(choice) {
  clearReply()
  api.engineLua(`if copsAndRobbers then copsAndRobbers.newBuild(${api.serializeToLua(choice)}) end`)
}

function resetBuild() {
  clearReply()
  send({ action: "build", op: "reset" })
}

function refreshStations() {
  send({ action: "stations" })
}

function station(op) {
  clearReply()
  send({ action: "station", op })
  refreshStations()
}

function unfold() {
  folded.value = false
  tab.value = 0
}

function close() {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.ui(${api.serializeToLua({ action: "toggleApp", name: "panel" })}) end`)
}

watch(
  () => state.value.phase,
  (phase, prev) => {
    if (phase !== "idle" && !state.value.test) runnerPick.value = null
    if (DRIVING.has(phase) && !DRIVING.has(prev)) {
      folded.value = true
    } else if (phase === "idle" && prev && prev !== "idle") {
      folded.value = false
      tab.value = 0
    }
  }
)

watch(tab, () => store.commitDrafts())

let lastReport = ""

function report(where, err) {
  try {
    const message = err && err.message ? err.message : String(err)
    const lines = err && typeof err.stack === "string" ? err.stack.split("\n").map(l => l.trim()) : []
    const at = lines.find(l => l.startsWith("at ")) || lines[0] || ""
    const text = `[cnr_ui] panel ${where}: ${message} | ${at}`
    if (text === lastReport) return
    lastReport = text
    api.engineLua(`log("E","cnr_ui",${api.serializeToLua(text)})`)
  } catch (e) {}
}

onErrorCaptured((err, instance, info) => {
  const options = (instance && instance.$options) || {}
  report(`${options.name || options.__name || "?"} ${info}`, err)
  return false
})

events.on("CnRPanel", data => {
  state.value = data && typeof data === "object" && data.phase ? data : {}
  if (!state.value.phase) {
    store.clear()
    folded.value = false
  }
})

events.on("CnRPanelReply", data => {
  if (!data || typeof data !== "object") return
  if (data.ok === undefined) {
    reply.value = { text: data.text || "", tone: "" }
    return
  }
  const r = store.onReply(data)
  if (r) reply.value = r
})

onMounted(() => {
  send({ action: "open" })
  openTimer = setInterval(() => {
    if (!connected.value) send({ action: "open" })
  }, OPEN_RETRY_MS)
})

onUnmounted(() => {
  store.dispose()
  send({ action: "close" })
  clearInterval(openTimer)
})
</script>

<style>
.cnr-panel {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  box-sizing: border-box;
  font-size: 0.875rem;
  --bng-icon-color: currentColor;
}
.cnr-panel .panel-card {
  flex: 1 1 auto;
  min-height: 0;
}
.cnr-panel .panel-card > .cnr-card-body {
  display: flex;
  flex-direction: column;
}
.cnr-panel .panel-tabs {
  flex: 1 1 auto;
  min-height: 0;
  --bng-tabs-content-overflow: auto;
}
.cnr-panel .p-tab {
  box-sizing: border-box;
  padding: 0.75rem 0.25rem 0.5rem;
}
.cnr-panel .p-empty {
  padding: 2rem 0;
  text-align: center;
  color: var(--cnr-muted);
}
.cnr-panel .p-state {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-height: 1.75rem;
  font-family: var(--cnr-display);
  font-size: 1rem;
  font-weight: 800;
}
.cnr-panel .p-dot {
  flex: 0 0 auto;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 50%;
  background: var(--cnr-muted);
}
.cnr-panel .p-dot-warn {
  background: var(--cnr-warn);
}
.cnr-panel .p-dot-good {
  background: var(--cnr-good);
}
.cnr-panel .p-dot-runner {
  background: var(--cnr-runner);
}
.cnr-panel .p-grow {
  flex: 1 1 auto;
  min-width: 0;
}
.cnr-panel .p-sub {
  margin-top: 0.25rem;
  color: var(--cnr-muted);
}
.cnr-panel .p-line {
  margin-top: 0.5rem;
}
.cnr-panel .p-sec {
  margin: 0.75rem 0 0.25rem;
  font-family: var(--cnr-display);
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--cnr-muted);
}
.cnr-panel .p-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-height: 1.5rem;
  margin-top: 0.25rem;
  padding: 0.25rem 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.cnr-panel .p-pick {
  cursor: pointer;
}
.cnr-panel .p-pick:hover {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-accent);
}
.cnr-panel .p-pick.sel {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-me);
}
.cnr-panel .p-name {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cnr-panel .p-muted {
  color: var(--cnr-muted);
}
.cnr-panel .p-good {
  color: var(--cnr-good);
}
.cnr-panel .p-warn {
  color: var(--cnr-warn);
}
.cnr-panel .p-mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.cnr-panel .p-why {
  margin-top: 0.25rem;
  color: var(--cnr-warn);
}
.cnr-panel .p-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.5rem;
}
.cnr-panel .p-gap {
  margin-top: 0.75rem;
}
.cnr-panel .bng-button.p-btn {
  flex: 1 1 auto;
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
  --bng-button-min-width: 0;
  --bng-content-align: center;
  --bng-icon-size: 1.25rem;
}
.cnr-panel .bng-button.p-big {
  width: 100%;
  font-size: 1rem;
  line-height: 2rem;
}
.cnr-panel .bng-button.p-fit {
  flex: 0 0 auto;
}
.cnr-panel .bng-button.p-icon-btn {
  flex: 0 0 auto;
  --bng-button-margin: 0;
  --bng-button-min-width: 1.75rem;
  --bng-button-padding: 0.25rem;
  --bng-button-padding-top: 0.25rem;
  --bng-button-padding-bottom: 0.25rem;
  --bng-icon-size: 1rem;
}
.cnr-panel .p-lock {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
  padding: 0.25rem 0.5rem;
  border-radius: var(--bng-corners-1);
  background: rgba(var(--bng-ter-yellow-200-rgb), 0.13);
  color: var(--cnr-warn);
  font-weight: 600;
  --bng-icon-size: 1rem;
}
.cnr-panel .p-seg {
  display: flex;
  gap: 0.25rem;
  padding: 0.25rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.cnr-panel .p-box {
  margin-top: 0.75rem;
  padding: 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.cnr-panel .p-box-title {
  font-family: var(--cnr-display);
  font-size: 1rem;
  font-weight: 800;
}
.cnr-panel .p-switch {
  margin-top: 0.75rem;
}
.cnr-panel .p-field {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  margin-top: 0.5rem;
}
.cnr-panel .p-text {
  box-sizing: border-box;
  width: 100%;
  padding: 0.25rem 0.5rem;
  border: 0;
  border-radius: var(--bng-corners-1);
  background: var(--cnr-row);
  color: var(--cnr-text);
  font-family: var(--fnt-defs);
  font-size: 0.875rem;
}
.cnr-panel .p-text:focus {
  outline: 0.125rem solid var(--cnr-accent);
}
.cnr-panel .p-text:disabled {
  opacity: 0.5;
}
.cnr-panel .p-reply {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.5rem;
  padding: 0.25rem 0.5rem;
  border-radius: var(--bng-corners-1);
  background: var(--cnr-row);
  font-weight: 600;
  --bng-icon-size: 1rem;
}
.cnr-panel .p-reply-good {
  color: var(--cnr-good);
  background: rgba(var(--bng-add-green-400-rgb), 0.16);
}
.cnr-panel .p-reply-warn {
  color: var(--cnr-warn);
  background: rgba(var(--bng-ter-yellow-200-rgb), 0.13);
}
.cnr-panel .p-bar {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem;
  background: var(--cnr-card);
  border-radius: var(--bng-corners-2);
  font-family: var(--cnr-display);
  font-weight: 800;
}
.cnr-panel .bar-phase {
  flex: 0 0 auto;
}
.cnr-panel .bar-runner {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--fnt-defs);
  font-weight: 600;
  color: var(--cnr-muted);
}
</style>
