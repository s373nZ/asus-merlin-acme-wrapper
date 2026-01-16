#!/bin/sh
# shellcheck shell=busybox

################################################################################
# validate-acme-wrapper.sh
#
# Validation script for asus-wrapper-acme.sh installation
# Tests prerequisites, configuration, and certificate setup
#
# Part of asus-merlin-acme-wrapper
# https://github.com/s373nZ/asus-merlin-acme-wrapper
#
# Usage: ./validate-acme-wrapper.sh
################################################################################

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Test counters
PASS=0
FAIL=0
WARN=0

print_header() {
    echo ""
    echo "================================"
    echo "$1"
    echo "================================"
}

print_pass() {
    echo "${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

print_fail() {
    echo "${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

print_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN + 1))
}

print_info() {
    echo "  INFO: $1"
}

# Start validation
echo "Starting validation of asus-wrapper-acme.sh installation..."
echo "Date: $(date)"
echo ""

################################################################################
# Test 1: File System Checks
################################################################################
print_header "Test 1: File System Checks"

# Check wrapper script exists
if [ -f "/jffs/sbin/asus-wrapper-acme.sh" ]; then
    print_pass "Wrapper script exists at /jffs/sbin/asus-wrapper-acme.sh"
else
    print_fail "Wrapper script NOT found at /jffs/sbin/asus-wrapper-acme.sh"
fi

# Check wrapper script is executable
if [ -x "/jffs/sbin/asus-wrapper-acme.sh" ]; then
    print_pass "Wrapper script is executable"
else
    print_fail "Wrapper script is NOT executable"
    print_info "Run: chmod +x /jffs/sbin/asus-wrapper-acme.sh"
fi

# Check real acme.sh symlink
if [ -L "/jffs/sbin/acme.sh" ]; then
    target=$(readlink /jffs/sbin/acme.sh)
    print_pass "acme.sh symlink exists, points to: $target"
else
    print_warn "acme.sh symlink NOT found at /jffs/sbin/acme.sh"
fi

# Check real acme.sh exists
if [ -f "/opt/home/acme.sh/acme.sh" ]; then
    print_pass "Real acme.sh exists at /opt/home/acme.sh/acme.sh"
else
    print_fail "Real acme.sh NOT found at /opt/home/acme.sh/acme.sh"
fi

# Check real acme.sh is executable
if [ -x "/opt/home/acme.sh/acme.sh" ]; then
    print_pass "Real acme.sh is executable"
else
    print_fail "Real acme.sh is NOT executable"
fi

# Check domains file exists
if [ -f "/jffs/.le/domains" ]; then
    print_pass "Domains file exists at /jffs/.le/domains"
else
    print_fail "Domains file NOT found at /jffs/.le/domains"
fi

# Check domains file is readable
if [ -r "/jffs/.le/domains" ]; then
    print_pass "Domains file is readable"
else
    print_fail "Domains file is NOT readable"
fi

################################################################################
# Test 2: Bind Mount Checks
################################################################################
print_header "Test 2: Bind Mount Checks"

# Check if wrapper is bind-mounted
if mount | grep -q "/usr/sbin/acme.sh"; then
    print_pass "Wrapper is bind-mounted at /usr/sbin/acme.sh"
    mount_source=$(mount | grep "/usr/sbin/acme.sh" | awk '{print $1}')
    print_info "Mount source: $mount_source"
else
    print_fail "Wrapper is NOT bind-mounted at /usr/sbin/acme.sh"
    print_info "Run: mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh"
fi

# Check post-mount script
if [ -f "/jffs/scripts/post-mount" ]; then
    print_pass "post-mount script exists"
    if grep -q "asus-wrapper-acme.sh" /jffs/scripts/post-mount; then
        print_pass "post-mount script contains wrapper mount command"
    else
        print_warn "post-mount script does NOT contain wrapper mount command"
        print_info "Wrapper may not survive reboots"
    fi
else
    print_warn "post-mount script NOT found at /jffs/scripts/post-mount"
    print_info "Wrapper may not survive reboots"
fi

################################################################################
# Test 3: Version and Configuration
################################################################################
print_header "Test 3: Version and Configuration"

# Check wrapper version
if /usr/sbin/acme.sh --version 2>&1 | grep -q "v3\|v2"; then
    version=$(/usr/sbin/acme.sh --version 2>&1 | head -1)
    print_pass "acme.sh version check works: $version"
else
    print_warn "Could not determine acme.sh version"
fi

# Check wrapper script version in file
wrapper_ver=$(grep "SCRIPT_VERSION=" /jffs/sbin/asus-wrapper-acme.sh 2>/dev/null | head -1 | cut -d'"' -f2)
if [ -n "$wrapper_ver" ]; then
    print_pass "Wrapper script version: $wrapper_ver"
else
    print_warn "Could not determine wrapper script version"
fi

# Check DNS API configuration
dns_api=$(grep "DNS_API=" /jffs/sbin/asus-wrapper-acme.sh | grep -v "^#" | head -1 | cut -d'"' -f2)
print_info "Configured DNS API: ${dns_api:-not set}"

################################################################################
# Test 4: Domains File Content
################################################################################
print_header "Test 4: Domains File Content"

if [ -f "/jffs/.le/domains" ]; then
    line_count=$(grep -cvE '^$|^#' /jffs/.le/domains)
    print_info "Domains file has $line_count non-empty line(s)"

    while IFS= read -r line; do
        # Skip empty lines and comments
        case "$line" in
            ''|'#'*)
                continue
                ;;
        esac

        print_info "Domain entry: $line"

        # Check if line contains pipe delimiter
        if echo "$line" | grep -q "|"; then
            domain_count=$(echo "$line" | tr '|' '\n' | wc -l)
            print_pass "Entry contains $domain_count domain(s)"
        else
            print_warn "Entry does not contain pipe delimiter (single domain?)"
        fi

        # Extract base domain (last non-wildcard)
        base_domain=$(echo "$line" | tr '|' '\n' | grep -v '^\*' | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        print_info "Base domain (cert directory): $base_domain"

        # Check if certificate directory exists
        if [ -d "/jffs/.le/${base_domain}_ecc" ]; then
            print_pass "Certificate directory exists: /jffs/.le/${base_domain}_ecc"
        else
            print_warn "Certificate directory NOT found: /jffs/.le/${base_domain}_ecc"
            print_info "This is OK if certificate hasn't been issued yet"
        fi
    done < /jffs/.le/domains
fi

################################################################################
# Test 5: Certificate Validation
################################################################################
print_header "Test 5: Certificate Validation"

# Find all certificate directories
cert_dirs=$(find /jffs/.le -maxdepth 1 -type d -name "*_ecc" 2>/dev/null)

if [ -z "$cert_dirs" ]; then
    print_warn "No certificate directories found"
    print_info "Certificates may not have been issued yet"
else
    for cert_dir in $cert_dirs; do
        cert_name=$(basename "$cert_dir")
        print_info "Checking certificate: $cert_name"

        # Check if certificate file exists
        if [ -f "$cert_dir/fullchain.pem" ]; then
            print_pass "Certificate file exists: $cert_dir/fullchain.pem"

            # Check certificate validity
            if openssl x509 -in "$cert_dir/fullchain.pem" -noout -checkend 0 2>/dev/null; then
                print_pass "Certificate is valid (not expired)"

                # Get expiry date
                expiry=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                print_info "Expires: $expiry"
            else
                print_fail "Certificate is EXPIRED or INVALID"
            fi

            # Check SANs
            sans=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -1)
            if [ -n "$sans" ]; then
                print_pass "Certificate has SANs"
                print_info "SANs: $sans"

                # Count SANs
                san_count=$(echo "$sans" | tr ',' '\n' | wc -l)
                print_info "SAN count: $san_count"

                if [ "$san_count" -gt 1 ]; then
                    print_pass "Certificate has multiple SANs (correct!)"
                else
                    print_warn "Certificate has only 1 SAN (may be old format)"
                fi
            else
                print_warn "Could not extract SANs from certificate"
            fi
        else
            print_warn "Certificate file NOT found: $cert_dir/fullchain.pem"
        fi

        # Check key file exists
        if [ -f "$cert_dir/domain.key" ]; then
            print_pass "Private key exists: $cert_dir/domain.key"
        else
            print_warn "Private key NOT found: $cert_dir/domain.key"
        fi
    done
fi

################################################################################
# Test 6: Account Configuration
################################################################################
print_header "Test 6: Account Configuration"

if [ -f "/jffs/.le/account.conf" ]; then
    print_pass "Account configuration exists at /jffs/.le/account.conf"

    # Check for common DNS API credentials
    if grep -qi "aws\|cf_\|gd_" /jffs/.le/account.conf 2>/dev/null; then
        print_pass "DNS API credentials found in account.conf"
    else
        print_warn "No DNS API credentials found in account.conf"
        print_info "Credentials may be in environment variables"
    fi
else
    print_warn "Account configuration NOT found at /jffs/.le/account.conf"
    print_info "acme.sh may not be initialized yet"
fi

################################################################################
# Test 7: Symlinks Check
################################################################################
print_header "Test 7: Certificate Symlinks"

if [ -d "/jffs/.cert" ]; then
    print_pass "Certificate symlink directory exists at /jffs/.cert"

    if [ -L "/jffs/.cert/cert.pem" ]; then
        cert_target=$(readlink /jffs/.cert/cert.pem)
        print_pass "cert.pem symlink exists, points to: $cert_target"

        # Check if target exists
        if [ -f "$cert_target" ]; then
            print_pass "cert.pem target file exists"
        else
            print_fail "cert.pem target file NOT found"
        fi
    else
        print_warn "cert.pem symlink NOT found"
    fi

    if [ -L "/jffs/.cert/key.pem" ]; then
        key_target=$(readlink /jffs/.cert/key.pem)
        print_pass "key.pem symlink exists, points to: $key_target"

        # Check if target exists
        if [ -f "$key_target" ]; then
            print_pass "key.pem target file exists"
        else
            print_fail "key.pem target file NOT found"
        fi
    else
        print_warn "key.pem symlink NOT found"
    fi
else
    print_warn "Certificate symlink directory NOT found at /jffs/.cert"
fi

################################################################################
# Test 8: Log Check
################################################################################
print_header "Test 8: Recent Log Entries"

if [ -f "/tmp/syslog.log" ]; then
    print_pass "syslog.log exists"

    # Check for recent wrapper logs
    recent_logs=$(grep "acme" /tmp/syslog.log 2>/dev/null | tail -5)
    if [ -n "$recent_logs" ]; then
        print_pass "Found recent acme log entries"
        echo ""
        echo "Last 5 acme log entries:"
        echo "$recent_logs"
        echo ""
    else
        print_warn "No recent acme log entries found"
    fi

    # Check for errors
    error_logs=$(grep -i "error" /tmp/syslog.log 2>/dev/null | grep acme | tail -3)
    if [ -n "$error_logs" ]; then
        print_warn "Found error entries in logs"
        echo ""
        echo "Recent errors:"
        echo "$error_logs"
        echo ""
    fi
else
    print_warn "syslog.log NOT found at /tmp/syslog.log"
fi

################################################################################
# Summary
################################################################################
print_header "Validation Summary"

TOTAL=$((PASS + FAIL + WARN))

echo ""
echo "Results:"
echo "  ${GREEN}PASS${NC}: $PASS"
echo "  ${RED}FAIL${NC}: $FAIL"
echo "  ${YELLOW}WARN${NC}: $WARN"
echo "  TOTAL: $TOTAL"
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
    echo "${GREEN}All tests passed! Installation looks good.${NC}"
    exit 0
elif [ $FAIL -eq 0 ]; then
    echo "${YELLOW}All critical tests passed, but there are warnings.${NC}"
    echo "Review the warnings above."
    exit 0
else
    echo "${RED}Some tests failed. Please review and fix the issues above.${NC}"
    exit 1
fi
