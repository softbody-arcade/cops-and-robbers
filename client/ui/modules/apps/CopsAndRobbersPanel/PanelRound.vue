<template>
  <div class="p-tab">
    <div class="p-state">
      <span class="p-dot" :class="'p-dot-' + status.tone"></span>
      <span class="p-grow">{{ status.text }} <span v-if="status.time" class="p-mono">{{ status.time }}</span></span>
      <BngButton
        v-if="view === 'chase'"
        v-bng-tooltip:top="'Fold into a bar'"
        class="p-icon-btn"
        :accent="ACCENTS.ghost"
        :icon="icons.arrowSmallUp"
        @click="emit('fold')"
      />
    </div>
    <div v-if="subline" class="p-sub">{{ subline }}</div>

    <template v-if="view === 'auto'">
      <div class="p-line">
        Next round in <span class="p-mono">{{ autoNext.seconds }}</span> s<template v-if="autoNext.runner">
          with <b>{{ autoNext.runner }}</b> (fewest runs)</template>
      </div>
      <div class="p-buttons">
        <BngButton class="p-btn" :accent="ACCENTS.main" :icon="icons.play" @click="emit('command', 'next')">Start now</BngButton>
        <BngButton class="p-btn" :accent="ACCENTS.secondary" @click="emit('command', 'auto off')">Stop automatic rounds</BngButton>
      </div>
    </template>

    <template v-else-if="view === 'prep'">
      <template v-if="inRound.length">
        <div class="p-sec">Players</div>
        <div v-for="p in inRound" :key="p.name" class="p-row">
          <span class="p-name">{{ p.name }}</span>
          <span class="p-state-text" :class="stateTone(p)">
            <BngIcon v-if="p.state === 'missing'" :type="icons.caution" />{{ stateText(p) }}
          </span>
          <RoleChip :role="p.role === 'runner' ? 'runner' : 'cop'" :label="p.role === 'runner' ? 'Runner' : 'Cop'" />
        </div>
      </template>
      <div class="p-buttons p-gap">
        <BngButton class="p-btn p-big" :accent="ACCENTS.main" :icon="icons.flag" :disabled="!can.go" @click="emit('command', 'go')">GO</BngButton>
      </div>
      <div v-if="!can.go && state.goBlocked" class="p-why">{{ state.goBlocked }}</div>
      <div class="p-buttons">
        <BngButton v-if="can.reroll" class="p-btn" :accent="ACCENTS.secondary" :icon="icons.restart" @click="emit('command', 'reroll')">New car</BngButton>
        <BngButton v-if="can.sky" class="p-btn" :accent="ACCENTS.secondary" @click="emit('command', 'sky')">New sky</BngButton>
        <BngButton v-if="can.stop" class="p-btn" :accent="ACCENTS.destructive" @click="emit('command', 'stop')">Cancel round</BngButton>
      </div>
    </template>

    <template v-else-if="view === 'chase'">
      <div class="p-buttons p-gap">
        <BngButton v-if="can.end" class="p-btn" :accent="ACCENTS.main" :icon="icons.flag" @click="emit('command', 'end')">End chase</BngButton>
        <BngButton v-if="can.stop" class="p-btn" :accent="ACCENTS.destructive" @click="cancelChase">
          {{ armed === "cancel" ? "Click again to cancel" : "Cancel round" }}
        </BngButton>
      </div>
      <div v-if="armed === 'cancel'" class="p-why">Cancelling throws this run away</div>
    </template>

    <template v-if="view === 'idle' || practiceStart">
      <div class="p-sec">{{ practiceStart ? "Start a real round" : "Runner" }}</div>
      <div v-for="p in players" :key="p.name" class="p-row p-pick" :class="{ sel: isPicked(p) }" @click="emit('update:pick', p.name)">
        <span class="p-name"><b v-if="isPicked(p)">{{ p.name }}</b><template v-else>{{ p.name }}</template></span>
        <span class="p-muted">{{ meta(p) }}</span>
        <RoleChip v-if="isPicked(p)" role="runner" label="Runner" />
      </div>
      <div class="p-row p-pick" :class="{ sel: randomPicked }" @click="emit('update:pick', RANDOM)">
        <span class="p-name p-muted">Random runner</span>
        <RoleChip v-if="randomPicked" role="runner" label="Runner" />
      </div>
      <div class="p-buttons p-gap">
        <BngButton
          class="p-btn"
          :class="{ 'p-big': !practiceStart }"
          :accent="practiceStart ? ACCENTS.secondary : ACCENTS.main"
          :icon="icons.play"
          :disabled="!canStart"
          @click="start"
        >
          {{ startLabel }}
        </BngButton>
      </div>
      <div v-if="startBlocked" class="p-why">{{ startBlocked }}</div>
      <div v-else-if="practiceStart" class="p-sub">Starting a round ends the practice</div>
    </template>

    <template v-if="view === 'idle'">
      <div v-if="can.test" class="p-buttons">
        <BngButton v-if="state.sitOut" class="p-btn" :accent="ACCENTS.secondary" :disabled="!!startBlocked" @click="emit('command', 'test cop')">Practice: watch the AI</BngButton>
        <template v-else>
          <BngButton class="p-btn" :accent="ACCENTS.secondary" :disabled="!!startBlocked" @click="emit('command', 'test runner')">Practice as runner</BngButton>
          <BngButton class="p-btn" :accent="ACCENTS.secondary" :disabled="!!startBlocked" @click="emit('command', 'test cop')">Practice as cop</BngButton>
        </template>
      </div>
      <div v-if="can.test && state.sitOut" class="p-sub">You're sitting out: an AI runner against two AI cops, and you watch</div>
      <BngSwitch
        class="p-switch"
        :model-value="state.auto === true"
        label-before
        :inline="false"
        @update:modelValue="v => emit('command', v ? 'auto on' : 'auto off')"
      >
        Automatic rounds <span class="p-muted">(next one {{ delayText }} after a round)</span>
      </BngSwitch>
    </template>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, BngIcon, BngSwitch, ACCENTS, icons } from "@/common/components/base"
import { vBngTooltip } from "@/common/directives"
import RoleChip from "../../copsAndRobbers/RoleChip.vue"
import { formatTime } from "../../copsAndRobbers/format.js"
import { useConfirm } from "./confirm.js"

const RANDOM = "\u0000random"
const PREP = new Set(["prep", "applying", "ready"])
const DRIVING = new Set(["countdown", "headstart", "running"])
const RESULT_LEAD = {
  caught: r => `${r} caught after`,
  escaped: r => `${r} escaped after`,
  called: r => `Chase ended: ${r} survived`,
  disconnect: r => `${r} left after`,
}

const props = defineProps({
  state: { type: Object, required: true },
  mapLabel: String,
  pick: String,
})
const emit = defineEmits(["command", "update:pick", "fold"])

const { armed, confirm } = useConfirm()

const can = computed(() => props.state.can || {})
const settings = computed(() => props.state.settings || {})
const players = computed(() => (Array.isArray(props.state.players) ? props.state.players.filter(p => p && p.name) : []))
const inRound = computed(() => players.value.filter(p => p.role))
const autoNext = computed(() => {
  const a = props.state.autoNext
  return a && typeof a === "object" && Number.isFinite(Number(a.seconds)) ? a : null
})

const view = computed(() => {
  const phase = props.state.phase
  if (phase === "idle") return autoNext.value ? "auto" : "idle"
  if (PREP.has(phase)) return "prep"
  if (DRIVING.has(phase)) return "chase"
  return "picking"
})

const status = computed(() => {
  const s = props.state
  switch (s.phase) {
    case "idle": {
      const r = s.lastResult
      if (r && typeof r === "object" && r.runner) {
        const lead = RESULT_LEAD[r.reason] || (n => `${n} survived`)
        return { tone: "muted", text: lead(r.runner), time: formatTime(r.seconds) }
      }
      return { tone: "muted", text: "No round" }
    }
    case "picking": return { tone: "warn", text: "Picking cars" }
    case "prep": return { tone: "warn", text: "Prep" }
    case "applying": return { tone: "warn", text: "Prep: applying the change" }
    case "ready": return { tone: "good", text: "Prep: ready for GO" }
    case "countdown": return { tone: "runner", text: "Countdown" }
    case "headstart": return { tone: "runner", text: "Head start" }
    case "running": return { tone: "runner", text: "Chase", time: formatTime(s.elapsed || 0) }
    default: return { tone: "muted", text: String(s.phase || "") }
  }
})

const evolvingMode = computed(() => settings.value.carMode === "evolving")
const build = computed(() => (props.state.build && typeof props.state.build === "object" ? props.state.build : null))

const carText = computed(() => {
  if (!evolvingMode.value && !props.state.evolving) return props.state.carName || "random car"
  if (!build.value) return "evolving build, none yet"
  return `build step ${build.value.step}, ${build.value.name}`
})

const subline = computed(() => {
  const s = props.state
  const practice = s.test ? "Practice round" : null
  if (view.value === "idle" || view.value === "auto") return [props.mapLabel, carText.value].filter(Boolean).join(" · ")
  const runner = runnerText(s, view.value === "chase")
  if (view.value === "prep") return [practice, runner, carText.value].filter(Boolean).join(" · ")
  return [practice, runner].filter(Boolean).join(" · ")
})

function runnerText(s, chase) {
  if (!s.runner) return null
  if (s.test) return `${s.runner} runs`
  return chase ? `${s.runner} running` : `${s.runner} is the runner`
}

const nextName = computed(() => props.state.nextRunner || (players.value.find(p => p.next) || {}).name || null)
const randomPicked = computed(() => props.pick === RANDOM)
const chosenName = computed(() => {
  const v = props.pick
  return v && v !== RANDOM && players.value.some(p => p.name === v) ? v : null
})
const pickedName = computed(() => (randomPicked.value ? null : chosenName.value || nextName.value))

function isPicked(p) {
  return !randomPicked.value && p.name === pickedName.value
}

function meta(p) {
  const runs = Number(p.runs) || 0
  const tags = []
  if (p.next) tags.push("next")
  if (p.last) tags.push("last")
  if (p.sitOut) tags.push("sitting out")
  tags.push(`${runs} ${runs === 1 ? "run" : "runs"}`)
  return tags.join(" · ")
}

const practiceStart = computed(() => props.state.test === true && can.value.start === true)
const startBlocked = computed(() => (evolvingMode.value && !build.value ? "Start a new build first, on the Car tab" : ""))
const canStart = computed(() => can.value.start === true && !startBlocked.value)
const startLabel = computed(() => {
  if (randomPicked.value) return "Start round with a random runner"
  return pickedName.value ? `Start round with ${pickedName.value}` : "Start round"
})

function start() {
  if (randomPicked.value) return emit("command", "start random")
  if (chosenName.value) return emit("command", `start =${chosenName.value}`)
  emit("command", "start next")
}

const delayText = computed(() => {
  const n = Number(settings.value.autoNextDelaySeconds)
  return Number.isFinite(n) ? `${n} s` : "a few seconds"
})

function stateText(p) {
  if (p.state === "changing") return p.change ? `changing: ${p.change}` : "changing"
  if (p.state === "missing") {
    const n = Number(p.missing) || 0
    return `missing ${n} ${n === 1 ? "part" : "parts"}`
  }
  return p.state || ""
}

function stateTone(p) {
  if (p.state === "ready") return "p-good"
  if (p.state === "missing") return "p-warn"
  return "p-muted"
}

function cancelChase() {
  confirm("cancel", true, () => emit("command", "stop"))
}
</script>

<style scoped>
.p-state-text {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  white-space: nowrap;
  --bng-icon-size: 1rem;
}
</style>
