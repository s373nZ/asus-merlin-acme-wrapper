#!/bin/sh

################################################################################
# asus-wrapper-acme.sh v1.0.4
#
# Wrapper for acme.sh on Asus routers running Merlin firmware.
# Intercepts Asus firmware's acme.sh calls to enable:
#   - DNS-based validation (instead of HTTP)
#   - Wildcard certificates
#   - Multiple SANs (Subject Alternative Names) in a single certificate
#
# Based on original concept by garycnew
# https://www.snbforums.com/threads/75233/
#
# Installation:
#   1. Place this script at /jffs/sbin/asus-wrapper-acme.sh
#   2. Make executable: chmod +x /jffs/sbin/asus-wrapper-acme.sh
#   3. Bind mount in /jffs/scripts/post-mount:
#      /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
#
# Configuration:
#   - Domains file: /jffs/.le/domains (one cert per line, pipe-delimited SANs)
#   - DNS API: Configured via ASUS_WRAPPER_DNS_API env var or defaults to dns_aws
#   - Real acme.sh: /opt/home/acme.sh/acme.sh (symlinked from /jffs/sbin/acme.sh)
#
# Example domains file:
#   *.example.yourdomain.com|example.yourdomain.com
#   *.example.com|example.com|www.example.com
#
# Note: The last domain in each line becomes the certificate directory name
################################################################################

#
# Configuration
#
readonly SCRIPT_VERSION="1.0.4"
readonly REAL_ACME_SH="/opt/home/acme.sh/acme.sh"
readonly DOMAINS_FILE="${ASUS_WRAPPER_ACME_DOMAINS:-/jffs/.le/domains}"
readonly DNS_API="${ASUS_WRAPPER_DNS_API:-dns_aws}"
readonly KEY_SUFFIX="_ecc"
readonly LOG_TAG="acme"

#
# Logging functions
#
log() {
    local level="$1"
    shift
    local msg="$*"
    echo "[$level] $msg"
    logger -p "user.$level" -t "$LOG_TAG" "$msg"
}

log_info() {
    log "info" "$@"
}

log_error() {
    log "error" "$@"
}

log_debug() {
    if [ "${ASUS_WRAPPER_DEBUG}" = "1" ]; then
        log "debug" "$@"
    fi
}

die() {
    log_error "$@"
    exit 1
}

#
# Validation functions
#
validate_prerequisites() {
    log_debug "Validating prerequisites..."

    # Check that real acme.sh exists
    if [ ! -x "$REAL_ACME_SH" ]; then
        die "Real acme.sh not found at $REAL_ACME_SH"
    fi

    # Check that domains file exists (only for cert operations)
    if echo "$*" | grep -qE '\-\-(issue|renew|deploy)'; then
        if [ ! -f "$DOMAINS_FILE" ]; then
            die "Domains file not found at $DOMAINS_FILE"
        fi

        if [ ! -r "$DOMAINS_FILE" ]; then
            die "Domains file not readable at $DOMAINS_FILE"
        fi

        # Check domains file is not empty
        if [ ! -s "$DOMAINS_FILE" ]; then
            die "Domains file is empty at $DOMAINS_FILE"
        fi
    fi

    log_debug "Prerequisites validated successfully"
}

#
# Parse Asus firmware arguments
#
parse_asus_args() {
    log_debug "Parsing Asus firmware arguments..."

    # Initialize variables
    ASUS_HOME=""
    ASUS_CERT_HOME=""
    ASUS_ACCOUNT_KEY=""
    ASUS_ACCOUNT_CONF=""
    ASUS_DOMAIN=""
    ASUS_USERAGENT=""
    ASUS_FULLCHAIN_FILE=""
    ASUS_KEY_FILE=""
    ASUS_DNSSLEEP=""
    ASUS_COMMAND=""
    ASUS_EXTRA_ARGS=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --home)
                ASUS_HOME="$2"
                shift 2
                ;;
            --certhome|--cert-home)
                ASUS_CERT_HOME="$2"
                shift 2
                ;;
            --accountkey)
                ASUS_ACCOUNT_KEY="$2"
                shift 2
                ;;
            --accountconf)
                ASUS_ACCOUNT_CONF="$2"
                shift 2
                ;;
            --domain)
                ASUS_DOMAIN="$2"
                shift 2
                ;;
            --useragent)
                ASUS_USERAGENT="$2"
                shift 2
                ;;
            --fullchain-file)
                ASUS_FULLCHAIN_FILE="$2"
                shift 2
                ;;
            --key-file)
                ASUS_KEY_FILE="$2"
                shift 2
                ;;
            --dnssleep)
                ASUS_DNSSLEEP="$2"
                shift 2
                ;;
            --issue|--renew|--revoke|--deploy)
                ASUS_COMMAND="$1"
                shift
                ;;
            --standalone)
                # Ignore --standalone, we're using DNS validation
                shift
                ;;
            --httpport)
                # Ignore httpport, not needed for DNS validation
                shift 2
                ;;
            *)
                # Collect other arguments
                ASUS_EXTRA_ARGS="$ASUS_EXTRA_ARGS $1"
                shift
                ;;
        esac
    done

    log_debug "Parsed Asus arguments:"
    log_debug "  HOME: $ASUS_HOME"
    log_debug "  CERT_HOME: $ASUS_CERT_HOME"
    log_debug "  COMMAND: $ASUS_COMMAND"
    log_debug "  EXTRA_ARGS: $ASUS_EXTRA_ARGS"
}

#
# Check if this is a pass-through command (no domain processing needed)
#
is_passthrough_command() {
    case "$1" in
        --version|--help|--list|--info|--upgrade|--uninstall|--cron|--showcsr|--showdomain)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#
# Process a single domain entry from the domains file
#
process_domain_entry() {
    local domain_entry="$1"

    log_info "Processing domain entry: $domain_entry"

    # Validate domain entry format
    if [ -z "$domain_entry" ]; then
        log_error "Empty domain entry, skipping"
        return 1
    fi

    # Split domain entry by pipe and categorize domains
    local wildcard_domains=""
    local base_domains=""
    local base_domain=""
    local old_ifs="$IFS"
    local IFS='|'

    for domain in $domain_entry; do
        # Trim whitespace
        domain=$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ -n "$domain" ]; then
            # Separate wildcard domains from base domains
            case "$domain" in
                \**)
                    wildcard_domains="$wildcard_domains $domain"
                    ;;
                *)
                    base_domains="$base_domains $domain"
                    base_domain="$domain"  # Last non-wildcard becomes cert directory name
                    ;;
            esac
        fi
    done

    # Restore IFS
    IFS="$old_ifs"

    # Combine domains with base domains FIRST (so acme.sh uses non-wildcard for directory)
    local domains="$base_domains $wildcard_domains"

    if [ -z "$base_domain" ]; then
        log_error "No non-wildcard domain found in entry: $domain_entry"
        log_error "At least one non-wildcard domain is required for certificate directory naming"
        return 1
    fi

    if [ -z "$base_domain" ]; then
        log_error "No valid domains in entry: $domain_entry"
        return 1
    fi

    log_debug "Base domain: $base_domain"
    log_debug "All domains: $domains"

    # Build certificate file paths
    local cert_dir="${ASUS_CERT_HOME}/${base_domain}${KEY_SUFFIX}"
    local fullchain_file="${cert_dir}/fullchain.pem"
    local key_file="${cert_dir}/domain.key"

    # Build acme.sh command with all domains
    local acme_cmd="$REAL_ACME_SH"

    # Add home and cert-home
    acme_cmd="$acme_cmd --home /opt/home/acme.sh"
    acme_cmd="$acme_cmd --cert-home $ASUS_CERT_HOME"

    # Add account settings if provided
    if [ -n "$ASUS_ACCOUNT_KEY" ]; then
        acme_cmd="$acme_cmd --accountkey $ASUS_ACCOUNT_KEY"
    fi

    if [ -n "$ASUS_ACCOUNT_CONF" ]; then
        acme_cmd="$acme_cmd --accountconf $ASUS_ACCOUNT_CONF"
    fi

    # Add ALL domains as separate -d flags (THIS IS THE KEY FIX)
    for domain in $domains; do
        acme_cmd="$acme_cmd --domain $domain"
    done

    # Add useragent if provided
    if [ -n "$ASUS_USERAGENT" ]; then
        acme_cmd="$acme_cmd --useragent $ASUS_USERAGENT"
    fi

    # Add output files
    acme_cmd="$acme_cmd --fullchain-file $fullchain_file"
    acme_cmd="$acme_cmd --key-file $key_file"

    # Add dnssleep (use provided value or default to 120 for reliable DNS propagation)
    local dns_sleep="${ASUS_DNSSLEEP:-120}"
    acme_cmd="$acme_cmd --dnssleep $dns_sleep"

    # Add command (--issue, --renew, etc.)
    if [ -n "$ASUS_COMMAND" ]; then
        acme_cmd="$acme_cmd $ASUS_COMMAND"
    fi

    # Add DNS API
    acme_cmd="$acme_cmd --dns $DNS_API"

    # Explicitly use Let's Encrypt (avoids ZeroSSL which requires EAB)
    acme_cmd="$acme_cmd --server letsencrypt"

    # Add extra arguments (but filter out duplicates and irrelevant ones)
    if [ -n "$ASUS_EXTRA_ARGS" ]; then
        for arg in $ASUS_EXTRA_ARGS; do
            # Skip if it's already handled or irrelevant
            case "$arg" in
                --standalone|--httpport|--dns|dns_*|--domain)
                    continue
                    ;;
                *)
                    acme_cmd="$acme_cmd $arg"
                    ;;
            esac
        done
    fi

    # Execute acme.sh
    log_info "Executing: $acme_cmd"

    # Run the command and capture output
    local output_file="/tmp/acme-wrapper-output-$$.log"
    if eval "$acme_cmd" > "$output_file" 2>&1; then
        log_info "Certificate operation successful for: $base_domain"

        # Log last few lines of output in debug mode
        if [ "${ASUS_WRAPPER_DEBUG}" = "1" ] && [ -f "$output_file" ]; then
            log_debug "Last 10 lines of acme.sh output:"
            tail -10 "$output_file" | while IFS= read -r line; do
                log_debug "  $line"
            done
        fi

        rm -f "$output_file"
        return 0
    else
        local exit_code=$?
        log_error "Certificate operation failed for: $base_domain (exit code: $exit_code)"

        # Log the error output
        if [ -f "$output_file" ]; then
            log_error "acme.sh error output (last 20 lines):"
            tail -20 "$output_file" | while IFS= read -r line; do
                log_error "  $line"
            done
            rm -f "$output_file"
        fi

        return $exit_code
    fi
}

#
# Main function
#
main() {
    log_info "Starting asus-wrapper-acme.sh v${SCRIPT_VERSION}"
    log_debug "Arguments: $*"

    # Check for pass-through commands (--version, --help, etc.)
    if is_passthrough_command "$1"; then
        log_info "Pass-through command detected: $1"
        exec "$REAL_ACME_SH" "$@"
    fi

    # Validate prerequisites
    validate_prerequisites "$@"

    # Parse Asus firmware arguments
    parse_asus_args "$@"

    # If no command specified, pass through
    if [ -z "$ASUS_COMMAND" ]; then
        log_info "No certificate command detected, passing through to real acme.sh"
        exec "$REAL_ACME_SH" "$@"
    fi

    # Process each domain entry from the domains file
    local success_count=0
    local fail_count=0
    local total_count=0

    while IFS= read -r domain_entry; do
        # Skip empty lines and comments
        case "$domain_entry" in
            ''|'#'*)
                continue
                ;;
        esac

        total_count=$((total_count + 1))

        if process_domain_entry "$domain_entry"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done < "$DOMAINS_FILE"

    # Report results
    log_info "Completed: $success_count successful, $fail_count failed out of $total_count total"

    if [ $fail_count -gt 0 ]; then
        log_error "Some certificate operations failed"
        exit 1
    fi

    log_info "All certificate operations completed successfully"
    exit 0
}

# Execute main function
main "$@"
