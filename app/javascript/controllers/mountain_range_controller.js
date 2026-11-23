import { Controller } from "@hotwired/stimulus"

// GSAP runs a ticker as soon as it loads, so load it only where a mountain range connects.
let loadingGsap
const withGsap = (use) => (loadingGsap ||= import("gsap").then((module) => module.gsap)).then(use)

// Draws each candidate's rating as a peak and moves the range with GSAP: peaks spring up on arrival,
// follow a drag, and a summit pulses lime as it breaks through the baseline. It owns every position
// on the chart (peaks, dots and the baseline line) so they always agree. The mountain editor tells it
// what changed through mountain-editor:rated and mountain-editor:baseline-moved.
// Connects to data-controller="mountain-range"
export default class extends Controller {
  static targets = ["column", "baseline"]
  static values = {
    baseline: { type: Number, default: 200 },
    baselineSet: Boolean,
    logLevel: { type: String, default: "warn" }
  }

  connect() {
    this.line = { value: this.baselineValue }
    this.peaks = new Map(this.columnTargets.map((column) => [ column, this.startingPeak(column) ]))
    this.resizeObserver = new ResizeObserver(() => {
      this.sizeSegments()
      this.placeBaseline()
    })
    this.resizeObserver.observe(this.element)
    this.sizeSegments()
    this.drawAll()
    this.markReady()
    this.riseIntoView()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    const targets = [ this.line, ...this.peaks.values() ]
    withGsap((gsap) => gsap.killTweensOf(targets))
  }

  rate({ detail: { candidacyId, rating, glide } }) {
    const index = this.columnTargets.findIndex((target) => target.dataset.candidacyId === String(candidacyId))
    const column = this.columnTargets[index]
    if (!column) return

    column.dataset.rating = rating
    this.tween(this.peaks.get(column), { height: rating }, glide, () => {
      this.drawColumn(column)
      if (index > 0) this.drawColumn(this.columnTargets[index - 1])
    })
  }

  moveBaseline({ detail: { baseline, glide } }) {
    this.baselineSetValue = true
    this.tween(this.line, { value: baseline }, glide, () => this.drawAll())
  }

  // A drag follows the pointer closely; a nudge glides and settles.
  tween(target, vars, glide, onUpdate) {
    withGsap((gsap) => gsap.to(target, {
      ...vars,
      duration: this.motionAllowed() ? (glide ? 0.45 : 0.12) : 0,
      ease: glide ? "back.out(2)" : "power2.out",
      overwrite: true,
      onUpdate
    }))
  }

  riseIntoView() {
    if (!this.motionAllowed()) return

    const peaks = Array.from(this.peaks.values())
    withGsap((gsap) => gsap.from(peaks, {
      height: 0,
      duration: 1.1,
      ease: "elastic.out(1, 0.6)",
      stagger: 0.07,
      onUpdate: () => this.drawAll()
    }))
  }

  startingPeak(column) {
    return { height: this.ratingOf(column), wasAboveLine: false }
  }

  ratingOf(column) {
    return column.dataset.rating === undefined || column.dataset.rating === "" ? 0 : Number(column.dataset.rating)
  }

  drawAll() {
    this.columnTargets.forEach((column) => this.drawColumn(column))
    this.placeBaseline()
  }

  drawColumn(column) {
    const peak = this.peaks.get(column)
    if (!peak) return

    const height = Math.max(0, Math.min(500, peak.height))
    const baseline = this.line.value
    const aboveLine = this.baselineSetValue && height > baseline
    const next = this.columnTargets[this.columnTargets.indexOf(column) + 1]
    const nextHeight = next ? Math.max(0, Math.min(500, this.peaks.get(next).height)) : 0
    this.drawSegment(column.querySelector(".mountain-peak"), height, nextHeight, baseline)
    const leftEdge = column.querySelector(".mountain-left-edge")
    if (leftEdge) this.drawSegment(leftEdge, 0, height, baseline)
    this.placeDot(column, height)
    if (aboveLine && !peak.wasAboveLine) this.pulseSummit(column)
    peak.wasAboveLine = aboveLine
  }

  drawSegment(svg, height, nextHeight, baseline) {
    this.setShape(svg, "peak-body", this.peakPath(height, nextHeight))
    this.setShape(svg, "peak-ridge", `M 0 ${500 - height} L 100 ${500 - nextHeight}`)
    this.setShape(svg, "peak-summit", this.baselineSetValue ? this.summitPath(height, nextHeight, baseline) : "")
    this.setShape(svg, "peak-rope", this.baselineSetValue ? this.ropePath(height, nextHeight, baseline) : "")
  }

  sizeSegments() {
    this.columnTargets.forEach((column, index) => {
      const next = this.columnTargets[index + 1]
      const svg = column.querySelector(".mountain-peak")
      const currentArea = column.querySelector(".rating-area").getBoundingClientRect()
      const nextArea = next?.querySelector(".rating-area").getBoundingClientRect()
      const width = nextArea ? nextArea.left + nextArea.width / 2 - currentArea.left - currentArea.width / 2 : currentArea.width / 2
      svg.style.width = `${width}px`
    })
  }

  peakPath(height, nextHeight) {
    return `M 0 ${500 - height} L 100 ${500 - nextHeight} L 100 500 L 0 500 Z`
  }

  summitPath(height, nextHeight, baseline) {
    if (height <= baseline && nextHeight <= baseline) return ""

    const [left, right] = this.summitBounds(height, nextHeight, baseline)
    return `M ${left} ${500 - Math.max(height, baseline)} L ${right} ${500 - Math.max(nextHeight, baseline)} L ${right} ${500 - baseline} L ${left} ${500 - baseline} Z`
  }

  ropePath(height, nextHeight, baseline) {
    if (height <= baseline && nextHeight <= baseline) return ""

    const [left, right] = this.summitBounds(height, nextHeight, baseline)
    return `M ${left} ${500 - baseline} H ${right}`
  }

  summitBounds(height, nextHeight, baseline) {
    if (height >= baseline && nextHeight >= baseline) return [0, 100]

    const crossing = 100 * (height - baseline) / (height - nextHeight)
    return height > baseline ? [0, crossing] : [crossing, 100]
  }

  setShape(column, role, path) {
    column.querySelector(`[data-role='${role}']`)?.setAttribute("d", path)
  }

  placeDot(column, height) {
    const dot = column.querySelector("[data-role='rating-dot']")
    if (dot) dot.style.top = `${100 - height / 5}%`
  }

  pulseSummit(column) {
    if (!this.motionAllowed()) return

    const dot = column.querySelector("[data-role='rating-dot']")
    withGsap((gsap) => gsap.fromTo(dot, { scale: 1.8 }, { scale: 1, duration: 0.6, ease: "elastic.out(1, 0.4)", overwrite: true }))
    this.log(`Summit cleared the baseline in ${column.dataset.candidacyId}`)
  }

  // The line sits in the chart, outside the columns, so it is measured against a rating area.
  placeBaseline() {
    if (!this.hasBaselineTarget) return

    const area = this.columnTargets[0]?.querySelector(".rating-area")
    const parent = this.baselineTarget.offsetParent
    if (!area || !parent) return

    const areaBox = area.getBoundingClientRect()
    const y = areaBox.top - parent.getBoundingClientRect().top + (1 - this.line.value / 500) * areaBox.height
    this.baselineTarget.style.top = `${y - this.baselineTarget.offsetHeight / 2}px`
  }

  markReady() {
    this.element.dataset.rangeReady = "true"
  }

  motionAllowed() {
    return !window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  log(message) {
    if (this.logLevelValue === "debug") console.debug(`[Mountain range] ${message}`)
  }
}
