<template>
  <span class="cnr-chip" :class="role">{{ label }}</span>
</template>

<script setup>
defineProps({
  role: { type: String, default: "runner", validator: v => v === "runner" || v === "cop" },
  label: String,
})
</script>

<style scoped>
.cnr-chip {
  display: inline-block;
  padding: 0 0.5rem;
  border-radius: var(--bng-corners-1);
  font-size: 0.75rem;
  font-weight: 700;
  line-height: 1.25rem;
  text-transform: uppercase;
  color: var(--bng-off-white);
}
.cnr-chip.runner {
  background: var(--bng-add-red-500);
}
.cnr-chip.cop {
  background: var(--bng-add-blue-500);
}
</style>
