import { Controller } from "@hotwired/stimulus"

// WebAuthn ceremonies. The server sends the options as JSON and checks the
// credential; this only hands them to the browser and back.
export default class extends Controller {
  static targets = ["error", "name", "password"]
  static values = { challengeUrl: String, url: String }

  connect() {
    if (!window.PublicKeyCredential?.parseRequestOptionsFromJSON) this.element.hidden = true
  }

  async signIn() {
    await this.run(async (options) => {
      const credential = await navigator.credentials.get({ publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options) })
      return { credential: credential.toJSON() }
    })
  }

  async register() {
    const start = { current_password: this.hasPasswordTarget ? this.passwordTarget.value : "" }
    await this.run(async (options) => {
      const credential = await navigator.credentials.create({ publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options) })
      return { credential: credential.toJSON(), name: this.hasNameTarget ? this.nameTarget.value : "" }
    }, start)
  }

  async run(ceremony, start = {}) {
    this.showError("")
    try {
      const options = await this.post(this.challengeUrlValue, start)
      const body = await ceremony(options)
      const result = await this.post(this.urlValue, body)
      Turbo.visit(result.location)
    } catch (error) {
      if (error.name !== "NotAllowedError" && error.name !== "AbortError") this.showError(error.message)
    }
  }

  async post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body: JSON.stringify(body),
      credentials: "same-origin"
    })
    const json = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(json.error || "Something went wrong. Try again.")
    return json
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = !message
  }
}
