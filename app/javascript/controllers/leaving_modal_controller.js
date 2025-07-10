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
        this.showLeavingModal(link, headerLogOutLink)
      })
    })
    const buttons = Array.from(document.querySelectorAll('header button, .progress-nav-container button')).filter(button => !button.closest('.progress-nav')).filter(button => !button.closest('.modal')).filter(button => !button.dataset.target)
    buttons.forEach(button => {
      button.addEventListener('click', (e) => {
        e.preventDefault()
        this.showLeavingModal(button, headerLogOutLink)
      })
    })
  }

  showLeavingModal(target, headerLogOutLink) {
    const leavingModalTrigger = document.getElementById('leavingWarningModalTrigger')
    leavingModalTrigger.click()
    this.leavingApplicationButtonTarget.addEventListener('click', () => {
      if (this.leavingApplicationButtonTarget.textContent === 'Logout') {
        headerLogOutLink.setAttribute('data-method', 'delete')
      }
      // need to check if the href type to trigger the default action
      if (target.nodeName === 'A') {
        // if it is an anchor tag, we just need to navigate to the href
        window.location.href = target.href
      } else if (target.nodeName === 'BUTTON' && target.type === 'submit' && target.closest('form')) {
        // need to submit the form if it is a submit button
        target.closest('form').submit()
      } else if (target.nodeName === 'BUTTON') {
        // need to unbind the click event set above and then click the button
        this.leavingApplicationButtonTarget.removeEventListener('click', this.showLeavingModal)
        target.click()
      }
    })
  }
}