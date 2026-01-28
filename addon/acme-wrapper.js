/**
 * ACME Wrapper Web UI JavaScript
 * Handles form interactions and communication with the Merlin backend
 *
 * Uses Merlin's Addons API:
 * - Settings are loaded via <% get_custom_settings(); %> (embedded in page)
 * - Settings are saved via amng_custom form field
 * - Actions trigger service-event scripts
 */

/* global custom_settings, showLoading, refreshpage, showhide */

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
        { key: 'CF_Zone_ID', label: 'Zone ID (optional)', type: 'text', placeholder: 'Your zone ID' }
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
 * Get a setting value from custom_settings
 * @param {string} key - Setting key (without prefix)
 * @param {string} defaultValue - Default value if not found
 * @returns {string} Setting value
 */
function getSetting(key, defaultValue) {
    var fullKey = SETTINGS_PREFIX + key;
    if (typeof custom_settings !== 'undefined' && custom_settings[fullKey]) {
        return custom_settings[fullKey];
    }
    return defaultValue || '';
}

/**
 * Set current page path in form fields
 * Required for Merlin to know which page we're on and prevent redirect loops
 */
function SetCurrentPage() {
    var path = window.location.pathname.substring(1);
    document.form.current_page.value = path;
    document.form.next_page.value = path;
}

/**
 * Initialize the page
 * Called by body onload - must call Merlin's show_menu() for navigation
 */
function initial() {
    SetCurrentPage();
    show_menu();
    loadSettings();
    updateStatusDisplay();
    showCertificateInfo();
}

/**
 * Load settings from the embedded custom_settings object
 */
function loadSettings() {
    // DNS API
    var dnsApi = getSetting('dns_api', 'dns_aws');
    var select = document.getElementById('dns_api');
    var found = false;

    for (var i = 0; i < select.options.length; i++) {
        if (select.options[i].value === dnsApi) {
            select.selectedIndex = i;
            found = true;
            break;
        }
    }

    if (!found && dnsApi) {
        select.value = 'other';
        document.getElementById('dns_api_custom').value = dnsApi;
        document.getElementById('dns_api_custom').style.display = 'inline-block';
    }

    // DNS Sleep
    var dnsSleep = getSetting('dnssleep', '120');
    document.getElementById('dnssleep').value = dnsSleep;

    // Debug mode
    var debug = getSetting('debug', '0');
    if (debug === '1') {
        document.getElementById('debug_on').checked = true;
    } else {
        document.getElementById('debug_off').checked = true;
    }

    // Domains - stored with \n escaped as \\n
    var domains = getSetting('domains', '');
    if (domains) {
        document.getElementById('domains').value = domains.replace(/\\n/g, '\n');
    }

    // Update credential fields based on selected provider
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
                'class="input_32_table" placeholder="' + (cred.placeholder || '') + '">' +
                '<span style="color:#888; margin-left:10px; font-size:11px;">' + cred.key + '</span></td>';
            credTable.appendChild(row);
        });

        // Add note about credentials
        var noteRow = document.createElement('tr');
        noteRow.innerHTML = '<td colspan="2" style="color:#AAAAAA; font-size:12px; padding-top:10px;">' +
            'Note: Credentials entered here will be saved to /jffs/.le/account.conf' +
            '</td>';
        credTable.appendChild(noteRow);
    } else if (dnsApi && dnsApi !== 'other') {
        var row = document.createElement('tr');
        row.innerHTML = '<td colspan="2" style="color:#AAAAAA;">' +
            'Configure credentials manually in /jffs/.le/account.conf<br>' +
            'See: <a href="https://github.com/acmesh-official/acme.sh/wiki/dnsapi" target="_blank" style="color:#5FA0CC;">acme.sh DNS API documentation</a>' +
            '</td>';
        credTable.appendChild(row);
    }
}

/**
 * Update status display
 * Reads system status from custom_settings (updated by backend)
 */
function updateStatusDisplay() {
    // Parse system status from custom_settings
    var sysStatus = getSetting('sys_status', '').split('|');
    var mountStatus = sysStatus[0] || 'unknown';
    var acmeVersion = sysStatus[1] || 'unknown';
    var wrapperVersion = sysStatus[2] || '2.0.0';

    document.getElementById('status-version').textContent = wrapperVersion;

    // Mount status
    if (mountStatus === 'mounted') {
        document.getElementById('status-mount').innerHTML =
            '<span class="status-ok">Active</span>';
    } else if (mountStatus === 'not_mounted') {
        document.getElementById('status-mount').innerHTML =
            '<span class="status-error">Not Mounted</span>';
    } else {
        document.getElementById('status-mount').innerHTML =
            '<span style="color:#888;">Unknown</span> ' +
            '<span style="color:#888; font-size:11px;">(Click "Refresh Status")</span>';
    }

    // acme.sh version - convert underscores back to spaces
    if (acmeVersion && acmeVersion !== 'not_installed') {
        acmeVersion = acmeVersion.replace(/_/g, ' ');
        document.getElementById('status-acme').textContent = acmeVersion;
    } else if (acmeVersion === 'not_installed') {
        document.getElementById('status-acme').innerHTML =
            '<span class="status-error">Not Installed</span>';
    } else {
        document.getElementById('status-acme').innerHTML =
            '<span style="color:#888;">Unknown</span> ' +
            '<span style="color:#888; font-size:11px;">(Click "Refresh Status")</span>';
    }
}

/**
 * Show certificate information
 * Reads certificate status from custom_settings (updated by backend)
 */
function showCertificateInfo() {
    var tbody = document.getElementById('cert-table-body');
    var certStatus = getSetting('cert_status', '');

    if (!certStatus) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align:center; color:#AAAAAA;">' +
            'No certificates found. Click "Refresh Status" to update.</td></tr>';
        return;
    }

    tbody.innerHTML = '';
    var certs = certStatus.split('\\n').filter(function(c) { return c; });

    if (certs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align:center; color:#AAAAAA;">' +
            'No certificates found. Click "Refresh Status" to update.</td></tr>';
        return;
    }

    certs.forEach(function(cert) {
        var parts = cert.split('|');
        var domain = parts[0] || '';
        var expiry = parts[1] || '';
        var status = parts[2] || '';

        // Convert underscores back to spaces for display
        expiry = expiry.replace(/_/g, ' ');

        var row = document.createElement('tr');
        var statusClass = status === 'valid' ? 'status-ok' : 'status-error';
        row.innerHTML = '<td>' + domain + '</td>' +
            '<td>' + expiry + '</td>' +
            '<td><span class="' + statusClass + '">' + status + '</span></td>';
        tbody.appendChild(row);
    });
}

/**
 * Apply settings - saves to custom_settings.txt and triggers service event
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

    // Update custom_settings object with form values
    custom_settings[SETTINGS_PREFIX + 'dns_api'] = dnsApi;
    custom_settings[SETTINGS_PREFIX + 'dnssleep'] = dnsSleep;
    custom_settings[SETTINGS_PREFIX + 'debug'] = debug;

    // Escape newlines in domains
    if (domains) {
        custom_settings[SETTINGS_PREFIX + 'domains'] = domains.replace(/\n/g, '\\n');
    }

    // Gather credentials if entered
    var credentials = DNS_CREDENTIALS[dnsApi] || [];
    credentials.forEach(function(cred) {
        var input = document.getElementById('cred_' + cred.key);
        if (input && input.value) {
            custom_settings[SETTINGS_PREFIX + 'cred_' + cred.key] = input.value;
        }
    });

    // Set form values - Merlin expects JSON format
    document.getElementById('amng_custom').value = JSON.stringify(custom_settings);
    document.form.action_script.value = 'start_acmewrapper';
    document.form.action_wait.value = '5';

    // Show loading
    if (typeof showLoading === 'function') {
        showLoading();
    }

    // Submit form
    document.form.submit();

    // Refresh after delay
    setTimeout(function() {
        if (typeof refreshpage === 'function') {
            refreshpage();
        } else {
            location.reload();
        }
    }, 6000);
}

/**
 * Issue/Renew certificates - triggers Let's Encrypt service restart
 */
function issueCertificates() {
    if (!confirm('This will issue or renew certificates for all configured domains.\n\nMake sure you have:\n1. Configured your domains\n2. Set up DNS API credentials in /jffs/.le/account.conf\n\nContinue?')) {
        return;
    }

    // Use Merlin's built-in Let's Encrypt service restart
    document.form.action_script.value = 'restart_letsencrypt';
    document.form.action_wait.value = '120';

    if (typeof showLoading === 'function') {
        showLoading();
    }

    document.form.submit();

    setTimeout(function() {
        alert('Certificate issuance triggered.\n\nCheck progress via SSH:\ntail -f /tmp/syslog.log | grep -i acme');
        if (typeof refreshpage === 'function') {
            refreshpage();
        } else {
            location.reload();
        }
    }, 5000);
}

/**
 * View logs - shows instructions since we can't fetch logs via AJAX
 */
function viewLogs() {
    var modal = document.getElementById('log-modal');
    var content = document.getElementById('log-content');

    modal.style.display = 'block';
    content.innerHTML =
        '<strong>To view ACME Wrapper logs, run on router via SSH:</strong>\n\n' +
        '# View wrapper log:\n' +
        'cat /tmp/acme-wrapper.log\n\n' +
        '# View system log (acme related):\n' +
        'grep -i acme /tmp/syslog.log | tail -50\n\n' +
        '# Watch live logs during certificate issuance:\n' +
        'tail -f /tmp/syslog.log | grep -i acme\n\n' +
        '# Check acme.sh log:\n' +
        'cat /tmp/acme.log 2>/dev/null || echo "No acme.sh log found"';
}

/**
 * Close log modal
 */
function closeLogModal() {
    document.getElementById('log-modal').style.display = 'none';
}

/**
 * Refresh status - triggers backend status update then reloads page
 */
function acmeWrapperRefreshStatus() {
    document.form.action_script.value = 'start_acmewrapperstatus';
    document.form.action_wait.value = '3';

    if (typeof showLoading === 'function') {
        showLoading();
    }

    document.form.submit();

    setTimeout(function() {
        location.reload();
    }, 4000);
}
