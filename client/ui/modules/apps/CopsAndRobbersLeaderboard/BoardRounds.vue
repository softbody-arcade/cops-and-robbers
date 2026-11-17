<template>
  <div class="b-tab">
    <template v-if="round">
      <BngButton class="b-back" :accent="ACCENTS.ghost" :icon="icons.arrowSmallLeft" @click="emit('update:selected', null)">All rounds</BngButton>
      <div class="b-title">{{ resultLead(round) }} <span class="b-mono">{{ formatTime(round.survivedSeconds) }}</span></div>
      <div class="b-sub">{{ detailSub }}</div>
      <div v-if="timeline.length" class="b-timeline">
        <div v-for="(e, i) in timeline" :key="i" class="b-event" :class="e.tone">
          <span class="b-mono b-muted">{{ formatTime(e.t) }}</span>
          <span>{{ e.text }}</span>
        </div>
      </div>
      <div v-else-if="round.endReason === 'caught' || round.endReason === 'called'" class="b-result">{{ endLine(round) }}</div>
      <template v-if="cops.length">
        <div class="b-sec">Cops</div>
        <div v-for="(c, i) in cops" :key="i" class="b-row b-cols-sight">
          <span class="b-name">{{ c.name }}</span>
          <span class="b-muted">{{ sight(c) }}</span>
          <span :class="c.catcher === true ? 'b-catch' : 'b-muted'">{{ c.catcher === true ? "Catch" : "–" }}</span>
        </div>
      </template>
    </template>
    <div v-else-if="!rounds.length" class="b-empty">No rounds yet</div>
    <template v-else>
      <template v-for="(g, gi) in groups" :key="gi">
        <div class="b-day">{{ g.label }}</div>
        <RoundRow
          v-for="r in g.rounds"
          :key="r.id"
          class="b-click"
          :round="r"
          detailed
          :all-maps="allMaps"
          :map-label="mapLabel"
          @click="emit('update:selected', r.id)"
        />
      </template>
      <BngButton v-if="more" class="b-more" :accent="ACCENTS.secondary" @click="emit('more')">Show more</BngButton>
    </template>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS, icons } from "@/common/components/base"
import { formatTime } from "../../copsAndRobbers/format.js"
import { buildStep, clock, dayLabel, endLine, events, list, resultLead } from "./board.js"
import RoundRow from "./RoundRow.vue"

const props = defineProps({
  rounds: { type: Array, required: true },
  selected: Number,
  allMaps: Boolean,
  mapLabel: { type: Function, required: true },
  more: Boolean,
})
const emit = defineEmits(["update:selected", "more"])

const round = computed(() => (props.selected === null || props.selected === undefined ? null : props.rounds.find(r => r.id === props.selected) || null))

const groups = computed(() => {
  const now = new Date()
  const out = []
  for (const r of props.rounds) {
    const label = dayLabel(r, now)
    const last = out[out.length - 1]
    if (last && last.label === label) last.rounds.push(r)
    else out.push({ label, rounds: [r] })
  }
  return out
})

const detailSub = computed(() => {
  const r = round.value
  if (!r) return ""
  const when = [dayLabel(r), clock(r)].filter(Boolean).join(" ")
  const step = buildStep(r)
  const car = (r.car || r.model || "") + (step !== null ? `, build step ${step}` : "")
  return [when, r.map ? props.mapLabel(r.map) : "", [car, r.skyLabel, r.trafficLabel].filter(Boolean).join(" · ")].filter(Boolean).join(" · ")
})

const timeline = computed(() => {
  const r = round.value
  if (!r) return []
  const evs = events(r)
  if (!evs.length && r.tracked !== true) return []
  return [
    { t: 0, text: "Cops released", tone: "" },
    ...evs,
    { t: Math.max(0, Number(r.survivedSeconds) || 0), text: endLine(r), tone: "end" },
  ]
})

const cops = computed(() => (round.value ? list(round.value.cops).filter(c => typeof c.name === "string" && c.name) : []))

function sight(c) {
  const n = Number(c.sightPct)
  return c.sightPct !== undefined && c.sightPct !== null && Number.isFinite(n) ? `in sight ${Math.round(n)}%` : ""
}
</script>
