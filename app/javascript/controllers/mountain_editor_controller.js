import { Controller } from "@hotwired/stimulus"
import { track } from "analytics"

// Interactive mountain ratings: drag within a candidate column, or slide a row in the list view, to
// set 0–500, and drag, slide or nudge the baseline to set the approval threshold. The mountain-range
// controller on the chart draws and animates what changes. Every change autosaves to the server draft,
// which answers with fresh Your vote, allowance and save bar panels.
export default class extends Controller {
  static targets = ["form"]
  static values = {
    maxHeight: { type: Number, default: 320 },
    draftUrl: String,
    autosaveDelay: { type: Number, default: 400 },
    logLevel: { type: String, default: "warn" }
  }

  connect() {
    this.draggingRating = false
    this.draggingBaseline = false
    this.activeRatingArea = null
    this.boundPointerMove = this.onPointerMove.bind(this)
    this.boundPointerUp = this.onPointerUp.bind(this)
    this.updateApprovalStates()
    this.trackedRatings = new Map(this.candidateColumns().map(column => [column.dataset.candidacyId, document.getElementById(column.dataset.ratingInputId).value]))
    this.trackedBaseline = this.baselineValue()
    if (this.isPhoneWidth()) this.setView("list")
  }

  disconnect() {
    this.teardownDocumentListeners()
    clearTimeout(this.autosaveTimer)
  }

  // The hidden form only feeds autosave; pressing Enter in it must not publish the mountain.
  preventSubmit(event) {
    event.preventDefault()
  }

  showView(event) {
    this.setView(event.params.view)
  }

  togglePartyEndorsements(event) {
    const visible = this.element.dataset.partyEndorsements !== "true"
    this.element.dataset.partyEndorsements = String(visible)
    event.currentTarget.setAttribute("aria-pressed", String(visible))
  }

  // Phones get the list: sliders are easier to thumb than columns.
  isPhoneWidth() {
    return window.matchMedia("(max-width: 640px)").matches
  }

  setView(view) {
    this.element.dataset.view = view
    this.element.querySelectorAll("[data-view-button]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.viewButton === view))
    })
  }

  rateFromSlider(event) {
    const column = this.candidateColumn(event.target.dataset.candidacyId)
    if (column) this.applyRatingUpdate(column, Number.parseInt(event.target.value, 10))
  }

  setBaselineFromSlider(event) {
    this.applyBaselineUpdate(Number.parseInt(event.target.value, 10))
  }

  nudgeBaseline(event) {
    const current = this.baselineValue() ?? 200
    this.applyBaselineUpdate(Math.max(0, Math.min(500, current + event.params.step)), { glide: true })
    this.trackBaselineChange("button")
  }

  finishRatingSlider(event) {
    this.trackRatingChange(this.candidateColumn(event.target.dataset.candidacyId), "slider")
  }

  finishBaselineSlider() {
    this.trackBaselineChange("slider")
  }

  analyticsProperties() {
    return { race_id: this.element.dataset.analyticsRaceId, race_mode: this.element.dataset.analyticsRaceMode, view: this.element.dataset.view }
  }

  trackRatingChange(column, inputMethod) {
    const id = column.dataset.candidacyId
    const value = document.getElementById(column.dataset.ratingInputId).value
    if (this.trackedRatings.get(id) === value) return

    this.trackedRatings.set(id, value)
    const ballotColumns = this.candidateColumns().filter(column => !column.classList.contains("off-ballot"))
    track("rating_changed", {
      ...this.analyticsProperties(), candidacy_id: id, input_method: inputMethod,
      rated_count: ballotColumns.filter(column => document.getElementById(column.dataset.ratingInputId).value !== "").length,
      candidate_count: ballotColumns.length, off_ballot: column.classList.contains("off-ballot")
    })
  }

  trackBaselineChange(inputMethod) {
    const baseline = this.baselineValue()
    if (baseline === this.trackedBaseline) return

    const scores = this.candidateColumns().filter(column => !column.classList.contains("off-ballot"))
      .map(column => document.getElementById(column.dataset.ratingInputId).value).filter(value => value !== "").map(Number)
    track("baseline_changed", {
      ...this.analyticsProperties(), input_method: inputMethod,
      direction: baseline > this.trackedBaseline ? "raised" : "lowered",
      approval_count_changed: scores.filter(value => value > baseline).length !== scores.filter(value => value > this.trackedBaseline).length
    })
    this.trackedBaseline = baseline
  }

  // Waits for any pending autosave so Save mountain publishes the latest edits.
  async saveAfterDraft(event) {
    if (!this.hasPendingAutosave()) return

    event.preventDefault()
    await this.autosave()
    event.target.requestSubmit()
  }

  hasPendingAutosave() {
    return Boolean(this.autosaveTimer || this.inflightAutosave)
  }

  scheduleAutosave() {
    if (!this.draftUrlValue || !this.hasFormTarget) return

    clearTimeout(this.autosaveTimer)
    this.autosaveTimer = setTimeout(() => this.autosave(), this.autosaveDelayValue)
  }

  async autosave() {
    clearTimeout(this.autosaveTimer)
    this.autosaveTimer = null
    if (this.inflightAutosave) await this.inflightAutosave

    this.inflightAutosave = this.sendDraft()
    try {
      await this.inflightAutosave
    } finally {
      this.inflightAutosave = null
    }
  }

  async sendDraft() {
    const body = new FormData(this.formTarget)
    body.delete("_method")
    try {
      const response = await fetch(this.draftUrlValue, {
        method: "PATCH",
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
        body
      })
      if (!response.ok) throw new Error(`Draft refused with ${response.status}`)
      window.Turbo.renderStreamMessage(await response.text())
      this.logDebug("[Mountain] Draft saved")
    } catch (error) {
      this.logWarning("[Mountain] Draft not saved", error)
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  logDebug(...messages) {
    if (this.logLevelValue === "debug") console.debug(...messages)
  }

  logWarning(...messages) {
    if (this.logLevelValue !== "silent") console.warn(...messages)
  }

  startRatingDrag(event) {
    if (!this.isPrimaryPointer(event)) return
    if (this.isInteractiveChrome(event.target)) return

    event.preventDefault()
    this.draggingRating = true
    this.draggingBaseline = false
    this.activeRatingArea = event.currentTarget
    this.capturePointer(event, this.activeRatingArea)
    this.toggleDraggingClass(this.activeRatingArea, true)
    this.attachDocumentListeners()
    this.updateRatingFromEvent(event)
  }

  startBaselineDrag(event) {
    if (!this.isPrimaryPointer(event)) return

    event.preventDefault()
    event.stopPropagation()
    this.draggingBaseline = true
    this.draggingRating = false
    this.activeRatingArea = null
    this.capturePointer(event, event.currentTarget)
    this.toggleBaselineDragging(true)
    this.attachDocumentListeners()
    this.updateBaselineFromEvent(event)
  }

  // Kept for data-action bindings; real work is in document listeners while dragging.
  dragRating(event) {
    if (!this.draggingRating) return
    this.updateRatingFromEvent(event)
  }

  dragBaseline(event) {
    if (!this.draggingBaseline) return
    this.updateBaselineFromEvent(event)
  }

  stopRatingDrag() {
    this.finishDrag()
  }

  stopBaselineDrag() {
    this.finishDrag()
  }

  onPointerMove(event) {
    if (this.draggingRating) {
      this.updateRatingFromEvent(event)
    } else if (this.draggingBaseline) {
      this.updateBaselineFromEvent(event)
    }
  }

  onPointerUp() {
    this.finishDrag()
  }

  finishDrag() {
    if (this.draggingRating) {
      this.trackRatingChange(this.closestCandidateColumn(this.activeRatingArea), "chart")
      this.toggleDraggingClass(this.activeRatingArea, false)
    }
    if (this.draggingBaseline) {
      this.trackBaselineChange("chart")
      this.toggleBaselineDragging(false)
    }

    this.draggingRating = false
    this.draggingBaseline = false
    this.activeRatingArea = null
    this.teardownDocumentListeners()
  }

  attachDocumentListeners() {
    document.addEventListener("pointermove", this.boundPointerMove)
    document.addEventListener("pointerup", this.boundPointerUp)
    document.addEventListener("pointercancel", this.boundPointerUp)
  }

  teardownDocumentListeners() {
    document.removeEventListener("pointermove", this.boundPointerMove)
    document.removeEventListener("pointerup", this.boundPointerUp)
    document.removeEventListener("pointercancel", this.boundPointerUp)
  }

  updateRatingFromEvent(event) {
    const ratingArea = this.activeRatingArea
    if (!ratingArea) return

    const column = this.closestCandidateColumn(ratingArea)
    if (!column) return

    const ratingValue = this.ratingFromPointer(event, ratingArea)
    this.applyRatingUpdate(column, ratingValue)
  }

  updateBaselineFromEvent(event) {
    const ratingArea = this.firstRatingArea()
    if (!ratingArea) return

    const ratingValue = this.ratingFromPointer(event, ratingArea)
    this.applyBaselineUpdate(ratingValue)
  }

  applyRatingUpdate(column, ratingValue) {
    const inputId = column.dataset.ratingInputId
    if (!inputId) return

    const input = document.getElementById(inputId)
    if (!input) return

    input.value = ratingValue
    this.updateColumnDisplay(column, ratingValue)
    this.updateListRow(column.dataset.candidacyId, ratingValue)
    this.updateApprovalStates()
    this.announceToChart("rated", { candidacyId: column.dataset.candidacyId, rating: ratingValue, glide: false })
    this.scheduleAutosave()
  }

  applyBaselineUpdate(ratingValue, { glide = false } = {}) {
    const input = this.baselineInput()
    if (!input) return

    input.value = ratingValue
    this.updateBaselineIndicator(ratingValue)
    this.updateBaselineDisplays(ratingValue)
    this.updateApprovalStates()
    this.announceToChart("baseline-moved", { baseline: ratingValue, glide })
    this.scheduleAutosave()
  }

  announceToChart(name, detail) {
    const chart = this.chartElement()
    if (chart) this.dispatch(name, { target: chart, detail })
  }

  updateListRow(candidacyId, ratingValue) {
    const row = this.listRow(candidacyId)
    if (!row) return

    row.querySelector("[data-role='rating-slider']").value = ratingValue
    row.querySelector("[data-role='row-value']").textContent = ratingValue
  }

  updateBaselineDisplays(ratingValue) {
    this.element.querySelectorAll("[data-role='baseline-value']").forEach((element) => {
      element.textContent = ratingValue
    })
    this.element.querySelectorAll("[data-role='baseline-slider']").forEach((slider) => {
      slider.value = ratingValue
    })
    const list = this.element.querySelector(".rating-list")
    if (list) list.style.setProperty("--baseline", `${ratingValue / 5}%`)
  }

  updateColumnDisplay(column, ratingValue) {
    const ratingDot = column.querySelector("[data-role='rating-dot']")
    if (ratingDot) {
      ratingDot.title = `Rating: ${ratingValue} (${this.approvalLabel(ratingValue)})`
    }

    const ratingValueElement = column.querySelector("[data-role='rating-value']")

    if (ratingValueElement) {
      ratingValueElement.textContent = `Rating: ${ratingValue}`
      ratingValueElement.hidden = false
    }
  }

  updateBaselineIndicator(ratingValue) {
    const baselineIndicator = this.baselineIndicator()
    if (!baselineIndicator) return

    baselineIndicator.title = `Approval Baseline: ${ratingValue}`
    baselineIndicator.dataset.baselineSet = "true"

    const label = baselineIndicator.querySelector("[data-role='baseline-label']")
    if (label) {
      label.textContent = `Baseline: ${ratingValue}`
    }

    const labelContainer = baselineIndicator.querySelector(".baseline-label")
    if (labelContainer) {
      labelContainer.classList.remove("baseline-empty")
    }
  }

  updateApprovalStates() {
    const baselineValue = this.baselineValue()
    const columns = this.candidateColumns()

    columns.forEach((column) => {
      const inputId = column.dataset.ratingInputId
      if (!inputId) return

      const input = document.getElementById(inputId)
      if (!input || input.value === "") {
        this.applyDotState(column, false, false)
        return
      }

      const ratingValue = Number.parseInt(input.value, 10)
      const approved = baselineValue !== null && ratingValue > baselineValue
      this.applyDotState(column, true, approved)
    })
  }

  applyDotState(column, hasRating, approved) {
    const row = this.listRow(column.dataset.candidacyId)
    if (row) row.dataset.state = hasRating ? (approved ? "approved" : "not-approved") : "unrated"

    const ratingDot = column.querySelector("[data-role='rating-dot']")
    if (!ratingDot) return

    ratingDot.classList.toggle("unrated", !hasRating)
    ratingDot.classList.toggle("approved", hasRating && approved)
    ratingDot.classList.toggle("disapproved", hasRating && !approved)
  }

  approvalLabel(ratingValue) {
    const baselineValue = this.baselineValue()
    if (baselineValue === null) return "Disapproved"
    return ratingValue > baselineValue ? "Approved" : "Disapproved"
  }

  baselineValue() {
    const input = this.baselineInput()
    if (!input || input.value === "") return null
    return Number.parseInt(input.value, 10)
  }

  ratingFromPointer(event, areaElement) {
    const rect = areaElement.getBoundingClientRect()
    const clientY = event.clientY ?? event.touches?.[0]?.clientY
    if (clientY === undefined) return 0

    const relativeY = clientY - rect.top
    const height = rect.height || this.maxHeightValue || 320
    const clampedY = Math.max(0, Math.min(relativeY, height))
    const rating = Math.round((1 - clampedY / height) * 500)
    return Math.max(0, Math.min(rating, 500))
  }

  chartElement() {
    return this.element.querySelector(".mountain-chart")
  }

  baselineIndicator() {
    return this.element.querySelector(".baseline-indicator")
  }

  baselineInput() {
    return this.element.querySelector("[data-mountain-editor-target='baselineInput']")
  }

  candidateColumns() {
    return Array.from(this.element.querySelectorAll(".candidate-column"))
  }

  firstRatingArea() {
    return this.element.querySelector(".rating-area")
  }

  candidateColumn(candidacyId) {
    return this.element.querySelector(`.candidate-column[data-candidacy-id='${candidacyId}']`)
  }

  listRow(candidacyId) {
    return this.element.querySelector(`[data-role='rating-row'][data-candidacy-id='${candidacyId}']`)
  }

  closestCandidateColumn(element) {
    return element.closest(".candidate-column")
  }

  isInteractiveChrome(target) {
    return Boolean(target.closest("a, button, input, textarea, select, label"))
  }

  toggleDraggingClass(element, shouldAdd) {
    if (!element) return
    element.classList.toggle("is-dragging", shouldAdd)
  }

  toggleBaselineDragging(shouldAdd) {
    const chart = this.chartElement()
    if (!chart) return
    chart.classList.toggle("baseline-dragging", shouldAdd)
  }

  capturePointer(event, element) {
    if (element?.setPointerCapture && event.pointerId !== undefined) {
      try {
        element.setPointerCapture(event.pointerId)
      } catch (_error) {
        // Ignore if the pointer is already released (common on touch end races).
      }
    }
  }

  isPrimaryPointer(event) {
    return event.isPrimary !== false
  }
}
