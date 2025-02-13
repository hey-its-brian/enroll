$(function () {
  applyBrokerTabClickHandlers();
});

function applyBrokerTabClickHandlers() {
  $('div[name=broker_agency_tabs] >')
    .children()
    .each(function () {
      $(this).change(function () {
        filter = 'broker';
        agency_type = $(this).attr('value');
        action_url = '/broker_agencies/broker_roles/new_broker.js';
        if (agency_type == 'new') {
          action_url = '/broker_agencies/broker_roles/new_broker_agency.js';
        }
        $.ajax({
          url: action_url,
          type: 'GET',
          data: { filter: filter, agency_type: agency_type },
        });
      });
    });
}

$(document).on('click', 'a.select-broker-agency', function () {
  if ($('.table-responsive').length) {
    $('.broker-agency-submit').removeClass('hidden');
  }
  $('.result .form-border').removeClass('agency-selected');
  $('#person_broker_agency_id').val($(this).data('broker_agency_profile_id'));
  $(this).parents('.form-border').addClass('agency-selected');
});

$(document).on('click', '.general-agency-search a.search', function () {
  $('.general-agency-search .result').empty();
  var general_agency_search = $('input#agency_search').val();
  if (general_agency_search != undefined && general_agency_search != '') {
    $(this).button('loading');
    $('#organization_general_agency_profile_id').val('');
    $.ajax({
      url: '/general_agencies/profiles/search_general_agency.js',
      type: 'GET',
      data: { general_agency_search: general_agency_search },
    });
  }
});
$(document).on('click', 'a.select-general-agency', function () {
  $('.result .form-border').removeClass('agency-selected');
  $('#organization_general_agency_profile_id').val(
    $(this).data('general_agency_profile_id')
  );
  $(this).parents('.form-border').addClass('agency-selected');
});

function allowBrokerAgencyFormSubmission() {
  var broker_attestation_fields = document.getElementsByClassName(
    'broker-attestation-field'
  );
  var form_button = document.getElementById('broker-btn');
  if (
    Array.from(broker_attestation_fields).every(
      (form_element) => form_element.checked == true
    ) == true
  ) {
    form_button.disabled = false;
  } else {
    form_button.disabled = true;
  }
}

$(function () {
  $('.broker-attestation-field').on('change', function () {
    allowBrokerAgencyFormSubmission();
  });
});

/// components/benefit_sponsors/app/views/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/_new_staff_applicant.html.erb
$(document).on('turbolinks:load ajax:success', function () {
  validateAjaxForm();
});

function brokerSearch() {
  var broker_agency_search = document.getElementById(
    'staff_agency_search'
  ).value;
  var broker_registration_page = document.getElementById(
    'staff_is_broker_registration_page'
  ).value;
  document.getElementById('broker-staff-btn').disabled = true;
  if (broker_agency_search != undefined) {
    $.ajax({
      url: '/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/search_broker_agency.js',
      type: 'GET',
      data: {
        q: broker_agency_search,
        broker_registration_page: broker_registration_page,
      },
    });
  }
}

function selectBrokereAgency(element) {
  var result = document.querySelectorAll('.result');
  result.forEach(function (result) {
    var elements = result.querySelectorAll('.staff-select-broker');
    elements.forEach(function (ele) {
      ele.classList.remove('agency-selected');
    });
  });
  document.getElementById('staff_profile_id').value =
    element.dataset.broker_agency_profile_id;
  element.closest('.staff-select-broker').classList.add('agency-selected');
  document.getElementById('broker-staff-btn').disabled = false;
}

/// components/benefit_sponsors/app/views/benefit_sponsors/profiles/registrations/new.html.erb
$(document).on('turbolinks:load ajax:success', function () {
  validateForm();
  checkDate();
  checkKeyValue();
  numKey();

  $('#broker_agency_form').tabs({
    activate: function (event, ui) {
      if (ui.newPanel.attr('id') == 'broker_agency_staff') {
        var url =
          '/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/new?profile_type';
        if (!$('#loaded').length) {
          $.ajax({
            url: url,
            type: 'GET',
            data: { profile_type: 'broker_agency_staff' },
            success: function (data) {
              $('#broker_agency_staff').html(data);
              const dobInput = document.querySelector('#staff_dob');
              checkDate();
              indicateRequiredFields();
            },
          });
        }
      }
    },
  });

  $('#general_agency_form').tabs({
    activate: function (event, ui) {
      if (ui.newPanel.attr('id') == 'general_agency_staff') {
        var url =
          '/benefit_sponsors/profiles/general_agencies/general_agency_staff_roles/new';
        if (!$('#loaded').length) {
          $.ajax({
            url: url,
            type: 'GET',
            data: { profile_type: 'general_agency_staff' },
            success: function (data) {
              $('#general_agency_staff').html(data);
              initDatepicker(
                'inputStaffDOB',
                new Date('<%= Date.today.beginning_of_month - 90.years %>'),
                new Date('<%= Date.today.end_of_month - 18.years %>')
              );
            },
          });
        }
      }
    },
  });
});

function checkDate() {
  const dobInput = document.querySelector(
    '#staff_dob, #agency_staff_roles_attributes_0_dob'
  );

  if (dobInput) {
    // Add event listeners
    dobInput.addEventListener('blur', function (event) {
      event.preventDefault();
      element = event.target;
      let dob = element.value;
      let input = element.dataset.input;
      let warningTitle = element.dataset.invalidDobTitle;
      let warningText;

      if ((dob || input.length > 0) && (dob.length < 10 || isNaN(Date.parse(dob)))) {
        warningText = element.dataset.invalidDobBody;
      } else if (Date.parse(dob) > Date.parse(element.max)) {
        warningText = element.dataset.invalidDobAfter;
      } else if (Date.parse(dob) < Date.parse(element.min)) {
        warningText = element.dataset.invalidDobBefore;
      }

      if (!warningText) return;
      swal({
        title: warningTitle,
        text: warningText,
        icon: 'warning'
      });
      element.value = '';
      element.dataset.input = "";
    });
  }
}

function checkKeyValue() {
  const npnInput = document.getElementById('inputNPN');

  if (npnInput) {
    npnInput.addEventListener('keypress', function (event) {
      const isRegistryEnabled =
        npnInput.dataset.enrollRegistryFeatureEnabled === 'true';

      if (isRegistryEnabled) {
        isAlphaNumeric(event);
      } else {
        isNumberKey(event);
      }
    });
  }
}

function numKey() {
  const phoneNum = $('[data-phone-number]');

  if (phoneNum.data('phoneNumber') === true) {
    phoneNum.on('keypress', function (event) {
      isNumberKey(event);
    });
  }
}
