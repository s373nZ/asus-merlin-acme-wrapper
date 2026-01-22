#!/bin/sh
# shellcheck shell=busybox

################################################################################
# acme-wrapper.sh
#
# amtm addon script for asus-merlin-acme-wrapper
# Provides menu-based installation, configuration, and management
#
# Part of asus-merlin-acme-wrapper
# https://github.com/s373nZ/asus-merlin-acme-wrapper
################################################################################

readonly SCRIPT_NAME="acme-wrapper"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_REPO="s373nZ/asus-merlin-acme-wrapper"
readonly SCRIPT_DEFAULT_BRANCH="main"

# Branch is configurable - set later after settings functions are defined
SCRIPT_BRANCH=""

# Paths
readonly ADDON_DIR="/jffs/addons/${SCRIPT_NAME}"
readonly SCRIPT_CONF="${ADDON_DIR}/${SCRIPT_NAME}.conf"
readonly SCRIPT_LOG="/tmp/${SCRIPT_NAME}.log"
readonly WRAPPER_SCRIPT="${ADDON_DIR}/asus-wrapper-acme.sh"
readonly WEBAPP_FILE="${ADDON_DIR}/${SCRIPT_NAME}.asp"
readonly WEBAPP_JS="${ADDON_DIR}/${SCRIPT_NAME}.js"

readonly LE_DIR="/jffs/.le"
readonly DOMAINS_FILE="${LE_DIR}/domains"
readonly ACCOUNT_CONF="${LE_DIR}/account.conf"

readonly REAL_ACME_SH="/opt/home/acme.sh/acme.sh"
readonly SYSTEM_ACME_SH="/usr/sbin/acme.sh"

readonly SCRIPTS_DIR="/jffs/scripts"
readonly POST_MOUNT="${SCRIPTS_DIR}/post-mount"
readonly SERVICE_EVENT="${SCRIPTS_DIR}/service-event"

readonly CUSTOM_SETTINGS="/jffs/addons/custom_settings.txt"

# Source Merlin helper functions (provides am_settings_get, am_settings_set, am_get_webui_page)
# shellcheck source=/dev/null
if [ -f /usr/sbin/helper.sh ]; then
    . /usr/sbin/helper.sh
fi

# Colors (disabled if not in terminal)
if [ -t 1 ]; then
    readonly COL_RED='\033[0;31m'
    readonly COL_GREEN='\033[0;32m'
    readonly COL_YELLOW='\033[1;33m'
    readonly COL_CYAN='\033[0;36m'
    readonly COL_BOLD='\033[1m'
    readonly COL_RESET='\033[0m'
else
    readonly COL_RED=''
    readonly COL_GREEN=''
    readonly COL_YELLOW=''
    readonly COL_CYAN=''
    readonly COL_BOLD=''
    readonly COL_RESET=''
fi

################################################################################
# Utility Functions
################################################################################

Print_Output() {
    local level="$1"
    local msg="$2"
    local color=""

    case "$level" in
        error) color="$COL_RED" ;;
        warn)  color="$COL_YELLOW" ;;
        info)  color="$COL_GREEN" ;;
        *)     color="" ;;
    esac

    printf '%b[%s]%b %s\n' "$color" "$(echo "$level" | tr '[:lower:]' '[:upper:]')" "$COL_RESET" "$msg"

    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg" >> "$SCRIPT_LOG"
}

Print_Header() {
    printf '\n%b============================================%b\n' "$COL_CYAN" "$COL_RESET"
    printf '%b  %s v%s%b\n' "$COL_BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$COL_RESET"
    printf '%b============================================%b\n\n' "$COL_CYAN" "$COL_RESET"
}

# Read user input, handling piped scripts (curl | sh) by reading from /dev/tty
Read_Input() {
    local input=""
    if [ -t 0 ]; then
        # stdin is a terminal, read normally
        read -r input
    elif [ -e /dev/tty ]; then
        # stdin is piped but tty exists, read from tty
        read -r input < /dev/tty
    fi
    echo "$input"
}

Confirm_Action() {
    local prompt="$1"
    local response

    printf '%s [y/N]: ' "$prompt"
    response=$(Read_Input)

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

################################################################################
# Settings Functions (using Merlin helper.sh)
################################################################################

# Read a setting from custom_settings.txt
# Uses am_settings_get from helper.sh with addon prefix
Get_Setting() {
    local key="$1"
    local default="$2"
    local full_key="${SCRIPT_NAME}_${key}"
    local value=""

    if type am_settings_get >/dev/null 2>&1; then
        value=$(am_settings_get "$full_key")
    elif [ -f "$CUSTOM_SETTINGS" ]; then
        # Fallback for environments without helper.sh (e.g., testing)
        value=$(grep "^${full_key} " "$CUSTOM_SETTINGS" 2>/dev/null | cut -d' ' -f2-)
    fi

    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Write a setting to custom_settings.txt
# Uses am_settings_set from helper.sh with addon prefix
Set_Setting() {
    local key="$1"
    local value="$2"
    local full_key="${SCRIPT_NAME}_${key}"

    if type am_settings_set >/dev/null 2>&1; then
        am_settings_set "$full_key" "$value"
    else
        # Fallback for environments without helper.sh (e.g., testing)
        mkdir -p "$(dirname "$CUSTOM_SETTINGS")"
        if [ -f "$CUSTOM_SETTINGS" ]; then
            sed -i "/^${full_key} /d" "$CUSTOM_SETTINGS"
        fi
        echo "${full_key} ${value}" >> "$CUSTOM_SETTINGS"
    fi
}

# Remove all settings for this addon
Clear_Settings() {
    if [ -f "$CUSTOM_SETTINGS" ]; then
        sed -i "/^${SCRIPT_NAME}_/d" "$CUSTOM_SETTINGS"
    fi
}

################################################################################
# Branch Configuration
################################################################################

# Get the configured branch (from settings, env var, or default)
Get_Branch() {
    # Command-line/env override takes precedence
    if [ -n "$SCRIPT_BRANCH" ]; then
        echo "$SCRIPT_BRANCH"
        return
    fi

    # Check settings
    local saved_branch
    saved_branch=$(Get_Setting "branch" "")
    if [ -n "$saved_branch" ]; then
        echo "$saved_branch"
        return
    fi

    # Default branch
    echo "$SCRIPT_DEFAULT_BRANCH"
}

# Set the branch for this session and save to settings
Set_Branch() {
    local branch="$1"
    SCRIPT_BRANCH="$branch"
    Set_Setting "branch" "$branch"
}

# Get the raw GitHub URL for the current branch
Get_Script_URL() {
    local branch
    branch=$(Get_Branch)
    echo "https://raw.githubusercontent.com/${SCRIPT_REPO}/${branch}"
}

# Validate that a branch exists on the remote repository
Validate_Branch() {
    local branch="$1"
    local test_url="https://raw.githubusercontent.com/${SCRIPT_REPO}/${branch}/addon/acme-wrapper.sh"

    if curl -fsSL --head "$test_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Load configuration from conf file
Load_Config() {
    if [ -f "$SCRIPT_CONF" ]; then
        # shellcheck source=/dev/null
        . "$SCRIPT_CONF"
    fi
}

# Save configuration to conf file
Save_Config() {
    cat > "$SCRIPT_CONF" << EOF
# ACME Wrapper Configuration
# Generated on $(date)

ACME_WRAPPER_VERSION="${SCRIPT_VERSION}"
ACME_WRAPPER_DNS_API="${ACME_WRAPPER_DNS_API:-dns_aws}"
ACME_WRAPPER_DEBUG="${ACME_WRAPPER_DEBUG:-0}"
ACME_WRAPPER_DNSSLEEP="${ACME_WRAPPER_DNSSLEEP:-120}"
ACME_WRAPPER_DOMAINS_FILE="${DOMAINS_FILE}"
ACME_WRAPPER_ACCOUNT_CONF="${ACCOUNT_CONF}"
EOF
}

################################################################################
# Prerequisite Checks
################################################################################

Check_Lock() {
    local lockfile="/tmp/${SCRIPT_NAME}.lock"

    if [ -f "$lockfile" ]; then
        local pid
        pid=$(cat "$lockfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            Print_Output error "Another instance is running (PID: $pid)"
            return 1
        fi
        rm -f "$lockfile"
    fi

    echo $$ > "$lockfile"
    trap 'rm -f "$lockfile"' EXIT
    return 0
}

Check_JFFS() {
    if [ ! -d "/jffs" ]; then
        Print_Output error "JFFS partition not found"
        return 1
    fi

    if [ ! -w "/jffs" ]; then
        Print_Output error "JFFS partition is not writable"
        return 1
    fi

    return 0
}

Check_Entware() {
    if [ ! -d "/opt/bin" ]; then
        Print_Output error "Entware not installed"
        Print_Output info "Install Entware first: amtm -> i"
        return 1
    fi
    return 0
}

Check_AcmeSh() {
    if [ ! -x "$REAL_ACME_SH" ]; then
        Print_Output warn "acme.sh not found at $REAL_ACME_SH"
        return 1
    fi
    return 0
}

Check_Prerequisites() {
    Print_Output info "Checking prerequisites..."

    if ! Check_JFFS; then
        return 1
    fi
    Print_Output info "JFFS partition OK"

    if ! Check_Entware; then
        return 1
    fi
    Print_Output info "Entware OK"

    if ! Check_AcmeSh; then
        Print_Output info "Attempting to install acme.sh..."
        if opkg update && opkg install acme; then
            if Check_AcmeSh; then
                Print_Output info "acme.sh installed successfully"
            else
                Print_Output error "Failed to install acme.sh"
                return 1
            fi
        else
            Print_Output error "Failed to install acme.sh via opkg"
            return 1
        fi
    else
        Print_Output info "acme.sh OK: $($REAL_ACME_SH --version 2>/dev/null | head -1)"
    fi

    return 0
}

################################################################################
# Web UI Functions (using Merlin helper.sh)
################################################################################

# Find an available userN.asp slot
# Uses am_get_webui_page from helper.sh
Get_WebUI_Page() {
    # First check if we already have a page assigned
    local existing_page
    existing_page=$(Get_Setting "webui_page" "")
    if [ -n "$existing_page" ] && [ -f "/www/user/$existing_page" ]; then
        if grep -q "ACME Wrapper" "/www/user/$existing_page" 2>/dev/null; then
            echo "$existing_page"
            return 0
        fi
    fi

    # Use helper.sh function if available
    if type am_get_webui_page >/dev/null 2>&1; then
        local page
        page=$(am_get_webui_page "$ADDON_DIR/${SCRIPT_NAME}.asp")
        if [ -n "$page" ] && [ "$page" != "none" ]; then
            echo "$page"
            return 0
        fi
    fi

    # Fallback: manual search for environments without helper.sh
    local i=1
    while [ $i -le 20 ]; do
        local page="/www/user/user${i}.asp"
        if [ ! -f "$page" ]; then
            echo "user${i}.asp"
            return 0
        fi
        i=$((i + 1))
    done

    echo ""
    return 1
}

# Mount the Web UI page
Mount_WebUI() {
    Print_Output info "Setting up Web UI..."

    local page
    page=$(Get_WebUI_Page)

    if [ -z "$page" ]; then
        Print_Output error "No available Web UI slot"
        return 1
    fi

    Print_Output info "Using Web UI slot: $page"

    # Copy our ASP file
    if [ -f "$WEBAPP_FILE" ]; then
        cp "$WEBAPP_FILE" "/www/user/$page"
    else
        Print_Output warn "Web UI file not found, skipping"
        return 0
    fi

    # Copy JavaScript
    if [ -f "$WEBAPP_JS" ]; then
        cp "$WEBAPP_JS" "/www/user/${SCRIPT_NAME}.js"
    fi

    # Update menuTree.js
    local menutree_file="/www/require/modules/menuTree.js"
    local tmp_menutree="/tmp/menuTree.js"

    # Unmount if already mounted
    umount "$menutree_file" 2>/dev/null

    # Copy and modify
    cp "$menutree_file" "$tmp_menutree"

    # Check if entry already exists
    if ! grep -q "ACME Wrapper" "$tmp_menutree"; then
        # Add entry under Tools section
        sed -i "/Tools_OtherSettings.asp/a\\
{url: \"$page\", tabName: \"ACME Wrapper\"}," "$tmp_menutree"
    fi

    # Mount the modified menuTree
    mount -o bind "$tmp_menutree" "$menutree_file"

    # Store the page slot for later
    Set_Setting "webui_page" "$page"

    Print_Output info "Web UI mounted successfully"
    return 0
}

# Unmount the Web UI page
Unmount_WebUI() {
    Print_Output info "Removing Web UI..."

    local page
    page=$(Get_Setting "webui_page" "")

    # Unmount menuTree
    local menutree_file="/www/require/modules/menuTree.js"
    umount "$menutree_file" 2>/dev/null

    # Remove our files
    if [ -n "$page" ] && [ -f "/www/user/$page" ]; then
        rm -f "/www/user/$page"
    fi

    rm -f "/www/user/${SCRIPT_NAME}.js"

    Print_Output info "Web UI removed"
    return 0
}

################################################################################
# Startup Hook Functions
################################################################################

# Add entry to post-mount script
Setup_PostMount() {
    Print_Output info "Configuring post-mount hook..."

    mkdir -p "$SCRIPTS_DIR"

    if [ -f "$POST_MOUNT" ]; then
        # Check if already configured
        if grep -q "$SCRIPT_NAME" "$POST_MOUNT"; then
            Print_Output info "post-mount hook already configured"
            return 0
        fi

        # Append to existing file
        cat >> "$POST_MOUNT" << 'POSTMOUNT'

# acme-wrapper: Mount wrapper script
if [ -x /jffs/addons/acme-wrapper/asus-wrapper-acme.sh ]; then
    sleep 5  # Wait for Entware
    /bin/mount -o bind /jffs/addons/acme-wrapper/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
POSTMOUNT
    else
        # Create new post-mount script
        cat > "$POST_MOUNT" << 'POSTMOUNT'
#!/bin/sh

# acme-wrapper: Mount wrapper script
if [ -x /jffs/addons/acme-wrapper/asus-wrapper-acme.sh ]; then
    sleep 5  # Wait for Entware
    /bin/mount -o bind /jffs/addons/acme-wrapper/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
POSTMOUNT
    fi

    chmod +x "$POST_MOUNT"
    Print_Output info "post-mount hook configured"
    return 0
}

# Remove entry from post-mount script
Remove_PostMount() {
    Print_Output info "Removing post-mount hook..."

    if [ -f "$POST_MOUNT" ]; then
        # Remove our section
        sed -i '/# acme-wrapper:/,/^fi$/d' "$POST_MOUNT"
        # Clean up empty lines
        sed -i '/^$/N;/^\n$/d' "$POST_MOUNT"
    fi

    Print_Output info "post-mount hook removed"
    return 0
}

# Add entry to service-event script
Setup_ServiceEvent() {
    Print_Output info "Configuring service-event hook..."

    mkdir -p "$SCRIPTS_DIR"

    if [ -f "$SERVICE_EVENT" ]; then
        # Check if already configured
        if grep -q "$SCRIPT_NAME" "$SERVICE_EVENT"; then
            Print_Output info "service-event hook already configured"
            return 0
        fi

        # Append to existing file
        cat >> "$SERVICE_EVENT" << 'SERVICEEVENT'

# acme-wrapper: Handle web UI events
if [ "$2" = "acmewrapper" ]; then
    /jffs/addons/acme-wrapper/acme-wrapper.sh service_event "$1" "$2"
fi
SERVICEEVENT
    else
        # Create new service-event script
        cat > "$SERVICE_EVENT" << 'SERVICEEVENT'
#!/bin/sh

# acme-wrapper: Handle web UI events
if [ "$2" = "acmewrapper" ]; then
    /jffs/addons/acme-wrapper/acme-wrapper.sh service_event "$1" "$2"
fi
SERVICEEVENT
    fi

    chmod +x "$SERVICE_EVENT"
    Print_Output info "service-event hook configured"
    return 0
}

# Remove entry from service-event script
Remove_ServiceEvent() {
    Print_Output info "Removing service-event hook..."

    if [ -f "$SERVICE_EVENT" ]; then
        # Remove our section
        sed -i '/# acme-wrapper:/,/^fi$/d' "$SERVICE_EVENT"
        # Clean up empty lines
        sed -i '/^$/N;/^\n$/d' "$SERVICE_EVENT"
    fi

    Print_Output info "service-event hook removed"
    return 0
}

################################################################################
# Bind Mount Functions
################################################################################

# Mount the wrapper script over system acme.sh
Mount_Wrapper() {
    Print_Output info "Mounting wrapper..."

    if ! [ -x "$WRAPPER_SCRIPT" ]; then
        Print_Output error "Wrapper script not found: $WRAPPER_SCRIPT"
        return 1
    fi

    # Unmount if already mounted
    if mount | grep -q "$SYSTEM_ACME_SH"; then
        umount "$SYSTEM_ACME_SH" 2>/dev/null
    fi

    # Mount wrapper
    if mount -o bind "$WRAPPER_SCRIPT" "$SYSTEM_ACME_SH"; then
        Print_Output info "Wrapper mounted successfully"
        return 0
    else
        Print_Output error "Failed to mount wrapper"
        return 1
    fi
}

# Unmount the wrapper script
Unmount_Wrapper() {
    Print_Output info "Unmounting wrapper..."

    if mount | grep -q "$SYSTEM_ACME_SH"; then
        if umount "$SYSTEM_ACME_SH"; then
            Print_Output info "Wrapper unmounted"
            return 0
        else
            Print_Output error "Failed to unmount wrapper"
            return 1
        fi
    else
        Print_Output info "Wrapper not mounted"
    fi

    return 0
}

################################################################################
# Migration Functions
################################################################################

# Check for existing manual installation
Check_Legacy_Install() {
    if [ -f "/jffs/sbin/asus-wrapper-acme.sh" ]; then
        return 0
    fi
    return 1
}

# Migrate from legacy installation
Migrate_Legacy() {
    Print_Output info "Migrating from legacy installation..."

    local legacy_script="/jffs/sbin/asus-wrapper-acme.sh"

    # Unmount old wrapper
    if mount | grep -q "$SYSTEM_ACME_SH"; then
        umount "$SYSTEM_ACME_SH" 2>/dev/null
    fi

    # Remove old post-mount entry
    if [ -f "$POST_MOUNT" ]; then
        sed -i '/\/jffs\/sbin\/asus-wrapper-acme.sh/d' "$POST_MOUNT"
    fi

    # Remove old script
    if [ -f "$legacy_script" ]; then
        rm -f "$legacy_script"
        rmdir /jffs/sbin 2>/dev/null || true
    fi

    # Remove old tools location
    if [ -d "/jffs/tools" ]; then
        rm -f /jffs/tools/validate-acme-wrapper.sh
        rm -f /jffs/tools/diagnose-acme-issue.sh
        rmdir /jffs/tools 2>/dev/null || true
    fi

    Print_Output info "Legacy installation migrated"
    return 0
}

################################################################################
# Download Functions
################################################################################

Download_File() {
    local url="$1"
    local dest="$2"

    if curl -fsSL "$url" -o "$dest"; then
        return 0
    else
        Print_Output error "Failed to download: $url"
        return 1
    fi
}

Download_Addon_Files() {
    local base_url
    base_url=$(Get_Script_URL)
    local branch
    branch=$(Get_Branch)

    Print_Output info "Downloading addon files from branch: $branch"

    # Create directories
    mkdir -p "$ADDON_DIR"
    mkdir -p "$ADDON_DIR/tools"
    mkdir -p "$LE_DIR"

    # Download wrapper script
    if ! Download_File "${base_url}/scripts/asus-wrapper-acme.sh" "$WRAPPER_SCRIPT"; then
        return 1
    fi
    chmod +x "$WRAPPER_SCRIPT"

    # Download Web UI files
    Download_File "${base_url}/addon/${SCRIPT_NAME}.asp" "$WEBAPP_FILE" || true
    Download_File "${base_url}/addon/${SCRIPT_NAME}.js" "$WEBAPP_JS" || true

    # Download tools
    Download_File "${base_url}/tools/validate-acme-wrapper.sh" "$ADDON_DIR/tools/validate-acme-wrapper.sh" || true
    Download_File "${base_url}/tools/diagnose-acme-issue.sh" "$ADDON_DIR/tools/diagnose-acme-issue.sh" || true
    chmod +x "$ADDON_DIR/tools/"*.sh 2>/dev/null || true

    # Download this script (self-update)
    Download_File "${base_url}/addon/acme-wrapper.sh" "$ADDON_DIR/acme-wrapper.sh" || true
    chmod +x "$ADDON_DIR/acme-wrapper.sh"

    Print_Output info "Addon files downloaded"
    return 0
}

################################################################################
# Install/Uninstall Functions
################################################################################

Menu_Install() {
    Print_Header

    local branch
    branch=$(Get_Branch)
    Print_Output info "Installing $SCRIPT_NAME from branch: $branch"

    # Validate branch exists
    if ! Validate_Branch "$branch"; then
        Print_Output error "Branch '$branch' not found in repository"
        return 1
    fi

    # Check lock
    if ! Check_Lock; then
        return 1
    fi

    # Check prerequisites
    if ! Check_Prerequisites; then
        Print_Output error "Prerequisites not met, aborting installation"
        return 1
    fi

    # Check for legacy install
    if Check_Legacy_Install; then
        Print_Output warn "Legacy installation detected"
        if Confirm_Action "Migrate existing installation?"; then
            Migrate_Legacy
        else
            Print_Output error "Cannot install alongside legacy installation"
            return 1
        fi
    fi

    # Download files
    if ! Download_Addon_Files; then
        Print_Output error "Failed to download addon files"
        return 1
    fi

    # Save branch preference
    Set_Setting "branch" "$branch"

    # Create default config
    ACME_WRAPPER_DNS_API="${ACME_WRAPPER_DNS_API:-dns_aws}"
    ACME_WRAPPER_DEBUG="${ACME_WRAPPER_DEBUG:-0}"
    ACME_WRAPPER_DNSSLEEP="${ACME_WRAPPER_DNSSLEEP:-120}"
    Save_Config

    # Create domains file if missing
    if [ ! -f "$DOMAINS_FILE" ]; then
        cat > "$DOMAINS_FILE" << 'EOF'
# Configure your domains here
# Format: *.yourdomain.com|yourdomain.com
# Uncomment and edit the line below:
# *.yourdomain.com|yourdomain.com
EOF
        Print_Output warn "Created sample domains file: $DOMAINS_FILE"
    fi

    # Setup hooks
    Setup_PostMount
    Setup_ServiceEvent

    # Mount Web UI
    Mount_WebUI

    # Mount wrapper
    Mount_Wrapper

    # Store installation info
    Set_Setting "version" "$SCRIPT_VERSION"
    Set_Setting "installed" "$(date '+%Y-%m-%d %H:%M:%S')"

    Print_Output info "Installation complete!"
    printf '\n'
    Print_Output info "Next steps:"
    printf '  1. Configure domains: nano %s\n' "$DOMAINS_FILE"
    printf '  2. Add DNS credentials: nano %s\n' "$ACCOUNT_CONF"
    printf '  3. Issue certificate: service restart_letsencrypt\n'
    printf '  4. Or use the Web UI: Administration -> Tools -> ACME Wrapper\n'
    printf '\n'

    return 0
}

Menu_Uninstall() {
    Print_Header
    Print_Output warn "Uninstalling $SCRIPT_NAME..."

    if ! Check_Lock; then
        return 1
    fi

    # Confirm
    if ! Confirm_Action "Are you sure you want to uninstall?"; then
        Print_Output info "Uninstall cancelled"
        return 0
    fi

    # Ask about config backup
    local backup_config=0
    if Confirm_Action "Backup configuration files?"; then
        backup_config=1
    fi

    # Unmount wrapper
    Unmount_Wrapper

    # Unmount Web UI
    Unmount_WebUI

    # Remove hooks
    Remove_PostMount
    Remove_ServiceEvent

    # Backup config if requested
    if [ "$backup_config" = "1" ]; then
        local backup_dir
        backup_dir="/jffs/backup-${SCRIPT_NAME}-$(date '+%Y%m%d')"
        mkdir -p "$backup_dir"

        [ -f "$SCRIPT_CONF" ] && cp "$SCRIPT_CONF" "$backup_dir/"
        [ -f "$DOMAINS_FILE" ] && cp "$DOMAINS_FILE" "$backup_dir/"
        [ -f "$ACCOUNT_CONF" ] && cp "$ACCOUNT_CONF" "$backup_dir/"

        Print_Output info "Configuration backed up to: $backup_dir"
    fi

    # Clear settings
    Clear_Settings

    # Remove addon directory
    rm -rf "$ADDON_DIR"

    # Note: We don't remove /jffs/.le as it contains user data

    Print_Output info "Uninstallation complete"
    return 0
}

Menu_Update() {
    Print_Header

    local branch
    branch=$(Get_Branch)
    Print_Output info "Updating $SCRIPT_NAME from branch: $branch"

    # Validate branch exists
    if ! Validate_Branch "$branch"; then
        Print_Output error "Branch '$branch' not found in repository"
        return 1
    fi

    if ! Check_Lock; then
        return 1
    fi

    # Store current config
    Load_Config
    local current_dns_api="$ACME_WRAPPER_DNS_API"
    local current_debug="$ACME_WRAPPER_DEBUG"
    local current_dnssleep="$ACME_WRAPPER_DNSSLEEP"

    # Download new files
    if ! Download_Addon_Files; then
        Print_Output error "Update failed"
        return 1
    fi

    # Restore config
    ACME_WRAPPER_DNS_API="$current_dns_api"
    ACME_WRAPPER_DEBUG="$current_debug"
    ACME_WRAPPER_DNSSLEEP="$current_dnssleep"
    Save_Config

    # Save branch preference (in case it was changed via SCRIPT_BRANCH)
    Set_Setting "branch" "$branch"

    # Remount wrapper
    Mount_Wrapper

    # Remount Web UI
    Unmount_WebUI
    Mount_WebUI

    # Update version in settings
    Set_Setting "version" "$SCRIPT_VERSION"
    Set_Setting "updated" "$(date '+%Y-%m-%d %H:%M:%S')"

    Print_Output info "Update complete: v$SCRIPT_VERSION (branch: $branch)"
    return 0
}

################################################################################
# Status and Info Functions
################################################################################

Menu_Status() {
    Print_Header

    local installed_version
    installed_version=$(Get_Setting "version" "not installed")

    local current_branch
    current_branch=$(Get_Branch)

    printf '%bInstallation Status:%b\n' "$COL_BOLD" "$COL_RESET"
    printf '  Addon version:    %s\n' "$installed_version"
    printf '  Script version:   %s\n' "$SCRIPT_VERSION"
    printf '  Update branch:    %s\n' "$current_branch"
    printf '  Addon directory:  %s\n' "$ADDON_DIR"

    # Check mount status
    printf '\n%bMount Status:%b\n' "$COL_BOLD" "$COL_RESET"
    if mount | grep -q "$SYSTEM_ACME_SH"; then
        printf '  Wrapper:          %b[MOUNTED]%b\n' "$COL_GREEN" "$COL_RESET"
    else
        printf '  Wrapper:          %b[NOT MOUNTED]%b\n' "$COL_RED" "$COL_RESET"
    fi

    # Check Web UI
    local webui_page
    webui_page=$(Get_Setting "webui_page" "")
    if [ -n "$webui_page" ] && [ -f "/www/user/$webui_page" ]; then
        printf '  Web UI:           %b[ACTIVE]%b (%s)\n' "$COL_GREEN" "$COL_RESET" "$webui_page"
    else
        printf '  Web UI:           %b[NOT ACTIVE]%b\n' "$COL_YELLOW" "$COL_RESET"
    fi

    # Check acme.sh
    printf '\n%bacme.sh Status:%b\n' "$COL_BOLD" "$COL_RESET"
    if [ -x "$REAL_ACME_SH" ]; then
        printf '  Location:         %s\n' "$REAL_ACME_SH"
        printf '  Version:          %s\n' "$($REAL_ACME_SH --version 2>/dev/null | head -1)"
    else
        printf '  %b[NOT INSTALLED]%b\n' "$COL_RED" "$COL_RESET"
    fi

    # Check configuration
    printf '\n%bConfiguration:%b\n' "$COL_BOLD" "$COL_RESET"
    Load_Config
    printf '  DNS API:          %s\n' "${ACME_WRAPPER_DNS_API:-dns_aws}"
    printf '  DNS Sleep:        %s seconds\n' "${ACME_WRAPPER_DNSSLEEP:-120}"
    printf '  Debug mode:       %s\n' "${ACME_WRAPPER_DEBUG:-0}"

    # Check domains file
    printf '\n%bDomains:%b\n' "$COL_BOLD" "$COL_RESET"
    if [ -f "$DOMAINS_FILE" ]; then
        local domain_count
        domain_count=$(grep -cv '^#\|^$' "$DOMAINS_FILE" 2>/dev/null || echo 0)
        printf '  Domains file:     %s (%d entries)\n' "$DOMAINS_FILE" "$domain_count"

        if [ "$domain_count" -gt 0 ]; then
            printf '  Configured domains:\n'
            grep -v '^#' "$DOMAINS_FILE" | grep -v '^$' | while read -r line; do
                printf '    - %s\n' "$line"
            done
        fi
    else
        printf '  Domains file:     %b[NOT FOUND]%b\n' "$COL_RED" "$COL_RESET"
    fi

    # Check certificates
    printf '\n%bCertificates:%b\n' "$COL_BOLD" "$COL_RESET"
    local cert_home="/jffs/.le"
    if [ -d "$cert_home" ]; then
        local cert_count=0
        for cert_dir in "$cert_home"/*_ecc; do
            if [ -d "$cert_dir" ] && [ -f "$cert_dir/fullchain.pem" ]; then
                cert_count=$((cert_count + 1))
                local cert_name
                cert_name=$(basename "$cert_dir" | sed 's/_ecc$//')
                local expiry
                expiry=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                printf '    %s (expires: %s)\n' "$cert_name" "$expiry"
            fi
        done

        if [ "$cert_count" -eq 0 ]; then
            printf '  No certificates found\n'
        fi
    else
        printf '  Certificate directory not found\n'
    fi

    printf '\n'
    return 0
}

################################################################################
# Service Event Handler
################################################################################

Handle_ServiceEvent() {
    local action="$1"
    local event="$2"

    case "$action" in
        start)
            # Called when web UI saves settings
            WebUI_Apply
            ;;
        restart)
            # Called when user clicks restart
            Mount_Wrapper
            ;;
    esac
}

WebUI_Apply() {
    Print_Output info "Applying Web UI settings..."

    # Read settings from custom_settings.txt
    local dns_api
    local debug_mode
    local dns_sleep
    local domains

    dns_api=$(Get_Setting "dns_api" "dns_aws")
    debug_mode=$(Get_Setting "debug" "0")
    dns_sleep=$(Get_Setting "dnssleep" "120")
    domains=$(Get_Setting "domains" "")

    # Update config
    ACME_WRAPPER_DNS_API="$dns_api"
    ACME_WRAPPER_DEBUG="$debug_mode"
    ACME_WRAPPER_DNSSLEEP="$dns_sleep"
    Save_Config

    # Update domains file if provided
    if [ -n "$domains" ]; then
        # Decode domains (newlines encoded as \n)
        printf '%s\n' "$domains" | sed 's/\\n/\n/g' > "$DOMAINS_FILE"
        Print_Output info "Updated domains file"
    fi

    # Update credentials in account.conf if any were provided
    # Credentials are stored as cred_KEY_NAME in custom_settings
    if [ -f "$CUSTOM_SETTINGS" ] && grep -q "^${SCRIPT_NAME}_cred_" "$CUSTOM_SETTINGS" 2>/dev/null; then
        mkdir -p "$(dirname "$ACCOUNT_CONF")"

        # Process each credential setting
        local cred_lines
        cred_lines=$(grep "^${SCRIPT_NAME}_cred_" "$CUSTOM_SETTINGS" 2>/dev/null)
        echo "$cred_lines" | while IFS=' ' read -r key value; do
            # Extract the actual credential key (remove prefix)
            local cred_key
            cred_key=$(echo "$key" | sed "s/^${SCRIPT_NAME}_cred_//")
            if [ -n "$cred_key" ] && [ -n "$value" ]; then
                # Update or add to account.conf
                if grep -q "^${cred_key}=" "$ACCOUNT_CONF" 2>/dev/null; then
                    # Update existing
                    sed -i "s|^${cred_key}=.*|${cred_key}='${value}'|" "$ACCOUNT_CONF"
                else
                    # Add new
                    echo "${cred_key}='${value}'" >> "$ACCOUNT_CONF"
                fi
            fi
        done

        Print_Output info "Updated credentials in account.conf"

        # Clean up credential settings from custom_settings (they're now in account.conf)
        sed -i "/^${SCRIPT_NAME}_cred_/d" "$CUSTOM_SETTINGS"
    fi

    Print_Output info "Settings applied"
    return 0
}

################################################################################
# Interactive Menu
################################################################################

Show_Menu() {
    Print_Header

    local installed_version
    installed_version=$(Get_Setting "version" "")

    local current_branch
    current_branch=$(Get_Branch)

    if [ -z "$installed_version" ]; then
        printf '%bStatus:%b Not installed\n' "$COL_BOLD" "$COL_RESET"
    else
        printf '%bStatus:%b Installed (v%s)\n' "$COL_BOLD" "$COL_RESET" "$installed_version"
    fi
    printf '%bBranch:%b %s\n\n' "$COL_BOLD" "$COL_RESET" "$current_branch"

    printf '  1.  Install\n'
    printf '  2.  Uninstall\n'
    printf '  3.  Update\n'
    printf '  4.  Status\n'
    printf '  5.  Configure DNS API\n'
    printf '  6.  Edit domains\n'
    printf '  7.  Issue certificates\n'
    printf '  8.  View logs\n'
    printf '  9.  Switch branch\n'
    printf '\n'
    printf '  e.  Exit\n'
    printf '\n'
    printf 'Choose an option: '

    local choice
    choice=$(Read_Input)

    case "$choice" in
        1) Menu_Install ;;
        2) Menu_Uninstall ;;
        3) Menu_Update ;;
        4) Menu_Status ;;
        5) Configure_DNS_API ;;
        6) Edit_Domains ;;
        7) Issue_Certificates ;;
        8) View_Logs ;;
        9) Switch_Branch ;;
        e|E|exit) exit 0 ;;
        *)
            Print_Output warn "Invalid option"
            sleep 1
            ;;
    esac

    # Return to menu after action
    printf '\nPress Enter to continue...'
    Read_Input > /dev/null
    Show_Menu
}

Configure_DNS_API() {
    Print_Header
    printf 'Select DNS Provider:\n\n'
    printf '  1.  AWS Route53       (dns_aws)\n'
    printf '  2.  Cloudflare        (dns_cf)\n'
    printf '  3.  GoDaddy           (dns_gd)\n'
    printf '  4.  DigitalOcean      (dns_dgon)\n'
    printf '  5.  Namecheap         (dns_namecheap)\n'
    printf '  6.  Linode            (dns_linode_v4)\n'
    printf '  7.  Vultr             (dns_vultr)\n'
    printf '  8.  Other (manual entry)\n'
    printf '\n'
    printf 'Choose an option: '

    local choice
    choice=$(Read_Input)

    local dns_api=""
    case "$choice" in
        1) dns_api="dns_aws" ;;
        2) dns_api="dns_cf" ;;
        3) dns_api="dns_gd" ;;
        4) dns_api="dns_dgon" ;;
        5) dns_api="dns_namecheap" ;;
        6) dns_api="dns_linode_v4" ;;
        7) dns_api="dns_vultr" ;;
        8)
            printf 'Enter DNS API name (e.g., dns_xxx): '
            dns_api=$(Read_Input)
            ;;
        *)
            Print_Output warn "Invalid option"
            return 1
            ;;
    esac

    if [ -n "$dns_api" ]; then
        Load_Config
        ACME_WRAPPER_DNS_API="$dns_api"
        Save_Config
        Set_Setting "dns_api" "$dns_api"
        Print_Output info "DNS API set to: $dns_api"
        Print_Output info "Don't forget to configure credentials in: $ACCOUNT_CONF"
    fi

    return 0
}

Switch_Branch() {
    Print_Header

    local current_branch
    current_branch=$(Get_Branch)

    printf 'Current branch: %b%s%b\n\n' "$COL_CYAN" "$current_branch" "$COL_RESET"
    printf 'Select branch:\n\n'
    printf '  1.  main     (stable releases)\n'
    printf '  2.  develop  (development/testing)\n'
    printf '  3.  Other (manual entry)\n'
    printf '\n'
    printf 'Choose an option: '

    local choice
    choice=$(Read_Input)

    local new_branch=""
    case "$choice" in
        1) new_branch="main" ;;
        2) new_branch="develop" ;;
        3)
            printf 'Enter branch name: '
            new_branch=$(Read_Input)
            ;;
        *)
            Print_Output warn "Invalid option"
            return 1
            ;;
    esac

    if [ -z "$new_branch" ]; then
        Print_Output warn "No branch specified"
        return 1
    fi

    if [ "$new_branch" = "$current_branch" ]; then
        Print_Output info "Already on branch: $new_branch"
        return 0
    fi

    # Validate branch exists
    Print_Output info "Validating branch '$new_branch'..."
    if ! Validate_Branch "$new_branch"; then
        Print_Output error "Branch '$new_branch' not found in repository"
        return 1
    fi

    # Save branch preference
    Set_Branch "$new_branch"
    Print_Output info "Branch switched to: $new_branch"
    Print_Output info "Run 'Update' to download files from the new branch"

    return 0
}

Edit_Domains() {
    if command -v nano >/dev/null 2>&1; then
        nano "$DOMAINS_FILE"
    elif command -v vi >/dev/null 2>&1; then
        vi "$DOMAINS_FILE"
    else
        Print_Output error "No text editor available"
        Print_Output info "Edit manually: $DOMAINS_FILE"
    fi
}

Issue_Certificates() {
    Print_Output info "Triggering certificate issuance..."
    service restart_letsencrypt
    Print_Output info "Certificate issuance triggered"
    Print_Output info "Check router logs for progress"
}

View_Logs() {
    Print_Header
    printf 'Recent log entries:\n\n'

    if [ -f "$SCRIPT_LOG" ]; then
        tail -50 "$SCRIPT_LOG"
    else
        Print_Output info "No log file found"
    fi

    printf '\nSystem log (acme related):\n\n'
    grep -i "acme" /tmp/syslog.log 2>/dev/null | tail -20
}

################################################################################
# Main Entry Point
################################################################################

# Parse command line options
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch=*)
                SCRIPT_BRANCH="${1#*=}"
                shift
                ;;
            -b|--branch)
                SCRIPT_BRANCH="$2"
                shift 2
                ;;
            *)
                # Not an option, return remaining args
                echo "$@"
                return
                ;;
        esac
    done
}

main() {
    # Parse options first (--branch, etc.)
    local args
    args=$(parse_args "$@")
    # shellcheck disable=SC2086
    set -- $args

    case "$1" in
        install)
            Menu_Install
            ;;
        uninstall)
            Menu_Uninstall
            ;;
        update)
            Menu_Update
            ;;
        status)
            Menu_Status
            ;;
        branch)
            if [ -n "$2" ]; then
                # Set branch
                if Validate_Branch "$2"; then
                    Set_Branch "$2"
                    Print_Output info "Branch set to: $2"
                else
                    Print_Output error "Branch '$2' not found in repository"
                    exit 1
                fi
            else
                # Show current branch
                printf 'Current branch: %s\n' "$(Get_Branch)"
            fi
            ;;
        service_event)
            Handle_ServiceEvent "$2" "$3"
            ;;
        webui)
            WebUI_Apply
            ;;
        mount)
            Mount_Wrapper
            ;;
        unmount)
            Unmount_Wrapper
            ;;
        menu|"")
            Show_Menu
            ;;
        *)
            printf 'Usage: %s [--branch=BRANCH] {install|uninstall|update|status|branch [NAME]|menu}\n' "$0"
            printf '\nOptions:\n'
            printf '  --branch=NAME, -b NAME    Use specified branch for install/update\n'
            printf '\nCommands:\n'
            printf '  install      Install the addon\n'
            printf '  uninstall    Remove the addon\n'
            printf '  update       Update to latest version\n'
            printf '  status       Show addon status\n'
            printf '  branch       Show or set the update branch\n'
            printf '  menu         Interactive menu (default)\n'
            exit 1
            ;;
    esac
}

main "$@"
