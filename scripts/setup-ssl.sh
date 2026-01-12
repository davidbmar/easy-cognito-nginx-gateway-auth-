#!/bin/bash

# SSL Certificate Setup Script
# Supports both self-signed certificates and Let's Encrypt automation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DOMAIN="localhost"
METHOD="self-signed"  # or "letsencrypt"
KEY_SIZE=4096         # RSA key size (2048, 4096)
VALIDITY_DAYS=365     # Certificate validity
SAN_DOMAINS=""        # Subject Alternative Names (comma-separated)
EMAIL=""              # Email for Let's Encrypt
STAGING=false         # Use Let's Encrypt staging

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --domain=DOMAIN           Domain name (default: localhost)"
    echo "  --letsencrypt             Use Let's Encrypt (production certificates)"
    echo "  --key-size=SIZE           RSA key size: 2048, 4096 (default: 4096)"
    echo "  --validity-days=DAYS      Certificate validity days (default: 365)"
    echo "  --san=DOMAINS             Subject Alternative Names (comma-separated)"
    echo "  --email=EMAIL             Email for Let's Encrypt notifications"
    echo "  --staging                 Use Let's Encrypt staging (for testing)"
    echo ""
    echo "Examples:"
    echo "  Self-signed (development):"
    echo "    $0 --domain=dev.example.com --san=www.dev.example.com,api.dev.example.com"
    echo ""
    echo "  Let's Encrypt (production):"
    echo "    $0 --domain=example.com --letsencrypt --email=admin@example.com"
    echo ""
    echo "  Let's Encrypt staging (testing):"
    echo "    $0 --domain=test.example.com --letsencrypt --staging"
    exit 1
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --letsencrypt)
            METHOD="letsencrypt"
            ;;
        --key-size=*)
            KEY_SIZE="${arg#*=}"
            ;;
        --validity-days=*)
            VALIDITY_DAYS="${arg#*=}"
            ;;
        --san=*)
            SAN_DOMAINS="${arg#*=}"
            ;;
        --email=*)
            EMAIL="${arg#*=}"
            ;;
        --staging)
            STAGING=true
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown argument $arg${NC}"
            usage
            ;;
    esac
done

# Validate key size
if [ "$KEY_SIZE" != "2048" ] && [ "$KEY_SIZE" != "4096" ]; then
    echo -e "${RED}Error: Invalid key size. Use 2048 or 4096${NC}"
    exit 1
fi

# Let's Encrypt path
if [ "$METHOD" = "letsencrypt" ]; then
    echo -e "${GREEN}Using Let's Encrypt for SSL certificate${NC}"
    echo ""

    # Build setup-letsencrypt.sh command
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LE_SCRIPT="$SCRIPT_DIR/setup-letsencrypt.sh"

    if [ ! -f "$LE_SCRIPT" ]; then
        echo -e "${RED}Error: setup-letsencrypt.sh not found at $LE_SCRIPT${NC}"
        exit 1
    fi

    LE_CMD="bash $LE_SCRIPT --domain=$DOMAIN"

    if [ -n "$EMAIL" ]; then
        LE_CMD="$LE_CMD --email=$EMAIL"
    fi

    if [ "$STAGING" = true ]; then
        LE_CMD="$LE_CMD --staging"
    fi

    echo "Running: $LE_CMD"
    exec $LE_CMD
fi

# Self-signed certificate path
SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/selfsigned.crt"
KEY_FILE="$SSL_DIR/selfsigned.key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Self-Signed SSL Certificate Generation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Domain: $DOMAIN"
echo "Key Size: RSA $KEY_SIZE"
echo "Validity: $VALIDITY_DAYS days"
if [ -n "$SAN_DOMAINS" ]; then
    echo "Subject Alternative Names: $SAN_DOMAINS"
fi
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0 $@"
    exit 1
fi

# Warning for production use
echo -e "${YELLOW}⚠️  WARNING: Self-signed certificates are NOT trusted by browsers${NC}"
echo -e "${YELLOW}   For production, use Let's Encrypt: $0 --domain=$DOMAIN --letsencrypt${NC}"
echo ""

# Create SSL directory
mkdir -p "$SSL_DIR"

# Build openssl command
OPENSSL_CMD="openssl req -x509 -nodes -days $VALIDITY_DAYS -newkey rsa:$KEY_SIZE"
OPENSSL_CMD="$OPENSSL_CMD -keyout $KEY_FILE -out $CERT_FILE"
OPENSSL_CMD="$OPENSSL_CMD -subj /C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"

# Add SAN if specified
if [ -n "$SAN_DOMAINS" ]; then
    # Build SAN string
    SAN_STRING="DNS:$DOMAIN"
    IFS=',' read -ra DOMAINS <<< "$SAN_DOMAINS"
    for domain in "${DOMAINS[@]}"; do
        # Trim whitespace
        domain=$(echo "$domain" | xargs)
        SAN_STRING="$SAN_STRING,DNS:$domain"
    done

    OPENSSL_CMD="$OPENSSL_CMD -addext subjectAltName=$SAN_STRING"
fi

# Generate certificate
echo "Generating certificate..."
if eval "$OPENSSL_CMD" 2>/dev/null; then
    echo -e "${GREEN}✓ Certificate generated successfully${NC}"
else
    echo -e "${RED}✗ Certificate generation failed${NC}"
    exit 1
fi

# Set proper permissions
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Information${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Certificate: $CERT_FILE"
echo "Private Key: $KEY_FILE"
echo ""

# Display certificate details
echo "Certificate Details:"
openssl x509 -text -noout -in "$CERT_FILE" | grep -A1 "Subject:"
openssl x509 -text -noout -in "$CERT_FILE" | grep -A1 "Validity"
if [ -n "$SAN_DOMAINS" ]; then
    echo "Subject Alternative Names:"
    openssl x509 -text -noout -in "$CERT_FILE" | grep -A1 "Subject Alternative Name"
fi
echo ""

# Display expiry date
EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
echo "Expires: $EXPIRY"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Next Steps${NC}"
echo -e "${GREEN}========================================${NC}"
echo "1. nginx will use these certificates automatically"
echo "2. Browsers will show a security warning (expected for self-signed)"
echo "3. Click 'Advanced' and accept the certificate in your browser"
echo ""
echo "For production (trusted certificates):"
echo "  sudo $0 --domain=$DOMAIN --letsencrypt --email=admin@$DOMAIN"
echo ""
echo -e "${GREEN}✓ SSL setup complete!${NC}"
