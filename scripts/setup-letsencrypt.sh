#!/bin/bash

# Automated Let's Encrypt SSL certificate setup with auto-renewal
# Uses certbot with nginx plugin for automatic configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DOMAIN=""
EMAIL=""
STAGING=false
NON_INTERACTIVE=true

# Usage function
usage() {
    echo "Usage: $0 --domain=example.com [--email=admin@example.com] [--staging] [--interactive]"
    echo ""
    echo "Options:"
    echo "  --domain=DOMAIN       Domain name for SSL certificate (required)"
    echo "  --email=EMAIL         Email for Let's Encrypt notifications (default: admin@DOMAIN)"
    echo "  --staging             Use Let's Encrypt staging environment (for testing)"
    echo "  --interactive         Run in interactive mode (not recommended for automation)"
    echo ""
    echo "Example:"
    echo "  $0 --domain=gateway.example.com --email=admin@example.com"
    exit 1
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --email=*)
            EMAIL="${arg#*=}"
            ;;
        --staging)
            STAGING=true
            ;;
        --interactive)
            NON_INTERACTIVE=false
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

# Validate required parameters
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: --domain is required${NC}"
    usage
fi

# Set default email if not provided
if [ -z "$EMAIL" ]; then
    EMAIL="admin@$DOMAIN"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Let's Encrypt SSL Certificate Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
if [ "$STAGING" = true ]; then
    echo -e "${YELLOW}Using STAGING environment (test certificates)${NC}"
fi
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0 $@"
    exit 1
fi

# Check if domain resolves
echo "Checking DNS resolution for $DOMAIN..."
if ! nslookup "$DOMAIN" > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: DNS lookup for $DOMAIN failed${NC}"
    echo "Make sure your domain's A record points to this server's IP address"
    echo "Current server IP addresses:"
    ip addr show | grep "inet " | awk '{print $2}' | cut -d/ -f1
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo -e "${RED}Error: nginx is not installed${NC}"
    echo "Please install nginx first or run the main install script"
    exit 1
fi

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "Starting nginx..."
    systemctl start nginx
fi

# Install certbot
echo "Installing certbot and nginx plugin..."
apt-get update
apt-get install -y certbot python3-certbot-nginx

# Build certbot command
CERTBOT_CMD="certbot --nginx -d $DOMAIN"

# Add staging flag if requested
if [ "$STAGING" = true ]; then
    CERTBOT_CMD="$CERTBOT_CMD --staging"
fi

# Add non-interactive flags
if [ "$NON_INTERACTIVE" = true ]; then
    CERTBOT_CMD="$CERTBOT_CMD --non-interactive --agree-tos --email $EMAIL --redirect"
else
    CERTBOT_CMD="$CERTBOT_CMD --email $EMAIL"
fi

# Obtain certificate
echo ""
echo "Obtaining SSL certificate from Let's Encrypt..."
echo "Command: $CERTBOT_CMD"
echo ""

if $CERTBOT_CMD; then
    echo -e "${GREEN}✓ Certificate obtained successfully!${NC}"
else
    echo -e "${RED}✗ Failed to obtain certificate${NC}"
    echo ""
    echo "Common issues:"
    echo "  1. Domain doesn't point to this server"
    echo "  2. Port 80 is not accessible from internet"
    echo "  3. nginx configuration has errors"
    echo ""
    echo "Debug steps:"
    echo "  - Check DNS: nslookup $DOMAIN"
    echo "  - Check port 80: curl http://$DOMAIN"
    echo "  - Check nginx: sudo nginx -t"
    echo "  - View certbot logs: sudo tail -50 /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi

# Set up automatic renewal
echo ""
echo "Setting up automatic certificate renewal..."

# Enable certbot timer (systemd)
systemctl enable certbot.timer
systemctl start certbot.timer

# Verify timer is active
if systemctl is-active --quiet certbot.timer; then
    echo -e "${GREEN}✓ Auto-renewal configured via systemd timer${NC}"
else
    echo -e "${YELLOW}Warning: certbot timer not active, setting up cron instead${NC}"

    # Fallback to cron
    CRON_CMD="0 0,12 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'"

    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo -e "${GREEN}✓ Auto-renewal configured via cron${NC}"
    else
        echo "Cron job already exists"
    fi
fi

# Test auto-renewal (dry run)
echo ""
echo "Testing automatic renewal (dry run)..."
if certbot renew --dry-run --quiet; then
    echo -e "${GREEN}✓ Renewal test passed${NC}"
else
    echo -e "${YELLOW}Warning: Renewal test failed${NC}"
    echo "Check logs: sudo tail -50 /var/log/letsencrypt/letsencrypt.log"
fi

# Display certificate info
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Information${NC}"
echo -e "${GREEN}========================================${NC}"

CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
if [ -d "$CERT_PATH" ]; then
    echo "Certificate directory: $CERT_PATH"
    echo "Certificate file: $CERT_PATH/fullchain.pem"
    echo "Private key: $CERT_PATH/privkey.pem"
    echo ""

    # Show expiry date
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH/fullchain.pem" | cut -d= -f2)
    echo "Expires: $EXPIRY"
    echo ""

    # Show certificate details
    echo "Subject Alternative Names:"
    openssl x509 -text -noout -in "$CERT_PATH/fullchain.pem" | grep "DNS:" | tr ',' '\n' | awk '{print "  - " $1}'
fi

# Renewal information
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Automatic Renewal${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Certificates will auto-renew before expiry (Let's Encrypt certs last 90 days)"
echo ""
echo "Check renewal status:"
echo "  sudo certbot renew --dry-run"
echo ""
echo "View certificates:"
echo "  sudo certbot certificates"
echo ""
echo "Manual renewal:"
echo "  sudo certbot renew"
echo ""
echo "Check systemd timer:"
echo "  sudo systemctl status certbot.timer"
echo "  sudo systemctl list-timers certbot"
echo ""

echo -e "${GREEN}✓ Let's Encrypt setup complete!${NC}"
echo ""
echo "Your site is now secured with HTTPS"
echo "Visit: https://$DOMAIN"
