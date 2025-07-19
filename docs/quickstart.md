# Quick Start Guide

## Prerequisites

1. **Install k3s** (lightweight Kubernetes):
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

3. **Install ArgoCD CLI** (optional):
```bash
brew install argocd  # macOS
# or download from https://github.com/argoproj/argo-cd/releases
```

## Deployment Steps

### 1. Generate Secrets
```bash
./scripts/generate-secrets.sh
```

This creates:
- Kubernetes secrets for Supabase (passwords, JWT tokens)
- Kubernetes secrets for applications
- A local `secrets.env` file (DO NOT COMMIT!)

### 2. Deploy the Platform

Apply the app-of-apps pattern:
```bash
kubectl apply -f argocd/apps/app-of-apps.yaml
```

### 3. Access ArgoCD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
# Username: admin
# Password: (from above command)
```

### 4. Monitor Deployment

In ArgoCD UI:
- Click on `invisible-platform` application
- Watch as all child applications are created and synced
- Each service will show its health status

### 5. Access Services

After deployment completes:

```bash
# Supabase Studio
kubectl port-forward -n invisible svc/supabase-kong 8000:8000
# Access at http://localhost:8000

# UI Hub
kubectl port-forward -n invisible svc/ui-hub 4400:80
# Access at http://localhost:4400

# UI Chat  
kubectl port-forward -n invisible svc/ui-chat 4500:80
# Access at http://localhost:4500
```

## Local Development with k3s

1. **Add local DNS entries** (optional):
```bash
sudo sh -c 'echo "127.0.0.1 api.invisible.local hub.invisible.local chat.invisible.local" >> /etc/hosts'
```

2. **Configure Traefik ingress** (included with k3s):
```bash
kubectl apply -f k8s/overlays/dev/ingress.yaml
```

## Troubleshooting

### Check pod status:
```bash
kubectl get pods -n invisible
```

### View logs:
```bash
kubectl logs -n invisible deployment/invisible-api
```

### Restart a service:
```bash
kubectl rollout restart -n invisible deployment/invisible-api
```

### Delete and redeploy:
```bash
# Delete everything
kubectl delete namespace invisible

# Regenerate secrets and redeploy
./scripts/generate-secrets.sh
kubectl apply -f argocd/apps/app-of-apps.yaml
```