/**
 * ACME Wrapper Web UI JavaScript
 * Handles form interactions and communication with the backend
 */

/* global $, showhide, showLoading, refreshpage */

var ADDON_NAME = 'acme-wrapper';
var SETTINGS_PREFIX = 'acme-wrapper_';

// DNS Provider credential field definitions
var DNS_CREDENTIALS = {
    'dns_aws': [
        { key: 'AWS_ACCESS_KEY_ID', label: 'Access Key ID', type: 'text', placeholder: 'AKIAXXXXXXXXXXXX' },
        { key: 'AWS_SECRET_ACCESS_KEY', label: 'Secret Access Key', type: 'password', placeholder: '' }
    ],
    'dns_cf': [
        { key: 'CF_Token', label: 'API Token', type: 'password', placeholder: 'Your API token' },
        { key: 'CF_Zone_ID', label: 'Zone ID', type: 'text', placeholder: 'Your zone ID' }
    ],
    'dns_gd': [
        { key: 'GD_Key', label: 'API Key', type: 'text', placeholder: '' },
        { key: 'GD_Secret', label: 'API Secret', type: 'password', placeholder: '' }
    ],
    'dns_dgon': [
        { key: 'DO_API_KEY', label: 'API Token', type: 'password', placeholder: '' }
    ],
    'dns_namecheap': [
        { key: 'NAMECHEAP_USERNAME', label: 'Username', type: 'text', placeholder: '' },
        { key: 'NAMECHEAP_API_KEY', label: 'API Key', type: 'password', placeholder: '' },
        { key: 'NAMECHEAP_SOURCEIP', label: 'Source IP', type: 'text', placeholder: 'Your whitelisted IP' }
    ],
    'dns_linode_v4': [
        { key: 'LINODE_V4_API_KEY', label: 'API Token', type: 'password', placeholder: '' }
    ],
    'dns_vultr': [
        { key: 'VULTR_API_KEY', label: 'API Key', type: 'password', placeholder: '' }
    ]
};

/**
 * Initialize the page
 */
function initial() {
    show_menu();
    loadSettings();
    refreshStatus();
    loadCertificates();
}

/**
 * Load settings from custom_settings.txt via AJAX
 */
function loadSettings() {
    $.ajax({
        url: '/ext/acme-wrapper/settings.json',
        dataType: 'json',
        timeout: 5000,
        success: function(data) {
            if (data) {
                applyLoadedSettings(data);
            }
        },
        error: function() {
            // Fall back to reading from custom_settings.txt via shell
            loadSettingsFromCustomSettings();
        }
    });
}

/**
 * Load settings from custom_settings.txt
 */
function loadSettingsFromCustomSettings() {
    $.ajax({
        url: '/ext/acme-wrapper/get_settings.cgi',
        dataType: 'json',
        timeout: 5000,
        success: function(data) {
            if (data) {
                applyLoadedSettings(data);
            }
        },
        error: function() {
            // Use defaults
            console.log('Could not load settings, using defaults');
        }
    });
}

/**
 * Apply loaded settings to form fields
 */
function applyLoadedSettings(data) {
    // DNS API
    if (data.dns_api) {
        var select = document.getElementById('dns_api');
        var found = false;
        for (var i = 0; i < select.options.length; i++) {
            if (select.options[i].value === data.dns_api) {
                select.selectedIndex = i;
                found = true;
                break;
            }
        }
        if (!found) {
            select.value = 'other';
            document.getElementById('dns_api_custom').value = data.dns_api;
            document.getElementById('dns_api_custom').style.display = 'inline-block';
        }
    }

    // DNS Sleep
    if (data.dnssleep) {
        document.getElementById('dnssleep').value = data.dnssleep;
    }

    // Debug mode
    if (data.debug === '1') {
        document.getElementById('debug_on').checked = true;
    } else {
        document.getElementById('debug_off').checked = true;
    }

    // Domains
    if (data.domains) {
        document.getElementById('domains').value = data.domains.replace(/\\n/g, '\n');
    }

    // Update credential fields
    onDnsApiChange();
}

/**
 * Handle DNS API selection change
 */
function onDnsApiChange() {
    var select = document.getElementById('dns_api');
    var customInput = document.getElementById('dns_api_custom');
    var credTable = document.getElementById('credentials-table');

    // Show/hide custom input
    if (select.value === 'other') {
        customInput.style.display = 'inline-block';
    } else {
        customInput.style.display = 'none';
    }

    // Update credential fields
    var dnsApi = select.value === 'other' ? customInput.value : select.value;
    var credentials = DNS_CREDENTIALS[dnsApi] || [];

    // Clear existing rows
    credTable.innerHTML = '';

    // Add rows for this provider
    if (credentials.length > 0) {
        credentials.forEach(function(cred) {
            var row = document.createElement('tr');
            row.innerHTML = '<th width="30%">' + cred.label + '</th>' +
                '<td><input type="' + cred.type + '" id="cred_' + cred.key + '" ' +
                'class="input_32_table" placeholder="' + (cred.placeholder || '') + '"></td>';
            credTable.appendChild(row);
        });
    } else if (dnsApi && dnsApi !== 'other') {
        var row = document.createElement('tr');
        row.innerHTML = '<td colspan="2" style="color:#AAAAAA;">' +
            'Configure credentials manually in /jffs/.le/account.conf' +
            '</td>';
        credTable.appendChild(row);
    }
}

/**
 * Refresh status information
 */
function refreshStatus() {
    // Get addon status via AJAX
    $.ajax({
        url: '/ext/acme-wrapper/status.json',
        dataType: 'json',
        timeout: 5000,
        success: function(data) {
            updateStatusDisplay(data);
        },
        error: function() {
            // Show basic status
            document.getElementById('status-version').textContent = '-';
            document.getElementById('status-mount').innerHTML = '<span class="status-warn">Unknown</span>';
            document.getElementById('status-acme').textContent = '-';
        }
    });
}

/**
 * Update status display with data
 */
function updateStatusDisplay(data) {
    if (data.version) {
        document.getElementById('status-version').textContent = data.version;
    }

    if (data.mounted) {
        document.getElementById('status-mount').innerHTML =
            '<span class="status-ok">Mounted</span>';
    } else {
        document.getElementById('status-mount').innerHTML =
            '<span class="status-error">Not Mounted</span>';
    }

    if (data.acme_version) {
        document.getElementById('status-acme').textContent = data.acme_version;
    }
}

/**
 * Load certificate information
 */
function loadCertificates() {
    $.ajax({
        url: '/ext/acme-wrapper/certificates.json',
        dataType: 'json',
        timeout: 5000,
        success: function(data) {
            displayCertificates(data);
        },
        error: function() {
            document.getElementById('cert-table-body').innerHTML =
                '<tr><td colspan="3" style="text-align:center; color:#AAAAAA;">Unable to load certificate information</td></tr>';
        }
    });
}

/**
 * Display certificate information in table
 */
function displayCertificates(certs) {
    var tbody = document.getElementById('cert-table-body');

    if (!certs || certs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align:center; color:#AAAAAA;">No certificates found</td></tr>';
        return;
    }

    var html = '';
    certs.forEach(function(cert) {
        var statusClass = 'status-ok';
        var statusText = 'Valid';

        if (cert.expired) {
            statusClass = 'status-error';
            statusText = 'Expired';
        } else if (cert.expiring_soon) {
            statusClass = 'status-warn';
            statusText = 'Expiring Soon';
        }

        html += '<tr>';
        html += '<td>' + escapeHtml(cert.domain) + '</td>';
        html += '<td>' + escapeHtml(cert.expires) + '</td>';
        html += '<td><span class="' + statusClass + '">' + statusText + '</span></td>';
        html += '</tr>';
    });

    tbody.innerHTML = html;
}

/**
 * Apply settings
 */
function applySettings() {
    // Gather form data
    var dnsApi = document.getElementById('dns_api').value;
    if (dnsApi === 'other') {
        dnsApi = document.getElementById('dns_api_custom').value;
    }

    var dnsSleep = document.getElementById('dnssleep').value;
    var debug = document.querySelector('input[name="debug"]:checked').value;
    var domains = document.getElementById('domains').value;

    // Validate
    if (!dnsApi) {
        alert('Please select a DNS API provider');
        return;
    }

    if (!dnsSleep || isNaN(parseInt(dnsSleep))) {
        alert('Please enter a valid DNS propagation wait time');
        return;
    }

    // Build settings object
    var settings = {
        dns_api: dnsApi,
        dnssleep: dnsSleep,
        debug: debug,
        domains: domains.replace(/\n/g, '\\n')
    };

    // Gather credentials if present
    var credentials = DNS_CREDENTIALS[dnsApi] || [];
    credentials.forEach(function(cred) {
        var input = document.getElementById('cred_' + cred.key);
        if (input && input.value) {
            settings['cred_' + cred.key] = input.value;
        }
    });

    // Save settings via custom_settings
    saveSettings(settings);
}

/**
 * Save settings to custom_settings.txt and trigger service event
 */
function saveSettings(settings) {
    // Build amng_custom string for the form
    var customSettings = [];
    for (var key in settings) {
        if (settings.hasOwnProperty(key)) {
            customSettings.push(SETTINGS_PREFIX + key + ' ' + settings[key]);
        }
    }

    document.getElementById('amng_custom').value = customSettings.join('\n');
    document.form.action_script.value = 'start_acmewrapper';
    document.form.action_wait.value = '5';

    // Show loading
    showLoading();

    // Submit form
    document.form.submit();

    // Refresh after delay
    setTimeout(function() {
        refreshpage();
    }, 6000);
}

/**
 * Issue/Renew certificates
 */
function issueCertificates() {
    if (!confirm('This will issue or renew certificates for all configured domains. Continue?')) {
        return;
    }

    showLoading();

    $.ajax({
        url: '/ext/acme-wrapper/issue.cgi',
        type: 'POST',
        timeout: 300000, // 5 minute timeout for cert issuance
        success: function(data) {
            alert('Certificate issuance triggered. Check logs for progress.');
            refreshStatus();
            loadCertificates();
        },
        error: function() {
            // Fall back to service command
            document.form.action_script.value = 'restart_letsencrypt';
            document.form.action_wait.value = '60';
            document.form.submit();

            setTimeout(function() {
                alert('Certificate issuance triggered. Check router logs for progress.');
                refreshpage();
            }, 5000);
        }
    });
}

/**
 * View logs
 */
function viewLogs() {
    var modal = document.getElementById('log-modal');
    var content = document.getElementById('log-content');

    modal.style.display = 'block';
    content.textContent = 'Loading...';

    $.ajax({
        url: '/ext/acme-wrapper/logs.txt',
        dataType: 'text',
        timeout: 10000,
        success: function(data) {
            content.textContent = data || 'No log entries found.';
        },
        error: function() {
            content.textContent = 'Unable to load logs. Check /tmp/acme-wrapper.log on the router.';
        }
    });
}

/**
 * Close log modal
 */
function closeLogModal() {
    document.getElementById('log-modal').style.display = 'none';
}

/**
 * Escape HTML for safe display
 */
function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Show loading indicator
 */
function showLoading() {
    if (typeof showhide === 'function') {
        showhide('Loading', 1);
    }
}

/**
 * Show menu - called by page template
 */
function show_menu() {
    if (typeof showmenu === 'function') {
        showmenu();
    }
}
