/**
 * @deprecated This function is deprecated and will be removed in future versions.
 * Handles the 'keydown' event for a radio button.
 * If the 'Enter' key is pressed, it triggers a click event on the radio button.
 *
 * Instead of using this function, add the attribute `data-keydown-id` with
 * the same value of the radioId to the same element used by this function.
 *
 * @param {KeyboardEvent} event - The keyboard event object.
 * @param {string} radioId - The ID of the radio button to be clicked.
 */
function handleRadioKeyDown(event, radioId) {
  if (event.key === 'Enter') {
    document.getElementById(radioId).click();
  }
}

function handleCitizenKeyDown(event, radioIdBase) {
  if (event.key === 'Enter') {
    const personElement = document.getElementById(`person_${radioIdBase}`);
    const dependentElement = document.getElementById(
      `dependent_${radioIdBase}`
    );

    if (personElement) {
      personElement.click();
    } else if (dependentElement) {
      dependentElement.click();
    }
  }
}

function handleContactInfoKeyDown(event, radioId, modifyDiv) {
  if (event.key === 'Enter') {
    document.getElementById(radioId).click();
    hidden_div = document.getElementById(modifyDiv);
    if (hidden_div.style.display === 'block') {
      hidden_div.style.display = 'none';
    } else {
      hidden_div.style.opacity = '1';
      hidden_div.style.display = 'block';
    }
  }
}

$(document).on('keydown', '.plan-contact-info-alt', function (event) {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    document.getElementById($(this).data('contact-click-id')).click();
  }
});

document.addEventListener('turbolinks:load', () => {
  // Use event propogation to handle `Enter` keydown events for HTML elements with the attribute `data-keydown-id`.
  // Using event propogation is mainly a workaround for FA Income pages, which load income forms by cloning dummy hidden forms.
  document.addEventListener('keydown', (event) => {
    // Traverse up the DOM tree to find the element with the `data-keydown-id` attribute, if any.
    let targetElement = event.target;
    while (targetElement && !targetElement.dataset.keydownId) {
      targetElement = targetElement.parentElement;
    }

    /*
     * Trigger the click on the proxy element identified by the attribute.
     */
   if (targetElement && event.key === 'Enter') {
      event.preventDefault();
      event.stopImmediatePropagation();

      const keydownId = targetElement.dataset.keydownId;
      clickElementById(keydownId);
    }
  });
});

/**
 * Simulates a click event on an HTML element with the specified ID.
 *
 * @param {string} keydownId - The ID of the HTML element to be clicked.
 */
function clickElementById(keydownId) {
  document.getElementById(keydownId).click();
}

/**
 * Handles the keydown event for a button and triggers a click event if the Enter key is pressed.
 * @deprecated This function is deprecated and will be removed in future versions. Use a more comprehensive keyboard navigation library instead.
 * @param {KeyboardEvent} event - The keydown event object.
 * @param {string} buttonId - The ID of the button to be clicked.
 *
 * Instead of using this function, add the attribute `data-keydown-id` with
 * the same value of the buttonId to the same element used by this function.
 */
function handleButtonKeyDown(event, buttonId) {
  if (event.key === 'Enter') {
    document.getElementById(buttonId).click();
  }
}

function handleSEPRadioButton(buttonId) {
  document.getElementById(buttonId).click();
}

function handleCancelButtonKeyDown(event, buttonId, hideForm) {
  if (event.key === 'Enter') {
    document.getElementById(buttonId).click();
    document.getElementById(hideForm).classList.add('hidden');
  }
}

function handleGlossaryFocus(glossaryId) {
  $('#' + glossaryId).popover('show');
}

function handleGlossaryBlur(glossaryId) {
  $('#' + glossaryId).popover('hide');
}

function handleGlossaryKeydown(event, glossaryId) {
  if (event.key === 'Tab' || event.key === 'Enter') {
    $('#' + glossaryId).popover('show');
  } else {
    $('#' + glossaryId).popover('hide');
  }
}

window.addEventListener(
  'keydown',
  function (event) {
    if (
      event.keyIdentifier == 'U+000A' ||
      event.keyIdentifier == 'Enter' ||
      event.key === 'Enter'
    ) {
      if (
        event.target.nodeName == 'INPUT' &&
        event.target.type !== 'text' &&
        event.target.type !== 'search' &&
        event.target.type !== 'textarea'
      ) {
        var form = event.target.closest('form');
        var reqCheckboxLists = form.querySelectorAll('.req-checkbox-group');
        var requiredChecklists = [...reqCheckboxLists];
        var checkListFail = false;
        requiredChecklists.forEach(function (reqCheckbox) {
          if (
            reqCheckbox.querySelectorAll('input[type="checkbox"]:checked')
              .length == 0
          ) {
            checkListFail = true;
            reqCheckbox.classList.add('invalid');
          } else {
            reqCheckbox.classList.remove('invalid');
          }
        });
        if (form.checkValidity() === false || checkListFail) {
          event.preventDefault();
          event.stopPropagation();
          form.classList.add('was-validated');
        } else {
          form.classList.remove('was-validated');
        }
      }
    }
  },
  true
);

document.addEventListener('turbolinks:load', () => {
  /**
   * Focus all elements in the document that have the attribute 'data-focus-id'.
   */
  const elements = document.querySelectorAll('[data-focus-id]');

  elements.forEach((element) => {
    const focusId = element.dataset.focusId;

    element.addEventListener('focus', (event) => {
      handleGlossaryFocus(focusId);
    });
  });
});

document.addEventListener('turbolinks:load', () => {
  /**
   * Blur all elements in the document that have the attribute 'data-blur-id'.
   */
  const elements = document.querySelectorAll('[data-blur-id]');

  elements.forEach((element) => {
    const blurId = element.dataset.blurId;

    element.addEventListener('blur', (event) => {
      handleGlossaryBlur(blurId);
    });
  });
});
