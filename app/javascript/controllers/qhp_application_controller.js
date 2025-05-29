import { Controller } from "stimulus"
import axios from 'axios'

export default class extends Controller {
  static targets = ["NewApplicant", "EditApplicantForm", "ApplicantRow", "EditApplicantButton", "AddApplicantButton"]
  static values = {
    NewApplicantUrl: String,
    url: String
  }

  connect() {
    this.checkForParam()
  }

  checkForParam() {
    const urlParams = new URLSearchParams(window.location.search)
    const applicantParam = urlParams.get('applicant')

    if (applicantParam) {
      if (applicantParam === 'new') {
        this.addApplicant();
      } else {
        this.EditApplicantButtonTargets.forEach(button => {
          if (button.dataset.memberId === applicantParam) {
            button.click()
          }
        });
      }
    }
  }

  async addApplicant(event) {
    if (event) {
      event.preventDefault()
    }
    const button = this.AddApplicantButtonTarget

    this.disableInteractions()

    try {

      const response = await axios.get(button.dataset.qhpApplicationUrlValue, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const template = document.createElement('template')
      template.innerHTML = response.data.trim()

      this.NewApplicantTarget.insertAdjacentElement('beforeend', template.content.firstElementChild)

      const newForm = this.NewApplicantTarget.firstElementChild
      newForm.classList.remove('hidden')
      newForm.scrollIntoView({ behavior: 'smooth', block: 'start' })

    } catch (error) {
      console.error("Error fetching applicant form")
    }
  }

  disableInteractions() {
    // Disable all action buttons
    this.element.querySelectorAll('button, a')
      .forEach(button => {
        button.disabled = true
        button.classList.add('disabled-for-editing')
      })
  }

  enableInteractions() {
    // Re-enable all action buttons
    this.element.querySelectorAll('.disabled-for-editing')
      .forEach(button => {
        button.disabled = false
        button.classList.remove('disabled-for-editing')
      })
  }

  async editApplicant(event) {
    // This function will be built to handle applicant editing
    // It will likely make an AJAX call to fetch the edit form
    // and update the appropriate section of the page
    // append it to the form
    // disable other buttons
    // scroll to the edit form
    event.preventDefault()
    const button = event.currentTarget
    const memberId = button.dataset.memberId
    const editApplicantForm = this.EditApplicantFormTargets.find(form => form.dataset.memberId === memberId)
    const applicantRow = this.ApplicantRowTargets.find(row => row.dataset.memberId === memberId)

    this.disableInteractions()

    try {

      const response = await axios.get(button.dataset.qhpApplicationUrlValue, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const template = document.createElement('template')
      template.innerHTML = response.data.trim()

      editApplicantForm.insertAdjacentElement('beforeend', template.content.firstElementChild)

      const newForm = editApplicantForm.firstElementChild
      newForm.classList.remove('hidden')

      if (applicantRow) {
        applicantRow.classList.add('hide');
      }

      newForm.scrollIntoView({ behavior: 'smooth', block: 'start' })

    } catch (error) {
      console.error("Error fetching applicant form")
      this.enableInteractions()
    }

  }

  cancelApplicantForm(event) {
    event.preventDefault()
    const button = event.currentTarget

    // Find the closest form element and remove it
    const form = event.target.closest('form')
    if (form) {
      form.remove()
    }

    if (event.currentTarget.dataset.memberId) {
      const memberId = button.dataset.memberId
      const applicantRow = this.ApplicantRowTargets.find(row => row.dataset.memberId === memberId)
      if (applicantRow) {
        applicantRow.classList.remove('hide');
      }
    }

    // Re-enable all action buttons
    this.enableInteractions()

    // Scroll to the top of the controller element
    this.element.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

}
