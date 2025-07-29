function isApplyingCoverage(target){
  fields = "input[name='" + target + "[is_applying_coverage]']"
  $("#employer-coverage-msg").hide();
  $("#ssn-coverage-msg").hide();
  if ($(fields).length > 0){
    addEventOnNoSsn(target);
    addEventOnSsn(target);
    if ($(fields).not(":checked").val() == "true"){
      $('.consumer_fields_for_applying_coverage').hide();
      $("#employer-coverage-msg").show();
      if ($("input[name='" + target + "[ssn]']").val() == '' && !$("input[name='" + target + "[no_ssn]']").is(":checked")){
        $("#ssn-coverage-msg").show();
      }
    }
    $(fields).change(function () {
      resetFormFields();
      if ($(fields).not(":checked").val() == "true"){
        $('.consumer_fields_for_applying_coverage').hide();
        $("#employer-coverage-msg").show();
        if ($("input[name='" + target + "[ssn]']").val() == '' && !$("input[name='" + target + "[no_ssn]']").is(":checked")){
          $("#ssn-coverage-msg").show();
        }
      } else {
        $('.consumer_fields_for_applying_coverage').show();
        $("#employer-coverage-msg").hide();
        $("#ssn-coverage-msg").hide();
      }
    });
  }
}

function resetFormFields() {
  // Set radio buttons to unchecked
  $('#is_incarcerated_true').prop('checked', false);
  $('#is_incarcerated_false').prop('checked', false);
}

function addEventOnNoSsn(target){
  $("input[name='" + target + "[no_ssn]']").change(function() {
    if ($(this).is(":checked")) {
       $("#ssn-coverage-msg").hide();
    } else if ($("input[name='" + target + "[ssn]']").val() == '' && $("input[name='" + target + "[is_applying_coverage]']").not(":checked").val() == "true"){
        $("#ssn-coverage-msg").show();
    }
  });
}

function addEventOnSsn(target){
  $("input[name='" + target + "[ssn]']").keyup(function() {
    if ($(this).val() != '') {
       $("#ssn-coverage-msg").hide();
    } else if ( !$("input[name='" + target + "[no_ssn]']").is(":checked") && $("input[name='" + target + "[is_applying_coverage]']").not(":checked").val() == "true"){
        $("#ssn-coverage-msg").show();
    }
  });
}

function applyFaaListenersFor(target) {
  // target is applicant or dependent
  $("input[name='" + target + "[us_citizen]']").change(function() {
    $('#vlp_documents_container').hide();
    $('#vlp_documents_container .vlp_doc_area').html("");
    $("input[name='" + target + "[naturalized_citizen]']").prop('checked', false);
    $("input[name='" + target + "[eligible_immigration_status]']").prop('checked', false);
    if ($(this).val() == 'true') {
      $('#naturalized_citizen_container').show();
      $('#immigration_status_container').hide();
      $("#" + target + "_naturalized_citizen_true").prop('required');
      $("#" + target + "_naturalized_citizen_false").prop('required');
    } else {
      $('#naturalized_citizen_container').hide();
      $('#immigration_status_container').show();
      $("#" + target + "_naturalized_citizen_true").removeAttr('required');
      $("#" + target + "_naturalized_citizen_false").removeAttr('required');
    }
  });

  $("input[name='" + target + "[naturalized_citizen]']").change(function() {
    var selected_doc_type = $('#naturalization_doc_type').val();
    if ($(this).val() == 'true') {
      $('#vlp_documents_container').show();
      $('#naturalization_doc_type_select').show();
      $('#immigration_doc_type_select').hide();
      showOnly(selected_doc_type);
    } else {
      $('#vlp_documents_container').hide();
      $('#naturalization_doc_type_select').hide();
      $('#immigration_doc_type_select').hide();
      $('#vlp_documents_container .vlp_doc_area').html("");
    }
  });

  $("input[name='" + target + "[eligible_immigration_status]']").change(function() {
    var selected_doc_type = $('#immigration_doc_type').val();
    if ($(this).val() == 'true' && this.checked) {
      $('#vlp_documents_container').show();
      $('#naturalization_doc_type_select').hide();
      $('#immigration_doc_type_select').show();
      showOnly(selected_doc_type);
    } else {
      $('#vlp_documents_container').hide();
      $('#naturalization_doc_type_select').hide();
      $('#immigration_doc_type_select').hide();
      $('#vlp_documents_container .vlp_doc_area').html("");
    }
  });

  //start tribe option controls
  $("input[name='" + target + "[indian_tribe_member]']").change(function() {
    if (this.value === 'true') {
      $('.tribal-container').removeClass('hide');
    } else {
      $('.tribal-container').addClass('hide');
    }
  });

  $('select#tribal-state').change(function() {
    if ($('.featured_tribes_selection').length > 0 && this.value == $('#enroll_state_abbr').val()) {
      $('.featured-tribe-container').removeClass('hide');
      var tribe_codes_array = $('.tribe_codes:checked').map(function(){ return $(this).val(); }).get();
      if (tribe_codes_array.includes("OT")){
        $('.tribal-name-container').removeClass('hide');
      } else {
        $('.tribal-name-container').addClass('hide');
      }
    } else {
      $('.tribal-name-container').removeClass('hide');
      $('.featured-tribe-container').addClass('hide');
    }
  });

  $("input#" + target + "_tribe_codes_ot").change(function() {
    if (this.checked){
      $('.tribal-name-container').removeClass('hide');
    } else {
      $('.tribal-name-container').addClass('hide');
    }
  });
  //end tribe option controls
}

function showOnly(selected) {
  if (selected == '' || selected == undefined) {
    return false;
  }

  var vlp_doc_map = {
    "Certificate of Citizenship": "citizenship_cert_container",
    "Naturalization Certificate": "naturalization_cert_container",
    "I-327 (Reentry Permit)": "immigration_i_327_fields_container",
    "I-551 (Permanent Resident Card)": "immigration_i_551_fields_container",
    "I-571 (Refugee Travel Document)": "immigration_i_571_fields_container",
    "I-766 (Employment Authorization Card)": "immigration_i_766_fields_container",
    "Machine Readable Immigrant Visa (with Temporary I-551 Language)": "machine_readable_immigrant_visa_fields_container",
    "Temporary I-551 Stamp (on passport or I-94)": "immigration_temporary_i_551_stamp_fields_container",
    "I-94 (Arrival/Departure Record)": "immigration_i_94_fields_container",
    "I-94 (Arrival/Departure Record) in Unexpired Foreign Passport": "immigration_i_94_2_fields_container",
    "Unexpired Foreign Passport": "immigration_unexpired_foreign_passport_fields_container",
    "I-20 (Certificate of Eligibility for Nonimmigrant (F-1) Student Status)": "immigration_temporary_i_20_stamp_fields_container",
    "DS2019 (Certificate of Eligibility for Exchange Visitor (J-1) Status)": "immigration_DS_2019_fields_container",
    "Other (With Alien Number)": "immigration_other_with_alien_number_fields_container",
    "Other (With I-94 Number)": "immigration_other_with_i94_fields_container"
  };

  var vlp_doc_target = vlp_doc_map[selected];
  $(".vlp_doc_area").html("<span>waiting...</span>");
  var target_id = $('input#vlp_doc_target_id').val();
  var target_type = $('input#vlp_doc_target_type').val();
  var target_url = $('input#vlp_doc_target_url').val();
  var bs4 = document.documentElement.dataset.bs4;
  $.ajax({
    type: "get",
    url: target_url,
    dataType: 'script',
    data: {
      'target_id': target_id,
      'target_type': target_type,
      'vlp_doc_target': vlp_doc_target,
      'vlp_doc_subject': selected,
      bs4: bs4,
    },
  });
}

function changeApplyingCoverageText() {
  $('#applicant_first_name').change(function() {
    var text = $('#applicant_first_name').val() == '' ? 'this person' : $('#applicant_first_name').val()
    $('#is_applying_coverage_value_dep').text('Does '+ text +' need coverage? *');
  });
}

function applyFaaListeners() {
  if ($("form.new_applicant, form.edit_applicant").length > 0) {
    applyFaaListenersFor("applicant");
  }

  $("#naturalization_doc_type").change(function() {
    showOnly($(this).val());
  });

  $("#immigration_doc_type").change(function() {
    showOnly($(this).val());
  });

  var immigrationDocType = $('#immigration_doc_type');
  if (immigrationDocType.length > 0 && immigrationDocType.is(':visible')) {
    var selected_doc_type = $('#immigration_doc_type').val();
    $('#vlp_documents_container').show();
    $('#naturalization_doc_type_select').show();
    $('#immigration_doc_type_select').hide();
    showOnly(selected_doc_type);
  }
}

var ApplicantValidations = (function(window, undefined) {

  function manageRequiredValidations(this_obj) {
    var hidden_requireds = $('[required]').not(":visible");
    $('[required]').not(":visible").removeAttr('required');
    this_obj.closest('div').find('button[type="submit"]').trigger('click');
  }

  function resetConfirmButton() {
    var btn = document.querySelector('.applicant-confirm-member');
    if (btn) {
      btn.textContent = 'Confirm Member';
      btn.classList.remove('disabled');
    }
  }

  function restoreRequiredAttributes(e) {
    e.preventDefault && e.preventDefault();
    var hidden_requireds = $('[required]').not(":visible");
    hidden_requireds.each(function(index) {
      $(this).prop('required', true);
    });
  }

  function customValidityWithChangeEvent(element, message) {
    // Set custom validity on all radio buttons in the group
    element.each(function() {
      this.setCustomValidity(message);
    });

    // One-time setup for the change event (if not already bound)
    if (!element.data('validationBound')) {
      element.data('validationBound', true);
      element.on('change', function() {
        // Clear the validity message on all radios in the group when any one changes
        element.each(function() {
          this.setCustomValidity('');
        });
      });
    }
  }

  function reportValidityForRadioGroup(element) {
    // Report validity on all radio buttons in the group
    element.each(function() {
      this.reportValidity();
    });
  }

  function validationForUsCitizenOrUsNational(e) {
    if ($('input[name="applicant[is_applying_coverage]"]').length > 0 && $('input[name="applicant[is_applying_coverage]"]').not(":checked").val() == "true"){
      return true;
    }
    if ($('input[name="applicant[us_citizen]"]').not(":checked").length == 2) {
      var usCitizenRadios = $('input[name="applicant[us_citizen]"]');
      customValidityWithChangeEvent(usCitizenRadios, "Please provide an answer for question: Are you a US Citizen or US National?")
      ApplicantValidations.restoreRequiredAttributes(e);
      reportValidityForRadioGroup(usCitizenRadios)
      return false;
    }

    return true;
  }

  function validationForIndianTribeMember(e) {
    if ($('#indian_tribe_area').length == 0){
      return false;
    }

    $('.close').click(function() {
      $('#tribal-id-alert').addClass('hide');
      $('#tribal-state-alert').addClass('hide');
      $('#tribal-name-alert').addClass('hide');
    });

    if ($('input[name="applicant[is_applying_coverage]"]').length > 0
    && $('input[name="applicant[is_applying_coverage]"]').not(":checked").val() == "true"){
      return true;
    }

    var tribe_member_yes = $("input#indian_tribe_member_yes").is(':checked');
    var tribe_member_no = $("input#indian_tribe_member_no").is(':checked');

    if (!tribe_member_yes && !tribe_member_no){
      var indianTribeMemberRadios = $('input[name="applicant[indian_tribe_member]"]');
      customValidityWithChangeEvent(indianTribeMemberRadios, "Please select the option for 'Are you a member of an American Indian or Alaska Native Tribe?'")
      ApplicantValidations.restoreRequiredAttributes(e);
      reportValidityForRadioGroup(indianTribeMemberRadios)
      return false;
    }

    if (tribe_member_no){
      $('#tribal-state').val("");
      $('input#tribal-name').val("");
      $('#tribal-id').val("");
      $('.tribe_codes:checked').removeAttr('checked');
    }

    if (tribe_member_yes){
      if ($('#tribal-state').length > 0 && $('#tribal-state').val() == ""){
        resetConfirmButton();
        $('#tribal-state-alert').show();
        ApplicantValidations.restoreRequiredAttributes(e);
      }

      if ($('.featured_tribes_selection').length > 0 && $('#tribal-state').val() == $('#enroll_state_abbr').val()){
        var tribe_codes_array = $('.tribe_codes:checked').map(function(){ return $(this).val(); }).get();
        if (tribe_codes_array.length < 1) {
          var tribeCodesboxes = $('input[name="applicant[tribe_codes][]"]');
          customValidityWithChangeEvent(tribeCodesboxes, "At least one tribe must be selected.")
          ApplicantValidations.restoreRequiredAttributes(e);
          tribeCodesboxes[1].reportValidity();
          return false;
        }

        if (tribe_codes_array.includes("OT") && $('input#tribal-name').val() == ""){
            var tribalNametext = $('input[name="applicant[tribal_name]"]');
            customValidityWithChangeEvent(tribalNametext, "Please provide an answer for 'Other' tribe name.")
            ApplicantValidations.restoreRequiredAttributes(e);
            tribalNametext[0].reportValidity();
            return false;
        }

        if (!tribe_codes_array.includes("OT")){
          $('input#tribal-name').val("");
        }
      }
      else if ($('input#tribal-name').val() == ""){
          $('#tribal-name-alert').show();
          ApplicantValidations.restoreRequiredAttributes(e);
      }

      if ($('#tribal-id').length > 0 && $('#tribal-id').val().length != 9){
        resetConfirmButton();
        $('#tribal-id-alert').show();
        ApplicantValidations.restoreRequiredAttributes(e);
      }
    }
  }

  function validationForIncarcerated(e) {
    if ($('input[name="applicant[is_applying_coverage]"]').length > 0 && $('input[name="applicant[is_applying_coverage]"]').not(":checked").val() == "true"){
      return true;
    }
    if ($('input[name="applicant[is_incarcerated]"]').not(":checked").length == 2) {
      var incarceratedRadios = $('input[name="applicant[is_incarcerated]"]');
      customValidityWithChangeEvent(incarceratedRadios, 'Please provide an answer for question: Are you currently incarcerated?')
      ApplicantValidations.restoreRequiredAttributes(e);
      reportValidityForRadioGroup(incarceratedRadios)
      return false;
    }
    return true;
  }

  function validationForNaturalizedCitizen(e) {
    if ($('input[name="applicant[is_applying_coverage]"]').length > 0 && $('input[name="applicant[is_applying_coverage]"]').not(":checked").val() == "true"){
      return true;
    }
    if ($('#naturalized_citizen_container').is(':visible') && $('input[name="applicant[naturalized_citizen]"]').not(":checked").length == 2) {
      var naturalizedRadios = $('input[name="applicant[naturalized_citizen]"]');
      customValidityWithChangeEvent(naturalizedRadios, 'Please provide an answer for question: Are you a naturalized citizen?')
      ApplicantValidations.restoreRequiredAttributes(e);
      reportValidityForRadioGroup(naturalizedRadios)
      return false;
    }
    return true;
  }

  function validationForEligibleImmigrationStatuses(e) {
    if ($('#immigration_status_container').is(':visible') && $('input[name="applicant[eligible_immigration_status]"]').not(":checked").length == 2 && !$('#immigration-checkbox').is(':visible')) {
      resetConfirmButton();
      alert('Please provide an answer for question: Do you have eligible immigration status?');
      ApplicantValidations.restoreRequiredAttributes(e);
    }
  }

  function validationForPersonOrDependent() {
    const immigration_field =
      document.getElementById('immigration_doc_type').value == '';
    if (!document.getElementById('dependent_ul') && immigration_field) {
      var us_citizen = document.getElementById('person_us_citizen_false') || document.getElementById('us_citizen_false');
      var naturalized_citizen = document.getElementById('person_naturalized_citizen_true') || document.getElementById('naturalized_citizen_true');
      return ( us_citizen.checked || naturalized_citizen.checked );
    } else if (immigration_field) {
      var us_citizen = document.getElementById('dependent_us_citizen_false') || document.getElementById('us_citizen_false');
      var naturalized_citizen = document.getElementById('dependent_naturalized_citizen_true') || document.getElementById('naturalized_citizen_true');
      return ( us_citizen.checked || naturalized_citizen.checked );
    }
  }

  function validationForDependentSSN(e) {
    var noSSNCheckbox = $("#dependent_no_ssn");
    var ssnField = $("#dependent_ssn");
  
    if (!noSSNCheckbox.length || !ssnField.length) {
      return true;
    }
    
    var dependentSSN = ssnField.val();
    var dependentNoSSN = noSSNCheckbox.is(':checked');
    
    if (dependentSSN == '' && !dependentNoSSN) {
      ssnField.off('change.validation');
      noSSNCheckbox.off('change.validation');
      
      customValidityWithChangeEvent(noSSNCheckbox, 'SSN is required');
      
      ssnField.on('change.validation', function() {
        customValidityWithChangeEvent(noSSNCheckbox, '');
      });
      ApplicantValidations.restoreRequiredAttributes(e);
      return false;
    }
    
    return true;
  }

  function validationForVlpDocuments(e) {
    if ($('#is_applying_coverage_true').prop('checked') && validationForPersonOrDependent()) {
      $('#showWarning').removeClass('hidden');
    }
    if ($('#vlp_documents_container').is(':visible')) {
      $('.vlp_doc_area input.doc_fields').each(function() {
        if ($(this).attr('placeholder') == 'Certificate Number') {
          if ($(this).val().length < 1) {
            if (!$('#showWarning').length) {
              alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
              ApplicantValidations.restoreRequiredAttributes(e);
            } else {
              $('#showWarning').removeClass('hidden');
            }
          }
        }
        if ($('#immigration_doc_type').val() == 'Naturalization Certificate' || $('#immigration_doc_type').val() == 'Certificate of Citizenship') {
        } else {
          if ($(this).attr('placeholder') == 'Alien Number') {
            if ($(this).val().length < 1) {
              if (!$('#showWarning').length) {
                alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
                ApplicantValidations.restoreRequiredAttributes(e);
              } else {
                $('#showWarning').removeClass('hidden');
              }
            }
          }
        }
        if ($(this).attr('placeholder') == 'Document Description') {
          if ($(this).val().length < 1) {
            if (!$('#showWarning').length) {
              alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
              ApplicantValidations.restoreRequiredAttributes(e);
            } else {
              $('#showWarning').removeClass('hidden');
            }
          }
        }
        if ($(this).attr('placeholder') == 'Card Number') {
          if ($(this).val().length < 1) {
            if (!$('#showWarning').length) {
              alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
              ApplicantValidations.restoreRequiredAttributes(e);
            } else {
              $('#showWarning').removeClass('hidden');
            }
          }
        }
        if ($(this).attr('placeholder') == 'Naturalization Number') {
          if ($(this).val().length < 1) {
            if (!$('#showWarning').length) {
              alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
              ApplicantValidations.restoreRequiredAttributes(e);
            } else {
              $('#showWarning').removeClass('hidden');
            }
          }
        }
        if ($('#immigration_doc_type').val() == 'I-20 (Certificate of Eligibility for Nonimmigrant (F-1) Student Status)' || $('#immigration_doc_type').val() == 'DS2019 (Certificate of Eligibility for Exchange Visitor (J-1) Status)' || $('#immigration_doc_type').val() == 'Temporary I-551 Stamp (on passport or I-94)' || $('#immigration_doc_type').val() == 'Other (With Alien Number)' || $('#immigration_doc_type').val() == 'Other (With I-94 Number)') {

        } else {
          if ($(this).attr('placeholder') == 'Passport Number') {
            if ($(this).val().length < 1) {
              if (!$('#showWarning').length) {
                alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
                ApplicantValidations.restoreRequiredAttributes(e);
              } else {
                $('#showWarning').removeClass('hidden');
              }
            }
          }
        }
        if ($(this).attr('placeholder') == 'I-766 Expiration Date') {
          if ($(this).val().length != 10) {
            if (!$('#showWarning').length) {
              alert('Please fill in your information for ' + $(this).attr('placeholder') + ' with a MM/DD/YYYY format.');
              ApplicantValidations.restoreRequiredAttributes(e);
            } else {
              $('#showWarning').removeClass('hidden');
            }
          }
        }
//        if ($(this).attr('placeholder') == 'I-94 Expiration Date') {
//          if ($(this).val().length != 10) {
//            alert('Please fill in your information for ' + $(this).attr('placeholder') + ' with a MM/DD/YYYY format.');
//            ApplicantValidations.restoreRequiredAttributes(e);
//
//          }
//        }
        if ($('#immigration_doc_type').val() == 'Unexpired Foreign Passport' || $('#immigration_doc_type').val() == 'I-94 (Arrival/Departure Record) in Unexpired Foreign Passport') {
          if ($(this).attr('placeholder') == 'Passport Expiration Date') {
            if ($(this).val().length != 10) {
              if (!$('#showWarning').length) {
                alert('Please fill in your information for ' + $(this).attr('placeholder') + ' with a MM/DD/YYYY format.');
                ApplicantValidations.restoreRequiredAttributes(e);
              } else {
                $('#showWarning').removeClass('hidden');
              }
            }
          }
        }
        if ($('#immigration_doc_type').val() == 'Unexpired Foreign Passport' || $('#immigration_doc_type').val() == 'I-20 (Certificate of Eligibility for Nonimmigrant (F-1) Student Status)' || $('#immigration_doc_type').val() == 'DS2019 (Certificate of Eligibility for Exchange Visitor (J-1) Status)') {
        } else {
          if ($(this).attr('placeholder') == 'I 94 Number') {
            if ($(this).val().length < 1) {
              if (!$('#showWarning').length) {
                alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
                ApplicantValidations.restoreRequiredAttributes(e);
              } else {
                $('#showWarning').removeClass('hidden');
              }
            }
          }
        }

        if ($('#immigration_doc_type').val() == 'I-20 (Certificate of Eligibility for Nonimmigrant (F-1) Student Status)' || $('#immigration_doc_type').val() == 'DS2019 (Certificate of Eligibility for Exchange Visitor (J-1) Status)') {
          if ($(this).attr('placeholder') == 'SEVIS ID') {
            if ($(this).val().length < 1) {
              if (!$('#showWarning').length) {
                alert('Please fill in your information for ' + $(this).attr('placeholder') + '.');
                ApplicantValidations.restoreRequiredAttributes(e);
              } else {
                $('#showWarning').removeClass('hidden');
              }
            }
          }
        }
      });
    }
  }

  // explicitly return public methods when this object is instantiated
  return {
    manageRequiredValidations: manageRequiredValidations,
    validationForUsCitizenOrUsNational: validationForUsCitizenOrUsNational,
    validationForNaturalizedCitizen: validationForNaturalizedCitizen,
    validationForEligibleImmigrationStatuses: validationForEligibleImmigrationStatuses,
    validationForVlpDocuments: validationForVlpDocuments,
    validationForIncarcerated: validationForIncarcerated,
    validationForIndianTribeMember: validationForIndianTribeMember,
    validationForDependentSSN: validationForDependentSSN,
    restoreRequiredAttributes: restoreRequiredAttributes
  };

})(window);

function applicantDemographicValidations() {
  applyFaaListeners();

  $('form.new_applicant, form.edit_applicant').submit(function(e) {
    ApplicantValidations.validationForUsCitizenOrUsNational(e);
    ApplicantValidations.validationForNaturalizedCitizen(e);
    ApplicantValidations.validationForEligibleImmigrationStatuses(e);
    ApplicantValidations.validationForIndianTribeMember(e);
    ApplicantValidations.validationForIncarcerated(e);
    ApplicantValidations.validationForDependentSSN(e);
    ApplicantValidations.validationForVlpDocuments(e);
    if ($('#showWarning').length && !$('#showWarning').hasClass('hidden') && !$('#showWarning').hasClass('shown')) {
      var btn = document.querySelector('.applicant-confirm-member');
      if (btn) {
        btn.textContent = 'Confirm Member';
        btn.classList.remove('disabled');
      }
      $('#showWarning').addClass('shown');
      e.preventDefault();
      return false;
    }
  });

  isApplyingCoverage("applicant");
};
