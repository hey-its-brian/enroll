function enableOrDisableSubmitButton() {
  if ($('#person_max_aptc').val() != '' && $('#person_csr').val() != '' && $('#jq_datepicker_ignore_person_effective_date').val() != '') {
    $('#create_eligibility').prop('disabled', false);
  }
  else {
    $('#create_eligibility').prop('disabled', true);
  }
}

$(document).on('keyup', "#person_max_aptc", function() {
  enableOrDisableSubmitButton();
});

$(document).on('change', "#person_csr, #jq_datepicker_ignore_person_effective_date", function() {
  enableOrDisableSubmitButton();
});



// sep_histroy_display.html.erb
$(document).on('click', '.sep-history-chevron', function() {
  addStyleToPanel($(this).data('fid'))
})

function addStyleToPanel(id) {
  var bs4 = document.documentElement.dataset.bs4;
  var ele = $('#viewSepPanel_'+id)
  var another = $('.add-default-class-'+id)
  var heading_elem = $('.sep-heading-'+id)
  if (ele.attr('aria-expanded') === 'false') {
    another.addClass('panel panel-default')
    ele.addClass('panel-heading')
    if (!bs4) {
      heading_elem.addClass('font-weight-bold')
    }
  }else {
    ele.removeClass('panel-heading')
    another.removeClass('panel panel-default')
    heading_elem.removeClass('font-weight-bold')
  }
}



// _new_secure_message.html.erb
$(document).on('click', '#send_secure_message', function(e) {
  var file_value = $('#file')[0].value;
  $(".btn-confirmation").removeAttr('disabled');

  if (file_value != "") {
    $('#body').attr('required', false)
  }

  if ( $('#secure_message_form')[0].checkValidity() ) {
    $('#sendSecure').modal('show')
  }
});

function confirmSecureMsg(event){
  $(".btn-confirmation").prop('disabled', true);

  event.preventDefault();
  event.stopImmediatePropagation();

  $('.modal-backdrop').removeClass('modal-backdrop');
  $('.modal-open').removeClass('modal-open');

  var formData = new FormData($('#secure_message_form')[0]);

  $.ajax({
    url: '/exchanges/hbx_profiles/create_send_secure_message.js',
    type: "POST",
    data : formData,
    contentType: false,
    processData: false,
  });
}

$(document).on('click', '.btn-confirmation.send-secure-msg-confirm', function() {
    confirmSecureMsg(event);
    return false;
});

$(document).on('submit', '#secure_message_form', function(e) {
    return false;
});

$(document).on('click', '#secureMessageFormClose', function(e) {
  $(this).closest('tr').remove();
});
