const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const DAY_MS = 86400000
const WARN_KINDS = new Set(["penalty", "illegalReset", "teleport", "partsChanged"])

export function list(value) {
  return Array.isArray(value) ? value.filter(v => v && typeof v === "object") : []
}

export function medal(rank) {
  return rank === 1 ? "gold" : rank === 2 ? "silver" : rank === 3 ? "bronze" : ""
}

export function orDash(value, format) {
  if (value === undefined || value === null || (typeof value === "number" && !Number.isFinite(value))) return "–"
  return format ? format(value) : String(value)
}

function dateOf(round) {
  const s = Number(round && round.endedAt)
  return Number.isFinite(s) && s > 0 ? new Date(s * 1000) : null
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

export function dayLabel(round, now = new Date()) {
  const d = dateOf(round)
  if (!d) return "Earlier"
  const days = Math.round((startOfDay(now) - startOfDay(d)) / DAY_MS)
  if (days === 0) return "Today"
  if (days === 1) return "Yesterday"
  const year = d.getFullYear() !== now.getFullYear() ? ` ${d.getFullYear()}` : ""
  return `${WEEKDAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}${year}`
}

export function clock(round) {
  const d = dateOf(round)
  if (!d) return ""
  const two = n => (n < 10 ? "0" : "") + n
  return `${two(d.getHours())}:${two(d.getMinutes())}`
}

function catchers(round) {
  return (Array.isArray(round.catchers) ? round.catchers : []).filter(n => typeof n === "string" && n)
}

export function endLine(round) {
  switch (round.endReason) {
    case "caught": {
      const c = catchers(round)
      return c.length ? `Caught by ${c.join(", ")}` : "Caught"
    }
    case "escaped": return "Escaped"
    case "called": return "Ended by the host"
    case "disconnect": return "Runner left"
  }
  return "Ended"
}

export function headline(round) {
  switch (round.endReason) {
    case "caught": {
      const c = catchers(round)
      return c.length ? `caught by ${c.join(", ")}` : "caught"
    }
    case "escaped": return "escaped"
    case "called": return "ended by the host"
    case "disconnect": return "left"
  }
  return "ended"
}

export function resultLead(round) {
  const name = round.player || "The runner"
  switch (round.endReason) {
    case "caught": return `${name} caught after`
    case "escaped": return `${name} escaped after`
    case "disconnect": return `${name} left after`
  }
  return `${name} survived`
}

export function buildStep(round) {
  const n = Number(round.buildStep)
  return round.buildStep !== undefined && round.buildStep !== null && Number.isFinite(n) ? n : null
}

function eventText(e) {
  const name = typeof e.name === "string" && e.name ? e.name : "Someone"
  switch (e.kind) {
    case "lost": return `${name} lost the cops`
    case "penalty": {
      const s = Number(e.seconds)
      const cause = e.cause === "traffic" ? " (traffic)" : ""
      return (Number.isFinite(s) ? `${name}: crash penalty ${Math.round(s)} s` : `${name}: crash penalty`) + cause
    }
    case "illegalReset": return `${name} reset illegally`
    case "teleport": return `${name} teleported`
    case "partsChanged": return `${name} changed parts`
  }
  return ""
}

export function events(round) {
  return list(round.timeline)
    .map(e => ({
      t: Math.max(0, Number(e.t) || 0),
      text: eventText(e),
      tone: e.kind === "lost" ? "good" : WARN_KINDS.has(e.kind) ? "warn" : "",
    }))
    .filter(e => e.text)
}

export function warnings(round) {
  return events(round).filter(e => e.tone === "warn")
}
