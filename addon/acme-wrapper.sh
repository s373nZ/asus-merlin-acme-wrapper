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

print_output() {
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

print_header() {
    printf '\n%b============================================%b\n' "$COL_CYAN" "$COL_RESET"
    printf '%b  %s v%s%b\n' "$COL_BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$COL_RESET"
    printf '%b============================================%b\n\n' "$COL_CYAN" "$COL_RESET"
}

# Read user input, handling piped scripts (curl | sh) by reading from /dev/tty
read_input() {
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

confirm_action() {
    local prompt="$1"
    local response

    printf '%s [y/N]: ' "$prompt"
    response=$(read_input)

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
get_setting() {
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
set_setting() {
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
clear_settings() {
    if [ -f "$CUSTOM_SETTINGS" ]; then
        sed -i "/^${SCRIPT_NAME}_/d" "$CUSTOM_SETTINGS"
    fi
}

################################################################################
# Branch Configuration
################################################################################

# Get the configured branch (from settings, env var, or default)
get_branch() {
    # Command-line/env override takes precedence
    if [ -n "$SCRIPT_BRANCH" ]; then
        echo "$SCRIPT_BRANCH"
        return
    fi

    # Check settings
    local saved_branch
    saved_branch=$(get_setting "branch" "")
    if [ -n "$saved_branch" ]; then
        echo "$saved_branch"
        return
    fi

    # Default branch
    echo "$SCRIPT_DEFAULT_BRANCH"
}

# Set the branch for this session and save to settings
set_branch() {
    local branch="$1"
    SCRIPT_BRANCH="$branch"
    set_setting "branch" "$branch"
}

# Get the raw GitHub URL for the current branch
get_script_url() {
    local branch
    branch=$(get_branch)
    echo "https://raw.githubusercontent.com/${SCRIPT_REPO}/${branch}"
}

# Validate that a branch exists on the remote repository
validate_branch() {
    local branch="$1"
    local test_url="https://raw.githubusercontent.com/${SCRIPT_REPO}/${branch}/addon/acme-wrapper.sh"

    if curl -fsSL --head "$test_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Load configuration from conf file
load_config() {
    if [ -f "$SCRIPT_CONF" ]; then
        # shellcheck source=/dev/null
        . "$SCRIPT_CONF"
    fi
}

# Save configuration to conf file
save_config() {
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

check_lock() {
    local lockfile="/tmp/${SCRIPT_NAME}.lock"

    if [ -f "$lockfile" ]; then
        local pid
        pid=$(cat "$lockfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            print_output error "Another instance is running (PID: $pid)"
            return 1
        fi
        rm -f "$lockfile"
    fi

    echo $$ > "$lockfile"
    trap 'rm -f "$lockfile"' EXIT
    return 0
}

check_jffs() {
    if [ ! -d "/jffs" ]; then
        print_output error "JFFS partition not found"
        return 1
    fi

    if [ ! -w "/jffs" ]; then
        print_output error "JFFS partition is not writable"
        return 1
    fi

    return 0
}

check_entware() {
    if [ ! -d "/opt/bin" ]; then
        print_output error "Entware not installed"
        print_output info "Install Entware first: amtm -> i"
        return 1
    fi
    return 0
}

check_acme_sh() {
    if [ ! -x "$REAL_ACME_SH" ]; then
        print_output warn "acme.sh not found at $REAL_ACME_SH"
        return 1
    fi
    return 0
}

check_prerequisites() {
    print_output info "Checking prerequisites..."

    if ! check_jffs; then
        return 1
    fi
    print_output info "JFFS partition OK"

    if ! check_entware; then
        return 1
    fi
    print_output info "Entware OK"

    if ! check_acme_sh; then
        print_output info "Attempting to install acme.sh..."
        if opkg update && opkg install acme; then
            if check_acme_sh; then
                print_output info "acme.sh installed successfully"
            else
                print_output error "Failed to install acme.sh"
                return 1
            fi
        else
            print_output error "Failed to install acme.sh via opkg"
            return 1
        fi
    else
        print_output info "acme.sh OK: $($REAL_ACME_SH --version 2>/dev/null | head -1)"
    fi

    return 0
}

################################################################################
# Web UI Functions (using Merlin helper.sh)
################################################################################

# Find an available userN.asp slot
# Uses am_get_webui_page from helper.sh
get_webui_page() {
    # First check if we already have a page assigned
    local existing_page
    existing_page=$(get_setting "webui_page" "")
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
mount_webui() {
    print_output info "Setting up Web UI..."

    local page
    page=$(get_webui_page)

    if [ -z "$page" ]; then
        print_output error "No available Web UI slot"
        return 1
    fi

    print_output info "Using Web UI slot: $page"

    # Copy our ASP file
    if [ -f "$WEBAPP_FILE" ]; then
        cp "$WEBAPP_FILE" "/www/user/$page"
    else
        print_output warn "Web UI file not found, skipping"
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
    set_setting "webui_page" "$page"

    print_output info "Web UI mounted successfully"
    return 0
}

# Unmount the Web UI page
unmount_webui() {
    print_output info "Removing Web UI..."

    local page
    page=$(get_setting "webui_page" "")

    # Unmount menuTree
    local menutree_file="/www/require/modules/menuTree.js"
    umount "$menutree_file" 2>/dev/null

    # Remove our files
    if [ -n "$page" ] && [ -f "/www/user/$page" ]; then
        rm -f "/www/user/$page"
    fi

    rm -f "/www/user/${SCRIPT_NAME}.js"

    print_output info "Web UI removed"
    return 0
}

################################################################################
# Startup Hook Functions
################################################################################

# Add entry to post-mount script
setup_post_mount() {
    print_output info "Configuring post-mount hook..."

    mkdir -p "$SCRIPTS_DIR"

    if [ -f "$POST_MOUNT" ]; then
        # Check if already configured
        if grep -q "$SCRIPT_NAME" "$POST_MOUNT"; then
            print_output info "post-mount hook already configured"
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
    print_output info "post-mount hook configured"
    return 0
}

# Remove entry from post-mount script
remove_post_mount() {
    print_output info "Removing post-mount hook..."

    if [ -f "$POST_MOUNT" ]; then
        # Remove our section
        sed -i '/# acme-wrapper:/,/^fi$/d' "$POST_MOUNT"
        # Clean up empty lines
        sed -i '/^$/N;/^\n$/d' "$POST_MOUNT"
    fi

    print_output info "post-mount hook removed"
    return 0
}

# Add entry to service-event script
setup_service_event() {
    print_output info "Configuring service-event hook..."

    mkdir -p "$SCRIPTS_DIR"

    if [ -f "$SERVICE_EVENT" ]; then
        # Check if already configured
        if grep -q "$SCRIPT_NAME" "$SERVICE_EVENT"; then
            print_output info "service-event hook already configured"
            return 0
        fi

        # Append to existing file
        cat >> "$SERVICE_EVENT" << 'SERVICEEVENT'

# acme-wrapper: Handle web UI events
case "$2" in
    acmewrapper|acmewrapperstatus)
        /jffs/addons/acme-wrapper/acme-wrapper.sh service_event "$1" "$2"
        ;;
esac
SERVICEEVENT
    else
        # Create new service-event script
        cat > "$SERVICE_EVENT" << 'SERVICEEVENT'
#!/bin/sh

# acme-wrapper: Handle web UI events
case "$2" in
    acmewrapper|acmewrapperstatus)
        /jffs/addons/acme-wrapper/acme-wrapper.sh service_event "$1" "$2"
        ;;
esac
SERVICEEVENT
    fi

    chmod +x "$SERVICE_EVENT"
    print_output info "service-event hook configured"
    return 0
}

# Remove entry from service-event script
remove_service_event() {
    print_output info "Removing service-event hook..."

    if [ -f "$SERVICE_EVENT" ]; then
        # Remove our section
        sed -i '/# acme-wrapper:/,/^esac$/d' "$SERVICE_EVENT"
        # Clean up empty lines
        sed -i '/^$/N;/^\n$/d' "$SERVICE_EVENT"
    fi

    print_output info "service-event hook removed"
    return 0
}

################################################################################
# Bind Mount Functions
################################################################################

# Mount the wrapper script over system acme.sh
mount_wrapper() {
    print_output info "Mounting wrapper..."

    if ! [ -x "$WRAPPER_SCRIPT" ]; then
        print_output error "Wrapper script not found: $WRAPPER_SCRIPT"
        return 1
    fi

    # Unmount if already mounted
    if mount | grep -q "$SYSTEM_ACME_SH"; then
        umount "$SYSTEM_ACME_SH" 2>/dev/null
    fi

    # Mount wrapper
    if mount -o bind "$WRAPPER_SCRIPT" "$SYSTEM_ACME_SH"; then
        print_output info "Wrapper mounted successfully"
        return 0
    else
        print_output error "Failed to mount wrapper"
        return 1
    fi
}

# Unmount the wrapper script
unmount_wrapper() {
    print_output info "Unmounting wrapper..."

    if mount | grep -q "$SYSTEM_ACME_SH"; then
        if umount "$SYSTEM_ACME_SH"; then
            print_output info "Wrapper unmounted"
            return 0
        else
            print_output error "Failed to unmount wrapper"
            return 1
        fi
    else
        print_output info "Wrapper not mounted"
    fi

    return 0
}

################################################################################
# Download Functions
################################################################################

download_file() {
    local url="$1"
    local dest="$2"

    if curl -fsSL "$url" -o "$dest"; then
        return 0
    else
        print_output error "Failed to download: $url"
        return 1
    fi
}

download_addon_files() {
    local base_url
    base_url=$(get_script_url)
    local branch
    branch=$(get_branch)

    print_output info "Downloading addon files from branch: $branch"

    # Create directories
    mkdir -p "$ADDON_DIR"
    mkdir -p "$ADDON_DIR/tools"
    mkdir -p "$LE_DIR"

    # Download wrapper script
    if ! download_file "${base_url}/scripts/asus-wrapper-acme.sh" "$WRAPPER_SCRIPT"; then
        return 1
    fi
    chmod +x "$WRAPPER_SCRIPT"

    # Download Web UI files
    download_file "${base_url}/addon/${SCRIPT_NAME}.asp" "$WEBAPP_FILE" || true
    download_file "${base_url}/addon/${SCRIPT_NAME}.js" "$WEBAPP_JS" || true

    # Download tools
    download_file "${base_url}/tools/validate-acme-wrapper.sh" "$ADDON_DIR/tools/validate-acme-wrapper.sh" || true
    download_file "${base_url}/tools/diagnose-acme-issue.sh" "$ADDON_DIR/tools/diagnose-acme-issue.sh" || true
    chmod +x "$ADDON_DIR/tools/"*.sh 2>/dev/null || true

    # Download this script (self-update)
    download_file "${base_url}/addon/acme-wrapper.sh" "$ADDON_DIR/acme-wrapper.sh" || true
    chmod +x "$ADDON_DIR/acme-wrapper.sh"

    print_output info "Addon files downloaded"
    return 0
}

################################################################################
# Install/Uninstall Functions
################################################################################

menu_install() {
    print_header

    local branch
    branch=$(get_branch)
    print_output info "Installing $SCRIPT_NAME from branch: $branch"

    # Validate branch exists
    if ! validate_branch "$branch"; then
        print_output error "Branch '$branch' not found in repository"
        return 1
    fi

    # Check lock
    if ! check_lock; then
        return 1
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        print_output error "Prerequisites not met, aborting installation"
        return 1
    fi

    # Download files
    if ! download_addon_files; then
        print_output error "Failed to download addon files"
        return 1
    fi

    # Save branch preference
    set_setting "branch" "$branch"

    # Create default config
    ACME_WRAPPER_DNS_API="${ACME_WRAPPER_DNS_API:-dns_aws}"
    ACME_WRAPPER_DEBUG="${ACME_WRAPPER_DEBUG:-0}"
    ACME_WRAPPER_DNSSLEEP="${ACME_WRAPPER_DNSSLEEP:-120}"
    save_config

    # Create domains file if missing
    if [ ! -f "$DOMAINS_FILE" ]; then
        cat > "$DOMAINS_FILE" << 'EOF'
# Configure your domains here
# Format: *.yourdomain.com|yourdomain.com
# Uncomment and edit the line below:
# *.yourdomain.com|yourdomain.com
EOF
        print_output warn "Created sample domains file: $DOMAINS_FILE"
    fi

    # Setup hooks
    setup_post_mount
    setup_service_event

    # Mount Web UI
    mount_webui

    # Mount wrapper
    mount_wrapper

    # Initialize status
    update_status_settings

    # Store installation info
    set_setting "version" "$SCRIPT_VERSION"
    set_setting "installed" "$(date '+%Y-%m-%d %H:%M:%S')"

    print_output info "Installation complete!"
    printf '\n'
    print_output info "Next steps:"
    printf '  1. Configure domains: nano %s\n' "$DOMAINS_FILE"
    printf '  2. Add DNS credentials: nano %s\n' "$ACCOUNT_CONF"
    printf '  3. Issue certificate: service restart_letsencrypt\n'
    printf '  4. Or use the Web UI: Administration -> Tools -> ACME Wrapper\n'
    printf '\n'

    return 0
}

menu_uninstall() {
    print_header
    print_output warn "Uninstalling $SCRIPT_NAME..."

    if ! check_lock; then
        return 1
    fi

    # Confirm
    if ! confirm_action "Are you sure you want to uninstall?"; then
        print_output info "Uninstall cancelled"
        return 0
    fi

    # Ask about config backup
    local backup_config=0
    if confirm_action "Backup configuration files?"; then
        backup_config=1
    fi

    # Unmount wrapper
    unmount_wrapper

    # Unmount Web UI
    unmount_webui

    # Remove hooks
    remove_post_mount
    remove_service_event

    # Backup config if requested
    if [ "$backup_config" = "1" ]; then
        local backup_dir
        backup_dir="/jffs/backup-${SCRIPT_NAME}-$(date '+%Y%m%d')"
        mkdir -p "$backup_dir"

        [ -f "$SCRIPT_CONF" ] && cp "$SCRIPT_CONF" "$backup_dir/"
        [ -f "$DOMAINS_FILE" ] && cp "$DOMAINS_FILE" "$backup_dir/"
        [ -f "$ACCOUNT_CONF" ] && cp "$ACCOUNT_CONF" "$backup_dir/"

        print_output info "Configuration backed up to: $backup_dir"
    fi

    # Clear settings
    clear_settings

    # Remove addon directory
    rm -rf "$ADDON_DIR"

    # Note: We don't remove /jffs/.le as it contains user data

    print_output info "Uninstallation complete"
    return 0
}

menu_update() {
    print_header

    local branch
    branch=$(get_branch)
    print_output info "Updating $SCRIPT_NAME from branch: $branch"

    # Validate branch exists
    if ! validate_branch "$branch"; then
        print_output error "Branch '$branch' not found in repository"
        return 1
    fi

    if ! check_lock; then
        return 1
    fi

    # Store current config
    load_config
    local current_dns_api="$ACME_WRAPPER_DNS_API"
    local current_debug="$ACME_WRAPPER_DEBUG"
    local current_dnssleep="$ACME_WRAPPER_DNSSLEEP"

    # Download new files
    if ! download_addon_files; then
        print_output error "Update failed"
        return 1
    fi

    # Restore config
    ACME_WRAPPER_DNS_API="$current_dns_api"
    ACME_WRAPPER_DEBUG="$current_debug"
    ACME_WRAPPER_DNSSLEEP="$current_dnssleep"
    save_config

    # Save branch preference (in case it was changed via SCRIPT_BRANCH)
    set_setting "branch" "$branch"

    # Remount wrapper
    mount_wrapper

    # Remount Web UI
    unmount_webui
    mount_webui

    # Regenerate service-event hook (in case hook format changed)
    remove_service_event
    setup_service_event

    # Update version in settings
    set_setting "version" "$SCRIPT_VERSION"
    set_setting "updated" "$(date '+%Y-%m-%d %H:%M:%S')"

    print_output info "Update complete: v$SCRIPT_VERSION (branch: $branch)"
    return 0
}

################################################################################
# Status and Info Functions
################################################################################

menu_status() {
    print_header

    local installed_version
    installed_version=$(get_setting "version" "not installed")

    local current_branch
    current_branch=$(get_branch)

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
    webui_page=$(get_setting "webui_page" "")
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
    load_config
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
# Status Gathering Functions
################################################################################

# Get certificate status as pipe-delimited string
# Format: domain|expiry|status\ndomain|expiry|status
get_certificate_status() {
    local status=""
    local le_dir="${LE_DIR}"

    for cert_dir in "$le_dir"/*_ecc; do
        [ -d "$cert_dir" ] || continue
        local domain
        domain=$(basename "$cert_dir" | sed 's/_ecc$//')
        local fullchain="$cert_dir/fullchain.cer"

        if [ -f "$fullchain" ]; then
            local expiry
            expiry=$(openssl x509 -enddate -noout -in "$fullchain" 2>/dev/null | cut -d= -f2)
            # Format: domain|expiry|status
            if [ -n "$expiry" ]; then
                status="${status}${domain}|${expiry}|valid\\n"
            fi
        fi
    done
    printf '%s' "$status"
}

# Get system status as pipe-delimited string
# Format: mount_status|acme_version|wrapper_version
get_system_status() {
    local mount_status="not_mounted"
    local acme_version="not_installed"
    local wrapper_version="${SCRIPT_VERSION}"

    # Check mount
    if mount | grep -q "acme.sh"; then
        mount_status="mounted"
    fi

    # Get acme.sh version
    if [ -x "$REAL_ACME_SH" ]; then
        acme_version=$("$REAL_ACME_SH" --version 2>/dev/null | head -1)
    fi

    printf '%s|%s|%s' "$mount_status" "$acme_version" "$wrapper_version"
}

# Update status in custom_settings
update_status_settings() {
    local cert_status
    local sys_status

    cert_status=$(get_certificate_status)
    sys_status=$(get_system_status)

    set_setting "cert_status" "$cert_status"
    set_setting "sys_status" "$sys_status"

    print_output info "Status updated in custom_settings"
}

################################################################################
# Service Event Handler
################################################################################

handle_service_event() {
    local action="$1"
    local event="$2"

    case "$action" in
        start)
            case "$event" in
                acmewrapper)
                    # Called when web UI saves settings
                    webui_apply
                    update_status_settings
                    ;;
                acmewrapperstatus)
                    # Called when web UI refreshes status
                    update_status_settings
                    ;;
                *)
                    # Default: apply settings (for backward compatibility)
                    webui_apply
                    update_status_settings
                    ;;
            esac
            ;;
        restart)
            # Called when user clicks restart
            mount_wrapper
            ;;
    esac
}

webui_apply() {
    print_output info "Applying Web UI settings..."

    # Read settings from custom_settings.txt
    local dns_api
    local debug_mode
    local dns_sleep
    local domains

    dns_api=$(get_setting "dns_api" "dns_aws")
    debug_mode=$(get_setting "debug" "0")
    dns_sleep=$(get_setting "dnssleep" "120")
    domains=$(get_setting "domains" "")

    # Update config
    ACME_WRAPPER_DNS_API="$dns_api"
    ACME_WRAPPER_DEBUG="$debug_mode"
    ACME_WRAPPER_DNSSLEEP="$dns_sleep"
    save_config

    # Update domains file if provided
    if [ -n "$domains" ]; then
        # Decode domains (newlines encoded as \n)
        printf '%s\n' "$domains" | sed 's/\\n/\n/g' > "$DOMAINS_FILE"
        print_output info "Updated domains file"
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

        print_output info "Updated credentials in account.conf"

        # Clean up credential settings from custom_settings (they're now in account.conf)
        sed -i "/^${SCRIPT_NAME}_cred_/d" "$CUSTOM_SETTINGS"
    fi

    print_output info "Settings applied"
    return 0
}

################################################################################
# Interactive Menu
################################################################################

show_menu() {
    print_header

    local installed_version
    installed_version=$(get_setting "version" "")

    local current_branch
    current_branch=$(get_branch)

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
    choice=$(read_input)

    case "$choice" in
        1) menu_install ;;
        2) menu_uninstall ;;
        3) menu_update ;;
        4) menu_status ;;
        5) configure_dns_api ;;
        6) edit_domains ;;
        7) issue_certificates ;;
        8) view_logs ;;
        9) switch_branch ;;
        e|E|exit) exit 0 ;;
        *)
            print_output warn "Invalid option"
            sleep 1
            ;;
    esac

    # Return to menu after action
    printf '\nPress Enter to continue...'
    read_input > /dev/null
    show_menu
}

configure_dns_api() {
    print_header
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
    choice=$(read_input)

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
            dns_api=$(read_input)
            ;;
        *)
            print_output warn "Invalid option"
            return 1
            ;;
    esac

    if [ -n "$dns_api" ]; then
        load_config
        ACME_WRAPPER_DNS_API="$dns_api"
        save_config
        set_setting "dns_api" "$dns_api"
        print_output info "DNS API set to: $dns_api"
        print_output info "Don't forget to configure credentials in: $ACCOUNT_CONF"
    fi

    return 0
}

switch_branch() {
    print_header

    local current_branch
    current_branch=$(get_branch)

    printf 'Current branch: %b%s%b\n\n' "$COL_CYAN" "$current_branch" "$COL_RESET"
    printf 'Select branch:\n\n'
    printf '  1.  main     (stable releases)\n'
    printf '  2.  develop  (development/testing)\n'
    printf '  3.  Other (manual entry)\n'
    printf '\n'
    printf 'Choose an option: '

    local choice
    choice=$(read_input)

    local new_branch=""
    case "$choice" in
        1) new_branch="main" ;;
        2) new_branch="develop" ;;
        3)
            printf 'Enter branch name: '
            new_branch=$(read_input)
            ;;
        *)
            print_output warn "Invalid option"
            return 1
            ;;
    esac

    if [ -z "$new_branch" ]; then
        print_output warn "No branch specified"
        return 1
    fi

    if [ "$new_branch" = "$current_branch" ]; then
        print_output info "Already on branch: $new_branch"
        return 0
    fi

    # Validate branch exists
    print_output info "Validating branch '$new_branch'..."
    if ! validate_branch "$new_branch"; then
        print_output error "Branch '$new_branch' not found in repository"
        return 1
    fi

    # Save branch preference
    set_branch "$new_branch"
    print_output info "Branch switched to: $new_branch"
    print_output info "Run 'Update' to download files from the new branch"

    return 0
}

edit_domains() {
    if command -v nano >/dev/null 2>&1; then
        nano "$DOMAINS_FILE"
    elif command -v vi >/dev/null 2>&1; then
        vi "$DOMAINS_FILE"
    else
        print_output error "No text editor available"
        print_output info "Edit manually: $DOMAINS_FILE"
    fi
}

issue_certificates() {
    print_output info "Triggering certificate issuance..."
    service restart_letsencrypt
    print_output info "Certificate issuance triggered"
    print_output info "Check router logs for progress"
}

view_logs() {
    print_header
    printf 'Recent log entries:\n\n'

    if [ -f "$SCRIPT_LOG" ]; then
        tail -50 "$SCRIPT_LOG"
    else
        print_output info "No log file found"
    fi

    printf '\nSystem log (acme related):\n\n'
    grep -i "acme" /tmp/syslog.log 2>/dev/null | tail -20
}

################################################################################
# Main Entry Point
################################################################################

main() {
    # Parse options first (--branch, etc.)
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
                # Not an option, break to process command
                break
                ;;
        esac
    done

    case "$1" in
        install)
            menu_install
            ;;
        uninstall)
            menu_uninstall
            ;;
        update)
            menu_update
            ;;
        status)
            menu_status
            ;;
        branch)
            if [ -n "$2" ]; then
                # Set branch
                if validate_branch "$2"; then
                    set_branch "$2"
                    print_output info "Branch set to: $2"
                else
                    print_output error "Branch '$2' not found in repository"
                    exit 1
                fi
            else
                # Show current branch
                printf 'Current branch: %s\n' "$(get_branch)"
            fi
            ;;
        service_event)
            handle_service_event "$2" "$3"
            ;;
        webui)
            webui_apply
            ;;
        mount)
            mount_wrapper
            ;;
        unmount)
            unmount_wrapper
            ;;
        menu|"")
            show_menu
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
