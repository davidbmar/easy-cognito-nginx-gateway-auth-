# AWS Cognito Setup Guide

This guide walks you through setting up AWS Cognito for use with the Easy Cognito Nginx Gateway Auth.

## Overview

You need to create:
1. A Cognito User Pool
2. An App Client (with secret)
3. A test user
4. Configure the Hosted UI

## Step 1: Create Cognito User Pool

### Via AWS Console

1. Go to **AWS Cognito Console**: https://console.aws.amazon.com/cognito/
2. Click **"Create user pool"**
3. Configure sign-in experience:
   - **Sign-in options**: Email
   - Click **"Next"**

4. Configure security requirements:
   - **Password policy**: Choose your requirements
   - **Multi-factor authentication**: Optional (recommended for production)
   - Click **"Next"**

5. Configure sign-up experience:
   - **Self-registration**: Enable if you want users to sign up themselves
   - **Required attributes**: Email
   - Click **"Next"**

6. Configure message delivery:
   - **Email provider**: Cognito (for testing) or SES (for production)
   - Click **"Next"**

7. Integrate your app:
   - **User pool name**: `my-app-users` (or your choice)
   - **Hosted UI**: Configure now
   - **Domain**: Choose a Cognito domain (e.g., `my-app-1234567890`)
   - Click **"Next"**

8. Review and create

### Via AWS CLI

```bash
# Create user pool
aws cognito-idp create-user-pool \
  --pool-name "my-app-users" \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 8,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": false
    }
  }' \
  --auto-verified-attributes email \
  --region us-east-1

# Save the UserPoolId from the output
```

## Step 2: Create App Client

### Via AWS Console

1. In your User Pool, go to **"App integration"** tab
2. Scroll down to **"App clients"**
3. Click **"Create app client"**

Configure:
- **App type**: Confidential client
- **App client name**: `my-app-client`
- **Authentication flows**:
  - ✅ ALLOW_REFRESH_TOKEN_AUTH
  - ✅ ALLOW_USER_SRP_AUTH
- **OAuth 2.0 grant types**:
  - ✅ Authorization code grant
- **OpenID Connect scopes**:
  - ✅ OpenID
  - ✅ Email
  - ✅ Profile

4. Click **"Create"**

**IMPORTANT**: Save the **Client ID** and **Client Secret** - you'll need these!

### Via AWS CLI

```bash
# Get user pool ID
USER_POOL_ID="us-east-1_XXXXXXXXX"

# Create app client
aws cognito-idp create-user-pool-client \
  --user-pool-id "$USER_POOL_ID" \
  --client-name "my-app-client" \
  --generate-secret \
  --allowed-o-auth-flows "code" \
  --allowed-o-auth-scopes "openid" "email" "profile" \
  --allowed-o-auth-flows-user-pool-client \
  --callback-urls "https://your-domain.com/oauth2/callback" \
  --logout-urls "https://your-domain.com/oauth2/sign_out" \
  --supported-identity-providers "COGNITO" \
  --region us-east-1
```

## Step 3: Configure Callback URLs

After creating the app client, add your callback URLs:

### Via AWS Console

1. Go to your **App Client** in Cognito
2. Under **"Hosted UI"**, edit **"Allowed callback URLs"**:
   - Add: `https://your-domain.com/oauth2/callback`
   - Add: `http://localhost/oauth2/callback` (for local testing)

3. Edit **"Allowed sign-out URLs"**:
   - Add: `https://your-domain.com/oauth2/sign_out`

4. Save changes

### Via AWS CLI

```bash
# Update app client with callback URLs
aws cognito-idp update-user-pool-client \
  --user-pool-id "$USER_POOL_ID" \
  --client-id "$CLIENT_ID" \
  --callback-urls "https://your-domain.com/oauth2/callback" \
  --logout-urls "https://your-domain.com/oauth2/sign_out" \
  --region us-east-1
```

## Step 4: Configure Hosted UI Domain

### Via AWS Console

1. In your User Pool, go to **"App integration"** tab
2. Scroll to **"Domain"**
3. Click **"Actions" → "Create Cognito domain"**
4. Enter a domain prefix: `my-app-12345678`
   - Must be globally unique
   - Will create: `https://my-app-12345678.auth.us-east-1.amazoncognito.com`

### Via AWS CLI

```bash
# Create domain
aws cognito-idp create-user-pool-domain \
  --user-pool-id "$USER_POOL_ID" \
  --domain "my-app-12345678" \
  --region us-east-1
```

## Step 5: Create Test User

### Via AWS Console

1. In your User Pool, go to **"Users"** tab
2. Click **"Create user"**
3. Configure:
   - **Email**: `test@example.com`
   - **Password**: Set a temporary password
   - **Mark email as verified**: ✅ Yes
4. Click **"Create user"**

### Via AWS CLI

```bash
# Create user
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "test@example.com" \
  --user-attributes Name=email,Value=test@example.com Name=email_verified,Value=true \
  --temporary-password "TempPassword123!" \
  --region us-east-1

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "test@example.com" \
  --password "MySecurePassword123!" \
  --permanent \
  --region us-east-1
```

## Step 6: Test Hosted UI

Test your Cognito Hosted UI:

1. Open this URL in a browser:
```
https://YOUR_DOMAIN.auth.REGION.amazoncognito.com/login?
  client_id=YOUR_CLIENT_ID&
  response_type=code&
  scope=openid+email+profile&
  redirect_uri=https://your-domain.com/oauth2/callback
```

Replace:
- `YOUR_DOMAIN` - your Cognito domain prefix
- `REGION` - your AWS region
- `YOUR_CLIENT_ID` - your app client ID
- `your-domain.com` - your actual domain

2. You should see the Cognito login page
3. Try logging in with your test user

## Step 7: Get Required Information

You need these values for the installation:

```bash
# From Cognito console:
AWS_REGION="us-east-1"
COGNITO_POOL_ID="us-east-1_XXXXXXXXX"    # From User Pool "General settings"
CLIENT_ID="abc123def456"                  # From App Client "General settings"
CLIENT_SECRET="secret123"                 # From App Client - shown once at creation
DOMAIN="your-domain.com"                  # Your application domain
```

## IAM Permissions (Optional)

If you want to automate Cognito management, create an IAM user/role with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminSetUserPassword",
        "cognito-idp:AdminGetUser",
        "cognito-idp:ListUsers",
        "cognito-idp:DescribeUserPool",
        "cognito-idp:DescribeUserPoolClient"
      ],
      "Resource": "arn:aws:cognito-idp:REGION:ACCOUNT_ID:userpool/POOL_ID"
    }
  ]
}
```

## Production Considerations

### Email Sending

For production, use **Amazon SES** instead of Cognito's email service:

1. Verify your domain in SES
2. Move SES out of sandbox (request production access)
3. Configure Cognito to use SES:
   - User Pool → "Messaging" → "Email"
   - Select "Send email with Amazon SES"

### Custom Domain

Use a custom domain instead of Cognito's domain:

1. Have a custom domain (e.g., `auth.yourdomain.com`)
2. Create ACM certificate for the domain
3. Configure custom domain in Cognito:
   - User Pool → "App integration" → "Domain"
   - "Custom domain" → enter your domain
   - Select ACM certificate
4. Create Route53 alias record pointing to Cognito

### MFA (Multi-Factor Authentication)

Enable MFA for better security:

1. User Pool → "Sign-in experience" → "Multi-factor authentication"
2. Choose:
   - **Optional**: Users can enable MFA themselves
   - **Required**: All users must use MFA
3. MFA methods:
   - SMS
   - TOTP (Authenticator app) - recommended

## Troubleshooting

### Issue: "Login pages unavailable"

**Cause**: App client not configured correctly for Hosted UI

**Fix**:
- Verify OAuth flows are enabled
- Check callback URLs are registered
- Ensure client has a secret (confidential client)

### Issue: Invalid redirect_uri

**Cause**: Callback URL not registered in Cognito

**Fix**:
- Go to App Client settings
- Add your callback URL to "Allowed callback URLs"
- Format: `https://your-domain.com/oauth2/callback`

### Issue: User not confirmed

**Cause**: Email not verified

**Fix**:
```bash
aws cognito-idp admin-update-user-attributes \
  --user-pool-id "$USER_POOL_ID" \
  --username "user@example.com" \
  --user-attributes Name=email_verified,Value=true \
  --region us-east-1
```

## Next Steps

Once Cognito is configured, proceed with [Installation Guide](INSTALLATION.md) to set up the nginx gateway.

## Resources

- [AWS Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [Cognito User Pools](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
- [Cognito Hosted UI](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-integration.html)
