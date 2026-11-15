<template>
  <CnrRoot ref="box" class="cnr-announce">
    <div ref="content" class="announce" :style="fit">
      <template v-if="hud.visible">
        <HudResult v-if="mode === 'result'" :result="hud.result" />
        <HudCenter v-else-if="mode === 'round'" :center="hud.center" />
      </template>
    </div>
  </CnrRoot>
</template>

<script setup>
import { ref, computed } from "vue"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import { useCnrHud } from "../../copsAndRobbers/hud.js"
import { useFit } from "../../copsAndRobbers/fit.js"
import HudCenter from "./HudCenter.vue"
import HudResult from "./HudResult.vue"

const { hud } = useCnrHud("announcements")
const box = ref(null)
const content = ref(null)
const fit = useFit(box, content)

const mode = computed(() => hud.value.mode)
</script>

<style scoped>
.cnr-announce {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  overflow: hidden;
  pointer-events: none;
  font-family: var(--cnr-display);
  text-shadow: var(--cnr-shadow-strong);
  --bng-icon-color: currentColor;
}
.announce {
  flex: none;
  box-sizing: border-box;
  max-width: 100%;
  padding: 0 0.5rem;
  overflow-wrap: anywhere;
  transform-origin: center;
}
</style>
