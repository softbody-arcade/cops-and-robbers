<template>
  <div class="p-tab">
    <div v-if="locked" class="p-lock"><BngIcon :type="icons.lockClosed" />Stop the round first to change the car</div>
    <div class="p-seg">
      <BngButton class="p-btn" :accent="evolving ? ACCENTS.ghost : ACCENTS.secondary" :disabled="locked" @click="setMode('random')">Random car</BngButton>
      <BngButton class="p-btn" :accent="evolving ? ACCENTS.secondary : ACCENTS.ghost" :disabled="locked" @click="setMode('evolving')">Evolving build</BngButton>
    </div>
    <div class="p-sub">{{ evolving ? "One shared car; each runner makes one change in prep" : "A new random car every round" }}</div>

    <template v-if="evolving">
      <div class="p-box">
        <template v-if="build">
          <div class="p-box-title">{{ build.name }} · step <span class="p-mono">{{ build.step }}</span></div>
          <div class="p-muted">{{ lastChangeText }}</div>
        </template>
        <template v-else>
          <div class="p-box-title">No build yet</div>
          <div class="p-muted">Choose a car or a random one to start the build</div>
        </template>
      </div>

      <template v-if="!locked">
        <div class="p-sec">New build</div>
        <div class="p-buttons">
          <BngDropdown v-model="choice" class="car-pick" :items="configs" show-search @open="loadConfigs">
            <template #display>
              <span class="car-pick-text">{{ choiceLabel || "Choose a car…" }}</span>
            </template>
          </BngDropdown>
          <BngButton class="p-btn p-fit" :accent="ACCENTS.secondary" @click="random">
            {{ armed === "random" ? "Click again to replace" : "Random" }}
          </BngButton>
        </div>
        <div v-if="choice" class="p-buttons">
          <BngButton class="p-btn" :accent="ACCENTS.main" @click="startChosen">
            {{ armed === "choose" ? "Click again to replace the build" : `Start build with ${choiceLabel || "this car"}` }}
          </BngButton>
        </div>
        <div v-if="build && (armed === 'choose' || armed === 'random')" class="p-why">This replaces the build at step {{ build.step }}</div>
        <div v-if="build" class="p-buttons">
          <BngButton class="p-btn" :accent="ACCENTS.destructive" @click="reset">
            {{ armed === "reset" ? "Click again to reset" : "Reset build" }}
          </BngButton>
        </div>
      </template>
    </template>

    <div class="p-sec">Cars that can be picked</div>
    <BngSwitch
      class="p-switch"
      :model-value="store.valueOf('includeModVehicles') === true"
      :disabled="locked"
      label-before
      :inline="false"
      @update:modelValue="v => store.change('includeModVehicles', v)"
    >
      Include mod cars
    </BngSwitch>
    <div class="excluded">
      <span class="p-grow">
        Excluded: <span class="p-muted">{{ excludedText }}</span>
      </span>
      <BngButton v-if="!locked" class="p-btn p-fit" :accent="ACCENTS.ghost" @click="editing = !editing">{{ editing ? "Done" : "Edit" }}</BngButton>
    </div>
    <div v-if="editing && !locked" class="p-field">
      <span class="p-muted">Model names, separated by commas</span>
      <input
        v-bng-text-input
        class="p-text"
        type="text"
        spellcheck="false"
        :disabled="locked"
        :value="store.draftOf('excludedModels')"
        @input="e => store.setDraft('excludedModels', e.target.value)"
        @keydown.enter="e => e.target.blur()"
        @blur="store.commitList('excludedModels')"
      />
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"
import { useBridge } from "@/bridge"
import { useEvents } from "@/services/events"
import { BngButton, BngDropdown, BngIcon, BngSwitch, ACCENTS, icons } from "@/common/components/base"
import { vBngTextInput } from "@/common/directives"
import { useConfirm } from "./confirm.js"

const props = defineProps({
  state: { type: Object, required: true },
  store: { type: Object, required: true },
})
const emit = defineEmits(["newBuild", "resetBuild"])

const { api } = useBridge()
const events = useEvents()
const { armed, confirm } = useConfirm()

const configs = ref([])
const choice = ref(null)
const editing = ref(false)

const can = computed(() => props.state.can || {})
const locked = computed(() => can.value.build !== true)
const evolving = computed(() => props.store.valueOf("carMode") === "evolving")
const build = computed(() => (props.state.build && typeof props.state.build === "object" ? props.state.build : null))
const choiceLabel = computed(() => (configs.value.find(c => c.value === choice.value) || {}).label || "")

const excludedText = computed(() => {
  const list = props.store.valueOf("excludedModels")
  const names = props.state.excludedNames
  const known = names && typeof names === "object" && !Array.isArray(names) ? names : {}
  const shown = Array.isArray(list) ? list.map(m => known[m] || m) : []
  return shown.length ? shown.join(", ") : "none"
})

const lastChangeText = computed(() => {
  const c = build.value && build.value.lastChange
  if (!c || typeof c !== "object") return "No changes yet"
  return c.by ? `Last change by ${c.by}: ${c.text}` : `Last change: ${c.text}`
})

function filter() {
  const excluded = props.store.valueOf("excludedModels")
  return { includeMods: props.store.valueOf("includeModVehicles") === true, excludedModels: Array.isArray(excluded) ? excluded : [] }
}

function loadConfigs() {
  api.engineLua(`if copsAndRobbers then copsAndRobbers.configs(${api.serializeToLua(filter())}) end`)
}

function setMode(mode) {
  if (props.store.valueOf("carMode") === mode) return
  props.store.save({ carMode: mode }, false)
}

function startChosen() {
  const config = choice.value
  confirm("choose", !!build.value, () => {
    emit("newBuild", { ...filter(), config })
    choice.value = null
  })
}

function random() {
  confirm("random", !!build.value, () => emit("newBuild", { ...filter(), random: true }))
}

function reset() {
  confirm("reset", true, () => emit("resetBuild"))
}

events.on("CnRConfigs", data => {
  configs.value = Array.isArray(data) ? data.map(c => ({ value: c.config, label: c.label })) : []
})
</script>

<style scoped>
.excluded {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.5rem;
}
.car-pick {
  flex: 1 1 0;
  min-width: 0;
}
.car-pick-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
