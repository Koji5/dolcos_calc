import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: Number
  }

  connect() {
    document.scrollingElement?.scrollTo({ top: 0, behavior: "smooth" })
    if (this.hasDelayValue) {
      setTimeout(() => this._animateAndRemove(), this.delayValue)
    }
  }

  dismiss(event) {
    event.preventDefault()
    this._animateAndRemove()
  }

  _animateAndRemove() {
    const el = this.element
    const height = el.scrollHeight + "px"

    el.style.height = height
    el.offsetHeight // reflow で height を確定
    el.style.transition = "opacity 0.6s ease, height 0.6s ease, margin 0.6s ease, padding 0.6s ease"
    el.style.opacity = "0"
    el.style.height = "0"
    el.style.margin = "0"
    el.style.padding = "0"
    el.style.overflow = "hidden"

    setTimeout(() => {
      this.element.remove()
    }, 600)
  }
}
