<template>
  <CnrRoot ref="box" class="cnr-hud">
    <div ref="stack" class="hud-stack" :style="fit">
      <template v-if="hud.visible">
        <HudNotices :notices="hud.notices" />
        <template v-if="mode === 'lobby' && hud.lobby">
          <HudColor v-if="colorOpen" :color="hud.lobby.color" @pick="pickColor" @close="colorOpen = false" />
          <HudLobby v-else :lobby="hud.lobby" @color="colorOpen = true" @help="openHelp" @toggle="toggleApp" />
        </template>
        <template v-if="mode === 'round'">
          <HudChange v-if="hud.change" :change="hud.change" @apply="ui({ action: 'apply' })" />
          <template v-if="hud.prep">
            <HudColor v-if="colorOpen" :color="hud.prep.color" @pick="pickColor" @close="colorOpen = false" />
            <HudPrep v-else :prep="hud.prep" @color="colorOpen = true" @help="openHelp" @toggle="toggleApp" />
          </template>
          <HudChase v-if="chaseShown" :status="hud.status" :bar="hud.catch" />
        </template>
      </template>
    </div>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, watch } from "vue"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import { useCnrHud } from "../../copsAndRobbers/hud.js"
import { useFit } from "../../copsAndRobbers/fit.js"
import HudChase from "./HudChase.vue"
import HudNotices from "./HudNotices.vue"
import HudChange from "./HudChange.vue"
import HudLobby from "./HudLobby.vue"
import HudPrep from "./HudPrep.vue"
import HudColor from "./HudColor.vue"

const { hud, ui } = useCnrHud("hud")
const box = ref(null)
const stack = ref(null)
const fit = useFit(box, stack)

const colorOpen = ref(false)
const mode = computed(() => hud.value.mode)
const chaseShown = computed(() => !!(hud.value.status || (hud.value.catch && hud.value.catch.visible)))
const colorAllowed = computed(() => !!(hud.value.visible && ((mode.value === "lobby" && hud.value.lobby) || (mode.value === "round" && hud.value.prep))))

watch(colorAllowed, allowed => {
  if (!allowed) colorOpen.value = false
})

function openHelp() {
  ui({ action: "help", open: true })
}

function toggleApp(name) {
  ui({ action: "toggleApp", name })
}

function pickColor(hex) {
  colorOpen.value = false
  ui(hex ? { action: "color", hex } : { action: "color" })
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
  text-shadow: var(--cnr-shadow);
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
