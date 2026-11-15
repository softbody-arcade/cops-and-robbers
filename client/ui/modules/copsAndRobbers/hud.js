import { ref, onMounted, onErrorCaptured } from "vue"
import { useEvents } from "@/services/events"
import { useBridge } from "@/bridge"

export function useCnrHud(app) {
  const { api } = useBridge()
  const events = useEvents()
  const hud = ref({ visible: false })
  let lastReport = ""

  function ui(msg) {
    api.engineLua(`if copsAndRobbers then copsAndRobbers.ui(${api.serializeToLua(msg)}) end`)
  }

  function report(where, err) {
    try {
      const message = err && err.message ? err.message : String(err)
      const lines = err && typeof err.stack === "string" ? err.stack.split("\n").map(l => l.trim()) : []
      const at = lines.find(l => l.startsWith("at ")) || lines[0] || ""
      const text = `[cnr_ui] ${app} ${where}: ${message} | ${at}`
      if (text === lastReport) return
      lastReport = text
      api.engineLua(`log("E","cnr_ui",${api.serializeToLua(text)})`)
    } catch (e) {}
  }

  onErrorCaptured((err, instance, info) => {
    const options = (instance && instance.$options) || {}
    report(`${options.name || options.__name || "?"} ${info}`, err)
    return false
  })

  events.on("CnRHud", data => {
    try {
      hud.value = data && typeof data === "object" ? data : { visible: false }
    } catch (err) {
      report("CnRHud handler", err)
    }
  })

  onMounted(() => ui({ action: "hello" }))

  return { hud, ui }
}
