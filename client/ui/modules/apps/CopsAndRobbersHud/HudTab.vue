<template>
  <div class="hud-tab">
    <HudWarnings :warnings="warnings" />
    <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.arrowSmallUp" @click="emit('show')">Cops and Robbers</BngButton>
  </div>
</template>

<script setup>
import { BngButton, ACCENTS, icons } from "@/common/components/base"
import HudWarnings from "./HudWarnings.vue"

defineProps({
  warnings: [Array, Object],
})
const emit = defineEmits(["show"])
</script>

<style scoped>
.hud-tab {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  max-width: 100%;
}
.hud-tab .cnr-btn {
  text-shadow: none;
  pointer-events: auto;
  --bng-icon-size: 1.25rem;
}
</style>
