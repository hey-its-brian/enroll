import { Controller } from 'stimulus';
import sanitizeHtml from 'sanitize-html';

export default class extends Controller {
  static targets = ["container", "year", "perPage"]

  connect() {
    console.log("Uploads controller connected")
  }

  changeYear() {
    this.loadDocuments({ page: 1 })
  }

  changePerPage() {
    this.loadDocuments({ page: 1 })
  }

  paginate(event) {
    event.preventDefault()
    const page = parseInt(event.currentTarget.dataset.page, 10)
    if (isNaN(page)) return

    this.loadDocuments({ page })
  }

  loadDocuments(options = {}) {
    const year = this.yearTarget.value
    const perPage = this.hasPerPageTarget ? this.perPageTarget?.value : 10
    const page = options.page || 1

    const button = this.containerTarget
    const url = new URL(button.dataset.uploadsUrlValue, window.location.origin)
    url.searchParams.set("year", year)
    url.searchParams.set("per_page", perPage)
    url.searchParams.set("page", page)

    this.containerTarget.innerHTML = "<div class='text-center py-4'>Loading...</div>"

    fetch(url.toString(), {
      headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
    })
      .then(response => response.text())
      .then(html => {
        this.containerTarget.innerHTML = this.sanitize(html);
      })
      .catch(error => {
        this.containerTarget.innerHTML = "<div class='alert alert-danger'>Failed to load documents.</div>"
      })
  }

  sanitize(html) {
    const allowedTags = sanitizeHtml.defaults.allowedTags.concat([
      'div', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
      'a', 'span', 'ul', 'li', 'nav', 'select', 'option',
      'button', 'span'
    ]);

    return sanitizeHtml(html, {
      allowedTags: allowedTags,
      allowedAttributes: {
        '*': ['class', 'id', 'aria-*', 'data-*'],
        'a': ['href', 'class', 'aria-*', 'data-*'],
        'select': ['class', 'data-*', 'data-target', 'data-action'],
        'option': ['value', 'selected'],
        'button': ['type', 'class', 'data-*'],
        'tr': ['class', 'colspan'],
        'td': ['class', 'colspan']
      }
    });
  }
}
