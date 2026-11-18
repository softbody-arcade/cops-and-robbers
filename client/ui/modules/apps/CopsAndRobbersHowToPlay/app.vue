<template>
  <CnrRoot ref="box" class="cnr-fit-box">
    <div v-if="shown" ref="card" class="cnr-fit-content howto-card" :style="fit">
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
.howto-card {
  display: flex;
  flex-direction: column;
  width: 100%;
  min-height: calc(100% / var(--cnr-fit-growth, 1));
}
</style>
