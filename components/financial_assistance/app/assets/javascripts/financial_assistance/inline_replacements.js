function init_faa_immigration_doc_fields() {
  $(document).ready(function(){
    if ($("[data-vlp-doc-subject]").length) {
      showOnly($("[data-vlp-doc-subject]").data('vlp-doc-subject'));
    }
  });
}


function init_faa_dependent_form() {
  // components/financial_assistance/app/views/financial_assistance/applicants/_dependent_form.html.erb
  var bs4 = document.documentElement.dataset.bs4
  var immigrationDocWarning = immigrationDocWarning || false;

  if (bs4) {
    function disableButton(button) {
      button.attr('disabled', 'disabled')
            .addClass('disabled');
    };

    function enableButton(button) {
      button.removeAttr('disabled')
            .removeClass('disabled');
    };

    $(document).ready(function() {
      $.inputMasks();
      $('.field_with_errors > *').unwrap();
      // enable confirm member button
      enableButton($('#confirm-dependent'));

      $('#applicant_same_with_primary').click(function(){
        if($(this).is(':checked')){
            $('#applicant-home-address-area').addClass("hidden");
        } else {
            $('#applicant-home-address-area').removeClass("hidden");
        }
      });

      $("#dependent_first_name").change(function() {
        var text = $("#dependent_first_name").val() == '' ? "This person" : $("#dependent_first_name").val()
        $("#is_applying_coverage_value_dep").text("Does "+ text +" need coverage? *");
        $("#is_applying_coverage_value_dep_1").text(text);
      });
    });

    $(document).off('click', '#confirm-dependent');
    $(document).on('click', '#confirm-dependent', function(e) {
      const $button = $(this);
      e.preventDefault();
      // disable confirm member button
      disableButton($button);
      // submit the form
      submitForm();

      function submitForm() {
        if ($("input#applicant_same_with_primary").is(":checked")) {
          $("#dependent-address input.required, dependent-address select.required, #dependent-address .address_required").removeAttr('required');
        } else {
          $("#dependent-address input.required, dependent-address select.required, #dependent-address .address_required").attr('required', true);
        }

        // addressChange pop up Confirmation button
        enableButton($(".btn-confirmation"));

        var form = $('#new_applicant')[0] || $('#new_dependent')[0] || $('#edit_dependent')[0];

        if (!$("input#applicant_same_with_primary").is(":checked")) {
          $('#addressChangeConfirmation')
            .modal({
              show: true,
              backdrop: false
            })
            .on('hidden.bs.modal', function (e) {
              enableButton($button);
            });
        } else {
          PersonValidations.manageRequiredValidations($('#confirm-dependent'));
        }

        // enable confirm member button
        if (!form.checkValidity()){
          enableButton($button);
       }
       if (!$('#showWarning').hasClass('hidden')) {
        if (!immigrationDocWarning) {
          immigrationDocWarning = true;
          enableButton($button);
        }
       }
      }
    });
  } else {
    $(document).ready(function() {
        $.inputMasks();

        $('.field_with_errors > *').unwrap();
        Freebies.floatlabels();
        if($("input#applicant_same_with_primary").is(":checked")){
            $("#dependent-address input, dependent-address select").removeAttr('required');
        };
        $("#dependent_first_name").change(function() {
            var text = $("#dependent_first_name").val() == '' ? "this person" : $("#dependent_first_name").val()
            $("#is_applying_coverage_value_dep").text("Does "+ text +" need coverage? *");
            $("#is_applying_coverage_value_dep_1").text(text);
        });
    });

    function confirmMember(element) {
      const form = element.closest('form')[0];
      const maleRadio = document.getElementById('radio_male');
      const femaleRadio = document.getElementById('radio_female');
      const confirmButtonText = "<%= l10n('confirm_member') %>";
      const applicantSSN = document.getElementById('applicant_ssn')
      const applicantNoSSN = document.getElementById('applicant_no_ssn')

      element.addClass("disabled");

      ApplicantValidations.manageRequiredValidations(element);

      if (!form.checkValidity() || !isGenderSelected(maleRadio, femaleRadio) || !isSsnSelected(applicantSSN, applicantNoSSN)) {
        element.removeClass("disabled");
      }
    }

    function isGenderSelected(maleRadio, femaleRadio) {
      return (maleRadio && maleRadio.checked) || (femaleRadio && femaleRadio.checked);
    }

    function isSsnSelected(applicantSSN, applicantNoSSN) {
      return (applicantSSN && applicantSSN.value.replace(/-/g, '').length == 9) || (applicantNoSSN && applicantNoSSN.checked);
    }

    $(document).on('click', '.applicant-confirm-member', function() {
      confirmMember($(this))
    })
  }
}
