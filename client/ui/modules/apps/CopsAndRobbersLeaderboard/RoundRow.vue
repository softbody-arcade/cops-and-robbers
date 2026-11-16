<template>
  <div class="b-row b-cols-round">
    <BngIcon class="b-end" :class="end.tone" :type="end.icon" />
    <span class="b-who">
      <span v-if="own" class="b-text">{{ endLine(round) }}</span>
      <span v-else class="b-text"><b>{{ round.player }}</b> {{ headline(round) }}</span>
      <span v-if="detailed && sub" class="b-sub">{{ sub }}</span>
      <span v-if="detailed && flag" class="b-flag"><BngIcon :type="icons.caution" />{{ flag }}</span>
    </span>
    <span class="b-right b-mono">{{ formatTime(round.survivedSeconds) }}</span>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngIcon, icons } from "@/common/components/base"
import { formatTime } from "../../copsAndRobbers/format.js"
import { buildStep, clock, endLine, headline, warnings } from "./board.js"

const ENDS = {
  caught: { icon: icons.carChase01, tone: "b-tone-runner" },
  escaped: { icon: icons.flag, tone: "b-tone-good" },
  called: { icon: icons.abandon, tone: "b-tone-muted" },
  disconnect: { icon: icons.abandon, tone: "b-tone-muted" },
}

const props = defineProps({
  round: { type: Object, required: true },
  own: Boolean,
  detailed: Boolean,
  allMaps: Boolean,
  mapLabel: Function,
})

const end = computed(() => ENDS[props.round.endReason] || ENDS.called)

const sub = computed(() => {
  const r = props.round
  const step = buildStep(r)
  const parts = [clock(r)]
  if (props.allMaps && props.mapLabel) parts.push(props.mapLabel(r.map))
  parts.push(r.car || r.model || "")
  parts.push(r.skyLabel)
  if (step !== null) parts.push(`step ${step}`)
  return parts.filter(Boolean).join(" · ")
})

const flag = computed(() => {
  const w = warnings(props.round)
  if (!w.length) return ""
  return w.length > 1 ? `${w[0].text} (+${w.length - 1} more)` : w[0].text
})
</script>
