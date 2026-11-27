import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

async function harness({ withUmami = true } = {}) {
  const events = []
  const umamiEvents = []
  const listeners = new Map()
  const timers = new Map()
  const storage = new Map()
  let now = 0
  let nextTimer = 0
  const metadata = { page_type: "races.index", path: "/races", signed_in: false, enabled: true }
  const root = {
    visibilityState: "visible", focused: true, count: null,
    hasFocus() { return this.focused },
    querySelector(selector) {
      if (selector.includes("ascent-analytics")) return { content: JSON.stringify(metadata) }
      if (selector === ".filter-form") return this.count === null ? null : {}
      if (selector === "[data-analytics-result-count]") return this.count === null ? null : { dataset: { analyticsResultCount: String(this.count) } }
      return null
    },
    addEventListener(name, callback) { listeners.set(name, callback) }
  }
  const context = vm.createContext({
    URL, document: root,
    window: {
      location: { origin: "https://ascent.test", href: "https://ascent.test/races" },
      addEventListener() {},
      umami: withUmami ? { track: (name, payload) => umamiEvents.push({ name, payload }) } : undefined
    },
    sessionStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) },
    performance: { now: () => now },
    setTimeout: (callback, delay) => { timers.set(++nextTimer, { callback, at: now + delay }); return nextTimer },
    clearTimeout: id => timers.delete(id),
    ahoy: { configure() {}, track: (name, properties) => events.push({ name, properties }) }
  })
  const source = await readFile(new URL("../../app/javascript/analytics.js", import.meta.url), "utf8")
  const module = new vm.SourceTextModule(source, { context })
  await module.link(() => new vm.SyntheticModule([], () => {}, { context }))
  await module.evaluate()

  function advance(milliseconds) {
    const target = now + milliseconds
    while (true) {
      const next = [...timers].sort((one, other) => one[1].at - other[1].at)[0]
      if (!next || next[1].at > target) break
      now = next[1].at
      timers.delete(next[0])
      next[1].callback()
    }
    now = target
  }

  return { events, umamiEvents, root, metadata, listeners, advance, window: context.window, analytics: module.namespace }
}

test("engagement counts 20 foreground seconds and pauses while hidden", async () => {
  const app = await harness()
  app.analytics.pageAnalytics.start()
  app.advance(9000)
  app.root.visibilityState = "hidden"
  app.listeners.get("visibilitychange")()
  app.advance(60000)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 0)
  app.root.visibilityState = "visible"
  app.listeners.get("visibilitychange")()
  app.advance(10999)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 0)
  app.advance(1)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 1)
  assert.equal(app.events.at(-1).properties.qualification, "active_time")
  assert.equal(app.umamiEvents.some(event => event.name === "page_engaged"), false)
})

test("interactions qualify once per view and cancel the remaining timer", async () => {
  const app = await harness()
  app.analytics.pageAnalytics.start()
  app.analytics.track("rating_changed", { race_id: 12 })
  app.analytics.track("baseline_changed", { race_id: 12 })
  app.advance(30000)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 1)
  assert.equal(app.events.find(event => event.name === "page_engaged").properties.qualification, "interaction")
  assert.equal(app.umamiEvents.some(event => event.name === "rating_changed"), true)
  app.analytics.pageAnalytics.start("/approval-voting")
  app.advance(20000)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 2)
})

test("page changes preserve browse paths and filtered empty-result counts without search text", async () => {
  const app = await harness()
  app.analytics.pageAnalytics.start()
  app.root.count = 0
  app.analytics.pageAnalytics.start("/races?q=unmatched&state_id=5")
  const view = app.events.filter(event => event.name === "page_viewed").at(-1)
  const browse = app.events.find(event => event.name === "browse_refined")
  assert.equal(view.properties.previous_path, "/races")
  assert.equal(view.properties.path, "/races")
  assert.equal(browse.properties.result_count, 0)
  assert.equal(browse.properties.query_length, 9)
  assert.equal(browse.properties.filter_names.join(","), "q,state_id")
  assert.equal(JSON.stringify(browse).includes("unmatched"), false)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 0)

  const umamiBrowse = app.umamiEvents.find(event => event.name === "browse_refined")
  assert.equal(umamiBrowse.payload.filter_names, "q,state_id")
  assert.equal(JSON.stringify(umamiBrowse).includes("unmatched"), false)
  assert.equal(app.umamiEvents.some(event => event.name === "page_viewed"), false)
})

test("frame navigation records its destination and count exactly once", async () => {
  const app = await harness()
  app.root.count = 2
  const frame = { id: "races-list", src: "https://ascent.test/races?status=active&page=2", dataset: { analyticsResultCount: "2" }, querySelector() { return null }, matches: selector => selector === ".index-results" }
  app.window.location.href = frame.src
  app.listeners.get("turbo:frame-load")({ target: frame })
  assert.equal(app.events.length, 0)
  app.listeners.get("turbo:load")()
  assert.equal(app.events.filter(event => event.name === "page_viewed").length, 1)
  assert.equal(app.events.find(event => event.name === "page_viewed").properties.frame_id, "races-list")
  assert.equal(app.events.find(event => event.name === "browse_refined").properties.result_count, 2)
})

test("lazy candidate-card frames do not count as page visits, while annotated frames fire frame_opened", async () => {
  const app = await harness()
  app.listeners.get("turbo:frame-load")({ target: { matches: () => false } })
  assert.equal(app.events.length, 0)

  app.analytics.pageAnalytics.start()
  app.listeners.get("turbo:frame-load")({
    target: {
      id: "modal-frame",
      src: "https://ascent.test/invite/secret?ref=1",
      dataset: { analyticsFrame: "invite_modal" },
      matches: selector => selector === "[data-analytics-frame]"
    }
  })
  const opened = app.events.find(event => event.name === "frame_opened")
  assert.equal(opened.properties.frame_name, "invite_modal")
  assert.equal(opened.properties.source_path, "/invite/:token")
  assert.equal(app.umamiEvents.some(event => event.name === "frame_opened"), true)
})

test("navigation_used forwards only external links to Umami and ui_interaction captures declarative buttons", async () => {
  const app = await harness()
  app.analytics.pageAnalytics.start()

  const internal = {
    href: "https://ascent.test/races",
    textContent: "All races",
    getAttribute() { return null },
    hasAttribute() { return false },
    closest(selector) { return selector === "a[href]" ? internal : null }
  }
  app.listeners.get("click")({ defaultPrevented: false, target: internal })

  const external = {
    href: "https://ballotpedia.org/Example",
    textContent: "Ballotpedia",
    getAttribute() { return null },
    hasAttribute() { return false },
    closest(selector) { return selector === "a[href]" ? external : null }
  }
  app.listeners.get("click")({ defaultPrevented: false, target: external })

  const button = {
    textContent: "Compare",
    dataset: { analyticsEvent: "ui_interaction", analyticsAction: "compare_toggle" },
    getAttribute() { return null },
    matches() { return false },
    closest(selector) { return selector === "[data-analytics-event]" ? button : null }
  }
  app.listeners.get("click")({ defaultPrevented: false, target: button })

  const umamiNav = app.umamiEvents.filter(event => event.name === "navigation_used")
  assert.equal(umamiNav.length, 1)
  assert.equal(umamiNav[0].payload.destination_host, "ballotpedia.org")
  assert.equal(app.umamiEvents.some(event => event.name === "ui_interaction"), true)
})

test("multiple map layers are one named browse filter", async () => {
  const app = await harness()
  app.root.count = 3
  app.analytics.pageAnalytics.start("/map?state_id=5&layers[]=counties&layers[]=congressional")
  const browse = app.events.find(event => event.name === "browse_refined")
  assert.equal(browse.properties.filter_names.join(","), "state_id,layers")
  assert.equal(browse.properties.result_count, 3)
})

test("opt-outs suppress browser events, missing window.umami is safe, and paths omit tokens and query strings", async () => {
  const noUmami = await harness({ withUmami: false })
  noUmami.analytics.pageAnalytics.start()
  noUmami.analytics.track("share_action", { channel: "copy" })
  assert.equal(noUmami.events.some(event => event.name === "share_action"), true)

  const app = await harness()
  app.metadata.enabled = false
  app.analytics.pageAnalytics.start()
  app.analytics.track("navigation_used", { destination: "/races", external: true })
  app.advance(30000)
  assert.equal(app.events.length, 0)
  assert.equal(app.umamiEvents.length, 0)
  assert.equal(app.analytics.cleanPath("/invite/private-token?ref=abc"), "/invite/:token")
  assert.equal(app.analytics.cleanPath("/influencers/private-token?q=example"), "/influencers/:token")
})
