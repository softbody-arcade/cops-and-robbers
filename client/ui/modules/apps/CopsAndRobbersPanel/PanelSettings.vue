<template>
  <div class="p-tab">
    <div v-if="locked" class="p-lock"><BngIcon :type="icons.lockClosed" />Stop the round first</div>
    <template v-for="group in visible" :key="group.id">
      <div v-if="group.toggle" class="p-sec more" @click="moreOpen = !moreOpen">
        <span class="p-grow">More settings ({{ moreCount }})</span>
        <BngIcon :type="moreOpen ? icons.arrowSmallDown : icons.arrowSmallRight" />
      </div>
      <template v-else>
        <div class="p-sec">{{ group.title }}</div>
        <div v-if="group.note" class="p-why">{{ group.note }}</div>
        <div v-for="item in group.items" :key="item.key" class="set" :class="{ list: item.kind === 'list' }">
          <span class="set-name">{{ item.label }}</span>
          <span class="set-control">
            <BngButton
              v-if="store.changed(item.key) && !locked"
              v-bng-tooltip:top="`Back to ${shown(item, store.defaultOf(item.key))}`"
              class="p-icon-btn"
              :accent="ACCENTS.ghost"
              :icon="icons.undo"
              @click="store.resetOne(item.key)"
            />
            <span v-if="item.kind === 'bool' && store.changed(item.key)" class="p-mono changed">{{ shown(item, store.valueOf(item.key)) }}</span>
            <BngSwitch
              v-if="item.kind === 'bool'"
              :model-value="store.valueOf(item.key) === true"
              :disabled="locked"
              @update:modelValue="v => store.change(item.key, v)"
            />
            <template v-else-if="item.kind !== 'list'">
              <BngButton class="p-icon-btn" :accent="ACCENTS.secondary" :icon="icons.minus" :disabled="locked" @click="store.step(item, -1)" />
              <span class="set-value p-mono" :class="{ changed: store.changed(item.key), pending: item.key in store.pending.value }">
                {{ shown(item, store.valueOf(item.key)) }}
              </span>
              <BngButton class="p-icon-btn" :accent="ACCENTS.secondary" :icon="icons.plus" :disabled="locked" @click="store.step(item, 1)" />
            </template>
          </span>
          <span class="set-help">{{ item.help }}</span>
          <input
            v-if="item.kind === 'list'"
            v-bng-text-input
            class="p-text set-list"
            :class="{ changed: store.changed(item.key) }"
            type="text"
            spellcheck="false"
            :disabled="locked"
            :value="store.draftOf(item.key)"
            @input="e => store.setDraft(item.key, e.target.value)"
            @keydown.enter="e => e.target.blur()"
            @blur="store.commitList(item.key)"
          />
        </div>
      </template>
    </template>
    <div class="p-buttons p-gap">
      <BngButton class="p-btn" :accent="ACCENTS.secondary" :disabled="locked" @click="emit('command', 'reload')">Reload config.json</BngButton>
      <BngButton class="p-btn" :accent="ACCENTS.destructive" :disabled="locked" @click="resetAll">
        {{ armed === "all" ? "Click again to reset" : "Reset to default" }}
      </BngButton>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"
import { BngButton, BngIcon, BngSwitch, ACCENTS, icons } from "@/common/components/base"
import { vBngTextInput, vBngTooltip } from "@/common/directives"
import { settingGroups, shown } from "./settings.js"
import { useConfirm } from "./confirm.js"

const props = defineProps({
  state: { type: Object, required: true },
  store: { type: Object, required: true },
})
const emit = defineEmits(["command"])

const { armed, confirm } = useConfirm()
const moreOpen = ref(false)

const locked = computed(() => !(props.state.can && props.state.can.settings === true))

const groups = computed(() => settingGroups(props.state.settings || {}))
const earth = computed(() => props.state.geo === true)
const open = item => !item.when || item.when(props.store.valueOf)
const common = computed(() =>
  groups.value
    .map(g => g.title === "Sky" && earth.value
      ? { id: `c-${g.title}`, title: g.title, items: [], note: "Not available on BeamNG.Earth yet" }
      : { id: `c-${g.title}`, title: g.title, items: g.items.filter(i => i.common && open(i)) })
    .filter(g => g.items.length || g.note)
)
const more = computed(() =>
  groups.value
    .filter(g => !(g.title === "Sky" && earth.value))
    .map(g => ({ id: `m-${g.title}`, title: g.title, items: g.items.filter(i => !i.common && open(i)) }))
    .filter(g => g.items.length)
)
const moreCount = computed(() => more.value.reduce((n, g) => n + g.items.length, 0))
const visible = computed(() => [...common.value, { id: "toggle", toggle: true }, ...(moreOpen.value ? more.value : [])])

function resetAll() {
  confirm("all", true, () => props.store.resetAll())
}
</script>

<style scoped>
.more {
  display: flex;
  align-items: center;
  cursor: pointer;
  --bng-icon-size: 1rem;
}
.set {
  display: grid;
  grid-template-columns: 1fr auto;
  align-items: center;
  gap: 0 0.75rem;
  margin-top: 0.25rem;
  padding: 0.25rem 0.5rem;
  background: var(--cnr-row);
  border-radius: var(--bng-corners-1);
}
.set-name {
  font-weight: 600;
}
.set-control {
  grid-column: 2;
  grid-row: 1 / span 2;
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
}
.set.list .set-control {
  grid-row: 1;
}
.set-help {
  grid-column: 1;
  font-size: 0.75rem;
  line-height: 1.25;
  color: var(--cnr-muted);
}
.set.list .set-help {
  grid-column: 1 / span 2;
}
.set-list {
  grid-column: 1 / span 2;
  margin-top: 0.25rem;
}
.set-value {
  min-width: 4rem;
  text-align: center;
}
.changed {
  color: var(--cnr-me);
}
.set-value.pending {
  font-style: italic;
}
</style>
