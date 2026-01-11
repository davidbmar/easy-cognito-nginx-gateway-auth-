#!/bin/bash

# Install oauth2-proxy binary
# Detects architecture and downloads the appropriate version

set -e

VERSION="v7.5.1"
INSTALL_DIR="/usr/local/bin"

echo "Detecting architecture..."
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        BINARY_ARCH="linux-amd64"
        ;;
    aarch64|arm64)
        BINARY_ARCH="linux-arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Architecture: $ARCH -> $BINARY_ARCH"
echo "Downloading oauth2-proxy $VERSION..."

DOWNLOAD_URL="https://github.com/oauth2-proxy/oauth2-proxy/releases/download/${VERSION}/oauth2-proxy-${VERSION}.${BINARY_ARCH}.tar.gz"

cd /tmp
wget -q "$DOWNLOAD_URL"
tar -xzf "oauth2-proxy-${VERSION}.${BINARY_ARCH}.tar.gz"

echo "Installing oauth2-proxy to $INSTALL_DIR..."
mv "oauth2-proxy-${VERSION}.${BINARY_ARCH}/oauth2-proxy" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/oauth2-proxy"

# Cleanup
rm -rf "/tmp/oauth2-proxy-${VERSION}.${BINARY_ARCH}"*

# Verify installation
if "$INSTALL_DIR/oauth2-proxy" --version; then
    echo "oauth2-proxy installed successfully!"
else
    echo "Error: oauth2-proxy installation failed"
    exit 1
fi
