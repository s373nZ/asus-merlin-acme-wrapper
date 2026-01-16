#!/bin/sh

################################################################################
# switch-to-letsencrypt.sh
#
# Configure acme.sh to use Let's Encrypt instead of ZeroSSL
# Then test certificate issuance
#
# Part of asus-merlin-acme-wrapper
# https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper
################################################################################

echo "=== Switch to Let's Encrypt and Test ==="
echo "Date: $(date)"
echo ""

# Step 1: Set Let's Encrypt as default CA
echo "Step 1: Configuring Let's Encrypt as default Certificate Authority..."
/opt/home/acme.sh/acme.sh --set-default-ca --server letsencrypt

if [ $? -eq 0 ]; then
    echo "  [OK] Let's Encrypt is now the default CA"
else
    echo "  [FAIL] Failed to set default CA"
    exit 1
fi
echo ""

# Step 2: Verify the change
echo "Step 2: Verifying configuration..."
if grep -q "letsencrypt" /opt/home/acme.sh/account.conf 2>/dev/null; then
    echo "  [OK] Configuration updated"
else
    echo "  [WARN] Could not verify configuration change"
fi
echo ""

# Helper function to get base domain
get_base_domain() {
    domain_entry=$(grep -v "^$" /jffs/.le/domains | grep -v "^#" | head -1)
    echo "$domain_entry" | tr '|' '\n' | grep -v '^\*' | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

BASE_DOMAIN=$(get_base_domain)

# Step 3: Clean up old attempts
echo "Step 3: Cleaning up previous certificate attempts..."
if [ -d "/jffs/.le/${BASE_DOMAIN}_ecc" ]; then
    echo "  Removing old certificate directory..."
    rm -rf "/jffs/.le/${BASE_DOMAIN}_ecc"
    echo "  [OK] Cleaned up"
else
    echo "  [OK] No cleanup needed"
fi
echo ""

# Step 4: Clear logs
echo "Step 4: Clearing old logs..."
if [ -f "/jffs/.le/acme.sh.log" ]; then
    cp /jffs/.le/acme.sh.log /jffs/.le/acme.sh.log.zerossl-backup
    echo "=== Test run with Let's Encrypt at $(date) ===" > /jffs/.le/acme.sh.log
    echo "  [OK] Log cleared (backup saved)"
else
    echo "  [OK] No existing log"
fi
echo ""

# Step 5: Run production certificate test
echo "Step 5: Testing certificate issuance with Let's Encrypt..."
echo "  This will take 3-5 minutes (includes 120 second DNS propagation wait)"
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

echo "Domains to request:"
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
cmd="$cmd --server letsencrypt"  # Explicitly specify Let's Encrypt
cmd="$cmd --debug 2"

echo "Certificate Authority: Let's Encrypt (production)"
echo "DNS API: $dns_api"
echo ""
echo "==================================================================="
echo ""
echo "Starting certificate issuance..."
echo ""

# Execute
eval "$cmd" 2>&1 | tee /tmp/letsencrypt-production-test.log
exit_code=$?

echo ""
echo "==================================================================="
echo ""
echo "Step 6: Analyzing results..."
echo ""

if [ $exit_code -eq 0 ]; then
    echo "[SUCCESS] Production certificate issued!"
    echo ""

    if [ -f "$fullchain_file" ]; then
        echo "Certificate created: $fullchain_file"
        echo ""
        echo "Certificate SANs:"
        openssl x509 -in "$fullchain_file" -text -noout | grep -A 2 "Subject Alternative Name"
        echo ""
        echo "Certificate dates:"
        openssl x509 -in "$fullchain_file" -noout -dates
        echo ""
        echo "Issuer:"
        openssl x509 -in "$fullchain_file" -noout -issuer
        echo ""
        echo "Certificate directory contents:"
        ls -lh "$cert_dir/"
        echo ""
        echo "[OK] Ready for production use!"
        echo ""
        echo "Next steps:"
        echo "  1. The certificate is installed and ready"
        echo "  2. Verify HTTPS works on your domain"
        echo "  3. Test wildcard subdomains if configured"
        echo "  4. Auto-renewal is configured via cron"
    else
        echo "[WARN] Certificate file not found"
    fi
else
    echo "[FAILED] Exit code: $exit_code"
    echo ""
    echo "Analyzing error..."
    echo ""

    # Check for common errors
    if grep -qi "timeout" /tmp/letsencrypt-production-test.log; then
        echo "[ERROR] DNS TIMEOUT"
        echo "   The CA timed out waiting for DNS propagation."
        echo "   Try running again - sometimes it works on second try."
    elif grep -qi "rate limit" /tmp/letsencrypt-production-test.log; then
        echo "[ERROR] RATE LIMIT"
        echo "   Too many requests. Wait 1 hour before trying again."
    elif grep -qi "CAA" /tmp/letsencrypt-production-test.log; then
        echo "[ERROR] CAA RECORD ISSUE"
        echo "   Check DNS CAA records for your domain"
    else
        echo "Last 30 lines of output:"
        tail -30 /tmp/letsencrypt-production-test.log
    fi
fi

echo ""
echo "==================================================================="
echo ""
echo "Log files:"
echo "  Test output: /tmp/letsencrypt-production-test.log"
echo "  acme.sh log: /jffs/.le/acme.sh.log"
echo "  ZeroSSL backup: /jffs/.le/acme.sh.log.zerossl-backup"
echo ""
echo "=== Complete ==="

exit $exit_code
