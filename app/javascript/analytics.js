import * as ahoyModule from "ahoy"

// Ahoy.js is a UMD script: loaded by the import map it sets globalThis.ahoy,
// and bundled (as rails-jsdom does in specs) it exports itself instead.
const ahoy = globalThis.ahoy || ahoyModule.default
globalThis.ahoy = ahoy
ahoy.configure({ trackVisits: false })

const UMAMI_CUSTOM_EVENTS = new Set([
  "browse_refined",
  "rating_changed",
  "baseline_changed",
  "share_action",
  "frame_opened",
  "ui_interaction"
])

export function cleanPath(value) {
  const url = new URL(value, window.location.origin)
  return url.pathname.replace(/^\/(invite|influencers)\/[^/]+/, "/$1/:token")
}

function pageContext() {
  return JSON.parse(document.querySelector('meta[name="ascent-analytics"]').content)
}

function compactObject(entries) {
  const result = {}
  for (const [key, value] of entries) {
    if (value !== undefined && value !== null && value !== "") result[key] = value
  }
  return result
}

export function forwardToUmami(name, properties = {}) {
  const tracker = window.umami?.track
  if (typeof tracker !== "function") return false

  const shouldForward = UMAMI_CUSTOM_EVENTS.has(name) ||
    (name === "navigation_used" && (properties.external === true || properties.umami === true))
  if (!shouldForward) return false

  const payload = compactObject(
    Object.entries(properties)
      .filter(([key]) => !["record_id", "enabled", "umami"].includes(key))
      .map(([key, value]) => [key, Array.isArray(value) ? value.join(",") : value])
  )

  try {
    tracker(name, payload)
    return true
  } catch (_) {
    return false
  }
}

export function track(name, properties = {}, options = {}) {
  const { enabled, ...context } = pageContext()
  if (!enabled) return

  const payload = { ...context, ...properties }
  ahoy.track(name, payload)
  forwardToUmami(name, { ...payload, ...(options.umami ? { umami: true } : {}) })
  if (["rating_changed", "baseline_changed", "navigation_used", "share_action", "frame_opened", "ui_interaction"].includes(name) || name === "browse_refined" && properties.method === "map_selection") {
    pageAnalytics.engage("interaction")
  }
}

function placementFor(element) {
  const tagged = element.closest?.("[data-analytics-placement]")
  if (tagged?.dataset?.analyticsPlacement) return tagged.dataset.analyticsPlacement

  const area = element.closest?.("nav, header, footer, section, main")
  return area?.getAttribute?.("aria-label") || area?.id || area?.className || area?.tagName?.toLowerCase()
}

function labelFor(element) {
  return (element.getAttribute?.("aria-label") || element.textContent || "").trim().replace(/\s+/g, " ").slice(0, 160)
}

class PageAnalytics {
  start(url = window.location.href, frame = null) {
    this.pause()
    this.engaged = false
    this.remaining = 20000
    const { enabled, ...context } = pageContext()
    this.context = { ...context, path: cleanPath(url), frame_id: frame?.id }
    try {
      this.context.previous_path = sessionStorage.getItem("ascent_previous_path")
      sessionStorage.setItem("ascent_previous_path", this.context.path)
    } catch (_) {
      this.context.previous_path = this.previousPath
    }
    this.previousPath = this.context.path
    track("page_viewed", this.context)
    this.trackBrowse(url, frame || document)
    this.resume()
  }

  resume() {
    if (this.engaged || this.startedAt !== undefined || document.visibilityState !== "visible" || !document.hasFocus()) return

    this.startedAt = performance.now()
    this.timer = setTimeout(() => this.engage("active_time"), this.remaining)
  }

  pause() {
    clearTimeout(this.timer)
    if (this.startedAt !== undefined) this.remaining -= performance.now() - this.startedAt
    this.startedAt = undefined
  }

  engage(qualification) {
    if (!this.context || this.engaged) return

    this.engaged = true
    this.pause()
    track("page_engaged", { ...this.context, qualification })
  }

  trackBrowse(url, root) {
    const query = new URL(url, window.location.origin).searchParams
    const names = [...new Set([...query.keys()]
      .filter(name => /^(q|.*_id|year|status|kind|near|layers?)$/.test(name.replace(/\[\]$/, "")) && query.get(name))
      .map(name => name.replace(/\[\]$/, "")))]
    if (!names.length || (!root.querySelector(".filter-form") && !document.querySelector(".filter-form"))) return

    const count = root.querySelector("[data-analytics-result-count]") || (root.dataset?.analyticsResultCount !== undefined ? root : null)
    track("browse_refined", {
      ...this.context, method: "filters", filter_names: names,
      query_length: (query.get("q") || "").length,
      result_count: count ? Number(count.dataset.analyticsResultCount) : null
    })
  }
}

export const pageAnalytics = new PageAnalytics()
let navigatedFrame

document.addEventListener("turbo:load", () => {
  const frame = navigatedFrame?.src === window.location.href ? navigatedFrame : null
  navigatedFrame = null
  pageAnalytics.start(window.location.href, frame)
})
document.addEventListener("turbo:before-cache", () => pageAnalytics.pause())
document.addEventListener("turbo:before-visit", () => pageAnalytics.pause())
document.addEventListener("turbo:frame-load", event => {
  const target = event.target
  if (!target?.matches) return

  if (target.matches("[data-analytics-frame]")) {
    track("frame_opened", compactObject(Object.entries({
      frame_id: target.id,
      frame_name: target.dataset?.analyticsFrame || target.id,
      source_path: target.src ? cleanPath(target.src) : undefined
    })))
  }
  if (target.matches(".index-results")) navigatedFrame = target
})
document.addEventListener("visibilitychange", () => document.visibilityState === "visible" ? pageAnalytics.resume() : pageAnalytics.pause())
window.addEventListener("focus", () => pageAnalytics.resume())
window.addEventListener("blur", () => pageAnalytics.pause())
window.addEventListener("pagehide", () => pageAnalytics.pause())

document.addEventListener("submit", event => {
  if (event.target.matches(".filter-form")) pageAnalytics.engage("interaction")
}, { capture: true })

document.addEventListener("click", event => {
  if (event.defaultPrevented || !event.target?.closest) return

  const link = event.target.closest("a[href]")
  if (link) {
    if (link.closest("[data-analytics-ignore]")) return

    const url = new URL(link.href, window.location.origin)
    if (!["http:", "https:"].includes(url.protocol)) return

    track("navigation_used", {
      label: labelFor(link),
      placement: placementFor(link),
      destination: cleanPath(url.href),
      external: url.origin !== window.location.origin,
      destination_host: url.hostname
    }, { umami: link.hasAttribute?.("data-analytics-umami") })
    return
  }

  const control = event.target.closest("[data-analytics-event]")
  if (!control || control.matches?.("form") || control.closest?.("[data-analytics-ignore]")) return

  track(control.dataset?.analyticsEvent || "ui_interaction", compactObject(Object.entries({
    action: control.dataset?.analyticsAction,
    label: labelFor(control),
    placement: placementFor(control)
  })))
}, { capture: true })
