<!DOCTYPE html>
<html>
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge">
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="icon" href="images/favicon.png">
<title>ACME Wrapper</title>
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script language="JavaScript" type="text/javascript" src="/state.js"></script>
<script language="JavaScript" type="text/javascript" src="/general.js"></script>
<script language="JavaScript" type="text/javascript" src="/popup.js"></script>
<script language="JavaScript" type="text/javascript" src="/help.js"></script>
<script language="JavaScript" type="text/javascript" src="/validator.js"></script>
<script type="text/javascript" src="/user/acme-wrapper.js"></script>
<script>
// Load custom settings from Merlin's addon API
var custom_settings;
try {
    custom_settings = <% get_custom_settings(); %>;
} catch(e) {
    custom_settings = {};
}
if (typeof custom_settings !== 'object' || custom_settings === null) {
    custom_settings = {};
}
</script>
<style>
.acme-section {
    margin-bottom: 20px;
}
.acme-section h4 {
    color: #FFCC00;
    margin-bottom: 10px;
    border-bottom: 1px solid #444;
    padding-bottom: 5px;
}
.status-ok { color: #33FF33; }
.status-warn { color: #FFCC00; }
.status-error { color: #FF3333; }
.domain-entry {
    display: flex;
    align-items: center;
    margin-bottom: 5px;
}
.domain-entry input {
    flex: 1;
    margin-right: 5px;
}
.domain-entry button {
    width: 30px;
}
.cert-table {
    width: 100%;
    border-collapse: collapse;
}
.cert-table th, .cert-table td {
    padding: 8px;
    text-align: left;
    border-bottom: 1px solid #444;
}
.cert-table th {
    background-color: #2F3A3E;
}
#loading {
    display: none;
    text-align: center;
    padding: 20px;
}
.action-button {
    margin: 5px;
    padding: 8px 15px;
    cursor: pointer;
}
textarea.domain-list {
    width: 100%;
    height: 100px;
    font-family: monospace;
    background-color: #2F3A3E;
    color: #FFF;
    border: 1px solid #444;
    padding: 8px;
}
</style>
</head>

<body onload="initial();">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>

<iframe name="hidden_frame" id="hidden_frame" src="about:blank" width="0" height="0" frameborder="0"></iframe>

<form method="post" name="form" id="form" action="/start_apply.htm" target="hidden_frame">
<input type="hidden" name="productid" value="<% nvram_get("productid"); %>">
<input type="hidden" name="current_page" value="">
<input type="hidden" name="next_page" value="">
<input type="hidden" name="modified" value="0">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_script" value="">
<input type="hidden" name="action_wait" value="5">
<input type="hidden" name="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
<input type="hidden" name="amng_custom" id="amng_custom" value="">

<table class="content" align="center" cellpadding="0" cellspacing="0">
<tr>
    <td width="17">&nbsp;</td>
    <td valign="top" width="202">
        <div id="mainMenu"></div>
        <div id="subMenu"></div>
    </td>
    <td valign="top">
        <div id="tabMenu" class="submenuBlock"></div>

        <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
        <tr>
            <td valign="top">
                <table width="760px" border="0" cellpadding="4" cellspacing="0" class="FormTitle" id="FormTitle">
                <tbody>
                <tr>
                    <td bgcolor="#4D595D" valign="top">
                        <div>&nbsp;</div>
                        <div class="formfonttitle">ACME Wrapper</div>
                        <div style="margin:10px 0 10px 5px;" class="splitLine"></div>

                        <div id="loading">
                            <img src="/images/InternetScan.gif">
                            <p>Loading...</p>
                        </div>

                        <div id="main-content">
                            <!-- Status Section -->
                            <div class="acme-section">
                                <h4>Status</h4>
                                <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable">
                                <tr>
                                    <th width="30%">Addon Version</th>
                                    <td id="status-version">-</td>
                                </tr>
                                <tr>
                                    <th>Wrapper Mount</th>
                                    <td id="status-mount">-</td>
                                </tr>
                                <tr>
                                    <th>acme.sh Version</th>
                                    <td id="status-acme">-</td>
                                </tr>
                                </table>
                            </div>

                            <!-- DNS Provider Section -->
                            <div class="acme-section">
                                <h4>DNS Provider</h4>
                                <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable">
                                <tr>
                                    <th width="30%">DNS API</th>
                                    <td>
                                        <select id="dns_api" class="input_option" onchange="onDnsApiChange()">
                                            <option value="dns_aws">AWS Route53</option>
                                            <option value="dns_cf">Cloudflare</option>
                                            <option value="dns_gd">GoDaddy</option>
                                            <option value="dns_dgon">DigitalOcean</option>
                                            <option value="dns_namecheap">Namecheap</option>
                                            <option value="dns_linode_v4">Linode</option>
                                            <option value="dns_vultr">Vultr</option>
                                            <option value="other">Other...</option>
                                        </select>
                                        <input type="text" id="dns_api_custom" class="input_20_table" style="display:none; margin-left:10px;" placeholder="dns_xxx">
                                    </td>
                                </tr>
                                <tr>
                                    <th>DNS Propagation Wait</th>
                                    <td>
                                        <input type="text" id="dnssleep" class="input_6_table" maxlength="4" value="120"> seconds
                                        <span style="color:#AAAAAA; margin-left:10px;">Time to wait for DNS propagation (default: 120)</span>
                                    </td>
                                </tr>
                                </table>

                                <!-- Credential Fields (dynamic based on provider) -->
                                <div id="credentials-section" style="margin-top:10px;">
                                    <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable" id="credentials-table">
                                    </table>
                                    <p style="color:#AAAAAA; font-size:12px; margin-top:5px;">
                                        Credentials are stored in /jffs/.le/account.conf
                                    </p>
                                </div>
                            </div>

                            <!-- Domains Section -->
                            <div class="acme-section">
                                <h4>Domains</h4>
                                <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable">
                                <tr>
                                    <th width="30%" style="vertical-align:top;">Domain Entries</th>
                                    <td>
                                        <textarea id="domains" class="domain-list" placeholder="# One certificate per line&#10;# Format: *.example.com|example.com|www.example.com&#10;# Non-wildcard domain should be included for certificate naming"></textarea>
                                        <p style="color:#AAAAAA; font-size:12px; margin-top:5px;">
                                            Use pipe (|) to separate domains. Wildcard domains require DNS validation.
                                            <br>Example: *.example.com|example.com
                                        </p>
                                    </td>
                                </tr>
                                </table>
                            </div>

                            <!-- Certificates Section -->
                            <div class="acme-section">
                                <h4>Certificates</h4>
                                <div id="cert-list">
                                    <table class="cert-table" id="cert-table">
                                        <thead>
                                            <tr>
                                                <th>Domain</th>
                                                <th>Expires</th>
                                                <th>Status</th>
                                            </tr>
                                        </thead>
                                        <tbody id="cert-table-body">
                                            <tr><td colspan="3" style="text-align:center;">Loading...</td></tr>
                                        </tbody>
                                    </table>
                                </div>
                            </div>

                            <!-- Options Section -->
                            <div class="acme-section">
                                <h4>Options</h4>
                                <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable">
                                <tr>
                                    <th width="30%">Debug Mode</th>
                                    <td>
                                        <input type="radio" name="debug" id="debug_on" value="1">
                                        <label for="debug_on">Enable</label>
                                        <input type="radio" name="debug" id="debug_off" value="0" checked>
                                        <label for="debug_off">Disable</label>
                                        <span style="color:#AAAAAA; margin-left:10px;">Enable verbose logging for troubleshooting</span>
                                    </td>
                                </tr>
                                </table>
                            </div>

                            <!-- Actions Section -->
                            <div class="acme-section">
                                <h4>Actions</h4>
                                <div style="text-align:center; padding:10px;">
                                    <input type="button" class="button_gen action-button" value="Issue/Renew Certificates" onclick="issueCertificates()">
                                    <input type="button" class="button_gen action-button" value="Refresh Status" onclick="refreshStatus()">
                                    <input type="button" class="button_gen action-button" value="View Logs" onclick="viewLogs()">
                                </div>
                            </div>

                            <!-- Apply Button -->
                            <div class="apply_gen">
                                <input class="button_gen" onclick="applySettings()" type="button" value="Apply">
                            </div>
                        </div>

                    </td>
                </tr>
                </tbody>
                </table>
            </td>
        </tr>
        </table>
    </td>
    <td width="10" align="center" valign="top">&nbsp;</td>
</tr>
</table>
</form>

<div id="footer"></div>

<!-- Log Viewer Modal -->
<div id="log-modal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); z-index:9999;">
    <div style="position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); width:80%; max-width:800px; background:#2F3A3E; border:1px solid #444; border-radius:5px;">
        <div style="padding:15px; border-bottom:1px solid #444; display:flex; justify-content:space-between; align-items:center;">
            <h3 style="margin:0; color:#FFCC00;">ACME Wrapper Logs</h3>
            <button onclick="closeLogModal()" style="background:none; border:none; color:#FFF; font-size:20px; cursor:pointer;">&times;</button>
        </div>
        <div style="padding:15px; max-height:400px; overflow-y:auto;">
            <pre id="log-content" style="margin:0; white-space:pre-wrap; font-family:monospace; font-size:12px; color:#CCC;">Loading...</pre>
        </div>
    </div>
</div>

</body>
</html>
