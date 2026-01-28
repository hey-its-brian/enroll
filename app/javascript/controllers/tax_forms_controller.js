import { Controller } from "stimulus";

export default class extends Controller {
    submit(event) {
        event.preventDefault();
        const taxFormId = this.element.querySelector('input[name="relation_id"]:checked');

        if (taxFormId) {
            const triggerId = event.target.dataset.triggerId;
            const trigger = document.getElementById(triggerId);
            if (trigger) {
                trigger.click();
            }
        } else {
            alert("Please select a document to submit.");
        }
    }

    confirm(event) {
        event.preventDefault();
        const formId = event.target.dataset.formId;
        const form = document.getElementById(formId);
        const submitBtn = form.querySelector('button[type="submit"]');
        if (submitBtn) {
            submitBtn.click();
        }

        const modal = event.target.closest('.modal');
        const closeBtn = modal.querySelector('.hidden[data-dismiss="modal"]');
        if (closeBtn) {
            closeBtn.click();
        }
    }
}
