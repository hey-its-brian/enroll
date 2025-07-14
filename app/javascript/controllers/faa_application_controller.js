import { Controller } from "stimulus"
import axios from "axios";

export default class extends Controller {
  static targets = ["EditApplicantButton"]

  connect() {
    this.checkForParam()
  }

  checkForParam() {
    const urlParams = new URLSearchParams(window.location.search)
    const applicantParam = urlParams.get('applicant')

    if (applicantParam) {
      this.EditApplicantButtonTargets.forEach(button => {
        if (button.dataset.memberId === applicantParam) {
          button.click()
        }
      });
    }
  }

}
