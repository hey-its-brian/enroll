// app/javascript/controllers/evidence_dropdown_controller.js
import { Controller } from "stimulus";

export default class extends Controller {

  connect() {
    this.updateDocumentDropdownVisibility()
  }

  updateDocumentDropdownVisibility() {
    const verificationSelect = document.querySelector('#verification_reason');
    const documentDropdown = document.getElementById('document-dropdown');
    const applicationReferenceSelect = document.querySelector('#application_reference');

    if (verificationSelect.value === 'Document in EnrollApp') {
      documentDropdown.classList.remove('hidden');
      applicationReferenceSelect.setAttribute('required', true);
    } else {
      documentDropdown.classList.add('hidden');
      applicationReferenceSelect.removeAttribute('required');
    }
  }
}
