import { ref, computed, watch, onBeforeUnmount } from "vue"

const DEFAULT_WIDTH_REM = 40
const MAX_GROWTH = 1.5

const element = r => (r.value && r.value.$el) || r.value

export function useFit(box, content) {
  const growth = ref(1)
  const scale = ref(1)
  const textObserver = typeof MutationObserver === "function" ? new MutationObserver(measure) : null
  const resizeObserver = typeof ResizeObserver === "function" ? new ResizeObserver(measure) : null

  function measure() {
    const frame = element(box)
    const body = element(content)
    if (!frame || !body || !frame.clientWidth || !frame.clientHeight) {
      growth.value = 1
      scale.value = 1
      return
    }
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize)
    growth.value = Math.max(1, Math.min(MAX_GROWTH, frame.clientWidth / (DEFAULT_WIDTH_REM * rem)))
    const height = Math.max(body.offsetHeight, body.scrollHeight)
    const overflowRight = Math.max(0, body.scrollWidth - body.offsetWidth)
    const width = body.offsetWidth + 2 * overflowRight
    scale.value = width && height
      ? Math.min(growth.value, frame.clientWidth / width, frame.clientHeight / height)
      : 1
  }

  watch(
    [box, content],
    () => {
      const frame = element(box)
      const body = element(content)
      resizeObserver?.disconnect()
      textObserver?.disconnect()
      if (frame && body) {
        resizeObserver?.observe(frame)
        resizeObserver?.observe(body)
        textObserver?.observe(body, { subtree: true, childList: true, characterData: true })
      }
      measure()
    },
    { flush: "post" }
  )

  onBeforeUnmount(() => {
    resizeObserver?.disconnect()
    textObserver?.disconnect()
  })

  return computed(() => ({
    "--cnr-fit-growth": growth.value,
    transform: scale.value === 1 ? undefined : `scale(${scale.value})`,
  }))
}
