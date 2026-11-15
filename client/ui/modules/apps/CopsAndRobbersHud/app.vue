<template>
  <div v-if="hud.visible" class="cnr-hud">
    <div v-if="hud.status" class="cnr-status">
      <span class="cnr-role" :class="hud.status.role === 'RUNNER' ? 'is-runner' : 'is-cop'">{{ hud.status.role }}</span>
      <span class="cnr-time">{{ hud.status.time }}</span>
      <span v-if="hud.status.reset" class="cnr-item">{{ hud.status.reset }}</span>
      <span v-if="hud.status.info" class="cnr-item">{{ hud.status.info }}</span>
    </div>
    <div v-if="hud.catch && hud.catch.visible" class="cnr-catch" :class="hud.catch.tone === 'runner' ? 'is-runner' : 'is-cop'">
      <div class="cnr-catch-label">{{ hud.catch.label }} {{ hud.catch.percent }}%</div>
      <div class="cnr-track"><div class="cnr-fill" :style="{ width: hud.catch.percent + '%' }"></div></div>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue"
import { useEvents } from "@/services/events"

const hud = ref({ visible: false })
const events = useEvents()

events.on("CnRHud", data => {
  hud.value = data && typeof data === "object" ? data : { visible: false }
})
</script>

<style scoped>
.cnr-hud {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  gap: 6px;
  color: #fff;
  font-family: sans-serif;
  pointer-events: none;
}
.cnr-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 14px;
  padding: 6px 14px;
  border-radius: 8px;
  background: rgba(10, 12, 18, 0.72);
  font-size: 15px;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-role {
  font-weight: 700;
  letter-spacing: 0.06em;
  padding: 1px 8px;
  border-radius: 4px;
}
.cnr-role.is-runner { background: #e53935; }
.cnr-role.is-cop { background: #1e88e5; }
.cnr-time {
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  font-size: 17px;
}
.cnr-item { opacity: 0.9; }
.cnr-item + .cnr-item::before,
.cnr-time + .cnr-item::before {
  content: "|";
  margin-right: 14px;
  opacity: 0.4;
}
.cnr-catch {
  padding: 6px 14px 8px;
  border-radius: 8px;
  background: rgba(10, 12, 18, 0.72);
}
.cnr-catch-label {
  text-align: center;
  font-weight: 700;
  letter-spacing: 0.08em;
  font-size: 14px;
  margin-bottom: 4px;
  font-variant-numeric: tabular-nums;
}
.cnr-track {
  height: 10px;
  border-radius: 5px;
  background: rgba(255, 255, 255, 0.15);
  overflow: hidden;
}
.cnr-fill {
  height: 100%;
  border-radius: 5px;
  transition: width 0.1s linear;
}
.cnr-catch.is-runner .cnr-fill { background: #e53935; }
.cnr-catch.is-runner .cnr-catch-label { color: #ff8a80; }
.cnr-catch.is-cop .cnr-fill { background: #1e88e5; }
.cnr-catch.is-cop .cnr-catch-label { color: #82b1ff; }
</style>
