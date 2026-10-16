// Replaces the browser's confirm() for data-turbo-confirm with the dialog in
// layouts/_confirm. Destructive actions (DELETE requests or danger buttons)
// get a red confirm button. Optional attributes on the form or link:
//   data-turbo-confirm-title    heading, default "Are you sure?"
//   data-turbo-confirm-button   confirm button label
import { Turbo } from "@hotwired/turbo-rails"

const DANGER_CLASSES = ["btn-danger", "btn-danger-solid", "btn-icon-danger"]

function isDestructive(element, submitter) {
  const method = (element.querySelector?.("input[name=_method]")?.value || element.getAttribute?.("method") || "").toLowerCase()
  if (method === "delete") return true

  return [element, submitter].some((node) => node && DANGER_CLASSES.some((name) => node.classList?.contains(name)))
}

function dataFrom(element, submitter, name) {
  return submitter?.dataset?.[name] || element.dataset?.[name]
}

export function confirmWithDialog(message, element, submitter) {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(window.confirm(message))

  const destructive = isDestructive(element, submitter)
  const button = dialog.querySelector("[data-confirm-button]")
  const icon = dialog.querySelector("[data-confirm-icon]")

  dialog.querySelector("[data-confirm-title]").textContent = dataFrom(element, submitter, "turboConfirmTitle") || "Are you sure?"
  dialog.querySelector("[data-confirm-message]").textContent = message
  button.textContent = dataFrom(element, submitter, "turboConfirmButton") || (destructive ? "Delete" : "Confirm")
  button.className = destructive ? "btn-danger-solid" : "btn-primary"
  icon.classList.toggle("bg-danger/10", destructive)
  icon.classList.toggle("text-danger", destructive)
  icon.classList.toggle("bg-strong-accent/10", !destructive)
  icon.classList.toggle("text-strong-accent", !destructive)

  dialog.returnValue = ""
  dialog.showModal()

  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), { once: true })
  })
}

Turbo.config.forms.confirm = confirmWithDialog
