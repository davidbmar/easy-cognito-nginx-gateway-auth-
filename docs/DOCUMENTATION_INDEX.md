# Documentation Index

**Last Updated**: 2026-01-14

This document serves as an index to all documentation across the 4-repository platform.

## Architecture Overview

This platform consists of 4 independent repositories:

```
easy-cognito-nginx-gateway-auth/  ← Authentication gateway (THIS REPO)
deploy-portal/                    ← Deployment automation
ssh-helper/                       ← Web terminal
website-cloner/                   ← Website cloning tool
```

---

## Documentation by Repository

### 1. easy-cognito-nginx-gateway-auth (Authentication Gateway)

**Location**: `github.com/davidbmar/easy-cognito-nginx-gateway-auth-`

**Purpose**: Central authentication gateway using nginx + oauth2-proxy + AWS Cognito

**Key Documentation**:
- `README.md` - Setup and installation guide
- `docs/INTEGRATION.md` - How to integrate applications with the gateway
- `docs/DEPLOYMENT_GUIDE.md` - **★ Complete deployment guide for entire platform**
- `docs/NGINX_CONFIGURATION_CHANGES.md` - Nginx routing configuration changes
- `docs/CSRF_COOKIE_FIX.md` - Troubleshooting OAuth2 CSRF cookie 403 errors

**Why deployment guide is here**: The gateway is the foundation that must be deployed first. This guide covers deploying the gateway + all 3 applications in the correct order.

---

### 2. deploy-portal (Deployment Automation)

**Location**: `github.com/davidbmar/deploy-portal`

**Purpose**: Self-service deployment portal for managing applications

**Key Documentation**:
- `README.md` - Setup and usage guide
- `docs/ARCHITECTURE.md` - System architecture diagrams
- `docs/MAC_DEPLOYMENT_GUIDE.md` - Deploying from Mac to EC2
- `scripts/deploy-to-remote.sh` - **★ Automated deployment script**

**Automation Tools**:
- `scripts/deploy-to-remote.sh` - Deploys all 4 repos to a new EC2 instance automatically

---

### 3. ssh-helper (Web Terminal)

**Location**: `github.com/davidbmar/ssh-helper`

**Purpose**: Web-based SSH terminal with xterm.js

**Key Documentation**:
- `README.md` - Setup and deployment guide
- `docs/DEPLOYMENT.md` - Production deployment instructions
- Configuration in `config.json`

---

### 4. website-cloner (Website Cloning Tool)

**Location**: `github.com/davidbmar/website-cloner`

**Purpose**: Clone websites and deploy to S3 static hosting

**Key Documentation**:
- `CLAUDE.md` - **★ Comprehensive architecture and development guide**
- `README.md` - Quick start and usage guide
- `config.example.json` - Configuration schema

**Why CLAUDE.md**: This repo has extensive architecture documentation for Claude Code sessions.

---

## Quick Start Guides

### For New Developers

1. **Understand the Platform**:
   - Read this index
   - Read `easy-cognito-nginx-gateway-auth/README.md`
   - Read `website-cloner/CLAUDE.md` for detailed architecture

2. **Set Up Local Development**:
   - Clone all 4 repositories
   - See each repo's README for setup instructions

3. **Deploy to EC2**:
   - Use `easy-cognito-nginx-gateway-auth/docs/DEPLOYMENT_GUIDE.md`
   - Or use automated script: `deploy-portal/scripts/deploy-to-remote.sh`

### For Operations

1. **Full Platform Deployment**:
   ```bash
   # Option 1: Manual (step-by-step)
   Follow: easy-cognito-nginx-gateway-auth/docs/DEPLOYMENT_GUIDE.md

   # Option 2: Automated
   deploy-portal/scripts/deploy-to-remote.sh <pem-file>
   ```

2. **Troubleshooting**:
   - CSRF/Auth issues: `easy-cognito-nginx-gateway-auth/docs/CSRF_COOKIE_FIX.md`
   - Nginx routing: `easy-cognito-nginx-gateway-auth/docs/NGINX_CONFIGURATION_CHANGES.md`
   - Gateway integration: `easy-cognito-nginx-gateway-auth/docs/INTEGRATION.md`

---

## Documentation Standards

### Where to Add New Documentation

| Topic | Repository | Directory |
|-------|-----------|-----------|
| Gateway authentication, nginx, oauth2-proxy | easy-cognito-nginx-gateway-auth | `docs/` |
| Deployment automation, provisioning | deploy-portal | `docs/` |
| SSH terminal features | ssh-helper | `docs/` |
| Website cloning architecture | website-cloner | Root (CLAUDE.md) |
| Cross-repo platform guides | easy-cognito-nginx-gateway-auth | `docs/` (as it's the foundation) |

### File Naming Conventions

- `README.md` - Primary setup/usage guide (every repo)
- `CLAUDE.md` - Detailed architecture for Claude Code (optional, but recommended)
- `ARCHITECTURE.md` - System design and diagrams
- `DEPLOYMENT.md` - Production deployment instructions
- `TROUBLESHOOTING.md` - Common issues and solutions
- `*_GUIDE.md` - Step-by-step guides (e.g., DEPLOYMENT_GUIDE.md)
- `*_FIX.md` - Specific problem resolutions (e.g., CSRF_COOKIE_FIX.md)

### What NOT to Commit

❌ **Never commit**:
- `/etc/nginx/sites-available/auth-gateway` - System config (environment-specific)
- `/etc/oauth2-proxy/config.cfg` - Contains secrets
- `*.pem` files - SSH private keys
- AWS credentials or tokens
- User-specific config files (e.g., `capsule-s3-config.json`)

✅ **Always commit**:
- Template configs (e.g., `auth-gateway.conf.template`)
- Example configs (e.g., `config.example.json`)
- Documentation updates
- Scripts and automation tools

---

## Authentication Architecture

All 4 repositories follow this pattern:

```
User Request → nginx (443)
              ↓
         oauth2-proxy (4180) ← AWS Cognito
              ↓
         nginx adds headers:
           X-User-Email
           X-Auth-Request-User
              ↓
         Backend App (trusts headers, no auth code)
```

**Key Principle**: Authentication is centralized in the gateway. Backend applications contain **ZERO authentication logic**.

---

## Deployment Flow

```
1. Deploy easy-cognito-nginx-gateway-auth (foundation)
   └→ Sets up: nginx, oauth2-proxy, SSL, AWS Cognito integration

2. Deploy backend applications (any order)
   ├→ ssh-helper (port 8080)
   ├→ deploy-portal (port 5000)
   └→ website-cloner (port 3000)

3. Configure nginx routes for each app
   └→ Each app provides nginx config snippets

4. Reload nginx
   └→ All apps now accessible via authenticated gateway
```

---

## Recent Changes (2026-01-13)

### Issues Fixed

1. ✅ OAuth redirect_mismatch after EC2 IP change
2. ✅ Root path routing (ssh-helper vs deploy-portal)
3. ✅ CSS not loading (static file serving)
4. ✅ 403 Forbidden on /deploy route
5. ✅ CSRF cookie 403 error (HTTP→HTTPS redirect)
6. ✅ SSH Helper 404 not found
7. ✅ Website Cloner 502 bad gateway

### Documentation Added

- `DEPLOYMENT_GUIDE.md` - Complete platform deployment (this update)
- `CSRF_COOKIE_FIX.md` - OAuth2 CSRF troubleshooting
- `NGINX_CONFIGURATION_CHANGES.md` - Config change history
- `deploy-to-remote.sh` - Automated deployment script

**See**: Individual files for detailed information on each fix.

---

## Support and Troubleshooting

### Common Issues

1. **Can't access gateway**: Check nginx, oauth2-proxy services
2. **Authentication loop**: Verify Cognito callback URLs match current IP/domain
3. **502 Bad Gateway**: Check if backend service is running on correct port
4. **403 Forbidden after login**: Check oauth2-proxy logs for CSRF errors

### Where to Get Help

1. **Gateway/Auth Issues**: See `easy-cognito-nginx-gateway-auth/docs/`
2. **App-Specific Issues**: See individual repo's documentation
3. **Deployment Issues**: See `DEPLOYMENT_GUIDE.md`

---

## Contributing

When adding new features or fixing bugs:

1. **Update documentation** in the appropriate repository
2. **Test on clean EC2 instance** before committing
3. **Follow naming conventions** above
4. **Update this index** if adding major new documentation
5. **Commit to git** - never leave uncommitted changes

---

## Repository URLs (Quick Reference)

```bash
git clone https://github.com/davidbmar/easy-cognito-nginx-gateway-auth-.git
git clone https://github.com/davidbmar/deploy-portal.git
git clone https://github.com/davidbmar/ssh-helper.git
git clone https://github.com/davidbmar/website-cloner.git
```

---

**Maintained By**: Platform Team
**Last Review**: 2026-01-14
**Next Review**: When major architectural changes occur
