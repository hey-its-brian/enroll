import { Controller } from "stimulus"
export default class extends Controller {
  static targets = ["leavingApplicationButton"]

  connect() {
    this.modalWhenLeavingFormUnfinished()
  }

  modalWhenLeavingFormUnfinished() {
    const headerLogOutLink = document.querySelector('header a[data-method="delete"]')
    headerLogOutLink.removeAttribute('data-method')
    const headerLinks = Array.from(document.querySelectorAll('header a, .progress-nav-container a')).filter(link => !link.closest('.progress-nav')).filter(link => !link.closest('.modal')).filter(link => !link.dataset.target).filter(link => !link.dataset.toggle).filter(link => link.href.length > 1)
    headerLinks.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault()
        this.showLeavingModal(link.href, headerLogOutLink)
      })
    })
    const buttons = Array.from(document.querySelectorAll('header button, .progress-nav-container button')).filter(button => !button.closest('.progress-nav')).filter(button => !button.closest('.modal')).filter(button => !button.dataset.target)
    buttons.forEach(button => {
      button.addEventListener('click', (e) => {
        e.preventDefault()
        this.showLeavingModal(button.href, headerLogOutLink)
      })
    })
  }

  showLeavingModal(href, headerLogOutLink) {
    const leavingModalTrigger = document.getElementById('leavingWarningModalTrigger')
    leavingModalTrigger.click()
    this.leavingApplicationButtonTarget.addEventListener('click', () => {
      if (this.leavingApplicationButtonTarget.textContent === 'Logout') {
        headerLogOutLink.setAttribute('data-method', 'delete')
      }
      window.location.href = href
    })
  }
}