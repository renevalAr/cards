# Deploy to NEXUS AI

## Prerequisites

1. **NEXUS AI account**: https://nexusai.run (sign up with GitHub, no credit card)
2. **NEXUS CLI**: `npm install -g nexusapp-cli` or `curl -fsSL https://nexusai.run/install.sh | bash`
3. **GitHub repo**: Code must be pushed to GitHub

## Quick Deploy

```powershell
# 1. Install CLI (if not installed)
npm install -g nexusapp-cli

# 2. Login
nexus auth login

# 3. Deploy
nexus deploy source `
  --repo https://github.com/renevalAr/cards `
  --name flashcards `
  --provider docker `
  --framework python `
  --services postgresql `
  --start-command "uvicorn app.main:app --host 0.0.0.0 --port 8000" `
  --wait

# 4. Check status
nexus deploy status flashcards

# 5. View logs
nexus deploy logs flashcards --follow
```

## After Deploy

- **URL**: `https://flashcards.nexusai.run`
- **PostgreSQL**: Auto-created and connected
- **Health check**: `https://flashcards.nexusai.run/api/health`

## Environment Variables

NEXUS AI auto-injects these when using `--services postgresql`:

| Variable | Description |
|---|---|
| `POSTGRES_HOST` | `postgresql` (internal hostname) |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `appdb` |
| `POSTGRES_USER` | `appuser` |
| `POSTGRES_PASSWORD` | Auto-generated |
| `DATABASE_URL` | Full connection string |

## Set Secrets

```powershell
# Set secret key (required)
nexus secret create --name SECRET_KEY --value "your-random-secret-key"

# Attach secret to deployment
nexus deploy redeploy flashcards --secret-ids <secret-id>
```

## Useful Commands

```powershell
# Status
nexus deploy status flashcards

# Logs
nexus deploy logs flashcards --follow

# Scale
nexus deploy scale flashcards 2

# Stop/Start
nexus deploy stop flashcards
nexus deploy start flashcards

# Redeploy after code changes
nexus deploy redeploy flashcards
```

## Free Tier Limits

- 1 active deployment
- PostgreSQL included (1 instance)
- 3 secrets
- `*.nexusai.run` domain
- No custom domains
- No rollback (upgrade to Pro for $149/mo)
