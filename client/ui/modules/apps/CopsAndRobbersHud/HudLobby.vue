<template>
  <CnrCard class="hud-lobby" title="Cops and Robbers" :sub="`${lobby.online} online`">
    <div class="status">{{ lobby.status }}</div>
    <HudWarnings class="warnings" :warnings="lobby.warnings" />
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
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.arrowSmallDown" @click="emit('hide')">Hide</BngButton>
    </template>
  </CnrCard>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, ACCENTS, icons } from "@/common/components/base"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import HudWarnings from "./HudWarnings.vue"

const props = defineProps({
  lobby: { type: Object, required: true },
})
const emit = defineEmits(["settings", "help", "toggle", "hide"])

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
.warnings {
  margin-top: 0.25rem;
}
.hud-lobby .cnr-btn {
  font-size: 0.875rem;
  line-height: 1.25rem;
  --bng-icon-size: 1rem;
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
