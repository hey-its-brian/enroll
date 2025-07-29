import { Controller } from "stimulus"
import IMask from "imask"
import sanitizeHtml from "sanitize-html"
export default class extends Controller {
  static targets = [
    "TribalContainer",
    "FeaturedTribeContainer",
    "TribalNameContainer",
    "TribalName",
    "TribalState",
    "ConsumerFields",
    "SsnMessage",
    "SsnInput",
    "NoSsnCheckbox",
    "RelationshipFields",
    "DependentAddress",
    "NaturalizedCitizenContainer",
    "ImmigrationStatusContainer",
    "AddressContainer",
    "addressFields",
    "newAddressFields",
    "NewMailingAddressFieldsTemplate",
    "NewHomeAddressFieldsTemplate",
    "EligibleImmigrationStatusContainer",
    "UsCitizenshipFields",
    "IncarceratedFields",
    "IndianTribeMember",
    "AddressButtons"
  ]

  connect() {
    this.initializeTribalFields()
    this.initializeApplyingCoverage()
    this.initializeCitizenshipFields()
    this.maskSSN()
    this.maskZip()
    this.initializeRequiredFields()
    // using existing init_glossary function for now to be consistent
    init_glossary();
  }

  initializeTribalFields() {
    const indianTribeMemberYes = document.querySelector('#indian_tribe_member_yes')
    if (indianTribeMemberYes?.checked) {
      this.showTribalFields()
      this.setTribalFieldsRequired(true)
    } else {
      if (this.hasTribalNameTarget) {
        this.setTribalNameRequired(false)
      }
      this.setTribalFieldsRequired(false)
    }
  }

  toggleTribalFields(event) {
    const isYes = event.target.value === 'true'
    if (isYes) {
      this.showTribalFields()
      this.setTribalFieldsRequired(true)
    } else {
      this.hideTribalFields()
      this.clearTribalFields()
      this.setTribalFieldsRequired(false)
    }
  }

  showTribalFields() {
    this.TribalContainerTarget.classList.remove('hide');
    const enrollStateAbbr = this.element.querySelector('#enroll_state_abbr').value
    const isFeaturedTribesEnabled = this.element.querySelector('#is_featured_tribes_selection_enabled').value === 'true'
    const selectedState = this.TribalStateTarget?.value
    if (isFeaturedTribesEnabled && selectedState === enrollStateAbbr) {
      this.TribalNameContainerTarget.classList.remove('hide')
      this.toggleOtherTribeName()
    } else {
      this.TribalNameContainerTarget.classList.remove('hide')
      this.setTribalNameRequired(true)
    }
  }

  hideTribalFields() {
    this.TribalContainerTarget.classList.add('hide')
  }

  clearTribalFields() {
    if (this.hasTribalStateTarget) {
      this.TribalStateTarget.value = ''
    }

    if (this.hasTribalNameTarget) {
      this.TribalNameTarget.value = ''
    }

    const tribeCheckboxes = this.element.querySelectorAll('.tribe_codes:checked')
    tribeCheckboxes.forEach(checkbox => checkbox.checked = false)
  }

  handleTribalStateChange(event) {
    const enrollStateAbbr = this.element.querySelector('#enroll_state_abbr').value
    const isFeaturedTribesEnabled = this.element.querySelector('#is_featured_tribes_selection_enabled').value === 'true'
    const isTribalDetailsEnabled = this.element.querySelector('#is_indian_alaskan_tribe_details_enabled').value === 'true'
    if (!isTribalDetailsEnabled) return

    const selectedState = event.target.value
    if (isFeaturedTribesEnabled && selectedState === enrollStateAbbr) {
      this.FeaturedTribeContainerTarget.classList.remove('hide')
      this.toggleOtherTribeName()
    } else {
      const tribeCheckboxes = this.element.querySelectorAll('.tribe_codes:checked')
      tribeCheckboxes.forEach(checkbox => checkbox.checked = false)

      this.TribalNameContainerTarget.classList.remove('hide')
      this.FeaturedTribeContainerTarget.classList.add('hide')
      this.setTribalNameRequired(true)
    }

    // Hide any existing alerts
    const tribalStateAlert = document.getElementById('tribal-state-alert')
    const tribalNameAlert = document.getElementById('tribal-name-alert')
    if (tribalStateAlert) tribalStateAlert.classList.add('hide')
    if (tribalNameAlert) tribalNameAlert.classList.add('hide')
  }

  setTribalFieldsRequired(required) {
    const input = this.element.querySelector('#is_indian_alaskan_tribe_details_enabled')
    if (!input) return
    const isTribalDetailsEnabled = input.value === 'true'
    if (isTribalDetailsEnabled) {
      // Set tribal state as required
      if (this.hasTribalStateTarget) {
        if (required) {
          this.TribalStateTarget.setAttribute('required', 'required')
        } else {
          this.TribalStateTarget.removeAttribute('required')
        }
      }

      // Handle tribal name requirement based on state selection and featured tribes
      const selectedState = this.TribalStateTarget?.value
      const enrollStateAbbr = this.element.querySelector('#enroll_state_abbr').value
      const isFeaturedTribesEnabled = this.element.querySelector('#is_featured_tribes_selection_enabled').value === 'true'

      if (isFeaturedTribesEnabled && selectedState === enrollStateAbbr) {
        // For featured tribes, only require tribal name if "Other" is selected
        const otherTribeSelected = this.element.querySelector('input#person_tribe_codes_ot')?.checked
        this.setTribalNameRequired(required && otherTribeSelected)
      } else {
        // Always require tribal name for non-featured tribe states
        this.setTribalNameRequired(required)
      }
    } else {
      // Handle tribal ID requirement for non-tribal-details case
      const tribalId = this.element.querySelector('#tribal-id')
      if (tribalId) {
        if (required) {
          tribalId.setAttribute('required', 'required')
        } else {
          tribalId.removeAttribute('required')
        }
      }
    }
  }

  setTribalNameRequired(required) {
    if (this.hasTribalNameTarget) {
      if (required) {
        this.TribalNameTarget.setAttribute('required', 'required')
      } else {
        this.TribalNameTarget.removeAttribute('required')
      }
    }
  }

  toggleOtherTribeName() {
    let input = document.querySelector('input#applicant_demographics_attributes_tribe_codes_ot')
    let tribalCodes = document.querySelectorAll('.tribe_codes')
    if (input.checked) {
      this.TribalNameContainerTarget.classList.remove('hide')
      this.setTribalNameRequired(true)
      tribalCodes.forEach(code => {
        code.classList.remove("indicate-invalid")
        code.setCustomValidity("")
        code.reportValidity()
      })
    } else {
      this.TribalNameContainerTarget.classList.add('hide')
      this.setTribalNameRequired(false)
      this.TribalNameTarget.value = ''
    }

    // Check if any tribe is selected when featured tribes are enabled
    const isFeaturedTribesEnabled = this.element.querySelector('#is_featured_tribes_selection_enabled').value === 'true'
    if (isFeaturedTribesEnabled) {
      const anyTribeSelected = Array.from(this.element.querySelectorAll('.tribe_codes'))
        .some(checkbox => checkbox.checked)

      if (!anyTribeSelected) {
        // Show validation message if no tribe is selected
        const tribalNameAlert = document.getElementById('tribal-name-alert')
        if (tribalNameAlert) tribalNameAlert.classList.remove('hide')
      } else {
        tribalCodes.forEach(code => {
          code.classList.remove("indicate-invalid")
          code.setCustomValidity("")
          code.reportValidity()
        })
      }
    }
  }

  initializeApplyingCoverage() {
    const applyingCoverageRadios = this.element.querySelectorAll('input[name="applicant[is_applying_coverage]"]')
    if (applyingCoverageRadios.length > 0) {
      this.addNoSsnListener()
      this.addSsnInputListener()

      // Check initial state
      const notApplyingForCoverage = Array.from(applyingCoverageRadios)
        .find(radio => !radio.checked && radio.value === 'true')

      if (notApplyingForCoverage) {
        this.hideConsumerFields()
        this.checkSsnMessage()
      }
    }
  }

  toggleApplyingCoverage(event) {
    const applyingForCoverage = event.target.value === 'true'
    if (!applyingForCoverage) {
      this.hideConsumerFields()
      this.checkSsnMessage()
      this.setUsCitizenshipRequired(false)
      this.setNaturalizedCitizenRequired(false)
      this.setIncarceratedRequired(false)
    } else {
      this.showConsumerFields()
      this.hideSsnMessage()
      this.setUsCitizenshipRequired(true)
      this.setIncarceratedRequired(true)

      const isUsCitizen = this.element.querySelector('#us_citizen_true')?.checked
      if (isUsCitizen) {
        this.setNaturalizedCitizenRequired(true)
      }
    }
  }

  hideConsumerFields() {
    if (this.hasConsumerFieldsTarget) {
      this.ConsumerFieldsTargets.forEach(field => {
        field.classList.add('hide')
      })
    }
  }

  showConsumerFields() {
    if (this.hasConsumerFieldsTarget) {
      this.ConsumerFieldsTargets.forEach(field => {
        field.classList.remove('hide')
      })
    }
  }

  showSsnMessage() {
    if (this.hasSsnMessageTarget) {
      this.SsnMessageTarget.classList.remove('hide')
    }
  }

  hideSsnMessage() {
    if (this.hasSsnMessageTarget) {
      this.SsnMessageTarget.classList.add('hide')
    }
  }

  checkSsnMessage() {
    if (this.hasSsnInputTarget && this.hasNoSsnCheckboxTarget) {
      if (this.SsnInputTarget.value === '' && !this.NoSsnCheckboxTarget.checked) {
        this.showSsnMessage()
      }
    }
  }

  handleNoSsnChange(event) {
    if (event.target.checked) {
      this.hideSsnMessage()
    } else {
      this.checkSsnMessage()
    }
  }

  handleSsnInput(event) {
    if (event.target.value !== '') {
      this.hideSsnMessage()
    } else {
      this.checkSsnMessage()
    }
  }

  addNoSsnListener() {
    if (this.hasNoSsnCheckboxTarget) {
      this.NoSsnCheckboxTarget.addEventListener('change', this.handleNoSsnChange.bind(this))
    }
  }

  addSsnInputListener() {
    if (this.hasSsnInputTarget) {
      this.SsnInputTarget.addEventListener('keyup', this.handleSsnInput.bind(this))
    }
  }

  toggleDependentAddress(event) {
    if (this.hasAddressFieldsTarget) {
      if (event.target.checked) {
        this.addressFieldsTarget.innerHTML = ''
        this.AddressButtonsTarget.classList.add('hide')
      } else {
        this.addressFieldsTarget.innerHTML = ''
        this.addressFieldsTarget.insertAdjacentHTML('beforeend', this.sanitize(this.NewHomeAddressFieldsTemplateTarget.innerHTML))
        this.AddressButtonsTarget.classList.remove('hide')
        this.maskZip()
      }
    }
  }

  hideAddressFields(formElement) {
    const addressFields = formElement.querySelector('[data-target="family-information.AddressFields"]')
    if (addressFields) {
      addressFields.classList.add('hide')
    }
  }

  showAddressFields(formElement) {
    const addressFields = formElement.querySelector('[data-target="family-information.AddressFields"]')
    if (addressFields) {
      addressFields.classList.remove('hide')
      this.maskZip()
    }
  }

  toggleCitizenshipFields(event) {
    const isUsCitizen = event.target.value === 'true';

    if (this.hasNaturalizedCitizenContainerTarget && this.hasEligibleImmigrationStatusContainerTarget) {
      if (isUsCitizen) {
        // Show naturalized citizen section and hide immigration status
        this.NaturalizedCitizenContainerTarget.classList.remove('hidden')
        this.EligibleImmigrationStatusContainerTarget.classList.add('hidden')

        // Make naturalized citizen radios required if applying for coverage
        const isApplyingCoverage = this.element.querySelector('#applicant_is_applying_coverage_true')?.checked
        if (isApplyingCoverage) {
          this.setNaturalizedCitizenRequired(true)
        }
      } else {
        // Hide naturalized citizen section and show immigration status
        this.NaturalizedCitizenContainerTarget.classList.add('hidden')
        this.EligibleImmigrationStatusContainerTarget.classList.remove('hidden')

        // Remove required from naturalized citizen radios
        this.setNaturalizedCitizenRequired(false)

        // Clear the naturalized citizen selection
        const naturalizedRadios = this.NaturalizedCitizenContainerTarget.querySelectorAll('input[type="radio"]')
        naturalizedRadios.forEach(radio => radio.checked = false)
      }
    }
  }

  addMailingAddress(event) {
    event.preventDefault()
    this.newAddressFieldsTarget.innerHTML = ''
    this.newAddressFieldsTarget.insertAdjacentHTML('beforeend', this.sanitize(this.NewMailingAddressFieldsTemplateTarget.innerHTML))
    document.getElementById('add_mail_address').classList.add('d-none')
    document.getElementById('remove_mail_address').classList.remove('d-none')
  }

  removeMailingAddress(event) {
    event.preventDefault()
    // Clear any content in the NewAddressFields target
    if (this.newAddressFieldsTarget.firstChild) {
      this.newAddressFieldsTarget.removeChild(this.newAddressFieldsTarget.firstChild)
    }
    this.newAddressFieldsTarget.innerHTML = ''

    // Toggle button visibility
    document.getElementById('remove_mail_address').classList.add('d-none')
    document.getElementById('add_mail_address').classList.remove('d-none')
  }

  maskSSN() {
    const ssnFields = this.element.querySelectorAll('.mask-ssn')
    ssnFields.forEach(field => {
      IMask(field, { mask: "000-00-0000" });
    })
  }

  maskZip() {
    const zipFields = this.element.querySelectorAll('.zip')
    zipFields.forEach(field => {
      IMask(field, { mask: "00000" });
    })
  }

  initializeCitizenshipFields() {
    if (this.hasNaturalizedCitizenContainerTarget && this.hasEligibleImmigrationStatusContainerTarget) {
      const usCitizenTrue = this.element.querySelector('#us_citizen_true')
      const usCitizenFalse = this.element.querySelector('#us_citizen_false')

      // Initially hide both sections until US citizen is answered
      if (!usCitizenTrue?.checked && !usCitizenFalse?.checked) {
        this.NaturalizedCitizenContainerTarget.classList.add('hidden')
        this.EligibleImmigrationStatusContainerTarget.classList.add('hidden')
        return
      }

      // Handle case where US citizen is already selected
      if (usCitizenTrue?.checked) {
        this.NaturalizedCitizenContainerTarget.classList.remove('hidden')
        this.EligibleImmigrationStatusContainerTarget.classList.add('hidden')

        // Make naturalized citizen radios required if applying for coverage
        const isApplyingCoverage = this.element.querySelector('#applicant_is_applying_coverage_true')?.checked
        if (isApplyingCoverage) {
          this.setNaturalizedCitizenRequired(true)
        }
      }
      // Handle case where Not US citizen is already selected
      else if (usCitizenFalse?.checked) {
        this.NaturalizedCitizenContainerTarget.classList.add('hidden')
        this.EligibleImmigrationStatusContainerTarget.classList.remove('hidden')
      }
    }
  }

  initializeRequiredFields() {
    const applyingCoverageRadio = this.element.querySelector('#applicant_is_applying_coverage_true')
    const isApplyingCoverage = applyingCoverageRadio?.checked
    const isUsCitizen = this.element.querySelector('#us_citizen_true')?.checked



    if (isApplyingCoverage) {
      this.setUsCitizenshipRequired(true)
      this.setIncarceratedRequired(true)

      if (isUsCitizen) {
        this.setNaturalizedCitizenRequired(true)
      }
    } else {
      this.setUsCitizenshipRequired(false)
      this.setNaturalizedCitizenRequired(false)
      this.setIncarceratedRequired(false)
    }
  }

  setUsCitizenshipRequired(required) {
    if (this.hasUsCitizenshipFieldsTarget) {
      const usCitizenRadios = this.UsCitizenshipFieldsTarget.querySelectorAll('input[type="radio"]')
      usCitizenRadios.forEach(radio => {
        if (required) {
          radio.setAttribute('required', 'required')
        } else {
          radio.removeAttribute('required')
        }
      })
    }
  }

  setNaturalizedCitizenRequired(required) {
    if (this.hasNaturalizedCitizenContainerTarget) {
      const naturalizedRadios = this.NaturalizedCitizenContainerTarget.querySelectorAll('input[type="radio"]')
      naturalizedRadios.forEach(radio => {
        if (required) {
          radio.setAttribute('required', 'required')
        } else {
          radio.removeAttribute('required')
        }
      })
    }
  }

  setIncarceratedRequired(required) {
    if (this.hasIncarceratedFieldsTarget) {
      const incarceratedRadios = this.IncarceratedFieldsTarget.querySelectorAll('input[type="radio"]')
      incarceratedRadios.forEach(radio => {
        if (required) {
          radio.setAttribute('required', 'required')
        } else {
          radio.removeAttribute('required')
        }
      })
    }
  }

  toggleNoSsn(event) {
    if (event.target.checked) {
      let input = this.SsnInputTarget.querySelector('input')
      let eye = this.SsnInputTarget.querySelector('img[class^=ssn-eye-off-]')
      if (eye) {
        eye.click()
      }
      input.value = ''
    }
  }

  ssnValueChanged(event) {
    if (event.target.value !== '') {
      this.NoSsnCheckboxTarget.checked = false
    }
  }

  checkValidations(event) {
    event.preventDefault()
    const form = this.element.querySelector('form')
    let ssnValid = this.checkSsnValidation()
    let tribalStateValid = this.checkTribalStateValidation()

    let valid = ssnValid && tribalStateValid && form.checkValidity()

    if (valid) {
      form.submit()
    } else {
      form.reportValidity()
    }
  }

  checkSsnValidation() {
    if (this.hasNoSsnCheckboxTarget && this.hasSsnInputTarget) {
      let input = this.SsnInputTarget.querySelector('input')
      if (this.NoSsnCheckboxTarget.checked && input.value.length > 1) {
        input.setCustomValidity("Cannot provide an SSN and claim you don't have a SSN")
        input.reportValidity()
        return false
      } else if (!this.NoSsnCheckboxTarget.checked && input.value.length == 0) {
        input.setCustomValidity("One of the following is required: SSN, or check the box that you don't have an SSN")
        input.reportValidity()
        return false
      } else {
        input.setCustomValidity("")
        input.reportValidity()
        return true
      }
    } else {
      return true
    }
  }

  checkTribalStateValidation() {
    const indianTribeMemberYes = document.querySelector('#indian_tribe_member_yes')
    const tribalState = this.TribalStateTarget
    const tribalName = this.TribalNameTarget
    if (indianTribeMemberYes?.checked) {
      if (this.hasTribalStateTarget && tribalState.value == "") {
        tribalState.setCustomValidity("Tribal state is required when native american / alaska native is selected")
        tribalState.reportValidity()
        return false
      } else {
        tribalState.setCustomValidity("")
        tribalState.reportValidity()
        return this.checkTribalNameOrCodeValidation()
      }
    } else {
      tribalState.setCustomValidity("")
      tribalState.reportValidity()
      if (tribalName) {
        tribalName.setCustomValidity("")
        tribalName.reportValidity()
      }
      return true
    }
  }

  checkTribalNameOrCodeValidation() {
    const enrollStateAbbr = this.element.querySelector('#enroll_state_abbr').value
    const isFeaturedTribesEnabled = this.element.querySelector('#is_featured_tribes_selection_enabled').value === 'true'
    const selectedState = this.TribalStateTarget?.value
    if (isFeaturedTribesEnabled && selectedState === enrollStateAbbr) {
      return this.checkTribalCodeValidation()
    } else {
      return this.checkTribalNameValidation()
    }
  }

  checkTribalNameValidation() {
    if (this.hasTribalNameTarget) {
      const tribalName = this.TribalNameTarget.value
      if (tribalName == "") {
        this.TribalNameTarget.setCustomValidity("Tribal name is required when native american / alaska native is selected")
        this.TribalNameTarget.reportValidity()
        return false
      } else {
        this.TribalNameTarget.setCustomValidity("")
        this.TribalNameTarget.reportValidity()
        return true
      }
    } else {
      return true
    }
  }
  checkTribalCodeValidation() {
    if (this.hasFeaturedTribeContainerTarget) {
      const featuredTribesContainer = this.FeaturedTribeContainerTarget
      let tribalCodes = featuredTribesContainer.querySelectorAll('.tribe_codes')
      let tribalIds = [...featuredTribesContainer.querySelectorAll('.tribe_codes:checked')].map(option => option.value)
      if (tribalIds.length == 0) {
        tribalCodes.forEach(code => {
          code.classList.add("indicate-invalid")
          if (code.value == "OT") {
            code.setCustomValidity("Tribal name is required when native american / alaska native is selected")
            code.reportValidity()
          }
        })
        return false
      } else if (tribalIds.includes("OT") && this.hasTribalNameTarget && this.TribalNameTarget.value == "") {
        this.TribalNameTarget.setCustomValidity("Tribal name is required when native american / alaska native is selected")
        this.TribalNameTarget.reportValidity()
        return false
      } else {
        tribalCodes.forEach(code => {
          code.classList.remove("indicate-invalid")
          code.setCustomValidity("")
          code.reportValidity()
        })
        if (this.hasTribalNameTarget) {
          this.TribalNameTarget.setCustomValidity("")
          this.TribalNameTarget.reportValidity()
        }
        featuredTribesContainer.setCustomValidity("")
        featuredTribesContainer.reportValidity()
        return true
      }
    } else {
      return true
    }
  }

  sanitize(dirty) {
    const allowedTags = sanitizeHtml.defaults.allowedTags.concat([ 'input', 'label', 'select', 'option' ])

    return sanitizeHtml(dirty, {
      allowedTags: allowedTags,
      allowedAttributes: {
        'input': [ 'type', 'name', 'id', 'value', 'placeholder', 'required', 'checked', 'disabled', 'readonly', 'class', 'style', 'data-*', 'min', 'max' ],
        'label': [ 'for' ],
        'select': [ 'name', 'id', 'class', 'style', 'data-*' ],
        'option': [ 'value', 'selected' ],
        'div': [ 'data-*', 'class', 'id' ],
        'i': [ 'class' ],
        'h4': [ 'class' ],
        'template': [ 'id', 'data-*' ]
      }
    });
  }
}
