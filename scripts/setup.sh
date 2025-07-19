#!/bin/bash
set -euo pipefail

# This script assumes k3s and ArgoCD are already installed
# It's meant to be run from the cloned repository

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Invisible Platform Setup${NC}"
echo "========================"

# Check prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}kubectl not found. Please install Kubernetes first.${NC}"
    echo "Run: curl -sfL https://get.k3s.io | sh -"
    exit 1
fi

# Check if ArgoCD is installed
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${YELLOW}ArgoCD not installed. Installing...${NC}"
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
fi

# Generate secrets
echo -e "${BLUE}Generating secrets...${NC}"
./scripts/generate-secrets.sh

# Apply ArgoCD applications
echo -e "${BLUE}Deploying applications...${NC}"
kubectl apply -f argocd/apps/app-of-apps.yaml

# Get credentials
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "localhost")
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Access ArgoCD: https://${SERVER_IP}:8080"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"