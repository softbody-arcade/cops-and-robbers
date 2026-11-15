<template>
  <div class="b-tab">
    <div v-if="!cops.length" class="b-empty">No catches yet</div>
    <template v-else>
      <div class="b-head b-cols-cops">
        <span>#</span><span>Cop</span><span class="b-right">Catches</span><span class="b-right">Fastest</span>
      </div>
      <div v-for="(c, i) in cops" :key="i" class="b-row b-cols-cops" :class="{ me: c.me === true }">
        <span class="b-rank" :class="medal(i + 1)">{{ i + 1 }}</span>
        <span class="b-who"><span class="b-name">{{ c.name }}</span><span class="b-sub">{{ assists(c) }}</span></span>
        <span class="b-right b-mono">{{ orDash(c.catches) }}</span>
        <span class="b-right b-mono">{{ orDash(c.fastest, formatTime) }}</span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { formatTime } from "../../copsAndRobbers/format.js"
import { medal, orDash } from "./board.js"

defineProps({
  cops: { type: Array, required: true },
})

function assists(c) {
  const n = Number(c.assists) || 0
  return `${n} ${n === 1 ? "assist" : "assists"}`
}
</script>
