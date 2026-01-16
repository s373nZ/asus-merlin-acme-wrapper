# Upgrade Guide

This guide covers upgrading from previous versions of the ACME wrapper.

## Upgrading from v1.0.x to Latest

### Step 1: Backup Current Setup

```bash
# Backup current wrapper
cp /jffs/sbin/asus-wrapper-acme.sh /jffs/sbin/asus-wrapper-acme.sh.backup

# Backup certificates (optional but recommended)
cp -r /jffs/.le /jffs/.le.backup

# Note current version
grep SCRIPT_VERSION /jffs/sbin/asus-wrapper-acme.sh
```

### Step 2: Download New Version

```bash
# Download latest wrapper
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-ca/main/scripts/asus-wrapper-acme.sh \
  -o /jffs/sbin/asus-wrapper-acme.sh

# Make executable
chmod +x /jffs/sbin/asus-wrapper-acme.sh

# Verify new version
grep SCRIPT_VERSION /jffs/sbin/asus-wrapper-acme.sh
```

### Step 3: Remount Wrapper

The bind mount caches the old script, so you need to remount:

```bash
# Unmount old version
umount /usr/sbin/acme.sh

# Mount new version
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh

# Verify mount
mount | grep acme.sh
```

### Step 4: Verify

```bash
# Run validation
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-ca/main/tools/validate-acme-wrapper.sh | sh
```

## Upgrading from Original v0.0.7 (garycnew's version)

The original v0.0.7 wrapper from SNBForums had several issues that are fixed in this version:

### Key Differences

| Feature | v0.0.7 | v1.0.4+ |
|---------|--------|---------|
| SAN certificates | Creates separate certs | Single cert with all SANs |
| Error handling | Minimal | Comprehensive |
| Logging | Basic | Structured with log levels |
| Argument parsing | Positional | Order-independent |
| Pass-through commands | No | Yes (--version, --help, etc.) |
| Configuration | Hardcoded | Environment variables |

### Migration Steps

1. **Backup everything:**
```bash
cp /jffs/sbin/asus-wrapper-acme.sh /jffs/sbin/asus-wrapper-acme.sh.v007
cp -r /jffs/.le /jffs/.le.v007
```

2. **Check your domains file format:**
```bash
cat /jffs/.le/domains
```

   The format should be:
   ```
   *.yourdomain.com|yourdomain.com
   ```

   If it's different, update it to match this format.

3. **Install new wrapper:**
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-ca/main/scripts/asus-wrapper-acme.sh \
  -o /jffs/sbin/asus-wrapper-acme.sh
chmod +x /jffs/sbin/asus-wrapper-acme.sh
```

4. **Update DNS API if needed:**

   v0.0.7 might have used `dns_ispman`. Update to your actual provider:
   ```bash
   # Edit wrapper or set environment variable
   export ASUS_WRAPPER_DNS_API=dns_aws  # or dns_cf, etc.
   ```

5. **Delete old certificates (to get proper SANs):**
```bash
# The old version created separate certs, we need fresh ones
rm -rf /jffs/.le/yourdomain.com_ecc
```

6. **Remount and re-issue:**
```bash
umount /usr/sbin/acme.sh
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
service restart_letsencrypt
```

7. **Verify SANs:**
```bash
openssl x509 -in /jffs/.le/yourdomain.com_ecc/fullchain.pem \
  -text -noout | grep -A 2 "Subject Alternative Name"
# Should show: DNS:yourdomain.com, DNS:*.yourdomain.com
```

## Rollback Procedure

If you need to rollback to a previous version:

### Rollback to Backup

```bash
# Restore old wrapper
cp /jffs/sbin/asus-wrapper-acme.sh.backup /jffs/sbin/asus-wrapper-acme.sh

# Remount
umount /usr/sbin/acme.sh
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh

# Optionally restore certificates
rm -rf /jffs/.le
cp -r /jffs/.le.backup /jffs/.le
```

### Rollback to Stock Behavior

To completely remove the wrapper and use stock Merlin behavior:

```bash
# Remove bind mount
umount /usr/sbin/acme.sh

# Remove from post-mount
sed -i '/asus-wrapper-acme/d' /jffs/scripts/post-mount

# Delete wrapper
rm /jffs/sbin/asus-wrapper-acme.sh

# Delete domains file (stock doesn't use it)
rm /jffs/.le/domains

# Restart service
service restart_letsencrypt
```

## Version History

### v1.0.4
- Stable release with all features
- Comprehensive documentation
- Utility scripts included

### v1.0.3
- Added pass-through command support
- Improved logging

### v1.0.2
- Better argument parsing
- DNS sleep time configurable

### v1.0.1
- Bug fixes

### v1.0.0
- Complete rewrite
- Fixed SAN certificate generation
- Added environment variable configuration
- Comprehensive error handling

### v0.0.7 (Original)
- Original implementation by garycnew
- Basic DNS validation support
- Had issues with SAN certificates
