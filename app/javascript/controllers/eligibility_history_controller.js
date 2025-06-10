import { Controller } from "stimulus";

/*
 * This controller is used to submit application selection.
 */
export default class extends Controller {
  connect() {
  }

  submit(event) {
    event.target.form.submit()
  }
}
