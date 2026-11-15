<template>
  <CnrCard class="hud-color" title="Your car colour" closable @close="emit('close')">
    <BngColorPicker v-model="hsl" view="compact_luminosity" @change="fromPicker" />
    <div class="hex-row">
      <span class="swatch" :class="{ empty: !valid }" :style="valid ? { background: normalized } : null"></span>
      <input
        v-model="hexText"
        v-bng-text-input
        class="hex"
        :class="{ bad: hexText && !valid }"
        type="text"
        maxlength="7"
        spellcheck="false"
        placeholder="#RRGGBB"
        @input="fromText"
        @keydown.enter="done"
      />
      <BngButton class="hud-btn" :accent="ACCENTS.secondary" @click="emit('pick', null)">No colour</BngButton>
      <BngButton class="hud-btn done" :accent="ACCENTS.main" :disabled="!valid" @click="done">Done</BngButton>
    </div>
    <div v-if="hexText && !valid" class="hint">Use six hex digits, like #2FB36B</div>
  </CnrCard>
</template>

<script setup>
import { ref, computed } from "vue"
import { BngButton, BngColorPicker, ACCENTS } from "@/common/components/base"
import { vBngTextInput } from "@/common/directives"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import { hexToHsl, hslToHex } from "../../copsAndRobbers/format.js"

const HEX = /^#?[0-9a-fA-F]{6}$/

const props = defineProps({
  color: String,
})
const emit = defineEmits(["pick", "close"])

const start = HEX.test(props.color || "") ? props.color.replace("#", "") : ""
const hexText = ref(start ? `#${start.toUpperCase()}` : "")
const hsl = ref(start ? hexToHsl(start) : { hue: 0.5, saturation: 1, luminosity: 0.5 })

const valid = computed(() => HEX.test(hexText.value.trim()))
const normalized = computed(() => (valid.value ? `#${hexText.value.trim().replace("#", "").toLowerCase()}` : ""))

function fromPicker() {
  hexText.value = hslToHex(hsl.value).toUpperCase()
}

function fromText() {
  if (valid.value) hsl.value = hexToHsl(normalized.value)
}

function done() {
  if (valid.value) emit("pick", normalized.value)
}
</script>

<style scoped>
.hud-color {
  width: 26rem;
  max-width: 100%;
  text-shadow: none;
  pointer-events: auto;
}
.hud-color :deep(.cnr-card-title) {
  font-size: 1.125rem;
}
.hex-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.75rem;
}
.swatch {
  flex: 0 0 auto;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: var(--bng-corners-1);
  box-shadow: 0 0 0 0.125rem var(--cnr-muted);
}
.swatch.empty {
  background: transparent;
}
.hex {
  flex: 0 0 auto;
  box-sizing: border-box;
  width: 7rem;
  height: 2rem;
  padding: 0 0.5rem;
  border: 0;
  border-radius: var(--bng-corners-1);
  outline: none;
  background: var(--cnr-row);
  box-shadow: inset 0 0 0 0.125rem var(--cnr-muted);
  color: var(--cnr-text);
  font-family: var(--fnt-mono);
  font-size: 1rem;
  font-variant-numeric: tabular-nums;
  text-transform: uppercase;
}
.hex:focus {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-accent);
}
.hex.bad {
  box-shadow: inset 0 0 0 0.125rem var(--cnr-warn);
}
.hud-color .hud-btn {
  font-family: var(--cnr-display);
  font-weight: 700;
  --bng-button-margin: 0;
}
.done {
  margin-left: auto;
}
.hint {
  margin-top: 0.5rem;
  font-size: 0.875rem;
  font-weight: 700;
  color: var(--cnr-warn);
}
</style>
