document.addEventListener('turbolinks:request-start', function (event) {
  var xhr = event.data.xhr;
  xhr.setRequestHeader(
    'X-Turbolinks-Nonce',
    $("meta[name='csp-nonce']").prop('content')
  );
});

function disableButton(button) {
  button.attr('disabled', 'disabled')
        .addClass('disabled');
};

function enableButton(button) {
  button.removeAttr('disabled')
        .removeClass('disabled');
};

$(document).on('click', '.remove-child-row-btn', function () {
  $('tr.child-row:visible').remove();
});

$(document).on('click', '.update-enrollment-end-date-btn', function () {
  TerminateWithEarlierDate();
});

$(document).on('click', '.expire-sep-type-end-on-col', function () {
  $('#end_on').attr('min', $('#min_date').val());
});

var immigrationDocWarning = immigrationDocWarning || false;
$(document).on('click', '.manage-person-validations-click', function () {
  var element = this;
  var form = $('.edit_person')[0];

  PersonValidations.manageRequiredValidations($(element));

  if (form.checkValidity()){
    disableButton($(element));
  }

  if (!$('#showWarning').hasClass('hidden') && !immigrationDocWarning) {
    immigrationDocWarning = true;
    $(this).removeAttr('disabled').removeClass('disabled');
  }
});

$(document).on('keydown', '.manage-person-validations-click', function (event) {
  var element = this;
  if (event.key === 'Enter') {
    $(element).click();
  }
});

$(document).on('click', '.qle-flow-close-fail', function () {
  $('#qle_flow_info').hide();
});

$(document).on('click', '.address-change-confirmation', function () {
  $('.btn-confirmation').prop('disabled', true);
  $('.modal-backdrop').removeClass('modal-backdrop');
  $('.modal-open').removeClass('modal-open');

  PersonValidations.manageRequiredValidations($('#confirm-dependent'));
  $('#addressChangeConfirmation').data('customParam', { disable: true }).modal('hide');

  return false;
});

$(document).on('click', '#confirm_add_sep', function (event) {
  var prior_sep = $('#prior_py_sep').val() == 'true';
  if (prior_sep) {
    event.preventDefault();
    if ($('#admin_sep_form')[0].checkValidity()) {
      $('#priorSepModal').modal('show');
    }
  }
});

$(document).on('click', '#priorSepModal .btn-confirmation', function () {
  $('.modal-backdrop').removeClass('modal-backdrop');
  $('.modal-open').removeClass('modal-open');
  $('#admin_sep_form').trigger('submit');
  return false;
});

$(document).on(
  'click',
  '.broker-staff-registration-container span.search',
  function () {
    // components/benefit_sponsors/app/views/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/_new_staff_applicant.html.erb
    brokerSearch();
    return false;
  }
);

$(document).on('click', '.select-broker-agency', function (event) {
  event.preventDefault();
  selectBrokereAgency(this);
});
// components/benefit_sponsors/app/views/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/_search_broker_agency.html.erb:

$(document).on(
  'click',
  '.assister-staff-registration-container span.search',
  function () {
    // components/benefit_sponsors/app/views/benefit_sponsors/profiles/assister_agencies/assister_agency_staff_roles/_new_staff_applicant.html.erb
    assisterSearch();
    return false;
  }
);

$(document).on('click', '.select-assister-agency', function (event) {
  event.preventDefault();
  selectAssisterAgency(this);
});
// components/benefit_sponsors/app/views/benefit_sponsors/profiles/assister_agencies/assister_agency_staff_roles/_search_assister_agency.html.erb:

function init_dependent_address_fields() {
  // app/views/shared/_address_fields_for_dependent.html.erb
  $(document).ready(function () {
    $('#state_id').change(function () {
      if (!$('#no_dc_address').is(':checked') && $(this).val() != 'DC') {
        alert('You have selected a Non DC state, please check No DC Address');
      }
    });
  });
}

function init_tribe_fields() {
  // app/views/insured/consumer_roles/_tribe_fields.html.erb
  var enroll_state_abbr = $('#enroll_state_abbr').val();
  var is_indian_alaskan_tribe_details_enabled =
    $('#is_indian_alaskan_tribe_details_enabled').val() === 'true';

  if (is_indian_alaskan_tribe_details_enabled) {
    var is_featured_tribes_selection_enabled =
      $('#is_featured_tribes_selection_enabled').val() === 'true';
    var tribal_state = $('#tribal-state').val();
    var tribe_codes_array = $('.tribe_codes:checked')
      .map(function () {
        return $(this).val();
      })
      .get();
    var tribal_name_container_show =
      typeof tribe_codes_array != 'undefined' &&
      tribe_codes_array.includes('OT');

    if (
      is_featured_tribes_selection_enabled &&
      tribal_state == enroll_state_abbr
    ) {
      $('.featured-tribe-container').removeClass('hide');
      if (tribal_name_container_show) {
        $('.tribal-name-container').removeClass('hide');
      } else {
        $('#tribal-name').val('');
        $('.tribal-name-container').addClass('hide');
      }
    } else {
      $('.tribe_codes:checked').removeAttr('checked');
      $('.tribal-name-container').removeClass('hide');
      $('.featured-tribe-container').addClass('hide');
    }
  }
}

function init_glossary() {
  // app/views/shared/_glossary.html.erb
  $(document).on('click', '.popover-close-btn', function () {
    $('.glossary').popover('hide');
  });

  $(function () {
    $('[data-toggle="popover"]').popover();
  });
  $('[data-toggle="popover"]').popover({
    trigger: 'focus',
    template:
      '<div class="popover ' +
      (document.documentElement.dataset.bs4 ? 'p-2' : '') +
      '"><div class="arrow"></div><h3 class="popover-title"></h3><div class="popover-content"></div></div>',
  });
}

function init_dependent_form() {
  // app/views/insured/family_members/_dependent_form.html.erb
  var bs4 = document.documentElement.dataset.bs4;

  if (bs4) {
    $(document).ready(function () {
      $.inputMasks();
      applyListeners();

      $('.field_with_errors > *').unwrap();

      if ($('input#dependent_same_with_primary').is(':checked')) {
        $(
          '#dependent-home-address-area input.required, #dependent-home-address-area select.required, #dependent-home-address-area .address_required'
        ).removeAttr('required');
      } else {
        $(
          '#dependent-home-address-area input.required, #dependent-home-address-area select.required, #dependent-home-address-area .address_required'
        ).attr('required', true);
      }

      $('#dependent_first_name').change(function () {
        var text =
          $('#dependent_first_name').val() == ''
            ? 'This person'
            : $('#dependent_first_name').val();
        $('#is_applying_coverage_value_dep').text(
          'Does ' + text + ' need coverage? *'
        );
        $('#is_applying_coverage_value_dep_1').text(text);
      });

      if ($('.dependent-error').length) {
        $('.dependent_list').get(0).scrollIntoView({ behavior: 'smooth' });
      }
    });

    if ($('.is-editing-member').length) {
      $('.remove-dependent-form').off('click');
      $('.remove-personal-form').on('click', function (e) {
        $('.append_consumer_info').empty();
        let member_id = $('.is-editing-member').data('member-id');
        $('#person-' + member_id).addClass('hidden');
        $('a[id^=edit-member]').removeClass('disabled');
        $('a[id^=edit-member]').removeAttr('disabled');
      });
    }

    $(document).off('click', '.confirm-member');
    $(document).on('click', '.confirm-member', function (e) {
      $('#confirm-dependent').click();
    });

    $(document).off('click', '#confirm-dependent');
    $(document).on('click', '#confirm-dependent', function (e) {
      if ($('input#dependent_same_with_primary').is(':checked')) {
        $(
          '#dependent-home-address-area input.required, #dependent-home-address-area select.required, #dependent-home-address-area .address_required'
        ).removeAttr('required');
      } else {
        $(
          '#dependent-home-address-area input.required, #dependent-home-address-area select.required, #dependent-home-address-area .address_required'
        ).attr('required', true);
      }

      $('.btn-confirmation').removeAttr('disabled');

      var form = $('#new_dependent')[0] || $('#edit_dependent')[0];

      if (
        form.checkValidity() &&
        !$('input#dependent_same_with_primary').is(':checked')
      ) {
        $('#addressChangeConfirmation').modal('show');
      } else {
        PersonValidations.manageRequiredValidations($('#confirm-dependent'));
      }
    });
  } else {
    $(document).ready(function () {
      $.inputMasks();

      $('.field_with_errors > *').unwrap();
      Freebies.floatlabels();
      if ($('input#dependent_same_with_primary').is(':checked')) {
        $('#address_info .address_required').removeAttr('required');
      }
      $('#dependent_first_name').change(function () {
        var text =
          $('#dependent_first_name').val() == ''
            ? 'This person'
            : $('#dependent_first_name').val();
        $('#is_applying_coverage_value_dep').text(
          'Does ' + text + ' need coverage? *'
        );
        $('#is_applying_coverage_value_dep_1').text(text);
      });
    });

    $(document).on('keydown', '#confirm-dependent', function (event) {
      handleButtonKeyDown(event, 'confirm-dependent');
    });
    $(document).off('click', '#confirm-dependent');
    $(document).on('click', '#confirm-dependent', function (e) {
      $('.btn-confirmation').removeAttr('disabled');

      var form = $('#new_dependent')[0] || $('#edit_dependent')[0];

      if (
        form.checkValidity() &&
        !$('input#dependent_same_with_primary').is(':checked')
      ) {
        $('#addressChangeConfirmation').modal('show');
      } else {
        PersonValidations.manageRequiredValidations($('#confirm-dependent'));
      }
    });

    $(document).on(
      'click',
      '.remove-new-employee-dependent, .confirm-member-form-btn',
      function () {
        $('#btn-continue').removeClass('disabled');
      }
    );

    $(document).on('keydown', '.radio-female-btn', function (event) {
      handleRadioKeyDown(event, 'radio_female');
    });
    $(document).on('keydown', '.radio-male-btn', function (event) {
      handleRadioKeyDown(event, 'radio_male');
    });
  }
}

function initSSNValidation() {
  $('input[data-ssn-ui-validation="true"]').on('invalid', function () {
    this.setCustomValidity($(this).data('ssn-ui-validation-message'));
  });

  $('input[data-ssn-ui-validation="true"]').on('input', function () {
    this.setCustomValidity('');
  });
}


function initSecurityQuestionsModal() {
  disableSelectric = true;

  $('.security-question-select').on('change', function(){
    var questionId = $(this).val();
    var selectedQuestions = [];

    $.each($('.selectric-scroll li.selected'), function(propertyName, propertyValue){
      var elemIndex = $(this).data('index');
      if(elemIndex != 0) {
        selectedQuestions.push(elemIndex);
      }
    });

    $('.selectric-scroll li').show();
    selectedQuestions.forEach(function(index){
      $(".selectric-scroll li[data-index='" + index +"']").hide();
    });

    //[attribute!='value']
    $.each($('.security-question-select').not(this), function(propertyName, propertyValue){
      $(this).children("option").show();
      $(this).children("option[value='" + questionId + "']").hide();
    });

  });
}

$('.remove-personal-form').off('click');
$('.remove-personal-form').on('click', function (e) {
  $('.append_consumer_info').empty();
  if ($('.my-household-page')) {
    $('#person-<%= @person.id %>').addClass('hidden');
    $('a[id^=edit-member]').removeClass('disabled');
    $('a[id^=edit-member]').removeAttr('disabled');
    // primary_family
    var family_table = $(
      "<%= escape_javascript(render 'insured/families/manage_family_table', members: @person.primary_family.active_family_members) %>"
    );
    $('#manage_family_content').html(family_table);
  }
});

$(document).off('click', '.confirm-member');
$(document).on('click', '.confirm-member', function (e) {
  $('#save_personal').trigger('click');
});

/// components/financial_assistance/app/views/financial_assistance/applicants/_edit.html.erb
$(document).on('ready', function () {
  $.inputMasks();
});

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
    $('#destroyApplicant').modal('hidden');
  });
  $('.btn-confirmation').removeAttr('disabled');
});

function confirmDestoyApplicant(event, url) {
  // console.log('Applicant Destroy1 Initiated');
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

/// app/views/exchanges/hbx_profiles/_view_hbx_enrollments.html.erb
function reInstateModal() {
  var row = document
    .querySelector('.reinstate-enrollment-row input[type=radio]:checked')
    .closest('.reinstate-enrollment-row');
  var failure = row.getAttribute('data-reinstate-failure');
  if (failure) {
    $('.modal-header .icon').removeClass('info-icon').addClass('warning-icon');
    $('b.warning-text').removeClass('hidden');
    $('#unableToReinstate').text(failure);
    $('#show_reinstate').hide();
    $('.btn-confirmation').hide();
  } else {
    $('.modal-header .icon').removeClass('warning-icon').addClass('info-icon');
    $('b.warning-text').addClass('hidden');
    $('#unableToReinstate').text('');
    $('#show_reinstate').show();
    $('.btn-confirmation').show();
  }

  var effectiveDate = row.querySelector('#reinstate').textContent;
  var planName = row.querySelector('#name').textContent;
  $('#effective-date').text(effectiveDate);
  $('#reinstate-plan-name').text(planName);

  $('#reinstate_confirm').modal('show');
}

function confirmReinstate(event) {
  $('#reinstate-form #comments').val($('.modal-dialog .comments').val());
  $('.btn-confirmation').prop('disabled', true);

  event.preventDefault();
  event.stopImmediatePropagation();

  $('.modal-backdrop').removeClass('modal-backdrop');
  $('.modal-open').removeClass('modal-open');

  var formData = new FormData($('#reinstate-form')[0]);

  $.ajax({
    url: '/exchanges/hbx_profiles/reinstate_enrollment.js',
    type: 'POST',
    data: formData,
    contentType: false,
    processData: false,
  });
}

$(document).on('ajax:success', function () {
  $('.reinstate-modal-confirm-btn').on('click', function (e) {
    confirmReinstate(e);
    return false;
  });

  $('#reinstate-submit').on('click', reInstateModal);
});

$(document).on('turbolinks:load', function () {
  const handleNewPartials = function (node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return;

    // Handle message viewing partials
    $(node)
      .find('[data-partial="individual_message"]:not([data-processed])')
      .attr('data-processed', true)
      .each(viewMessage);

    // Handle message deletion partials
    $(node)
      .find('[data-msg-delete]:not([data-processed])')
      .attr('data-processed', true)
      .each(deleteMessage);
  };

  const observer = new MutationObserver(function (mutations) {
    mutations.forEach((mutation) =>
      mutation.addedNodes.forEach(handleNewPartials)
    );
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });
});

// view message function
function viewMessage() {
  $(document)
    .off('click keydown', '.msg-inbox')
    .on('click keydown', '.msg-inbox', function (event) {
      // Don't trigger if it's a tab key or if event is from delete button
      if (
        event.keyCode === 9 ||
        $(event.target).closest('[data-msg-delete]').length
      ) {
        return;
      }

      // Only process click or enter key
      if (event.type === 'keydown' && event.keyCode !== 13) {
        return;
      }

      $.ajax({
        type: 'GET',
        url: $(this).data('url'),
        dataType: 'script',
      });
    });
}

// delete message function
function deleteMessage() {
  $(document)
    .off('click keydown', '[data-msg-delete]')
    .on('click keydown', '[data-msg-delete]', function (event) {
      if (event.type === 'keydown' && event.key !== 'Enter') return;

      event.preventDefault();
      event.stopPropagation();

      const messageRow = $(this).closest('.msg-inbox');
      const url = messageRow.data('url');

      $.ajax({
        type: 'DELETE',
        url: url,
        dataType: 'script',
      });
    });
}

$(document).on('ajax:success', function () {
  var resetButton = document.getElementById('resetUsernameEmailFields');

  if (resetButton) {
    resetButton.addEventListener('click', function (event) {
      event.preventDefault();
      document.getElementById('inputNewUsername').value = '';
      document.getElementById('inputNewEmail').value = '';
    });
  }
});

$(document).on('invalid', '.dependent-ssn-input', function () {
  this.setCustomValidity($(this).data('error-message'));
});

$(document).on('input', '.dependent-ssn-input', function () {
  this.setCustomValidity('');
});

$(document).on('keydown', '#existing-submit', function (event) {
  handleButtonKeyDown(event, 'existing-submit');
});


$(document).on('keydown', '#upload-identity', function(event) { handleButtonKeyDown(event, 'upload_identity') })

$(document).on('turbolinks:load ajax:success', function () {
  $(document).off('click', '#preview_submit');
  $(document).on('click', '#preview_submit', function (e) {
    onSubmit(e);
  });
});

function onSubmit(e) {
  if (
    !document.getElementsByClassName('badge-alt-blue').length &&
    !document.getElementsByClassName('badge-blue').length
  ) {
    e.preventDefault();
    e.stopImmediatePropagation();
    if (document.getElementsByClassName('badge-danger').length) {
      alert('Recipients is invalid. Please check red badges.');
    } else {
      alert('Recipients should not be blank');
    }
    return;
  }

  if (document.getElementsByClassName('badge-danger').length) {
    e.preventDefault();
    e.stopImmediatePropagation();
    alert('Recipients is invalid. Please check red badges.');
  }
}

$(document).on('keydown', '#btn-keep-plan', function(event) { handleButtonKeyDown(event, 'btn-keep-plan') })
