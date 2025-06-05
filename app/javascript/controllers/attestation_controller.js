import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["Check", "SubmitButton", "FirstNameField", "LastNameField", "FirstName", "LastName"]

  connect() {
    this.canSubmitCheck()
  }

  canSubmitCheck() {
    let allChecked = this.CheckTargets.every(check => check.checked)
    let validSignature = this.checkSignature()
    let canSubmit = allChecked && validSignature
    if (canSubmit) {
      this.SubmitButtonTarget.disabled = false
      this.SubmitButtonTarget.classList.remove('disabled')
    } else {
      this.SubmitButtonTarget.disabled = true
      this.SubmitButtonTarget.classList.add('disabled')
    }
  }

  checkSignature() {
    let firstNameInput = this.FirstNameFieldTarget.value
    let lastNameInput = this.LastNameFieldTarget.value
    let firstName = this.FirstNameTarget.value
    let lastName = this.LastNameTarget.value
    if (firstNameInput.length > 0 && lastNameInput.length > 0 && firstName.length > 0 && lastName.length > 0) {
      return firstNameInput.toLowerCase() === firstName && lastNameInput.toLowerCase() === lastName
    } else {
      return false
    }
  }

}