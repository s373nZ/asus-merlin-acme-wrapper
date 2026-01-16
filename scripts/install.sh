#!/bin/sh

################################################################################
# install.sh
#
# Installer script for asus-merlin-acme-wrapper
# Run with: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main/scripts/install.sh | sh
#
# Part of asus-merlin-acme-wrapper
# https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper
################################################################################

set -e

# Configuration
REPO_URL="https://raw.githubusercontent.com/YOUR_USERNAME/asus-merlin-acme-wrapper/main"
INSTALL_DIR="/jffs/sbin"
LE_DIR="/jffs/.le"
SCRIPTS_DIR="/jffs/scripts"

# Colors (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

echo_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo "${RED}[ERROR]${NC} $1"
}

echo ""
echo "=========================================="
echo "  asus-merlin-acme-wrapper Installer"
echo "=========================================="
echo ""

# Check if running on Asus Merlin
echo_info "Checking environment..."

if [ ! -d "/jffs" ]; then
    echo_error "JFFS partition not found. Is this an Asus router with Merlin firmware?"
    exit 1
fi

if [ ! -w "/jffs" ]; then
    echo_error "JFFS partition is not writable. Enable JFFS in Administration > System"
    exit 1
fi

echo_info "JFFS partition found and writable"

# Check for Entware and acme.sh
if [ ! -f "/opt/home/acme.sh/acme.sh" ]; then
    echo_warn "acme.sh not found at /opt/home/acme.sh/acme.sh"
    echo_warn "Install it via Entware: opkg install acme"

    if [ ! -d "/opt/bin" ]; then
        echo_error "Entware not installed. Please install Entware first."
        echo_error "See: https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware"
        exit 1
    fi

    echo_info "Attempting to install acme.sh via Entware..."
    opkg update
    opkg install acme

    if [ ! -f "/opt/home/acme.sh/acme.sh" ]; then
        echo_error "Failed to install acme.sh"
        exit 1
    fi
fi

echo_info "acme.sh found: $(/opt/home/acme.sh/acme.sh --version | head -1)"

# Create directories
echo_info "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LE_DIR"
mkdir -p "$SCRIPTS_DIR"

# Download wrapper script
echo_info "Downloading wrapper script..."
curl -fsSL "$REPO_URL/scripts/asus-wrapper-acme.sh" -o "$INSTALL_DIR/asus-wrapper-acme.sh"
chmod +x "$INSTALL_DIR/asus-wrapper-acme.sh"

# Verify download
if grep -q "SCRIPT_VERSION" "$INSTALL_DIR/asus-wrapper-acme.sh"; then
    version=$(grep "SCRIPT_VERSION=" "$INSTALL_DIR/asus-wrapper-acme.sh" | head -1 | cut -d'"' -f2)
    echo_info "Wrapper script installed: v$version"
else
    echo_error "Download verification failed"
    exit 1
fi

# Create domains file if it doesn't exist
if [ ! -f "$LE_DIR/domains" ]; then
    echo_info "Creating sample domains file..."
    cat > "$LE_DIR/domains" << 'EOF'
# Configure your domains here
# Format: *.yourdomain.com|yourdomain.com
# Uncomment and edit the line below:
# *.yourdomain.com|yourdomain.com
EOF
    echo_warn "Please edit $LE_DIR/domains with your domain configuration"
else
    echo_info "Domains file already exists, preserving"
fi

# Set up post-mount script
echo_info "Configuring post-mount script..."

if [ -f "$SCRIPTS_DIR/post-mount" ]; then
    if grep -q "asus-wrapper-acme.sh" "$SCRIPTS_DIR/post-mount"; then
        echo_info "post-mount already configured"
    else
        echo_info "Adding wrapper mount to existing post-mount script"
        cat >> "$SCRIPTS_DIR/post-mount" << 'EOF'

# asus-merlin-acme-wrapper wrapper mount
if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
EOF
    fi
else
    echo_info "Creating post-mount script"
    cat > "$SCRIPTS_DIR/post-mount" << 'EOF'
#!/bin/sh

# Wait for Entware
sleep 5

# asus-merlin-acme-wrapper wrapper mount
if [ -f /jffs/sbin/asus-wrapper-acme.sh ]; then
    /bin/mount -o bind /jffs/sbin/asus-wrapper-acme.sh /usr/sbin/acme.sh
fi
EOF
fi

chmod +x "$SCRIPTS_DIR/post-mount"

# Mount the wrapper now
echo_info "Mounting wrapper..."
if mount | grep -q "/usr/sbin/acme.sh"; then
    echo_info "Wrapper already mounted, remounting..."
    umount /usr/sbin/acme.sh
fi

mount -o bind "$INSTALL_DIR/asus-wrapper-acme.sh" /usr/sbin/acme.sh

if mount | grep -q "/usr/sbin/acme.sh"; then
    echo_info "Wrapper mounted successfully"
else
    echo_error "Failed to mount wrapper"
    exit 1
fi

# Download utility scripts (optional)
echo_info "Downloading utility scripts..."
mkdir -p /jffs/tools

for script in validate-acme-wrapper.sh diagnose-acme-issue.sh; do
    curl -fsSL "$REPO_URL/tools/$script" -o "/jffs/tools/$script" 2>/dev/null || true
    [ -f "/jffs/tools/$script" ] && chmod +x "/jffs/tools/$script"
done

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Configure your domains:"
echo "   nano $LE_DIR/domains"
echo ""
echo "2. Add your DNS provider credentials:"
echo "   nano $LE_DIR/account.conf"
echo "   (See docs/DNS_PROVIDERS.md for examples)"
echo ""
echo "3. Set DNS provider (if not using AWS Route53):"
echo "   echo 'export ASUS_WRAPPER_DNS_API=dns_cf' >> /jffs/configs/profile.add"
echo ""
echo "4. Issue certificate:"
echo "   service restart_letsencrypt"
echo ""
echo "5. Verify installation:"
echo "   /jffs/tools/validate-acme-wrapper.sh"
echo ""
echo "Documentation: https://github.com/YOUR_USERNAME/asus-merlin-acme-wrapper"
echo ""
