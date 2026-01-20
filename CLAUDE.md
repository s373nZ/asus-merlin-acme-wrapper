# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a wrapper script for acme.sh on Asus routers running Merlin firmware. It intercepts the firmware's built-in Let's Encrypt calls via bind mount to enable DNS-based validation, wildcard certificates, and multiple SANs.

**Key flow:** Asus firmware calls `/usr/sbin/acme.sh` → bind mount redirects to wrapper → wrapper transforms args (removes `--standalone`, adds `--dns`) → calls real acme.sh at `/opt/home/acme.sh/acme.sh`

## Commands

### Linting
```bash
# Run shellcheck on all scripts (excludes SC2034 for unused vars)
shellcheck --exclude=SC2034 scripts/*.sh tools/*.sh tests/*.sh addon/*.sh

# Check shell syntax
sh -n scripts/*.sh tools/*.sh addon/*.sh
```

### Testing
```bash
# Build and run Docker-based tests
docker build -t acme-wrapper-test -f tests/Dockerfile .
docker run --rm acme-wrapper-test

# Or run the test suite directly in the container
cd tests && docker build -t acme-wrapper-test . && docker run --rm acme-wrapper-test
```

### Formatting (optional)
```bash
shfmt -i 4 -w scripts/*.sh
```

## Architecture

### Core Files
- **scripts/asus-wrapper-acme.sh** - Main wrapper script (bind-mounted to `/usr/sbin/acme.sh` on router)
- **scripts/install.sh** - Legacy installation script
- **tools/** - Diagnostic and validation utilities for troubleshooting on routers
- **tests/** - Docker-based test environment with mock acme.sh

### amtm Addon Files
- **addon/acme-wrapper.sh** - Main addon script (install/uninstall/update/menu)
- **addon/acme-wrapper.asp** - Web UI page for router admin panel
- **addon/acme-wrapper.js** - Web UI JavaScript

### On Router (when installed as addon)
```
/jffs/addons/acme-wrapper/
├── acme-wrapper.sh        # Main addon script
├── asus-wrapper-acme.sh   # Wrapper script (bind-mounted)
├── acme-wrapper.conf      # Configuration file
├── acme-wrapper.asp       # Web UI page
├── acme-wrapper.js        # Web UI JavaScript
└── tools/                 # Diagnostic utilities
```

The wrapper parses the domains file (`/jffs/.le/domains`) which uses pipe-delimited format:
```
*.example.com|example.com|www.example.com
```

Non-wildcard domains are listed first when calling acme.sh so the certificate directory uses a non-wildcard name.

## Shell Script Conventions

- Use POSIX-compliant shell (`#!/bin/sh`) with busybox compatibility (`# shellcheck shell=busybox`)
- All scripts must pass shellcheck
- Use `readonly` for constants
- Use `local` for function variables
- Use `log_info`, `log_error`, `log_debug` functions for logging (writes to both stdout and syslog via `logger`)

## Environment Variables

- `ASUS_WRAPPER_DEBUG=1` - Enable debug logging
- `ASUS_WRAPPER_DNS_API=dns_cf` - Override DNS provider (default: `dns_aws`)
- `ASUS_WRAPPER_ACME_DOMAINS=/path/to/domains` - Custom domains file location
