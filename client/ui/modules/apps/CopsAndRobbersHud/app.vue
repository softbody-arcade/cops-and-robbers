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
        <template v-for="(line, i) in (hud.change.lines || [])" :key="'c' + i">
          <div class="cnr-change-line">
            <span class="cnr-change-label">{{ line.label }}</span>
            <span v-if="line.from === '(none)'" class="cnr-change-value cnr-change-to">+ {{ line.to === line.label ? "added" : line.to }}</span>
            <span v-else-if="line.to === '(none)'" class="cnr-change-value cnr-change-removed">− {{ line.from === line.label ? "removed" : line.from }}</span>
            <span v-else class="cnr-change-value">
              <span class="cnr-muted">{{ line.from }}</span> → <span class="cnr-change-to">{{ line.to }}</span>
            </span>
          </div>
          <div v-if="line.extra" class="cnr-change-extra">+ {{ line.extra }} {{ line.extra === 1 ? "part comes" : "parts come" }} with it</div>
        </template>
        <div v-if="hud.change.more" class="cnr-muted">+{{ hud.change.more }} more</div>
      </div>
      <div v-else-if="hud.prep" class="cnr-panel cnr-prep">
        <span class="cnr-role" :class="hud.prep.role === 'RUNNER' ? 'is-runner' : 'is-cop'">{{ hud.prep.role }}</span>
        <span class="cnr-item">{{ hud.prep.car }}</span>
        <span class="cnr-item cnr-muted">waiting for GO</span>
      </div>
      <div v-for="(text, i) in (hud.events || [])" :key="'e' + i" class="cnr-panel cnr-event">{{ text }}</div>
      <div v-if="hud.status" class="cnr-panel cnr-status">
        <div class="cnr-status-main">
          <span class="cnr-role" :class="hud.status.role === 'RUNNER' ? 'is-runner' : 'is-cop'">{{ hud.status.role }}</span>
          <span class="cnr-time">{{ hud.status.time }}</span>
          <span v-if="hud.status.tag || hud.status.info" class="cnr-divider"></span>
          <span v-if="hud.status.tag" class="cnr-tag" :class="'tag-' + hud.status.tag.toLowerCase().replace(' ', '-')">◉ {{ hud.status.tag }}</span>
          <span v-if="hud.status.info" class="cnr-info">{{ hud.status.info }}</span>
        </div>
        <div v-if="hud.status.reset" class="cnr-status-reset" :class="{ 'cnr-reset-flash': hud.status.resetFlash, 'is-ok': hud.status.reset === 'Reset OK' }">{{ hud.status.reset }}</div>
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
  gap: 0.75rem;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-change-label {
  flex: 0 1 auto;
  max-width: 45%;
  overflow: hidden;
  text-overflow: ellipsis;
  font-weight: 700;
}
.cnr-change-value {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cnr-change-removed {
  color: #ff7b72;
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
  flex-direction: column;
  align-items: center;
  gap: 0.125rem;
  padding: 0.375rem 0.875rem;
  border-radius: 0.5rem;
  background: rgba(10, 12, 18, 0.72);
  font-size: 0.9375rem;
  white-space: nowrap;
  overflow: hidden;
}
.cnr-status-main {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  max-width: 100%;
}
.cnr-info {
  overflow: hidden;
  text-overflow: ellipsis;
}
.cnr-divider {
  width: 1px;
  align-self: stretch;
  margin: 0.125rem 0;
  background: rgba(255, 255, 255, 0.3);
}
.cnr-tag {
  padding: 0 0.4375rem;
  border: 1px solid currentColor;
  border-radius: 0.25rem;
  font-size: 0.8125rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  color: rgba(255, 255, 255, 0.85);
  background: transparent;
}
.cnr-tag.tag-spotted, .cnr-tag.tag-in-sight {
  color: #ff7b72;
}
.cnr-tag.tag-hidden {
  color: #7ee2a8;
}
.cnr-tag.tag-live {
  color: #79b8ff;
}
.cnr-status-reset {
  font-size: 0.8125rem;
  color: rgba(255, 255, 255, 0.75);
}
.cnr-status-reset.is-ok {
  color: #9fe870;
}
.cnr-change-extra {
  padding-left: 1rem;
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.6);
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
