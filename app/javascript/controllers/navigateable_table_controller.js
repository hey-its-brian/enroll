import { Controller } from "stimulus";

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("tr[data-href]").forEach((row) => {
      const actions = [ "click", "keydown" ].map((eventType) => { return `${eventType}->${this.identifier}#handleEvent` }).join(" ");
      row.setAttribute("data-action", actions);
      row.setAttribute("tabindex", "0");
    });
  }

  handleEvent(event) {
    if (event.type === "click" || (event.type === "keydown" && event.key === "Enter")) {
      this.#navigate(event.currentTarget);
    }
  }

  #navigate(target) {
    const url = target.dataset.href;
    if (url) {
      window.location.href = url;
    }
  }
}
