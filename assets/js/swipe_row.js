// Swipe a row to the left (or long-press it) to reveal its actions.
// Markup comes from PuppyLogWeb.UI.swipe_row/1. Only one row is open at a time.

const OPEN_EVENT = "swipe-row:open"
const LONG_PRESS_MS = 450
const SLOP = 8

export const SwipeRow = {
  mounted() {
    this.front = this.el.querySelector(".swipe-front")
    this.isOpen = false
    this.suppressClick = false

    this.onDown = e => this.down(e)
    this.onMove = e => this.move(e)
    this.onUp = e => this.up(e)
    this.onClick = e => this.click(e)
    this.onOtherOpen = e => { if (e.detail !== this.el) this.setOpen(false) }
    this.onOutside = e => { if (this.isOpen && !this.el.contains(e.target)) this.setOpen(false) }

    this.front.addEventListener("pointerdown", this.onDown)
    this.front.addEventListener("pointermove", this.onMove)
    this.front.addEventListener("pointerup", this.onUp)
    this.front.addEventListener("pointercancel", this.onUp)
    this.front.addEventListener("click", this.onClick, true)
    this.front.addEventListener("contextmenu", e => e.preventDefault())
    window.addEventListener(OPEN_EVENT, this.onOtherOpen)
    document.addEventListener("pointerdown", this.onOutside)
  },

  updated() {
    // LiveView patches reset the class attribute; restore our state.
    this.el.classList.toggle("is-open", this.isOpen)
  },

  destroyed() {
    window.removeEventListener(OPEN_EVENT, this.onOtherOpen)
    document.removeEventListener("pointerdown", this.onOutside)
    clearTimeout(this.timer)
  },

  width() {
    return parseInt(getComputedStyle(this.el).getPropertyValue("--swipe-width"), 10) || 132
  },

  setOpen(open) {
    this.isOpen = open
    this.el.classList.toggle("is-open", open)
    if (open) window.dispatchEvent(new CustomEvent(OPEN_EVENT, {detail: this.el}))
  },

  down(e) {
    this.start = {x: e.clientX, y: e.clientY}
    this.dragging = false
    this.offset = 0
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.suppressClick = true
      if (navigator.vibrate) navigator.vibrate(10)
      this.setOpen(!this.isOpen)
    }, LONG_PRESS_MS)
  },

  move(e) {
    if (!this.start) return
    const dx = e.clientX - this.start.x
    const dy = e.clientY - this.start.y

    if (!this.dragging) {
      if (Math.abs(dx) > SLOP || Math.abs(dy) > SLOP) clearTimeout(this.timer)
      if (Math.abs(dx) > SLOP && Math.abs(dx) > Math.abs(dy)) {
        this.dragging = true
        this.el.classList.add("is-dragging")
        this.front.setPointerCapture(e.pointerId)
      } else {
        return
      }
    }

    const width = this.width()
    const base = this.isOpen ? -width : 0
    this.offset = Math.max(Math.min(base + dx, 0), -width - 24)
    this.front.style.transform = `translateX(${this.offset}px)`
  },

  up(_e) {
    clearTimeout(this.timer)
    if (this.dragging) {
      this.suppressClick = true
      this.el.classList.remove("is-dragging")
      this.front.style.transform = ""
      this.setOpen(this.offset < -this.width() / 2)
    }
    this.start = null
    this.dragging = false
  },

  click(e) {
    if (this.suppressClick || this.isOpen) {
      e.preventDefault()
      e.stopPropagation()
      if (!this.suppressClick) this.setOpen(false)
    }
    this.suppressClick = false
  },
}
