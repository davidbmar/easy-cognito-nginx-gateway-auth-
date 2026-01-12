# Single Instance Auth Gateway - Terraform Example

Deploy a cost-optimized authentication gateway for small teams.

## Architecture

```
┌─────────────────────────────────────┐
│         Internet Gateway            │
└──────────────┬──────────────────────┘
               │
               ↓
┌─────────────────────────────────────┐
│            VPC (10.0.0.0/16)        │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Public Subnet               │  │
│  │                              │  │
│  │  ┌────────────────────────┐ │  │
│  │  │ EC2 Instance (t3.small)│ │  │
│  │  │  - nginx               │ │  │
│  │  │  - oauth2-proxy        │ │  │
│  │  │  - Let's Encrypt SSL   │ │  │
│  │  └────────────────────────┘ │  │
│  │                              │  │
│  └──────────────────────────────┘  │
│                                     │
└─────────────────────────────────────┘
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (>= 1.0)
3. **AWS CLI** configured
4. **Cognito User Pool** created (see below)
5. **Domain name** with ability to create DNS A record

## Quick Start

### Step 1: Create Cognito User Pool

```bash
# Option A: AWS Console
1. Go to AWS Cognito
2. Create User Pool
3. Create App Client (with client secret)
4. Note: Pool ID, Client ID, Client Secret

# Option B: AWS CLI
aws cognito-idp create-user-pool \
  --pool-name "auth-gateway-pool" \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}"
```

### Step 2: Configure Terraform

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth.git
cd easy-cognito-nginx-gateway-auth/terraform/examples/single-instance

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars
```

**Minimum required values:**
```hcl
region                = "us-east-1"
domain_name           = "gateway.example.com"
cognito_pool_id       = "us-east-1_XXXXXXXXX"
cognito_client_id     = "your-client-id"
cognito_client_secret = "your-client-secret"
```

### Step 3: Deploy

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy
terraform apply
```

Deployment takes about 10 minutes.

### Step 4: Update DNS

Point your domain to the Elastic IP:

```bash
# Get the IP from terraform output
terraform output public_ip

# Create DNS A record
gateway.example.com → <public_ip>
```

### Step 5: Test

```bash
# Wait for installation to complete (check logs)
ssh ubuntu@$(terraform output -raw public_ip)
sudo tail -f /var/log/user-data.log

# Visit gateway
https://gateway.example.com
# Should redirect to Cognito login
```

## Configuration Options

### Cost Optimization

```hcl
instance_type = "t3.micro"   # Cheapest option ($7/month)
allocate_eip  = false        # Use public IP instead of EIP
```

### High Availability

For production, use the `multi-az` example instead (coming soon).

### Using Existing VPC

```hcl
create_vpc      = false
existing_vpc_id = "vpc-xxxxxxxxx"
```

### SSH Access

Option 1: Static IP whitelist
```hcl
ssh_allowed_cidr_blocks = ["203.0.113.5/32"]
```

Option 2: Dynamic with ssh-helper (recommended)
```bash
# Install ssh-helper
git clone <ssh-helper-repo>

# Configure
echo "security_group_id: $(terraform output -raw security_group_id)" > config.yml

# Add your IP for 24 hours
./ssh-helper.py add --duration=24h
```

### SSL Configuration

**Let's Encrypt (default):**
```hcl
ssl_method = "letsencrypt"
ssl_email  = "admin@example.com"
```

**Self-signed (development):**
```hcl
ssl_method = "self-signed"
```

**Custom Certificate:**
After deployment, manually replace:
- `/etc/nginx/ssl/selfsigned.crt`
- `/etc/nginx/ssl/selfsigned.key`

## Outputs

```bash
# Gateway URL
terraform output gateway_url

# Public IP
terraform output public_ip

# Security Group (for ssh-helper)
terraform output security_group_id

# Next steps guide
terraform output next_steps
```

## Managing the Gateway

### View Logs

```bash
# User data (installation)
ssh ubuntu@<ip> sudo tail -f /var/log/user-data.log

# nginx
ssh ubuntu@<ip> sudo tail -f /var/log/nginx/error.log

# oauth2-proxy
ssh ubuntu@<ip> sudo journalctl -u oauth2-proxy -f
```

### Restart Services

```bash
ssh ubuntu@<ip>

# Restart nginx
sudo systemctl restart nginx

# Restart oauth2-proxy
sudo systemctl restart oauth2-proxy
```

### Update Configuration

```bash
# Edit nginx config
sudo nano /etc/nginx/sites-available/auth-gateway

# Test config
sudo nginx -t

# Reload
sudo systemctl reload nginx
```

## Adding Protected Applications

### Example: Protect website-cloner

```bash
# SSH to gateway
ssh ubuntu@<ip>

# Edit nginx config
sudo nano /etc/nginx/sites-available/auth-gateway
```

Add location block:
```nginx
location /cloner/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;

    proxy_set_header X-User $user;
    proxy_set_header X-User-Email $email;

    rewrite ^/cloner/(.*)$ /$1 break;
    proxy_pass http://127.0.0.1:3000;
}
```

Reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Troubleshooting

### Issue: Terraform apply fails

**Check AWS credentials:**
```bash
aws sts get-caller-identity
```

**Check IAM permissions:**
Ensure your IAM user/role can create EC2, VPC, IAM resources.

### Issue: Gateway not accessible after deployment

**Check installation logs:**
```bash
ssh ubuntu@<ip> sudo cat /var/log/user-data.log
```

**Check DNS:**
```bash
nslookup gateway.example.com
# Should return the correct IP
```

**Check security group:**
```bash
# Port 443 should be open
aws ec2 describe-security-groups --group-ids <sg-id>
```

### Issue: Cognito redirect loop

**Check oauth2-proxy config:**
```bash
ssh ubuntu@<ip> sudo cat /etc/oauth2-proxy/config.cfg
```

**Verify Cognito settings:**
- Callback URL must be: `https://gateway.example.com/oauth2/callback`
- Logout URL: `https://gateway.example.com/`

## Cost Estimate

### Minimum Configuration
- **EC2 t3.small:** ~$15/month
- **Elastic IP:** ~$3/month (when instance running)
- **Data transfer:** ~$1/month (low traffic)
- **Total:** ~$19/month

### Reduce Costs
- **Use t3.micro:** ~$7/month (50% savings)
- **Skip Elastic IP:** Free (but IP changes on restart)
- **Use spot instance:** ~$5/month (80% savings, may terminate)

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm deletion
yes
```

**Note:** This does NOT delete:
- Cognito User Pool (delete manually if needed)
- Route53 records (delete manually)
- CloudWatch logs (delete manually if needed)

## Related Documentation

- [Main README](../../../README.md)
- [Installation Scripts](../../../scripts/)
- [nginx Configuration](../../../config/nginx/)
- [Troubleshooting Guide](../../../docs/TROUBLESHOOTING.md)

## Support

For issues or questions:
- GitHub Issues: https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth/issues
- Documentation: https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth/docs/
