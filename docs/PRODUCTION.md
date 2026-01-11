# Production Deployment Guide

Best practices and recommendations for deploying the Easy Cognito Nginx Gateway Auth in production environments.

## Pre-Production Checklist

Before deploying to production, ensure you have:

- [ ] Valid SSL/TLS certificates (Let's Encrypt or commercial CA)
- [ ] Production AWS Cognito User Pool configured
- [ ] DNS configured and tested
- [ ] Backup and monitoring systems in place
- [ ] Security review completed
- [ ] Load testing performed
- [ ] Disaster recovery plan documented
- [ ] Team trained on operations

## SSL/TLS Configuration

### Use Let's Encrypt

**Never use self-signed certificates in production!**

Install Let's Encrypt:
```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
```

Obtain certificate:
```bash
sudo certbot --nginx -d your-domain.com -d www.your-domain.com
```

This will:
- Obtain certificate from Let's Encrypt
- Automatically configure nginx
- Set up auto-renewal

Verify auto-renewal:
```bash
sudo certbot renew --dry-run
```

### SSL Best Practices

Update nginx configuration:

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # Let's Encrypt certificates
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # SSL session caching
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;

    # DNS resolver for OCSP
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # ... rest of configuration
}
```

Test SSL configuration:
```bash
# Test with SSL Labs
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=your-domain.com

# Test locally
openssl s_client -connect your-domain.com:443 -tls1_2
```

## AWS Cognito Production Configuration

### User Pool Settings

**Password Policy:**
```
Minimum length: 12 characters
Require uppercase: Yes
Require lowercase: Yes
Require numbers: Yes
Require symbols: Yes
```

Configure in Cognito Console:
- User Pool → Security → Password policy

**Multi-Factor Authentication (MFA):**
```
MFA enforcement: Optional (or Required for admin users)
MFA methods: Time-based One-time Password (TOTP)
```

**Account Recovery:**
```
Password recovery: Email only
Email verification: Required
```

### Email Configuration

**Use Amazon SES:**

1. **Verify domain in SES:**
   ```bash
   aws ses verify-domain-identity --domain your-domain.com
   ```

2. **Move SES out of sandbox:**
   - Submit request in SES console
   - Provide use case details
   - Wait for approval (usually 24 hours)

3. **Configure Cognito to use SES:**
   - User Pool → Messaging → Email
   - Select "Send email with Amazon SES"
   - Choose SES region
   - Provide FROM email address

### App Client Configuration

**OAuth Settings:**
```
OAuth flows: Authorization code grant
OAuth scopes: openid, email, profile
Callback URLs: https://your-domain.com/oauth2/callback
Sign-out URLs: https://your-domain.com/oauth2/sign_out
```

**Token Lifetimes:**
```
Access token: 1 hour
ID token: 1 hour
Refresh token: 30 days
```

**Advanced Security:**
```
Enable token revocation: Yes
Prevent user existence errors: Yes (for privacy)
```

### Custom Domain

Use custom domain for Cognito Hosted UI:

1. **Get ACM certificate:**
   ```bash
   # Must be in us-east-1 for Cognito
   aws acm request-certificate \
     --domain-name auth.your-domain.com \
     --validation-method DNS \
     --region us-east-1
   ```

2. **Verify domain ownership:**
   - Add DNS CNAME records provided by ACM

3. **Configure custom domain:**
   - User Pool → App integration → Domain
   - Choose "Custom domain"
   - Enter: `auth.your-domain.com`
   - Select ACM certificate

4. **Update DNS:**
   - Add CNAME record: `auth.your-domain.com` → CloudFront distribution

5. **Update oauth2-proxy config:**
   ```ini
   oidc_issuer_url = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXXX"
   # Hosted UI will use: https://auth.your-domain.com/login
   ```

## oauth2-proxy Production Configuration

### Security Settings

```ini
# Cookie security
cookie_secure = true              # HTTPS only
cookie_httponly = true            # No JavaScript access
cookie_samesite = "lax"           # CSRF protection
cookie_secret = "..."             # Strong random secret (32+ bytes)

# Session duration
cookie_expire = "12h"             # Re-authenticate every 12 hours
cookie_refresh = "1h"             # Refresh token every hour

# Email restrictions (optional)
email_domains = ["your-company.com"]  # Restrict to company domain

# Security headers
skip_auth_strip_headers = false   # Prevent header injection
```

### Generate Strong Cookie Secret

```bash
# Generate 32-byte random secret
openssl rand -base64 32

# Add to config
cookie_secret = "GENERATED_SECRET_HERE"
```

**Important:**
- Store secret securely (consider using secrets manager)
- Use same secret across all oauth2-proxy instances
- Rotate periodically (requires user re-authentication)

### Logging

```ini
# Production logging
request_logging = true
auth_logging = true
standard_logging = true

# Log to file for log aggregation
# StandardOutput=append:/var/log/oauth2-proxy/oauth2-proxy.log
```

Configure log rotation in systemd service:

```ini
[Service]
StandardOutput=append:/var/log/oauth2-proxy/oauth2-proxy.log
StandardError=append:/var/log/oauth2-proxy/oauth2-proxy-error.log

# Limit log size
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000
```

Create log rotation:

```bash
sudo nano /etc/logrotate.d/oauth2-proxy
```

```
/var/log/oauth2-proxy/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    missingok
    postrotate
        systemctl reload oauth2-proxy > /dev/null 2>&1 || true
    endscript
}
```

## nginx Production Configuration

### Performance Tuning

```nginx
# /etc/nginx/nginx.conf

user www-data;
worker_processes auto;  # One per CPU core
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Buffer sizes
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    # Logging
    access_log /var/log/nginx/access.log combined buffer=32k flush=1m;
    error_log /var/log/nginx/error.log warn;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    # Include site configs
    include /etc/nginx/sites-enabled/*;
}
```

### Rate Limiting

Protect against abuse:

```nginx
server {
    # General rate limit
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;

    # Stricter limit for auth endpoints
    location /oauth2/ {
        limit_req zone=auth burst=5 nodelay;
        proxy_pass http://127.0.0.1:4180;
    }
}
```

### Logging

Custom log format with user info:

```nginx
log_format auth_log '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'user=$http_x_user_email '
                    'auth_time=$upstream_response_time';

server {
    access_log /var/log/nginx/auth-access.log auth_log;
}
```

Configure log rotation:

```bash
sudo nano /etc/logrotate.d/nginx
```

```
/var/log/nginx/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
```

## Monitoring and Alerting

### Health Checks

Create health check endpoint:

```nginx
location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
}
```

Monitor with external service (e.g., UptimeRobot, Pingdom, CloudWatch).

### Metrics Collection

**Option 1: nginx-module-vts**

Install nginx with vts module for metrics:
```bash
sudo apt install -y nginx-module-vts
```

Configure:
```nginx
http {
    vhost_traffic_status_zone;

    server {
        location /status {
            vhost_traffic_status_display;
            vhost_traffic_status_display_format json;
            allow 127.0.0.1;
            deny all;
        }
    }
}
```

**Option 2: Prometheus + nginx-prometheus-exporter**

Install exporter:
```bash
wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
tar -xzf nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
sudo mv nginx-prometheus-exporter /usr/local/bin/
```

Run exporter:
```bash
/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri=http://localhost/stub_status
```

### Log Aggregation

**Option 1: AWS CloudWatch Logs**

Install CloudWatch agent:
```bash
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb
```

Configure agent:
```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/nginx/access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/nginx/error",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/oauth2-proxy/oauth2-proxy.log",
            "log_group_name": "/aws/ec2/oauth2-proxy",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

**Option 2: ELK Stack (Elasticsearch, Logstash, Kibana)**

**Option 3: Splunk, Datadog, or other commercial solutions**

### Alerts

Set up alerts for:

- **Service Down:** oauth2-proxy or nginx not responding
- **High Error Rate:** >5% 5xx responses
- **Authentication Failures:** Spike in 401 responses
- **Certificate Expiry:** Alert 30 days before expiration
- **Disk Space:** >80% usage
- **Memory Usage:** >80% usage
- **High Latency:** p95 > 500ms

Example CloudWatch alarm (using AWS CLI):
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name nginx-5xx-errors \
  --alarm-description "Alert when 5xx error rate is high" \
  --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## High Availability

### Load Balancer Configuration

**AWS Application Load Balancer (ALB):**

```bash
# Create target group
aws elbv2 create-target-group \
  --name auth-gateway-targets \
  --protocol HTTPS \
  --port 443 \
  --vpc-id vpc-xxxxx \
  --health-check-path /health \
  --health-check-interval-seconds 30

# Register targets
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=i-xxxxx Id=i-yyyyy

# Create load balancer
aws elbv2 create-load-balancer \
  --name auth-gateway-lb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-xxxxx \
  --scheme internet-facing

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:... \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...
```

**Health Check Configuration:**
- Path: `/health`
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2
- Unhealthy threshold: 3

### Auto Scaling

**AWS Auto Scaling Group:**

```bash
# Create launch template
aws ec2 create-launch-template \
  --launch-template-name auth-gateway-template \
  --version-description v1 \
  --launch-template-data '{
    "ImageId": "ami-xxxxx",
    "InstanceType": "t3.small",
    "IamInstanceProfile": {"Name": "auth-gateway-role"},
    "UserData": "..."  # Base64 encoded installation script
  }'

# Create auto scaling group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name auth-gateway-asg \
  --launch-template LaunchTemplateName=auth-gateway-template \
  --min-size 2 \
  --max-size 10 \
  --desired-capacity 2 \
  --target-group-arns arn:aws:elasticloadbalancing:... \
  --vpc-zone-identifier "subnet-xxxxx,subnet-yyyyy"

# Create scaling policies
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name auth-gateway-asg \
  --policy-name scale-up \
  --scaling-adjustment 1 \
  --adjustment-type ChangeInCapacity
```

### Database for Sessions (Optional)

For very large scale, use Redis for session storage:

**Install Redis:**
```bash
sudo apt install -y redis-server
```

**Configure Redis:**
```bash
sudo nano /etc/redis/redis.conf
```

```
# Bind to localhost only
bind 127.0.0.1

# Require password
requirepass YOUR_STRONG_PASSWORD

# Persistence
save 900 1
save 300 10
save 60 10000
```

**Configure oauth2-proxy:**
```ini
session_store_type = "redis"
redis_connection_url = "redis://:YOUR_STRONG_PASSWORD@localhost:6379"
```

**Benefits:**
- Unlimited session data size
- Can revoke sessions centrally
- Shared sessions across multiple oauth2-proxy instances

## Backup and Disaster Recovery

### What to Backup

**Configuration Files:**
```bash
/etc/nginx/sites-available/auth-gateway
/etc/nginx/nginx.conf
/etc/oauth2-proxy/config.cfg
/etc/systemd/system/oauth2-proxy.service
/etc/letsencrypt/  # SSL certificates
```

**Backup Script:**

```bash
#!/bin/bash
BACKUP_DIR="/backup/auth-gateway"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR/$DATE"

# Backup configs
cp /etc/nginx/sites-available/auth-gateway "$BACKUP_DIR/$DATE/"
cp /etc/nginx/nginx.conf "$BACKUP_DIR/$DATE/"
cp /etc/oauth2-proxy/config.cfg "$BACKUP_DIR/$DATE/"
cp /etc/systemd/system/oauth2-proxy.service "$BACKUP_DIR/$DATE/"

# Backup SSL certs
cp -r /etc/letsencrypt "$BACKUP_DIR/$DATE/"

# Compress
tar -czf "$BACKUP_DIR/backup-$DATE.tar.gz" "$BACKUP_DIR/$DATE"
rm -rf "$BACKUP_DIR/$DATE"

# Upload to S3
aws s3 cp "$BACKUP_DIR/backup-$DATE.tar.gz" s3://my-backups/auth-gateway/

# Clean old backups (keep 30 days)
find "$BACKUP_DIR" -name "backup-*.tar.gz" -mtime +30 -delete

echo "Backup completed: backup-$DATE.tar.gz"
```

**Automate with cron:**
```bash
sudo crontab -e
```

```
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/backup-auth-gateway.sh
```

### Disaster Recovery Plan

**Recovery Time Objective (RTO):** 15 minutes

**Recovery Point Objective (RPO):** 24 hours

**Recovery Steps:**

1. **Provision new server**
   ```bash
   # Launch EC2 instance or provision VM
   ```

2. **Restore backups**
   ```bash
   aws s3 cp s3://my-backups/auth-gateway/backup-latest.tar.gz .
   tar -xzf backup-latest.tar.gz
   sudo cp -r backup/etc/* /etc/
   ```

3. **Install dependencies**
   ```bash
   sudo apt update
   sudo apt install -y nginx
   sudo ./scripts/setup-oauth2-proxy.sh
   ```

4. **Start services**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl start oauth2-proxy
   sudo systemctl start nginx
   ```

5. **Update DNS**
   ```bash
   # Point domain to new server IP
   ```

6. **Verify**
   ```bash
   sudo ./scripts/test-auth.sh
   # Test in browser
   ```

## Security Hardening

### Server Hardening

**Update packages:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

**Configure firewall:**
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable
```

**Disable root login:**
```bash
sudo nano /etc/ssh/sshd_config
```
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

**Install fail2ban:**
```bash
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
```

### Secrets Management

**Use AWS Secrets Manager:**

Store oauth2-proxy config:
```bash
aws secretsmanager create-secret \
  --name prod/auth-gateway/oauth2-proxy-config \
  --secret-string file:///etc/oauth2-proxy/config.cfg
```

Retrieve at startup:
```bash
#!/bin/bash
aws secretsmanager get-secret-value \
  --secret-id prod/auth-gateway/oauth2-proxy-config \
  --query SecretString \
  --output text > /etc/oauth2-proxy/config.cfg

sudo systemctl restart oauth2-proxy
```

### Regular Security Audits

**Monthly:**
- Review access logs for anomalies
- Check for failed authentication attempts
- Review user list in Cognito
- Update software packages

**Quarterly:**
- Rotate cookie_secret
- Review and update IAM permissions
- Test disaster recovery plan
- Security vulnerability scan

**Annually:**
- Full security audit
- Penetration testing
- Review and update security policies

## Performance Optimization

### Caching

**Static assets:**
```nginx
location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

**API responses (if applicable):**
```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=1g;

location /api/ {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;
    proxy_cache_key "$scheme$request_method$host$request_uri$http_x_user_email";
    proxy_pass http://127.0.0.1:3000;
}
```

### CDN Integration

Use CloudFront or other CDN for static assets:

```nginx
location /static/ {
    # Serve from local first, fallback to CDN
    try_files $uri @cdn;
}

location @cdn {
    proxy_pass https://cdn.example.com;
}
```

## Compliance

### GDPR Compliance

- **Data Minimization:** Only collect necessary user data (email, name)
- **Right to Erasure:** Provide user deletion in Cognito
- **Data Portability:** Allow users to export their data
- **Privacy Policy:** Link to privacy policy on login page
- **Cookie Consent:** Implement cookie consent banner

### HIPAA Compliance (if applicable)

- **AWS Business Associate Agreement (BAA):** Sign with AWS
- **Encryption:** Enable encryption at rest for logs
- **Audit Logging:** Enable detailed audit logs
- **Access Controls:** Implement strict access controls

### SOC 2 Compliance

- **Access Logs:** Maintain detailed access logs
- **Change Management:** Document all configuration changes
- **Incident Response:** Have documented incident response plan
- **Vendor Management:** Maintain list of third-party services

## Cost Optimization

**AWS Cognito Costs:**
- Free tier: 50,000 MAUs (Monthly Active Users)
- Beyond free tier: $0.0055 per MAU
- Advanced security features: Additional cost

**EC2 Costs:**
- t3.small: ~$15/month (suitable for small deployments)
- t3.medium: ~$30/month (suitable for medium deployments)
- Use Reserved Instances for 30-40% savings

**ALB Costs:**
- ~$16/month base cost
- ~$0.008 per LCU-hour

**Total Estimated Cost (Small Deployment):**
- EC2 (t3.small): $15/month
- Cognito (within free tier): $0/month
- Data transfer: $5-10/month
- **Total: ~$20-25/month**

## Launch Checklist

Before going live:

- [ ] SSL certificates installed and tested
- [ ] DNS configured and propagated
- [ ] Cognito production pool configured
- [ ] MFA enabled for admin users
- [ ] SES configured and out of sandbox
- [ ] oauth2-proxy using strong cookie_secret
- [ ] nginx rate limiting configured
- [ ] Security headers added
- [ ] Monitoring and alerts configured
- [ ] Backup automation tested
- [ ] Load testing completed
- [ ] Disaster recovery plan documented
- [ ] Team trained on operations
- [ ] Runbook created
- [ ] Security review completed
- [ ] Privacy policy published
- [ ] Support contact information added

## Next Steps

- Review [Troubleshooting Guide](TROUBLESHOOTING.md) for common issues
- Set up monitoring dashboards
- Schedule regular security reviews
- Train team on operations and incident response
- Document runbooks for common tasks
