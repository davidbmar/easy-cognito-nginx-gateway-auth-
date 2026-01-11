# Architecture

Deep dive into how the Easy Cognito Nginx Gateway Auth works.

## Overview

The authentication gateway acts as a reverse proxy that sits between users and your applications, handling all authentication via AWS Cognito without requiring any code changes in your applications.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        User Browser                          │
│                     (https://domain.com)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS (443)
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                         nginx                                │
│                  (Reverse Proxy + SSL)                       │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Location: /oauth2/*                               │    │
│  │  → Forward to oauth2-proxy                         │    │
│  └────────────────────────────────────────────────────┘    │
│                           │                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Location: /*                                      │    │
│  │  1. auth_request /oauth2/auth                      │    │
│  │  2. If 401 → redirect to /oauth2/start             │    │
│  │  3. If 200 → proxy to application                  │    │
│  └────────────────────────────────────────────────────┘    │
└──────────────┬────────────────────────┬─────────────────────┘
               │                        │
               │ (4180)                 │ (3000)
               ↓                        ↓
┌──────────────────────┐   ┌───────────────────────────┐
│   oauth2-proxy       │   │   Your Application        │
│   (Port 4180)        │   │   (Port 3000)             │
│   - OIDC client      │   │   - Receives X-User-Email │
│   - Cookie mgmt      │   │   - No auth code needed   │
│   - Token validation │   │                           │
└──────────┬───────────┘   └───────────────────────────┘
           │
           │ OIDC Protocol
           ↓
┌──────────────────────────────────────────┐
│        AWS Cognito User Pool             │
│        (Identity Provider)               │
│        - Hosted UI                       │
│        - User management                 │
│        - Token issuance                  │
└──────────────────────────────────────────┘
```

## Authentication Flow

### Initial Request (Unauthenticated User)

```
1. User → nginx (GET /)
   ├─ nginx checks: auth_request /oauth2/auth
   │
   └─ nginx → oauth2-proxy (GET /oauth2/auth)
      ├─ oauth2-proxy checks cookie
      └─ No valid cookie → Return 401

2. nginx receives 401 from oauth2-proxy
   └─ nginx returns 302 redirect to /oauth2/start?rd=https://domain.com/

3. User → nginx (GET /oauth2/start?rd=...)
   └─ nginx → oauth2-proxy (GET /oauth2/start?rd=...)
      └─ oauth2-proxy generates state token
      └─ oauth2-proxy returns 302 redirect to Cognito

4. User → AWS Cognito (GET /login?client_id=...&redirect_uri=...&state=...)
   └─ Cognito shows login page
```

### Login and Callback (User Authenticates)

```
5. User submits credentials to Cognito
   └─ Cognito validates credentials
   └─ Cognito returns 302 redirect to /oauth2/callback?code=...&state=...

6. User → nginx (GET /oauth2/callback?code=...&state=...)
   └─ nginx → oauth2-proxy (GET /oauth2/callback?code=...&state=...)
      ├─ oauth2-proxy validates state token (CSRF protection)
      ├─ oauth2-proxy exchanges code for tokens
      │  └─ oauth2-proxy → Cognito (POST /token)
      │     └─ Returns: id_token, access_token, refresh_token
      ├─ oauth2-proxy validates id_token signature
      ├─ oauth2-proxy extracts user info (email, name, etc.)
      ├─ oauth2-proxy creates encrypted session cookie
      └─ oauth2-proxy returns 302 redirect to original URL (rd parameter)

7. User → nginx (GET / with _oauth2_proxy cookie)
   ├─ nginx checks: auth_request /oauth2/auth
   │
   └─ nginx → oauth2-proxy (GET /oauth2/auth with cookie)
      ├─ oauth2-proxy validates cookie
      ├─ oauth2-proxy decrypts session
      ├─ oauth2-proxy validates token expiry
      └─ oauth2-proxy returns 200 with X-Auth-Request-* headers

8. nginx receives 200 from oauth2-proxy
   ├─ nginx extracts user info from response headers
   ├─ nginx adds X-User-Email header
   └─ nginx → Your Application (GET / with X-User-Email: user@example.com)

9. Your Application receives request with user info
   └─ Your Application returns response
   └─ nginx → User (200 OK with response)
```

### Subsequent Requests (Authenticated User)

```
User → nginx (GET /page with _oauth2_proxy cookie)
├─ nginx checks: auth_request /oauth2/auth
│
└─ nginx → oauth2-proxy (GET /oauth2/auth with cookie)
   ├─ oauth2-proxy validates cookie (fast, in-memory)
   └─ oauth2-proxy returns 200 with user headers

nginx → Your Application (GET /page with X-User-Email)
└─ Response flows back to user
```

**Note:** After initial authentication, the auth check is extremely fast (microseconds) because oauth2-proxy only validates the encrypted cookie, not making calls to Cognito.

## Security Model

### OAuth 2.0 Authorization Code Flow

This implementation uses the **Authorization Code Flow** (most secure OAuth flow):

1. **Authorization Request** → User redirected to Cognito
2. **User Authentication** → User logs in at Cognito
3. **Authorization Code** → Cognito returns short-lived code (1-10 minutes)
4. **Token Exchange** → oauth2-proxy exchanges code for tokens (server-side, with client secret)
5. **Access Granted** → User gets encrypted session cookie

**Why this is secure:**
- Client secret never exposed to browser
- Authorization code is single-use and short-lived
- Token exchange happens server-side
- Tokens never exposed to browser (stored in encrypted cookie)

### PKCE (Proof Key for Code Exchange)

oauth2-proxy uses PKCE for additional security:

1. Generate random `code_verifier` (43-128 characters)
2. Create `code_challenge` = BASE64URL(SHA256(code_verifier))
3. Send `code_challenge` with authorization request
4. Send `code_verifier` with token exchange
5. Cognito validates: SHA256(code_verifier) == code_challenge

**Protection:** Prevents authorization code interception attacks.

### Cookie Security

Session cookies have multiple layers of security:

```ini
cookie_secret = "..."      # AES encryption key for cookie data
cookie_secure = true       # Only sent over HTTPS
cookie_httponly = true     # Not accessible via JavaScript
cookie_samesite = "lax"    # CSRF protection
```

**Cookie Contents (Encrypted):**
- User email
- Access token
- Refresh token
- Token expiry
- Issue time

**Why encrypted:** Even if cookie is intercepted, attacker can't read or modify contents without the `cookie_secret`.

### CSRF Protection

Multiple layers of CSRF protection:

1. **State Parameter:** Random token in OAuth flow, validated on callback
2. **SameSite Cookie:** Browser enforces same-site policy
3. **Origin Validation:** oauth2-proxy validates origin headers

### Token Validation

oauth2-proxy validates tokens on every request:

1. **Signature Verification:** Validates JWT signature using Cognito's public keys
2. **Expiry Check:** Ensures token not expired
3. **Issuer Validation:** Confirms token from correct Cognito pool
4. **Audience Validation:** Confirms token for correct client ID

### Header Injection Prevention

nginx sanitizes headers before passing to application:

```nginx
# Remove any X-User-Email header from client request
proxy_set_header X-User-Email "";

# Set X-User-Email from authenticated session only
auth_request_set $email $upstream_http_x_auth_request_email;
proxy_set_header X-User-Email $email;
```

**Protection:** Client can't spoof user email by sending fake header.

## Token Management

### Token Lifecycle

```
Access Token:  1 hour (default, configurable in Cognito)
ID Token:      1 hour (default, configurable in Cognito)
Refresh Token: 30 days (default, configurable in Cognito)
Session Cookie: 24 hours (default, configurable in oauth2-proxy)
```

### Token Refresh Flow

```
1. User makes request with cookie (access token expired)
   └─ oauth2-proxy detects expired access token
   └─ oauth2-proxy uses refresh token to get new tokens
      └─ oauth2-proxy → Cognito (POST /token with refresh_token)
      └─ Cognito returns new access_token and id_token
   └─ oauth2-proxy updates session cookie
   └─ Request proceeds normally
```

**Configuration:**

```ini
# In /etc/oauth2-proxy/config.cfg
cookie_refresh = "1h"    # How often to refresh token
cookie_expire = "24h"    # How long until re-authentication required
```

**Behavior:**
- `cookie_refresh < access_token_lifetime`: Token refreshed before expiry
- `cookie_expire > refresh_token_lifetime`: User must re-authenticate when refresh token expires

### Session Termination

**User Logout:**
```
User clicks logout → /oauth2/sign_out
└─ oauth2-proxy deletes session cookie
└─ oauth2-proxy redirects to Cognito logout (optional)
└─ Cognito terminates session
└─ User redirected back to application
```

**Admin Revocation:**
```bash
# Revoke user in Cognito
aws cognito-idp admin-user-global-sign-out \
  --user-pool-id POOL_ID \
  --username user@example.com
```

Next request:
- Token validation fails
- User redirected to login

## Request Processing Pipeline

### nginx Processing Phases

```
1. SSL Termination
   ├─ Decrypt HTTPS
   └─ Validate certificate

2. HTTP Request Phase
   ├─ Parse request
   └─ Match location block

3. Access Phase (auth_request)
   ├─ Sub-request to /oauth2/auth
   ├─ Wait for response
   └─ Continue if 200, redirect if 401

4. Content Phase
   ├─ Extract auth headers
   ├─ Add custom headers (X-User-Email)
   └─ Proxy to backend application

5. Response Phase
   ├─ Receive response from backend
   └─ Add security headers

6. SSL Encryption
   └─ Encrypt response
   └─ Send to client
```

### oauth2-proxy Processing

```
Request: /oauth2/auth (with cookie)
├─ Extract cookie
├─ Decrypt session data
├─ Validate token expiry
├─ Check if refresh needed
│  └─ If needed: refresh token from Cognito
├─ Return 200 with headers:
│  ├─ X-Auth-Request-User: user@example.com
│  ├─ X-Auth-Request-Email: user@example.com
│  └─ X-Auth-Request-Preferred-Username: John Doe
```

```
Request: /oauth2/auth (no valid cookie)
├─ Check for cookie → Not found or invalid
└─ Return 401 (triggers nginx redirect)
```

```
Request: /oauth2/start?rd=https://domain.com/page
├─ Generate state token (CSRF)
├─ Store state in session
├─ Generate PKCE code_verifier and code_challenge
├─ Build Cognito authorization URL
└─ Return 302 redirect to Cognito login
```

```
Request: /oauth2/callback?code=...&state=...
├─ Validate state token (CSRF protection)
├─ Extract authorization code
├─ Exchange code for tokens (with PKCE code_verifier)
│  └─ POST to Cognito /token endpoint
│     └─ Returns: access_token, id_token, refresh_token
├─ Validate id_token signature
├─ Extract user info from id_token
├─ Create encrypted session
├─ Set _oauth2_proxy cookie
└─ Return 302 redirect to original URL (rd parameter)
```

## Performance Characteristics

### Latency

**First Request (Unauthenticated):**
- Client → nginx → oauth2-proxy: ~1-2ms
- Redirect to Cognito: ~50-100ms (network)
- User authentication: depends on user
- Callback + token exchange: ~100-200ms (network + crypto)
- **Total (excluding user input):** ~150-300ms

**Authenticated Request (Cookie Valid):**
- Client → nginx → oauth2-proxy: ~1-2ms (cookie validation)
- oauth2-proxy → nginx: ~1-2ms
- nginx → application: ~1-10ms (depending on app)
- **Total Added Latency:** ~2-5ms

**Token Refresh (Expired Token):**
- Cookie validation + refresh: ~100-200ms (network to Cognito)
- **Total:** ~100-200ms (once per hour)

### Throughput

**oauth2-proxy:**
- CPU-bound (cryptography operations)
- Can handle ~10,000 requests/second on modern CPU (cookie validation)
- Token exchange: ~100-200 requests/second (network-bound to Cognito)

**nginx:**
- Can handle 10,000+ requests/second
- auth_request adds minimal overhead (~1ms per request)

**Bottlenecks:**
- Cognito API rate limits (token exchange): ~200 requests/second
- Network latency to AWS: 50-100ms
- Your application performance

### Scalability

**Horizontal Scaling:**
```
     Load Balancer
         |
    ┌────┴────┐
    ↓         ↓
  Server1   Server2
  (nginx)   (nginx)
     |         |
  oauth2    oauth2
   proxy     proxy
```

**Requirements:**
- Shared cookie_secret across all oauth2-proxy instances
- Sticky sessions NOT required (cookies work across servers)
- Consider Redis session storage for very large scale

**Vertical Scaling:**
- nginx: Increase worker_processes
- oauth2-proxy: Single-threaded, but very efficient
- For 10,000+ concurrent users, consider multiple oauth2-proxy instances

## High Availability

### Multiple nginx Instances

```
Load Balancer (AWS ALB/ELB)
    ↓
  ┌─────┬─────┐
  ↓     ↓     ↓
nginx1 nginx2 nginx3
  ↓     ↓     ↓
app1  app2  app3
```

**Requirements:**
- Same configuration on all nginx instances
- Same SSL certificates
- Health checks: `GET /oauth2/ping`

### Multiple oauth2-proxy Instances

```
nginx
  ↓
upstream oauth2_proxy {
    server 127.0.0.1:4180;
    server 127.0.0.1:4181;
    server 127.0.0.1:4182;
}
```

**Requirements:**
- Same `cookie_secret` on all instances
- Same Cognito configuration
- No session state (stateless design)

### Disaster Recovery

**Backup Requirements:**
- nginx configuration files
- oauth2-proxy configuration (includes secrets!)
- SSL certificates
- DNS records

**Recovery Steps:**
1. Restore configuration files
2. Start services
3. Update DNS if needed
4. Test authentication flow

**RTO (Recovery Time Objective):** ~5-10 minutes

**RPO (Recovery Point Objective):** 0 (no data loss, all state in AWS Cognito)

## Monitoring

### Health Checks

```bash
# oauth2-proxy health
curl http://localhost:4180/ping
# Returns: "OK"

# nginx health
curl -I https://localhost/
# Returns: 302 (redirect to Cognito)
```

### Metrics to Monitor

**oauth2-proxy:**
- Request rate (`/oauth2/auth` requests/second)
- Authentication failures (401 responses)
- Token refresh rate
- Response latency (p50, p95, p99)

**nginx:**
- Request rate
- Error rate (4xx, 5xx)
- Response latency
- Active connections

**Cognito:**
- Authentication success rate
- Token exchange rate
- Failed login attempts

### Logging

**oauth2-proxy logs:**
```
journalctl -u oauth2-proxy -f
```

Log entries:
- Authentication requests
- Token exchanges
- Cookie validation
- Errors and warnings

**nginx access logs:**
```
tail -f /var/log/nginx/access.log
```

Log format:
```
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"
```

**nginx error logs:**
```
tail -f /var/log/nginx/error.log
```

## Comparison with Alternatives

### vs. Application-Level Authentication

**Authentication Gateway (This Solution):**
- ✅ No code changes in application
- ✅ Centralized authentication
- ✅ Works with any application
- ✅ Consistent security policy
- ❌ Additional component to manage

**Application-Level:**
- ✅ No additional components
- ✅ Fine-grained control
- ❌ Code changes required
- ❌ Must implement in every app
- ❌ Inconsistent implementations

### vs. AWS ALB Authentication

**nginx + oauth2-proxy:**
- ✅ Works on-premises or any cloud
- ✅ Full control over configuration
- ✅ No AWS ALB cost
- ✅ Can customize extensively
- ❌ Must manage components

**AWS ALB Authentication:**
- ✅ Managed service (less to manage)
- ✅ Integrated with AWS ecosystem
- ❌ Requires AWS ALB ($$$)
- ❌ AWS-only solution
- ❌ Less customizable

### vs. AWS API Gateway Authorizer

**nginx + oauth2-proxy:**
- ✅ Works with any HTTP application
- ✅ No per-request cost
- ✅ Lower latency
- ❌ Must manage infrastructure

**API Gateway:**
- ✅ Serverless
- ✅ Managed service
- ❌ Per-request cost ($$)
- ❌ Higher latency
- ❌ API-only (not for web apps)

## Security Considerations

### Threats Mitigated

✅ **Session Hijacking:** Encrypted cookies, HTTPS only
✅ **CSRF Attacks:** State parameter, SameSite cookies
✅ **Token Replay:** Short-lived tokens, signature validation
✅ **Header Injection:** nginx sanitizes all headers
✅ **Man-in-the-Middle:** TLS/SSL encryption
✅ **Brute Force Login:** Cognito rate limiting, MFA
✅ **Authorization Code Interception:** PKCE

### Remaining Risks

⚠️ **Compromised Cookie Secret:** Attacker could forge sessions
→ **Mitigation:** Rotate cookie_secret regularly, use strong random value

⚠️ **Stolen Refresh Token:** Long-lived access
→ **Mitigation:** Short refresh token lifetime, detect anomalous usage

⚠️ **XSS in Application:** Could steal cookie via JavaScript
→ **Mitigation:** HTTPOnly cookie flag prevents JS access

⚠️ **Compromised Server:** Full access to sessions
→ **Mitigation:** Server hardening, regular security updates

## Related Documentation

- **[Installation Guide](INSTALLATION.md)** - Setup instructions
- **[Configuration Guide](CONFIGURATION.md)** - Configuration options
- **[Production Deployment](PRODUCTION.md)** - Production best practices
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues
