<template>
  <CnrRoot class="cnr-hud">
    <template v-if="hud.visible">
      <div v-show="!helpShown" class="hud-center">
        <HudResult v-if="mode === 'result'" :result="hud.result" />
        <HudCenter v-else-if="mode === 'round'" :center="hud.center" />
      </div>
      <div class="hud-bottom">
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
      </div>
      <div v-if="helpShown" class="hud-help">
        <HowToPlay :rules="hud.help.rules" @close="ui({ action: 'help', open: false })" />
      </div>
    </template>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, watch, onMounted, onErrorCaptured } from "vue"
import { useEvents } from "@/services/events"
import { useBridge } from "@/bridge"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import HudCenter from "./HudCenter.vue"
import HudChase from "./HudChase.vue"
import HudNotices from "./HudNotices.vue"
import HudResult from "./HudResult.vue"
import HudChange from "./HudChange.vue"
import HudLobby from "./HudLobby.vue"
import HudPrep from "./HudPrep.vue"
import HudColor from "./HudColor.vue"
import HowToPlay from "./HowToPlay.vue"

const { api } = useBridge()
const events = useEvents()

const hud = ref({ visible: false })
const colorOpen = ref(false)
const mode = computed(() => hud.value.mode)
const chaseShown = computed(() => !!(hud.value.status || (hud.value.catch && hud.value.catch.visible)))
const helpShown = computed(() => !!(hud.value.visible && hud.value.help && hud.value.help.open && !hud.value.driving))
const colorAllowed = computed(() => !!(hud.value.visible && ((mode.value === "lobby" && hud.value.lobby) || (mode.value === "round" && hud.value.prep))))

watch(colorAllowed, allowed => {
  if (!allowed) colorOpen.value = false
})

function ui(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.ui(${api.serializeToLua(msg)}) end`)
}

function report(where, err) {
  try {
    const message = err && err.message ? err.message : String(err)
    const lines = err && typeof err.stack === "string" ? err.stack.split("\n").map(l => l.trim()) : []
    const at = lines.find(l => l.startsWith("at ")) || lines[0] || ""
    api.engineLua(`log("E","cnr_ui",${api.serializeToLua(`[cnr_ui] ${where}: ${message} | ${at}`)})`)
  } catch (e) {}
}

onErrorCaptured((err, instance, info) => {
  const options = (instance && instance.$options) || {}
  report(`${options.name || options.__name || "?"} ${info}`, err)
  return false
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

events.on("CnRHud", data => {
  try {
    hud.value = data && typeof data === "object" ? data : { visible: false }
  } catch (err) {
    report("CnRHud handler", err)
  }
})

onMounted(() => ui({ action: "hello" }))
</script>

<style scoped>
.cnr-hud {
  position: relative;
  width: 100%;
  height: 100%;
  overflow: hidden;
  pointer-events: none;
  font-family: var(--cnr-display);
  text-shadow: var(--cnr-shadow);
  --bng-icon-color: currentColor;
}
.hud-center {
  position: absolute;
  top: 22%;
  left: 0;
  right: 0;
  width: 48rem;
  max-width: calc(100% - 2rem);
  margin: 0 auto;
}
.hud-bottom {
  position: absolute;
  bottom: 4.5rem;
  left: 0;
  right: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  width: 40rem;
  max-width: calc(100% - 2rem);
  margin: 0 auto;
}
.hud-help {
  position: absolute;
  inset: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  pointer-events: none;
}
</style>
