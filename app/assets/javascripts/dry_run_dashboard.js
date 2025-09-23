document.addEventListener('DOMContentLoaded', function() {
  const endpoints = window.dryRunEndpoints;

  // Helper function to convert kebab-case to camelCase
  function camelCase(str) {
    return str.replace(/-([a-z])/g, function(match, group) {
      return group.toUpperCase();
    });
  }

  // Cache for API responses to avoid repeated calls during auto-refresh
  var responseCache = {};
  var cacheExpiry = 2 * 60 * 1000; // 2 minutes

  // Track all active requests to prevent duplicates
  var activeRequests = {};
  var requestCounter = 0;

  function makeAjaxCall(url, successCallback, errorCallback) {
    // Generate a unique request ID
    var requestId = ++requestCounter;

    // Check if there's an active request to the same URL
    if (activeRequests[url]) {
      return; // Skip this request
    }

    // Check cache first to avoid duplicate requests
    var now = new Date().getTime();
    if (responseCache[url] && now - responseCache[url].timestamp < cacheExpiry) {
      successCallback(responseCache[url].data);
      return;
    }

    // Mark this URL as having an active request
    activeRequests[url] = requestId;

    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.setRequestHeader('Accept', 'text/html');
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    // Add timeout for better performance
    xhr.timeout = 45000; // 45 seconds

    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4) {
        // Clear the active request tracking
        delete activeRequests[url];

        if (xhr.status === 200) {
          // Store response in cache
          responseCache[url] = {
            data: xhr.responseText,
            timestamp: new Date().getTime()
          };
          successCallback(xhr.responseText);
        } else {
          errorCallback('HTTP Error: ' + xhr.status);
        }
      }
    };

    xhr.ontimeout = function() {
      // Clear the active request tracking
      delete activeRequests[url];
      errorCallback('Request timed out after 45 seconds');
    };

    xhr.onerror = function() {
      // Clear the active request tracking
      delete activeRequests[url];
      errorCallback('Network error occurred');
    };

    xhr.send();
  }

  function showError(sectionName, errorMessage) {
    var loadingElement = document.getElementById(sectionName + '-loading');
    var contentElement = document.getElementById(sectionName + '-content');

    if (loadingElement) loadingElement.classList.add('d-none');
    if (contentElement) {
      // Clear existing content safely
      contentElement.textContent = '';

      // Create error alert element safely
      var alertDiv = document.createElement('div');
      alertDiv.className = 'alert alert-danger';

      var strongElement = document.createElement('strong');
      strongElement.textContent = 'Error: ';

      var errorText = document.createTextNode(errorMessage);

      alertDiv.appendChild(strongElement);
      alertDiv.appendChild(errorText);
      contentElement.appendChild(alertDiv);
      contentElement.classList.remove('d-none');
    }
  }

  function showContent(sectionName, htmlContent) {
    var loadingElement = document.getElementById(sectionName + '-loading');
    var contentElement = document.getElementById(sectionName + '-content');

    if (loadingElement) loadingElement.classList.add('d-none');
    if (contentElement) {
      // Clear existing content safely
      contentElement.textContent = '';

      // Parse HTML content safely using DOMParser to avoid XSS
      var parser = new DOMParser();
      var doc = parser.parseFromString(htmlContent, 'text/html');

      // Move all child nodes from the parsed document to our content element
      // Filter out script elements to prevent code execution
      var body = doc.body;
      if (body) {
        while (body.firstChild) {
          var node = body.firstChild;
          // Skip script elements to prevent XSS
          if (node.nodeType === Node.ELEMENT_NODE && node.tagName.toLowerCase() === 'script') {
            body.removeChild(node);
            continue;
          }
          contentElement.appendChild(node);
        }
      }

      contentElement.classList.remove('d-none');
    }
  }

  // Load Benefit Coverage
  function loadBenefitCoverage(callback) {
    if (!endpoints.benefitCoverage) {
      if (callback) callback();
      return;
    }

    makeAjaxCall(endpoints.benefitCoverage, function(htmlContent) {
      showContent('benefit-coverage', htmlContent);
      if (callback) callback();
    }, function(error) {
      showError('benefit-coverage', error);
      if (callback) callback();
    });
  }

  // Load Application States
  function loadApplicationStates(callback) {
    if (!endpoints.applicationStates) {
      if (callback) callback();
      return;
    }

    makeAjaxCall(endpoints.applicationStates, function(htmlContent) {
      showContent('application-states', htmlContent);
      if (callback) callback();
    }, function(error) {
      showError('application-states', error);
      if (callback) callback();
    });
  }

  // Load QHP Application States
  function loadQhpApplicationStates(callback) {
    if (!endpoints.qhpApplicationStates) {
      if (callback) callback();
      return;
    }

    makeAjaxCall(endpoints.qhpApplicationStates, function(htmlContent) {
      showContent('qhp-application-states', htmlContent);
      if (callback) callback();
    }, function(error) {
      showError('qhp-application-states', error);
      if (callback) callback();
    });
  }

  // Load Notices
  function loadNotices(callback) {
    if (!endpoints.notices) {
      if (callback) callback();
      return;
    }

    makeAjaxCall(endpoints.notices, function(htmlContent) {
      showContent('notices', htmlContent);
      if (callback) callback();
    }, function(error) {
      showError('notices', error);
      if (callback) callback();
    });
  }

  // Load Enrollment States
  function loadEnrollmentStates(callback) {
    if (!endpoints.enrollmentStates) {
      if (callback) callback();
      return;
    }

    makeAjaxCall(endpoints.enrollmentStates, function(htmlContent) {
      showContent('enrollment-states', htmlContent);
      if (callback) callback();
    }, function(error) {
      showError('enrollment-states', error);
      if (callback) callback();
    });
  }

  // Initialize all sections
  function initializeDashboard() {

    // Load each section with a callback to track completion
    loadBenefitCoverage(function() {
    });

    loadApplicationStates(function() {
    });

    loadQhpApplicationStates(function() {
    });

    loadNotices(function() {
    });

    loadEnrollmentStates(function() {
    });
  }

  // Auto-refresh functionality
  var autoRefreshInterval;
  var refreshIntervalMinutes = 5; // Default 5 minutes
  var isAutoRefreshEnabled = true;

  // Debounce mechanism to prevent duplicate calls
  var refreshDebounces = {};
  var refreshInProgress = {};

  function startAutoRefresh() {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval);
    }

    autoRefreshInterval = setInterval(function() {
      if (isAutoRefreshEnabled && document.visibilityState === 'visible') {
        refreshDashboard();
      }
    }, refreshIntervalMinutes * 60 * 1000);
  }

  function stopAutoRefresh() {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval);
      autoRefreshInterval = null;
    }
  }

  function refreshDashboard() {
    // Show loading indicators
    var sections = ['benefit-coverage', 'application-states', 'qhp-application-states', 'notices', 'enrollment-states'];
    sections.forEach(function(section) {
      var loadingElement = document.getElementById(section + '-loading');
      var contentElement = document.getElementById(section + '-content');

      if (loadingElement && contentElement) {
        loadingElement.classList.remove('d-none');
        contentElement.classList.add('d-none');
      }
    });

    // Reload all sections
    initializeDashboard();
  }

  function refreshSection(sectionName) {
    // Prevent duplicate refreshes
    if (refreshInProgress[sectionName]) {
      return;
    }

    // Clear any pending debounce timers
    if (refreshDebounces[sectionName]) {
      clearTimeout(refreshDebounces[sectionName]);
      refreshDebounces[sectionName] = null;
    }

    // Mark this section as currently being refreshed
    refreshInProgress[sectionName] = true;

    // Show loading indicator for specific section
    var loadingElement = document.getElementById(sectionName + '-loading');
    var contentElement = document.getElementById(sectionName + '-content');

    if (loadingElement && contentElement) {
      loadingElement.classList.remove('d-none');
      contentElement.classList.add('d-none');
    }

    // Clear cache for this section's endpoint
    if (endpoints && endpoints[camelCase(sectionName)]) {
      delete responseCache[endpoints[camelCase(sectionName)]];
    }


    // Reload specific section based on section name
    var loadFunction;
    switch(sectionName) {
      case 'benefit-coverage':
        loadFunction = loadBenefitCoverage;
        break;
      case 'application-states':
        loadFunction = loadApplicationStates;
        break;
      case 'qhp-application-states':
        loadFunction = loadQhpApplicationStates;
        break;
      case 'notices':
        loadFunction = loadNotices;
        break;
      case 'enrollment-states':
        loadFunction = loadEnrollmentStates;
        break;
      default:
        // Reset the in-progress flag
        refreshInProgress[sectionName] = false;
        return;
    }

    // Create a wrapped function that clears the in-progress flag
    function executeLoad() {
      loadFunction();

      // Reset the in-progress flag after a short delay
      setTimeout(function() {
        refreshInProgress[sectionName] = false;
      }, 500);
    }

    // Execute with a very small delay to ensure browser event queue is clear
    refreshDebounces[sectionName] = setTimeout(executeLoad, 50);
  }

  function toggleAutoRefresh() {
    isAutoRefreshEnabled = !isAutoRefreshEnabled;
    updateAutoRefreshButton();

    if (isAutoRefreshEnabled) {
      startAutoRefresh();
    } else {
      stopAutoRefresh();
    }
  }

  function updateAutoRefreshButton() {
    var button = document.getElementById('auto-refresh-toggle');
    if (button) {
      if (isAutoRefreshEnabled) {
        button.textContent = 'Disable Auto-Refresh';
        button.className = 'btn btn-warning btn-sm';
        button.title = 'Currently refreshing every ' + refreshIntervalMinutes + ' minutes';
      } else {
        button.textContent = 'Enable Auto-Refresh';
        button.className = 'btn btn-success btn-sm';
        button.title = 'Click to enable auto-refresh every ' + refreshIntervalMinutes + ' minutes';
      }
    }
  }

  function setRefreshInterval(minutes) {
    refreshIntervalMinutes = minutes;
    if (isAutoRefreshEnabled) {
      startAutoRefresh(); // Restart with new interval
    }
    updateAutoRefreshButton();
  }

  // Set up auto-refresh controls
  function setupAutoRefreshControls() {
    var refreshButton = document.getElementById('manual-refresh');
    if (refreshButton) {
      refreshButton.addEventListener('click', function(e) {
        e.preventDefault();
        refreshDashboard();
      });
    }

    var autoRefreshButton = document.getElementById('auto-refresh-toggle');
    if (autoRefreshButton) {
      autoRefreshButton.addEventListener('click', function(e) {
        e.preventDefault();
        toggleAutoRefresh();
      });
    }

    // Set up interval dropdown options
    var intervalOptions = document.querySelectorAll('.interval-option');
    intervalOptions.forEach(function(option) {
      option.addEventListener('click', function(e) {
        e.preventDefault();
        var value = parseInt(this.getAttribute('data-value'));
        var text = this.textContent;

        // Update button text
        var currentIntervalSpan = document.getElementById('current-interval');
        if (currentIntervalSpan) {
          currentIntervalSpan.textContent = text;
        }

        // Update active state
        intervalOptions.forEach(function(opt) {
          opt.classList.remove('active');
        });
        this.classList.add('active');

        // Set the new interval
        setRefreshInterval(value);
      });
    });

    // Set up individual section refresh buttons - remove any existing listeners first
    var sectionRefreshButtons = document.querySelectorAll('.section-refresh');
    sectionRefreshButtons.forEach(function(button) {
      // First, remove any existing click listeners to prevent duplicates
      var newButton = button.cloneNode(true);
      button.parentNode.replaceChild(newButton, button);

      // Now add our listener to the fresh button
      newButton.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation(); // Stop event bubbling

        var sectionName = this.getAttribute('data-section');
        refreshSection(sectionName);
      });
    });

    // Update button initial state
    updateAutoRefreshButton();
  }

  // Pause auto-refresh when page is not visible
  document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'hidden') {
      // Page is hidden, auto-refresh will pause automatically
    } else if (document.visibilityState === 'visible' && isAutoRefreshEnabled) {
      // Page is visible again, ensure auto-refresh is running
      if (!autoRefreshInterval) {
        startAutoRefresh();
      }
    }
  });

  // Start loading all sections
  initializeDashboard();

  // Set up auto-refresh controls
  setupAutoRefreshControls();

  // Start auto-refresh
  if (isAutoRefreshEnabled) {
    startAutoRefresh();
  }

  // Expose functions globally for debugging
  window.dryRunDashboard = {
    refresh: refreshDashboard,
    refreshSection: refreshSection,
    toggleAutoRefresh: toggleAutoRefresh,
    setRefreshInterval: setRefreshInterval
  };
});
