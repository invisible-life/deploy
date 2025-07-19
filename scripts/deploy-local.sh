#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${BLUE}================================${NC}"
echo "${BLUE}Invisible Platform Local Installer${NC}"
echo "${BLUE}================================${NC}"
echo ""

# Detect OS
OS="$(uname -s)"

# Install k3d based on OS
case "$OS" in
    Darwin*)
        echo "${BLUE}Detected macOS${NC}"
        
        # Check if brew is installed
        if ! command -v brew >/dev/null 2>&1; then
            echo "${RED}Homebrew not found. Please install from https://brew.sh${NC}"
            exit 1
        fi
        
        # Install dependencies
        echo "${BLUE}Installing dependencies...${NC}"
        brew list jq &>/dev/null || brew install jq
        brew list k3d &>/dev/null || brew install k3d
        brew list kubectl &>/dev/null || brew install kubectl
        
        # Create k3d cluster if it doesn't exist
        if ! k3d cluster list | grep -q "invisible"; then
            echo "${BLUE}Creating k3d cluster...${NC}"
            k3d cluster create invisible \
                -p "8000:80@loadbalancer" \
                -p "8443:443@loadbalancer" \
                -p "5432:32432@loadbalancer" \
                --agents 2
        else
            echo "${GREEN}k3d cluster 'invisible' already exists${NC}"
        fi
        
        # Set kubeconfig
        k3d kubeconfig merge invisible --kubeconfig-merge-default --kubeconfig-switch-context
        ;;
        
    Linux*)
        echo "${BLUE}Detected Linux${NC}"
        
        # Install k3d
        if ! command -v k3d >/dev/null 2>&1; then
            echo "${BLUE}Installing k3d...${NC}"
            curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
        fi
        
        # Create cluster
        if ! k3d cluster list | grep -q "invisible"; then
            echo "${BLUE}Creating k3d cluster...${NC}"
            k3d cluster create invisible \
                -p "8000:80@loadbalancer" \
                -p "8443:443@loadbalancer" \
                -p "5432:32432@loadbalancer" \
                --agents 2
        fi
        
        k3d kubeconfig merge invisible --kubeconfig-merge-default --kubeconfig-switch-context
        ;;
        
    *)
        echo "${RED}Unsupported OS: $OS${NC}"
        exit 1
        ;;
esac

# Wait for cluster to be ready
echo "${BLUE}Waiting for cluster to be ready...${NC}"
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

# Generate secrets (from current directory)
echo "${BLUE}Generating secrets...${NC}"
if [ -f "./scripts/generate-secrets.sh" ]; then
    ./scripts/generate-secrets.sh
else
    echo "${RED}generate-secrets.sh not found. Make sure you're in the deploy directory${NC}"
    exit 1
fi

# Setup Docker Hub authentication
echo "${BLUE}Setting up Docker Hub authentication...${NC}"
if [ -f "./scripts/setup-docker-auth.sh" ]; then
    ./scripts/setup-docker-auth.sh
else
    echo "${YELLOW}Warning: setup-docker-auth.sh not found. Skipping Docker auth setup.${NC}"
    echo "${YELLOW}You may need to manually configure Docker Hub credentials for private images.${NC}"
fi

# Deploy applications
echo "${BLUE}Deploying Invisible platform...${NC}"
kubectl apply -f argocd/apps/app-of-apps.yaml

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Get Supabase credentials from generated secrets
if [ -f secrets.env ]; then
    DASHBOARD_PASSWORD=$(grep DASHBOARD_PASSWORD secrets.env | cut -d'=' -f2)
    ANON_KEY=$(grep "^ANON_KEY=" secrets.env | cut -d'=' -f2)
fi

# Start port forwards in background
echo "${BLUE}Starting port forwards...${NC}"
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
ARGOCD_PF_PID=$!

# Wait for initial sync
echo "${BLUE}Waiting for initial deployment (this may take 5-10 minutes)...${NC}"
echo "${YELLOW}You can monitor progress at: https://localhost:8080${NC}"
echo "${YELLOW}Username: admin, Password: ${ARGOCD_PASSWORD}${NC}"
sleep 30

# Print success message
echo ""
echo "${GREEN}================================${NC}"
echo "${GREEN}✅ Local Deployment Complete!${NC}"
echo "${GREEN}================================${NC}"
echo ""
echo "${BLUE}Access Points:${NC}"
echo "ArgoCD UI: https://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Supabase Studio: http://localhost:8000"
echo "  Username: supabase"
echo "  Password: ${DASHBOARD_PASSWORD}"
echo ""
echo "UI Hub: http://localhost:8000/hub"
echo "UI Chat: http://localhost:8000/chat"
echo ""
echo "${BLUE}Useful Commands:${NC}"
echo "Check deployment status: kubectl get pods -n invisible"
echo "View logs: kubectl logs -n invisible deployment/invisible-api"
echo "Stop port forward: kill ${ARGOCD_PF_PID}"
echo ""
echo "${BLUE}Additional Port Forwards (if needed):${NC}"
echo "kubectl port-forward -n invisible svc/supabase 8000:8000"
echo "kubectl port-forward -n invisible svc/ui-hub 4400:80"
echo "kubectl port-forward -n invisible svc/ui-chat 4500:80"
echo ""
echo "${YELLOW}Note: Services may take a few minutes to become fully available.${NC}"
echo "${YELLOW}Check ArgoCD UI for real-time deployment status.${NC}"
echo ""
echo "${BLUE}To stop the cluster:${NC}"
echo "k3d cluster delete invisible"