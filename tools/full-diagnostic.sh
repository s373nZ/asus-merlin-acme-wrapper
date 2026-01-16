#!/bin/sh

################################################################################
# full-diagnostic.sh
#
# Comprehensive diagnostic to identify certificate issuance issues
# Uses Let's Encrypt STAGING environment to avoid rate limits
#
# Part of asus-merlin-acme-wrapper
# https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper
################################################################################

echo "=== Full Certificate Diagnostic ==="
echo "Date: $(date)"
echo ""

# Get base domain from domains file for messages
get_base_domain() {
    domain_entry=$(grep -v "^$" /jffs/.le/domains | grep -v "^#" | head -1)
    echo "$domain_entry" | tr '|' '\n' | grep -v '^\*' | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

BASE_DOMAIN=$(get_base_domain)

# Clean up old attempts
echo "Step 1: Cleaning up any previous failed attempts..."
if [ -d "/jffs/.le/${BASE_DOMAIN}_ecc" ]; then
    echo "  Removing old certificate directory..."
    rm -rf "/jffs/.le/${BASE_DOMAIN}_ecc"
    echo "  [OK] Cleaned up"
else
    echo "  [OK] No cleanup needed"
fi
echo ""

# Check wrapper configuration
echo "Step 2: Checking wrapper configuration..."
wrapper_version=$(grep "SCRIPT_VERSION=" /jffs/sbin/asus-wrapper-acme.sh | head -1 | cut -d'"' -f2)
echo "  Wrapper version: $wrapper_version"

if mount | grep -q "/usr/sbin/acme.sh"; then
    echo "  [OK] Wrapper is bind-mounted"
else
    echo "  [FAIL] Wrapper is NOT bind-mounted"
    echo "    Run: mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh"
fi
echo ""

# Check domains file
echo "Step 3: Checking domains file..."
if [ -f "/jffs/.le/domains" ]; then
    echo "  [OK] Domains file exists"
    echo "  Content: $(cat /jffs/.le/domains)"
else
    echo "  [FAIL] Domains file NOT found"
    exit 1
fi
echo ""

# Check account configuration
echo "Step 4: Checking acme.sh account..."
if [ -f "/jffs/.le/account.conf" ]; then
    echo "  [OK] Account configuration exists"
    if grep -qi "aws\|cf_" /jffs/.le/account.conf; then
        echo "  [OK] DNS API credentials found"
    else
        echo "  [WARN] DNS API credentials NOT found in account.conf"
        echo "    They may be in environment variables"
    fi
else
    echo "  [FAIL] Account configuration NOT found"
fi
echo ""

# Clear old logs
echo "Step 5: Clearing old acme.sh logs..."
if [ -f "/jffs/.le/acme.sh.log" ]; then
    # Keep a backup
    cp /jffs/.le/acme.sh.log /jffs/.le/acme.sh.log.backup
    # Clear the log
    echo "=== Test run at $(date) ===" > /jffs/.le/acme.sh.log
    echo "  [OK] Log cleared (backup saved to acme.sh.log.backup)"
else
    echo "  [OK] No existing log"
fi
echo ""

# Run the actual test
echo "Step 6: Running certificate issuance test..."
echo "  This will use Let's Encrypt STAGING environment (rate limit friendly)"
echo "  Command will be visible below..."
echo ""
echo "==================================================================="

# Parse domains
domain_entry=$(grep -v "^$" /jffs/.le/domains | grep -v "^#" | head -1)

# Separate wildcard and base domains
wildcard_domains=""
base_domains=""
base_domain=""
old_ifs="$IFS"
IFS='|'
for domain in $domain_entry; do
    domain=$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$domain" ]; then
        case "$domain" in
            \**)
                wildcard_domains="$wildcard_domains $domain"
                ;;
            *)
                base_domains="$base_domains $domain"
                base_domain="$domain"
                ;;
        esac
    fi
done
IFS="$old_ifs"

# Combine with base domains first
domains="$base_domains $wildcard_domains"

echo "Domains to request (in order):"
for d in $domains; do
    echo "  - $d"
done
echo ""

# Determine DNS API
dns_api=$(grep "^readonly DNS_API=" /jffs/sbin/asus-wrapper-acme.sh 2>/dev/null | cut -d'"' -f2)
dns_api="${dns_api:-dns_aws}"

# Build command
cert_dir="/jffs/.le/${base_domain}_ecc"
fullchain_file="${cert_dir}/fullchain.pem"
key_file="${cert_dir}/domain.key"

cmd="/opt/home/acme.sh/acme.sh"
cmd="$cmd --home /opt/home/acme.sh"
cmd="$cmd --cert-home /jffs/.le"
cmd="$cmd --accountkey /jffs/.le/account.key"
cmd="$cmd --accountconf /jffs/.le/account.conf"

for domain in $domains; do
    cmd="$cmd --domain $domain"
done

cmd="$cmd --useragent asusrouter/0.2"
cmd="$cmd --fullchain-file $fullchain_file"
cmd="$cmd --key-file $key_file"
cmd="$cmd --dnssleep 120"  # 2 minutes for DNS propagation
cmd="$cmd --issue"
cmd="$cmd --dns $dns_api"
cmd="$cmd --keylength ec-256"
cmd="$cmd --staging"  # Use staging for testing
cmd="$cmd --debug 2"  # Full debug output

echo "DNS API: $dns_api"
echo ""
echo "Full command:"
echo "$cmd"
echo ""
echo "==================================================================="
echo ""
echo "Starting certificate issuance (this will take 2-5 minutes)..."
echo ""

# Execute and capture output
eval "$cmd" 2>&1 | tee /tmp/acme-test-output.log
exit_code=$?

echo ""
echo "==================================================================="
echo ""
echo "Step 7: Analyzing results..."
echo ""

if [ $exit_code -eq 0 ]; then
    echo "[SUCCESS] Certificate was issued!"
    echo ""

    # Verify the certificate
    if [ -f "$fullchain_file" ]; then
        echo "Certificate file created: $fullchain_file"
        echo ""
        echo "Certificate SANs:"
        openssl x509 -in "$fullchain_file" -text -noout | grep -A 2 "Subject Alternative Name"
        echo ""
        echo "Certificate dates:"
        openssl x509 -in "$fullchain_file" -noout -dates
        echo ""
        echo "Certificate directory contents:"
        ls -lh "$cert_dir/"
    else
        echo "[WARN] Certificate file not found at expected location"
    fi
else
    echo "[FAILED] Exit code: $exit_code"
    echo ""
    echo "Checking for specific errors in output..."
    echo ""

    # Check for common errors
    if grep -qi "timeout" /tmp/acme-test-output.log; then
        echo "[ERROR] TIMEOUT ERROR DETECTED"
        echo "The CA timed out waiting for DNS propagation."
        echo ""
        echo "Possible causes:"
        echo "  1. DNS propagation is too slow"
        echo "  2. DNS zone configuration issue"
        echo "  3. Firewall blocking CA's DNS queries"
        echo ""
        echo "Try increasing --dnssleep even more (currently 120 seconds)"
    fi

    if grep -qi "rate limit" /tmp/acme-test-output.log; then
        echo "[ERROR] RATE LIMIT ERROR"
        echo "Too many requests to Let's Encrypt."
        echo "Wait 1 hour before trying again."
    fi

    if grep -qi "unauthorized" /tmp/acme-test-output.log; then
        echo "[ERROR] AUTHORIZATION ERROR"
        echo "DNS API credentials may be incorrect or lack permissions."
    fi

    if grep -qi "dns.*error" /tmp/acme-test-output.log; then
        echo "[ERROR] DNS API ERROR"
        echo "Problem communicating with DNS provider."
    fi

    echo ""
    echo "Last 30 lines of output:"
    tail -30 /tmp/acme-test-output.log
fi

echo ""
echo "==================================================================="
echo ""
echo "Step 8: Log files locations..."
echo "  Full test output: /tmp/acme-test-output.log"
echo "  acme.sh debug log: /jffs/.le/acme.sh.log"
echo "  Previous log backup: /jffs/.le/acme.sh.log.backup"
echo ""

if [ $exit_code -eq 0 ]; then
    echo "[OK] NEXT STEPS:"
    echo "  1. This was a STAGING test (fake certificate)"
    echo "  2. Remove staging cert: rm -rf $cert_dir"
    echo "  3. Run production test: service restart_letsencrypt"
    echo "  4. Or modify this script to remove --staging line"
else
    echo "[TROUBLESHOOTING]:"
    echo "  1. Review: /tmp/acme-test-output.log"
    echo "  2. Review: /jffs/.le/acme.sh.log"
    echo "  3. Check DNS: dig _acme-challenge.$base_domain TXT"
    echo "  4. Check DNS provider permissions"
fi

echo ""
echo "=== Diagnostic Complete ==="
exit $exit_code
