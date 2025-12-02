import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["nameField"]

  static VALID_NAME_REGEX = /^[a-zA-Z\s'-]+$/
  static VALIDATION_MESSAGE = "Name fields can only contain letters, spaces, hyphens, and apostrophes."

  connect() {
    this.nameFieldTargets.forEach(field => {
      field.addEventListener('input', (event) => this.validateName(event))
    })
  }

  validateName(event) {
    const field = event.target;
    const value = field.value.trim();

    field.setCustomValidity('');
    if (value && !this.constructor.VALID_NAME_REGEX.test(value)) {
      field.setCustomValidity(this.constructor.VALIDATION_MESSAGE);
    }
  }
}
