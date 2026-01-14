#!/bin/bash

# Fix Static Files Permissions Script
#
# This script fixes common permission issues that prevent nginx from serving
# static files (CSS, JS, images) from application directories.
#
# Issue: nginx runs as 'www-data' user and needs execute permission on parent
# directories to access static files via the 'alias' directive.
#
# Usage:
#   sudo ./scripts/fix-static-files-permissions.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

log_info "==========================================="
log_info "Static Files Permissions Fix"
log_info "==========================================="
echo ""

# Fix /home/ubuntu permissions
log_info "Checking /home/ubuntu permissions..."

if [ ! -d /home/ubuntu ]; then
    log_error "/home/ubuntu directory not found"
    exit 1
fi

CURRENT_PERMS=$(stat -c '%a' /home/ubuntu)
log_info "Current permissions: $CURRENT_PERMS"

if [ "$CURRENT_PERMS" != "755" ]; then
    log_info "Fixing /home/ubuntu permissions..."
    chmod 755 /home/ubuntu
    log_success "Set /home/ubuntu permissions to 755"
else
    log_success "/home/ubuntu already has correct permissions (755)"
fi

# Verify www-data can access directory
log_info "Verifying www-data access..."

if sudo -u www-data test -x /home/ubuntu; then
    log_success "www-data can access /home/ubuntu ✓"
else
    log_error "www-data still cannot access /home/ubuntu"
    exit 1
fi

# Check common application directories
log_info "Checking application directories..."

for dir in /home/ubuntu/src/*/; do
    if [ -d "$dir" ]; then
        APP_NAME=$(basename "$dir")

        # Check if directory is readable by others
        if [ -r "$dir" ]; then
            log_success "✓ $APP_NAME - accessible"

            # Check for static directory
            if [ -d "$dir/static" ]; then
                if sudo -u www-data test -r "$dir/static"; then
                    log_success "  ✓ $APP_NAME/static - www-data can read"
                else
                    log_warning "  ✗ $APP_NAME/static - www-data cannot read"
                    log_info "  Fixing permissions on $APP_NAME/static..."
                    chmod -R o+r "$dir/static"
                    find "$dir/static" -type d -exec chmod o+rx {} \;
                    log_success "  Fixed $APP_NAME/static permissions"
                fi
            fi
        else
            log_warning "✗ $APP_NAME - not accessible by others"
        fi
    fi
done

echo ""
log_info "Testing static file access through nginx..."

# Test if nginx can serve a static file (if nginx is running)
if systemctl is-active --quiet nginx; then
    # Try to find and test a CSS file
    TEST_FILE=$(find /home/ubuntu/src/*/static -name "*.css" -type f 2>/dev/null | head -1)

    if [ -n "$TEST_FILE" ]; then
        log_info "Testing access to: $TEST_FILE"
        if sudo -u www-data test -r "$TEST_FILE"; then
            log_success "www-data can read static files ✓"
        else
            log_error "www-data cannot read static files"
            log_info "File permissions: $(ls -l $TEST_FILE)"
            exit 1
        fi
    else
        log_info "No CSS files found to test (this is OK if apps don't have static files)"
    fi
else
    log_warning "nginx is not running - skipping static file test"
fi

echo ""
log_success "==========================================="
log_success "All permissions fixed successfully!"
log_success "==========================================="
echo ""
log_info "Next steps:"
echo "  1. Reload nginx if it's running: sudo systemctl reload nginx"
echo "  2. Clear browser cache and refresh page"
echo "  3. CSS/JS should now load correctly"
echo ""
