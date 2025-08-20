import { Controller } from "stimulus"
import IMask from "imask"

export default class extends Controller {
  static targets = [
    "enrollSmsNotificationsInput",
    "disableSubmissionInput",
    "preferencesForm",
    "homePhone",
    "mobilePhone",
    "homeEmail",
    "workEmail",
    "submitButton",
    "mailPreference",
    "emailPreference",
    "textPreference",
    "yearsToRenew",
    "methodContainer"
  ]

  // Get the sms flag from the input.
  get isSmsFlagEnabled() {
    return this.hasEnrollSmsNotificationsInputTarget && this.enrollSmsNotificationsInputTarget.value === "true"
  }

  // Get the disable submission control from the input.
  // This control is used to drive whether or not the contact method validation disables the save button, 
  // allowing some flows to disable the save button when validation fails.
  get canDisableSubmission() {
    return this.hasDisableSubmissionInputTarget && this.disableSubmissionInputTarget.value === "true"
  }

  get validators() {
    if (!this._validators) {
      this._validators = {
        homeEmail: new PersonalEmailValidator(this.homeEmailTarget),
        mobilePhone: new MobilePhoneValidator(this.mobilePhoneTarget),
        homePhone: new HomePhoneValidator(this.homePhoneTarget)
      }
    }
    return this._validators
  }

  get hasMobilePhone() {
    return this.validators.mobilePhone.hasValue
  }

  get hasHomeEmail() {
    return this.validators.homeEmail.hasValue
  }

  get preferences() {
    return {
      mail: this.mailPreferenceTarget.checked,
      email: this.emailPreferenceTarget.checked,
      text: this.textPreferenceTarget.checked
    }
  }

  connect() {
    this.updateFormState(this.canDisableSubmission) // when the form can disable the save button, we should report validity on connection
    this.maskPhones()
  }

  updateFormState(reportErrors = true) {
    this.homeEmailTarget.setCustomValidity(this.validateEmail() || '')
    this.mobilePhoneTarget.setCustomValidity(this.validateText() || '')
    this.homePhoneTarget.setCustomValidity(this.validateHomePhone() || '')

    if (this.canDisableSubmission) {
      const hasErrors = !this.preferencesFormTarget.checkValidity()
      this.submitButtonTarget.disabled = hasErrors
      this.submitButtonTarget.classList.toggle('disabled', hasErrors)
    }

    if (reportErrors) {
      this.preferencesFormTarget.reportValidity()
    }
  }

  validateEmail() {
    const hasEmailContact = this.preferences.email

    let isMobilePhoneBlankOrBothFilled = (this.isSmsFlagEnabled && (!this.hasMobilePhone || this.hasHomeEmail))
    this.toggleFieldRequired(this.homeEmailTarget, hasEmailContact || isMobilePhoneBlankOrBothFilled)

    if (hasEmailContact) {
      return this.validators.homeEmail.validate()
    }
    return null
  }

  validateText() {
    const hasTextContact = this.preferences.text
    let isHomeEmailBlankOrBothFilled = (this.isSmsFlagEnabled && (!this.hasHomeEmail || this.hasMobilePhone))
    this.toggleFieldRequired(this.mobilePhoneTarget, hasTextContact || isHomeEmailBlankOrBothFilled)

    if (hasTextContact) {
      return this.validators.mobilePhone.validate()
    }
    return null
  }
  
  validateHomePhone() {
    return this.validators.homePhone.validate()
  }

  validateSubmission(event) {
    if (!this.preferencesFormTarget.checkValidity()) {
      event.preventDefault();
      this.preferencesFormTarget.reportValidity();
      return;
    }

    if (this.hasYearsToRenewTarget) {
      if (!this.yearsToRenewTarget.checkValidity()) {
        event.preventDefault();
        this.yearsToRenewTarget.reportValidity();
        return;
      }
    }

    if (this.hasMethodContainerTarget) {
      this.setDestroys()
    }

    const preferences = this.preferences

    if (this.isSmsFlagEnabled && this.homeEmailTarget.value.length == 0 && this.mobilePhoneTarget.value == 0) {
      event.preventDefault();
      alert('An email or mobile phone number is required.');
      this.mobilePhoneTarget.focus();
    } else if (!preferences.mail && !preferences.email && !preferences.text) {
      event.preventDefault();
      alert('A contact method is required to proceed. If selecting Text, you must also choose Email or Mail.');
    } else if (preferences.text && !preferences.mail && !preferences.email) {
      event.preventDefault();
      alert('Text cannot be your only contact method. If you select Text, you must also choose Email or Mail.');
    } else {
      this.preferencesFormTarget.submit()
    }
  }

  setDestroys() {
    this.methodContainerTargets.forEach(container => {
      let input = container.querySelector('input.full-width')
      let destroy = container.querySelector('input.destroy')
      
      if (input && destroy) {
        destroy.value = input.value.length === 0
      }
    })
  }

  maskPhones() {
    IMask(this.homePhoneTarget, { mask: "(000) 000-0000" })
    IMask(this.mobilePhoneTarget, { mask: "(000) 000-0000" })
  }

  toggleFieldRequired(fieldTarget, isRequired) {
    let label = fieldTarget.closest('div').querySelector('label')
    label.classList.toggle('required', isRequired)
  }
}

class HomePhoneValidator {
  static REQUIRED_LENGTH = 10
  static ERRORS = {
    allZeros: "Home Phone number cannot be all zeros.",
    beginWithZero: "Phone numbers cannot begin with a 0. Please check the number you entered, remove any leading zeros, and resubmit.",
    invalidLength: `Phone must be ${HomePhoneValidator.REQUIRED_LENGTH} digits long.`
  }

  constructor(phoneTarget) {
    this.phoneTarget = phoneTarget
  }

  validate() {
    const phoneValue = this.phoneTarget.value.replace(/\D/g, '')

    if (phoneValue.length > 0) {
      if (/^0+$/.test(phoneValue)) {
        return HomePhoneValidator.ERRORS.allZeros
      } else if(/^0\d+/.test(phoneValue)) {
        return HomePhoneValidator.ERRORS.beginWithZero
      } else if (phoneValue.length < HomePhoneValidator.REQUIRED_LENGTH) {
        return HomePhoneValidator.ERRORS.invalidLength
      }
    }
    return null
  }
}

class PersonalEmailValidator {
  static ERRORS = {
    empty: "You must enter an email address to receive notices and updates by email."
  }

  constructor(emailTarget) {
    this.emailTarget = emailTarget
  }

  get hasValue() {
    return this.emailTarget.value.trim().length > 0
  }

  validate() {
    const emailValue = this.emailTarget.value.trim()

    if (emailValue.length === 0) {
      return PersonalEmailValidator.ERRORS.empty
    }
    return null
  }
}

class MobilePhoneValidator {
  static REQUIRED_LENGTH = 10
  static ERRORS = {
    allZeros: "Mobile Phone number cannot be all zeros.",
    beginWithZero: "Phone numbers cannot begin with a 0. Please check the number you entered, remove any leading zeros, and resubmit.",
    invalidLength: "You must enter a mobile phone number to receive notices and updates by text."
  }

  constructor(phoneTarget) {
    this.phoneTarget = phoneTarget
  }

  get hasValue() {
    return this.phoneTarget.value.length > 0
  }

  validate() {
    const phoneValue = this.phoneTarget.value.replace(/\D/g, '')

    if (/^0+$/.test(phoneValue)) {
      return MobilePhoneValidator.ERRORS.allZeros
    } else if(/^0\d+/.test(phoneValue)) {
      return MobilePhoneValidator.ERRORS.beginWithZero
    } else if (phoneValue.length < 1 || phoneValue.length < MobilePhoneValidator.REQUIRED_LENGTH) {
      return MobilePhoneValidator.ERRORS.invalidLength
    }
    return null
  }
}
