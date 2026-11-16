<template>
  <CnrCard class="hud-lobby" title="Cops and Robbers" :sub="`${lobby.online} online`">
    <div class="status">{{ lobby.status }}</div>
    <div v-for="w in warnings" :key="w" class="warning">
      <BngIcon :type="icons.caution" />
      <span>{{ w }}</span>
    </div>
    <template #actions>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" @click="emit('settings')">
        <span class="cnr-swatch" :class="{ empty: !lobby.color }" :style="lobby.color ? { background: lobby.color } : null"></span>
        <span>Settings</span>
      </BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.info" @click="emit('help')">How to play</BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.cup" @click="emit('toggle', 'board')">
        <span>Leaderboard</span>
        <span v-if="apps.board" class="open-mark"></span>
      </BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.cogSolid" @click="emit('toggle', 'panel')">
        <span>Host panel</span>
        <span v-if="apps.panel" class="open-mark"></span>
      </BngButton>
    </template>
  </CnrCard>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"

const props = defineProps({
  lobby: { type: Object, required: true },
})
const emit = defineEmits(["settings", "help", "toggle"])

const warnings = computed(() => (Array.isArray(props.lobby.warnings) ? props.lobby.warnings : []))
const apps = computed(() => props.lobby.apps || {})
</script>

<style scoped>
.hud-lobby {
  width: 100%;
  text-shadow: none;
  pointer-events: auto;
}
.hud-lobby :deep(.cnr-card-title) {
  font-size: 1.125rem;
}
.hud-lobby :deep(.cnr-card-actions) {
  flex-wrap: wrap;
}
.status {
  font-size: 1rem;
}
.warning {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.25rem;
  font-size: 0.875rem;
  font-weight: 700;
  color: var(--cnr-warn);
  --bng-icon-size: 1rem;
}
.hud-lobby .cnr-btn {
  --bng-icon-size: 1.25rem;
}
.open-mark {
  position: absolute;
  left: 0.5rem;
  right: 0.5rem;
  bottom: 0;
  height: 0.125rem;
  background: var(--cnr-accent);
}
</style>
