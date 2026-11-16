<template>
  <div class="hud-chase">
    <div v-if="status" class="chase-top">
      <RoleChip class="chase-chip" :role="role" :label="role === 'runner' ? 'Runner' : 'Cop'" />
      <span v-if="status.releaseIn" class="item">
        <BngIcon :type="icons.strobeLights" />
        <span>Cops released in <span class="mono">{{ status.releaseIn }}</span></span>
      </span>
      <span v-else class="item">
        <BngIcon :type="icons.stopwatchArrows02" />
        <span class="mono">{{ status.time }}</span>
        <span v-if="status.limit" class="mono limit">/ {{ status.limit }}</span>
      </span>
      <span v-if="status.tag" class="item" :class="'tone-' + tagTone">
        <BngIcon :type="status.tag === 'HIDDEN' ? icons.eyeSolidClosed : icons.eyeSolidOpened" />
        <span>{{ status.tag }}</span>
      </span>
      <span v-if="status.info" class="item info">
        <BngIcon :type="role === 'runner' ? icons.carChase01 : icons.mapPoint" />
        <span class="info-text"><span v-if="status.info.before">{{ status.info.before }}</span><span v-if="status.info.dist" class="mono">{{ status.info.before ? ' ' : '' }}{{ status.info.dist }}</span><span v-if="status.info.after">{{ status.info.before || status.info.dist ? ' ' : '' }}{{ status.info.after }}</span></span>
      </span>
    </div>
    <div v-if="bar && bar.visible" class="chase-catch" :class="'tone-' + barTone">
      <div class="catch-label">
        <span>{{ bar.label }}</span>
        <span class="mono">{{ percent }}%</span>
      </div>
      <div class="catch-track"><div class="catch-fill" :style="{ width: percent + '%' }"></div></div>
    </div>
    <div v-if="status && status.reset" class="chase-reset" :class="{ ready: status.reset === RESET_READY, flash: status.resetFlash }">
      <BngIcon :type="icons.restart" />
      <span>{{ status.reset }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngIcon, icons } from "@/common/components/base"
import RoleChip from "../../copsAndRobbers/RoleChip.vue"

const RESET_READY = "Reset ready"
const TAG_TONES = { SPOTTED: "warn", HIDDEN: "plain", "IN SIGHT": "good", LIVE: "cop" }

const props = defineProps({
  status: Object,
  bar: Object,
})

const role = computed(() => (props.status && props.status.role === "cop" ? "cop" : "runner"))
const tagTone = computed(() => TAG_TONES[props.status && props.status.tag] || "plain")
const barTone = computed(() => (props.bar && props.bar.tone === "cop" ? "cop" : "runner"))
const percent = computed(() => Math.max(0, Math.min(100, Number(props.bar && props.bar.percent) || 0)))
</script>

<style scoped>
.hud-chase {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  width: 100%;
}
.chase-top {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0.25rem 1.25rem;
  max-width: 100%;
  font-size: 1.25rem;
  font-weight: 700;
  white-space: nowrap;
  --bng-icon-size: 1.5rem;
}
.chase-top .chase-chip {
  font-size: 0.875rem;
  font-weight: 800;
  line-height: 1.5rem;
  letter-spacing: 0.08em;
  text-shadow: none;
}
.item {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 0.25rem;
}
.info {
  flex: 0 1 auto;
  min-width: 0;
}
.info-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.limit {
  font-weight: 600;
}
.tone-warn {
  color: var(--cnr-warn);
}
.tone-good {
  color: var(--cnr-good);
}
.tone-cop {
  color: var(--cnr-cop-text);
}
.tone-runner {
  color: var(--cnr-runner-text);
}
.chase-catch {
  margin-top: 0.5rem;
}
.catch-label {
  display: flex;
  justify-content: space-between;
  font-size: 0.875rem;
  font-weight: 800;
  letter-spacing: 0.06em;
}
.catch-track {
  height: 0.5rem;
  margin-top: 0.25rem;
  background: var(--bng-black-o2);
}
.catch-fill {
  height: 100%;
  transition: width 0.1s linear;
}
.chase-catch.tone-runner .catch-fill {
  background: var(--cnr-runner);
}
.chase-catch.tone-cop .catch-fill {
  background: var(--cnr-cop);
}
.chase-reset {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.25rem;
  margin-top: 0.5rem;
  font-size: 0.875rem;
  font-weight: 600;
  --bng-icon-size: 1rem;
}
.chase-reset.ready {
  font-weight: 800;
}
.chase-reset.flash {
  color: var(--cnr-warn);
  font-weight: 700;
}
</style>
