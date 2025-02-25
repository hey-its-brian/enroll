import { Controller } from "stimulus";

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("tr[data-href]").forEach((row) => {
      row.setAttribute("data-action", `click->${this.identifier}#navigate`);
    });
  }

  navigate(event) {
    const url = event.currentTarget.dataset.href;
    if (url) {
      window.location.href = url;
    }
  }
}
