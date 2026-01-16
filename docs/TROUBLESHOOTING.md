# Troubleshooting Guide

This guide covers common issues and their solutions when using asus-merlin-acme-wrapper.

## Quick Diagnostics

Run the validation script first:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main/tools/validate-acme-wrapper.sh | sh
```

Or if already installed:
```bash
/jffs/tools/validate-acme-wrapper.sh
```

## Common Issues

### Wrapper Not Active

**Symptoms:**
- Certificate issuance uses HTTP validation instead of DNS
- Wildcard certificates fail
- Logs show stock acme.sh behavior

**Solution:**

Check if wrapper is mounted:
```bash
mount | grep acme.sh
```

If not mounted:
```bash
# Mount now
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh

# Verify
mount | grep acme.sh
```

Ensure post-mount script is configured:
```bash
cat /jffs/scripts/post-mount
# Should contain the mount command
```

---

### DNS Validation Fails

**Symptoms:**
- Error: "DNS problem" or "Timeout during connect"
- Error: "Incorrect TXT record"

**Solutions:**

1. **Verify DNS API credentials:**
```bash
cat /jffs/.le/account.conf | grep -i "aws\|cf_\|gd_"
```

2. **Check DNS API is set correctly:**
```bash
grep "DNS_API" /jffs/sbin/asus-wrapper-acme.sh
echo $ASUS_WRAPPER_DNS_API
```

3. **Test DNS API manually:**
```bash
/jffs/tools/diagnose-acme-issue.sh
```

4. **Verify DNS propagation:**
```bash
# Check if TXT record was created
dig _acme-challenge.yourdomain.com TXT

# Or using nslookup
nslookup -type=TXT _acme-challenge.yourdomain.com
```

5. **Increase DNS sleep time:**

   Edit wrapper and change `--dnssleep 120` to a higher value like `180` or `300`.

---

### Rate Limit Errors

**Symptoms:**
- Error: "too many certificates already issued"
- Error: "rate limit exceeded"

**Solutions:**

1. **Wait before retrying:**
   - Certificate rate limit: 5 per week per domain
   - Wait 1 week or use a different subdomain

2. **Use staging for testing:**
```bash
/jffs/tools/full-diagnostic.sh  # Uses staging by default
```

3. **Check existing certificates:**
```bash
/opt/home/acme.sh/acme.sh --list
```

---

### Certificate Not Updating in Router

**Symptoms:**
- New certificate issued but router still shows old cert
- HTTPS shows expired certificate

**Solutions:**

1. **Restart HTTP daemon:**
```bash
service restart_httpd
```

2. **Check symlinks:**
```bash
ls -la /jffs/.cert/
# Should point to current certificate directory
```

3. **Verify certificate files:**
```bash
ls -la /jffs/.le/yourdomain.com_ecc/
openssl x509 -in /jffs/.le/yourdomain.com_ecc/fullchain.pem -noout -dates
```

---

### Wrapper Not Surviving Reboot

**Symptoms:**
- After reboot, certificate operations fail
- Mount not present after reboot

**Solutions:**

1. **Check post-mount script exists and is executable:**
```bash
ls -la /jffs/scripts/post-mount
cat /jffs/scripts/post-mount
```

2. **Verify content:**
```bash
grep "asus-wrapper-acme.sh" /jffs/scripts/post-mount
```

3. **Make executable:**
```bash
chmod +x /jffs/scripts/post-mount
```

4. **Correct post-mount script:**
```bash
#!/bin/sh
sleep 5
if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
```

---

### Domains File Not Found

**Symptoms:**
- Error: "Domains file not found"
- Error: "Domains file is empty"

**Solutions:**

1. **Create domains file:**
```bash
mkdir -p /jffs/.le
cat > /jffs/.le/domains << 'EOF'
*.yourdomain.com|yourdomain.com
EOF
```

2. **Check file permissions:**
```bash
ls -la /jffs/.le/domains
chmod 644 /jffs/.le/domains
```

3. **Verify content:**
```bash
cat /jffs/.le/domains
```

---

### Real acme.sh Not Found

**Symptoms:**
- Error: "Real acme.sh not found"

**Solutions:**

1. **Install acme.sh via Entware:**
```bash
opkg update
opkg install acme
```

2. **Verify installation:**
```bash
ls -la /opt/home/acme.sh/acme.sh
/opt/home/acme.sh/acme.sh --version
```

3. **Check Entware is running:**
```bash
ls /opt/bin/
# Should show Entware binaries
```

---

### Certificate Shows Wrong SANs

**Symptoms:**
- Certificate has only one domain
- Wildcard not included
- Separate certificates created instead of one with SANs

**Solutions:**

1. **Verify wrapper version:**
```bash
grep "SCRIPT_VERSION" /jffs/sbin/asus-wrapper-acme.sh
# Should be 1.0.4 or newer
```

2. **Check domains file format:**
```bash
cat /jffs/.le/domains
# Format should be: *.domain.com|domain.com
```

3. **Delete old certificate and re-issue:**
```bash
rm -rf /jffs/.le/yourdomain.com_ecc
service restart_letsencrypt
```

4. **Verify new certificate:**
```bash
openssl x509 -in /jffs/.le/yourdomain.com_ecc/fullchain.pem \
  -text -noout | grep -A 2 "Subject Alternative Name"
```

---

## Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable debug
export ASUS_WRAPPER_DEBUG=1

# Trigger certificate operation
service restart_letsencrypt

# View debug logs
grep acme /tmp/syslog.log | tail -50
```

## Log Files

| File | Contents |
|------|----------|
| `/tmp/syslog.log` | System log including wrapper messages |
| `/jffs/.le/acme.sh.log` | Detailed acme.sh output |
| `/tmp/acme-wrapper-output-*.log` | Temporary output during operations |

## Getting Help

1. **Run full diagnostic:**
```bash
/jffs/tools/full-diagnostic.sh 2>&1 | tee /tmp/diagnostic.log
```

2. **Collect information for support:**
```bash
echo "=== Wrapper Version ===" > /tmp/support-info.txt
grep SCRIPT_VERSION /jffs/sbin/asus-wrapper-acme.sh >> /tmp/support-info.txt
echo "=== Domains File ===" >> /tmp/support-info.txt
cat /jffs/.le/domains >> /tmp/support-info.txt
echo "=== Mount Status ===" >> /tmp/support-info.txt
mount | grep acme >> /tmp/support-info.txt
echo "=== Recent Logs ===" >> /tmp/support-info.txt
grep acme /tmp/syslog.log | tail -50 >> /tmp/support-info.txt
```

3. **Open an issue** on GitHub with:
   - Router model and firmware version
   - DNS provider being used
   - Error messages from logs
   - Output of diagnostic scripts
