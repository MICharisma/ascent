import * as ahoyModule from "ahoy"

// Ahoy.js is a UMD script: loaded by the import map it sets globalThis.ahoy,
// and bundled (as rails-jsdom does in specs) it exports itself instead.
const ahoy = globalThis.ahoy || ahoyModule.default
globalThis.ahoy = ahoy
ahoy.configure({ trackVisits: false })

export function cleanPath(value) {
  const url = new URL(value, window.location.origin)
  return url.pathname.replace(/^\/(invite|influencers)\/[^/]+/, "/$1/:token")
}

function pageContext() {
  return JSON.parse(document.querySelector('meta[name="ascent-analytics"]').content)
}

export function track(name, properties = {}) {
  const { enabled, ...context } = pageContext()
  if (!enabled) return

  ahoy.track(name, { ...context, ...properties })
  if (["rating_changed", "baseline_changed", "navigation_used", "share_action"].includes(name) || name === "browse_refined" && properties.method === "map_selection") {
    pageAnalytics.engage("interaction")
  }
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
  if (event.target.matches(".index-results")) navigatedFrame = event.target
})
document.addEventListener("visibilitychange", () => document.visibilityState === "visible" ? pageAnalytics.resume() : pageAnalytics.pause())
window.addEventListener("focus", () => pageAnalytics.resume())
window.addEventListener("blur", () => pageAnalytics.pause())
window.addEventListener("pagehide", () => pageAnalytics.pause())

document.addEventListener("submit", event => {
  if (event.target.matches(".filter-form")) pageAnalytics.engage("interaction")
}, { capture: true })

document.addEventListener("click", event => {
  const link = event.target.closest("a[href]")
  if (!link || event.defaultPrevented || link.closest("[data-analytics-ignore]")) return

  const url = new URL(link.href, window.location.origin)
  if (!["http:", "https:"].includes(url.protocol)) return

  const area = link.closest("nav, header, footer, section, main")
  track("navigation_used", {
    label: (link.getAttribute("aria-label") || link.textContent).trim().replace(/\s+/g, " ").slice(0, 160),
    placement: area?.getAttribute("aria-label") || area?.id || area?.className || area?.tagName.toLowerCase(),
    destination: cleanPath(url.href), external: url.origin !== window.location.origin,
    destination_host: url.hostname
  })
}, { capture: true })
