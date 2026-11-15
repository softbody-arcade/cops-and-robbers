<template>
  <div class="b-tab">
    <div v-if="!runners.length" class="b-empty">No runs yet</div>
    <template v-else>
      <div class="b-head b-cols-runners"><span>#</span><span>Runner</span><span class="b-right">Best</span></div>
      <div v-for="(r, i) in runners" :key="i" class="b-row b-cols-runners" :class="{ me: r.me === true }">
        <span class="b-rank" :class="medal(i + 1)">{{ i + 1 }}</span>
        <span class="b-who"><span class="b-name">{{ r.player }}</span><span v-if="sub(r)" class="b-sub">{{ sub(r) }}</span></span>
        <span class="b-right b-mono">{{ formatTime(r.survivedSeconds) }}</span>
      </div>
      <template v-if="mineRow">
        <div class="b-gap">· · ·</div>
        <div class="b-row b-cols-runners me">
          <span class="b-rank" :class="medal(mineRow.rank)">{{ mineRow.rank }}</span>
          <span class="b-who"><span class="b-name">{{ mineRow.player }}</span><span v-if="sub(mineRow)" class="b-sub">{{ sub(mineRow) }}</span></span>
          <span class="b-right b-mono">{{ formatTime(mineRow.survivedSeconds) }}</span>
        </div>
      </template>
    </template>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { formatTime } from "../../copsAndRobbers/format.js"
import { medal } from "./board.js"

const props = defineProps({
  runners: { type: Array, required: true },
  mine: Object,
  allMaps: Boolean,
  mapLabel: { type: Function, required: true },
})

const mineRow = computed(() => {
  const m = props.mine
  return m && typeof m === "object" && Number.isFinite(Number(m.rank)) && m.player ? { ...m, rank: Number(m.rank) } : null
})

function sub(r) {
  const parts = [r.car || r.model || ""]
  if (props.allMaps && r.map) parts.push(props.mapLabel(r.map))
  return parts.filter(Boolean).join(" · ")
}
</script>
