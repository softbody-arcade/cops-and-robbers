<template>
  <div class="hud-prep">
    <span v-if="prep.waiting" class="waiting">
      <BngIcon :type="icons.lockClosed" />
      <span>{{ prep.waiting }}</span>
    </span>
    <span class="buttons">
      <BngButton class="hud-btn" :accent="ACCENTS.secondary" @click="emit('color')">
        <span class="swatch" :class="{ empty: !prep.color }" :style="prep.color ? { background: prep.color } : null"></span>
        <span>Colour</span>
      </BngButton>
      <BngButton class="hud-btn" :accent="ACCENTS.secondary" :icon="icons.info" @click="emit('help')">How to play</BngButton>
      <BngButton class="hud-btn" :accent="ACCENTS.secondary" :icon="icons.cogSolid" @click="emit('toggle', 'panel')">Host panel</BngButton>
    </span>
  </div>
</template>

<script setup>
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"

defineProps({
  prep: { type: Object, required: true },
})
const emit = defineEmits(["color", "help", "toggle"])
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
  color: var(--cnr-muted);
  --bng-icon-size: 1.25rem;
}
.buttons {
  display: inline-flex;
  gap: 0.5rem;
  text-shadow: none;
}
.hud-prep .hud-btn {
  pointer-events: auto;
  font-family: var(--cnr-display);
  font-size: 0.875rem;
  font-weight: 700;
  line-height: 1.25rem;
  --bng-button-margin: 0;
  --bng-content-align: center;
  --bng-icon-size: 1rem;
}
.swatch {
  display: inline-block;
  width: 1rem;
  height: 1rem;
  margin-right: 0.5rem;
  border-radius: var(--bng-corners-1);
  box-shadow: 0 0 0 0.125rem var(--cnr-muted);
}
.swatch.empty {
  background: transparent;
}
</style>
