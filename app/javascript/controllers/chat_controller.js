import { Controller } from "@hotwired/stimulus"

// Research chat: follows a streaming answer unless the reader scrolled up
// (then offers "Jump to latest"), grows the composer with its text, sends on
// Enter (Shift+Enter for a new line), and locks the composer while an answer
// is still being written.
export default class extends Controller {
  static targets = ["scroller", "messages", "jump", "form", "input", "send"]
  static NEAR_BOTTOM = 160

  connect() {
    this.following = true
    if (this.hasMessagesTarget) {
      this.observer = new MutationObserver(() => this.messagesChanged())
      this.observer.observe(this.messagesTarget, { childList: true, subtree: true, characterData: true })
      this.scrollToBottom()
      this.syncComposer()
    }
    if (this.hasInputTarget) {
      this.resize()
      // Focusing on load would open the keyboard on phones, so only do it with a mouse or trackpad.
      if (!this.inputTarget.disabled && window.matchMedia("(pointer: fine)").matches) this.inputTarget.focus()
    }
  }

  disconnect() {
    this.observer?.disconnect()
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    if (this.inputTarget.value.trim() && !this.inputTarget.disabled) this.formTarget.requestSubmit()
  }

  resize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${input.scrollHeight}px`
  }

  fill({ params: { text } }) {
    this.inputTarget.value = text
    this.resize()
    this.inputTarget.focus()
  }

  scrolled() {
    this.following = this.distanceFromBottom() < this.constructor.NEAR_BOTTOM
    if (this.hasJumpTarget) this.jumpTarget.hidden = this.following
  }

  jumpToLatest() {
    this.following = true
    this.jumpTarget.hidden = true
    this.scrollToBottom("smooth")
  }

  messagesChanged() {
    if (this.following) this.scrollToBottom()
    else if (this.hasJumpTarget) this.jumpTarget.hidden = false
    this.syncComposer()
  }

  syncComposer() {
    if (!this.hasInputTarget) return

    const busy = !!this.messagesTarget.querySelector("[data-message-status=streaming]")
    this.inputTarget.disabled = busy
    if (this.hasSendTarget) this.sendTarget.disabled = busy
    this.inputTarget.placeholder = busy ? "wait for the answer to finish" : "ask a follow-up question"
  }

  scrollToBottom(behavior = "auto") {
    if (this.hasScrollerTarget) this.scrollerTarget.scrollTo({ top: this.scrollerTarget.scrollHeight, behavior })
  }

  distanceFromBottom() {
    const scroller = this.scrollerTarget
    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight
  }
}
