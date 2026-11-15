<template>
  <section class="cnr-card">
    <header class="cnr-card-head">
      <BngCardHeading type="line" class="cnr-card-title">{{ title }}</BngCardHeading>
      <span v-if="sub" class="cnr-card-sub">{{ sub }}</span>
      <BngButton v-if="closable" accent="ghost" icon="xmark" class="cnr-card-close" @click="emit('close')" />
    </header>
    <div class="cnr-card-body"><slot /></div>
    <footer v-if="$slots.actions" class="cnr-card-actions"><slot name="actions" /></footer>
  </section>
</template>

<script setup>
import { BngButton, BngCardHeading } from "@/common/components/base"

defineProps({
  title: String,
  sub: String,
  closable: Boolean,
})
const emit = defineEmits(["close"])
</script>

<style scoped>
.cnr-card {
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  padding: 0.25rem 1rem 1rem;
  background: var(--cnr-card, rgba(var(--bng-off-black-rgb), 0.8));
  border-radius: var(--bng-corners-2);
  color: var(--cnr-text, var(--bng-off-white));
  font-family: var(--fnt-defs);
}
.cnr-card-head {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.cnr-card-title {
  flex: 1 1 auto;
  min-width: 0;
  font-family: var(--cnr-display, "Overpass", var(--fnt-defs));
}
.cnr-card-sub {
  font-size: 0.875rem;
  color: var(--cnr-muted, var(--bng-cool-gray-100));
}
.cnr-card-body {
  flex: 1 1 auto;
  min-height: 0;
}
.cnr-card-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.75rem;
}
</style>
