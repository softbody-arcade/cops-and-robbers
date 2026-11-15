<template>
  <CnrRoot class="cnr-board">
    <CnrCard v-if="!hidden" class="board-card" title="Leaderboard" closable @close="close">
      <div v-if="!connected" class="b-empty">Not on a Cops and Robbers server</div>
      <BngTabs v-else v-model="tab" class="board-tabs" :show-arrows="false">
        <template #after-tab-list>
          <div v-if="filtersShown" class="b-filters">
            <BngDropdown v-model="mapFilter" class="b-filter" :items="mapItems">
              <template #display>
                <span class="b-filter-text">{{ filterLabel }}</span>
              </template>
            </BngDropdown>
            <BngDropdown v-model="modeFilter" class="b-filter" :items="MODES" />
          </div>
        </template>
        <BoardRunners tab-heading="Runners" :runners="runners" :mine="state.mine" :all-maps="allMaps" :map-label="mapLabel" />
        <BoardCops tab-heading="Cops" :cops="cops" />
        <BoardPlayers v-model:selected="playerKey" tab-heading="Players" :players="players" :rounds="rounds" />
        <BoardRounds
          v-model:selected="roundId"
          tab-heading="Rounds"
          :rounds="rounds"
          :all-maps="allMaps"
          :map-label="mapLabel"
          :more="moreShown"
          @more="more"
        />
      </BngTabs>
    </CnrCard>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"
import { $translate } from "@/services"
import { BngDropdown, BngTabs } from "@/common/components/base"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import { useCnrHud } from "../../copsAndRobbers/hud.js"
import { mapName } from "../../copsAndRobbers/format.js"
import { list } from "./board.js"
import BoardRunners from "./BoardRunners.vue"
import BoardCops from "./BoardCops.vue"
import BoardPlayers from "./BoardPlayers.vue"
import BoardRounds from "./BoardRounds.vue"

const OPEN_RETRY_MS = 2000
const PLAYERS_TAB = 2
const ROUNDS_TAB = 3
const MODES = [
  { value: "all", label: "All car modes" },
  { value: "random", label: "Random car" },
  { value: "evolving", label: "Evolving build" },
]

const { api } = useBridge()
const events = useEvents()
const { hud, ui } = useCnrHud("board")

const state = ref({})
const tab = ref(0)
const playerKey = ref(null)
const roundId = ref(null)
let openTimer = null

const hidden = computed(() => hud.value.driving === true)
const connected = computed(() => typeof state.value.filter === "string")
const runners = computed(() => list(state.value.runners))
const cops = computed(() => list(state.value.cops))
const players = computed(() => list(state.value.players))
const rounds = computed(() => list(state.value.rounds))
const allMaps = computed(() => state.value.filter === "all")

const filtersShown = computed(() => {
  if (tab.value === PLAYERS_TAB && playerKey.value !== null) return false
  if (tab.value === ROUNDS_TAB && roundId.value !== null) return false
  return true
})

const moreShown = computed(() => state.value.moreRounds === true)

function mapLabel(id) {
  const names = state.value.mapNames
  const info = names && typeof names === "object" && !Array.isArray(names) ? names[id] : null
  return mapName(info && typeof info === "object" ? { id, ...info } : { id, pretty: id }, t => $translate.instant(t)) || String(id || "")
}

const mapItems = computed(() => {
  const here = state.value.map
  const hasHere = typeof here === "string" && here !== ""
  const others = (Array.isArray(state.value.maps) ? state.value.maps : []).filter(m => typeof m === "string" && m !== "" && m !== here)
  return [
    ...(hasHere ? [{ value: here, label: "This map" }] : []),
    { value: "all", label: "All maps" },
    ...others.map(m => ({ value: m, label: mapLabel(m) })),
  ]
})

const filterLabel = computed(() => (allMaps.value ? "All maps" : mapLabel(state.value.filter)))

const mapFilter = computed({
  get: () => state.value.filter,
  set: value => filter(value, state.value.mode),
})

const modeFilter = computed({
  get: () => state.value.mode || "all",
  set: value => filter(state.value.filter, value),
})

function send(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.board(${api.serializeToLua(msg)}) end`)
}

function filter(map, mode) {
  send({ action: "filter", map, mode })
}

function more() {
  send({ action: "more" })
}

function close() {
  ui({ action: "toggleApp", name: "board" })
}

watch(tab, () => {
  playerKey.value = null
  roundId.value = null
})

events.on("CnRBoard", data => {
  state.value = data && typeof data === "object" && typeof data.filter === "string" ? data : {}
  if (playerKey.value !== null && !players.value.some(p => p.key === playerKey.value)) playerKey.value = null
  if (roundId.value !== null && !rounds.value.some(r => r.id === roundId.value)) roundId.value = null
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

<style>
.cnr-board {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  box-sizing: border-box;
  font-size: 0.875rem;
  --bng-icon-color: currentColor;
}
.cnr-board .board-card {
  flex: 1 1 auto;
  min-height: 0;
}
.cnr-board .board-card > .cnr-card-body {
  display: flex;
  flex-direction: column;
}
.cnr-board .board-tabs {
  flex: 1 1 auto;
  min-height: 0;
  --bng-tabs-content-overflow: auto;
}
.cnr-board .b-filters {
  display: flex;
  gap: 0.5rem;
  padding: 0.5rem 0.25rem 0;
}
.cnr-board .b-filter {
  flex: 1 1 0;
  min-width: 0;
}
.cnr-board .b-filter-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cnr-board .b-tab {
  box-sizing: border-box;
  padding: 0.5rem 0.25rem;
}
.cnr-board .b-empty {
  padding: 2rem 0;
  text-align: center;
  color: var(--cnr-muted);
}
.cnr-board .b-head,
.cnr-board .b-row {
  display: grid;
  gap: 0.5rem;
  align-items: center;
}
.cnr-board .b-head {
  padding: 0 0.5rem 0.25rem;
  font-family: var(--cnr-display);
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--cnr-muted);
}
.cnr-board .b-row {
  min-height: 1.5rem;
  margin-top: 0.25rem;
  padding: 0.25rem 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
  font-weight: 600;
  --bng-icon-size: 1rem;
}
.cnr-board .b-row.me {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-me);
}
.cnr-board .b-click {
  cursor: pointer;
}
.cnr-board .b-click:hover {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-accent);
}
.cnr-board .b-cols-runners {
  grid-template-columns: 1.5rem minmax(0, 1fr) auto;
}
.cnr-board .b-cols-cops {
  grid-template-columns: 1.5rem minmax(0, 1fr) 3.75rem 3.75rem;
}
.cnr-board .b-cols-players {
  grid-template-columns: minmax(0, 1fr) 2.5rem 3rem 3.75rem 3.75rem;
}
.cnr-board .b-cols-round {
  grid-template-columns: 1rem minmax(0, 1fr) auto;
}
.cnr-board .b-cols-sight {
  grid-template-columns: minmax(0, 1fr) auto 3rem;
}
.cnr-board .b-rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.25rem;
  border-radius: var(--bng-corners-1);
  background: rgba(var(--bng-off-white-rgb), 0.12);
  color: var(--cnr-muted);
  font-family: var(--fnt-mono);
  font-size: 0.75rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.cnr-board .b-rank.gold {
  background: linear-gradient(135deg, var(--bng-ter-peach-100), var(--bng-ter-peach-500));
  color: var(--bng-off-black);
}
.cnr-board .b-rank.silver {
  background: linear-gradient(135deg, var(--bng-cool-gray-50), var(--bng-cool-gray-400));
  color: var(--bng-off-black);
}
.cnr-board .b-rank.bronze {
  background: linear-gradient(135deg, var(--bng-orange-200), var(--bng-orange-600));
  color: var(--bng-off-black);
}
.cnr-board .b-who {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.cnr-board .b-name,
.cnr-board .b-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cnr-board .b-sub {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--cnr-muted);
}
.cnr-board .b-flag {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  font-size: 0.75rem;
  color: var(--cnr-warn);
  --bng-icon-size: 0.75rem;
}
.cnr-board .b-right {
  text-align: right;
}
.cnr-board .b-mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.cnr-board .b-muted {
  color: var(--cnr-muted);
}
.cnr-board .b-gap {
  margin-top: 0.25rem;
  text-align: center;
  letter-spacing: 0.25em;
  color: var(--cnr-muted);
}
.cnr-board .b-tone-runner {
  color: var(--cnr-runner-text);
}
.cnr-board .b-tone-good {
  color: var(--cnr-good);
}
.cnr-board .b-tone-muted {
  color: var(--cnr-muted);
}
.cnr-board .b-day,
.cnr-board .b-sec {
  margin: 0.75rem 0 0.25rem;
  font-family: var(--cnr-display);
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--cnr-muted);
}
.cnr-board .b-tab > .b-day:first-child {
  margin-top: 0;
}
.cnr-board .bng-button.b-back {
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
  --bng-button-min-width: 0;
  --bng-button-padding: 0.25rem;
  --bng-button-text-enabled-color: var(--cnr-accent);
  --bng-icon-size: 1rem;
}
.cnr-board .bng-button.b-more {
  width: 100%;
  margin-top: 0.75rem;
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
  --bng-button-min-width: 0;
  --bng-button-max-width: none;
}
.cnr-board .b-title {
  margin-top: 0.25rem;
  font-family: var(--cnr-display);
  font-size: 1rem;
  font-weight: 800;
}
.cnr-board .b-tiles {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 0.25rem;
  margin-top: 0.5rem;
}
.cnr-board .b-tile {
  min-width: 0;
  padding: 0.25rem 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.cnr-board .b-tile-key {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--cnr-display);
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--cnr-muted);
}
.cnr-board .b-tile-value {
  font-size: 1rem;
  font-weight: 800;
}
.cnr-board .b-result {
  margin-top: 0.5rem;
}
.cnr-board .b-timeline {
  position: relative;
  margin-top: 0.5rem;
  padding-left: 1rem;
}
.cnr-board .b-timeline::before {
  content: "";
  position: absolute;
  left: 0.25rem;
  top: 0.75rem;
  bottom: 0.75rem;
  width: 0.125rem;
  transform: translateX(-50%);
  background: rgba(var(--bng-off-white-rgb), 0.14);
}
.cnr-board .b-event {
  position: relative;
  display: grid;
  grid-template-columns: 3rem minmax(0, 1fr);
  gap: 0.5rem;
  padding: 0.25rem 0;
}
.cnr-board .b-event::before {
  content: "";
  position: absolute;
  left: -0.75rem;
  top: 50%;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 50%;
  transform: translate(-50%, -50%);
  background: var(--cnr-muted);
}
.cnr-board .b-event.warn::before {
  background: var(--cnr-warn);
}
.cnr-board .b-event.good::before {
  background: var(--cnr-good);
}
.cnr-board .b-event.end::before {
  background: var(--cnr-runner);
}
.cnr-board .b-catch {
  font-family: var(--cnr-display);
  font-weight: 700;
}
</style>
