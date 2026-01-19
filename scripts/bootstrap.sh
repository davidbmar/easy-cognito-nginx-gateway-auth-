#!/bin/bash
set -euo pipefail

# Auth Gateway Bootstrap Script
# Sets up oauth2-proxy + nginx authentication gateway with modular configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[AUTH-GATEWAY]${NC} $1"
}

error() {
    echo -e "${RED}[AUTH-GATEWAY ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[AUTH-GATEWAY WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[AUTH-GATEWAY INFO]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (use sudo)"
    fi
}

load_config() {
    log "Loading configuration..."

    # Try to load from global config first
    if [ -f "/home/ubuntu/.ec2-config.env" ]; then
        source "/home/ubuntu/.ec2-config.env"
        log "Loaded config from /home/ubuntu/.ec2-config.env"
    elif [ -f "$PROJECT_ROOT/config.env" ]; then
        source "$PROJECT_ROOT/config.env"
        log "Loaded config from $PROJECT_ROOT/config.env"
    else
        error "No configuration file found. Create /home/ubuntu/.ec2-config.env or $PROJECT_ROOT/config.env"
    fi

    # Auto-detect public IP if not set
    if [ -z "${PUBLIC_IP:-}" ]; then
        PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "")
        if [ -z "$PUBLIC_IP" ]; then
            error "Could not auto-detect PUBLIC_IP and it's not set in config"
        fi
        log "Auto-detected PUBLIC_IP: $PUBLIC_IP"
    fi

    # Validate required variables
    local required_vars=(
        "COGNITO_POOL_ID"
        "COGNITO_CLIENT_ID"
        "COGNITO_CLIENT_SECRET"
        "COGNITO_REGION"
        "COGNITO_DOMAIN"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required variable $var not set in config"
        fi
    done

    # Set defaults
    OAUTH2_PORT="${OAUTH2_PORT:-4180}"
    AWS_REGION="${AWS_REGION:-$COGNITO_REGION}"

    # Build full Cognito domain
    FULL_COGNITO_DOMAIN="${COGNITO_DOMAIN}.auth.${COGNITO_REGION}.amazoncognito.com"

    info "Configuration loaded:"
    info "  Domain/IP: $PUBLIC_IP"
    info "  Cognito Region: $COGNITO_REGION"
    info "  Cognito Pool: $COGNITO_POOL_ID"
    info "  Cognito Domain: $FULL_COGNITO_DOMAIN"
    info "  OAuth2 Port: $OAUTH2_PORT"
}

create_nginx_include_directories() {
    log "Creating nginx include directories..."

    # Create directories for modular nginx configuration
    mkdir -p /etc/nginx/conf.d/system-upstreams
    mkdir -p /etc/nginx/conf.d/routes

    # Create README files to explain the structure
    cat > /etc/nginx/conf.d/system-upstreams/README.md <<'EOF'
# System Upstreams Directory

This directory contains upstream definitions for system applications.
Each application should provide its own upstream configuration file.

Example (deploy-portal.conf):
```nginx
upstream deploy_portal {
    server 127.0.0.1:5000;
}
```
EOF

    cat > /etc/nginx/conf.d/routes/README.md <<'EOF'
# Routes Directory

This directory contains location block definitions for system applications.
Each application should provide its own routes configuration file.

Example (deploy-portal.conf):
```nginx
location /deploy/ {
    proxy_pass http://deploy_portal/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Pass authenticated user info
    proxy_set_header X-User-Email $http_x_user_email;
}
```
EOF

    chmod 755 /etc/nginx/conf.d/system-upstreams
    chmod 755 /etc/nginx/conf.d/routes

    log "Nginx include directories created"
}

install_auth_gateway() {
    log "Installing authentication gateway..."

    # Run the existing install.sh with our configuration
    cd "$SCRIPT_DIR"

    # For automated install, we'll call install.sh non-interactively
    # by pre-answering 'yes' to confirmation
    echo "y" | bash "$SCRIPT_DIR/install.sh" \
        --domain="$PUBLIC_IP" \
        --cognito-region="$COGNITO_REGION" \
        --cognito-pool-id="$COGNITO_POOL_ID" \
        --cognito-client-id="$COGNITO_CLIENT_ID" \
        --cognito-client-secret="$COGNITO_CLIENT_SECRET" \
        --oauth2-port="$OAUTH2_PORT" \
        --app-port="5000" \
        --app-path="/" \
        --skip-cognito-validation

    log "Authentication gateway installed"
}

fix_oauth2_permissions() {
    log "Fixing OAuth2 proxy file permissions..."

    # Ensure correct ownership for oauth2-proxy config
    # The service runs as ubuntu user, so the config must be readable
    if [ -f "/etc/oauth2-proxy/config.cfg" ]; then
        chown ubuntu:ubuntu /etc/oauth2-proxy/config.cfg
        chmod 600 /etc/oauth2-proxy/config.cfg
        log "OAuth2 proxy config ownership fixed (ubuntu:ubuntu)"
    else
        warn "OAuth2 proxy config file not found at /etc/oauth2-proxy/config.cfg"
    fi
}

add_nginx_buffer_settings() {
    log "Adding nginx buffer settings for OAuth headers..."

    # Check if buffer settings already exist
    if grep -q "proxy_buffer_size" /etc/nginx/sites-available/auth-gateway; then
        log "Nginx buffer settings already present"
        return
    fi

    # Add buffer settings to the HTTPS server block
    # These are needed because OAuth2 callback headers can be very large
    local temp_file=$(mktemp)

    awk '
    /^server {/ {
        in_server = 1
        print
        next
    }

    in_server && /listen 443 ssl/ {
        print
        print ""
        print "    # OAuth2 headers can be large - increase buffers"
        print "    proxy_buffer_size 16k;"
        print "    proxy_buffers 4 16k;"
        print "    proxy_busy_buffers_size 32k;"
        print ""
        buffer_added = 1
        next
    }

    { print }
    ' /etc/nginx/sites-available/auth-gateway > "$temp_file"

    if [ -s "$temp_file" ]; then
        mv "$temp_file" /etc/nginx/sites-available/auth-gateway
        log "Nginx buffer settings added"
    else
        rm "$temp_file"
        warn "Failed to add nginx buffer settings"
    fi
}

configure_modular_nginx() {
    log "Configuring modular nginx includes..."

    # Backup the auth-gateway config
    if [ -f "/etc/nginx/sites-available/auth-gateway" ]; then
        cp /etc/nginx/sites-available/auth-gateway /etc/nginx/sites-available/auth-gateway.backup
    fi

    # Check if includes are already present
    if ! grep -q "include /etc/nginx/conf.d/system-upstreams/\*.conf;" /etc/nginx/sites-available/auth-gateway; then
        # Add include statements before the server block closes
        # We'll add them right after the oauth2 proxy upstream definition

        # Create a temporary file with the includes
        local temp_file=$(mktemp)

        # Read the file and insert includes after the oauth2_proxy upstream block
        awk '
        /^upstream oauth2_proxy/,/^}/ {
            print
            if (/^}/) {
                print ""
                print "# System application upstreams"
                print "include /etc/nginx/conf.d/system-upstreams/*.conf;"
                print ""
                added_upstreams = 1
            }
            next
        }

        /^server/,/^}/ {
            # Inside server block
            if (/location \/oauth2\//) {
                in_oauth2_location = 1
            }
            if (in_oauth2_location && /^    }/) {
                in_oauth2_location = 0
                print
                if (!added_routes) {
                    print ""
                    print "    # System application routes"
                    print "    include /etc/nginx/conf.d/routes/*.conf;"
                    print ""
                    added_routes = 1
                }
                next
            }
            print
            next
        }

        { print }
        ' /etc/nginx/sites-available/auth-gateway > "$temp_file"

        mv "$temp_file" /etc/nginx/sites-available/auth-gateway

        log "Added include statements to nginx config"
    else
        log "Include statements already present in nginx config"
    fi

    # Test nginx configuration
    if nginx -t 2>&1 | grep -q "successful"; then
        log "Nginx configuration is valid"
    else
        warn "Nginx configuration test failed, restoring backup"
        if [ -f "/etc/nginx/sites-available/auth-gateway.backup" ]; then
            mv /etc/nginx/sites-available/auth-gateway.backup /etc/nginx/sites-available/auth-gateway
        fi
        error "Failed to configure modular nginx includes"
    fi
}

reload_services() {
    log "Reloading services..."

    systemctl daemon-reload

    if systemctl is-active --quiet oauth2-proxy; then
        systemctl restart oauth2-proxy
    else
        systemctl start oauth2-proxy
    fi

    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
    else
        systemctl start nginx
    fi

    # Enable services to start on boot
    systemctl enable oauth2-proxy
    systemctl enable nginx

    log "Services reloaded"
}

verify_installation() {
    log "Verifying installation..."

    # Check if oauth2-proxy is running
    if ! systemctl is-active --quiet oauth2-proxy; then
        error "oauth2-proxy service is not running"
    fi

    # Check if nginx is running
    if ! systemctl is-active --quiet nginx; then
        error "nginx service is not running"
    fi

    # Check if oauth2-proxy is responding
    if curl -s http://localhost:$OAUTH2_PORT/ping | grep -q "OK"; then
        log "oauth2-proxy is responding correctly"
    else
        warn "oauth2-proxy is not responding to /ping"
    fi

    # Check if directories exist
    if [ ! -d "/etc/nginx/conf.d/system-upstreams" ]; then
        error "System upstreams directory not created"
    fi

    if [ ! -d "/etc/nginx/conf.d/routes" ]; then
        error "Routes directory not created"
    fi

    log "Verification complete"
}

main() {
    log "Starting auth gateway bootstrap..."

    check_root
    load_config
    create_nginx_include_directories
    install_auth_gateway
    fix_oauth2_permissions
    add_nginx_buffer_settings
    configure_modular_nginx
    reload_services
    verify_installation

    log "Auth gateway bootstrap complete!"
    info ""
    info "Next steps:"
    info "  1. Add application upstreams to /etc/nginx/conf.d/system-upstreams/"
    info "  2. Add application routes to /etc/nginx/conf.d/routes/"
    info "  3. Reload nginx: sudo systemctl reload nginx"
    info ""
    info "Access the gateway at: https://$PUBLIC_IP/"
}

main "$@"
