# Deploy to Fly.io

## Prerequisites

1. Install Fly CLI: https://fly.io/docs/handsctl/install/
2. Sign up: `fly auth signup` (free, no card required)
3. Login: `fly auth login`

## Quick Deploy

```bash
cd backend

# Create app (first time only)
fly launch --name flashcards --region ams --no-deploy

# Create PostgreSQL cluster
fly postgres create --name flashcards-db --region ams --size shared-cpu-1x --initial-cluster-size 1

# Attach database to app
fly postgres attach flashcards-db

# Set secrets
fly secrets set SECRET_KEY=$(openssl rand -hex 32)
fly secrets set EMAIL_API_KEY=""  # Optional: add SendGrid key later

# Deploy
fly deploy

# Check status
fly status
fly logs
```

## After Deploy

Your app will be available at: `https://flashcards.fly.dev`

### Useful Commands

```bash
# View logs
fly logs

# SSH into machine
fly ssh console

# Check database
fly postgres connect flashcards-db

# Scale up (if needed)
fly scale vm shared-cpu-1x --memory 512

# Open app in browser
fly open
```

## Environment Variables

| Variable | Description |
|---|---|
| `SECRET_KEY` | JWT signing key (auto-generated) |
| `DATABASE_URL` | Auto-set by `fly postgres attach` |
| `EMAIL_API_KEY` | SendGrid API key (optional) |
| `SECURE_COOKIES` | Set to `true` (HTTPS) |
| `RATE_LIMIT_ENABLED` | Set to `true` |

## Free Tier Limits

- **3 shared-cpu-1x VMs** (256MB RAM each)
- **1GB PostgreSQL storage**
- **160GB bandwidth/month**

More than enough for a personal flashcards app!
