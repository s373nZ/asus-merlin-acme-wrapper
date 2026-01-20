#!/bin/sh
# shellcheck shell=busybox

################################################################################
# test-runner.sh
#
# Test suite for asus-merlin-acme-wrapper wrapper script
# Runs in Docker container with mocked environment
################################################################################

# Colors (disabled if not running in a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

PASS=0
FAIL=0

echo_pass() {
    printf '%b[PASS]%b %s\n' "$GREEN" "$NC" "$1"
    PASS=$((PASS + 1))
}

echo_fail() {
    printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$1"
    FAIL=$((FAIL + 1))
}

echo_info() {
    printf '%b[INFO]%b %s\n' "$YELLOW" "$NC" "$1"
}

echo ""
echo "=========================================="
echo "  asus-merlin-acme-wrapper Test Suite"
echo "=========================================="
echo ""

################################################################################
# Test 1: Script exists and is executable
################################################################################
echo_info "Test 1: Script exists and is executable"

if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    echo_pass "Wrapper script exists"
else
    echo_fail "Wrapper script not found"
fi

if [ -x /jffs/sbin/asus-wrapper-acme.sh ]; then
    echo_pass "Wrapper script is executable"
else
    echo_fail "Wrapper script is not executable"
fi

################################################################################
# Test 2: Version constant is set
################################################################################
echo_info "Test 2: Version constant is set"

if grep -q 'SCRIPT_VERSION="[0-9]' /jffs/sbin/asus-wrapper-acme.sh; then
    version=$(grep 'SCRIPT_VERSION=' /jffs/sbin/asus-wrapper-acme.sh | head -1 | cut -d'"' -f2)
    echo_pass "Version is set: $version"
else
    echo_fail "Version constant not found or invalid"
fi

################################################################################
# Test 3: Pass-through commands work
################################################################################
echo_info "Test 3: Pass-through commands"

# Test --version
output=$(/jffs/sbin/asus-wrapper-acme.sh --version 2>&1)
if echo "$output" | grep -q "v3\|acme"; then
    echo_pass "--version passes through correctly"
else
    echo_fail "--version did not pass through"
fi

# Test --help
if /jffs/sbin/asus-wrapper-acme.sh --help >/dev/null 2>&1; then
    echo_pass "--help passes through correctly"
else
    echo_fail "--help did not pass through"
fi

# Test --list
if /jffs/sbin/asus-wrapper-acme.sh --list >/dev/null 2>&1; then
    echo_pass "--list passes through correctly"
else
    echo_fail "--list did not pass through"
fi

################################################################################
# Test 4: Domains file parsing
################################################################################
echo_info "Test 4: Domains file validation"

if [ -f /jffs/.le/domains ]; then
    echo_pass "Domains file exists"
else
    echo_fail "Domains file not found"
fi

if [ -s /jffs/.le/domains ]; then
    echo_pass "Domains file is not empty"
else
    echo_fail "Domains file is empty"
fi

################################################################################
# Test 5: Certificate issuance simulation
################################################################################
echo_info "Test 5: Certificate issuance simulation"

# Clear previous test artifacts
rm -rf /jffs/.le/test.example.com_ecc
rm -f /tmp/acme-calls.log

# Simulate firmware calling the wrapper
export ASUS_WRAPPER_DEBUG=1
/jffs/sbin/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain test.example.com \
    --issue \
    --standalone \
    --httpport 80 \
    > /tmp/test-output.log 2>&1

# Check if mock acme.sh was called
if [ -f /tmp/acme-calls.log ]; then
    echo_pass "acme.sh was called"

    # Check that --standalone was removed
    if grep -q -- "--standalone" /tmp/acme-calls.log; then
        echo_fail "--standalone was not removed from call"
    else
        echo_pass "--standalone was correctly removed"
    fi

    # Check that --dns was added
    if grep -q -- "--dns" /tmp/acme-calls.log; then
        echo_pass "--dns flag was added"
    else
        echo_fail "--dns flag was not added"
    fi
else
    echo_fail "acme.sh was not called"
fi

# Check if certificate directory was created
if [ -d /jffs/.le/test.example.com_ecc ]; then
    echo_pass "Certificate directory was created"
else
    echo_fail "Certificate directory was not created"
fi

################################################################################
# Test 6: Multiple domain parsing
################################################################################
echo_info "Test 6: Multiple domain parsing"

# Update domains file for multi-domain test
echo "*.multi.example.com|multi.example.com|www.multi.example.com" > /jffs/.le/domains

rm -rf /jffs/.le/multi.example.com_ecc
rm -f /tmp/acme-calls.log

/jffs/sbin/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain multi.example.com \
    --issue \
    > /tmp/test-output.log 2>&1

if [ -f /tmp/acme-calls.log ]; then
    # Count --domain flags in the call
    domain_count=$(grep -o -- "--domain" /tmp/acme-calls.log | wc -l)
    if [ "$domain_count" -ge 2 ]; then
        echo_pass "Multiple domains passed to acme.sh ($domain_count domains)"
    else
        echo_fail "Not enough domains passed to acme.sh (expected 3, got $domain_count)"
    fi
else
    echo_fail "acme.sh was not called for multi-domain test"
fi

################################################################################
# Test 7: Environment variable configuration
################################################################################
echo_info "Test 7: Environment variable configuration"

# Test DNS API override
export ASUS_WRAPPER_DNS_API=dns_cf
rm -f /tmp/acme-calls.log

echo "test-env.example.com" > /jffs/.le/domains

/jffs/sbin/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain test-env.example.com \
    --issue \
    > /tmp/test-output.log 2>&1

if [ -f /tmp/acme-calls.log ]; then
    if grep -q "dns_cf" /tmp/acme-calls.log; then
        echo_pass "DNS API override works (dns_cf)"
    else
        echo_fail "DNS API override not applied"
    fi
else
    echo_fail "acme.sh was not called"
fi

unset ASUS_WRAPPER_DNS_API

################################################################################
# Test 8: Error handling - missing domains file
################################################################################
echo_info "Test 8: Error handling"

# Temporarily remove domains file
mv /jffs/.le/domains /jffs/.le/domains.bak

output=$(/jffs/sbin/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain test.example.com \
    --issue 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo_pass "Returns error when domains file missing"
else
    echo_fail "Should have returned error for missing domains file"
fi

# Restore domains file
mv /jffs/.le/domains.bak /jffs/.le/domains

################################################################################
# Test 9: Addon structure
################################################################################
echo_info "Test 9: Addon structure"

if [ -d /jffs/addons/acme-wrapper ]; then
    echo_pass "Addon directory exists"
else
    echo_fail "Addon directory not found"
fi

if [ -f /jffs/addons/acme-wrapper/acme-wrapper.sh ]; then
    echo_pass "Main addon script exists"
else
    echo_fail "Main addon script not found"
fi

if [ -x /jffs/addons/acme-wrapper/acme-wrapper.sh ]; then
    echo_pass "Main addon script is executable"
else
    echo_fail "Main addon script is not executable"
fi

if [ -f /jffs/addons/acme-wrapper/asus-wrapper-acme.sh ]; then
    echo_pass "Wrapper script exists in addon directory"
else
    echo_fail "Wrapper script not found in addon directory"
fi

################################################################################
# Test 10: Addon config file support
################################################################################
echo_info "Test 10: Addon config file support"

# Create addon config file
cat > /jffs/addons/acme-wrapper/acme-wrapper.conf << 'CONFEOF'
ACME_WRAPPER_VERSION="2.0.0"
ACME_WRAPPER_DNS_API="dns_gd"
ACME_WRAPPER_DEBUG="1"
ACME_WRAPPER_DNSSLEEP="180"
ACME_WRAPPER_DOMAINS_FILE="/jffs/.le/domains"
ACME_WRAPPER_ACCOUNT_CONF="/jffs/.le/account.conf"
CONFEOF

rm -f /tmp/acme-calls.log
unset ASUS_WRAPPER_DNS_API

echo "config-test.example.com" > /jffs/.le/domains

/jffs/addons/acme-wrapper/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain config-test.example.com \
    --issue \
    > /tmp/test-output.log 2>&1

if [ -f /tmp/acme-calls.log ]; then
    if grep -q "dns_gd" /tmp/acme-calls.log; then
        echo_pass "Config file DNS API (dns_gd) was used"
    else
        echo_fail "Config file DNS API was not used"
        cat /tmp/acme-calls.log
    fi

    if grep -q -- "--dnssleep 180" /tmp/acme-calls.log; then
        echo_pass "Config file dnssleep (180) was used"
    else
        echo_fail "Config file dnssleep was not used"
    fi
else
    echo_fail "acme.sh was not called for config test"
fi

# Clean up config for next test
rm -f /jffs/addons/acme-wrapper/acme-wrapper.conf

################################################################################
# Test 11: Environment variables override config file
################################################################################
echo_info "Test 11: Environment variables override config"

# Create config with one value
cat > /jffs/addons/acme-wrapper/acme-wrapper.conf << 'CONFEOF'
ACME_WRAPPER_DNS_API="dns_gd"
CONFEOF

# Set env var with different value
export ASUS_WRAPPER_DNS_API=dns_vultr
rm -f /tmp/acme-calls.log

echo "override-test.example.com" > /jffs/.le/domains

/jffs/addons/acme-wrapper/asus-wrapper-acme.sh \
    --home /opt/home/acme.sh \
    --cert-home /jffs/.le \
    --domain override-test.example.com \
    --issue \
    > /tmp/test-output.log 2>&1

if [ -f /tmp/acme-calls.log ]; then
    if grep -q "dns_vultr" /tmp/acme-calls.log; then
        echo_pass "Environment variable overrides config file"
    else
        echo_fail "Environment variable did not override config file"
        cat /tmp/acme-calls.log
    fi
else
    echo_fail "acme.sh was not called for override test"
fi

unset ASUS_WRAPPER_DNS_API
rm -f /jffs/addons/acme-wrapper/acme-wrapper.conf

################################################################################
# Test 12: Web UI files exist
################################################################################
echo_info "Test 12: Web UI files"

if [ -f /jffs/addons/acme-wrapper/acme-wrapper.asp ]; then
    echo_pass "Web UI ASP file exists"
else
    echo_fail "Web UI ASP file not found"
fi

if [ -f /jffs/addons/acme-wrapper/acme-wrapper.js ]; then
    echo_pass "Web UI JavaScript file exists"
else
    echo_fail "Web UI JavaScript file not found"
fi

# Check ASP file contains expected content
if grep -q "ACME Wrapper" /jffs/addons/acme-wrapper/acme-wrapper.asp 2>/dev/null; then
    echo_pass "Web UI ASP file contains expected content"
else
    echo_fail "Web UI ASP file missing expected content"
fi

################################################################################
# Summary
################################################################################
echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    printf '%bAll tests passed!%b\n' "$GREEN" "$NC"
    exit 0
else
    printf '%bSome tests failed.%b\n' "$RED" "$NC"
    exit 1
fi
