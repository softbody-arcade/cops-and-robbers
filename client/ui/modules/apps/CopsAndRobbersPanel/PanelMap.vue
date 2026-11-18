<template>
  <div class="p-tab">
    <div class="p-state">
      <span class="p-grow">{{ mapLabel }} · <span class="p-mono">{{ count }}</span> {{ count === 1 ? "gas station" : "gas stations" }}</span>
    </div>
    <div class="p-sub">
      Players may reset while standing still at a gas station.
    </div>
    <div class="p-buttons p-gap">
      <BngButton class="p-btn" :accent="ACCENTS.main" :icon="icons.mapPoint" @click="emit('station', 'add')">Add station here</BngButton>
      <BngButton class="p-btn" :accent="ACCENTS.secondary" :disabled="!canRemove" @click="emit('station', 'remove')">Remove nearest</BngButton>
    </div>
    <div v-if="stations && !canRemove" class="p-why">No station within 50 m to remove</div>

    <template v-if="stations">
      <template v-if="nearest.length">
        <div class="p-sec">Nearest</div>
        <div v-for="(n, i) in nearest" :key="i" class="p-row">
          <span class="p-name station"><BngIcon :type="icons.mapPoint" />Gas station</span>
          <span class="p-mono p-muted">{{ formatDistance(n.meters) }}</span>
        </div>
      </template>
      <div v-else-if="count > 0" class="p-sub">Get in a car to see how far the nearest stations are.</div>
      <div v-else class="p-sub">No gas stations on this map yet.</div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { useEvents } from "@/services/events"
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"
import { formatDistance } from "../../copsAndRobbers/format.js"

const props = defineProps({
  state: { type: Object, required: true },
  mapLabel: String,
})
const emit = defineEmits(["station", "refresh"])

const REFRESH_MS = 2000

const events = useEvents()
const stations = ref(null)
let refreshTimer = null

const count = computed(() => {
  const n = Number(props.state.stationCount)
  if (Number.isFinite(n)) return n
  return stations.value ? Number(stations.value.count) || 0 : 0
})
const nearest = computed(() => {
  const list = stations.value && stations.value.nearest
  return Array.isArray(list) ? list.filter(n => n && Number.isFinite(Number(n.meters))).slice(0, 3) : []
})
const canRemove = computed(() => !!(stations.value && stations.value.canRemove === true))

events.on("CnRStations", data => {
  stations.value = data && typeof data === "object" ? data : null
})

watch(() => props.state.stationCount, () => emit("refresh"))
onMounted(() => {
  emit("refresh")
  refreshTimer = setInterval(() => emit("refresh"), REFRESH_MS)
})
onUnmounted(() => clearInterval(refreshTimer))
</script>

<style scoped>
.station {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  --bng-icon-size: 1rem;
}
</style>
