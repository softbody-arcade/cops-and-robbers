<template>
  <div v-if="center" class="hud-center-block">
    <template v-if="center.kind === 'countdown'">
      <div class="kick">{{ center.label }}</div>
      <div class="number" :class="'tone-' + center.tone">{{ center.number }}</div>
    </template>
    <template v-else-if="center.kind === 'role'">
      <div v-if="center.car" class="kick">{{ center.car }}</div>
      <div class="title" :class="'tone-' + center.role">{{ center.title }}</div>
      <div v-if="center.role === 'cop' && center.runner" class="runner-line"><b class="runner-name">{{ center.runner }}</b> {{ runnerVerb }}</div>
    </template>
    <div v-else-if="center.kind === 'flash'" class="title tone-good">{{ center.text }}</div>
    <div v-else-if="center.kind === 'applying'" class="title applying">{{ center.text }}</div>
  </div>
</template>

<script setup>
import { computed } from "vue"

const AI_NAME = /^AI (runner|cop)( \d+)?$/

const props = defineProps({
  center: Object,
})

const runnerVerb = computed(() => (AI_NAME.test((props.center && props.center.runner) || "") ? "runs" : "is the runner"))
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
.runner-line {
  max-width: 36rem;
  margin-top: 0.5rem;
  font-size: 1.125rem;
  font-weight: 600;
  line-height: 1.4;
}
.runner-name {
  font-weight: 900;
}
.applying {
  animation: cnr-pulse 1.2s ease-in-out infinite alternate;
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
    opacity: 0.85;
  }
}
</style>
