import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

async function harness() {
  const events = []
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
    window: { location: { origin: "https://ascent.test", href: "https://ascent.test/races" }, addEventListener() {} },
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

  return { events, root, metadata, listeners, advance, window: context.window, analytics: module.namespace }
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
})

test("interactions qualify once per view and cancel the remaining timer", async () => {
  const app = await harness()
  app.analytics.pageAnalytics.start()
  app.analytics.track("rating_changed", { race_id: 12 })
  app.analytics.track("baseline_changed", { race_id: 12 })
  app.advance(30000)
  assert.equal(app.events.filter(event => event.name === "page_engaged").length, 1)
  assert.equal(app.events.find(event => event.name === "page_engaged").properties.qualification, "interaction")
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

test("lazy candidate-card frames do not count as page visits", async () => {
  const app = await harness()
  app.listeners.get("turbo:frame-load")({ target: { matches: () => false } })
  assert.equal(app.events.length, 0)
})

test("multiple map layers are one named browse filter", async () => {
  const app = await harness()
  app.root.count = 3
  app.analytics.pageAnalytics.start("/map?state_id=5&layers[]=counties&layers[]=congressional")
  const browse = app.events.find(event => event.name === "browse_refined")
  assert.equal(browse.properties.filter_names.join(","), "state_id,layers")
  assert.equal(browse.properties.result_count, 3)
})

test("opt-outs suppress browser events and paths omit tokens and query strings", async () => {
  const app = await harness()
  app.metadata.enabled = false
  app.analytics.pageAnalytics.start()
  app.analytics.track("navigation_used", { destination: "/races" })
  app.advance(30000)
  assert.equal(app.events.length, 0)
  assert.equal(app.analytics.cleanPath("/invite/private-token?ref=abc"), "/invite/:token")
  assert.equal(app.analytics.cleanPath("/influencers/private-token?q=example"), "/influencers/:token")
})
