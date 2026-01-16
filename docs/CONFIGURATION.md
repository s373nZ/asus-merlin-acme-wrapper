# Configuration Reference

This document covers all configuration options for asus-merlin-acme-wrapper.

## File Locations

| File | Purpose |
|------|---------|
| `/jffs/sbin/asus-wrapper-acme.sh` | Main wrapper script |
| `/jffs/.le/domains` | Domain configuration |
| `/jffs/.le/account.conf` | acme.sh account and API credentials |
| `/jffs/.le/account.key` | ACME account private key |
| `/jffs/.le/<domain>_ecc/` | Certificate storage directory |
| `/jffs/scripts/post-mount` | Startup script for bind mount |
| `/jffs/configs/profile.add` | Environment variables |

## Domains File

### Location
`/jffs/.le/domains`

### Format
```
domain1|domain2|domain3|...
```

- One certificate per line
- Domains separated by pipes (`|`)
- Supports wildcards (e.g., `*.domain.com`)
- The first non-wildcard domain becomes the certificate directory name
- Comments start with `#`
- Empty lines are ignored

### Examples

```bash
# Single wildcard certificate with base domain
*.yourdomain.com|yourdomain.com

# Multiple subdomains (no wildcard)
www.example.com|api.example.com|app.example.com

# Mixed wildcard and specific subdomains
*.yourdomain.com|yourdomain.com|www.yourdomain.com

# Multiple certificates (one per line)
*.domain1.com|domain1.com
*.domain2.com|domain2.com
```

### Important Notes

- At least one non-wildcard domain is required per line
- The certificate directory is named after the first non-wildcard domain
- Order matters: base domains should come before wildcards for proper directory naming

## Environment Variables

Set these in `/jffs/configs/profile.add` or export before running.

### ASUS_WRAPPER_DNS_API

DNS provider plugin to use for validation.

```bash
export ASUS_WRAPPER_DNS_API=dns_aws   # AWS Route53 (default)
export ASUS_WRAPPER_DNS_API=dns_cf    # Cloudflare
export ASUS_WRAPPER_DNS_API=dns_gd    # GoDaddy
export ASUS_WRAPPER_DNS_API=dns_dgon  # DigitalOcean
```

See [DNS_PROVIDERS.md](DNS_PROVIDERS.md) for full list.

### ASUS_WRAPPER_DEBUG

Enable debug logging for troubleshooting.

```bash
export ASUS_WRAPPER_DEBUG=1   # Enable debug output
export ASUS_WRAPPER_DEBUG=0   # Disable (default)
```

### ASUS_WRAPPER_ACME_DOMAINS

Custom location for domains file.

```bash
export ASUS_WRAPPER_ACME_DOMAINS=/jffs/custom/my-domains
```

Default: `/jffs/.le/domains`

## Account Configuration

### Location
`/jffs/.le/account.conf`

### DNS Provider Credentials

Add credentials for your DNS provider:

```bash
# AWS Route53
AWS_ACCESS_KEY_ID='AKIAXXXXXXXXXXXXXXXX'
AWS_SECRET_ACCESS_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

# Cloudflare
CF_Token='your-api-token'
CF_Zone_ID='your-zone-id'

# GoDaddy
GD_Key='your-key'
GD_Secret='your-secret'
```

### Security

Protect your credentials:

```bash
chmod 600 /jffs/.le/account.conf
```

## Wrapper Script Configuration

These values are set in the script itself (`/jffs/sbin/asus-wrapper-acme.sh`):

### SCRIPT_VERSION
Current version of the wrapper script.

### REAL_ACME_SH
Path to the real acme.sh binary.
Default: `/opt/home/acme.sh/acme.sh`

### DOMAINS_FILE
Default path to domains file (can be overridden by environment variable).
Default: `/jffs/.le/domains`

### DNS_API
Default DNS API plugin (can be overridden by environment variable).
Default: `dns_aws`

### KEY_SUFFIX
Suffix for certificate directories.
Default: `_ecc` (for ECC certificates)

### LOG_TAG
Syslog tag for log entries.
Default: `acme`

## Post-Mount Script

### Location
`/jffs/scripts/post-mount`

### Purpose
Ensures the wrapper is bind-mounted after USB drives are mounted (required for Entware).

### Example
```bash
#!/bin/sh

# Wait for Entware
sleep 5

# Mount the wrapper
if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi

# Mount custom DNS API scripts (if any)
if [ -d /jffs/sbin/dnsapi ]; then
    /bin/mount -o bind /jffs/sbin/dnsapi /usr/sbin/dnsapi
fi
```

## Certificate Storage

### Directory Structure
```
/jffs/.le/
├── domains                      # Domain configuration
├── account.conf                 # Account and API configuration
├── account.key                  # ACME account key
├── acme.sh.log                  # acme.sh log file
└── yourdomain.com_ecc/          # Certificate directory
    ├── yourdomain.com.cer       # Domain certificate
    ├── yourdomain.com.key       # Private key
    ├── ca.cer                   # CA certificate
    ├── fullchain.cer            # Full certificate chain
    ├── fullchain.pem            # Full chain (PEM format)
    └── domain.key               # Private key (alternate name)
```

### Router Certificate Symlinks
```
/jffs/.cert/
├── cert.pem -> /jffs/.le/yourdomain.com_ecc/fullchain.pem
└── key.pem  -> /jffs/.le/yourdomain.com_ecc/domain.key
```

## Logging

### Syslog
Logs are written to syslog with tag `acme`:

```bash
# View acme logs
grep acme /tmp/syslog.log

# Follow logs in real-time
tail -f /tmp/syslog.log | grep acme
```

### Log Levels
- `info` - Normal operation messages
- `error` - Error conditions
- `debug` - Detailed debug information (when ASUS_WRAPPER_DEBUG=1)

### acme.sh Log
Detailed acme.sh output is logged to:
```
/jffs/.le/acme.sh.log
```

## Advanced Configuration

### Custom DNS Sleep Time

If DNS propagation is slow, you can increase the wait time by modifying the wrapper or setting in account.conf:

```bash
# In the wrapper, the default is 120 seconds
# Modify this line if needed:
local dns_sleep="${ASUS_DNSSLEEP:-120}"
```

### Using Let's Encrypt Staging

For testing without hitting rate limits, use the staging environment:

```bash
# Add --staging to acme.sh calls
# Or use the full-diagnostic.sh tool which uses staging by default
```

### Multiple DNS Providers

If you have domains across different DNS providers, you can configure multiple certificates with different providers by using environment variables in your test scripts.
