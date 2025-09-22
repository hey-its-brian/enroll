document.addEventListener('click', function(e) {
    if (e.target.matches('button#delete_applicant_button_qhp')) {
        e.preventDefault();
        showModal();
    }

    if (e.target.textContent.trim() === 'Cancel') {
        closeModal();
    }

    if (e.target.matches('#destroy-confirm-qhp')) {
        confirmDestroyApplicantQhp(e, e.target.dataset.url);
    }
});

function showModal() {
    const modal = document.getElementById('destroyApplicantQhp');
    modal.classList.add('show');
    modal.style.display = 'block';
    document.body.classList.add('modal-open');
    
    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop fade show';
    document.body.appendChild(backdrop);
    
    const confirmButton = document.querySelector('.btn-confirmation');
    if (confirmButton) confirmButton.removeAttribute('disabled');
}

function closeModal() {
    const modal = document.getElementById('destroyApplicantQhp');
    if (modal) {
        modal.style.display = 'none';
        modal.classList.remove('show');
    }
    document.body.classList.remove('modal-open');
    const backdrop = document.querySelector('.modal-backdrop');
    if (backdrop) backdrop.remove();
}

function confirmDestroyApplicantQhp(event, url) {
    const confirmButton = document.getElementById('destroy-confirm-qhp');
    confirmButton.disabled = true;
    event.preventDefault();
    event.stopImmediatePropagation();

    // Clean up modal
    document.querySelectorAll('.modal-backdrop').forEach(el => el.classList.remove('modal-backdrop'));
    document.querySelectorAll('.modal-open').forEach(el => el.classList.remove('modal-open'));

    // Get CSRF token from meta tag --> not needed when running cucumber test
    const csrfMeta = document.querySelector('meta[name="csrf-token"]');
    const csrfToken = csrfMeta ? csrfMeta.getAttribute('content') : '';

    fetch(url, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': csrfToken }
    })
    .then(response => {
        closeModal();
        if (response.redirected) {
            // Follow the redirect from the controller
            window.location.href = response.url;
        } else if (response.ok) {
            // Fallback: navigate to applicants index
            const baseUrl = url.replace(/\/[^\/]+$/, '');
            window.location.href = baseUrl;
        } else {
            throw new Error(`HTTP ${response.status}`);
        }
    })
    .catch(error => {
        confirmButton.disabled = false;
    });
}