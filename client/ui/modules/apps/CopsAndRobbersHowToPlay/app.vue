<template>
  <CnrRoot ref="box" class="cnr-howto">
    <div v-if="shown" ref="card" class="howto-card" :style="fit">
      <HowToPlay :rules="hud.help.rules" :units="hud.help.units" @close="ui({ action: 'help', open: false })" />
    </div>
  </CnrRoot>
</template>

<script setup>
import { ref, computed } from "vue"
import CnrRoot from "../../copsAndRobbers/CnrRoot.vue"
import { useCnrHud } from "../../copsAndRobbers/hud.js"
import { useFit } from "../../copsAndRobbers/fit.js"
import HowToPlay from "./HowToPlay.vue"

const { hud, ui } = useCnrHud("howtoplay")
const box = ref(null)
const card = ref(null)
const fit = useFit(box, card)

const shown = computed(() => !!(hud.value.visible && hud.value.help && hud.value.help.open && !hud.value.driving && hud.value.mode !== "result"))
</script>

<style scoped>
.cnr-howto {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  overflow: hidden;
  pointer-events: none;
  --bng-icon-color: currentColor;
}
.howto-card {
  flex: none;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  width: 100%;
  min-height: 100%;
  transform-origin: center;
}
</style>
