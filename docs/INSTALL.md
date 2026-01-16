# Installation Guide

This guide walks you through installing asus-merlin-acme-wrapper on your Asus router running Merlin firmware.

## Prerequisites

### 1. Merlin Firmware

Ensure your router is running [Asuswrt-Merlin](https://www.asuswrt-merlin.net/) firmware. This wrapper has been tested on version 384.x and newer.

### 2. JFFS Partition

Enable JFFS custom scripts:
1. Go to **Administration > System**
2. Set **Enable JFFS custom scripts and configs** to **Yes**
3. Click **Apply**

### 3. Entware

Install Entware for package management. You'll need a USB drive formatted as ext4.

```bash
# Format USB and install Entware
# See: https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware
entware-setup.sh
```

### 4. acme.sh

Install acme.sh via Entware:

```bash
opkg update
opkg install acme
```

Verify installation:
```bash
/opt/home/acme.sh/acme.sh --version
```

### 5. DNS Provider Credentials

You'll need API credentials for your DNS provider. See [DNS_PROVIDERS.md](DNS_PROVIDERS.md) for setup instructions.

## Installation Steps

### Step 1: Download the Wrapper Script

```bash
# Create directory if it doesn't exist
mkdir -p /jffs/sbin

# Download the wrapper
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main/scripts/asus-wrapper-acme.sh \
  -o /jffs/sbin/asus-wrapper-acme.sh

# Make executable
chmod +x /jffs/sbin/asus-wrapper-acme.sh

# Verify
head -5 /jffs/sbin/asus-wrapper-acme.sh
```

### Step 2: Create Symlink to Real acme.sh

```bash
# Create symlink (for reference, not strictly required)
ln -sf /opt/home/acme.sh/acme.sh /jffs/sbin/acme.sh
```

### Step 3: Configure Domains

Create the domains file:

```bash
# Create the .le directory if needed
mkdir -p /jffs/.le

# Create domains file
cat > /jffs/.le/domains << 'EOF'
# Format: domain1|domain2|domain3
# Wildcards supported: *.domain.com
# Last non-wildcard domain becomes certificate directory name

*.yourdomain.com|yourdomain.com
EOF
```

### Step 4: Configure DNS API Credentials

Add your DNS provider credentials to the account configuration:

```bash
# For AWS Route53
cat >> /jffs/.le/account.conf << 'EOF'
AWS_ACCESS_KEY_ID='YOUR_ACCESS_KEY'
AWS_SECRET_ACCESS_KEY='YOUR_SECRET_KEY'
EOF

# For Cloudflare
cat >> /jffs/.le/account.conf << 'EOF'
CF_Token='YOUR_API_TOKEN'
CF_Zone_ID='YOUR_ZONE_ID'
EOF
```

### Step 5: Set Up Bind Mount

The bind mount makes the firmware use our wrapper instead of the built-in acme.sh.

```bash
# Create or edit post-mount script
cat > /jffs/scripts/post-mount << 'EOF'
#!/bin/sh

# Wait for Entware to be available
sleep 5

# Mount the ACME wrapper
if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
EOF

# Make executable
chmod +x /jffs/scripts/post-mount
```

### Step 6: Activate Bind Mount

```bash
# Mount now (without rebooting)
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh

# Verify mount
mount | grep acme.sh
```

### Step 7: (Optional) Change DNS API

If you're not using AWS Route53, edit the wrapper to use your DNS provider:

```bash
# Option 1: Edit the script
sed -i 's/dns_aws/dns_cf/' /jffs/sbin/asus-wrapper-acme.sh

# Option 2: Use environment variable (add to /jffs/configs/profile.add)
echo 'export ASUS_WRAPPER_DNS_API=dns_cf' >> /jffs/configs/profile.add
```

### Step 8: Issue Certificate

```bash
# Trigger certificate issuance
service restart_letsencrypt

# Monitor progress
tail -f /tmp/syslog.log | grep acme
```

### Step 9: Verify Installation

```bash
# Download and run validation script
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main/tools/validate-acme-wrapper.sh \
  -o /tmp/validate-acme-wrapper.sh
chmod +x /tmp/validate-acme-wrapper.sh
/tmp/validate-acme-wrapper.sh
```

## Post-Installation

### Verify Certificate

```bash
# Check certificate SANs
openssl x509 -in /jffs/.le/yourdomain.com_ecc/fullchain.pem \
  -text -noout | grep -A 2 "Subject Alternative Name"

# Check expiry
openssl x509 -in /jffs/.le/yourdomain.com_ecc/fullchain.pem \
  -noout -dates
```

### Enable HTTPS in Router UI

1. Go to **Administration > System**
2. Set **Local Access Config > HTTPS LAN port** to **8443** (or your preferred port)
3. Enable **Enable HTTPS access from LAN**
4. Click **Apply**

### Automatic Renewal

The Merlin firmware handles automatic renewal via cron. Certificates are renewed approximately 60 days before expiration.

## Troubleshooting

If installation fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or run:

```bash
# Quick diagnostic
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main/tools/diagnose-acme-issue.sh | sh
```

## Uninstallation

To remove the wrapper and revert to stock behavior:

```bash
# Remove bind mount
umount /usr/sbin/acme.sh

# Remove from post-mount
sed -i '/asus-wrapper-acme/d' /jffs/scripts/post-mount

# Remove wrapper script
rm /jffs/sbin/asus-wrapper-acme.sh

# Optionally remove domains file
rm /jffs/.le/domains
```
