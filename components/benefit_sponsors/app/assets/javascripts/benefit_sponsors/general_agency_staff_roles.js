// components/benefit_sponsors/app/views/benefit_sponsors/profiles/general_agencies/general_agency_staff_roles/new.html.slim
$(document).on('click', '.ga-search-btn', function(e) {
  console.log('search clicked')
  e.preventDefault()
  generalAgencySearch();
  return false
})

function generalAgencySearch() {
  console.log('gaSearch')
  var general_agency_search = document.getElementById('staff_agency_search').value
  var general_agency_registration_page = document.getElementById('staff_is_general_agency_registration_page').value
  document.getElementById('general-agency-staff-btn').disabled = true;
  if (generalAgencySearch != undefined) {
      $.ajax({
        url: '/benefit_sponsors/profiles/general_agencies/general_agency_staff_roles/search_general_agency.js',
        type: "GET",
        data: {'q': general_agency_search, "general_agency_registration_page": general_agency_registration_page},
        success: function() { console.log('gasearch success') },
        error: function() { console.log('gasearch error') }
      });
  };

}

function selectGeneralAgency(element) {
  var result = document.querySelectorAll('.result');
  result.forEach(function (result) {
      var element = result.querySelectorAll('.select-ga')
      element.forEach(function (ele) {
          ele.classList.remove("agency-selected");
      })
  });
  document.getElementById('staff_profile_id').value = element.dataset.general_agency_profile_id;
  element.closest(".select-ga").classList.add('agency-selected')
    document.getElementById('general-agency-staff-btn').disabled = false;
}

// app/views/ui-components/v1/forms/general_agency_registration/_general_agency_staff_information.html.slim
$(document).on('blur', '#inputStaffDOB', function() {
  validDob(this)
})

function validDob(element) {
  if (element.value && element.value.length < 10) {
    swal({
      title: "Invalid DOB Format",
      text: "DOB must be entered as MM/DD/YYYY",
      icon: "warning"
    }),
    element.value = ''
  }
}

// components/benefit_sponsors/app/views/benefit_sponsors/profiles/general_agencies/general_agency_staff_roles/_search_general_agency.html.erb
$(document).on('click', '.select-general-agency', function(e) {
  e.preventDefault()
  selectGeneralAgency(this)
})
