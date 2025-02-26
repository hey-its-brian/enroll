/// components/benefit_sponsors/app/views/benefit_sponsors/profiles/assister_agencies/assister_agency_staff_roles/_new_staff_applicant.html.erb

$(document).on('turbolinks:load ajax:success', function () {
  validateAjaxForm();
});

function assisterSearch() {
  var assister_agency_search = document.getElementById('staff_agency_search').value;
  var assister_registration_page = document.getElementById('staff_is_assister_registration_page').value;
  document.getElementById('assister-staff-btn').disabled = true;
  if (assister_agency_search != undefined) {
    $.ajax({
      url: '/benefit_sponsors/profiles/assister_agencies/assister_agency_staff_roles/search_assister_agency.js',
      type: "GET",
      data: {'q': assister_agency_search, "assister_registration_page": assister_registration_page}
    });
  }
}

function selectAssisterAgency(element) {
  var result = document.querySelectorAll('.result');
  result.forEach(function (result) {
    var elements = result.querySelectorAll('.staff-select-assister');
    elements.forEach(function (ele) {
      ele.classList.remove("agency-selected");
    });
  });
  document.getElementById('staff_profile_id').value = element.dataset.assister_agency_profile_id;
  element.closest(".staff-select-assister").classList.add('agency-selected');
  document.getElementById('assister-staff-btn').disabled = false;
}

$(document).on('click', 'a.select-assister-agency', function () {
  if ($('.table-responsive').length) {
    $('.assister-agency-submit').removeClass('hidden');
  }
});

function allowAssisterAgencyFormSubmission() {
  var assister_attestation_fields = document.getElementsByClassName('assister-attestation-field');
  var form_button = document.getElementById('assister-btn');
  if (
    Array.from(assister_attestation_fields).every(
      (form_element) => form_element.checked == true
    ) == true
  ) {
    form_button.disabled = false;
  } else {
    form_button.disabled = true;
  }
}

$(function () {
  $('.assister-attestation-field').on('change', function () {
    allowAssisterAgencyFormSubmission();
  });
});