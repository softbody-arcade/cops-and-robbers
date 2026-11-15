<template>
  <div v-if="result" class="hud-result">
    <div class="title" :class="'tone-' + titleTone">{{ result.title }}</div>
    <div v-if="result.runner || result.catchers" class="summary">
      <template v-if="result.runner">{{ result.runner }} survived <span v-if="result.time" class="mono">{{ result.time }}</span></template>
      <template v-if="result.catchers">{{ result.runner ? " · caught by " : "Caught by " }}{{ result.catchers }}</template>
    </div>
    <div v-if="rows.length" class="rows">
      <div v-for="r in rows" :key="r.rank" class="row" :class="{ me: r.me }">
        <span class="player">{{ r.rank }} · {{ r.player }}</span>
        <span class="mono">{{ r.time }}</span>
      </div>
    </div>
    <div v-if="result.nextIn" class="next">NEXT ROUND IN <span class="mono">{{ result.nextIn }}</span></div>
  </div>
</template>

<script setup>
import { computed } from "vue"

const TITLE_TONES = { "RUNNER CAUGHT": "runner", ESCAPED: "good" }

const props = defineProps({
  result: Object,
})

const titleTone = computed(() => TITLE_TONES[props.result && props.result.title] || "muted")
const rows = computed(() => (props.result && Array.isArray(props.result.rows) ? props.result.rows.slice(0, 3) : []))
</script>

<style scoped>
.hud-result {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}
.title {
  font-size: 2.5rem;
  font-style: italic;
  font-weight: 900;
  line-height: 1.1;
  letter-spacing: 0.01em;
}
.summary {
  margin-top: 0.25rem;
  font-size: 1.25rem;
  font-weight: 700;
}
.rows {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  width: 20rem;
  max-width: 100%;
  margin-top: 0.75rem;
  font-size: 1rem;
  font-weight: 600;
  text-shadow: none;
}
.row {
  display: flex;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.25rem 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.row.me {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-me);
}
.player {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.next {
  margin-top: 0.75rem;
  font-size: 1rem;
  font-weight: 800;
  letter-spacing: 0.1em;
  color: var(--cnr-muted);
}
.mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.tone-runner {
  color: var(--cnr-runner-text);
}
.tone-good {
  color: var(--cnr-good);
}
.tone-muted {
  color: var(--cnr-muted);
}
</style>
