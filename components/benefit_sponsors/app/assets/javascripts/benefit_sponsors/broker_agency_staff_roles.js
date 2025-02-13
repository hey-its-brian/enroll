$(document).on('click', '.select-broker-agency', function(e) {
  e.preventDefault()
  selectBrokereAgency(this);
})

$(document).on('click', '.ba-search-btn', function(e) {
  e.preventDefault()
  brokerSearch();
  return false
})

function brokerSearch() {
  var broker_agency_search = document.getElementById('staff_agency_search').value
  var broker_registration_page = document.getElementById('staff_is_broker_registration_page').value
  document.getElementById('broker-staff-btn').disabled = true;
  if (broker_agency_search != undefined) {
      $.ajax({
        url: '/benefit_sponsors/profiles/broker_agencies/broker_agency_staff_roles/search_broker_agency.js',
        type: "GET",
        data: {'q': broker_agency_search, "broker_registration_page": broker_registration_page},
        success: function() {
          if ($('.table-responsive').length) {
            $('.broker-agency-submit').removeClass('hidden');
          }
        }
      });
  };

}

function selectBrokereAgency(element) {
  var result = document.querySelectorAll('.result');
  result.forEach(function (result) {
      var element = result.querySelectorAll('.staff-select-broker')
      element.forEach(function (ele) {
          ele.classList.remove("agency-selected");
      })
  });
  document.getElementById('staff_profile_id').value = element.dataset.broker_agency_profile_id;
  element.closest(".staff-select-broker").classList.add('agency-selected')
    document.getElementById('broker-staff-btn').disabled = false;
}
