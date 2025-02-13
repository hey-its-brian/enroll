//Clear filter selections on page refresh
window.addEventListener('load', function () {
  clearAll();
});

// Stores values to be processed on function filterResults
var filterParams = {
  selectedMetalLevels: new Array(),
  selectedPlanTypes: new Array(),
  selectedPlanNetworks: new Array(),
  selectedCarrier: new String(),
  selectedHSA: new String(),
  selectedOSSE: new String(),
  premiumFromAmountValue: new String(),
  premiumToAmountValue: new String(),
  deductibleFromAmountValue: new String(),
  deductibleToAmountValue: new String(),
};

function filterMetalLevel(element) {
  processValues(element);
}

function filterPlanType(element) {
  processValues(element);
}

function filterPlanNetwork(element) {
  processValues(element);
}

$(document).on('change', '.plan-carrier-selection-filter.v1-filter', function() { filterPlanCarriers(this) })

$(document).on('change', '.plan-hsa-eligibility-selection-filter.v1-filter', function() { filterHSAEligibility(this) })

$(document).on('change', '.plan-osse-eligibility-selection-filter.v1-filter', function() { filterOSSEEligibility(this) })

$(document).on('click', '.plan-type-selection-filter.checkbox-custom', function() { filterPlanType(this) })

$(document).on('click', '.plan-metal-network-selection-filter.checkbox-custom', function() { filterPlanNetwork(this) })

$(document).on('blur', '#premium_min', function() { premiumFromAmount(this) })
$(document).on('input', '#premium_min', function() { toCurrency(this) })

$(document).on('blur', '#premium_max', function() { premiumToAmount(this) })
$(document).on('input', '#premium_max', function() { toCurrency(this) })

$(document).on('blur', '#deductible_min', function() { deductibleFromAmount(this) })
$(document).on('input', '#deductible_min', function() { toCurrency(this) })

$(document).on('blur', '#deductible_max', function() { deductibleToAmount(this) })
$(document).on('input', '#deductible_max', function() { toCurrency(this) })


function filterPlanCarriers(element) {
  filterParams.selectedCarrier = element.value;
}

function filterHSAEligibility(element) {
  filterParams.selectedHSA = element.value;
}

function filterOSSEEligibility(element) {
  filterParams.selectedOSSE = element.value;
}

function premiumFromAmount(element) {
  filterParams.premiumFromAmountValue = element.value;
}

function premiumToAmount(element) {
  filterParams.premiumToAmountValue = element.value;
}

function deductibleFromAmount(element) {
  filterParams.deductibleFromAmountValue = element.value;
}

function deductibleToAmount(element) {
  filterParams.deductibleToAmountValue = element.value;
}
// Passes values from inputs and passes to array
function processValues(element) {
  if (element.checked) {
    var dataType = element.dataset.category;

    if (dataType == 'planMetalLevel') {
      filterParams.selectedMetalLevels.push(element.dataset.planMetalLevel);
    }
    if (dataType == 'planType') {
      filterParams.selectedPlanTypes.push(element.dataset.planType);
    }
    if (dataType == 'planNetwork') {
      filterParams.selectedPlanNetworks.push(element.dataset.planNetwork);
    }
  } else if (!element.checked) {
    var dataType = element.dataset.category;

    if (dataType == 'planMetalLevel') {
      index = filterParams.selectedMetalLevels.indexOf(
        element.dataset.planMetalLevel
      );
      removeItems(filterParams.selectedMetalLevels, index);
    }
    if (dataType == 'planType') {
      index = filterParams.selectedPlanTypes.indexOf(element.dataset.planType);
      removeItems(filterParams.selectedPlanTypes, index);
    }
    if (dataType == 'planNetwork') {
      index = filterParams.selectedPlanNetworks.indexOf(
        element.dataset.planNetwork
      );
      removeItems(filterParams.selectedPlanNetworks, index);
    }
  }
}

function clearAll() {
  // Clears all checkboxes within #filter-sidebar only
  var inputs = document.querySelectorAll(
    '#filter-sidebar .filter-input-block input'
  );
  for (var i = 0; i < inputs.length; i++) {
    inputs[i].checked = false;
    inputs[i].value = '';
  }

  // Clear stored values
  filterParams.selectedMetalLevels = [];
  filterParams.selectedPlanTypes = [];
  filterParams.selectedPlanNetworks = [];
  filterParams.selectedCarrier = '';
  filterParams.selectedHSA = '';
  filterParams.selectedOSSE = '';
  filterParams.premiumFromAmountValue = '';
  filterParams.premiumToAmountValue = '';
  filterParams.deductibleFromAmountValue = '';
  filterParams.deductibleToAmountValue = '';
}

$(document).on('click', '.apply-filters-btn', function(e) {
  e.preventDefault()
  filterResults()
})

// Gets the filtered Results
function filterResults() {
  filterResultsSelections(filterParams);
}

// Removes an item from array
function removeItems(arr, index) {
  arr.splice(index, 1);
}
