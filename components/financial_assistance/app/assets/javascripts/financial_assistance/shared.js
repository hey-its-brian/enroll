function getDateFieldDate(id) {
  const dateValue = $(id).val();
  return dateValue ? new Date(dateValue) : null;
};

function validateDateWarnings(id) {
  var useBs4 = document.documentElement.dataset.bs4
  const startDateId = "#start_on_" + id;
  const endDateId = ("#end_on_" + id);
  var startDate = useBs4 ? getDateFieldDate(startDateId) : $(startDateId).datepicker('getDate');
  var endDate = useBs4 ? getDateFieldDate(endDateId) : $(endDateId).datepicker('getDate');
  var today = new Date();
  var requiresStartDateWarning = startDate > today
  var requiresEndDateWarning = endDate
  var warning_div = $("#date_warning_message_" + id);
  var startDateWarning = $("#start_date_warning_" + id)
  var endDateWarning = $("#end_date_warning_" + id)

  warning_div.add(startDateWarning).add(endDateWarning).addClass('hidden');
  if (requiresStartDateWarning) warning_div.add(startDateWarning).removeClass('hidden');
  if (requiresEndDateWarning) warning_div.add(endDateWarning).removeClass('hidden');
};

$(document).on('change', "[data-validate-date-id]", function() {
  let id = $(this).data('validate-date-id')
  let bs4 = $(this).data('use-bs4')
  if (id.length) {
    validateDateWarnings(id, bs4)
  }
})
