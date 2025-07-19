#!/bin/sh
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${BLUE}================================${NC}"
echo "${BLUE}Invisible Platform Installer${NC}"
echo "${BLUE}================================${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "${YELLOW}This script must be run as root. Re-running with sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Detect OS
OS=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

# Install dependencies based on OS
echo "${BLUE}Installing dependencies...${NC}"
case "$OS" in
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y curl wget git jq openssl
        ;;
    centos|rhel|fedora)
        yum install -y curl wget git jq openssl
        ;;
    *)
        echo "${YELLOW}Unknown OS. Please ensure curl, wget, git, jq, and openssl are installed.${NC}"
        ;;
esac

# Install k3s
if ! command -v k3s >/dev/null 2>&1; then
    echo "${BLUE}Installing k3s...${NC}"
    curl -sfL https://get.k3s.io | sh -
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG=~/.kube/config
else
    echo "${GREEN}k3s already installed${NC}"
fi

# Wait for k3s to be ready
echo "${BLUE}Waiting for k3s to be ready...${NC}"
until kubectl get nodes >/dev/null 2>&1; do
    sleep 2
done
kubectl wait --for=condition=ready node --all --timeout=300s

# Install ArgoCD
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo "${BLUE}Installing ArgoCD...${NC}"
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    echo "${BLUE}Waiting for ArgoCD to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
else
    echo "${GREEN}ArgoCD already installed${NC}"
fi

# Clone repository
echo "${BLUE}Cloning deployment repository...${NC}"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git clone https://github.com/invisible-life/deploy.git
cd deploy

# Generate secrets
echo "${BLUE}Generating secrets...${NC}"
./scripts/generate-secrets.sh

# Deploy applications
echo "${BLUE}Deploying Invisible platform...${NC}"
kubectl apply -f argocd/apps/app-of-apps.yaml

# Get server IP
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "YOUR-SERVER-IP")

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Get Supabase credentials from generated secrets
if [ -f secrets.env ]; then
    DASHBOARD_PASSWORD=$(grep DASHBOARD_PASSWORD secrets.env | cut -d'=' -f2)
    ANON_KEY=$(grep "^ANON_KEY=" secrets.env | cut -d'=' -f2)
fi

# Wait for initial sync
echo "${BLUE}Waiting for initial deployment (this may take 5-10 minutes)...${NC}"
sleep 30

# Print success message
echo ""
echo "${GREEN}================================${NC}"
echo "${GREEN}✅ Deployment Complete!${NC}"
echo "${GREEN}================================${NC}"
echo ""
echo "${BLUE}Access Points:${NC}"
echo "ArgoCD UI: https://${SERVER_IP}:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Supabase Studio: https://${SERVER_IP}:8000"
echo "  Username: supabase"
echo "  Password: ${DASHBOARD_PASSWORD}"
echo ""
echo "UI Hub: https://${SERVER_IP}:4400"
echo "UI Chat: https://${SERVER_IP}:4500"
echo ""
echo "${BLUE}Useful Commands:${NC}"
echo "Check deployment status: kubectl get pods -n invisible"
echo "View ArgoCD locally: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "${YELLOW}Note: Services may take a few minutes to become fully available.${NC}"
echo "${YELLOW}Check ArgoCD UI for real-time deployment status.${NC}"
echo ""
echo "${GREEN}Deployment files saved in: $TEMP_DIR/deploy${NC}"