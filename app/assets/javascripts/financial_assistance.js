// Initialize the dependent person form
$(document).on('ajax:success', '#edit-dependent-person', function (event) {
  $.inputMasks();
  init_glossary();

  $('#applicant_same_with_primary').on('click', function () {
    if ($(this).is(':checked')) {
      $('#applicant-home-address-area').addClass('hidden');
    } else {
      $('#applicant-home-address-area').removeClass('hidden');
    }
  });

  $(document).on('click', 'button#delete_applicant_button', function (e) {
    e.preventDefault();
    $('#destroyApplicant').modal();

    $('#destroyApplicant .modal-cancel-button').on('click', function (e) {
      console.log('cancel');
      $('#destroyApplicant').modal('hidden');
    });
    $('.btn-confirmation').removeAttr('disabled');
  });

  $(document).on('click', '#destroy-confirm', function (e) {
    confirmDestoyApplicant(e, $(this).data('url'));
  });

  function confirmDestoyApplicant(event, url) {
    // console.log('Applicant Destroy Initiated');
    $('#destroy-confirm').prop('disabled', true);
    event.preventDefault();
    event.stopImmediatePropagation();
    //
    $('.modal-backdrop').removeClass('modal-backdrop');
    $('.modal-open').removeClass('modal-open');

    $.ajax({
      url: url,
      type: 'DELETE',
      dataType: 'script',
      contentType: false,
      processData: false,
    });
  }

  $(document).off('click', '#confirm_member');
  $(document).on('click', '#confirm_member', function (e) {
    if ($('input#applicant_same_with_primary').length) {
      if ($('input#applicant_same_with_primary').is(':checked')) {
        $(
          '#applicant-home-address-area input.required, #applicant-home-address-area select.required, #applicant-home-address-area .address_required'
        ).removeAttr('required');
      } else {
        $(
          '#applicant-home-address-area input.required, #applicant-home-address-area select.required, #applicant-home-address-area .address_required'
        ).attr('required', true);
      }

      $('.btn-confirmation').removeAttr('disabled');
    }
    $(this).addClass('disabled').attr('tabindex', -1).blur();
    PersonValidations.manageRequiredValidations($('#confirm_member'));

    if ($(this).closest('form')[0].checkValidity()) {
      $(this).removeClass('disabled').attr('tabindex', 0);
    }
  });
});

$(document).on('ajax:success', '#primary-person', function (event) {
  $.inputMasks();
  init_glossary();
});
