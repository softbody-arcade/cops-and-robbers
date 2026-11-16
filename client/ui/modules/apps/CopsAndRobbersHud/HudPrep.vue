<template>
  <div class="hud-prep">
    <span v-if="prep.waiting" class="waiting">
      <BngIcon :type="icons.lockClosed" />
      <span>{{ prep.waiting }}</span>
    </span>
    <span class="buttons">
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" @click="emit('settings')">
        <span class="cnr-swatch" :class="{ empty: !prep.color }" :style="prep.color ? { background: prep.color } : null"></span>
        <span>Settings</span>
      </BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.info" @click="emit('help')">How to play</BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.cogSolid" @click="emit('toggle', 'panel')">Host panel</BngButton>
    </span>
  </div>
</template>

<script setup>
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"

defineProps({
  prep: { type: Object, required: true },
})
const emit = defineEmits(["settings", "help", "toggle"])
</script>

<style scoped>
.hud-prep {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0.5rem 1rem;
  max-width: 100%;
}
.waiting {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  min-width: 0;
  font-size: 1rem;
  font-weight: 700;
  --bng-icon-size: 1.25rem;
}
.buttons {
  display: inline-flex;
  gap: 0.5rem;
  text-shadow: none;
}
.hud-prep .cnr-btn {
  pointer-events: auto;
  font-size: 0.875rem;
  line-height: 1.25rem;
  --bng-icon-size: 1rem;
}
</style>
