<template>
  <div class="b-tab">
    <template v-if="player">
      <BngButton class="b-back" :accent="ACCENTS.ghost" :icon="icons.arrowSmallLeft" @click="emit('update:selected', null)">All players</BngButton>
      <div class="b-title">{{ player.name }}</div>
      <div class="b-tiles">
        <div v-for="t in tiles" :key="t.label" class="b-tile">
          <div class="b-tile-key">{{ t.label }}</div>
          <div class="b-tile-value b-mono">{{ t.value }}</div>
        </div>
      </div>
      <template v-if="recent.length">
        <div class="b-sec">Last rounds</div>
        <RoundRow v-for="r in recent" :key="r.id" :round="r" :own="r.player === player.name" />
      </template>
    </template>
    <div v-else-if="!players.length" class="b-empty">No players yet</div>
    <template v-else>
      <div class="b-head b-cols-players">
        <span>Player</span><span class="b-right">Runs</span><span class="b-right">Best</span>
        <span class="b-right">Catches</span><span class="b-right">Assists</span>
      </div>
      <div
        v-for="p in players"
        :key="p.key"
        class="b-row b-cols-players b-click"
        :class="{ me: p.me === true }"
        @click="emit('update:selected', p.key)"
      >
        <span class="b-name">{{ p.name }}</span>
        <span class="b-right b-mono">{{ orDash(p.runs) }}</span>
        <span class="b-right b-mono">{{ orDash(p.best, formatTime) }}</span>
        <span class="b-right b-mono">{{ orDash(p.catches) }}</span>
        <span class="b-right b-mono">{{ orDash(p.assists) }}</span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS, icons } from "@/common/components/base"
import { formatTime } from "../../copsAndRobbers/format.js"
import { list, orDash } from "./board.js"
import RoundRow from "./RoundRow.vue"

const RECENT = 5

const props = defineProps({
  players: { type: Array, required: true },
  rounds: { type: Array, required: true },
  selected: String,
})
const emit = defineEmits(["update:selected"])

const player = computed(() => props.players.find(p => p.key === props.selected) || null)

const tiles = computed(() => {
  const p = player.value
  if (!p) return []
  return [
    { label: "Runs", value: orDash(p.runs) },
    { label: "Best", value: orDash(p.best, formatTime) },
    { label: "Average", value: orDash(p.average, formatTime) },
    { label: "Escapes", value: orDash(p.escapes) },
    { label: "Catches", value: orDash(p.catches) },
    { label: "Assists", value: orDash(p.assists) },
    { label: "Hidden", value: orDash(p.hiddenPct, v => `${Math.round(v)}%`) },
    { label: "Lost cops", value: orDash(p.lostThem, v => `${v}×`) },
  ]
})

const recent = computed(() => {
  const p = player.value
  if (!p) return []
  return props.rounds.filter(r => r.player === p.name || list(r.cops).some(c => c.name === p.name)).slice(0, RECENT)
})
</script>
