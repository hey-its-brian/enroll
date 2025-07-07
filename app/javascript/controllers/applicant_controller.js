import { Controller } from "stimulus"
import axios from 'axios'

export default class extends Controller {

  showSsn(event) {
    event.stopImmediatePropagation();
    let target = event.target;
    let applicantId = target.getAttribute('data-id');
    let applicationId = target.getAttribute('data-application-id');
    let url = target.getAttribute('data-url');

    if (!url) {
      url = `/financial_assistance/applications/${applicationId}/applicants/${applicantId}/show_ssn`;
    }

    if (applicantId == 'temp') {
      this.showSsnInput(applicantId);
    } else {
      axios({
        method: 'GET',
        url: url,
        headers: {
          'X-CSRF-Token': document.querySelector("meta[name=csrf-token]").content
        }
      }).then((response) => {
        if (response.data.status == 200) {
          let payload = response.data.payload;
          this.populateHtmlElement(applicantId, payload);
          this.noSsn(applicantId);
          this.showSsnInput(applicantId);
        } else {
          console.log("Unauthorized.");
        }
      }).catch(() => {
        console.log('Error retrieving info');
      })
    }
  }

  noSsn(applicantId) {
    let noSsnCheckbox = document.querySelector(`#personal_info .no-ssn-container input[type="checkbox"]`)
    if (noSsnCheckbox && noSsnCheckbox.checked) {
      let input = document.querySelector(`.ssn-input-${applicantId}`)
      if (input) {
        input.value = ''
      }
    }
  }

  populateHtmlElement(applicantId, payload) {
    let ssnInputElement = document.querySelector(`.ssn-input-${applicantId}`);

    if (ssnInputElement.tagName === 'INPUT') {
      ssnInputElement.value = payload;
      ssnInputElement.setAttribute('value', payload);
    } else {
      ssnInputElement.textContent = payload;
    }
  }

  depopulateHtmlElement(applicantId) {
    if (applicantId == 'temp') return;
    let ssnInputElement = document.querySelector(`.ssn-input-${applicantId}`);

    if (ssnInputElement.tagName === 'INPUT') {
      ssnInputElement.value = '';
      ssnInputElement.setAttribute('value', '');
    } else {
      ssnInputElement.textContent = '';
    }
  }

  hideSsn(event) {
    const target = event.target;
    const applicantId = target.getAttribute('data-id');

    document.querySelector(`.ssn-input-${applicantId}`).classList.add('hidden');
    $(`.ssn-input-${applicantId}`).parents('label').addClass('hidden');
    document.querySelector(`.ssn-facade-${applicantId}`).classList.remove('hidden');
    $(`.ssn-facade-${applicantId}`).parents('label').removeClass('hidden');
    document.querySelector(`.ssn-eye-on-${applicantId}`).classList.add('hidden');
    document.querySelector(`.ssn-eye-off-${applicantId}`).classList.remove('hidden');

    document.querySelector(`.ssn-eye-off-${applicantId}`).focus();
    this.depopulateHtmlElement(applicantId);
    const ssnInput = document.querySelector(`.ssn-input-${applicantId}`);
    if (ssnInput.getAttribute('data-admin-can-enable') !== null) {
      ssnInput.disabled = true;
    }
  }

  showSsnInput(applicantId) {
    document.querySelector(`.ssn-input-${applicantId}`).classList.remove('hidden');
    $(`.ssn-input-${applicantId}`).parents('label').removeClass('hidden');
    document.querySelector(`.ssn-facade-${applicantId}`).classList.add('hidden');
    $(`.ssn-facade-${applicantId}`).parents('label').addClass('hidden');
    document.querySelector(`.ssn-eye-on-${applicantId}`).classList.remove('hidden');
    document.querySelector(`.ssn-eye-off-${applicantId}`).classList.add('hidden');

    document.querySelector(`.ssn-eye-on-${applicantId}`).focus();
    const ssnInput = document.querySelector(`.ssn-input-${applicantId}`);
    if (ssnInput.getAttribute('data-admin-can-enable') !== null) {
      ssnInput.disabled = false;
    }
  }
}
