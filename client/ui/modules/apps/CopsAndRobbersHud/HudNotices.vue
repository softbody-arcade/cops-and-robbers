<template>
  <div v-if="items.length" class="hud-notices">
    <div v-for="n in items" :key="n.text" class="notice" :class="n.tone === 'warn' ? 'warn' : 'info'">
      <BngIcon :type="n.tone === 'warn' ? icons.caution : icons.info" />
      <span>{{ n.text }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngIcon, icons } from "@/common/components/base"

const props = defineProps({
  notices: [Array, Object],
})

const items = computed(() => (Array.isArray(props.notices) ? props.notices.slice(0, 2) : []))
</script>

<style scoped>
.hud-notices {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.25rem;
  max-width: 100%;
  --bng-icon-size: 1.25rem;
}
.notice {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  max-width: 100%;
  font-size: 1rem;
  font-weight: 700;
}
.notice span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.warn {
  color: var(--cnr-warn);
}
.info {
  color: var(--cnr-muted);
}
</style>
