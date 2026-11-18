import { readFileSync } from "node:fs"
import { basename } from "node:path"
import { SourceTextModule, SyntheticModule } from "node:vm"
import { compileScript, parse } from "@vue/compiler-sfc"
import * as Vue from "vue"

const controls = {
  BngButton: "button", BngSwitch: "switch", BngColorPicker: "picker",
  BngCardHeading: "h2", BngIcon: "icon", icons: {}, ACCENTS: {},
}
const defaults = {
  vue: Vue,
  "@/common/components/base": controls,
  "@/common/directives": { vBngTextInput: {}, vBngTooltip: {} },
  "../../copsAndRobbers/CnrRoot.vue": { default: "cnr-root" },
}

async function loadUi(url, mocks = {}) {
  let content = readFileSync(url, "utf8")
  if (url.pathname.endsWith(".vue")) {
    const name = basename(url.pathname)
    const { descriptor } = parse(content, { filename: name })
    content = compileScript(descriptor, { id: name, inlineTemplate: true }).content
  }
  const module = new SourceTextModule(content)
  await module.link(async path => {
    const bindings = mocks[path] || defaults[path]
    if (!bindings && path.startsWith(".")) {
      return loadUi(new URL(path, url), mocks)
    }
    if (!bindings) throw new Error(`Missing test binding for ${path}`)
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

const apps = new URL("../../client/ui/modules/apps/", import.meta.url)

export { apps, buttonFor, controls, descendants, loadUi, node, renderer }
