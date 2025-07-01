import { Controller } from "stimulus"
export default class extends Controller {
  static targets = ["leavingApplicationButton"]

  connect() {
    this.modalWhenLeavingFormUnfinished()
  }

  modalWhenLeavingFormUnfinished() {
    const headerLinks = Array.from(document.querySelectorAll('header a, .progress-nav-container a')).filter(link => !link.closest('.progress-nav')).filter(link => !link.closest('.modal')).filter(link => !link.dataset.target).filter(link => link.href.length > 1)
    headerLinks.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault()
        this.showLeavingModal(link.href)
      })
    })
  }

  showLeavingModal(href) {
    const leavingModalTrigger = document.getElementById('leavingWarningModalTrigger')
    leavingModalTrigger.click()
    this.leavingApplicationButtonTarget.addEventListener('click', () => {
      window.location.href = href
    })
  }
}
