$(document).on('click', '.select-assister-agency', function(e) {
  e.preventDefault()
  selectAssisterAgency(this);
})

$(document).on('click', '.aa-search-btn', function(e) {
  e.preventDefault()
  assisterSearch();
  return false
})

function assisterSearch() {
  var assister_agency_search = document.getElementById('staff_agency_search').value
  var assister_registration_page = document.getElementById('staff_is_assister_registration_page').value
  document.getElementById('assister-staff-btn').disabled = true;
  if (assister_agency_search != undefined) {
      $.ajax({
        url: '/benefit_sponsors/profiles/assister_agencies/assister_agency_staff_roles/search_assister_agency.js',
        type: "GET",
        data: {'q': assister_agency_search, "assister_registration_page": assister_registration_page},
        success: function() {
          if ($('.table-responsive').length) {
            $('.assister-agency-submit').removeClass('hidden');
          }
        }
      });
  };
}

function selectAssisterAgency(element) {
  var result = document.querySelectorAll('.result');
  result.forEach(function (result) {
    var element = result.querySelectorAll('.staff-select-assister')
    element.forEach(function (ele) {
        ele.classList.remove("agency-selected");
    })
  });
  document.getElementById('staff_profile_id').value = element.dataset.assister_agency_profile_id;
  element.closest(".staff-select-assister").classList.add('agency-selected')
  document.getElementById('assister-staff-btn').disabled = false;
}
