# Invisible Deploy - ArgoCD GitOps Repository

This repository deploys the Invisible platform using Kubernetes and ArgoCD.

## Production Deployment

Run this single command on your Linux server:

```bash
curl -sfL https://raw.githubusercontent.com/invisible-life/invisible-deploy/main/scripts/deploy.sh | sh -
```

## Local Development (Mac/Linux)

For local testing:

```bash
git clone https://github.com/invisible-life/invisible-deploy.git
cd invisible-deploy
./scripts/deploy-local.sh
```

This script will:
1. Install k3s (lightweight Kubernetes)
2. Install ArgoCD
3. Generate all required secrets
4. Deploy the entire Invisible platform
5. Output access credentials and URLs

## What Gets Deployed

- **Supabase Stack**: PostgreSQL, Auth, Storage, Realtime, Functions
- **Application Services**: API, ETL, Processor, Schema, Operations
- **UI Applications**: Hub (admin) and Chat interfaces
- **Supporting Services**: Ollama (LLM), Traefik (ingress)

## Access Points

After deployment completes (~5-10 minutes), access:

- **ArgoCD UI**: https://YOUR-SERVER-IP:8080 (manage deployments)
- **Supabase Studio**: https://YOUR-SERVER-IP:8000
- **UI Hub**: https://YOUR-SERVER-IP:4400
- **UI Chat**: https://YOUR-SERVER-IP:4500

Credentials will be displayed after installation.

## Repository Structure

```
invisible-deploy/
├── argocd/apps/        # ArgoCD application definitions
├── k8s/                # Kubernetes manifests
│   ├── base/          # Base configurations
│   └── overlays/      # Environment-specific configs
└── scripts/           # Deployment scripts
```

## Manual Deployment

If you need more control:

```bash
# 1. Clone repository
git clone https://github.com/invisible-life/invisible-deploy.git
cd invisible-deploy

# 2. Run setup
./scripts/setup.sh
```

## Updates

To update the platform:
1. Push changes to this repository
2. ArgoCD will automatically sync within 3 minutes
3. Or manually sync in ArgoCD UI

## Troubleshooting

```bash
# Check status
kubectl get pods -n invisible

# View logs
kubectl logs -n invisible deployment/invisible-api

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
```