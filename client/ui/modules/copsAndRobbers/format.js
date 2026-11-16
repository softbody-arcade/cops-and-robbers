export function formatTime(seconds) {
  const total = Math.max(0, Math.floor(Number(seconds) || 0))
  const s = total % 60
  return `${Math.floor(total / 60)}:${s < 10 ? "0" : ""}${s}`
}

export function formatDistance(meters) {
  const m = Math.max(0, Number(meters) || 0)
  const rounded = Math.round(m)
  if (rounded >= 1000) return `${(m / 1000).toFixed(1)} km`
  return `${rounded} m`
}

export function hexToHsl(hex) {
  const h = String(hex || "").replace("#", "")
  const full = h.length === 3 ? h.replace(/./g, c => c + c) : h
  const n = parseInt(full, 16)
  if (full.length !== 6 || Number.isNaN(n)) return { hue: 0, saturation: 0, luminosity: 0 }
  const r = ((n >> 16) & 255) / 255
  const g = ((n >> 8) & 255) / 255
  const b = (n & 255) / 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const l = (max + min) / 2
  const d = max - min
  if (d === 0) return { hue: 0, saturation: 0, luminosity: l }
  const s = d / (1 - Math.abs(2 * l - 1))
  let hue
  if (max === r) hue = ((g - b) / d) % 6
  else if (max === g) hue = (b - r) / d + 2
  else hue = (r - g) / d + 4
  hue = (hue / 6 + 1) % 1
  return { hue, saturation: s, luminosity: l }
}

export function hslToHex({ hue, saturation, luminosity }) {
  const a = saturation * Math.min(luminosity, 1 - luminosity)
  const channel = n => {
    const k = (n + hue * 12) % 12
    const v = luminosity - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
    return Math.round(v * 255).toString(16).padStart(2, "0")
  }
  return `#${channel(0)}${channel(8)}${channel(4)}`
}

export function mapName({ id, title, pretty }, translate) {
  if (title && translate) {
    const t = translate(title)
    if (t && t !== title && !String(t).startsWith("levels.")) return t
  }
  return pretty || id
}
