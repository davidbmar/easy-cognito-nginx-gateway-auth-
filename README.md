

# Easy Cognito Nginx Gateway Auth

**Simple, production-ready AWS Cognito authentication gateway using nginx and oauth2-proxy**
  Why this architecture works so well:

  1. Single Responsibility: Each repo does ONE thing perfectly - gateway handles auth, ssh-helper manages access, cloner clones websites
  2. Loose Coupling: Applications don't know about authentication. They just read headers. This means you can swap out the gateway or add new apps without changing existing code
  3. Terraform Automation: The compute module's user_data template calls the install scripts, meaning both manual and IaC deployments use the SAME battle-tested installation logic
     
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Protect your web applications with AWS Cognito authentication using nginx as a reverse proxy and oauth2-proxy as the OIDC provider. No code changes required in your application!

##  Features

- **Zero Code Changes** - Works with any web application
- **Single Sign-On** - Authenticate once, access all protected apps
- **Secure** - Industry-standard OAuth2 + PKCE flow
- **Flexible** - Protect one or multiple applications
- **Production Ready** - Battle-tested configuration
- **Easy Setup** - One-command installation
- **User Info Headers** - App receives authenticated user email/ID

## 🏗️ Architecture

```
User Browser
     ↓ (HTTPS)
┌────────────────┐
│     Nginx      │  ← Reverse proxy with auth_request
│  (Ports 80/443)│
└────────┬───────┘
         │
         ├──→ /oauth2/*  → oauth2-proxy (port 4180)
         │                 ↓
         │              AWS Cognito
         │              (Authentication)
         │
         └──→ /*         → Your App (port 3000, 4000, etc.)
               (authenticated)
```

**How it works:**
1. User visits your site
2. Nginx checks authentication via oauth2-proxy
3. If not authenticated, redirects to AWS Cognito
4. User logs in with Cognito
5. oauth2-proxy validates and sets secure cookie
6. Nginx proxies request to your application
7. Your app receives `X-User-Email` header with user info

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian Linux server
- nginx installed (or will be installed)
- AWS account with Cognito User Pool configured
- Your web application running on a port (e.g., 3000)

### Installation

1. **Clone this repository:**
```bash
git clone https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth.git
cd easy-cognito-nginx-gateway-auth
```

2. **Run the installation script:**
```bash
sudo ./scripts/install.sh \
  --domain=your-domain.com \
  --cognito-region=us-east-1 \
  --cognito-pool-id=us-east-1_XXXXXXXXX \
  --cognito-client-id=YOUR_CLIENT_ID \
  --cognito-client-secret=YOUR_CLIENT_SECRET \
  --app-port=3000
```

3. **Start your application:**
```bash
# Your app should be running on the port specified (3000 in this example)
```

4. **Visit your site:**
```bash
https://your-domain.com
```

You'll be redirected to AWS Cognito for authentication!

### Bootstrap Installation (Recommended for EC2 Infrastructure)

For automated EC2 instance setup with multiple system applications:

1. **Create configuration file:**
```bash
cp config.env.example config.env
# OR use global config at /home/ubuntu/.ec2-config.env
```

2. **Edit configuration with your values:**
```bash
nano config.env
# Set COGNITO_POOL_ID, COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET, etc.
```

3. **Run bootstrap script:**
```bash
sudo scripts/bootstrap.sh
```

The bootstrap script will:
- Install oauth2-proxy binary
- Generate self-signed SSL certificates
- Configure oauth2-proxy with Cognito settings
- Set up nginx with modular configuration
- Create systemd service for oauth2-proxy
- Set up include directories for application routes

4. **Verify installation:**
```bash
scripts/verify-setup.sh
```

This approach sets up a modular nginx configuration where each application can add its own upstream and route configs to `/etc/nginx/conf.d/system-upstreams/` and `/etc/nginx/conf.d/routes/` respectively.

## 📚 Documentation

- **[Installation Guide](docs/INSTALLATION.md)** - Detailed setup instructions
- **[AWS Cognito Setup](docs/AWS_SETUP.md)** - How to configure Cognito
- **[Configuration Options](docs/CONFIGURATION.md)** - Customize the gateway
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and fixes
- **[Architecture](docs/ARCHITECTURE.md)** - How it all works
- **[Production Deployment](docs/PRODUCTION.md)** - Production best practices

## 💡 Use Cases

### Single Application

Protect one web application with Cognito authentication:

```bash
sudo ./scripts/install.sh \
  --domain=myapp.com \
  --cognito-region=us-east-1 \
  --cognito-pool-id=us-east-1_ABC123 \
  --cognito-client-id=abc123 \
  --cognito-client-secret=secret123 \
  --app-port=3000
```

### Multiple Applications

Protect multiple apps behind one authentication gateway:

```nginx
# /app1/ → port 3000
# /app2/ → port 4000
# /app3/ → port 5000
```

See [Multi-App Configuration](docs/CONFIGURATION.md#multi-app) for details.

### Microservices

Protect all your microservices with a single authentication layer:
- No auth code in each service
- Centralized user management
- Consistent security policy

## 🔐 Security Features

- ✅ OAuth2 Authorization Code Flow with PKCE
- ✅ Secure HTTPOnly cookies
- ✅ TLS/SSL encryption (HTTPS)
- ✅ CSRF protection
- ✅ Token validation
- ✅ Session management (24-hour expiry)
- ✅ No secrets in application code

## 🛠️ What Gets Installed

The installation script will:

1. Install **oauth2-proxy** v7.5.1
2. Configure **nginx** with `auth_request` directive
3. Generate **SSL certificates** (self-signed, or use your own)
4. Create **systemd service** for oauth2-proxy
5. Set up **configuration files** from templates

## 📝 Configuration Files

After installation, you'll find:

```
/etc/oauth2-proxy/config.cfg          - oauth2-proxy configuration
/etc/nginx/sites-available/auth-gateway - nginx configuration
/etc/systemd/system/oauth2-proxy.service - systemd service
/etc/nginx/ssl/                        - SSL certificates
```

## 🧪 Testing

After installation, run the test suite:

```bash
sudo ./scripts/test-auth.sh
```

This will verify:
- oauth2-proxy is running
- nginx is configured correctly
- Ports are listening
- Configuration files are valid

## 🌐 Browser Testing

1. Visit your domain: `https://your-domain.com`
2. You'll be redirected to AWS Cognito login page
3. Enter your Cognito user credentials
4. After successful login, you'll be redirected back to your app
5. Your app receives the `X-User-Email` header with user info

## 📊 Monitoring

**Check service status:**
```bash
sudo systemctl status oauth2-proxy
sudo systemctl status nginx
```

**View logs:**
```bash
# oauth2-proxy logs
sudo journalctl -u oauth2-proxy -f

# nginx error logs
sudo tail -f /var/log/nginx/error.log

# nginx access logs
sudo tail -f /var/log/nginx/access.log
```

## 🔧 Common Commands

**Restart services:**
```bash
sudo systemctl restart oauth2-proxy
sudo systemctl restart nginx
```

**Update configuration:**
```bash
# Edit oauth2-proxy config
sudo nano /etc/oauth2-proxy/config.cfg
sudo systemctl restart oauth2-proxy

# Edit nginx config
sudo nano /etc/nginx/sites-available/auth-gateway
sudo nginx -t  # Test configuration
sudo systemctl reload nginx
```

**View configuration:**
```bash
# oauth2-proxy config
cat /etc/oauth2-proxy/config.cfg

# nginx config
cat /etc/nginx/sites-available/auth-gateway
```

## 🐛 Troubleshooting

### Common Issues

**Issue: Redirect loop**
- Check oauth2-proxy is running: `systemctl status oauth2-proxy`
- Verify cookie domain matches your domain
- Check nginx logs: `tail -f /var/log/nginx/error.log`

**Issue: 502 Bad Gateway**
- Verify your application is running on the specified port
- Check: `curl http://localhost:3000` (replace 3000 with your port)

**Issue: SSL certificate errors**
- For self-signed certs, click "Advanced" and accept the warning
- For production, use Let's Encrypt: `certbot --nginx`

See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for more help.

## 📦 Examples

Check out the `examples/` directory for:

- **basic-app/** - Simple Node.js app with authentication
- **multi-app/** - Multiple apps protected by one gateway

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) - The OIDC proxy
- [nginx](https://nginx.org/) - The reverse proxy server
- [AWS Cognito](https://aws.amazon.com/cognito/) - Identity management

## 🔗 Related Projects

- [oauth2-proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [AWS Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [nginx auth_request Module](http://nginx.org/en/docs/http/ngx_http_auth_request_module.html)

## 📞 Support

- 📖 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth/issues)
- 💬 [Discussions](https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth/discussions)

---

**Made with ❤️ for the community**

⭐ Star this repo if you find it useful!
