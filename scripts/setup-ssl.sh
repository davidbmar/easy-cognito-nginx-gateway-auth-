#!/bin/bash

# Generate self-signed SSL certificates
# For production, use Let's Encrypt instead

set -e

# Parse arguments
DOMAIN="localhost"

for arg in "$@"; do
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
    esac
done

SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/selfsigned.crt"
KEY_FILE="$SSL_DIR/selfsigned.key"

echo "Generating self-signed SSL certificate for $DOMAIN..."

# Create SSL directory
mkdir -p "$SSL_DIR"

# Generate certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" \
    2>/dev/null

chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "SSL certificate generated:"
echo "  Certificate: $CERT_FILE"
echo "  Private Key: $KEY_FILE"
echo ""
echo "Note: This is a self-signed certificate."
echo "For production, use Let's Encrypt: https://letsencrypt.org/"
