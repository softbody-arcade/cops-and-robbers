<template>
  <div class="hud-spectate">
    <div class="spectate-top">
      <span class="item">
        <BngIcon :type="icons.movieCamera" />
        <span>SPECTATING · <span class="watched">{{ spectate.name }}</span></span>
      </span>
      <span v-if="spectate.time" class="item">
        <BngIcon :type="icons.stopwatchArrows02" />
        <span class="mono">{{ spectate.time }}</span>
        <span v-if="spectate.limit" class="mono limit">/ {{ spectate.limit }}</span>
      </span>
      <span v-if="spectate.heli" class="item">
        <BngIcon :type="icons.radar" />
        <span>{{ spectate.heli.text }}</span>
        <span v-if="spectate.heli.time" class="mono">{{ spectate.heli.time }}</span>
      </span>
    </div>
    <div v-if="spectate.forecast" class="spectate-forecast">
      <span class="item">
        <BngIcon :type="icons.weather" />
        <span>{{ spectate.forecast.text }}</span>
      </span>
      <span v-if="spectate.forecast.heli" class="forecast-heli">{{ spectate.forecast.heli }}</span>
    </div>
    <span class="buttons">
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="spectate.sitOut ? icons.play : icons.pause" @click="emit('sitOut', !spectate.sitOut)">
        {{ spectate.sitOut ? "Play" : "Sit out" }}
      </BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.info" @click="emit('help')">How to play</BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.cup" @click="emit('toggle', 'board')">
        <span>Leaderboard</span>
        <span v-if="apps.board" class="open-mark"></span>
      </BngButton>
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" :icon="icons.cogSolid" @click="emit('toggle', 'panel')">
        <span>Host panel</span>
        <span v-if="apps.panel" class="open-mark"></span>
      </BngButton>
    </span>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { BngButton, BngIcon, ACCENTS, icons } from "@/common/components/base"

const props = defineProps({
  spectate: { type: Object, required: true },
})
const emit = defineEmits(["sitOut", "help", "toggle"])

const apps = computed(() => props.spectate.apps || {})
</script>

<style scoped>
.hud-spectate {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  max-width: 100%;
}
.spectate-top {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0.25rem 1.25rem;
  max-width: 100%;
  font-size: 1.25rem;
  font-weight: 700;
  white-space: nowrap;
  --bng-icon-size: 1.5rem;
}
.spectate-forecast {
  display: flex;
  flex-direction: column;
  align-items: center;
  font-size: 1.25rem;
  font-weight: 700;
  white-space: nowrap;
  --bng-icon-size: 1.5rem;
}
.forecast-heli {
  font-size: 1rem;
  font-weight: 600;
}
.item {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 0.25rem;
}
.watched {
  font-weight: 900;
}
.mono {
  font-family: var(--fnt-mono);
  font-variant-numeric: tabular-nums;
}
.limit {
  font-weight: 600;
}
.buttons {
  display: inline-flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 0.5rem;
  text-shadow: none;
}
.hud-spectate .cnr-btn {
  pointer-events: auto;
  font-size: 0.875rem;
  line-height: 1.25rem;
  --bng-icon-size: 1rem;
}
.open-mark {
  position: absolute;
  left: 0.5rem;
  right: 0.5rem;
  bottom: 0;
  height: 0.125rem;
  background: var(--cnr-accent);
}
</style>
