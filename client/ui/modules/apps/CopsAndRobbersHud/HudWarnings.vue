<template>
  <div v-if="items.length" class="hud-warnings">
    <div v-for="w in items" :key="w" class="warning">
      <BngIcon :type="icons.caution" />
      <span>{{ w }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngIcon, icons } from "@/common/components/base"

const props = defineProps({
  warnings: [Array, Object],
})

const items = computed(() => (Array.isArray(props.warnings) ? props.warnings : []))
</script>

<style scoped>
.hud-warnings {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  max-width: 100%;
}
.warning {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.875rem;
  font-weight: 700;
  color: var(--cnr-warn);
  --bng-icon-size: 1rem;
}
</style>
