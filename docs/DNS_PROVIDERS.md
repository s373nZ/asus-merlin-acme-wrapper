# DNS Provider Setup

This guide covers setting up DNS API credentials for the most common providers. The wrapper uses acme.sh's DNS plugins, which support 100+ providers.

## Supported Providers

For a full list of supported DNS providers, see the [acme.sh DNS API documentation](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

## AWS Route53

### Prerequisites
- AWS account with Route53 hosted zone
- IAM user with appropriate permissions

### Step 1: Create IAM Policy

Create a policy with the minimum required permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetHostedZone",
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName",
                "route53:GetHostedZoneCount",
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetChange"
            ],
            "Resource": "arn:aws:route53:::change/*"
        }
    ]
}
```

For better security, restrict to specific hosted zones:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/YOUR_ZONE_ID"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:GetChange"
            ],
            "Resource": "*"
        }
    ]
}
```

### Step 2: Create IAM User

1. Go to IAM > Users > Create User
2. Attach the policy created above
3. Create access keys (Security credentials > Access keys)

### Step 3: Configure Credentials

```bash
# Add to /jffs/.le/account.conf
cat >> /jffs/.le/account.conf << 'EOF'
AWS_ACCESS_KEY_ID='AKIAXXXXXXXXXXXXXXXX'
AWS_SECRET_ACCESS_KEY='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
EOF

# Set permissions
chmod 600 /jffs/.le/account.conf
```

### Step 4: Configure Wrapper

The wrapper defaults to `dns_aws`. No changes needed if using Route53.

---

## Cloudflare

### Prerequisites
- Cloudflare account with your domain
- API token with DNS edit permissions

### Step 1: Create API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) > My Profile > API Tokens
2. Click **Create Token**
3. Use the **Edit zone DNS** template, or create custom:
   - Permissions: Zone > DNS > Edit
   - Zone Resources: Include > Specific zone > your domain
4. Click **Continue to summary** > **Create Token**
5. Copy the token (shown only once)

### Step 2: Get Zone ID

1. Go to your domain's Overview page in Cloudflare
2. Scroll down to find **Zone ID** in the right sidebar
3. Copy the Zone ID

### Step 3: Configure Credentials

```bash
# Add to /jffs/.le/account.conf
cat >> /jffs/.le/account.conf << 'EOF'
CF_Token='your-api-token-here'
CF_Zone_ID='your-zone-id-here'
EOF

# Set permissions
chmod 600 /jffs/.le/account.conf
```

### Step 4: Configure Wrapper

Change the DNS API to Cloudflare:

```bash
# Option 1: Environment variable
echo 'export ASUS_WRAPPER_DNS_API=dns_cf' >> /jffs/configs/profile.add

# Option 2: Edit wrapper directly
sed -i 's/dns_aws/dns_cf/' /jffs/sbin/asus-wrapper-acme.sh
```

---

## GoDaddy

### Step 1: Get API Credentials

1. Go to [GoDaddy Developer Portal](https://developer.godaddy.com/)
2. Create a **Production** API key
3. Note your Key and Secret

### Step 2: Configure Credentials

```bash
cat >> /jffs/.le/account.conf << 'EOF'
GD_Key='your-key-here'
GD_Secret='your-secret-here'
EOF

chmod 600 /jffs/.le/account.conf
```

### Step 3: Configure Wrapper

```bash
echo 'export ASUS_WRAPPER_DNS_API=dns_gd' >> /jffs/configs/profile.add
```

---

## DigitalOcean

### Step 1: Create API Token

1. Go to [DigitalOcean API Tokens](https://cloud.digitalocean.com/account/api/tokens)
2. Click **Generate New Token**
3. Give it a name and ensure **Write** scope is enabled
4. Copy the token

### Step 2: Configure Credentials

```bash
cat >> /jffs/.le/account.conf << 'EOF'
DO_API_KEY='your-token-here'
EOF

chmod 600 /jffs/.le/account.conf
```

### Step 3: Configure Wrapper

```bash
echo 'export ASUS_WRAPPER_DNS_API=dns_dgon' >> /jffs/configs/profile.add
```

---

## Namecheap

### Step 1: Enable API Access

1. Log in to Namecheap
2. Go to Profile > Tools > API Access
3. Enable API access and whitelist your IP

### Step 2: Configure Credentials

```bash
cat >> /jffs/.le/account.conf << 'EOF'
NAMECHEAP_USERNAME='your-username'
NAMECHEAP_API_KEY='your-api-key'
NAMECHEAP_SOURCEIP='your-whitelisted-ip'
EOF

chmod 600 /jffs/.le/account.conf
```

### Step 3: Configure Wrapper

```bash
echo 'export ASUS_WRAPPER_DNS_API=dns_namecheap' >> /jffs/configs/profile.add
```

---

## Other Providers

For other DNS providers, consult the [acme.sh DNS API wiki](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

General steps:
1. Find your provider in the wiki
2. Note the required environment variables
3. Add them to `/jffs/.le/account.conf`
4. Set `ASUS_WRAPPER_DNS_API` to the correct plugin name

## Testing Your Configuration

After configuring your DNS provider, test with the staging environment:

```bash
# Run the diagnostic tool
/jffs/tools/diagnose-acme-issue.sh
```

This will attempt a staging certificate to verify your DNS API is working without affecting rate limits.

## Troubleshooting

### Common Issues

**"DNS API error" or "Unauthorized"**
- Verify your API credentials are correct
- Check that the API token has DNS edit permissions
- Ensure credentials are in `/jffs/.le/account.conf`

**"Zone not found"**
- Verify the Zone ID (for Cloudflare) or hosted zone (for Route53)
- Check that the domain in your domains file matches your DNS zone

**"Rate limit exceeded"**
- Wait 1 hour before trying again
- Use `--staging` flag for testing

**DNS propagation timeout**
- Increase `--dnssleep` value (default is 120 seconds)
- Check if your DNS provider has slow propagation
