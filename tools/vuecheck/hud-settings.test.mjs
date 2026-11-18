import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { basename } from "node:path"
import { SourceTextModule, SyntheticModule } from "node:vm"
import { compileScript, parse } from "@vue/compiler-sfc"
import * as Vue from "vue"

const hud = Vue.ref({})
const actions = []
const controls = {
  BngButton: "button", BngSwitch: "switch", BngColorPicker: "picker",
  BngCardHeading: "h2", BngIcon: "icon", icons: {}, ACCENTS: {},
}
const mocks = {
  vue: Vue,
  "@/common/components/base": controls,
  "@/common/directives": { vBngTextInput: {} },
  "../../copsAndRobbers/format.js": { hexToHsl() {}, hslToHex() {} },
  "../../copsAndRobbers/hud.js": { useCnrHud: () => ({ hud, ui: action => actions.push(action) }) },
  "../../copsAndRobbers/fit.js": { useFit: () => ({}) },
}

async function component(name) {
  const url = new URL(`../../client/ui/modules/apps/CopsAndRobbersHud/${name}`, import.meta.url)
  const { descriptor } = parse(readFileSync(url, "utf8"), { filename: name })
  const { content } = compileScript(descriptor, { id: name, inlineTemplate: true })
  const module = new SourceTextModule(content)
  await module.link(async path => {
    if (path.startsWith("./Hud") || path.endsWith("/CnrCard.vue")) return component(path)
    const bindings = mocks[path] || { default: basename(path, ".vue") }
    return new SyntheticModule(Object.keys(bindings), function () {
      for (const [key, value] of Object.entries(bindings)) this.setExport(key, value)
    })
  })
  return module
}

const node = (type, text = "") => ({ type, text, props: {}, style: {}, children: [] })
const renderer = Vue.createRenderer({
  createElement: type => node(type), createText: text => node("text", text), createComment: () => node("comment"),
  setElementText: (el, text) => { el.text = text }, setText: (el, text) => { el.text = text },
  patchProp: (el, prop, prev, value) => { el.props[prop] = value },
  insert(el, parent, anchor) {
    el.parent = parent
    const at = parent.children.indexOf(anchor)
    parent.children.splice(at < 0 ? parent.children.length : at, 0, el)
  },
  remove: el => el.parent.children.splice(el.parent.children.indexOf(el), 1),
  parentNode: el => el.parent,
  nextSibling: el => el.parent.children[el.parent.children.indexOf(el) + 1],
})

function descendants(el) {
  if (el.style.display === "none") return []
  return [el, ...el.children.flatMap(descendants)]
}

function buttonFor(root, label) {
  return descendants(root).find(el => el.type === "button" && descendants(el).some(n => n.text === label))
}

const module = await component("app.vue")
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
