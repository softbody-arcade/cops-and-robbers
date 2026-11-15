<template>
  <div v-if="center" class="hud-center-block">
    <template v-if="center.kind === 'countdown'">
      <div class="kick">{{ center.label }}</div>
      <div class="number" :class="'tone-' + center.tone">{{ center.number }}</div>
    </template>
    <template v-else-if="center.kind === 'role'">
      <div v-if="center.car" class="kick muted">{{ center.car }}</div>
      <div class="title" :class="'tone-' + center.role">{{ center.title }}</div>
      <div v-if="center.rule" class="rule">{{ center.rule }}</div>
    </template>
    <div v-else-if="center.kind === 'flash'" class="title tone-good">{{ center.text }}</div>
    <div v-else-if="center.kind === 'applying'" class="title applying">{{ center.text }}</div>
  </div>
</template>

<script setup>
defineProps({
  center: Object,
})
</script>

<style scoped>
.hud-center-block {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}
.kick {
  font-size: 1rem;
  font-weight: 800;
  letter-spacing: 0.1em;
  text-transform: uppercase;
}
.number {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
  font-size: 5rem;
  font-weight: 700;
  line-height: 1;
}
.title {
  font-size: 2.5rem;
  font-style: italic;
  font-weight: 900;
  line-height: 1.1;
  letter-spacing: 0.01em;
}
.rule {
  max-width: 36rem;
  margin-top: 0.5rem;
  font-size: 1.125rem;
  font-weight: 600;
  line-height: 1.4;
}
.applying {
  animation: cnr-pulse 1.2s ease-in-out infinite alternate;
}
.muted {
  color: var(--cnr-muted);
}
.tone-runner {
  color: var(--cnr-runner-text);
}
.tone-cop {
  color: var(--cnr-cop-text);
}
.tone-warn {
  color: var(--cnr-warn);
}
.tone-good {
  color: var(--cnr-good);
}
@keyframes cnr-pulse {
  from {
    opacity: 1;
  }
  to {
    opacity: 0.6;
  }
}
</style>
