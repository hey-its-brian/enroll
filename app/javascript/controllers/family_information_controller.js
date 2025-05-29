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
    "AddressFields",
    "NewAddressFields",
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
    this.initializeDependentAddress()
    this.initializeCitizenshipFields()
    this.maskSSN()
    this.initializeRequiredFields()
  }

  initializeTribalFields() {
    const indianTribeMemberYes = this.element.querySelector('#indian_tribe_member_yes')
    if (indianTribeMemberYes?.checked) {
      this.showTribalFields()
      this.setTribalFieldsRequired(true)
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
    this.TribalContainerTarget.classList.remove('hide')
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
    const otherTribeSelected = this.element.querySelector('input#person_tribe_codes_ot')?.checked

    if (isFeaturedTribesEnabled && selectedState === enrollStateAbbr) {
      this.FeaturedTribeContainerTarget.classList.remove('hide')
      if (otherTribeSelected) {
        this.TribalNameContainerTarget.classList.remove('hide')
        this.setTribalNameRequired(true)
      } else {
        this.TribalNameTarget.value = ''
        this.TribalNameContainerTarget.classList.add('hide')
        this.setTribalNameRequired(false)
      }
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
    const isTribalDetailsEnabled = this.element.querySelector('#is_indian_alaskan_tribe_details_enabled').value === 'true'

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

  toggleOtherTribeName(event) {
    if (event.target.checked && event.target.id === 'person_tribe_codes_ot') {
      this.TribalNameContainerTarget.classList.remove('hide')
      this.setTribalNameRequired(true)
    } else if (event.target.id === 'person_tribe_codes_ot') {
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

  initializeDependentAddress() {
    const addressSamePrimary = this.element.querySelector('input[name="applicant[address_same_as_primary]"]')
    if (addressSamePrimary) {
      // Check initial state and hide/show fields accordingly
      if (addressSamePrimary.checked) {
        this.AddressButtonsTarget.classList.add('hide')
      } else {
        this.AddressButtonsTarget.classList.remove('hide')
      }
    }
  }

  toggleDependentAddress(event) {
    if (this.hasAddressFieldsTarget) {
      if (event.target.checked) {
        this.AddressFieldsTarget.innerHTML = ''
        this.AddressButtonsTarget.classList.add('hide')
      } else {
        this.AddressFieldsTarget.innerHTML = ''
        this.AddressFieldsTarget.insertAdjacentHTML('beforeend', this.sanitize(this.NewHomeAddressFieldsTemplateTarget.innerHTML))
        this.AddressButtonsTarget.classList.remove('hide')
      }
    } else {
      console.log('No AddressFields target found')
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
    this.NewAddressFieldsTarget.innerHTML = ''
    this.NewAddressFieldsTarget.insertAdjacentHTML('beforeend', this.sanitize(this.NewMailingAddressFieldsTemplateTarget.innerHTML))
    document.getElementById('add_mail_address').classList.add('d-none')
    document.getElementById('remove_mail_address').classList.remove('d-none')
  }

  removeMailingAddress(event) {
    event.preventDefault()
    // Clear any content in the NewAddressFields target
    if (this.NewAddressFieldsTarget.firstChild) {
      this.NewAddressFieldsTarget.removeChild(this.NewAddressFieldsTarget.firstChild)
    }
    this.NewAddressFieldsTarget.innerHTML = ''

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

  sanitize(dirty) {
    const allowedTags = sanitizeHtml.defaults.allowedTags.concat([ 'input', 'label', 'select', 'option' ])

    return sanitizeHtml(dirty, {
      allowedTags: allowedTags,
      allowedAttributes: {
        'input': [ 'type', 'name', 'id', 'value', 'placeholder', 'required', 'checked', 'disabled', 'readonly', 'class', 'style', 'data-*' ],
        'label': [ 'for' ],
        'select': [ 'name', 'id', 'class', 'style' ],
        'option': [ 'value', 'selected' ],
        'div': [ 'data-*', 'class', 'id' ],
        'i': [ 'class' ],
        'h4': [ 'class' ],
        'template': [ 'id', 'data-*' ]
      }
    });
  }
}
