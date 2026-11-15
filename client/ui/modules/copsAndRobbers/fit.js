import { ref, computed, watch, onBeforeUnmount } from "vue"

const element = r => (r.value && r.value.$el) || r.value

export function useFit(box, content) {
  const scale = ref(1)
  const observer = typeof ResizeObserver === "function" ? new ResizeObserver(measure) : null

  function measure() {
    const b = element(box)
    const c = element(content)
    if (!b || !c) {
      scale.value = 1
      return
    }
    const h = Math.max(c.offsetHeight, c.scrollHeight)
    const w = Math.max(c.offsetWidth, c.scrollWidth)
    const s = Math.min(1, h > 0 ? b.clientHeight / h : 1, w > 0 ? b.clientWidth / w : 1)
    scale.value = s > 0 ? Math.floor(s * 100) / 100 : 1
  }

  watch(
    [box, content],
    () => {
      if (!observer) return
      observer.disconnect()
      for (const el of [element(box), element(content)]) if (el) observer.observe(el)
      measure()
    },
    { flush: "post" }
  )

  onBeforeUnmount(() => observer && observer.disconnect())

  return computed(() => (scale.value < 1 ? { transform: `scale(${scale.value})` } : undefined))
}
