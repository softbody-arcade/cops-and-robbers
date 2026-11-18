import assert from "node:assert/strict"
import { EventEmitter } from "node:events"
import { mock } from "node:test"
import * as Vue from "vue"
import { apps, buttonFor, controls, descendants, loadUi, node, renderer } from "./mount-ui.mjs"

const events = new EventEmitter()
const calls = []
const BngTabs = {
  props: ["modelValue"],
  emits: ["update:modelValue"],
  setup(props, { slots, emit }) {
    return () => {
      const tabs = slots.default()
      return Vue.h("tabs", [
        ...tabs.map((tab, i) => Vue.h("button", { onClick: () => emit("update:modelValue", i) }, tab.props["tab-heading"])),
        tabs[props.modelValue],
      ])
    }
  },
}
const BngDropdown = (_, { attrs, slots }) => Vue.h("dropdown", attrs, slots.display())
const module = await loadUi(new URL("CopsAndRobbersPanel/app.vue", apps), {
  "@/bridge": { useBridge: () => ({ api: { serializeToLua: JSON.stringify, engineLua: code => calls.push(code) } }) },
  "@/services": { $translate: { instant: key => key } },
  "@/services/events": { useEvents: () => ({
    on(name, listener) {
      events.on(name, listener)
      Vue.onBeforeUnmount(() => events.off(name, listener))
    },
  }) },
  "@/common/components/base": { ...controls, BngTabs, BngDropdown },
})
await module.evaluate()

const root = node("root")
const findText = text => descendants(root).find(n => n.text === text)
const button = label => buttonFor(root, label)
async function click(label) {
  const el = button(label)
  assert.ok(el && !el.props.disabled, label)
  el.props.onClick()
  await Vue.nextTick()
}

const car = { config: "vehicles/pickup/base.pc", label: "Pickup – Base" }
let state = {
  phase: "idle", map: "west_coast_usa", stationCount: 1,
  can: { settings: true, build: true }, settings: { carMode: "evolving", excludedModels: [] },
  build: { name: "Pickup", step: 2 },
}
async function update(patch = {}) {
  state = { ...state, ...patch }
  events.emit("CnRPanel", state)
  await Vue.nextTick()
}
const dropdown = () => descendants(root).find(n => n.type === "dropdown")
async function sendConfigs(list) {
  const request = calls.findLast(c => c.includes(".configs("))
  assert.ok(request, "requested a config list")
  const opts = JSON.parse(request.match(/\.configs\((.*)\) end$/)[1])
  events.emit("CnRConfigs", list, opts)
  await Vue.nextTick()
}
async function chooseCar() {
  dropdown().props.onOpen()
  await sendConfigs([car])
  dropdown().props["onUpdate:modelValue"](car.config)
  await Vue.nextTick()
}

mock.timers.enable({ apis: ["setInterval"] })
const app = renderer.createApp(module.namespace.default)
app.mount(root)
try {
  await update()
  await click("Settings")
  descendants(root).find(n => n.text.startsWith("More settings (")).parent.props.onClick()
  await Vue.nextTick()
  assert.ok(findText("Runner countdown"))
  await click("Reset to default")
  await click("Car")
  await chooseCar()
  await click("Start build with Pickup – Base")
  await click("Settings")
  assert.ok(findText("Runner countdown"), "More settings stays expanded across tabs")
  assert.ok(button("Reset to default"), "Settings reset confirmation is local to one visit")
  await click("Car")
  assert.ok(findText(car.label), "selected car is displayed on return")
  assert.ok(button("Start build with Pickup – Base").props.disabled, "selected build waits for config validation")
  await sendConfigs([car])
  assert.ok(button("Start build with Pickup – Base"), "build replacement needs a fresh confirmation")
  await click("Map")
  events.emit("CnRStations", { map: state.map, count: 1, nearest: [{ meters: 30 }], canRemove: true })
  await Vue.nextTick()
  assert.ok(findText("30 m"))
  assert.equal(button("Remove nearest").props.disabled, false)
  await click("Round")
  const before = calls.length
  mock.timers.tick(4000)
  assert.equal(calls.length, before, "Map stops polling while hidden")
  await click("Map")
  assert.ok(findText("30 m"), "cached station distances are visible on return")
  assert.ok(button("Remove nearest").props.disabled, "cached range cannot authorize removal")
  assert.equal(calls.length, before + 1)
  assert.match(calls.at(-1), /"action":"stations"/)
  mock.timers.tick(2000)
  assert.equal(calls.length, before + 2)
  await click("Round")
  await update({ map: "italy" })
  await click("Map")
  assert.equal(findText("30 m"), undefined, "previous map distances are discarded")
  events.emit("CnRStations", { map: "west_coast_usa", count: 1, nearest: [{ meters: 30 }], canRemove: true })
  await Vue.nextTick()
  assert.ok(button("Remove nearest").props.disabled)
  await update({ can: { settings: false, build: false } })
  await update({ can: { settings: true, build: true } })
  await click("Car")
  assert.equal(findText(car.label), undefined, "a build lock clears the pending choice")
  await chooseCar()
  await click("Round")
  await update({ settings: { ...state.settings, excludedModels: ["citybus"] } })
  await click("Car")
  events.emit("CnRConfigs", [car], { includeMods: false, excludedModels: [] })
  await Vue.nextTick()
  assert.ok(button("Start build with Pickup – Base")?.props.disabled, "late replies for earlier filters cannot enable the build")
  await sendConfigs([car])
  assert.equal(button("Start build with Pickup – Base").props.disabled, false, "a still-eligible selection survives a filter change")
  await click("Round")
  await click("Car")
  await sendConfigs([])
  assert.equal(findText(car.label), undefined, "refresh removes an unavailable config")
  await click("Map")
  events.emit("CnRStations", { map: state.map, count: 1, nearest: [{ meters: 120 }], canRemove: false })
  await Vue.nextTick()
  assert.ok(findText("120 m"))
  await click("Round")
  await update({ stationCount: 0 })
  await click("Map")
  assert.equal(findText("120 m"), undefined, "a changed station count invalidates hidden distances")
  await click("Settings")
  events.emit("CnRPanel", {})
  await Vue.nextTick()
  await update()
  assert.equal(findText("Runner countdown"), undefined, "a disconnected panel drops its fold state")
  await click("Car")
  assert.equal(calls.some(c => c.includes(".newBuild(") || c.includes('"action":"settings"')), false)
  await chooseCar()
  await click("Start build with Pickup – Base")
  await click("Click again to replace the build")
  const builds = calls.filter(c => c.includes(".newBuild("))
  assert.equal(builds.length, 1)
  assert.deepEqual(JSON.parse(builds[0].match(/\.newBuild\((.*)\) end$/)[1]), {
    includeMods: false, excludedModels: ["citybus"], config: car.config,
  })
  await click("Round")
  await click("Car")
  assert.equal(findText(car.label), undefined, "starting a build consumes the selected config")
} finally {
  app.unmount()
  mock.timers.reset()
}
assert.deepEqual(events.eventNames(), [])
assert.match(calls.at(-1), /"action":"close"/)
console.log("Host panel preserves tab choices, validates refreshed data and releases inactive tab actions and timers")
