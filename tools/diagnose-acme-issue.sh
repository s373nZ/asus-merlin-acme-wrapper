#!/bin/sh

################################################################################
# diagnose-acme-issue.sh
#
# Diagnostic script to help troubleshoot certificate issuance failures
#
# Part of asus-merlin-acme-wrapper
# https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper
################################################################################

echo "=== ACME Wrapper Diagnostic Tool ==="
echo "Date: $(date)"
echo ""

# Check if wrapper is mounted
echo "1. Checking bind mount..."
if mount | grep -q "/usr/sbin/acme.sh"; then
    echo "   [OK] Wrapper is mounted"
    mount | grep "/usr/sbin/acme.sh"
else
    echo "   [FAIL] Wrapper NOT mounted"
fi
echo ""

# Check wrapper version
echo "2. Checking wrapper version..."
grep "SCRIPT_VERSION" /jffs/sbin/asus-wrapper-acme.sh | head -1
echo ""

# Check domains file
echo "3. Domains file content:"
cat /jffs/.le/domains
echo ""

# Check if real acme.sh exists
echo "4. Checking real acme.sh..."
if [ -x "/opt/home/acme.sh/acme.sh" ]; then
    echo "   [OK] Real acme.sh exists and is executable"
    /opt/home/acme.sh/acme.sh --version | head -1
else
    echo "   [FAIL] Real acme.sh NOT found or not executable"
fi
echo ""

# Check DNS API credentials
echo "5. Checking DNS API credentials..."
if [ -f "/jffs/.le/account.conf" ]; then
    echo "   Account.conf exists:"
    grep -i "aws\|dns\|cf_" /jffs/.le/account.conf | grep -v "^#" | head -5
else
    echo "   [FAIL] account.conf NOT found"
fi
echo ""

# Check certificate directory
echo "6. Certificate directory status:"
cert_dirs=$(find /jffs/.le -maxdepth 1 -type d -name "*_ecc" 2>/dev/null)
if [ -n "$cert_dirs" ]; then
    for dir in $cert_dirs; do
        echo "   Certificate directory exists: $dir"
        ls -lh "$dir/" 2>/dev/null
    done
else
    echo "   Certificate directory does not exist yet (normal for first run)"
fi
echo ""

# Test DNS API manually
echo "7. Testing DNS API with a simple acme.sh command..."
echo "   (This will use staging environment to avoid rate limits)"
echo ""

# Extract domains from file
domain_entry=$(grep -v "^$" /jffs/.le/domains | grep -v "^#" | head -1)
if [ -n "$domain_entry" ]; then
    # Get first domain
    first_domain=$(echo "$domain_entry" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Determine DNS API from wrapper config
    dns_api=$(grep "^readonly DNS_API=" /jffs/sbin/asus-wrapper-acme.sh | cut -d'"' -f2)
    dns_api="${dns_api:-dns_aws}"

    echo "   Testing with domain: $first_domain"
    echo "   DNS API: $dns_api"
    echo "   Command: /opt/home/acme.sh/acme.sh --issue -d test.$first_domain --dns $dns_api --staging --debug 2"
    echo ""
    echo "   Running test (this may take 30-60 seconds)..."
    echo "   ---"

    /opt/home/acme.sh/acme.sh \
        --issue \
        -d "test.${first_domain}" \
        --dns "$dns_api" \
        --staging \
        --debug 2 \
        2>&1 | tail -50

    test_exit=$?
    echo "   ---"
    echo "   Test exit code: $test_exit"

    if [ $test_exit -eq 0 ]; then
        echo "   [OK] DNS API test PASSED"
    else
        echo "   [FAIL] DNS API test FAILED"
        echo "   This indicates the problem is with DNS API credentials or configuration"
    fi
else
    echo "   [FAIL] No domains found in /jffs/.le/domains"
fi

echo ""
echo "8. Recent syslog entries:"
grep acme /tmp/syslog.log | tail -20
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Next steps:"
echo "1. Review the DNS API test output above"
echo "2. If DNS API test failed, check your DNS provider credentials"
echo "3. If DNS API test passed, there may be an issue with the wrapper command construction"
echo "4. Enable debug mode: export ASUS_WRAPPER_DEBUG=1 && service restart_letsencrypt"
