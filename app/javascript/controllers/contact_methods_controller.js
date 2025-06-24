import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["preferencesForm", "homePhone", "mobilePhone", "homeEmail", "workEmail", "submitButton", "mailPreference", "emailPreference", "textPreference"]

  connect() {
    this.canSubmitCheck()
  }

  canSubmitCheck() {
    const emailValid = this.emailChecked()
    const textValid = this.textChecked()
    const homePhoneValid = this.homePhoneChecked()

    if (!emailValid || !textValid || !homePhoneValid) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add('disabled')
    } else {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove('disabled')
    }
  }

  emailChecked() {
    const emailPreference = this.emailPreferenceTarget.checked
    let homeEmail = this.homeEmailTarget
    let emailLabel = homeEmail.closest('div').querySelector('label')
    if (emailPreference) {
      homeEmail.required = true
      emailLabel.classList.add('required')
      let valid = true
      if (homeEmail.value.length < 1) {
        homeEmail.setCustomValidity("You must enter an email address to receive notices and updates by email.")
        valid = false
      } else {
        homeEmail.setCustomValidity('')
      }
      this.preferencesFormTarget.reportValidity()
      return valid
    } else {
      this.homeEmailTarget.required = false
      emailLabel.classList.remove('required')
      homeEmail.setCustomValidity('')
      this.preferencesFormTarget.reportValidity()
      return true
    }
  }

  textChecked() {
    const textPreference = this.textPreferenceTarget.checked
    let mobilePhone = this.mobilePhoneTarget
    let textLabel = mobilePhone.closest('div').querySelector('label')
    let phoneValue = mobilePhone.value.replace(/\D/g, '')
    if (textPreference) {
      mobilePhone.required = true
      textLabel.classList.add('required')
      let valid = true
      if (/^(.)\0*$/.test(phoneValue)) {
        mobilePhone.setCustomValidity("Mobile Phone number cannot be all zeros.")
        valid = false
      } else if (phoneValue.length < 1 || phoneValue.length < 10) {
        mobilePhone.setCustomValidity("You must enter a mobile phone number to receive notices and updates by text.")
        valid = false
      } else {
        mobilePhone.setCustomValidity('')
      }
      this.preferencesFormTarget.reportValidity()
      return valid
    } else {
      mobilePhone.required = false
      textLabel.classList.remove('required')
      mobilePhone.setCustomValidity('')
      this.preferencesFormTarget.reportValidity()
      return true
    }
  }

  homePhoneChecked() {
    let homePhone = this.homePhoneTarget
    let phoneValue = homePhone.value.replace(/\D/g, '')
    if (phoneValue.length > 0) {
      let valid = true
      if (/^(.)\0*$/.test(phoneValue)) {
        homePhone.setCustomValidity("Home Phone number cannot be all zeros.")
        valid = false
      } else if (phoneValue.length < 1 || phoneValue.length < 10) {
        homePhone.setCustomValidity("Home phone must be 10 digits long.")
        valid = false
      } else {
        homePhone.setCustomValidity('')
      }
      this.preferencesFormTarget.reportValidity()
      return valid
    } else {
      homePhone.setCustomValidity('')
      this.preferencesFormTarget.reportValidity()
      return true
    }
  }

  alertForInvalidContactMethods(event) {
    event.preventDefault()
    let mailPreference = this.mailPreferenceTarget.checked
    let emailPreference = this.emailPreferenceTarget.checked
    let textPreference = this.textPreferenceTarget.checked

    if (!mailPreference && !emailPreference && !textPreference) {
      alert('A contact method is required to proceed. If selecting Text, you must also choose Email or Mail.');
    } else if (textPreference && !mailPreference && !emailPreference) {
      alert('Text cannot be your only contact method. If you select Text, you must also choose Email or Mail.');
    } else {
      this.preferencesFormTarget.submit()
    }
  }

  textMessageOnly() {
    let textPreference = this.textPreferenceTarget.checked
    let mailPreference = this.mailPreferenceTarget.checked
    let emailPreference = this.emailPreferenceTarget.checked

    if (textPreference && !mailPreference && !emailPreference) {
      return false
    } else {
      return true
    }
  }

}
