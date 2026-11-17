<template>
  <BngButton class="cnr-btn hud-tab" :accent="ACCENTS.secondary" :icon="icons.arrowSmallUp" @click="emit('show')">Cops and Robbers</BngButton>
</template>

<script setup>
import { BngButton, ACCENTS, icons } from "@/common/components/base"

const emit = defineEmits(["show"])
</script>

<style scoped>
.hud-tab {
  text-shadow: none;
  pointer-events: auto;
  --bng-icon-size: 1.25rem;
}
</style>
