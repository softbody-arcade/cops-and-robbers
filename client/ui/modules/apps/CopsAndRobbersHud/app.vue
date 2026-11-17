<template>
  <CnrRoot ref="box" class="cnr-hud">
    <div ref="stack" class="hud-stack" :style="fit">
      <template v-if="hud.visible">
        <HudNotices v-if="!settingsShown" :notices="hud.notices" />
        <template v-if="mode === 'lobby' && hud.lobby">
          <HudTab v-if="hud.lobby.hudHidden" @show="setHidden(false)" />
          <HudLobby v-else v-show="!settingsOpen" :lobby="hud.lobby" @settings="openSettings" @help="openHelp" @toggle="toggleApp" @hide="setHidden(true)" />
        </template>
        <template v-if="mode === 'round'">
          <HudChange v-if="hud.change" :change="hud.change" @apply="ui({ action: 'apply' })" />
          <template v-if="hud.prep">
            <HudPrep v-show="!settingsOpen" :prep="hud.prep" @settings="openSettings" @help="openHelp" @toggle="toggleApp" />
          </template>
          <HudChase v-if="chaseShown" :status="hud.status" :bar="hud.catch" />
        </template>
        <HudSettings
          v-if="settingsShown"
          v-model:draft="colorDraft"
          :settings="settings"
          @pick="hex => ui({ action: 'color', hex })"
          @clear="clearColor"
          @setting="(key, value) => ui({ action: 'setting', key, value })"
          @close="closeSettings"
        />
      </template>
    </div>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, watch, onBeforeUnmount } from "vue"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import { useCnrHud } from "../../copsAndRobbers/hud.js"
import { useFit } from "../../copsAndRobbers/fit.js"
import HudChase from "./HudChase.vue"
import HudNotices from "./HudNotices.vue"
import HudChange from "./HudChange.vue"
import HudLobby from "./HudLobby.vue"
import HudPrep from "./HudPrep.vue"
import HudSettings from "./HudSettings.vue"
import HudTab from "./HudTab.vue"

const { hud, ui } = useCnrHud("hud")
const box = ref(null)
const stack = ref(null)
const fit = useFit(box, stack)

const GAP_MS = 1500

const settingsOpen = ref(false)
const colorDraft = ref("")
const mode = computed(() => hud.value.mode)
const chaseShown = computed(() => !!(hud.value.status || (hud.value.catch && hud.value.catch.visible)))
const settingsAllowed = computed(() => !!(hud.value.visible && ((mode.value === "lobby" && hud.value.lobby && !hud.value.lobby.hudHidden) || (mode.value === "round" && hud.value.prep))))

const settingsShown = computed(() => settingsOpen.value && settingsAllowed.value)

const settings = computed(() => hud.value.settings || { headlights: false, siren: false, sirensAllowed: false })

let gapTimer = null

function stopGapTimer() {
  if (gapTimer !== null) clearTimeout(gapTimer)
  gapTimer = null
}

watch(settingsAllowed, allowed => {
  stopGapTimer()
  if (!allowed && settingsOpen.value) gapTimer = setTimeout(closeSettings, GAP_MS)
})

onBeforeUnmount(stopGapTimer)

function openHelp() {
  ui({ action: "help", open: true })
}

function toggleApp(name) {
  ui({ action: "toggleApp", name })
}

function setHidden(value) {
  ui({ action: "setting", key: "hudHidden", value })
}

function openSettings() {
  const color = settings.value.color
  colorDraft.value = color ? color.toUpperCase() : ""
  settingsOpen.value = true
}

function closeSettings() {
  stopGapTimer()
  settingsOpen.value = false
  colorDraft.value = ""
}

function clearColor() {
  colorDraft.value = ""
  ui({ action: "color" })
}
</script>

<style scoped>
.cnr-hud {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  align-items: center;
  width: 100%;
  height: 100%;
  overflow: hidden;
  pointer-events: none;
  font-family: var(--cnr-display);
  text-shadow: var(--cnr-shadow-strong);
  --bng-icon-color: currentColor;
}
.hud-stack {
  flex: none;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  box-sizing: border-box;
  width: 40rem;
  max-width: 100%;
  transform-origin: bottom center;
}
</style>
