<template>
  <CnrCard class="hud-change" :title="change.title" :sub="sub">
    <div v-if="lines.length || change.more" class="lines">
      <div v-for="(line, i) in lines" :key="i" class="line">
        <div class="line-main">
          <span class="label">{{ line.label }}</span>
          <span v-if="line.from === NONE" class="value to">+ {{ line.to === line.label ? "added" : line.to }}</span>
          <span v-else-if="line.to === NONE" class="value from">− {{ line.from === line.label ? "removed" : line.from }}</span>
          <span v-else class="value"><span class="from">{{ line.from }}</span> → <span class="to">{{ line.to }}</span></span>
          <span v-if="line.missing" class="missing"><BngIcon :type="icons.caution" /> missing</span>
        </div>
        <div v-if="line.extra" class="sub">+ {{ line.extra }} {{ line.extra === 1 ? "part comes" : "parts come" }} with it</div>
      </div>
      <div v-if="change.more" class="sub">+{{ change.more }} more</div>
    </div>
    <template v-if="change.canApply" #actions>
      <BngButton class="apply" :accent="ACCENTS.main" :icon="icons.checkmarkBold" @click="emit('apply')">Apply change</BngButton>
      <span class="hint">then the host presses GO</span>
    </template>
  </CnrCard>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"

const NONE = "(none)"

const props = defineProps({
  change: { type: Object, required: true },
})
const emit = defineEmits(["apply"])

const lines = computed(() => (Array.isArray(props.change.lines) ? props.change.lines : []))
const sub = computed(() => {
  const n = Number(props.change.count)
  if (!Number.isFinite(n)) return undefined
  if (n === 0) return "none yet"
  return n === 1 ? "1 change" : `${n} changes`
})
</script>

<style scoped>
.hud-change {
  width: 100%;
  text-shadow: none;
  pointer-events: auto;
}
.hud-change :deep(.cnr-card-title) {
  font-size: 1.125rem;
}
.hud-change :deep(.cnr-card-actions) {
  align-items: center;
}
.lines {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.875rem;
}
.line-main {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  white-space: nowrap;
  --bng-icon-size: 1rem;
}
.label {
  flex: 0 1 auto;
  max-width: 45%;
  overflow: hidden;
  text-overflow: ellipsis;
  font-weight: 700;
}
.value {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.from {
  color: var(--cnr-muted);
}
.to {
  color: var(--cnr-good);
}
.missing {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  flex: 0 0 auto;
  font-weight: 700;
  color: var(--cnr-warn);
}
.sub {
  padding-left: 1rem;
  font-size: 0.75rem;
  color: var(--cnr-muted);
}
.apply {
  pointer-events: auto;
}
.hint {
  font-size: 0.875rem;
  color: var(--cnr-muted);
}
</style>
