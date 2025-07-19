# 🧪 Local Testing Guide

## Option 1: k3s (Recommended - Full K8s Experience)

### 1. Install k3s
```bash
# macOS with multipass
brew install multipass
multipass launch --name k3s --cpus 4 --memory 8G --disk 40G

# SSH into VM
multipass shell k3s

# Inside VM, install k3s
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Copy kubeconfig to your local machine
multipass exec k3s sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config-k3s
# Edit the server URL in ~/.kube/config-k3s to use the VM IP
export KUBECONFIG=~/.kube/config-k3s
```

### 2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### 3. Deploy Invisible Platform
```bash
cd deploy

# Generate secrets
./scripts/generate-secrets.sh

# Deploy app-of-apps
kubectl apply -f argocd/apps/app-of-apps.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get admin password
echo "ArgoCD Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"

# Open https://localhost:8080
```

### 4. Monitor Deployment
```bash
# Watch pods come up
watch kubectl get pods -n invisible

# Check Supabase logs
kubectl logs -n invisible statefulset/supabase -f

# Check service status
kubectl get svc -n invisible
```

### 5. Test Services
```bash
# Port forward all services
kubectl port-forward -n invisible svc/supabase 8000:8000 &
kubectl port-forward -n invisible svc/ui-hub 4400:80 &
kubectl port-forward -n invisible svc/ui-chat 4500:80 &
kubectl port-forward -n invisible svc/invisible-api 4300:4300 &
kubectl port-forward -n invisible svc/invisible-schema 8001:8000 &

# Access:
# - Supabase Studio: http://localhost:8000
# - UI Hub: http://localhost:4400
# - UI Chat: http://localhost:4500
# - API: http://localhost:4300/health
# - SQLMesh: http://localhost:8001
```

## Option 2: Docker Desktop K8s (Simpler)

### 1. Enable Kubernetes in Docker Desktop
- Open Docker Desktop → Settings → Kubernetes
- Check "Enable Kubernetes"
- Click "Apply & Restart"

### 2. Deploy
```bash
# Same as above, starting from "Install ArgoCD"
```

## Option 3: Kind (Kubernetes in Docker)

### 1. Install Kind
```bash
brew install kind

# Create cluster
kind create cluster --name invisible --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 8000
    protocol: TCP
  - containerPort: 30001
    hostPort: 4400
    protocol: TCP
  - containerPort: 30002
    hostPort: 4500
    protocol: TCP
EOF
```

### 2. Deploy (same as above)

## 🧪 Quick Smoke Test

Once deployed, run this test script:

```bash
cat > test-deployment.sh <<'EOF'
#!/bin/bash
echo "🧪 Testing Invisible Platform Deployment..."

# Test Supabase
echo -n "Testing Supabase Kong Gateway... "
curl -s http://localhost:8000/auth/v1/health | grep -q "ok" && echo "✅" || echo "❌"

# Test API
echo -n "Testing Invisible API... "
curl -s http://localhost:4300/health | grep -q "UP" && echo "✅" || echo "❌"

# Test UI Hub
echo -n "Testing UI Hub... "
curl -s http://localhost:4400 | grep -q "<title>" && echo "✅" || echo "❌"

# Test UI Chat
echo -n "Testing UI Chat... "
curl -s http://localhost:4500 | grep -q "<title>" && echo "✅" || echo "❌"

# Test Database
echo -n "Testing PostgreSQL... "
kubectl exec -n invisible statefulset/supabase -- docker exec supabase-db-1 pg_isready && echo "✅" || echo "❌"

echo "Done!"
EOF

chmod +x test-deployment.sh
./test-deployment.sh
```

## 🐛 Common Issues

### Supabase not starting
```bash
# Check if docker-in-docker is working
kubectl exec -n invisible supabase-0 -- docker ps

# If not, check logs
kubectl logs -n invisible supabase-0
```

### Services can't connect to Supabase
```bash
# Verify service DNS
kubectl run -n invisible test-pod --image=busybox --rm -it -- nslookup supabase-db
kubectl run -n invisible test-pod --image=busybox --rm -it -- nslookup supabase-kong
```

### Out of resources
```bash
# Check node resources
kubectl top nodes
kubectl top pods -n invisible

# Scale down if needed
kubectl scale --replicas=0 -n invisible deployment/invisible-processor
```

## 🧹 Cleanup

```bash
# k3s with multipass
multipass delete k3s
multipass purge

# Kind
kind delete cluster --name invisible

# Docker Desktop
# Just disable Kubernetes in settings
```