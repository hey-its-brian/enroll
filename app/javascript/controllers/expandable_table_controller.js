import { Controller } from "stimulus";

/*
 * This controller is used to expand and collapse rows in a table.
 */
export default class extends Controller {
  static targets = ["row", "details"];

  // Setup actionable rows
  connect() {
    // prepend a caret icon to the first cell of each row
    const hasExpandable = this.rowTargets.some((row) => { return this.#isExpandable(row) });

    this.rowTargets.forEach(row => {
      const firstCell = row.querySelector('td');
      const originalContent = Array.from(firstCell.children)
      const newContent = document.createElement('div');

      if(this.#isExpandable(row)) {
        const actions = [ "click", "keydown" ].map((eventType) => { return `${eventType}->${this.identifier}#handleEvent` }).join(" ");
        row.setAttribute('data-action', actions);
        row.setAttribute('tabindex', '0');

        const caretDiv = document.createElement('div');
        caretDiv.classList.add('caret-icon', 'mr-1');
        newContent.appendChild(caretDiv);
      } else if (hasExpandable) {
        newContent.classList.add('ml-3');
      }

      newContent.classList.add('d-flex', 'align-items-center');
      originalContent.forEach(child => {
        newContent.appendChild(child);
      });

      while (firstCell.firstChild) {
        firstCell.removeChild(firstCell.firstChild);
      }

      firstCell.appendChild(newContent);
    });

    // hide and prevent hover of detail rows
    this.detailsTargets.forEach(details => { 
      details.classList.add('hidden', 'no-hover') 
    });
  }

  handleEvent(event) {
    if (event.type === "click" || (event.type === "keydown" && event.key === "Enter")) {
      this.#toggle(event.currentTarget);
     }
  }

  // Expand or collapse action which toggles the "expanded" class on the row element and the "hidden" class on the details element.
  #toggle(row) {    
    if (!this.#isExpandable(row) || window.getSelection().toString()) { return; } // prevent click fires when the row isn't expandable or the user was highlighting the cell

    const details = row.nextElementSibling;

    row.classList.toggle("expanded");
    details.classList.toggle("hidden");
  }

  /*
  * Checks if the given row is expandable by verifying if the next sibling row
  * has the `data-target="expandable-table.details"` attribute.
  *
  * @param {HTMLElement} row - The row element to check.
  * @returns {boolean} - Returns true if the row is expandable, otherwise false.
  */
  #isExpandable(row) {
    const nextRow = row.nextElementSibling;
    return nextRow && nextRow.dataset.target === "expandable-table.details";
  }
}