#!/bin/sh

################################################################################
# test-wrapper-manually.sh
#
# Manually test what the wrapper would do, with full output visible
# Bypasses the wrapper to test acme.sh directly with your configuration
#
# Part of asus-merlin-acme-wrapper
# https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper
################################################################################

echo "=== Manual Wrapper Test ==="
echo ""

# Configuration
DOMAINS_FILE="/jffs/.le/domains"
KEY_SUFFIX="_ecc"

# Determine DNS API from wrapper or default
DNS_API=$(grep "^readonly DNS_API=" /jffs/sbin/asus-wrapper-acme.sh 2>/dev/null | cut -d'"' -f2)
DNS_API="${DNS_API:-dns_aws}"

# Read first domain entry
domain_entry=$(grep -v "^$" "$DOMAINS_FILE" | grep -v "^#" | head -1)

if [ -z "$domain_entry" ]; then
    echo "ERROR: No domains found in $DOMAINS_FILE"
    exit 1
fi

echo "Domain entry from file: $domain_entry"
echo "DNS API: $DNS_API"
echo ""

# Parse domains - separate wildcard from base domains
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

# Combine with base domains FIRST
domains="$base_domains $wildcard_domains"

if [ -z "$base_domain" ]; then
    echo "ERROR: No non-wildcard domain found. At least one non-wildcard domain is required."
    exit 1
fi

echo "Parsed domains: $domains"
echo "Base domain: $base_domain"
echo ""

# Build certificate paths
cert_dir="/jffs/.le/${base_domain}${KEY_SUFFIX}"
fullchain_file="${cert_dir}/fullchain.pem"
key_file="${cert_dir}/domain.key"

echo "Certificate directory: $cert_dir"
echo "Fullchain file: $fullchain_file"
echo "Key file: $key_file"
echo ""

# Build acme.sh command
acme_cmd="/opt/home/acme.sh/acme.sh"
acme_cmd="$acme_cmd --home /opt/home/acme.sh"
acme_cmd="$acme_cmd --cert-home /jffs/.le"

# Check for account files
if [ -f "/jffs/.le/account.key" ]; then
    acme_cmd="$acme_cmd --accountkey /jffs/.le/account.key"
else
    echo "WARNING: account.key not found"
fi

if [ -f "/jffs/.le/account.conf" ]; then
    acme_cmd="$acme_cmd --accountconf /jffs/.le/account.conf"
else
    echo "WARNING: account.conf not found"
fi

# Add all domains
for domain in $domains; do
    acme_cmd="$acme_cmd --domain $domain"
done

acme_cmd="$acme_cmd --useragent asusrouter/0.2"
acme_cmd="$acme_cmd --fullchain-file $fullchain_file"
acme_cmd="$acme_cmd --key-file $key_file"
acme_cmd="$acme_cmd --dnssleep 120"
acme_cmd="$acme_cmd --issue"
acme_cmd="$acme_cmd --dns $DNS_API"
acme_cmd="$acme_cmd --keylength ec-256"
acme_cmd="$acme_cmd --server letsencrypt"

# Add staging for testing (comment out for production)
# acme_cmd="$acme_cmd --staging"

# Add debug
acme_cmd="$acme_cmd --debug 2"

echo "=== Command to Execute ==="
echo "$acme_cmd"
echo ""
echo "=== Executing (this may take 2-5 minutes) ==="
echo ""

# Execute
eval "$acme_cmd"
exit_code=$?

echo ""
echo "=== Execution Complete ==="
echo "Exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
    echo "[SUCCESS]"
    echo ""
    echo "Verifying certificate SANs:"
    if [ -f "$fullchain_file" ]; then
        openssl x509 -in "$fullchain_file" -text -noout | grep -A 2 "Subject Alternative Name"
    fi
else
    echo "[FAILED]"
    echo ""
    echo "Check the output above for errors"
    echo "Common issues:"
    echo "  - DNS API credentials not configured"
    echo "  - DNS propagation timeout"
    echo "  - Rate limiting (use --staging for testing)"
    echo "  - Firewall blocking DNS queries"
fi

exit $exit_code
