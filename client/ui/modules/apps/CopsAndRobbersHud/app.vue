<template>
  <CnrRoot class="cnr-hud">
    <template v-if="hud.visible">
      <div class="hud-center">
        <HudResult v-if="mode === 'result'" :result="hud.result" />
        <HudCenter v-else-if="mode === 'round'" :center="hud.center" />
      </div>
      <div class="hud-bottom">
        <HudNotices :notices="hud.notices" />
        <template v-if="mode === 'round'">
          <HudChange v-if="hud.change" :change="hud.change" @apply="ui({ action: 'apply' })" />
          <HudChase v-if="chaseShown" :status="hud.status" :bar="hud.catch" />
        </template>
      </div>
    </template>
  </CnrRoot>
</template>

<script setup>
import { ref, computed, onMounted } from "vue"
import { useEvents } from "@/services/events"
import { useBridge } from "@/bridge"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import HudCenter from "./HudCenter.vue"
import HudChase from "./HudChase.vue"
import HudNotices from "./HudNotices.vue"
import HudResult from "./HudResult.vue"
import HudChange from "./HudChange.vue"

const { api } = useBridge()
const events = useEvents()

const hud = ref({ visible: false })
const mode = computed(() => hud.value.mode)
const chaseShown = computed(() => !!(hud.value.status || (hud.value.catch && hud.value.catch.visible)))

function ui(msg) {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.ui(${api.serializeToLua(msg)}) end`)
}

events.on("CnRHud", data => {
  hud.value = data && typeof data === "object" ? data : { visible: false }
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
</style>
