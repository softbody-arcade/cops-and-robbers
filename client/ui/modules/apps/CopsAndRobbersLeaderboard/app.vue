<template>
  <div class="cnr-board" :class="{ collapsed }">
    <div class="cnr-head">
      <button class="cnr-toggle" :title="collapsed ? 'Show leaderboard' : 'Hide leaderboard'" @click="collapsed = !collapsed">{{ collapsed ? "▸" : "▾" }}</button>
      <template v-if="collapsed">
        <span class="cnr-mini" @click="collapsed = false">Leaderboard</span>
      </template>
      <template v-else>
        <button v-for="t in TABS" :key="t.id" class="cnr-tab" :class="{ active: tab === t.id }" @click="selectTab(t.id)">{{ t.label }}</button>
        <BngDropdown v-if="connected" v-model="filter" :items="filterItems" class="cnr-filter" />
      </template>
    </div>

    <div v-if="collapsed"></div>
    <div v-else-if="!connected" class="cnr-empty">Not on a Cops and Robbers server</div>

    <div v-else-if="tab === 'runners'" class="cnr-body">
      <div v-if="!runners.length" class="cnr-empty">No runs yet</div>
      <div v-for="(r, i) in runners" :key="i" class="cnr-row cnr-wrap">
        <span class="cnr-rank">{{ i + 1 }}.</span>
        <span class="cnr-name">{{ r.player }}</span>
        <span class="cnr-num">{{ formatTime(r.survivedSeconds) }}</span>
        <span class="cnr-sub">{{ r.car || r.model }}<template v-if="state.filter === 'all'"> · {{ r.map }}</template></span>
      </div>
    </div>

    <div v-else-if="tab === 'cops'" class="cnr-body">
      <div v-if="!cops.length" class="cnr-empty">No catches yet</div>
      <div v-for="(c, i) in cops" :key="i" class="cnr-row cnr-wrap">
        <span class="cnr-rank">{{ i + 1 }}.</span>
        <span class="cnr-name">{{ c.name }}</span>
        <span class="cnr-num">{{ c.catches }} {{ c.catches === 1 ? "catch" : "catches" }}</span>
        <span class="cnr-sub">fastest {{ formatTime(c.fastest) }}</span>
      </div>
    </div>

    <div v-else class="cnr-body">
      <template v-if="selected">
        <button class="cnr-back" @click="selectedKey = null">‹ All players</button>
        <div class="cnr-detail-name">{{ selected.name }}</div>
        <div v-for="row in detailRows" :key="row.label" class="cnr-stat">
          <span>{{ row.label }}</span><span class="cnr-num">{{ row.value }}</span>
        </div>
      </template>
      <template v-else>
        <div v-if="!players.length" class="cnr-empty">No players yet</div>
        <div v-else class="cnr-row cnr-header">
          <span class="cnr-name">Player</span><span class="cnr-col">Runs</span><span class="cnr-col">Best</span>
          <span class="cnr-col">Catches</span><span class="cnr-col">Assists</span>
        </div>
        <div v-for="p in players" :key="p.key" class="cnr-row cnr-click" @click="selectedKey = p.key">
          <span class="cnr-name">{{ p.name }}</span>
          <span class="cnr-col">{{ p.runs }}</span>
          <span class="cnr-col">{{ p.best != null ? formatTime(p.best) : "–" }}</span>
          <span class="cnr-col">{{ p.catches }}</span>
          <span class="cnr-col">{{ p.assists }}</span>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"
import { BngDropdown } from "@/common/components/base"

const TABS = [
  { id: "runners", label: "RUNNERS" },
  { id: "cops", label: "COPS" },
  { id: "players", label: "PLAYERS" },
]
const OPEN_RETRY_MS = 2000

const { api } = useBridge()
const events = useEvents()

const state = ref({})
const tab = ref("runners")
const collapsed = ref(false)
const selectedKey = ref(null)
let openTimer = null

const connected = computed(() => typeof state.value.filter === "string")
const list = name => (Array.isArray(state.value[name]) ? state.value[name] : [])
const runners = computed(() => list("runners"))
const cops = computed(() => list("cops"))
const players = computed(() => list("players"))
const selected = computed(() => players.value.find(p => p.key === selectedKey.value) || null)

const filterItems = computed(() => {
  const here = state.value.map
  const maps = Array.isArray(state.value.maps) ? state.value.maps : []
  return [
    { value: here, label: "This map" },
    { value: "all", label: "All maps" },
    ...maps.filter(m => m !== here).map(m => ({ value: m, label: m })),
  ]
})

const filter = computed({
  get: () => state.value.filter,
  set: value => send({ action: "filter", map: value }),
})

function formatTime(seconds) {
  const total = Math.floor(Number(seconds) || 0)
  const s = total % 60
  return `${Math.floor(total / 60)}:${s < 10 ? "0" : ""}${s}`
}

function orDash(v, fmt) {
  return v === undefined || v === null ? "–" : fmt ? fmt(v) : String(v)
}

const detailRows = computed(() => {
  const p = selected.value
  if (!p) return []
  return [
    { label: "Runs", value: p.runs },
    { label: "Best survival", value: orDash(p.best, formatTime) },
    { label: "Average survival", value: orDash(p.average, formatTime) },
    { label: "Escapes", value: p.escapes },
    { label: "Catches", value: p.catches },
    { label: "Assists", value: p.assists },
    { label: "Hidden from cops", value: orDash(p.hiddenPct, v => `${Math.round(v)}%`) },
    { label: "Lost the cops", value: orDash(p.lostThem, v => `${v}×`) },
  ]
})

function send(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.board(${api.serializeToLua(msg)}) end`)
}

function selectTab(id) {
  tab.value = id
  selectedKey.value = null
}

events.on("CnRBoard", data => {
  state.value = data && typeof data === "object" && typeof data.filter === "string" ? data : {}
  if (selectedKey.value && !selected.value) selectedKey.value = null
})

onMounted(() => {
  send({ action: "open" })
  openTimer = setInterval(() => {
    if (!connected.value) send({ action: "open" })
  }, OPEN_RETRY_MS)
})

onUnmounted(() => {
  send({ action: "close" })
  clearInterval(openTimer)
})
</script>

<style scoped>
.cnr-board {
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
.cnr-board.collapsed {
  height: auto;
  padding: 0.375rem 0.625rem;
}
.cnr-head {
  display: flex;
  align-items: center;
  gap: 0.375rem;
  margin-bottom: 0.5rem;
}
.cnr-board.collapsed .cnr-head {
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
  font-weight: 700;
  cursor: pointer;
}
.cnr-tab {
  background: transparent;
  border: 0;
  border-bottom: 2px solid transparent;
  color: rgba(255, 255, 255, 0.6);
  font-size: 0.8125rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  padding: 0.25rem 0.375rem;
  cursor: pointer;
}
.cnr-tab.active {
  color: #fff;
  border-bottom-color: #ff6600;
}
.cnr-filter {
  margin-left: auto;
  min-width: 7.5rem;
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
  gap: 0.25rem;
}
.cnr-row {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  padding: 0.25rem 0.375rem;
  border-radius: 0.25rem;
  background: rgba(255, 255, 255, 0.05);
}
.cnr-header {
  background: transparent;
  color: rgba(255, 255, 255, 0.6);
  font-size: 0.75rem;
  font-weight: 700;
}
.cnr-click {
  cursor: pointer;
}
.cnr-click:hover {
  background: rgba(255, 102, 0, 0.2);
}
.cnr-rank {
  width: 1.5rem;
  color: rgba(255, 255, 255, 0.6);
}
.cnr-name {
  flex: 1;
  font-weight: 700;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.cnr-num {
  font-variant-numeric: tabular-nums;
  font-weight: 700;
}
.cnr-col {
  width: 3.5rem;
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.cnr-sub {
  width: 100%;
  order: 10;
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.6);
}
.cnr-wrap {
  flex-wrap: wrap;
}
.cnr-back {
  align-self: flex-start;
  background: transparent;
  border: 0;
  color: #ff9a4d;
  font-size: 0.8125rem;
  cursor: pointer;
  padding: 0;
}
.cnr-detail-name {
  font-size: 1.125rem;
  font-weight: 700;
  margin: 0.25rem 0;
}
.cnr-stat {
  display: flex;
  justify-content: space-between;
  padding: 0.25rem 0.375rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
</style>
