import assert from "node:assert/strict"
import * as Vue from "vue"
import { apps, buttonFor, descendants, loadUi, node, renderer } from "./mount-ui.mjs"

const hud = Vue.ref({})
const actions = []
const mocks = {
  "../../copsAndRobbers/hud.js": { useCnrHud: () => ({ hud, ui: action => actions.push(action) }) },
  "../../copsAndRobbers/fit.js": { useFit: () => ({}) },
}

const module = await loadUi(new URL("CopsAndRobbersHud/app.vue", apps), mocks)
await module.evaluate()
for (const state of [
  { mode: "lobby", lobby: {} },
  { mode: "round", prep: {}, change: { title: "New change", canApply: true } },
  { mode: "round", status: { role: "runner", time: "3:12" }, catch: { visible: true, label: "BEING CAUGHT" } },
  { mode: "round", status: { role: "cop", time: "3:12" } },
  { mode: "round", spectate: { name: "Free camera", time: "3:12", forecast: { text: "Forecast: clearing" } } },
]) {
  hud.value = { visible: true, notices: [{ text: "Round notice" }], settings: { lightning: true }, ...state }
  const root = node("root")
  const app = renderer.createApp(module.namespace.default)
  app.mount(root)
  const button = buttonFor(root, "Settings")
  assert.ok(button, `Settings button for ${JSON.stringify(state)}`)
  const oldText = descendants(root).map(el => el.text).filter(Boolean)
  button.props.onClick()
  await Vue.nextTick()
  const settingsText = descendants(root).map(el => el.text)
  for (const text of oldText) assert.ok(!settingsText.includes(text), `HUD content still visible in Settings: ${text}`)
  const label = descendants(root).find(el => el.text === "Lightning flashes")
  assert.ok(label, `Lightning flashes switch for ${JSON.stringify(state)}`)
  const toggle = descendants(label.parent.parent).find(el => el.type === "switch")
  assert.equal(toggle.props["model-value"], true)
  toggle.props["onUpdate:modelValue"](false)
  assert.deepEqual(actions.pop(), { action: "setting", key: "lightning", value: false })
  if (state.spectate) hud.value.spectate.time = "3:19"
  buttonFor(root, "Done").props.onClick()
  await Vue.nextTick()
  const restored = descendants(root).map(el => el.text)
  for (const text of oldText) {
    assert.ok(restored.includes(state.spectate && text === "3:12" ? "3:19" : text))
  }
  app.unmount()
}
console.log("HUD Settings opens and changes Lightning flashes in lobby, prep, both chase roles and spectator mode")

const panel = await loadUi(new URL("CopsAndRobbersPanel/PanelSettings.vue", apps))
const settings = await loadUi(new URL("CopsAndRobbersPanel/settings.js", apps))
await panel.evaluate()
await settings.evaluate()
const state = Vue.ref({ can: { settings: true }, settings: {
  weather: "thunderstorm", weatherChanges: false, lightningMinSeconds: 5, lightningMaxSeconds: 5,
} })
const store = settings.namespace.useSettings(state, () => {}, () => {})
const root = node("root")
const app = renderer.createApp(panel.namespace.default, { state: state.value, store })
app.mount(root)

const limitKey = "roundTimeLimitSeconds"
const limitRow = descendants(root).find(el => el.text === "Time limit").parent
for (const [seconds, label, direction, expected] of [
  [1800, "30 min", 1, 2100], [1800, "30 min", -1, 1500],
  [300, "5 min", -1, 0], [0, "off", -1, 0], [0, "off", 1, 300],
  [765, "12:45", 1, 900], [765, "12:45", -1, 600],
]) {
  store.clear()
  state.value.settings[limitKey] = seconds
  await Vue.nextTick()
  assert.ok(descendants(limitRow).some(el => el.text === label), label)
  const buttons = descendants(limitRow).filter(el => el.type === "button")
  buttons[direction > 0 ? 1 : 0].props.onClick()
  assert.equal(store.valueOf(limitKey), expected)
}
store.clear()

function strikeRows(visible) {
  const nodes = descendants(root)
  for (const label of ["Minimum strike interval", "Maximum strike interval"]) {
    const index = nodes.findIndex(el => el.text === label)
    assert.equal(index >= 0, visible, label)
    if (visible) {
      const section = nodes.slice(0, index).findLast(el => el.props.class === "p-sec")
      assert.equal(section?.text, "Sky")
      assert.ok(descendants(nodes[index].parent).some(el => el.text === "5 s"))
    }
  }
}

strikeRows(false)
descendants(root).find(el => el.text.startsWith("More settings (")).parent.props.onClick()
await Vue.nextTick()
for (const [weather, weatherChanges, visible] of [
  ["thunderstorm", false, true], ["random", false, true], ["clear", true, true], ["storm", false, false],
]) {
  Object.assign(state.value.settings, { weather, weatherChanges })
  await Vue.nextTick()
  strikeRows(visible)
}
app.unmount()
console.log("Host panel shows strike intervals under More settings when thunderstorms are possible")

const fitModule = await loadUi(new URL("../copsAndRobbers/fit.js", apps))
await fitModule.evaluate()
let resize
globalThis.ResizeObserver = class {
  constructor(callback) { resize = callback }
  observe() {}
  disconnect() {}
}
let textChanged
globalThis.MutationObserver = class {
  constructor(callback) { this.callback = callback }
  observe() { textChanged = this.callback }
  disconnect() { textChanged = null }
}
globalThis.document = { documentElement: {} }
let rootFontSize = 16
globalThis.getComputedStyle = () => ({ fontSize: rootFontSize + "px" })

const box = Vue.shallowRef(null)
const content = Vue.shallowRef(null)
let fit
const fitApp = renderer.createApp({
  setup() {
    fit = fitModule.namespace.useFit(box, content)
    return () => null
  },
})
fitApp.mount(node("root"))
box.value = { $el: { clientWidth: 640, clientHeight: 352 } }
content.value = { offsetWidth: 240, scrollWidth: 240, offsetHeight: 100, scrollHeight: 100 }
await Vue.nextTick()

function currentScale() {
  const transform = fit.value?.transform
  return transform ? Number(transform.match(/^scale\((.+)\)$/)[1]) : 1
}

function scaleAt(width, height) {
  Object.assign(box.value.$el, { clientWidth: width, clientHeight: height })
  resize()
  return currentScale()
}

assert.equal(scaleAt(640, 352), 1, "short announcement at default width")
assert.equal(scaleAt(800, 440), 1.25, "enlarging the app enlarges the announcement")
assert.equal(scaleAt(1920, 1080), 1.5, "growth stays bounded")
assert.equal(scaleAt(960, 75), 0.75, "a short app still fits tall content")
content.value.offsetWidth = 800
content.value.scrollWidth = 900
assert.equal(scaleAt(800, 440), 0.8, "centered content fits its 100px overflow on both sides")
content.value.scrollWidth = 1200
textChanged()
assert.equal(currentScale(), 0.5, "live text can grow without resizing its layout box")
content.value.offsetWidth = content.value.scrollWidth = 240
rootFontSize = 20
assert.equal(scaleAt(800, 440), 1, "the game UI scale determines the default width")
content.value = null
await Vue.nextTick()
assert.equal(fit.value?.transform, undefined, "hidden content releases its scale")
fitApp.unmount()
console.log("Fitted UI scales with app width and stays within both dimensions")
