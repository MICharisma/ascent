import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { Dimension } from "shared-ratings/dimension"
import { HorizontalDrag } from "shared-ratings/horizontal-drag"

// A voter's quality ratings for one citizen or policy. Dragging a thumb across moves in coarse steps;
// dragging down while still holding switches to fine steps. Release saves once, and Escape or a lost
// pointer puts the row back. The server answers each save or clear with the redrawn row.
export default class extends Controller {
  static targets = ["row", "slider", "precisionButton", "picker"]
  static values = {
    url: String,
    precision: { type: String, default: "coarse" },
    logLevel: { type: String, default: "warn" }
  }

  initialize() {
    this.pointerMove = this.moveDrag.bind(this)
    this.pointerUp = this.finishDrag.bind(this)
    this.pointerCancel = this.cancelDrag.bind(this)
  }

  disconnect() {
    this.endDrag(false)
  }

  sliderTargetConnected(slider) {
    slider.ratingDimension = new Dimension(JSON.parse(this.rowFor(slider).dataset.dimension))
  }

  precisionValueChanged() {
    this.precisionButtonTargets.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.precision === this.precisionValue)))
  }

  changePrecision(event) {
    this.precisionValue = event.currentTarget.dataset.precision
  }

  openDimension(event) {
    const button = event.currentTarget
    const row = this.rowTargets.find(row => row.dataset.key === button.dataset.dimensionKey)
    row.hidden = false
    button.hidden = true
    if (this.pickerIsEmpty()) this.pickerTarget.hidden = true
    row.querySelector("input").focus()
    this.debug("Opened", row.dataset.key)
  }

  pickerIsEmpty() {
    return [...this.pickerTarget.querySelectorAll("button")].every(button => button.hidden)
  }

  startDrag(event) {
    if (this.drag) {
      event.preventDefault()
      return
    }
    if (!event.isPrimary || event.button !== 0) return
    const slider = this.rowFor(event.currentTarget).querySelector("input")
    if (slider.disabled) return
    const bounds = slider.getBoundingClientRect()
    const width = bounds.width - 24
    if (width <= 0 || !this.isNearThumb(event.clientX, slider, bounds, width)) return
    event.preventDefault()
    slider.focus({ preventScroll: true })
    const row = this.rowFor(slider)
    this.drag = {
      slider, pointerId: event.pointerId,
      original: { value: slider.value, label: this.valueLabel(row).textContent, status: this.statusIndicator(row).textContent, aria: slider.getAttribute("aria-valuetext") },
      gesture: new HorizontalDrag({ dimension: slider.ratingDimension, value: Number(slider.value), x: event.clientX, y: event.clientY, width, precision: this.precisionValue })
    }
    document.addEventListener("pointermove", this.pointerMove)
    document.addEventListener("pointerup", this.pointerUp)
    document.addEventListener("pointercancel", this.pointerCancel)
    slider.setPointerCapture(event.pointerId)
  }

  isNearThumb(x, slider, bounds, width) {
    const thumbX = bounds.left + 12 + slider.ratingDimension.position(Number(slider.value)) * width
    return Math.abs(x - thumbX) <= 22
  }

  moveDrag(event) {
    if (!this.drag || event.pointerId !== this.drag.pointerId) return
    event.preventDefault()
    const { slider, gesture } = this.drag
    const value = gesture.move(event.clientX, event.clientY)
    if (Number(slider.value) !== value) {
      slider.value = value
      this.showDraft(slider)
    }
    this.showPrecision(slider, gesture.precision === "fine" ? "Fine" : "Coarse")
  }

  finishDrag(event) {
    if (!this.drag || event.pointerId !== this.drag.pointerId) return
    this.moveDrag(event)
    this.endDrag(true)
  }

  cancelDrag(event) {
    if (this.drag && event.pointerId === this.drag.pointerId) this.endDrag(false)
  }

  endDrag(commit) {
    if (!this.drag) return
    const { slider, pointerId, original } = this.drag
    this.drag = null
    document.removeEventListener("pointermove", this.pointerMove)
    document.removeEventListener("pointerup", this.pointerUp)
    document.removeEventListener("pointercancel", this.pointerCancel)
    if (slider.hasPointerCapture(pointerId)) slider.releasePointerCapture(pointerId)
    this.showPrecision(slider, "")
    if (commit && slider.value !== original.value) this.save(slider)
    else this.restore(slider, original)
  }

  restore(slider, original) {
    const row = this.rowFor(slider)
    slider.value = original.value
    this.valueLabel(row).textContent = original.label
    this.statusIndicator(row).textContent = original.status
    slider.setAttribute("aria-valuetext", original.aria)
    this.moveHandle(slider)
  }

  preview(event) {
    if (this.drag) return
    const slider = event.target
    const step = this.stepFor(slider)
    slider.value = Math.round(Number(slider.value) / step) * step
    this.showDraft(slider)
  }

  commit(event) {
    if (!this.drag) this.save(event.target)
  }

  adjustWithKeyboard(event) {
    const slider = event.target
    if (slider.disabled) return
    if (this.drag) {
      event.preventDefault()
      if (event.key === "Escape") this.endDrag(false)
      return
    }
    const value = this.keyboardValue(event.key, slider)
    if (value === undefined) return
    event.preventDefault()
    slider.value = value
    this.showDraft(slider)
    this.save(slider)
  }

  keyboardValue(key, slider) {
    const dimension = slider.ratingDimension
    const steps = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1, PageUp: 10, PageDown: -10 }
    if (key === "Home") return dimension.minimum
    if (key === "End") return dimension.maximum
    if (!(key in steps)) return undefined
    return Math.max(dimension.minimum, Math.min(dimension.maximum, Number(slider.value) + steps[key] * this.stepFor(slider)))
  }

  stepFor(slider) {
    return this.precisionValue === "fine" ? slider.ratingDimension.fine_step : slider.ratingDimension.coarse_step
  }

  rateNeutral(event) {
    const slider = this.rowFor(event.currentTarget).querySelector("input")
    slider.value = slider.ratingDimension.neutral_value
    this.showDraft(slider)
    this.save(slider)
  }

  clear(event) {
    this.save(this.rowFor(event.currentTarget).querySelector("input"), "DELETE")
  }

  retry(event) {
    const row = this.rowFor(event.currentTarget)
    this.save(row.querySelector("input"), row.dataset.failedMethod)
  }

  async save(slider, method = "POST") {
    if (slider.disabled) return
    const row = this.rowFor(slider)
    const focused = document.activeElement === slider
    this.markBusy(row, method === "DELETE" ? "Clearing…" : "Saving…")
    try {
      const response = await fetch(this.urlValue, {
        method,
        headers: { "Content-Type": "application/json", Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
        body: JSON.stringify({ dimension_rating: { dimension_key: row.dataset.key, value: Number(slider.value) } })
      })
      if (!this.isRowResponse(response)) throw new Error(`Rating not saved: ${response.status}`)
      await Turbo.renderStreamMessage(await response.text())
      if (focused) this.refocus(row.id)
    } catch (error) {
      this.warn(error.message)
      this.markFailed(row, slider, method)
    }
  }

  isRowResponse(response) {
    return response.ok && response.headers.get("content-type")?.includes("turbo-stream")
  }

  // Turbo swaps in a new row; wait for it before handing focus back.
  refocus(rowId) {
    requestAnimationFrame(() => requestAnimationFrame(() => document.getElementById(rowId)?.querySelector("input")?.focus({ preventScroll: true })))
  }

  markBusy(row, message) {
    row.querySelector("input").disabled = true
    row.setAttribute("aria-busy", "true")
    this.statusIndicator(row).textContent = message
    row.querySelector(".dimension-rating-retry").hidden = true
  }

  markFailed(row, slider, method) {
    slider.disabled = false
    row.removeAttribute("aria-busy")
    row.dataset.failedMethod = method
    this.statusIndicator(row).textContent = method === "DELETE" ? "Couldn’t clear your rating." : "Couldn’t save your rating."
    row.querySelector(".dimension-rating-retry").hidden = false
  }

  showDraft(slider) {
    const row = this.rowFor(slider)
    const label = this.signed(slider.value)
    this.valueLabel(row).textContent = label
    slider.setAttribute("aria-valuetext", label)
    this.statusIndicator(row).textContent = "Not saved yet"
    this.moveHandle(slider)
  }

  showPrecision(slider, label) {
    const indicator = this.rowFor(slider).querySelector(".drag-precision")
    if (indicator.textContent !== label) indicator.textContent = label
  }

  moveHandle(slider) {
    this.rowFor(slider).style.setProperty("--rating-position", `${slider.ratingDimension.position(Number(slider.value)) * 100}%`)
  }

  rowFor(element) { return element.closest(".dimension-rating-row") }
  valueLabel(row) { return row.querySelector(".dimension-rating-value") }
  statusIndicator(row) { return row.querySelector(".status-indicator") }
  csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content || "" }

  signed(value) {
    const number = Number(value)
    return `${number > 0 ? "+" : ""}${number.toLocaleString()}`
  }

  debug(...messages) {
    if (this.logLevelValue === "debug") console.debug("[DimensionRating]", ...messages)
  }

  warn(...messages) {
    if (this.logLevelValue !== "silent") console.warn("[DimensionRating]", ...messages)
  }
}
