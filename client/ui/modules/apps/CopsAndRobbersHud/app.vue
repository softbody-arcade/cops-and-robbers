<template>
  <div v-if="hud.visible" class="cnr-hud">
    <div v-if="hud.result" class="cnr-panel cnr-result">
      <div class="cnr-result-title">{{ hud.result.title }}</div>
      <div v-if="hud.result.runner" class="cnr-result-line">
        <span class="cnr-strong">{{ hud.result.runner }}</span>
        <span class="cnr-time">{{ hud.result.time }}</span>
      </div>
      <div v-if="hud.result.catchers" class="cnr-result-line">Caught by {{ hud.result.catchers }}</div>
      <div v-if="hud.result.top && hud.result.top.length" class="cnr-result-top">
        <div v-for="(line, i) in hud.result.top" :key="i">{{ line }}</div>
      </div>
      <div v-if="hud.result.nextIn" class="cnr-result-next">Next round in {{ hud.result.nextIn }}</div>
    </div>
    <template v-else>
      <div v-if="hud.banner" class="cnr-panel cnr-banner">
        <span class="cnr-banner-label">{{ hud.banner.label }}</span>
        <span v-if="hud.banner.number" class="cnr-banner-number">{{ hud.banner.number }}</span>
      </div>
      <div v-if="hud.change" class="cnr-panel cnr-change">
        <div class="cnr-change-title">{{ hud.change.title }}</div>
        <div v-for="(line, i) in (hud.change.lines || [])" :key="'c' + i" class="cnr-change-line">
          <span class="cnr-change-label">{{ line.label }}</span>
          <span class="cnr-muted">{{ line.from }}</span>
          <span>→</span>
          <span class="cnr-change-to">{{ line.to }}</span>
        </div>
        <div v-if="hud.change.more" class="cnr-muted">+{{ hud.change.more }} more</div>
      </div>
      <div v-else-if="hud.prep" class="cnr-panel cnr-prep">
        <span class="cnr-role" :class="hud.prep.role === 'RUNNER' ? 'is-runner' : 'is-cop'">{{ hud.prep.role }}</span>
        <span class="cnr-item">{{ hud.prep.car }}</span>
        <span class="cnr-item cnr-muted">waiting for GO</span>
      </div>
      <div v-for="(text, i) in (hud.events || [])" :key="'e' + i" class="cnr-panel cnr-event">{{ text }}</div>
      <div v-if="hud.status" class="cnr-panel cnr-status">
        <span class="cnr-role" :class="hud.status.role === 'RUNNER' ? 'is-runner' : 'is-cop'">{{ hud.status.role }}</span>
        <span class="cnr-time">{{ hud.status.time }}</span>
        <span v-if="hud.status.reset" class="cnr-item" :class="{ 'cnr-reset-flash': hud.status.resetFlash }">{{ hud.status.reset }}</span>
        <span v-if="hud.status.info" class="cnr-item">{{ hud.status.info }}</span>
      </div>
      <div v-if="hud.catch && hud.catch.visible" class="cnr-panel cnr-catch" :class="hud.catch.tone === 'runner' ? 'is-runner' : 'is-cop'">
        <div class="cnr-catch-label">{{ hud.catch.label }} {{ hud.catch.percent }}%</div>
        <div class="cnr-track"><div class="cnr-fill" :style="{ width: hud.catch.percent + '%' }"></div></div>
      </div>
    </template>
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
  gap: 0.375rem;
  color: #fff;
  font-family: sans-serif;
  pointer-events: none;
}
.cnr-panel {
  border-radius: 0.5rem;
  background: rgba(10, 12, 18, 0.72);
  padding: 0.375rem 0.875rem;
}
.cnr-banner {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.875rem;
  font-weight: 800;
  letter-spacing: 0.08em;
}
.cnr-banner-label { font-size: 1.125rem; }
.cnr-banner-number {
  font-size: 2.125rem;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}
.cnr-change {
  display: flex;
  flex-direction: column;
  gap: 0.125rem;
  font-size: 0.8125rem;
}
.cnr-change-title {
  font-weight: 700;
  letter-spacing: 0.04em;
  color: #ff9a4d;
}
.cnr-change-line {
  display: flex;
  gap: 0.5rem;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-change-label {
  min-width: 6rem;
  font-weight: 700;
}
.cnr-change-to {
  color: #9fe870;
}
.cnr-prep, .cnr-event {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  font-size: 0.875rem;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-muted { opacity: 0.7; }
.cnr-reset-flash {
  color: #ffd54f;
  font-weight: 700;
}
.cnr-result { text-align: center; }
.cnr-result-title {
  font-size: 1.25rem;
  font-weight: 800;
  letter-spacing: 0.08em;
}
.cnr-result-line {
  display: flex;
  justify-content: center;
  gap: 0.75rem;
  font-size: 0.9375rem;
}
.cnr-strong { font-weight: 700; }
.cnr-result-top {
  margin-top: 0.25rem;
  font-size: 0.8125rem;
  opacity: 0.85;
}
.cnr-result-next {
  margin-top: 0.25rem;
  font-size: 0.8125rem;
  font-weight: 700;
  color: #82b1ff;
}
.cnr-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.875rem;
  padding: 0.375rem 0.875rem;
  border-radius: 0.5rem;
  background: rgba(10, 12, 18, 0.72);
  font-size: 0.9375rem;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-role {
  font-weight: 700;
  letter-spacing: 0.06em;
  padding: 1px 0.5rem;
  border-radius: 0.25rem;
}
.cnr-role.is-runner { background: #e53935; }
.cnr-role.is-cop { background: #1e88e5; }
.cnr-time {
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  font-size: 1.0625rem;
}
.cnr-item { opacity: 0.9; }
.cnr-item + .cnr-item::before,
.cnr-time + .cnr-item::before {
  content: "|";
  margin-right: 0.875rem;
  opacity: 0.4;
  color: #fff;
  font-weight: 400;
}
.cnr-catch {
  padding: 0.375rem 0.875rem 0.5rem;
  border-radius: 0.5rem;
  background: rgba(10, 12, 18, 0.72);
}
.cnr-catch-label {
  text-align: center;
  font-weight: 700;
  letter-spacing: 0.08em;
  font-size: 0.875rem;
  margin-bottom: 0.25rem;
  font-variant-numeric: tabular-nums;
}
.cnr-track {
  height: 0.625rem;
  border-radius: 0.3125rem;
  background: rgba(255, 255, 255, 0.15);
  overflow: hidden;
}
.cnr-fill {
  height: 100%;
  border-radius: 0.3125rem;
  transition: width 0.1s linear;
}
.cnr-catch.is-runner .cnr-fill { background: #e53935; }
.cnr-catch.is-runner .cnr-catch-label { color: #ff8a80; }
.cnr-catch.is-cop .cnr-fill { background: #1e88e5; }
.cnr-catch.is-cop .cnr-catch-label { color: #82b1ff; }
</style>
