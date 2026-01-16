# Asus Merlin ACME Wrapper

A wrapper script for acme.sh on Asus routers running Merlin firmware that enables DNS-based validation, wildcard certificates, and proper Subject Alternative Names (SANs).

## Features

- **DNS-based validation** - Use DNS providers (AWS Route53, Cloudflare, etc.) instead of HTTP validation
- **Wildcard certificate support** - Request certificates like `*.yourdomain.com`
- **Multiple SANs in a single certificate** - Combine wildcard and base domains in one cert
- **Seamless integration** - Works with Asus Merlin's built-in Let's Encrypt support
- **Configurable DNS providers** - Support for 100+ DNS providers via acme.sh
- **Robust error handling** - Comprehensive validation and logging

## The Problem This Solves

The Asus Merlin firmware has built-in Let's Encrypt support, but it:
1. Only supports HTTP validation (requires port 80 open to the internet)
2. Doesn't support wildcard certificates
3. Has limited SAN support

This wrapper intercepts the firmware's acme.sh calls to add DNS validation support, enabling wildcard certificates without exposing any ports to the internet.

## Quick Start

### Prerequisites

- Asus router running [Merlin firmware](https://www.asuswrt-merlin.net/)
- [Entware](https://github.com/Entware/Entware/wiki) installed
- acme.sh installed via Entware: `opkg install acme`
- DNS provider API credentials (e.g., AWS Route53, Cloudflare)

### Installation

```bash
# Download the wrapper script
curl -fsSL https://raw.githubusercontent.com/s373nZ/asus-merlin-acme-wrapper/main/scripts/asus-wrapper-acme.sh \
  -o /jffs/sbin/asus-wrapper-acme.sh

# Make it executable
chmod +x /jffs/sbin/asus-wrapper-acme.sh

# Create the domains file
cat > /jffs/.le/domains << 'EOF'
*.yourdomain.com|yourdomain.com
EOF

# Set up the bind mount (add to /jffs/scripts/post-mount)
cat >> /jffs/scripts/post-mount << 'EOF'
/bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
EOF
chmod +x /jffs/scripts/post-mount

# Activate the bind mount now
mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh

# Issue certificate
service restart_letsencrypt
```

See [docs/INSTALL.md](docs/INSTALL.md) for detailed installation instructions.

## Configuration

### Domains File

Create `/jffs/.le/domains` with your domain configuration:

```bash
# One certificate per line
# Domains separated by pipes (|)
# Non-wildcard domain should be included for certificate directory naming

# Example: Wildcard + base domain
*.yourdomain.com|yourdomain.com

# Example: Multiple subdomains
www.example.com|example.com|mail.example.com

# Example: Multiple certificates (one per line)
*.domain1.com|domain1.com
*.domain2.com|domain2.com
```

### Environment Variables

```bash
# Enable debug logging
export ASUS_WRAPPER_DEBUG=1

# Change DNS API (default: dns_aws)
export ASUS_WRAPPER_DNS_API=dns_cf

# Custom domains file location
export ASUS_WRAPPER_ACME_DOMAINS=/jffs/custom-domains
```

### DNS Provider Setup

See [docs/DNS_PROVIDERS.md](docs/DNS_PROVIDERS.md) for setup guides for:
- AWS Route53
- Cloudflare
- And other providers

## Documentation

- [Installation Guide](docs/INSTALL.md) - Detailed setup instructions
- [Configuration Reference](docs/CONFIGURATION.md) - All configuration options
- [DNS Provider Setup](docs/DNS_PROVIDERS.md) - Provider-specific guides
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Upgrade Guide](docs/UPGRADE.md) - Upgrading from previous versions

## Utility Scripts

The `tools/` directory contains helpful utilities:

- **validate-acme-wrapper.sh** - Validate your installation
- **diagnose-acme-issue.sh** - Troubleshoot certificate issues
- **full-diagnostic.sh** - Comprehensive diagnostic with staging test
- **test-wrapper-manually.sh** - Test acme.sh directly

## Architecture

```
Asus Merlin Firmware
        |
        | (calls /usr/sbin/acme.sh)
        v
asus-wrapper-acme.sh (bind mount)
        |
        | (parses domains, adds DNS flags)
        v
Real acme.sh (/opt/home/acme.sh/acme.sh)
        |
        | (DNS validation)
        v
Let's Encrypt CA
```

## Requirements

- Asus router with Merlin firmware (384.x or newer recommended)
- Entware installed on USB or JFFS
- acme.sh 3.0+ installed via Entware
- DNS provider with API access
- ~5MB free space on JFFS partition

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Credits

- Based on original concept by [garycnew](https://www.snbforums.com/threads/75233/)
- Built on [acme.sh](https://github.com/acmesh-official/acme.sh) by Neil Pang
- Thanks to the [Asuswrt-Merlin](https://www.asuswrt-merlin.net/) community

## Support

- [GitHub Issues](https://github.com/s373nZ/asus-merlin-acme-wrapper/issues) - Bug reports and feature requests
- [SNBForums](https://www.snbforums.com/) - Community discussion
- [Asuswrt-Merlin Wiki](https://github.com/RMerl/asuswrt-merlin.ng/wiki) - General Merlin documentation
