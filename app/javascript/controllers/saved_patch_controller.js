import { Controller } from "@hotwired/stimulus"

// Animates saved-page rows into an inline Undo patch when unmarked, and back when restored.
export default class extends Controller {
  connect() {
    this.beforeStreamRender = this.handleBeforeStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.beforeStreamRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)
  }

  handleBeforeStreamRender(event) {
    const stream = event.target
    if (stream.getAttribute("action") !== "replace") return

    const targetId = stream.getAttribute("target")
    if (!targetId || !targetId.startsWith("saved_")) return

    const existing = this.element.querySelector(`#${CSS.escape(targetId)}`)
    if (!existing) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    event.preventDefault()
    const render = event.detail.render

    existing.style.maxHeight = `${existing.offsetHeight}px`
    void existing.offsetHeight
    existing.classList.add("is-leaving")

    window.setTimeout(() => render(stream), 190)
  }
}
