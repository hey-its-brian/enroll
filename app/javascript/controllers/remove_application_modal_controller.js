// app/javascript/controllers/remove_application_modal_controller.js
import { Controller } from "stimulus"

export default class extends Controller {
  redirectAndClose(event) {
    event.preventDefault()

    const modal = this.element.closest(".modal")
    if (modal) {
      modal.classList.remove("show")
      modal.setAttribute("aria-hidden", "true")
      modal.style.display = "none"


      const backdrop = document.querySelector(".modal-backdrop")
      if (backdrop) {
        backdrop.remove()
      }
    }

    const url = event.currentTarget.getAttribute("href")
    window.location.href = url
  }
}
