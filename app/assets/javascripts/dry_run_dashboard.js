document.addEventListener('DOMContentLoaded', function() {
  const endpoints = window.dryRunEndpoints;
  
  // Cache for API responses to avoid repeated calls during auto-refresh
  var responseCache = {};
  var cacheExpiry = 2 * 60 * 1000; // 2 minutes

  function makeAjaxCall(url, successCallback, errorCallback) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.setRequestHeader('Accept', 'text/html');
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    
    // Add timeout for better performance
    xhr.timeout = 45000; // 45 seconds

    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4) {
        if (xhr.status === 200) {
          successCallback(xhr.responseText);
        } else {
          errorCallback('HTTP Error: ' + xhr.status);
        }
      }
    };
    
    xhr.ontimeout = function() {
      errorCallback('Request timed out after 45 seconds');
    };
    
    xhr.onerror = function() {
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
  function loadBenefitCoverage() {
    if (!endpoints.benefitCoverage) return;
    
    makeAjaxCall(endpoints.benefitCoverage, function(htmlContent) {
      showContent('benefit-coverage', htmlContent);
    }, function(error) {
      showError('benefit-coverage', error);
    });
  }

  // Load Application States
  function loadApplicationStates() {
    if (!endpoints.applicationStates) return;
    
    makeAjaxCall(endpoints.applicationStates, function(htmlContent) {
      showContent('application-states', htmlContent);
    }, function(error) {
      showError('application-states', error);
    });
  }

  // Load Notices
  function loadNotices() {
    if (!endpoints.notices) return;
    
    makeAjaxCall(endpoints.notices, function(htmlContent) {
      showContent('notices', htmlContent);
    }, function(error) {
      showError('notices', error);
    });
  }

  // Load Enrollment States
  function loadEnrollmentStates() {
    if (!endpoints.enrollmentStates) return;
    
    makeAjaxCall(endpoints.enrollmentStates, function(htmlContent) {
      showContent('enrollment-states', htmlContent);
    }, function(error) {
      showError('enrollment-states', error);
    });
  }

  // Initialize all sections
  function initializeDashboard() {
    loadBenefitCoverage();
    loadApplicationStates();
    loadNotices();
    loadEnrollmentStates();
  }

  // Auto-refresh functionality
  var autoRefreshInterval;
  var refreshIntervalMinutes = 5; // Default 5 minutes
  var isAutoRefreshEnabled = true;

  function startAutoRefresh() {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval);
    }
    
    autoRefreshInterval = setInterval(function() {
      if (isAutoRefreshEnabled && document.visibilityState === 'visible') {
        console.log('Auto-refreshing dry run dashboard...');
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
    var sections = ['benefit-coverage', 'application-states', 'notices', 'enrollment-states'];
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

    var intervalSelect = document.getElementById('refresh-interval');
    if (intervalSelect) {
      intervalSelect.addEventListener('change', function(e) {
        setRefreshInterval(parseInt(e.target.value));
      });
    }

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
    toggleAutoRefresh: toggleAutoRefresh,
    setRefreshInterval: setRefreshInterval
  };
});
