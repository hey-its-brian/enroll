import { Controller } from "stimulus";

/*
 * This controller is used to expand and collapse rows in a table.
 */
export default class extends Controller {
  static targets = ["row", "details"];

  // Setup actionable rows
  connect() {
    // prepend a caret icon to the first cell of each row
    this.rowTargets.forEach(row => {
      if(!this._isExpandable(row)) { return; }

      row.setAttribute('data-action', 'click->expandable-table#toggle');

      const firstCell = row.querySelector('td');
      const caretDiv = document.createElement('div');
      caretDiv.classList.add('caret-icon', 'mr-2');
      firstCell.insertBefore(caretDiv, firstCell.firstChild);
      firstCell.classList.add('d-flex', 'align-items-center');
    });

    // hide and prevent hover of detail rows
    this.detailsTargets.forEach(details => { 
      details.classList.add('hidden', 'no-hover') 
    });
  }

  // Expand or collapse action which toggles the "expanded" class on the row element and the "hidden" class on the details element.
  toggle(event) {    
    const row = event.currentTarget

    if (!this._isExpandable(row) || window.getSelection().toString()) { return; } // prevent click fires when the row isn't expandable or the user was highlighting the cell

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
  _isExpandable(row) {
    const nextRow = row.nextElementSibling;
    return nextRow && nextRow.dataset.target === "expandable-table.details";
  }
}