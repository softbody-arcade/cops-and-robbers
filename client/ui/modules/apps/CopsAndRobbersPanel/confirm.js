import { ref, onUnmounted } from "vue"

const CONFIRM_MS = 3000

export function useConfirm() {
  const armed = ref(null)
  let timer = null

  function disarm() {
    clearTimeout(timer)
    timer = null
    armed.value = null
  }

  function confirm(kind, needed, run) {
    if (needed && armed.value !== kind) {
      clearTimeout(timer)
      armed.value = kind
      timer = setTimeout(() => (armed.value = null), CONFIRM_MS)
      return
    }
    disarm()
    run()
  }

  onUnmounted(disarm)
  return { armed, confirm }
}
