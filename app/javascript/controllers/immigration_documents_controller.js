import { Controller } from "stimulus"
import sanitizeHtml from 'sanitize-html';
export default class extends Controller {
  static targets = [
    "documentSelect",      // The select dropdown
    "documentFields",      // Container for the dynamic fields
    "template",            // Templates for different document types
    "ImmigrationDocumentsContainer",
    "NewNaturalizedCitizenStatusTemplate",
    "immigrationDocStatus"
  ]

  connect() {
    this.hideDocumentFields()
    this.initializeImmigrationDocuments()
  }

  toggleDocumentSelect(event) {
    const isCheckbox = event.target.type === 'checkbox'
    const showSelect = isCheckbox ?
      event.target.checked : // For checkbox
      (event.target.name.includes('naturalized_citizen') && event.target.value === 'true') || // For radio buttons
      (event.target.name.includes('eligible_immigration_status') && event.target.value === 'true')

    if (showSelect) {
      // Find the template and add its content after the checkbox/radio container
      const template = document.querySelector('[data-target="immigration-documents.NewImmigrationStatusTemplate"]')
      if (template && this.ImmigrationDocumentsContainerTarget) {
        // For checkbox, append after the checkbox div
        if (isCheckbox) {
          const checkboxContainer = event.target.closest('#immigration-checkbox')
          checkboxContainer.insertAdjacentHTML('afterend', this.sanitize(template.innerHTML))
        } else {
          // For radio buttons, replace the container content
          this.ImmigrationDocumentsContainerTarget.innerHTML = this.sanitize(template.innerHTML)
        }
        this.ImmigrationDocumentsContainerTarget.classList.remove('hidden')
      }
    } else {
      if (this.ImmigrationDocumentsContainerTarget) {
        if (isCheckbox) {
          // For checkbox, remove only the generated content after the checkbox
          const generatedFields = this.ImmigrationDocumentsContainerTarget.querySelector('.generated_fields')
          if (generatedFields) {
            generatedFields.remove()
          }
        } else {
          // For radio buttons, clear the entire container
          this.ImmigrationDocumentsContainerTarget.innerHTML = ''
        }
        this.ImmigrationDocumentsContainerTarget.innerHTML = ''
        this.ImmigrationDocumentsContainerTarget.classList.add('hidden')
      }
    }
  }

  toggleNaturalizedCitizenDocumentSelect(event) {
    const isCheckbox = event.target.type === 'checkbox'
    const showSelect = isCheckbox ?
      event.target.checked : // For checkbox
      (event.target.name.includes('naturalized_citizen') && event.target.value === 'true') || // For radio buttons
      (event.target.name.includes('eligible_immigration_status') && event.target.value === 'true')
    if (showSelect) {
      // Find the template and add its content after the checkbox/radio container
      const template = document.querySelector('[data-target="immigration-documents.NewNaturalizedCitizenStatusTemplate"]')
      if (template && this.ImmigrationDocumentsContainerTarget) {
        // For checkbox, append after the checkbox div
        if (isCheckbox) {
          const checkboxContainer = event.target.closest('#immigration-checkbox')
          checkboxContainer.insertAdjacentHTML('afterend', this.sanitize(template.innerHTML))
        } else {
          // For radio buttons, replace the container content
          this.ImmigrationDocumentsContainerTarget.innerHTML = this.sanitize(template.innerHTML)
        }
        this.ImmigrationDocumentsContainerTarget.classList.remove('hidden')
        
      }
    } else {
      if (this.ImmigrationDocumentsContainerTarget) {
        this.ImmigrationDocumentsContainerTarget.innerHTML = ''
        this.ImmigrationDocumentsContainerTarget.classList.add('hidden')
      }
    }
  }

  toggleUsCitizen(event) {
    const isUsCitizen = event.target.value === 'true';

    this.ImmigrationDocumentsContainerTarget.innerHTML = ''
  }

  handleDocumentChange(event) {
    const selectedDoc = event.target.value
    if (!selectedDoc) {
      this.hideDocumentFields()
      return
    }

    // Convert the selected value to match template ID format
    const templateId = `${selectedDoc.toLowerCase()
      .replace(/[\s()-]/g, '_')
      .replace(/\//g, '_')
      .replace(/[.']/g, '')}_template`
    const template = document.querySelector(`#${templateId}`)
    // clear the document fields
    this.documentFieldsTarget.innerHTML = "";
    if (template) {
      this.documentFieldsTarget.innerHTML = this.sanitize(template.innerHTML)

      if (this.hasImmigrationDocStatusTarget) {
        var docStatusTemplate = this.immigrationDocStatusTarget
        let container = document.createElement("div");
        container.classList.add("mb-3")
        container.innerHTML = this.sanitize(docStatusTemplate.innerHTML)
        this.documentFieldsTarget.append(container)
      }

      this.documentFieldsTarget.classList.remove('hidden')

      // Add required validation for specific fields based on document type
      const docFields = this.documentFieldsTarget.querySelectorAll('.doc_fields')
      docFields.forEach(field => {
        if (selectedDoc === 'Naturalization Certificate' || selectedDoc === 'Certificate of Citizenship') {
          if (field.getAttribute('placeholder') === 'Certificate Number' ||
              field.getAttribute('placeholder') === 'Naturalization Number') {
            field.setAttribute('required', 'required')
            field.classList.add('required')
          }
        } else {
          // For all other document types
          if (field.getAttribute('placeholder') === 'Alien Number') {
            field.setAttribute('required', 'required')
            field.classList.add('required')
          }

          if (selectedDoc === 'I-766 (Employment Authorization Card)' &&
              field.getAttribute('placeholder') === 'Card Number') {
            field.setAttribute('required', 'required')
            field.classList.add('required')
          }
        }

        // Document Description is required for "Other" document types
        if ((selectedDoc === 'Other (With Alien Number)' || selectedDoc === 'Other (With I-94 Number)') &&
            field.getAttribute('placeholder') === 'Document Description') {
          field.setAttribute('required', 'required')
          field.classList.add('required')
        }
      })
    } else {
      console.error(`No template found for document type`)
    }
  }

  hideDocumentFields() {
    if (this.documentFieldsTargets.length > 0) {
      this.documentFieldsTarget.classList.add('hidden')
      this.documentFieldsTarget.innerHTML = ''
    }
  }

  initializeImmigrationDocuments() {
    this.documentSelectTargets.forEach(select => {
      if (select.value) {
        // Manually trigger the change event
        const event = new Event('change')
        select.dispatchEvent(event)
        this.ImmigrationDocumentsContainerTarget.classList.remove('hidden')
      }
    })
  }

  sanitize(dirty) {
    const allowedTags = sanitizeHtml.defaults.allowedTags.concat([ 'input', 'label', 'select', 'option', 'template', 'span', 'small', 'fieldset', 'legend' ])

    return sanitizeHtml(dirty, {
      allowedTags: allowedTags,
      allowedAttributes: {
        'input': [ 'pattern','type', 'name', 'id', 'value', 'placeholder', 'required', 'checked', 'disabled', 'readonly', 'class', 'style', 'data-*' ],
        'label': [ 'for', 'class' ],
        'select': [ 'name', 'id', 'class', 'style', 'data-*' ],
        'option': [ 'value', 'selected' ],
        'div': [ 'data-*', 'class', 'id' ],
        'i': [ 'class' ],
        'h4': [ 'class' ],
        'template': [ 'id', 'data-*' ],
        'fieldset': [ 'id', 'class' ],
        'legend': [ 'class' ],
        'span': [ 'class' ],
        'small': [ 'class' ]
      }
    });
  }
}