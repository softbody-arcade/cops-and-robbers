<template>
  <CnrCard class="hud-settings" title="Your settings" closable @close="emit('close')">
    <div class="section">Car colour</div>
    <BngColorPicker v-model="hsl" view="compact_luminosity" @change="fromPicker" />
    <div class="hex-row">
      <span class="cnr-swatch" :class="{ empty: !valid }" :style="valid ? { background: normalized } : null"></span>
      <input
        :value="draft"
        v-bng-text-input
        class="hex"
        :class="{ bad: draft && !valid }"
        type="text"
        maxlength="7"
        spellcheck="false"
        placeholder="#RRGGBB"
        @input="fromText"
        @keydown.enter="done"
      />
      <BngButton class="cnr-btn" :accent="ACCENTS.secondary" @click="clear">No colour</BngButton>
    </div>
    <div v-if="draft && !valid" class="hint">Use six hex digits, like #2FB36B</div>
    <div class="divider"></div>
    <div class="row">
      <div class="label">
        <div class="name">Auto headlights</div>
        <div class="desc">On at night and in bad weather</div>
      </div>
      <BngSwitch :model-value="settings.headlights === true" @update:modelValue="v => emit('setting', 'headlights', v)" />
    </div>
    <div class="row" :class="{ off: !settings.sirensAllowed }">
      <div class="label">
        <div class="name">Siren</div>
        <div class="desc">{{ settings.sirensAllowed ? "As a cop, once cops are released" : "Turned off by the host" }}</div>
      </div>
      <BngSwitch
        :model-value="settings.sirensAllowed === true && settings.siren === true"
        :disabled="!settings.sirensAllowed"
        @update:modelValue="v => emit('setting', 'siren', v)"
      />
    </div>
    <div class="row stack">
      <div class="label">
        <div class="name">Route to the runner</div>
        <div class="desc">As a cop</div>
      </div>
      <div class="choices">
        <BngButton
          v-for="c in ROUTES"
          :key="c.value"
          class="cnr-btn"
          :accent="(settings.route || 'sight') === c.value ? ACCENTS.main : ACCENTS.secondary"
          @click="emit('setting', 'route', c.value)"
        >{{ c.label }}</BngButton>
      </div>
    </div>
    <template #actions>
      <BngButton class="cnr-btn" :accent="ACCENTS.main" :disabled="!!draft && !valid" @click="done">Done</BngButton>
    </template>
  </CnrCard>
</template>

<script setup>
import { ref, computed, watch } from "vue"
import { BngButton, BngColorPicker, BngSwitch, ACCENTS } from "@/common/components/base"
import { vBngTextInput } from "@/common/directives"
import CnrCard from "../../copsAndRobbers/CnrCard.vue"
import { hexToHsl, hslToHex } from "../../copsAndRobbers/format.js"

const ROUTES = [
  { value: "always", label: "Always" },
  { value: "sight", label: "Out of sight" },
  { value: "never", label: "Never" },
]

const HEX = /^#?[0-9a-fA-F]{6}$/

const props = defineProps({
  settings: { type: Object, required: true },
  draft: { type: String, default: "" },
})
const emit = defineEmits(["pick", "clear", "setting", "close", "update:draft"])

const NEUTRAL = { hue: 0.5, saturation: 1, luminosity: 0.5 }
const hsl = ref(HEX.test(props.draft) ? hexToHsl(props.draft.replace("#", "")) : { ...NEUTRAL })
const cleared = ref(false)

watch(() => props.settings.color, () => {
  cleared.value = false
})

const valid = computed(() => HEX.test(props.draft.trim()))
const normalized = computed(() => (valid.value ? `#${props.draft.trim().replace("#", "").toLowerCase()}` : ""))

function fromPicker() {
  emit("update:draft", hslToHex(hsl.value).toUpperCase())
}

function fromText(e) {
  const text = e.target.value
  emit("update:draft", text)
  if (HEX.test(text.trim())) hsl.value = hexToHsl(text.trim().replace("#", ""))
}

function clear() {
  hsl.value = { ...NEUTRAL }
  cleared.value = true
  emit("clear")
}

function done() {
  if (props.draft && !valid.value) return
  const saved = cleared.value ? "" : (props.settings.color || "").toLowerCase()
  if (valid.value && normalized.value !== saved) emit("pick", normalized.value)
  emit("close")
}
</script>

<style scoped>
.hud-settings {
  width: 26rem;
  max-width: 100%;
  text-shadow: none;
  pointer-events: auto;
}
.hud-settings :deep(.cnr-card-title) {
  font-size: 1.125rem;
}
.section {
  margin: 0.5rem 0;
  font-size: 0.875rem;
  font-weight: 700;
  color: var(--cnr-muted);
}
.hex-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.75rem;
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
.hint {
  margin-top: 0.5rem;
  font-size: 0.875rem;
  font-weight: 700;
  color: var(--cnr-warn);
}
.divider {
  height: 0.0625rem;
  margin: 0.75rem 0 0.25rem;
  background: var(--cnr-muted);
  opacity: 0.4;
}
.row {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-top: 0.5rem;
}
.choices {
  display: flex;
  flex: 0 0 auto;
  gap: 0.25rem;
}
.row.stack {
  flex-direction: column;
  align-items: stretch;
  gap: 0.25rem;
}
.row.stack .choices {
  display: flex;
  gap: 0.5rem;
}
.row.stack .choices :deep(.cnr-btn) {
  flex: 1 1 0;
  min-width: 0;
}
.row.off .label {
  opacity: 0.5;
}
.label {
  flex: 1 1 auto;
  min-width: 0;
}
.name {
  font-size: 1rem;
  font-weight: 700;
}
.desc {
  font-size: 0.875rem;
  color: var(--cnr-muted);
}
</style>
