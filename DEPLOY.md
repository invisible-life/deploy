# 🚀 Deployment Guide

## Prerequisites

1. **Install k3s** (includes Traefik ingress):
```bash
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

2. **Install ArgoCD**:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 🎯 Quick Deploy

### 1. Clone the repo
```bash
git clone https://github.com/invisible-life/deploy.git
cd deploy
```

### 2. Generate secrets
```bash
./scripts/generate-secrets.sh
```

### 3. Deploy everything with ArgoCD
```bash
kubectl apply -f argocd/apps/app-of-apps.yaml
```

### 4. Access ArgoCD UI
```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080
# Username: admin
# Password: (from above)
```

## 🔍 What Gets Deployed

### Infrastructure (Supabase)
- All-in-one Supabase running in Docker-in-Docker
- PostgreSQL, Auth, Storage, Realtime, Functions, etc.
- Accessible at `supabase-kong:8000` internally

### Application Services
- **invisible-api** - Main API (port 4300)
- **invisible-etl** - Platform sync (port 4001)
- **invisible-processor** - AI message processor
- **invisible-schema** - SQLMesh (port 8000)
- **invisible-operations** - License service (port 8081)
- **ollama** - LLM service (port 11434)

### UI Applications
- **ui-hub** - Admin dashboard
- **ui-chat** - Chat interface

## 📡 Access Services

### Option 1: Port Forwarding (Quick)
```bash
# Supabase Studio
kubectl port-forward -n invisible svc/supabase 8000:8000

# UI Hub
kubectl port-forward -n invisible svc/ui-hub 4400:80

# UI Chat
kubectl port-forward -n invisible svc/ui-chat 4500:80
```

### Option 2: Ingress (Production-like)
```bash
# Add to /etc/hosts
127.0.0.1 api.invisible.local hub.invisible.local chat.invisible.local schema.invisible.local

# Apply ingress
kubectl apply -f k8s/overlays/dev/ingress.yaml

# Access:
# - https://api.invisible.local - Supabase
# - https://hub.invisible.local - UI Hub
# - https://chat.invisible.local - UI Chat
# - https://schema.invisible.local - SQLMesh
```

## 🔧 Troubleshooting

### Check pod status
```bash
kubectl get pods -n invisible
```

### View logs
```bash
# Supabase (all services)
kubectl logs -n invisible statefulset/supabase

# Specific service
kubectl logs -n invisible deployment/invisible-api
```

### Supabase not starting?
```bash
# Check the init logs
kubectl logs -n invisible statefulset/supabase -c supabase

# Exec into the container
kubectl exec -it -n invisible supabase-0 -- sh
cd /supabase
docker compose ps
docker compose logs
```

### Restart a service
```bash
kubectl rollout restart -n invisible deployment/invisible-api
```

## 🎨 Customization

### Update environment variables
1. Edit the appropriate ConfigMap/Secret
2. Restart the affected pods

### Change resource limits
1. Edit `k8s/overlays/dev/kustomization.yaml`
2. Push changes
3. ArgoCD will auto-sync

### Add new environment
1. Create `k8s/overlays/YOUR_ENV/`
2. Copy from dev and customize
3. Create new ArgoCD app pointing to it

## 🧹 Cleanup

### Delete everything
```bash
# Remove ArgoCD apps
kubectl delete -f argocd/apps/app-of-apps.yaml

# Delete namespace (removes all resources)
kubectl delete namespace invisible

# Uninstall ArgoCD
kubectl delete namespace argocd
```

## 🎉 Success!

Once everything is green in ArgoCD:
1. Supabase Studio: http://localhost:8000
2. UI Hub: http://localhost:4400
3. UI Chat: http://localhost:4500

Default Supabase credentials are shown after running `generate-secrets.sh`