# syntax=docker/dockerfile:1.4

# Dockerfile for testing asus-merlin-acme-wrapper
#
# This creates a minimal environment that simulates the router filesystem
# for testing the wrapper script without an actual router.
#
# Build: docker build -t acme-wrapper-test .
# Run:   docker run --rm acme-wrapper-test

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    bash \
    coreutils \
    openssl \
    curl \
    grep \
    sed \
    findutils

# Create router-like directory structure
RUN mkdir -p /jffs/sbin \
    && mkdir -p /jffs/.le \
    && mkdir -p /jffs/scripts \
    && mkdir -p /jffs/tools \
    && mkdir -p /opt/home/acme.sh \
    && mkdir -p /usr/sbin \
    && mkdir -p /tmp

# Create mock acme.sh that logs calls and simulates success
RUN cat > /opt/home/acme.sh/acme.sh <<'MOCKEOF'
#!/bin/sh
# Mock acme.sh for testing
echo "Mock acme.sh called with: $@" >> /tmp/acme-calls.log

case "$1" in
    --version)
        echo "https://github.com/acmesh-official/acme.sh"
        echo "v3.0.7"
        exit 0
        ;;
    --help)
        echo "Mock acme.sh - for testing only"
        exit 0
        ;;
    --list)
        echo "No certs found."
        exit 0
        ;;
    *)
        # Simulate successful certificate issuance
        echo "Mock: Processing certificate request..."
        # Create mock certificate if --issue is in args
        if echo "$@" | grep -q -- "--issue"; then
            # Extract domain from args
            domain=$(echo "$@" | grep -oE -- '--domain [^ ]+' | head -1 | cut -d' ' -f2)
            if [ -n "$domain" ]; then
                cert_dir="/jffs/.le/${domain}_ecc"
                mkdir -p "$cert_dir"
                # Create mock certificate files
                echo "MOCK CERTIFICATE" > "$cert_dir/fullchain.pem"
                echo "MOCK KEY" > "$cert_dir/domain.key"
                echo "Mock: Created certificate for $domain"
            fi
        fi
        exit 0
        ;;
esac
MOCKEOF
RUN chmod +x /opt/home/acme.sh/acme.sh

# Copy wrapper script and tools
COPY scripts/asus-wrapper-acme.sh /jffs/sbin/
COPY tools/*.sh /jffs/tools/

# Make scripts executable
RUN chmod +x /jffs/sbin/*.sh /jffs/tools/*.sh 2>/dev/null || true

# Create test domains file
RUN echo "*.test.example.com|test.example.com" > /jffs/.le/domains

# Create mock account.conf
RUN cat > /jffs/.le/account.conf <<EOF
# Mock credentials for testing
AWS_ACCESS_KEY_ID='MOCK_KEY'
AWS_SECRET_ACCESS_KEY='MOCK_SECRET'
EOF

# Create symlink like on real router
RUN ln -sf /opt/home/acme.sh/acme.sh /jffs/sbin/acme.sh

# Copy test runner
COPY tests/test-runner.sh /test-runner.sh
RUN chmod +x /test-runner.sh

# Set working directory
WORKDIR /jffs

# Run tests by default
CMD ["/test-runner.sh"]
